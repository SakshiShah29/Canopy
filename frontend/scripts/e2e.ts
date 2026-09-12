/**
 * The Canopy end-to-end runner: all fifteen beats, in order, on live Sepolia, from one command.
 *
 * This is both the acceptance test for Day 5 and the rehearsal for the video. It is the thing that
 * proves the flow before any of it is on screen, so it asserts outcomes rather than printing them —
 * including the **four beats that must revert** (8, 9, 12, 15) and the one that must still succeed
 * after the lapse (14). A runner that only checks the happy path would pass against a build with no
 * enforcement at all.
 *
 *   npx tsx scripts/e2e.ts [--reset-broker] [--yes]
 *
 * Environment:
 *   SEPOLIA_RPC_URL       an archive-capable endpoint is not required
 *   DEPLOYER_PRIVATE_KEY  holds ROLE_REGISTRAR on the registries and owns the adapters
 *   ALICE_PRIVATE_KEY     retail investor under acme/prime      — must sign her own swap
 *   MM_PRIVATE_KEY        market maker under acme/prime         — must sign liquidity calls
 *   BOB_PRIVATE_KEY       retail investor under zenith/prime    — beats 10 and 13
 *   REJECT_WALLET         an address CRE must refuse (beat 2). No key needed: filed on its behalf.
 *   BORDERLINE_WALLET     passes under prime, fails under delta (beat 3). No key needed.
 *
 * The three investor keys are not optional. `hierarchy.json` ships with empty wallets, which the
 * deploy script turns into deterministic placeholders — those cannot sign, so any wallet that has
 * to transact on camera needs a real key here and a real address in the config.
 */

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

import {
  createPublicClient,
  createWalletClient,
  http,
  keccak256,
  parseEther,
  toHex,
  type Account,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'

import {
  permissionsAdapterAbi,
  registryAbi,
  registryWriteAbi,
} from '../lib/abis'
import {
  addLiquidity,
  apply,
  balanceOf,
  eligibilityOf,
  ensureApprovals,
  hierarchyOf,
  issuers,
  issuersOf,
  labelId,
  removeLiquidity,
  swap,
  type Canopy,
  type Eligibility,
} from '../lib/canopy'
import { brokerRegistry, coreAddresses, issuerAddresses } from '../lib/addresses'

// ── configuration ────────────────────────────────────────────────

const ACME = 'acme'
const ZENITH = 'zenith'
const PRIME = 'prime'
const DELTA = 'delta'

const SWAP_AMOUNT = parseEther('0.0005')
const LIQUIDITY_AMOUNT = parseEther('0.002')
const LIQUIDITY_UNITS = 1_000_000_000n

/** How long to wait for the CRE workflow to deliver a verdict before calling a beat failed. */
const CRE_TIMEOUT_MS = 5 * 60 * 1000
const CRE_POLL_MS = 5_000

/** Beat 11 waits for a real expiry. Past this the broker TTL was clearly not shortened. */
const LAPSE_TIMEOUT_MS = 20 * 60 * 1000

const args = new Set(process.argv.slice(2))
const RESET_BROKER = args.has('--reset-broker')

// ── transcript ───────────────────────────────────────────────────

const GREEN = '\x1b[32m'
const RED = '\x1b[31m'
const DIM = '\x1b[2m'
const BOLD = '\x1b[1m'
const RESET = '\x1b[0m'

let failures = 0
const started = Date.now()

function heading(text: string) {
  console.log(`\n${BOLD}${text}${RESET}`)
}

function note(text: string) {
  console.log(`${DIM}    ${text}${RESET}`)
}

async function beat(n: number, title: string, fn: () => Promise<void>) {
  const label = `${BOLD}beat ${String(n).padStart(2)}${RESET}  ${title}`
  const t0 = Date.now()
  try {
    await fn()
    console.log(`${GREEN}  ok  ${RESET}${label} ${DIM}(${((Date.now() - t0) / 1000).toFixed(1)}s)${RESET}`)
  } catch (error) {
    failures++
    console.log(`${RED}  FAIL${RESET}${label}`)
    console.log(`${RED}        ${(error as Error).message}${RESET}`)
  }
}

/** The assertion that carries the argument: the chain refusing, not our UI greying out. */
async function mustRevert(what: string, fn: () => Promise<unknown>) {
  try {
    await fn()
  } catch {
    return // the refusal is the pass
  }
  throw new Error(`${what} was expected to revert, and did not`)
}

function assertFlags(actual: Eligibility, expected: Eligibility['tier'], who: string) {
  if (actual.tier !== expected) {
    throw new Error(`${who}: expected ${expected}, got ${actual.tier} (raw 0x${actual.raw.toString(16)})`)
  }
}

// ── setup ────────────────────────────────────────────────────────

function requireEnv(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`${name} is not set — see the header of this file`)
  return value
}

