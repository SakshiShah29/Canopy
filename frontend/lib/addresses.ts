import type { Address } from 'viem'
import { getAddress, isAddress } from 'viem'

/**
 * Resolving `deployments.json` into per-issuer address sets.
 *
 * The file is written by two people from two directions. Builder A's scripts write flat,
 * issuer-scoped keys (`registry_acme`, `checker_acme`, `registry_acme_prime`); Builder B's write
 * nested objects (`canopy`, `uniswap`, `pool`). Both shapes are load-bearing, so this reads both
 * rather than asking either side to migrate mid-hackathon.
 */

export type AddressBook = Record<string, unknown>

/** One issuer's world: its registry, its checker, its pool, its token. */
export type IssuerAddresses = {
  label: string
  registry: Address
  checker: Address
  /** The pool's currency1 — what the pool actually holds. */
  adapter: Address
  /** What the wallet holds. Confusing these two is the "insufficient balance on a funded wallet" bug. */
  underlying: Address
  poolFee: number
  poolTickSpacing: number
  hooks: Address
}

export type CoreAddresses = {
  platformRegistry: Address
  applicationContract: Address
  mintAttestor: Address
  universalRouter: Address
  positionManager: Address
}

/** Canonical Permit2. Same on every chain, so it is not in the address book. */
export const PERMIT2: Address = '0x000000000022D473030F116dDEE9F6B43aC78BA3'

// ── reading the book ─────────────────────────────────────────────

function at(book: AddressBook, path: string): unknown {
  return path.split('.').reduce<unknown>((node, key) => {
    if (node && typeof node === 'object') return (node as Record<string, unknown>)[key]
    return undefined
  }, book)
}

function optionalAddress(book: AddressBook, path: string): Address | null {
  const value = at(book, path)
  if (typeof value !== 'string' || !isAddress(value)) return null
  const checksummed = getAddress(value)
  // The scripts write the zero address for "not deployed yet". Treating that as a real address
  // produces calls that succeed against nothing and return zero, which reads as "not eligible".
  return checksummed === '0x0000000000000000000000000000000000000000' ? null : checksummed
}

function requireAddress(book: AddressBook, path: string, hint: string): Address {
  const found = optionalAddress(book, path)
  if (!found) throw new Error(`deployments.json is missing \`${path}\` — ${hint}`)
  return found
}

/**
 * Every issuer the address book knows about, in declaration order.
 *
 * Derived from `checker_*` keys rather than `registry_*`: a broker's registry is also stored as
 * `registry_<issuer>_<broker>`, so splitting on the underscore would report `acme_prime` as an
 * issuer. Only issuers get a checker.
 */
export function knownIssuers(book: AddressBook): string[] {
  return Object.keys(book)
    .filter((key) => key.startsWith('checker_'))
    .map((key) => key.slice('checker_'.length))
}

export function coreAddresses(book: AddressBook): CoreAddresses {
  return {
    platformRegistry: requireAddress(book, 'platformRegistry', 'run DeployIssuerHierarchy first'),
    applicationContract: requireAddress(book, 'cre.ApplicationContract', 'run DeployCREContracts first'),
    mintAttestor: requireAddress(book, 'cre.MintAttestor', 'run DeployCREContracts first'),
    universalRouter: requireAddress(book, 'uniswap.UniversalRouter', 'Builder B writes this'),
    positionManager: requireAddress(book, 'uniswap.PermissionedPositionManager', 'Builder B writes this'),
  }
}

/**
 * One issuer's addresses.
 *
 * Pool and adapter are looked up per-issuer first (`adapter_acme`, `pool_acme.*`). While only one
 * pool exists they fall back to the unsuffixed keys Builder B wrote on Sep 5 — but **only when the
 * book contains exactly one issuer**. With two issuers configured and one pool deployed, the
 * fallback would silently hand Zenith's calls Acme's pool, and beats 9 and 13 would both pass while
 * proving nothing. Failing loudly is the whole point.
 */
export function issuerAddresses(book: AddressBook, label: string): IssuerAddresses {
  const registry = requireAddress(book, `registry_${label}`, `no issuer \`${label}\` in the hierarchy`)
  const checker = requireAddress(book, `checker_${label}`, 'run DeployIssuerHierarchy --sig deployCheckers')
  const underlying = requireAddress(book, `permissionedToken_${label}`, `no pool token for \`${label}\``)

  const soleIssuer = knownIssuers(book).length === 1
  const adapter =
    optionalAddress(book, `adapter_${label}`) ??
    (soleIssuer ? optionalAddress(book, 'canopy.PermissionsAdapter') : null)

  if (!adapter) {
    throw new Error(
      `deployments.json has no \`adapter_${label}\`. ` +
        `The unsuffixed \`canopy.PermissionsAdapter\` is only used when a single issuer is configured; ` +
        `with ${knownIssuers(book).length} issuers it would silently point one issuer at another's pool.`,
    )
  }

  const pool = (at(book, `pool_${label}`) ?? (soleIssuer ? at(book, 'pool') : undefined)) as
    | Record<string, unknown>
    | undefined
  if (!pool) throw new Error(`deployments.json has no \`pool_${label}\``)

  const hooks = optionalAddress(book, `pool_${label}.hooks`) ?? optionalAddress(book, 'pool.hooks')
  if (!hooks) throw new Error(`deployments.json has no hooks address for \`${label}\``)

  return {
    label,
    registry,
    checker,
    adapter,
    underlying,
    poolFee: Number(pool.fee ?? 3000),
    poolTickSpacing: Number(pool.tickSpacing ?? 60),
    hooks,
  }
}

/** A broker's registry under a given issuer. The issuer is part of the key on purpose: the same
 *  broker label under two issuers is two registries, and collapsing them is how one issuer's
 *  expiry ends up cutting off the other's investors. */
export function brokerRegistry(book: AddressBook, issuer: string, broker: string): Address {
  return requireAddress(
    book,
    `registry_${issuer}_${broker}`,
    `no broker \`${broker}\` under issuer \`${issuer}\``,
  )
}
