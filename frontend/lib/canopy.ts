import type { Account, Address, Hex, PublicClient, WalletClient } from 'viem'
import {
  decodeEventLog,
  encodeAbiParameters,
  encodePacked,
  keccak256,
  maxUint128,
  maxUint256,
  parseAbiParameters,
  toHex,
} from 'viem'

import {
  applicationContractAbi,
  checkerAbi,
  erc20Abi,
  permit2Abi,
  positionManagerAbi,
  registryAbi,
  universalRouterAbi,
} from './abis'
import {
  PERMIT2,
  type AddressBook,
  type IssuerAddresses,
  brokerRegistry,
  coreAddresses,
  issuerAddresses,
  knownIssuers,
} from './addresses'

/**
 * The one place that knows how to call Canopy. Plain viem, no React — the console imports it and
 * so does `scripts/e2e.ts`, and the runner is the thing that proves it works before any of it is
 * on screen.
 *
 * **Every function takes an issuer.** There is one adapter, one pool, one token and one checker per
 * issuer, so a call without one is ambiguous — and the ambiguity would resolve silently to whichever
 * issuer happens to be first in the address book, which is the worst kind of bug to find on camera.
 */

// ── permission flags ─────────────────────────────────────────────

export const SWAP_ALLOWED = 0x0001
export const LIQUIDITY_ALLOWED = 0x0002

export type Eligibility = {
  raw: number
  canSwap: boolean
  canProvideLiquidity: boolean
  /** 'none' | 'retail' | 'marketMaker' — what the two badges show. */
  tier: 'none' | 'retail' | 'marketMaker'
}

function readFlags(raw: Hex): Eligibility {
  const value = Number(BigInt(raw))
  const canSwap = (value & SWAP_ALLOWED) !== 0
  const canProvideLiquidity = (value & LIQUIDITY_ALLOWED) !== 0
  return {
    raw: value,
    canSwap,
    canProvideLiquidity,
    tier: canProvideLiquidity ? 'marketMaker' : canSwap ? 'retail' : 'none',
  }
}

// ── context ──────────────────────────────────────────────────────

export type Canopy = {
  book: AddressBook
  publicClient: PublicClient
  walletClient?: WalletClient
}

export function issuers(ctx: Canopy): string[] {
  return knownIssuers(ctx.book)
}

function issuerOf(ctx: Canopy, issuer: string): IssuerAddresses {
  return issuerAddresses(ctx.book, issuer)
}

function requireWallet(ctx: Canopy): WalletClient {
  if (!ctx.walletClient) throw new Error('this call writes to the chain and needs a walletClient')
  return ctx.walletClient
}

const DEADLINE_WINDOW = 3600n

function deadline(): bigint {
  return BigInt(Math.floor(Date.now() / 1000)) + DEADLINE_WINDOW
}

// ── beats 1-4: applying ──────────────────────────────────────────

export type Tier = 0 | 1

export type Application = {
  hash: Hex
  applicationId: Hex
  wallet: Address
  issuer: Address
  broker: Address
  brokerPath: string
  label: string
  requestedTier: number
}

/**
 * Submit an eligibility application. Emits `ApplicationSubmitted`, which the CRE workflow triggers
 * on; nothing is granted here.
 *
 * `broker` is the broker's *label* under this issuer (`"prime"`), not an address — the same label
 * under two issuers is two different registries, and passing an address invites using the wrong one.
 *
 * `wallet` may be an address the caller does not control, which routes through `submitApplicationFor`.
 * The demo needs that for wallets we hold no keys to — a sanctioned address, an address too new to
 * pass the age rule — and those have to be real addresses with real history or the screening step
 * proves nothing. When `wallet` is the signer, the stricter `submitApplication` is used instead.
 */