/**
 * Assigned by `initialise()`, not at module scope.
 *
 * A missing key or an undeployed address book has to surface as one legible line — an operator
 * running this at 2am needs to be told which variable is unset. Building any of it during module
 * evaluation puts the throw outside `main().catch()`, where it escapes as a raw Node stack trace
 * about `wrapModuleLoad` with the real message buried.
 */
let book: Record<string, unknown>
let publicClient: PublicClient
let deployer: Account
let alice: Account
let mm: Account
let bob: Account
let asDeployer: Canopy
let core: ReturnType<typeof coreAddresses>

const REJECT_WALLET = (process.env.REJECT_WALLET ?? '') as Address
const BORDERLINE_WALLET = (process.env.BORDERLINE_WALLET ?? '') as Address

function initialise() {
  const here = dirname(fileURLToPath(import.meta.url))
  const bookPath = resolve(here, '../../deployments.json')

  try {
    book = JSON.parse(readFileSync(bookPath, 'utf8'))
  } catch {
    throw new Error(`could not read ${bookPath} — run the deploy scripts first`)
  }

  publicClient = createPublicClient({
    chain: sepolia,
    transport: http(process.env.SEPOLIA_RPC_URL ?? 'https://ethereum-sepolia-rpc.publicnode.com'),
  }) as PublicClient

  deployer = privateKeyToAccount(requireEnv('DEPLOYER_PRIVATE_KEY') as Hex)
  alice = privateKeyToAccount(requireEnv('ALICE_PRIVATE_KEY') as Hex)
  mm = privateKeyToAccount(requireEnv('MM_PRIVATE_KEY') as Hex)
  bob = privateKeyToAccount(requireEnv('BOB_PRIVATE_KEY') as Hex)

  asDeployer = ctxFor(deployer)
  core = coreAddresses(book)
}

function walletFor(account: Account): WalletClient {
  return createWalletClient({ account, chain: sepolia, transport: http(process.env.SEPOLIA_RPC_URL) })
}

function ctxFor(account: Account): Canopy {
  return { book, publicClient, walletClient: walletFor(account) }
}

// ── helpers ──────────────────────────────────────────────────────

async function waitForEligibility(wallet: Address, issuer: string, want: Eligibility['tier']): Promise<void> {
  const deadline = Date.now() + CRE_TIMEOUT_MS
  let last: Eligibility['tier'] = 'none'

  while (Date.now() < deadline) {
    const current = await eligibilityOf(asDeployer, wallet, issuer)
    last = current.tier
    if (current.tier === want) return
    await sleep(CRE_POLL_MS)
  }

  throw new Error(
    `CRE did not produce ${want} for ${wallet} under ${issuer} within ${CRE_TIMEOUT_MS / 1000}s ` +
      `(last seen: ${last}). Check the workflow logs and that MintAttestor has ROLE_REGISTRAR.`,
  )
}

/** Beat 2 and 3 assert a *non-event*: no subname appears. Waiting the full CRE timeout for that
 *  would take five minutes each, so this waits a shorter, fixed window and asserts nothing arrived. */
