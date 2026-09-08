/**
 * Differential check: the plans `lib/canopy.ts` builds must be byte-identical to the ones
 * `contracts/script/SeedAndSwap.s.sol` builds.
 *
 * That script's encoding is the only one a live Sepolia transaction has ever accepted. A plan that
 * differs from it type-checks, survives a dry run against a node that does not simulate the hook,
 * and then reverts inside the router with no reason string — so this is the cheapest place to catch
 * it, and it needs no RPC, no deployment and no key.
 *
 * The reference bytes are *generated*, never transcribed:
 *
 *     cd contracts && forge test --match-path test/PlanEncoding.t.sol
 *
 * writes `contracts/test/fixtures/plan-encodings.json`, which this reads. Copying 500-byte hex
 * strings by hand is its own source of false failures — the first version of this check did exactly
 * that, spliced two words together, and reported a mismatch that did not exist.
 *
 * Run:  npx tsx scripts/check-encoding.ts
 */

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

import { encodeBurnPlan, encodeMintPlan, encodeSwapPlan } from '../lib/canopy'
import type { IssuerAddresses } from '../lib/addresses'

// Fixed inputs, identical to the constants in PlanEncoding.t.sol.
const FIXTURE: IssuerAddresses = {
  label: 'acme',
  registry: '0x0000000000000000000000000000000000000001',
  checker: '0x0000000000000000000000000000000000000002',
  adapter: '0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9',
  underlying: '0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920',
  poolFee: 3000,
  poolTickSpacing: 60,
  hooks: '0x51247E2291d290d17C08813A175AC86465EdE8c0',
}

const RECIPIENT = '0xcE1606F346726d8714985b680B84dD6959fb4186' as const
const AMOUNT_IN = 1_000_000_000_000_000n // 0.001 ether
const MIN_OUT = 0n
const LIQUIDITY = 1_234_567_890n
const TOKEN_ID = 42n

const here = dirname(fileURLToPath(import.meta.url))
const fixturePath = resolve(here, '../../contracts/test/fixtures/plan-encodings.json')

let expected: Record<string, string>
try {
  expected = JSON.parse(readFileSync(fixturePath, 'utf8'))
} catch {
  console.error(`could not read ${fixturePath}`)
  console.error('generate it first:  cd contracts && forge test --match-path test/PlanEncoding.t.sol')
  process.exit(1)
}

const cases: [string, string][] = [
  ['swap', encodeSwapPlan(FIXTURE, AMOUNT_IN, MIN_OUT)],
  ['mint', encodeMintPlan(FIXTURE, RECIPIENT, LIQUIDITY)],
  ['burn', encodeBurnPlan(FIXTURE, RECIPIENT, TOKEN_ID)],
]

let failed = 0
for (const [name, actual] of cases) {
  const reference = expected[name]
  if (!reference) {
    console.error(`  FAIL  ${name} — not in the fixture`)
    failed++
    continue
  }

  if (actual.toLowerCase() === reference.toLowerCase()) {
    console.log(`  ok    ${name}  (${(actual.length - 2) / 2} bytes)`)
    continue
  }

  failed++
  console.error(`  FAIL  ${name}`)
  // Report the first differing 32-byte word rather than dumping a kilobyte of hex.
  const a = actual.slice(2)
  const b = reference.slice(2)
  const words = Math.ceil(Math.max(a.length, b.length) / 64)
  for (let i = 0; i < words; i++) {
    const wa = a.slice(i * 64, i * 64 + 64)
    const wb = b.slice(i * 64, i * 64 + 64)
    if (wa !== wb) {
      console.error(`        first difference at word ${i} (byte offset ${i * 32})`)
      console.error(`          solidity   0x${wb || '<missing>'}`)
      console.error(`          typescript 0x${wa || '<missing>'}`)
      break
    }
  }
}

if (failed > 0) {
  console.error(`\n${failed} plan(s) do not match the Solidity encoding.`)
  process.exit(1)
}
console.log('\nall plans match contracts/test/PlanEncoding.t.sol')