export async function apply(
  ctx: Canopy,
  args: { wallet: Address; issuer: string; broker: string; label: string; tier: Tier; account?: Account | Address },
): Promise<Application> {
  const wallet = requireWallet(ctx)
  const core = coreAddresses(ctx.book)
  const broker = brokerRegistry(ctx.book, args.issuer, args.broker)

  const account = args.account ?? wallet.account
  if (!account) throw new Error('apply() needs an account')

  const signer = typeof account === 'string' ? account : account.address
  const onBehalf = signer.toLowerCase() !== args.wallet.toLowerCase()

  const hash = await wallet.writeContract({
    address: core.applicationContract,
    abi: applicationContractAbi,
    functionName: onBehalf ? 'submitApplicationFor' : 'submitApplication',
    args: onBehalf
      ? [args.wallet, broker, args.label, args.tier]
      : ([broker, args.label, args.tier] as never),
    account,
    chain: wallet.chain,
  })

  const receipt = await ctx.publicClient.waitForTransactionReceipt({ hash })

  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== core.applicationContract.toLowerCase()) continue
    try {
      const decoded = decodeEventLog({ abi: applicationContractAbi, data: log.data, topics: log.topics })
      if (decoded.eventName !== 'ApplicationSubmitted') continue
      const a = decoded.args as unknown as Omit<Application, 'hash'>
      return { hash, ...a }
    } catch {
      // Not our event shape; keep looking.
    }
  }

  throw new Error('ApplicationSubmitted not found in the receipt — did the application revert?')
}

// ── the badges ───────────────────────────────────────────────────

/** What `issuer`'s checker says about `wallet`, against `issuer`'s own pool token. */
export async function eligibilityOf(ctx: Canopy, wallet: Address, issuer: string): Promise<Eligibility> {
  const { checker, underlying } = issuerOf(ctx, issuer)
  const raw = await ctx.publicClient.readContract({
    address: checker,
    abi: checkerAbi,
    functionName: 'checkAllowlist',
    args: [wallet, underlying],
  })
  return readFlags(raw as Hex)
}

/**
 * Every issuer this wallet is eligible under. Beat 9 is a wallet that is good for one issuer's pool
 * and refused by another's, so the console needs the whole row, not a single answer.
 */
export async function issuersOf(ctx: Canopy, wallet: Address): Promise<Record<string, Eligibility>> {
  const labels = issuers(ctx)
  const results = await Promise.all(labels.map((label) => eligibilityOf(ctx, wallet, label)))
  return Object.fromEntries(labels.map((label, i) => [label, results[i]]))
}

// ── the hierarchy behind a badge ─────────────────────────────────

export type HierarchyLevel = {
  registry: Address
  /** The leaf's own label is not recoverable from chain state — only its hash is stored. */
  label: string | null
  labelhash: bigint
  expiry: bigint
  status: 'available' | 'reserved' | 'registered'
  alive: boolean
  /** False when the parent no longer delegates this label to this registry. */
  confirmedByParent: boolean
}

export type Hierarchy = {
  levels: HierarchyLevel[]
  reachesPlatform: boolean
  passesThroughIssuer: boolean
  eligible: Eligibility
}

const STATUS = ['available', 'reserved', 'registered'] as const
const MAX_HOPS = 8

/**
 * Walk leaf → broker → issuer → platform, with each level's expiry, exactly as
 * `ENSAllowlistChecker._ancestorsAlive` does.
 *
 * It reproduces all three of the checker's conditions rather than only reading expiries, because a
 * console that shows a tree the checker does not believe is worse than no console: it would display
 * a healthy hierarchy next to a refused swap and send you debugging the pool.
 */