async function assertStaysIneligible(wallet: Address, issuer: string, seconds = 90) {
  const deadline = Date.now() + seconds * 1000
  while (Date.now() < deadline) {
    const current = await eligibilityOf(asDeployer, wallet, issuer)
    if (current.tier !== 'none') {
      throw new Error(`${wallet} became ${current.tier} under ${issuer}, but CRE was expected to reject`)
    }
    await sleep(CRE_POLL_MS)
  }
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms))
}

async function brokerExpiry(issuer: string, broker: string): Promise<bigint> {
  const issuerReg = issuerAddresses(book, issuer).registry
  const state = (await publicClient.readContract({
    address: issuerReg,
    abi: registryAbi,
    functionName: 'getState',
    args: [BigInt(labelId(broker))],
  })) as { expiry: bigint }
  return state.expiry
}

/** `LibLabel.id` — keccak of the label with the low 32 bits cleared for the version counter. */
function localLabelId(label: string): Hex {
  const hash = BigInt(keccak256(toHex(label)))
  return `0x${(hash & ~0xffffffffn).toString(16).padStart(64, '0')}` as Hex
}

// ── ABIs for new-feature verification ───────────────────────────

const mintAttestorReadAbi = [
  { type: 'function', name: 'ceilingOf', stateMutability: 'view', inputs: [{ name: 'parentRegistry', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'owner', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
] as const

const resolverTextAbi = [
  { type: 'function', name: 'text', stateMutability: 'view', inputs: [{ name: 'node', type: 'bytes32' }, { name: 'key', type: 'string' }], outputs: [{ type: 'string' }] },
] as const

// Role constants from CanopyRoles.sol
const ROLE_ELIGIBLE_SWAP = 1n << 64n
const ROLE_ELIGIBLE_LIQUIDITY = 1n << 68n

/** ENS namehash for "eth" */
const ETH_NAMEHASH = '0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae' as Hex

/** Compute namehash for a broker path like "acme/prime" → namehash("prime.acme.canopy.eth") */
function computeBrokerNode(brokerPath: string): Hex {
  const canopyLabel = keccak256(toHex('canopy'))
  let node = keccak256((`0x${ETH_NAMEHASH.slice(2)}${canopyLabel.slice(2)}`) as Hex)

  const segments = brokerPath.split('/')
  for (const segment of segments) {
    const lh = keccak256(toHex(segment))
    node = keccak256((`0x${node.slice(2)}${lh.slice(2)}`) as Hex)
  }
  return node
}

/**
 * The eligibility matrix — wallet × issuer × flag. Printed before and after the lapse.
 *
 * This table is the clearest single artifact the project produces: beats 9, 10 and 13 are all
 * "this cell is filled and that one is not", and reading it beside the second copy is the entire
 * containment argument without a word of narration.
 */
async function printMatrix(title: string) {
  const labels = issuers(asDeployer)
  const people: [string, Address][] = [
    ['alice', alice.address],
    ['mm', mm.address],
    ['bob', bob.address],
  ]

  heading(title)
  console.log(`    ${'wallet'.padEnd(10)}${labels.map((l) => l.padEnd(14)).join('')}`)
  for (const [name, address] of people) {
    const row = await issuersOf(asDeployer, address)
    const cells = labels.map((l) => {
      const tier = row[l].tier
      const text = tier === 'none' ? '—' : tier === 'retail' ? 'swap' : 'swap+liq'
      const colour = tier === 'none' ? DIM : GREEN
      return `${colour}${text.padEnd(14)}${RESET}`
    })
    console.log(`    ${name.padEnd(10)}${cells.join('')}`)
  }
}

// ── the run ──────────────────────────────────────────────────────

async function main() {
  initialise()

  heading('Canopy end-to-end — fifteen beats on Sepolia')
  note(`deployer  ${deployer.address}`)
  note(`alice     ${alice.address}`)
  note(`mm        ${mm.address}`)
  note(`bob       ${bob.address}`)
  note(`issuers   ${issuers(asDeployer).join(', ')}`)

  const acme = issuerAddresses(book, ACME)
  const zenith = issuerAddresses(book, ZENITH)
  const acmePrime = brokerRegistry(book, ACME, PRIME)

  if (RESET_BROKER) {
    note('--reset-broker: re-arm acme/prime with a short TTL before running, via')
    note('  forge script script/DeployIssuerHierarchy.s.sol --sig "resetBroker(string,string)" acme prime')
  }

  // ── beats 1-4: the CRE mint path ───────────────────────────────

  await beat(1, 'alice applies to Acme through prime → APPROVE → subname minted', async () => {
    const before = await eligibilityOf(asDeployer, alice.address, ACME)
    if (before.tier !== 'none') {
      note('alice is already eligible — treating beat 1 as satisfied by a previous run')
      return
    }
    const application = await apply(ctxFor(alice), {
      wallet: alice.address,
      issuer: ACME,
      broker: PRIME,
      label: 'alice',
      tier: 0,
    })
    note(`brokerPath derived on-chain: ${application.brokerPath}`)
    await waitForEligibility(alice.address, ACME, 'retail')
  })

  await beat(2, 'a second applicant → REJECT → no subname, no access', async () => {
    if (!REJECT_WALLET) throw new Error('REJECT_WALLET is not set')
    await apply(asDeployer, {
      wallet: REJECT_WALLET,
      issuer: ACME,
      broker: PRIME,
      label: 'rejected',
      tier: 0,
      account: deployer,
    })
    await assertStaysIneligible(REJECT_WALLET, ACME)
  })

  await beat(3, 'borderline applicant passes under prime, fails under delta', async () => {
    if (!BORDERLINE_WALLET) throw new Error('BORDERLINE_WALLET is not set')
    await apply(asDeployer, {
      wallet: BORDERLINE_WALLET,
      issuer: ACME,
      broker: DELTA,
      label: 'borderline',
      tier: 0,
      account: deployer,
    })
    await assertStaysIneligible(BORDERLINE_WALLET, ACME)
    note('same issuer, same engine, stricter rulebook — per-broker criteria are a mechanism, not a claim')
  })

  await beat(4, 'mm applies → APPROVE with both role bits', async () => {
    const before = await eligibilityOf(asDeployer, mm.address, ACME)
    if (before.tier === 'marketMaker') {
      note('mm is already a market maker — satisfied by a previous run')
      return
    }
    await apply(ctxFor(mm), { wallet: mm.address, issuer: ACME, broker: PRIME, label: 'mm', tier: 1 })
    await waitForEligibility(mm.address, ACME, 'marketMaker')
  })

  // ── beat 5: one transaction turns the pool hierarchical ────────

  await beat(5, 'acmeAdapter.updateAllowListChecker(acmeChecker)', async () => {
    const current = (await publicClient.readContract({
      address: acme.adapter,
      abi: permissionsAdapterAbi,
      functionName: 'allowListChecker',
    })) as Address

    if (current.toLowerCase() === acme.checker.toLowerCase()) {
      note('already pointed at the hierarchical checker')
      return
    }

    const hash = await walletFor(deployer).writeContract({
      address: acme.adapter,
      abi: permissionsAdapterAbi,
      functionName: 'updateAllowListChecker',
      args: [acme.checker],
      account: deployer,
      chain: sepolia,
    })
    await publicClient.waitForTransactionReceipt({ hash })
    note(`flat checker → ENSAllowlistChecker in one call: ${hash}`)
  })

  await printMatrix('eligibility before the lapse')

  // ── beats 6-8: the two tiers ───────────────────────────────────

  let positionTokenId: bigint | null = null

  await beat(6, 'mm adds liquidity on Acme (caller == recipient) → succeeds', async () => {
    await ensureApprovals(ctxFor(mm), { account: mm, issuer: ACME })
    const nextId = (await publicClient.readContract({
      address: core.positionManager,
      abi: [{ type: 'function', name: 'nextTokenId', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] }],
      functionName: 'nextTokenId',
    })) as bigint
    const hash = await addLiquidity(ctxFor(mm), {
      account: mm,
      issuer: ACME,
      amountEth: LIQUIDITY_AMOUNT,
      liquidity: LIQUIDITY_UNITS,
    })
    await publicClient.waitForTransactionReceipt({ hash })
    positionTokenId = nextId
    note(`position #${nextId}`)
  })

  await beat(7, 'alice swaps on Acme → succeeds', async () => {
    const before = await balanceOf(asDeployer, alice.address, ACME)
    const hash = await swap(ctxFor(alice), { account: alice, issuer: ACME, amountIn: SWAP_AMOUNT })
    await publicClient.waitForTransactionReceipt({ hash })
    const after = await balanceOf(asDeployer, alice.address, ACME)
    if (after <= before) throw new Error('swap settled but the balance did not increase')
    note(`received ${after - before} units`)
  })

  await beat(8, 'alice attempts addLiquidity → REVERTS (the tier split)', async () => {
    await mustRevert('alice addLiquidity', () =>
      addLiquidity(ctxFor(alice), {
        account: alice,
        issuer: ACME,
        amountEth: LIQUIDITY_AMOUNT,
        liquidity: LIQUIDITY_UNITS,
      }),
    )
    note('two successes prove nothing about tiers — the refusal is the proof')
  })

  // ── beats 9-10: cross-issuer isolation ─────────────────────────

  await beat(9, "alice attempts a swap on Zenith's pool → REVERTS (isolation)", async () => {
    assertFlags(await eligibilityOf(asDeployer, alice.address, ZENITH), 'none', 'alice under zenith')
    await mustRevert('alice swapping on zenith', () =>
      swap(ctxFor(alice), { account: alice, issuer: ZENITH, amountIn: SWAP_AMOUNT }),
    )
    note('eligibility is issuer-scoped, and the walk must pass through the issuer to prove it')
  })

  await beat(10, 'bob, onboarded by prime under Zenith, swaps on Zenith → succeeds', async () => {
    assertFlags(await eligibilityOf(asDeployer, bob.address, ZENITH), 'retail', 'bob under zenith')
    await ensureApprovals(ctxFor(bob), { account: bob, issuer: ZENITH })
    const hash = await swap(ctxFor(bob), { account: bob, issuer: ZENITH, amountIn: SWAP_AMOUNT })
    await publicClient.waitForTransactionReceipt({ hash })
    note('one broker, two issuers, two independent books')
  })

  // ── beat 11: the lapse ─────────────────────────────────────────

  await beat(11, "Acme's prime lapses — no transaction sent", async () => {
    const expiry = await brokerExpiry(ACME, PRIME)
    const deadline = Date.now() + LAPSE_TIMEOUT_MS

    while (Date.now() < deadline) {
      const block = await publicClient.getBlock()
      const remaining = Number(expiry - block.timestamp)
      if (remaining <= 0) {
        note('acme/prime has expired. Nothing was sent to make that happen.')
        return
      }
      process.stdout.write(`\r${DIM}    acme/prime expires in ${remaining}s${RESET}   `)
      await sleep(5_000)
    }
    process.stdout.write('\n')
    throw new Error(
      `acme/prime still has ${expiry} in the future after ${LAPSE_TIMEOUT_MS / 60000} minutes. ` +
        'Re-arm it with a short TTL: BROKER_TTL=300 and --sig "resetBroker(string,string)" acme prime',
    )
  })

  // ── beats 12-14: what the lapse did, and did not, do ───────────

  await beat(12, 'alice and mm both attempt swaps on Acme → BOTH revert', async () => {
    assertFlags(await eligibilityOf(asDeployer, alice.address, ACME), 'none', 'alice after the lapse')
    assertFlags(await eligibilityOf(asDeployer, mm.address, ACME), 'none', 'mm after the lapse')

    await mustRevert('alice swapping after the lapse', () =>
      swap(ctxFor(alice), { account: alice, issuer: ACME, amountIn: SWAP_AMOUNT }),
    )
    await mustRevert('mm swapping after the lapse', () =>
      swap(ctxFor(mm), { account: mm, issuer: ACME, amountIn: SWAP_AMOUNT }),
    )

    // The names themselves are untouched — only the broker above them expired.
    const tree = await hierarchyOf(asDeployer, alice.address, ACME)
    const leaf = tree.levels[0]
    if (leaf && !leaf.alive) throw new Error("alice's own name expired; the cascade should come from the broker")
    note("both cut off in the same block, and alice's own name is still perfectly valid")
  })

  await beat(13, 'bob swaps on Zenith → still succeeds (containment)', async () => {
    assertFlags(await eligibilityOf(asDeployer, bob.address, ZENITH), 'retail', 'bob after acme/prime lapsed')
    const hash = await swap(ctxFor(bob), { account: bob, issuer: ZENITH, amountIn: SWAP_AMOUNT })
    await publicClient.waitForTransactionReceipt({ hash })
    note('one issuer dropped one broker; the same broker\'s other book is untouched')
  })

  await beat(14, 'mm removes liquidity → succeeds (not frozen)', async () => {
    if (positionTokenId === null) {
      note('no position was minted this run — skipping, but beat 14 needs one to mean anything')
      return
    }
    const hash = await removeLiquidity(ctxFor(mm), { account: mm, issuer: ACME, tokenId: positionTokenId })
    await publicClient.waitForTransactionReceipt({ hash })
    note('eligibility gates entry, not exit — exposure can always be unwound')
  })

  await printMatrix('eligibility after the lapse')

  // ── beat 15: the name changes hands ────────────────────────────

  await beat(15, 'the name is re-registered to another registry → its investors stay dead', async () => {
    // NOTE: this is *not* the spec's wording, which says "Acme re-registers prime". Reinstating the
    // same registry legitimately restores the book — only Acme holds ROLE_REGISTRAR, so that is
    // Acme's deliberate act, and `test_reinstatingABrokerRestoresItsBook` asserts it. The claim that
    // survives is this one: a *different* registry taking the freed name inherits nothing.
    const takeover = brokerRegistry(book, ACME, DELTA)
    const farFuture = BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 3600)

    const hash = await walletFor(deployer).writeContract({
      address: acme.registry,
      abi: registryWriteAbi,
      functionName: 'register',
      args: [PRIME, deployer.address, takeover, '0x0000000000000000000000000000000000000000', 0n, farFuture],
      account: deployer,
      chain: sepolia,
    })
    await publicClient.waitForTransactionReceipt({ hash })

    assertFlags(await eligibilityOf(asDeployer, alice.address, ACME), 'none', 'alice after the takeover')
    assertFlags(await eligibilityOf(asDeployer, mm.address, ACME), 'none', 'mm after the takeover')
    note('the incoming broker inherits the name, not the book — version-stamped resources')

    await mustRevert('alice swapping after the takeover', () =>
      swap(ctxFor(alice), { account: alice, issuer: ACME, amountIn: SWAP_AMOUNT }),
    )
  })

  // ── verdict ────────────────────────────────────────────────────

  const elapsed = ((Date.now() - started) / 1000).toFixed(0)
  heading(failures === 0 ? `${GREEN}all fifteen beats passed${RESET} (${elapsed}s)` : `${RED}${failures} beat(s) failed${RESET} (${elapsed}s)`)

  if (failures > 0) {
    console.log(`${DIM}    Re-run with --reset-broker after re-arming acme/prime.${RESET}`)
    process.exit(1)
  }

  console.log(`${DIM}    acme/prime now points at the takeover registry. Re-arm before the next run:${RESET}`)
  console.log(`${DIM}      forge script script/DeployIssuerHierarchy.s.sol --sig "resetBroker(string,string)" acme prime${RESET}`)
}

main().catch((error) => {
  console.error(`\n${RED}runner aborted:${RESET} ${(error as Error).message}`)
  process.exit(1)
})