export async function hierarchyOf(ctx: Canopy, wallet: Address, issuer: string): Promise<Hierarchy> {
  const { checker, registry: issuerRegistry } = issuerOf(ctx, issuer)
  const core = coreAddresses(ctx.book)

  const [leafRegistry, leafLabelhash] = (await ctx.publicClient.readContract({
    address: checker,
    abi: checkerAbi,
    functionName: 'leafOf',
    args: [wallet],
  })) as [Address, bigint]

  const eligible = await eligibilityOf(ctx, wallet, issuer)

  if (leafRegistry === '0x0000000000000000000000000000000000000000') {
    return { levels: [], reachesPlatform: false, passesThroughIssuer: false, eligible }
  }

  const levels: HierarchyLevel[] = []
  let current = leafRegistry
  let labelhash = leafLabelhash
  let label: string | null = null
  let passesThroughIssuer = current.toLowerCase() === issuerRegistry.toLowerCase()
  let reachesPlatform = false

  for (let hop = 0; hop <= MAX_HOPS; hop++) {
    const state = (await ctx.publicClient.readContract({
      address: current,
      abi: registryAbi,
      functionName: 'getState',
      args: [labelhash],
    })) as { status: number; expiry: bigint; latestOwner: Address; tokenId: bigint; resource: bigint }

    // The leaf's state lives in its own registry; every level above is read from its parent, so
    // the parent lookup happens after recording this level.
    const [parent, parentLabel] = (await ctx.publicClient.readContract({
      address: current,
      abi: registryAbi,
      functionName: 'getParent',
    })) as [Address, string]

    let confirmedByParent = false
    if (parent !== '0x0000000000000000000000000000000000000000') {
      const delegated = (await ctx.publicClient.readContract({
        address: parent,
        abi: registryAbi,
        functionName: 'getSubregistry',
        args: [parentLabel],
      })) as Address
      confirmedByParent = delegated.toLowerCase() === current.toLowerCase()
    }

    levels.push({
      registry: current,
      label,
      labelhash,
      expiry: state.expiry,
      status: STATUS[state.status] ?? 'available',
      alive: state.status === 2 && state.expiry > BigInt(Math.floor(Date.now() / 1000)),
      confirmedByParent,
    })

    if (parent.toLowerCase() === core.platformRegistry.toLowerCase()) {
      reachesPlatform = true
      break
    }
    if (parent === '0x0000000000000000000000000000000000000000') break

    if (parent.toLowerCase() === issuerRegistry.toLowerCase()) passesThroughIssuer = true

    // Step up: the parent's own name is the label the child claimed.
    labelhash = BigInt(labelId(parentLabel))
    label = parentLabel
    current = parent
  }

  return { levels, reachesPlatform, passesThroughIssuer, eligible }
}

/** `LibLabel.id` is keccak256 of the label with the low 32 bits cleared for the version counter. */
export function labelId(label: string): Hex {
  const hash = BigInt(keccak256(toHex(label)))
  return `0x${(hash & ~0xffffffffn).toString(16).padStart(64, '0')}` as Hex
}

// ── beat 7: swapping ─────────────────────────────────────────────

const V4_SWAP_COMMAND: Hex = '0x10'

const ACTION = {
  DECREASE_LIQUIDITY: 0x01,
  MINT_POSITION: 0x02,
  BURN_POSITION: 0x03,
  SWAP_EXACT_IN_SINGLE: 0x06,
  SETTLE_ALL: 0x0c,
  SETTLE_PAIR: 0x0d,
  TAKE_ALL: 0x0f,
  TAKE_PAIR: 0x11,
} as const

const NATIVE: Address = '0x0000000000000000000000000000000000000000'

function poolKeyOf(a: IssuerAddresses) {
  // currency0 is native ETH, currency1 is the adapter. Sorted numerically, and the zero address
  // always sorts first, so this ordering is fixed for every Canopy pool.
  return {
    currency0: NATIVE,
    currency1: a.adapter,
    fee: a.poolFee,
    tickSpacing: a.poolTickSpacing,
    hooks: a.hooks,
  } as const
}

const POOL_KEY_PARAMS = parseAbiParameters(
  '(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)',
)

/**
 * Swap ETH into the issuer's permissioned token.
 *
 * The router calls `isAllowed` on both `_pay` and `_take`, so an ineligible wallet reverts here
 * rather than receiving anything — beats 9 and 12 are this function reverting, and the runner
 * asserts the revert rather than the success.
 */
export async function swap(
  ctx: Canopy,
  args: { account: Account | Address; issuer: string; amountIn: bigint; minOut?: bigint },
): Promise<Hex> {
  const wallet = requireWallet(ctx)
  const core = coreAddresses(ctx.book)
  const a = issuerOf(ctx, args.issuer)

  return wallet.writeContract({
    address: core.universalRouter,
    abi: universalRouterAbi,
    functionName: 'execute',
    args: [V4_SWAP_COMMAND, [encodeSwapPlan(a, args.amountIn, args.minOut ?? 0n)], deadline()],
    value: args.amountIn,
    account: args.account,
    chain: wallet.chain,
  })
}

/**
 * Exported so the encoding can be diffed byte-for-byte against `script/SeedAndSwap.s.sol`, which is
 * the only version known to have been accepted by the live router. A mis-encoded plan does not fail
 * a type check and does not fail loudly on chain — it reverts inside the router with no useful
 * reason string, which is an expensive thing to debug during a demo.
 */
export function encodeSwapPlan(a: IssuerAddresses, amountIn: bigint, minOut: bigint): Hex {
  const poolKey = poolKeyOf(a)

  const actions = encodePacked(
    ['uint8', 'uint8', 'uint8'],
    [ACTION.SWAP_EXACT_IN_SINGLE, ACTION.SETTLE_ALL, ACTION.TAKE_ALL],
  )

  const params: Hex[] = [
    encodeAbiParameters(
      [
        {
          type: 'tuple',
          components: [
            { name: 'poolKey', type: 'tuple', components: [...POOL_KEY_PARAMS[0].components] },
            { name: 'zeroForOne', type: 'bool' },
            { name: 'amountIn', type: 'uint128' },
            { name: 'amountOutMinimum', type: 'uint128' },
            { name: 'minHopPriceX36', type: 'uint256' },
            { name: 'hookData', type: 'bytes' },
          ],
        },
      ],
      [
        {
          poolKey,
          zeroForOne: true, // ETH → adapter
          amountIn,
          amountOutMinimum: minOut,
          minHopPriceX36: 0n,
          hookData: '0x',
        },
      ] as never,
    ),
    // SETTLE_ALL the input currency, TAKE_ALL the output.
    encodeAbiParameters(parseAbiParameters('address, uint256'), [poolKey.currency0, maxUint256]),
    encodeAbiParameters(parseAbiParameters('address, uint256'), [poolKey.currency1, minOut]),
  ]

  return encodeAbiParameters(parseAbiParameters('bytes, bytes[]'), [actions, params])
}

// ── beats 6 and 8: liquidity ─────────────────────────────────────

/** Full-range bounds, multiples of the 60 tick spacing. */
export const TICK_LOWER = -887220
export const TICK_UPPER = 887220

/**
 * Add liquidity to the issuer's pool.
 *
 * **Caller is always the recipient.** `PermissionedPositionManager` takes no recipient parameter by
 * design — a market maker cannot mint a position to somebody else, because the permission is checked
 * against the caller and the position would otherwise land somewhere the checker never approved.
 *
 * Beat 8 is a retail wallet calling this and reverting: holding `SWAP_ALLOWED` without
 * `LIQUIDITY_ALLOWED` is refused by the hook, not by our UI.
 */
export async function addLiquidity(
  ctx: Canopy,
  args: { account: Account | Address; issuer: string; amountEth: bigint; liquidity: bigint },
): Promise<Hex> {
  const wallet = requireWallet(ctx)
  const core = coreAddresses(ctx.book)
  const a = issuerOf(ctx, args.issuer)
  const recipient = typeof args.account === 'string' ? args.account : args.account.address

  return wallet.writeContract({
    address: core.positionManager,
    abi: positionManagerAbi,
    functionName: 'modifyLiquidities',
    args: [encodeMintPlan(a, recipient, args.liquidity), deadline()],
    value: args.amountEth,
    account: args.account,
    chain: wallet.chain,
  })
}

/** @see encodeSwapPlan for why these are exported. */
export function encodeMintPlan(a: IssuerAddresses, recipient: Address, liquidity: bigint): Hex {
  const poolKey = poolKeyOf(a)

  const actions = encodePacked(['uint8', 'uint8'], [ACTION.MINT_POSITION, ACTION.SETTLE_PAIR])

  const params: Hex[] = [
    encodeAbiParameters(
      [
        { name: 'poolKey', type: 'tuple', components: [...POOL_KEY_PARAMS[0].components] },
        { name: 'tickLower', type: 'int24' },
        { name: 'tickUpper', type: 'int24' },
        { name: 'liquidity', type: 'uint256' },
        { name: 'amount0Max', type: 'uint128' },
        { name: 'amount1Max', type: 'uint128' },
        { name: 'owner', type: 'address' },
        { name: 'hookData', type: 'bytes' },
      ],
      [poolKey, TICK_LOWER, TICK_UPPER, liquidity, maxUint128, maxUint128, recipient, '0x'] as never,
    ),
    encodeAbiParameters(parseAbiParameters('address, address'), [poolKey.currency0, poolKey.currency1]),
  ]

  return encodeAbiParameters(parseAbiParameters('bytes, bytes[]'), [actions, params])
}

/**
 * Withdraw a position. **Beat 14, and it must still succeed after the broker has lapsed** — the
 * claim is that eligibility gates entry, not exit. If this ever starts reverting alongside the
 * swaps, the product is a freeze rather than an allowlist.
 */
export async function removeLiquidity(
  ctx: Canopy,
  args: { account: Account | Address; issuer: string; tokenId: bigint },
): Promise<Hex> {
  const wallet = requireWallet(ctx)
  const core = coreAddresses(ctx.book)
  const a = issuerOf(ctx, args.issuer)
  const recipient = typeof args.account === 'string' ? args.account : args.account.address

  return wallet.writeContract({
    address: core.positionManager,
    abi: positionManagerAbi,
    functionName: 'modifyLiquidities',
    args: [encodeBurnPlan(a, recipient, args.tokenId), deadline()],
    account: args.account,
    chain: wallet.chain,
  })
}

/** @see encodeSwapPlan for why these are exported. */
export function encodeBurnPlan(a: IssuerAddresses, recipient: Address, tokenId: bigint): Hex {
  const poolKey = poolKeyOf(a)

  const actions = encodePacked(['uint8', 'uint8'], [ACTION.BURN_POSITION, ACTION.TAKE_PAIR])

  const params: Hex[] = [
    encodeAbiParameters(parseAbiParameters('uint256, uint128, uint128, bytes'), [tokenId, 0n, 0n, '0x']),
    encodeAbiParameters(parseAbiParameters('address, address, address'), [
      poolKey.currency0,
      poolKey.currency1,
      recipient,
    ]),
  ]

  return encodeAbiParameters(parseAbiParameters('bytes, bytes[]'), [actions, params])
}

// ── approvals ────────────────────────────────────────────────────

/**
 * The two-step approval v4 needs: the token approves Permit2, and Permit2 approves the spender.
 * Missing the second is the classic "approved it, still reverts".
 *
 * Note the token approved here is the **underlying**, not the adapter — the wallet holds the
 * underlying, the pool holds the adapter.
 */
export async function ensureApprovals(
  ctx: Canopy,
  args: { account: Account | Address; issuer: string; spenders?: Address[] },
): Promise<Hex[]> {
  const wallet = requireWallet(ctx)
  const core = coreAddresses(ctx.book)
  const a = issuerOf(ctx, args.issuer)
  const owner = typeof args.account === 'string' ? args.account : args.account.address
  const spenders = args.spenders ?? [core.universalRouter, core.positionManager]
  const hashes: Hex[] = []

  const allowance = (await ctx.publicClient.readContract({
    address: a.underlying,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [owner, PERMIT2],
  })) as bigint

  if (allowance === 0n) {
    hashes.push(
      await wallet.writeContract({
        address: a.underlying,
        abi: erc20Abi,
        functionName: 'approve',
        args: [PERMIT2, maxUint256],
        account: args.account,
        chain: wallet.chain,
      }),
    )
  }

  // viem types anything <= uint48 as `number`; 2^48-1 sits well inside MAX_SAFE_INTEGER.
  const MAX_UINT48 = 281_474_976_710_655
  for (const spender of spenders) {
    hashes.push(
      await wallet.writeContract({
        address: PERMIT2,
        abi: permit2Abi,
        functionName: 'approve',
        args: [a.underlying, spender, maxUint128, MAX_UINT48],
        account: args.account,
        chain: wallet.chain,
      }),
    )
  }

  return hashes
}

/** Underlying balance — what the wallet actually holds. */
export async function balanceOf(ctx: Canopy, wallet: Address, issuer: string): Promise<bigint> {
  const { underlying } = issuerOf(ctx, issuer)
  return (await ctx.publicClient.readContract({
    address: underlying,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [wallet],
  })) as bigint
}

export { issuerAddresses, brokerRegistry, coreAddresses, knownIssuers } from './addresses'
export type { AddressBook, IssuerAddresses, CoreAddresses } from './addresses'
