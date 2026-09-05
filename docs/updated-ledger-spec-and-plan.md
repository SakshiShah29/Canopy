# Ledger — Technical Spec & Build Plan

**Project:** Ledger — Tiered, Expiring Eligibility for Uniswap Permissioned Pools
**Event:** ETHOnline 2026, Sep 4 – Sep 13 (10 days)
**Team:** 2 builders — Builder A (contracts/Solidity), Builder B (off-chain/CRE/frontend)
**Track:** Classic "From Scratch" (empty repo Sep 4)
**Sponsors targeted (3, all load-bearing):** Uniswap Foundation · ENS · Chainlink CRE

---

## 0. Ground truth

**Rev 3 — Sep 5 2026, verified against contract source.** Docs were re-read first; then every remaining open question was closed by reading the actual Solidity in `Uniswap/v4-periphery` and `ensdomains/contracts-v2`. **All architecture gates are now closed.** Summary:

**Gate 2 — which address reaches `checkAllowlist` — 🟢 CLOSED, favourably.** `PermissionedV4Router._pay` / `._take` call `permissionsAdapter.isAllowed(msgSender(), SWAP_ALLOWED)`, and `PermissionsAdapter.isAllowed` forwards that account straight into `checkAllowlist`. `msgSender()` is the end user (Uniswap's own comment on the liquidity path calls it "the actual user"), **not** the router. Binding an ENS name to a trader EOA works. The architecture stands.

**Gate 3 — role-bit collision — 🔴 CLOSED, and both our picks were colliding.** `RegistryRolesLib` assigns nybbles 0–9 plus 30 and 31. `1 << 4` is `ROLE_REGISTER_RESERVED` and `1 << 8` is `ROLE_SET_PARENT`. New values chosen from the free range (nybbles 10–29).

**Gate 4 — on-camera lapse — 🟢 CLOSED.** Subname expiry is ours to set, with no minimum and no clamp to the parent. `getSubregistry`/`getResolver` return `address(0)` once a name is expired, so the parent-expiry cascade is real and enforced in-registry.

**Corrections to Rev 2 — one of which was my own error:**

- 🔴 **Rev 2's "corrected" `State` struct was itself wrong.** The ENS docs page documents the *internal `Entry`* storage struct; `State` is a different, richer struct. **The original Rev-1 spec was right**: `State { Status status; uint64 expiry; address latestOwner; uint256 tokenId; uint256 resource; }`. Reverted. (Rev-1 had two smaller errors that do stand corrected: `resource` is `uint256` not `bytes32`, and `Status` is `{AVAILABLE, RESERVED, REGISTERED}` — there is no `EXPIRED` member.)
- 🔴 **Rev 2's manual resource derivation is unnecessary.** `PermissionedRegistry.hasRoles(uint256 anyId, ...)` accepts a labelhash/tokenId/resource and calls `getResource()` internally. Pass `state.resource` and stop.
- 🔴 **`PermissionFlag` is `bytes2`, not `uint16`.** Rev-1's flag-assembly code would not compile. The type ships `|`, `&` and `==` operators — use those.
- 🔴 **Every ENS address in this document was wrong.** There is a *dedicated hackathon ENSv2 deployment* separate from the standard Sepolia beta. Table replaced below.
- ⚠️ **The swap gate lives in the router, not the hook.** Docs say `beforeSwap` checks `SWAP_ALLOWED`; source shows `PermissionedV4Router` does it in `_pay`/`_take`. Swaps must go through the permissioned Universal Router.

**CRE — verified Sep 5** against the confidential-workflows docs (concepts, TS guide, SDK reference) plus `SamAg19/LienFi`, a working CRE-on-Sepolia project of Builder B's. Three results:

- 🟢 **`cre workflow simulate --broadcast` writes a real KeystoneForwarder transaction to Sepolia**, and the docs say plainly *"Do not wait for early access. Simulate confidential workflows in minutes."* Beta enrollment is **not** on the critical path. Risk #3's zero-impact rating is now verified rather than assumed.
- ✅ **`handlerInTee` / `usingTheDons` are real** and the Sep-3 draft had them right. An intermediate Sep-5 revision wrongly declared them nonexistent after generalising from LienFi, which uses the *other* mechanism (Confidential HTTP). Retracted in §0.
- 🔴 **Source code and compiled binaries are explicitly NOT confidential.** A rulebook written in `main.ts` is public — and our repo must be public. The rulebook has been moved into a Vault-DON secret; without that, the CRE prize's premise is false. New risk #20.

The Privy subsection was **cut** rather than verified — see below for why.

**Every sponsor surface in this document is now verified.** Uniswap and ENS against contract source; CRE against current docs plus a working project. The two residual CRE unknowns — whether nitro/`us-west-2` is the only registered TEE, and whether LienFi's ~6-month-old SDK shapes have drifted — are both nuisance-grade with stated mitigations (risk #21).

### Uniswap Permissioned Pools

> **Verification pass — Sep 5 2026.** Everything in this subsection marked ✅ was re-read against the official docs at `developers.uniswap.org/docs/protocols/v4-hooks/permissioned-pools/{overview,architecture,deploy-a-permissioned-pool,provide-liquidity}`, then re-confirmed against `Uniswap/v4-periphery` contract source. **No open items remain in this subsection.**

- Shipped **23 July 2026** with Superstate, Securitize, and Dowgo as launch partners. Landed as a periphery + hook standard, not a v4-core change.
- Source of truth: `Uniswap/v4-periphery`, `src/hooks/permissionedPools/`. The interface we implement is `IAllowlistChecker` in `interfaces/IAllowlistChecker.sol`; flags are in `libraries/PermissionFlags.sol` (`SWAP_ALLOWED = 0x0001`, `LIQUIDITY_ALLOWED = 0x0002`). ✅
- ✅ Exact interface signature (confirmed against the official deploy guide's own reference checker):

```solidity
function checkAllowlist(address account, address tokenAddress)
    external view returns (PermissionFlag);
```

- ✅ ERC-165 gating: the checker must return true for `type(IAllowlistChecker).interfaceId`. Note the docs are explicit that this check "only confirms that a checker implements `IAllowlistChecker`" — it is a shape check, not a behaviour check.
- ✅ The reference checker in the docs **ignores `tokenAddress` entirely** and returns `permissions[account]`. Our single-pool checker doing the same is idiomatic, not a shortcut.
- ✅ `PermissionsAdapter` behaviour: wraps the underlying permissioned token, mints a **virtual token** that the pool trades; transfers out burn the virtual token and release the underlying in the same call.
- ✅ Admin surface on the adapter: `updateAllowListChecker`, `updateAllowedWrapper`, `updateAllowedHook`, `updateSwappingEnabled`. **Swapping is off by default** — swaps revert with `SwappingDisabled` until the owner calls `updateSwappingEnabled(true)`.
- ✅ **The checker is supplied at adapter creation**, not bolted on afterwards:
  `factory.createPermissionsAdapter(IERC20(permissionedToken), issuerAdmin, IAllowlistChecker(checker))`.
  `updateAllowListChecker` exists to swap it later — which we exploit in the demo (see §6, Sep 9).
- ✅ Factory verification: the issuer allowlists the adapter on the underlying token, transfers it a small balance (**as little as 1 wei**), then calls `PermissionsAdapter(adapter).depositForVerification(1)`.
- ✅ Wrapper/hook approvals are required before anything routes. All four of these must be registered:

```solidity
PermissionsAdapter(adapter).updateAllowedWrapper(permissionedPositionManager, true);
PermissionsAdapter(adapter).updateAllowedWrapper(universalRouter, true);
PermissionsAdapter(adapter).updateAllowedWrapper(v4Quoter, true);
PermissionsAdapter(adapter).updateAllowedWrapper(mixedRouteQuoterV2, true);
PermissionsAdapter(adapter).updateAllowedHook(IHooks(permissionedHooks), true);
```

- ✅ **There is a dedicated `PermissionedPositionManager`.** The standard v4 `PositionManager` is not usable for permissioned pools. This is load-bearing for the console and for every liquidity test.
- ✅ Position NFTs are **non-transferable**: `transferFrom` and both `safeTransferFrom` overloads revert with `TransferDisabled`.
- ✅ `unwindPosition(tokenId)` burns the NFT, removes liquidity, and routes each asset back to the holder; assets the holder cannot receive fall back to the **adapter owner** (not, as previously written here, "that asset's own issuer").
- ✅ Hook callbacks: `beforeSwap` checks `SWAP_ALLOWED` for the swapper; `beforeAddLiquidity` checks `LIQUIDITY_ALLOWED`.
- ✅ **`LIQUIDITY_ALLOWED` is checked twice on mint/increase, against two different addresses**: the position manager checks the **recipient**, and the hook's `beforeAddLiquidity` checks the **caller**. If caller ≠ recipient, both need the permission.
- ✅ **Decreases and burns are never gated.** Per the docs: "you can always withdraw, even if the wallet later loses permission." This bounds what the expiry cascade can demonstrate — see §1.
- ✅ The deploy guide's step 7 — **allowlist your pool for routing with Uniswap Labs** — buys eligibility for the **Uniswap-hosted interface and routing API, and nothing else**. It is not an on-chain gate and cannot restrict direct contract calls. The only on-chain gates are the adapter's `allowedWrapper` / `allowedHook` registrations and our checker's return value, all of which we control. **Out of scope, with no impact on the build:** our console calls the router, quoter and position manager directly. See §2 for what that requires.
#### 🟢 Gate 2 — closed from source. `account` is the end trader.

`PermissionsAdapter.isAllowed` forwards its `account` argument straight through:

```solidity
function isAllowed(address account, PermissionFlag permission) public view returns (bool) {
    return ((allowListChecker.checkAllowlist(account, address(PERMISSIONED_TOKEN))) & (permission)) == (permission);
}
```

and every call site passes the **end user**, not the router:

```solidity
// PermissionedV4Router._take and ._pay  (swap path)
if (!permissionsAdapter.isAllowed(msgSender(), PermissionFlags.SWAP_ALLOWED)) revert Unauthorized();

// PermissionedPositionManager._pay      (liquidity path — caller)
// Uniswap's own comment: "Check liquidity permission for the actual user"
if (!permissionsAdapter.isAllowed(msgSender(), PermissionFlags.LIQUIDITY_ALLOWED)) revert Unauthorized();

// PermissionedPositionManager._checkRecipientAllowed  (liquidity path — recipient)
if (!IPermissionsAdapter(...).isAllowed(recipient, PermissionFlags.LIQUIDITY_ALLOWED)) revert Unauthorized();
```

**Binding an ENS name to a trader EOA works.** This was the one finding that could have killed the project; it landed the right way.

Two corollaries:

- ✅ **`tokenAddress` is the underlying `PERMISSIONED_TOKEN`, not the adapter.** The interface comment explains why it exists: *"lets a single allowlist checker serve multiple assets without an extra round-trip into the adapter."* Our single-asset checker ignoring it remains correct.
- ⚠️ **The swap gate is in the router, not the hook.** The docs say `beforeSwap` checks `SWAP_ALLOWED`; the source shows `PermissionedV4Router._pay` / `._take` doing it. `src/hooks/permissionedPools/` contains **no hook contract at all** — only the adapter, factory, router, position manager and checker base. So swaps *must* route through the permissioned Universal Router; the deployed `PermissionedHooks` mainly exists to be allow-listed. `PermissionedV4Router._validatePoolKey` enforces that, with a pointed comment: rejecting only `address(0)` "is insufficient — a no-op hook, or an address mined without `BEFORE_SWAP_FLAG`, would otherwise pass."

#### 🔴 `PermissionFlag` is `bytes2`, not `uint16`

```solidity
type PermissionFlag is bytes2;
using {or as |} for PermissionFlag global;
using {and as &} for PermissionFlag global;
using {eq as ==} for PermissionFlag global;

library PermissionFlags {
    PermissionFlag constant NONE              = PermissionFlag.wrap(0x0000);
    PermissionFlag constant SWAP_ALLOWED      = PermissionFlag.wrap(0x0001);
    PermissionFlag constant LIQUIDITY_ALLOWED = PermissionFlag.wrap(0x0002);
    PermissionFlag constant ALL_ALLOWED       = PermissionFlag.wrap(0xFFFF);
}
```

Rev-1's `uint16`-based flag assembly would not have compiled. The type ships global `|`, `&` and `==`, so assemble with the operators and use `PermissionFlags.NONE` rather than `PermissionFlag.wrap(0)`. Also note **`IAllowlistChecker` already extends `IERC165`**, and there is a `BaseAllowListChecker` abstract in the repo we could inherit instead of wiring ERC-165 by hand.

#### Deployed addresses (from the official deploy guide, Sep 5 2026)

| Contract | Ethereum Mainnet | Sepolia |
|---|---|---|
| `PermissionsAdapterFactory` | `0x7DA911490Ca4663E572eA9C8154f3CdEbCE16452` | `0xE6B0d96919334C33d06266d1420F97f6f434fA2B` |
| `PermissionedPositionManager` | `0x63Bd7e5D4EcfAA74d82AE1dE98F476C935a81973` | `0xf99D553912084c99F6299291b75Fe9B7119Aa1A7` |
| `PermissionedHooks` | `0x499a724Ab630549f14C995EC41a8E04fA3fd28c0` | `0x51247E2291d290d17C08813A175AC86465EdE8c0` |
| Universal Router | `0x0542093271A31f6FC1DADB232bd59eeb27de780F` | `0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7` |
| `V4Quoter` | `0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203` | `0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227` |
| `MixedRouteQuoterV2` | `0xE63C5F5005909E96b5aA9CE10744CCE70eC16CC3` | `0x4745F77b56a0E2294426E3936dc4Fab68d9543Cd` |

**Sepolia is live.** We do not need to deploy any Permissioned Pools infrastructure ourselves. This removes a full day of contingency from the schedule (old risk #2) and pre-clears the old Gate 3.

Note the Universal Router address above is a **permissioned-pool-specific deployment**, not the canonical Sepolia Universal Router. The prior "Universal Router 2.2.0+" framing was not wrong so much as unhelpful — use *this* address.

### ENSv2 (Sepolia beta)

- **Chain: regular Sepolia, chain ID 11155111.** (The interim Tenderly-virtual-chain deployment is no longer canonical — the Sep 2026 docs point to Sepolia proper.)
- Canonical deployments (from `docs.ens.domains/learn/deployments#sepolia-ensv2-beta`, fetched Sep 3):

> 🔴 **All addresses below were replaced on Sep 5.** The previous table pointed at the *standard* ENSv2 Sepolia beta. The docs state: *"the table below lists the dedicated hackathon ENSv2 deployment, which is separate from the standard ENSv2 Beta deployment on Sepolia."* **Use these. Every prior address in this spec was wrong.** Note `ManagedUniversalResolverProxy` is also renamed to `UpgradableUniversalResolverProxy`.

| Contract | Address (hackathon deployment) |
|---|---|
| `RootRegistry` | `0xe7f0d5724f8337e3aa9a9910540341ff4273fed9` |
| `ETHRegistry` (the `.eth` TLD registry) | `0x1d78834d97c1d7b1a38c1dedbd1a287cfed3971e` |
| `ETHRegistrar` | `0x7d1b7f586a62ac3f54b9a396849757814283270b` |
| `VerifiableFactory` | `0x894bc9cc8ff1ad96b8a288c86a8c71d662c07780` |
| `UserRegistryImpl` (subname registry proxy target) | `0x47b442d0cf617c41cabaff5f02f44dd1e5f72546` |
| `PermissionedResolverImpl` | `0xa9d3814ab151bf6e37a427432795371a8361614e` |
| `UniversalResolverV2` | `0xfea8d4b7fcce0b8765c793d6695eac384aaa458f` |
| `UpgradableUniversalResolverProxy` | `0xd26f2040d083af1cd2962ba303f4bea0c4faf142` |
| `LabelStore` | `0xd7351f76866123a7e49381f38a30a96adba7e855` |
| `MockUSDC` (ETHRegistrar payment token) | `0xcbfd80f74375c54e545af34788ff465f96f66f05` |
| `DefaultReverseRegistrarAdapter` | `0x0a8d7ed4061548fb3cb192d0cbe9e1a57b3b1ae9` |

> **Verification pass — Sep 5 2026.** Re-read against the ETHOnline preview docs build at `feature-permres-inode-refact.docs-bao.pages.dev` (`/ensv2/{overview,enhanced-access-control,permissioned-registry,registry-hierarchy,eth-registrar,mutable-token-ids}`). This build is ahead of the live site and includes the Permissioned Resolver / inode refactor. Everything below was then re-confirmed against `ensdomains/contracts-v2` source; where the two disagree, **source wins and is noted inline**. **No open items remain in this subsection.**

#### Enhanced Access Control — bitmap layout ✅

- `uint256` bitmap split in half: **bits 0–127 regular roles, bits 128–255 admin roles**. 32 regular + 32 admin per contract.
- Each role occupies **one 4-bit nybble**. Regular role at nybble index N spans bits `4N…4N+3`; its admin twin sits at `4N+128…4N+131`, i.e. `ROLE << 128`. So role constants are of the form `1 << (4 * N)`.
- The nybble stores a **count**, not a flag: `_roleCount[resource]` per role, `_roles[resource][account]` as 0 or 1. Hence **a hard cap of 15 accounts holding a given role on a given resource.**
  - Harmless as designed — each investor's name is its own resource with exactly one holder. **But it would be fatal to "optimise" eligibility onto a shared resource: `ROOT_RESOURCE` would cap the entire product at 15 investors.** Comment this in `LedgerRoles.sol` before someone tries it.
- A **resource** is "the thing you're controlling access to… in most ENS contracts a resource is a name — but it can be any `uint256` identifier." `ROOT_RESOURCE = 0x0` means contract-wide.
- ✅ `hasRoles(uint256 anyId, uint256 roleBitmap, address account)` — note `PermissionedRegistry` **overrides** this to accept a labelhash / tokenId / resource and resolve `getResource()` internally. We do not compute resources by hand.

#### 🔴 The real `RegistryRolesLib` table — Gate 3, closed from source

Read from `ensdomains/contracts-v2`, `contracts/src/registry/libraries/RegistryRolesLib.sol`:

| Nybble | Constant | Value | Scope |
|---|---|---|---|
| 0 | `ROLE_REGISTRAR` | `1 << 0` | root only |
| 1 | `ROLE_REGISTER_RESERVED` | `1 << 4` | root only |
| 2 | `ROLE_SET_PARENT` | `1 << 8` | root only |
| 3 | `ROLE_UNREGISTER` | `1 << 12` | root or token |
| 4 | `ROLE_RENEW` | `1 << 16` | root or token |
| 5 | `ROLE_SET_SUBREGISTRY` | `1 << 20` | root or token |
| 6 | `ROLE_SET_RESOLVER` | `1 << 24` | root or token |
| 7 | `ROLE_CAN_TRANSFER` | admin-only: `(1 << 28) << 128` | checked on token owner |
| 8 | `ROLE_WAS_RESERVED` | `1 << 32` | token only, not revokable |
| 9 | `ROLE_SET_URI` | `1 << 36` | root only |
| 30 | `ROLE_CAN_NAME` | `1 << 120` | root only |
| 31 | `ROLE_UPGRADE` | `1 << 124` | root only |

Admin variants are uniformly `ROLE << 128`.

**Our two proposed constants were both colliding.** `ROLE_ELIGIBLE_SWAP = 1 << 4` is `ROLE_REGISTER_RESERVED`; `ROLE_ELIGIBLE_LIQUIDITY = 1 << 8` is `ROLE_SET_PARENT`. (The earlier guess that they hit `ROLE_SET_SUBREGISTRY` / `ROLE_SET_RESOLVER` was wrong about *which* roles — those sit at nybbles 5 and 6 — but right that there was a collision.) Both colliding roles happen to be **root-only**, so on a per-name resource they may well have been inert in practice — but shipping a checker whose eligibility bits alias protocol-reserved roles is indefensible in a submission judged by ENS.

**Free nybbles: 10 through 29** (`1 << 40` … `1 << 116`). We take nybbles 16 and 17 — mid-range, far from both the assigned low block and the reserved 30/31:

```solidity
uint256 constant ROLE_ELIGIBLE_SWAP      = 1 << 64;   // nybble 16
uint256 constant ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;   // nybble 17
```

#### `getState` and `State` ✅ — verified from source (and a Rev-2 error reverted)

> ⚠️ **Rev 2 got this wrong and Rev 1 was essentially right.** The ENS docs page describes the registry's *internal* `Entry` storage struct — `{eacVersionId, tokenVersionId, subregistry, expiry, resolver}` — which is **not** what `getState` returns. Confirmed from `IPermissionedRegistry.sol` and `PermissionedRegistry.getState`:

```solidity
enum Status { AVAILABLE, RESERVED, REGISTERED }   // no EXPIRED member

struct State {
    Status  status;       // getStatus()
    uint64  expiry;       // getExpiry()
    address latestOwner;  // latestOwnerOf()
    uint256 tokenId;      // getTokenId()
    uint256 resource;     // getResource()   <-- uint256, not bytes32
}
```

So the Rev-1 traversal was structurally correct. Two small Rev-1 errors do stand corrected: `resource` is `uint256` (not `bytes32`), and the `Status` enum is `{AVAILABLE, RESERVED, REGISTERED}` — there is no `EXPIRED` member, because *"names are treated as `AVAILABLE` once `block.timestamp >= expiry`."*

- `anyId` is polymorphic across labelhash / token ID / resource; `_entry()` zeroes the version bits to resolve any of them. ✅
- **`state.resource` is handed to us** — no manual bit-twiddling. And `hasRoles` accepts `anyId` anyway.
- ✅ `_isExpired(expiry)` is exactly `block.timestamp >= expiry`. Note this is `>=`, so the Rev-1 predicate `state.expiry <= block.timestamp` is correct.

#### Resource and token ID derivation ✅ — architecturally load-bearing

Both are `labelhash`-derived but **version-stamped**:

```
resource = (upper 224 bits of labelhash) | eacVersionId    (lower 32 bits)
tokenId  = (upper 224 bits of labelhash) | tokenVersionId  (lower 32 bits)
```

- `tokenVersionId` increments when **roles are granted or revoked**, or the name is unregistered/re-registered. So *every role change regenerates the token.*
- `eacVersionId` increments **only** on unregister / re-register.
- On expiry-then-re-registration both bump, the name gets a **fresh resource**, and every role grant from the previous registration is orphaned under the dead resource.

This is a strong result for us, in three ways:

1. **It vindicates the cache design.** We cache only `(labelhash, registry)` and re-read `getState` every call. A design that cached resources or token IDs would be silently wrong after any role change.
2. **Risk #1 is genuinely low.** Our checker never touches token IDs, and `tokenVersionId` churn (which fires on every role grant) cannot affect us. Uniswap-adjacent bonus: the source comment says version-stamping tokens on role change exists to "prevent frontrunning a transfer with a role revocation."
3. **It strengthens the product story.** A lapsed-then-re-registered broker name cannot resurrect its old book. And this is enforced even *before* re-registration: `_constructResource` returns `eacVersionId + 1` while a name is expired, so an expired name's resource is already a different one from the resource its grants live under. **Expiry fails closed by construction.** Say this in the video.

`TokenRegenerated(oldTokenId, newTokenId)` is the signal event.

#### 🟢 Parent-expiry cascade — confirmed in source

The claim that a lapsed parent takes its subtree with it is **real and enforced in the registry**, not merely a resolution convention:

```solidity
function getSubregistry(string calldata label) public view virtual returns (IRegistry) {
    Entry storage entry = _entry(LibLabel.id(label));
    return _isExpired(entry.expiry) ? IRegistry(address(0)) : entry.subregistry;
}
// getResolver() has the identical guard
```

An expired name returns a **null subregistry and null resolver**, so top-down resolution dead-ends there and everything beneath it is unreachable.

Our checker walks bottom-up from a cached path and tests `expiry` at every hop, so it reaches the same verdict by its own means. Belt and braces — say in the README that the cascade is enforced twice over, once by ENS and once by our traversal.

**Gate 4 residual, resolved:** a child's expiry is **not** clamped to its parent's. The child lives in a different registry contract, which has no knowledge of the parent; `_register` only enforces `CannotSetPastExpiry`. So a subname can nominally outlive its parent — it just becomes unreachable. Irrelevant to us, and it means a short `brokerA` expiry is registrable without fighting anything.

#### Registration paths — two different calls, two different conventions ✅

**`.eth` second-level names (`issuer.eth`) go through `ETHRegistrar`** and this is materially more involved than the spec assumed:

```solidity
ETHRegistrar.register(
    string label, address owner, bytes32 secret, IRegistry subregistry,
    address resolver, uint64 duration, IERC20 paymentToken, bytes32 referrer
)
```

- **Commit–reveal is mandatory:** `commit(makeCommitment(...))` → wait `MIN_COMMITMENT_AGE` (**60 seconds**) → `register()` with matching params. Commitment expires after `MAX_COMMITMENT_AGE` (~24h). **This step was missing from the plan entirely.**
- **`duration` in seconds, not an absolute expiry.** A `MIN_REGISTER_DURATION` is enforced (value unpublished; examples use `31536000` = 1 year).
- **It costs money, in ERC20.** 3 chars $640/yr, 4 chars $160/yr, **5+ chars $8/yr**, paid by `safeTransferFrom` to an immutable beneficiary. Multi-year discounts ~12.5% (2y) to ~44% (6y).
- This is what ENS's **`MockUSDC` (hackathon deployment: `0xcbfd80f74375c54e545af34788ff465f96f66f05`) is for** — it is the registrar payment token, *not* a pool asset.

**Subnames (`brokerA.issuer.eth`, `alice.brokerA…`) go through our own `UserRegistry`** via `IPermissionedRegistry.register(label, owner, subregistry, resolver, roleBitmap, expiry)` with an **absolute** expiry we choose. No commit–reveal, no payment, no documented minimum duration. See Gate 4 — this is what makes the on-camera lapse feasible.

#### Expiry ✅

- ✅ Expired iff `block.timestamp >= expiry`. Grace period **28 days**, renewable by anyone during grace, base rate only, no premium.
- ✅ After grace, a 21-day **premium** period: starts ~$100M, halves daily, decays to zero.
- ✅ `renew()` can only extend expiry, never reduce it.
- ✅ **The "expired parent ⇒ subtree inaccessible" claim is confirmed in source** — `getSubregistry` and `getResolver` both return `address(0)` once `_isExpired(entry.expiry)`. See the cascade subsection above. Our checker independently tests `expiry` at every hop, so the cascade holds twice over.
- Supporting quote for the README: *"merely owning a subname token does not guarantee anything in isolation: the registry must be referenced by a parent registry, and so on up to the root."*

#### Hierarchy traversal ✅

- `IRegistry.getSubregistry(string calldata label) external view returns (IRegistry)` — note it takes a **label string, not a labelhash**. We avoid needing it, since `getState` hands us `subregistry` directly.
- Resolution walks **down** from root, calling `getResolver()` / `getSubregistry()` at each level.
- Wiring a new UserRegistry: deploy proxy via `VerifiableFactory`, `initialize()` with a bitmap including at least `ROLE_REGISTRAR_ADMIN | ROLE_RENEW_ADMIN`, then `setSubregistry(...)` on the parent.
- **A name's resolver and subregistry are its owner's own deployments** — look them up fresh, never hardcode or cache. In ENSv2 every account now gets its **own Permissioned Resolver proxy** with per-record permissions, so this matters more than in v1.

### Chainlink CRE Confidential Workflows

> **Verification pass — Sep 5 2026.** `docs.chain.link/cre/privacy` was read, and — more usefully — the CRE SDK usage below was verified against **a working CRE project on Sepolia that Builder B wrote**: `github.com/SamAg19/LienFi` (four workflows, live Sepolia deployments, forwarder-based receivers). Where the two disagree, the working project wins. Several Sep-3 claims in this subsection were wrong.

#### 🟢 `cre workflow simulate` DOES write to live Sepolia — via `--broadcast`

This retires the biggest open question in the plan. From LienFi's `run-cre.sh`:

```bash
cre workflow simulate "$WORKFLOW_DIR" \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --broadcast \
  --verbose \
  --evm-tx-hash "$EVM_TX_HASH" \
  --evm-event-index 0
```

The script then greps the output for the **forwarder broadcast tx hash** and reports it. So a simulated run produces a real KeystoneForwarder transaction on Sepolia that lands in the receiver contract. Risk #3's "Impact: Zero" rating is **correct and now verified** — the CRE→on-chain link is fully demonstrable without beta enrollment. The `--broadcast` flag was missing from the Sep-3 simulator invocation and is the single most important detail in this subsection.

#### ✅ RETRACTED: the Sep-3 SDK shape was right after all

An intermediate Sep-5 revision claimed `handlerInTee` and `usingTheDons` "do not exist in the shipped SDK." **That was wrong.** It generalised from LienFi, which uses **Confidential HTTP** — a different mechanism with a different API. Both exist. Verified against `docs.chain.link/cre/reference/sdk/confidential-workflows-client-ts`:

```typescript
function handlerInTee<TRawTriggerOutput, TTriggerOutput, TConfig, TResult>(
  trigger: Trigger<TRawTriggerOutput, TTriggerOutput>,
  fn: (runtime: TeeRuntime<TConfig>, triggerOutput: TTriggerOutput) => TResult,
  tees: TeeConstraint,
  hooks?: Hooks<TConfig, TTriggerOutput>
): HandlerEntry<...>

interface TeeRuntime<C> extends BaseRuntime<C>, SecretsProvider {
  reportFromDon(input: ReportRequest | ReportRequestJson): { result: () => Report }
  usingTheDons(): Runtime<C>
}

getSecret(request: SecretRequest | SecretRequestJson): { result: () => Secret }
getSecrets(requests: Array<SecretRequest | SecretRequestJson>): { result: () => Record<string, Secret> }
```

`TeeConstraint` accepts `{}` (any registered TEE, any region), `{ regions: [...] }`, or `[{ tee: 'nitro', regions: ['us-west-2'] }]`.

⚠️ The Sep-3 claim that **nitro / `us-west-2` is the *only* registered TEE** is still unconfirmed — the docs use it as the example but publish no registry list. Use `{}` unless we have a reason not to.

#### 🟢 Simulation does not require beta enrollment

Docs, verbatim: **"Do not wait for early access. Simulate confidential workflows in minutes."** Combined with LienFi's `--broadcast` evidence above, the CRE path is fully demonstrable: a confidential workflow, simulated locally, writing a real forwarder transaction to Sepolia. Enrollment is needed only to deploy to a live DON.

#### 🔴 The confidentiality boundary — and what it costs our headline claim

Verified verbatim from `docs.chain.link/cre/concepts/confidential-workflows`.

**Protected by default:**
- "Secrets the Vault DON releases into the enclave"
- "Sensitive inputs and intermediate values you don't explicitly share outside the enclave"
- "Capability calls made from inside the enclave"
- "Enclave execution memory, for as long as your computation runs inside it"

**NOT automatically protected:**
- "Workflow triggers, chain reads, and chain writes—these always execute on Workflow DON nodes"
- **"Your workflow's source code, deployed binary, and orchestration metadata"**
- "Reports, transaction calldata, and any output you deliver outside the enclave boundary"

And the explicit caveat: *"Your handler's source code and compiled binary are not confidential just because part of its logic runs inside an enclave."*

**🔴 This directly threatens §1's "compliance without leaking rules" pitch.** If the eligibility rulebook is written as TypeScript in `main.ts`, it is **not confidential** — the source and binary are excluded from protection, and our repo is public by prize requirement. Running it inside a TEE protects the *applicant's data*, not *our logic*.

**The fix, and it is not optional:** the rulebook's discriminating content — score thresholds, tier boundaries, jurisdiction rules — must live in **Vault DON secrets** fetched via `runtime.getSecrets([...])` inside the enclave, with `main.ts` containing only the generic evaluation shape. Then the claim is true: the code is public, the criteria are not, and neither is the PII.

Also note **reports are explicitly not protected**, which retroactively justifies §2's design: the on-chain report carries only `{ wallet, label, brokerRegistry, roleBitmap, expiry, approved }` and never raw KYC data. That was a lucky guess in the Sep-3 draft; it is now a requirement.

#### Two confidentiality mechanisms — pick deliberately

| Mechanism | What runs in the TEE | API | Status |
|---|---|---|---|
| **Confidential Workflows** | The whole handler — "risk thresholds, proprietary scoring, multi-step reasoning over sensitive inputs" | `handlerInTee` + `TeeRuntime` + `usingTheDons()` | Private beta to **deploy**; **simulates freely** |
| **Confidential HTTP** | A *single* outbound HTTP request, secrets injected via templates, optional encrypted response | `ConfidentialHTTPClient` / `ConfidentialHTTPSendRequester` | Used in production by LienFi |

Both fetch secrets from the **Vault DON** rather than the regular Workflow DON runtime, and both execute in a hardware-isolated enclave.

**Recommendation: build on Confidential Workflows.** It is the mechanism our pitch actually describes — the rulebook evaluates inside the enclave, not just the KYC fetch — and since simulation needs no enrollment, the beta gate does not block the demo. Confidential HTTP remains the fallback if `handlerInTee` misbehaves under simulation; LienFi proves that path works end-to-end on Sepolia.

#### Still unverified in this subsection

- Whether nitro / `us-west-2` is the **only** registered TEE type/region. Docs use it as an example and publish no registry. Mitigation: pass `{}` and accept any registered TEE.
- Whether LienFi's SDK version (last pushed 2026-03-09) matches what `cre init` produces today. The confidential APIs above come from current docs, but the `EVMClient` / `writeReport` / `logTrigger` shapes come from LienFi and are ~6 months old. Reconcile on Day 1 by diffing against a fresh `cre init`.

### Privy — deliberately not a ground-truth item

**Cut Sep 5.** This subsection previously documented Privy **Server Wallets** and their policy engine (`override_policy_ids`, `ethereum_calldata` field sources, DENY-beats-ALLOW, `PATCH /v1/policies/…`). None of it belongs here:

- Privy is **not a sponsor we are targeting**, so none of it earns prize points.
- It described **Server Wallets**, while the architecture uses **embedded wallets** for issuer console sign-in — a different product with a different API. Leaving it in read like a plan to build a policy-gated signing layer that is not in scope and never was.
- The only load-bearing claim — an embedded wallet can sign a Sepolia transaction — is verified by the console working on Day 3, not by reading docs.

Privy's entire role in this project is **console authentication**, stated in §2. Desktop only; see risk #9.

---

## 1. Product summary

### Problem (verbatim from the source discovery)

Uniswap Permissioned Pools shipped July 2026 with a **flat, issuer-managed eligibility set**. Real tokenised-fund distribution is not flat — it runs through brokers and placement agents. An issuer onboarding three brokers today adds every end investor individually, and cutting off a broker's book is one write per investor. There is also **no expiry**, so a lapsed accreditation stays tradeable until a human remembers to remove it.

### Solution

`ENSAllowlistChecker` — an `IAllowlistChecker` implementation where eligibility means holding a **live subname under `issuer.eth`**, with each broker holding an intermediate subregistry (`brokerA.issuer.eth`, `brokerB.issuer.eth`, …). Investors hold `alice.brokerA.issuer.eth`.

### The one hard technical insight

**Permissions in the standard are a bitmask, not a boolean.** `SWAP_ALLOWED = 0x0001` is checked in `beforeSwap`; `LIQUIDITY_ALLOWED = 0x0002` in `beforeAddLiquidity`.

We derive those two bits from **two separate EAC role grants** on the investor's subname:
- Holding a custom role `ROLE_ELIGIBLE_SWAP` → contributes `SWAP_ALLOWED` to the returned flag.
- Holding a custom role `ROLE_ELIGIBLE_LIQUIDITY` → contributes `LIQUIDITY_ALLOWED`.

An issuer can now grant a retail investor swap-only access and a market maker swap+liquidity — **revocable and expiring independently**. A flat allowlist has no vocabulary for this.

Two properties come free from ENSv2:
- **Expiry** — a lapsed subname cuts off the whole subtree beneath it in one event, with no on-chain revocation transaction. Our checker tests `expiry` at *every* hop, so it enforces this cascade itself rather than depending on the registry to do it.
- **Stale-grant invalidation** — ✅ verified Sep 5, and stronger than we assumed. The EAC **resource** is version-stamped (`upper224(labelhash) | eacVersionId`), and `eacVersionId` bumps on re-registration. So a broker who lets their name lapse and re-registers it gets a **fresh resource**, and every eligibility grant in their old book is orphaned under a resource that no longer corresponds to a live name. Re-registration cannot resurrect a revoked book. This is ENS doing the work, not our code — and it is worth saying out loud in the video.

### Sponsor roles (each load-bearing)

| Sponsor | Load-bearing role | What breaks if removed |
|---|---|---|
| **Uniswap** | `IAllowlistChecker` is the documented issuer extension point; the whole checker is the integration surface | There is no product — nothing to plug the checker into |
| **ENS** | Hierarchical registries (parent/broker/investor), EAC role bits for the swap/liquidity split, expiry semantics for atomic cutoffs | Reduces to hand-rolled bespoke registry with none of the lifecycle guarantees |
| **Chainlink CRE** | Applicant PII fetched and evaluated inside a TEE; the rulebook supplied as a **Vault-DON secret** so the criteria stay private even though the repo is public; only a verdict (`APPROVE`/`REJECT`) crosses back via `usingTheDons` and mints the subname | Criteria and PII must go on-chain or be trusted to our server — kills the "compliance without leaking rules" story |

### The money-shot demo (this is the memorable moment)

Two investors registered under `brokerA.issuer.eth`:
- `retail.brokerA.issuer.eth` holds `ROLE_ELIGIBLE_SWAP` only.
- `mm.brokerA.issuer.eth` holds both `ROLE_ELIGIBLE_SWAP` and `ROLE_ELIGIBLE_LIQUIDITY`.

On camera:
1. Retail swaps successfully (`SWAP_ALLOWED` bit set).
2. Retail attempts `addLiquidity` → reverts (no `LIQUIDITY_ALLOWED`).
3. Market maker both swaps and adds liquidity successfully.
4. **`brokerA.issuer.eth` expires.** No transactions are sent to anyone.
5. Both investors now revert on **swap and on adding liquidity** — the broker's entire subtree collapsed in one event.

That's the sequence a judge remembers. Everything else in the demo serves this moment.

**Two honesty constraints on step 5, both verified Sep 5:**

- **Withdrawal is not cut off, by design.** Decreases and burns are never gated in the standard — "you can always withdraw, even if the wallet later loses permission." So the correct on-camera claim is *"they can no longer trade or add exposure"*, **not** *"they're frozen"*. Any judge who knows the standard will catch an overclaim here, and the narrower claim is the more credible one anyway: an eligibility system that traps assets is a bug, not a feature. Say this out loud in the video — it reads as command of the spec.
- **Sepolia cannot be time-warped, but ✅ we don't need to.** Register `brokerA.issuer.eth` with a **deliberately short expiry** (e.g. 10 minutes) and let it lapse on camera. Verified Sep 5: subname expiry is set by us via `IPermissionedRegistry.register`, there is no minimum duration, and **no clamp to the parent's expiry** — only `CannotSetPastExpiry`. The whole demo runs on live Sepolia; the Anvil fork fallback is retired.

---

## 2. Architecture

```
     ┌───────────────────────── OFF-CHAIN ─────────────────────────┐
     │                                                             │
     │  Issuer console (Builder B, Next.js + Privy embedded)       │
     │       │                                                     │
     │       │  applicant submits KYC package                      │
     │       v                                                     │
     │  ┌───────────────────────────────────────────┐              │
     │  │ Chainlink CRE Confidential Workflow (TEE) │              │
     │  │  - rulebook + applicant PII as secrets    │              │
     │  │  - only APPROVE|REJECT + labelhash cross  │              │
     │  │    back via usingTheDons                  │              │
     │  └───────────────────────┬───────────────────┘              │
     │                          │  evmClient.writeReport           │
     └──────────────────────────┼──────────────────────────────────┘
                                v
     ┌────────────────────────────── ON-CHAIN (Sepolia) ───────────────────────┐
     │                                                                          │
     │  MintAttestor (CRE IReceiver) ──▶ SubnameRegistrar                       │
     │                                     │ REGISTRY.register(label, owner,    │
     │                                     │   subregistry, resolver, ROLES, X) │
     │                                     v                                    │
     │                              UserRegistry (deployed via                  │
     │                              VerifiableFactory, wired under              │
     │                              issuer.eth via setSubregistry)              │
     │                                                                          │
     │  ═══════════════════ swap path ═══════════════════                       │
     │                                                                          │
     │  Trader ─(Universal Router, permissioned deployment)─▶ PoolManager       │
     │                                          │                               │
     │                                          v                               │
     │                              PermissionedHooks (Uniswap-deployed)        │
     │                                          │ beforeSwap                    │
     │                                          v                               │
     │                                    PermissionsAdapter                    │
     │                                          │ checkAllowlist(msgSender(),   │
     │                                          │   PERMISSIONED_TOKEN)         │
     │                                          │   ^^^ = the END TRADER (✅)   │
     │                                          v                               │
     │                              ENSAllowlistChecker                         │
     │                                                                          │
     │  ═════════════════ liquidity path ════════════════                       │
     │                                                                          │
     │  LP ─▶ PermissionedPositionManager ──▶ checkAllowlist(RECIPIENT, token)  │
     │           │                                                              │
     │           └─▶ PoolManager ─▶ PermissionedHooks                           │
     │                                  │ beforeAddLiquidity                    │
     │                                  └─▶ checkAllowlist(CALLER, token)       │
     │                                                                          │
     │  (LIQUIDITY_ALLOWED is checked TWICE, on two different addresses.        │
     │   Decreases and burns are never gated.)                                  │
     │                                    │                                     │
     │                                    v                                     │
     │                     traverse: address → subname → parent → grandparent   │
     │                                                                          │
     │                     for each hop:  state = registry.getState(labelhash)  │
     │                       - state.status != REGISTERED     ? -> NONE         │
     │                       - state.expiry <= block.timestamp ? -> NONE        │
     │                                                                          │
     │                     on the LEAF hop only:                                │
     │                       - hasRoles(state.resource, ROLE_ELIGIBLE_SWAP) ?   │
     │                       - hasRoles(state.resource, ROLE_ELIGIBLE_LIQ)   ?  │
     │                                                                          │
     │                     assemble PermissionFlag from the leaf's role bits    │
     │                     (return NONE if ANY ancestor lapsed)                 │
     └──────────────────────────────────────────────────────────────────────────┘
```

### Contract list (all in a single Foundry project)

| Contract | Location | Responsibility |
|---|---|---|
| `ENSAllowlistChecker.sol` | `src/checker/` | `IAllowlistChecker` + ERC-165 impl. Traverses ENSv2 hierarchy for `account`, assembles `PermissionFlag`. **Load-bearing for Uniswap prize.** |
| `SubnameRegistrar.sol` | `src/registrar/` | Minimal registrar mirroring the docs' `SimpleSubnameRegistrar` shape, but registration is gated by a call from `MintAttestor`. |
| `MintAttestor.sol` | `src/cre/` | CRE receiver. **Inherits `ReceiverTemplate`** (forwarder gating + ERC-165 + metadata decode, from `SamAg19/LienFi`); adds the workflow-ID check the template omits, then calls `SubnameRegistrar.registerFromAttestation`. |
| `IssuerAllowlistCheckerFlat.sol` | `src/checker/` | Baseline flat checker (copied from KuCoin walkthrough) used only for gas benchmarks. Not shipped in the demo. |
| `Deploy.s.sol` | `script/` | Foundry deployment script. Sepolia only. |

**No custom v4 hook.** We use the Uniswap-deployed standard `PermissionedHooks` (Sepolia `0x51247E2291d290d17C08813A175AC86465EdE8c0`) and supply our checker to `createPermissionsAdapter`, with `updateAllowListChecker` available to swap it later. This is deliberate — the hook is not issuer-controlled per the standard, and reimplementing it means we'd be building our own hook against v4-core, which pulls the project into hook-writing scope we don't need.

**No custom position manager either.** Liquidity must go through the Uniswap-deployed `PermissionedPositionManager` (Sepolia `0xf99D553912084c99F6299291b75Fe9B7119Aa1A7`); the standard v4 `PositionManager` will not work against a permissioned pool. `console/lib/uniswap.ts` and every liquidity test target this address.

**Caller vs. recipient on mint.** Because `LIQUIDITY_ALLOWED` is checked against both the caller and the recipient, our demo has `mm.brokerA.issuer.eth` **mint for itself** (caller == recipient), so a single ENS name and a single role grant satisfy both checks. If the console ever mints on a user's behalf, the console's own address would also need a live name with `ROLE_ELIGIBLE_LIQUIDITY` — an easy trap, deliberately avoided rather than solved.

### The console talks to the chain directly — no Uniswap-hosted services

We depend on no Uniswap off-chain infrastructure. All three pieces the console needs are deployed contracts on Sepolia:

| Need | Contract | Sepolia |
|---|---|---|
| Swaps | Universal Router (permissioned deployment) | `0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7` |
| Quotes | `V4Quoter` (via `eth_call`) | `0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227` |
| Liquidity | `PermissionedPositionManager` | `0xf99D553912084c99F6299291b75Fe9B7119Aa1A7` |

**We need no routing API.** Path-finding services exist to search multi-hop routes across thousands of pools; we have exactly one pool and know its `PoolKey` at build time, so the swap is a directly-encoded v4 command sequence.

Two integration details that will cost an afternoon each if missed:

1. **The wrapper approvals are load-bearing for the frontend, not just for setup.** If `updateAllowedWrapper` was not called for the router and the quoter, every console action fails — and it fails in a way that looks like a bug in `ENSAllowlistChecker`. Verify these are set before debugging the checker, ever.
2. **The pool's currency is the adapter address, not the underlying token.** The pool trades the virtual token the adapter mints; the investor's wallet holds the underlying. `console/lib/uniswap.ts` must be explicit about which of the two each balance, approval and `PoolKey` field refers to. Getting this wrong produces "insufficient balance" against a wallet that visibly holds funds.

### The reverse-lookup problem and how we solve it

`IAllowlistChecker.checkAllowlist(account, tokenAddress)` gives us an **address**, but ENSv2 subnames are identified by labelhash + registry. We need a fast address→name lookup.

Options considered:
1. **Store a mapping in the checker itself** on registration. Rejected because it duplicates authoritative state and drifts when names change ownership.
2. **Query `UniversalResolverV2` reverse resolution.** ENSv2 supports reverse resolution via the `DefaultReverseRegistrarAdapter` at `0x7a84e241f862d73960d73c26d68c3c8f89f0b18f`. But reverse resolution is user-set and unreliable — an investor might not have set their primary name to `alice.brokerA.issuer.eth`.
3. **Chosen:** the investor's on-chain address is emitted by the registrar at mint time and stored in a **thin index contract** (`AddressToNameIndex`) inside the checker. This keeps the source of truth in ENSv2 but caches the name path derived at mint. On every check we still **re-read `getState()` fresh from the registries** for status/expiry/roles — the cache holds only the (labelhash, registry) path, not the state.

Cache invalidation: if an investor is transferred or reassigned, we listen to `TokenRegenerated` events off-chain and rebuild. For the hackathon demo, since transfers don't happen in the money-shot, this is fine and documented.

### Traversal algorithm (spec)

Given `account`:

**Verified against source Sep 5.** The Rev-1 shape was right; Rev 2 briefly "corrected" it wrongly and is reverted here.

```
1.  Look up path = index[account]  // (labelhash, registryAddress) from investor up to issuer
2.  If path is empty → return PermissionFlags.NONE
3.  For each hop from investor up to issuer:
     a. state = IPermissionedRegistry(hop.registry).getState(hop.labelhash)
     b. If state.status != Status.REGISTERED → return NONE
     c. If state.expiry <= block.timestamp    → return NONE   // _isExpired is >=
     d. If hop is the leaf (investor):
          hasSwap = registry.hasRoles(state.resource, ROLE_ELIGIBLE_SWAP, account)
          hasLiq  = registry.hasRoles(state.resource, ROLE_ELIGIBLE_LIQUIDITY, account)
4.  flag = (hasSwap ? SWAP_ALLOWED : NONE) | (hasLiq ? LIQUIDITY_ALLOWED : NONE)
5.  Return flag
```

**No manual resource derivation.** `getState` returns `resource` directly, and `PermissionedRegistry.hasRoles(uint256 anyId, ...)` resolves `getResource()` internally anyway — so a raw labelhash would work too. Passing `state.resource` is the clearest form.

**Why we still re-read every call rather than caching.** `resource = withVersion(labelhash, eacVersionId)`, and `_constructResource` returns `eacVersionId + 1` whenever the name is expired. So a cached resource would keep matching grants that the registry itself has already moved past. We cache only `(labelhash, registry)` — both stable — and read the rest fresh. Same reasoning for token IDs, which churn on *every* role grant.

**Both status and expiry are checked** even though `status` is derived from expiry and ownership. `_constructStatus` folds in `latestOwner`, so an unregistered-but-unexpired entry is caught by the status test and not by the expiry test. Cheap, and it fails closed.

Cost: **one `getState` per hop** plus exactly **two `hasRoles` calls total**, on the leaf only. For `investor.broker.issuer` that is 3 `getState` + 2 `hasRoles`. Note `hasRoles` internally calls `getResource`, so it is not quite free. Still the item benchmarked in Gate 1 / Day 7.

**Non-cacheable rule (from ENS docs):** "A name's resolver is its owner's own deployment — look it up fresh at write time, never hardcode or cache. Same for subregistries." We honour this for subregistry pointers; the address→(labelhashes, registries) path index is a distinct thing.

### Data model — issuer.eth namespace

```
issuer.eth                              ← registered on ETHRegistry, owned by IssuerMultisig
  ├─ subregistry: IssuerRootRegistry    (UserRegistry proxy)
  │
  ├─ brokerA.issuer.eth                 ← subname, expiry = 1 year
  │    ├─ subregistry: BrokerARegistry  (UserRegistry proxy)
  │    ├─ alice.brokerA.issuer.eth      ← subname, roles = {ELIGIBLE_SWAP}
  │    └─ mm.brokerA.issuer.eth         ← subname, roles = {ELIGIBLE_SWAP, ELIGIBLE_LIQUIDITY}
  │
  └─ brokerB.issuer.eth                 ← subname, expiry = 1 year
       ├─ subregistry: BrokerBRegistry
       └─ bob.brokerB.issuer.eth        ← subname, roles = {ELIGIBLE_SWAP}
```

**Role definitions we introduce** (custom roles allowed within EAC 32 regular + 32 admin per resource):
```solidity
uint256 constant ROLE_ELIGIBLE_SWAP      = 1 << 64;  // nybble 16
uint256 constant ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;  // nybble 17
```

✅ **Gate 3 closed from source Sep 5.** The original `1 << 4` / `1 << 8` did collide — with `ROLE_REGISTER_RESERVED` (nybble 1) and `ROLE_SET_PARENT` (nybble 2). The values above sit in the free range (nybbles 10–29). Full assigned-role table in §0.

### CRE workflow, concretely

**Verified Sep 5** — the confidential surface against the CRE docs (concepts / TS guide / SDK reference), the EVM-report-and-receiver surface against `SamAg19/LienFi`.

```ts
import { handlerInTee, HTTPClient, EVMClient, getNetwork, hexToBase64,
         TxStatus, Runner, type TeeRuntime, type EVMLog } from "@chainlink/cre-sdk"
import { encodeAbiParameters, parseAbiParameters } from "viem"

const initWorkflow = (config: Config) => {
  const evmClient = new EVMClient(network.chainSelector.selector)
  return [
    handlerInTee(
      // The trigger is NOT confidential — triggers always execute on Workflow
      // DON nodes. Never put PII in the event.
      evmClient.logTrigger({
        addresses: [hexToBase64(applicationRegistryAddress)],
        topics: [{ values: [hexToBase64(APPLICATION_SUBMITTED_TOPIC)] }],
      }),
      onApplicationSubmitted,
      {},                    // TeeConstraint: any registered TEE, any region
    ),
  ]
}

const onApplicationSubmitted = (runtime: TeeRuntime<Config>, log: EVMLog) => {
  // ── inside the enclave ──────────────────────────────────────────────
  // THE RULEBOOK LIVES HERE AS A SECRET, NOT AS SOURCE CODE.
  // Source and binary are explicitly NOT confidential (§0) and our repo is
  // public by prize requirement. Only Vault-DON secrets are protected.
  const secrets = runtime.getSecrets([
    { id: "KYC_API_TOKEN" },
    { id: "ELIGIBILITY_RULEBOOK" },   // thresholds, tier boundaries, jurisdictions
  ]).result()

  const resp = new HTTPClient().sendRequest(runtime, {
    url: runtime.config.kycUrl,
    method: "POST",
    multiHeaders: { Authorization: { values: [`Bearer ${secrets["KYC_API_TOKEN"].value}`] } },
  }).result()

  // Generic evaluator; every discriminating value comes from the secret.
  const verdict = evaluate(resp, JSON.parse(secrets["ELIGIBILITY_RULEBOOK"].value))

  // ── crossing back out ───────────────────────────────────────────────
  // Everything past this line runs on Workflow DON nodes and is NOT
  // confidential. Cross ONLY the verdict — never the KYC payload.
  const donRuntime = runtime.usingTheDons()

  // Flat, statically-typed ABI tuple. No dynamic arrays.
  const reportData = encodeAbiParameters(
    parseAbiParameters(
      "address wallet, bytes32 labelBytes, address brokerRegistry, uint256 roleBitmap, uint64 expiry, bool approved"
    ),
    [wallet, labelBytes, brokerRegistry, verdict.roleBitmap, verdict.expiry, verdict.approved]
  )

  const report = donRuntime.report({
    encodedPayload: hexToBase64(reportData),
    encoderName: "evm",
    signingAlgo: "ecdsa",
    hashingAlgo: "keccak256",
  }).result()

  const writeResult = evmClient.writeReport(donRuntime, {
    receiver: mintAttestorAddress,
    report,
    gasConfig: { gasLimit },
  }).result()
  if (writeResult.txStatus !== TxStatus.SUCCESS) throw new Error(`writeReport failed: ${writeResult.txStatus}`)
}
```

`TeeRuntime` also exposes `reportFromDon(...)` as a one-step alternative to `usingTheDons().report(...)`. Either works; the explicit `donRuntime` form is clearer about where the confidentiality boundary sits, which matters in a demo we have to narrate.

#### What is and is not confidential — state this precisely

| | Confidential? |
|---|---|
| Applicant PII from the KYC endpoint | ✅ fetched and evaluated inside the enclave |
| Eligibility thresholds / tier rules | ✅ **only because they are Vault-DON secrets**, not source |
| `main.ts` source and compiled binary | ❌ explicitly excluded — and our repo is public |
| The trigger event | ❌ always executes on Workflow DON nodes |
| The on-chain report | ❌ which is exactly why it carries only the verdict |

The honest one-liner: **"the code is public, the criteria are not, and the applicant's data never leaves the enclave."** Claiming the *logic* is confidential merely because it runs in a TEE is the specific overclaim the docs warn against — *"your handler's source code and compiled binary are not confidential just because part of its logic runs inside an enclave"* — and a Chainlink judge will know it.

**Which mechanism:** build on **Confidential Workflows** (`handlerInTee`). It is what §1 actually describes, and since simulation needs no enrollment it does not block us. **Confidential HTTP** is the fallback if `handlerInTee` misbehaves under simulation — LienFi proves that path works end-to-end on Sepolia.

#### Running it

The demo runs via `cre workflow simulate … --broadcast`, which produces a **real KeystoneForwarder transaction on Sepolia**. Stage a mock KYC endpoint returning deterministic responses per `applicationId` so the demo is repeatable. `project.yaml` needs only:

```yaml
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
```

Per-workflow `workflow.yaml` points at `main.ts`, `config.staging.json` and a shared `../secrets.yaml`.


---

## 3. Sponsor requirements checklist

**Uniswap Foundation** — from the prize brief:
- [ ] Public GitHub repo ✅ (implied)
- [ ] `FEEDBACK.md` in the repo root
- [ ] Completed submission at `developers.uniswap.org/hackathon-feedback` linking to `FEEDBACK.md`
- [ ] README clearly points to the relevant contracts and lines of code
- [ ] One README sentence on routing: *"Routing allowlisting is a separate Uniswap Labs process for their hosted interface; it is out of scope for this demo and is not part of the integration surface."* Not a limitation to apologise for — the console is the demo surface by design, since no swap UI can render an ENS hierarchy, role bits, or an expiry countdown.

**ENS** — from the prize brief:
- [ ] Built on ENSv2 (Sepolia) ✅
- [ ] ENSv2 features **central**, not cosmetic ✅ (checker traversal, EAC roles, expiry, hierarchical registries — all load-bearing)
- [ ] Demo functional, not hard-coded values ✅
- [ ] Video **or** live demo (both if possible)
- [ ] Open source

**Chainlink CRE** — from the prize brief (qualification "coming soon" as of Sep 3):
- [ ] Uses CRE Confidential Workflow ✅
- [ ] Check Chainlink Discord on Sep 4 for the published qualification version
- [ ] Include README section documenting the enrollment path since we demo on simulator

**General:**
- [ ] Proper git commit history — **no single-commit final-day entries**. Both builders commit daily starting Sep 4.

---

## 4. Verification gates

### Cleared on Sep 5 by documentation review (no code written)

| Old # | Gate | Outcome |
|---|---|---|
| 2 | Confirm exact `IAllowlistChecker` signature | ✅ **PASS.** `checkAllowlist(address account, address tokenAddress) external view returns (PermissionFlag)` confirmed verbatim against the official deploy guide's reference checker. Our §5 signature is correct. |
| 3 | Are Permissioned Pools contracts deployed on Sepolia? | ✅ **PASS.** Factory, position manager, hooks, router and both quoters are all live on Sepolia (addresses in §0). We deploy none of it. Old risk #2 is retired and ~1 day of contingency is released back into the schedule. |

### Closed on Sep 5 by reading contract source

| Question | Outcome |
|---|---|
| 🔴 **Gate 2 — which address reaches `checkAllowlist`** | ✅ **PASS — the end trader.** `PermissionedV4Router._pay`/`._take` and `PermissionedPositionManager._pay` pass `msgSender()`; `_checkRecipientAllowed` passes `recipient`. `PermissionsAdapter.isAllowed` forwards either into `checkAllowlist`. **The architecture stands.** |
| 🔴 **Gate 3 — role-bit collision** | ❌ **FAIL as specced, now fixed.** `1 << 4` = `ROLE_REGISTER_RESERVED`, `1 << 8` = `ROLE_SET_PARENT`. Moved to nybbles 16/17 (`1 << 64`, `1 << 68`) from the free range 10–29. |
| 🟢 **Gate 4 — on-camera lapse** | ✅ **PASS.** No parent clamp on subname expiry; only `CannotSetPastExpiry`. A ~10-minute `brokerA` expiry is registrable on live Sepolia. No Anvil fork needed. |
| Parent-expiry cascade | ✅ **Real and enforced in-registry** — `getSubregistry`/`getResolver` return `address(0)` once expired. Our per-hop walk agrees independently. |
| Real `State` / `Status` | ✅ Rev-1 was right; **Rev 2's "correction" was my error** (it described the internal `Entry`). Reverted. `resource` is `uint256`; `Status` has no `EXPIRED` member. |
| Resource derivation | ✅ Handled by the registry. `hasRoles` takes `anyId` and resolves internally — no manual bit-twiddling. Expired names report `eacVersionId + 1`, so stale grants fail closed. |
| `PermissionFlag` type | 🔴 **`bytes2`, not `uint16`.** Rev-1's flag assembly would not compile. Uses global `\|`/`&`/`==` operators. |
| ENS deployment addresses | 🔴 **All ten were wrong** — there is a separate dedicated hackathon deployment. Replaced in §0. |

### Still open

| # | Gate | Who | Pass criterion | If it fails |
|---|---|---|---|---|
| 1 | Gas cost of an on-chain ENSv2 hierarchy walk from a contract on Sepolia | A | 3-hop walk ≤ 120k gas | Cache path in index with stale bound (already planned); if per-hop is >40k, drop to 2-hop hierarchy (issuer → investor, no broker layer) |
| 5 | `cre init` fresh template + `cre workflow simulate --broadcast` end-to-end, landing a forwarder tx on Sepolia. Diff the generated SDK shapes against §2 (LienFi's are ~6 months old) | B | A simulated confidential workflow writes a real Sepolia transaction | Fall back to Confidential HTTP (LienFi's proven path). Beta enrollment is **not** required either way |

**Every architecture-breaking question is now closed.** Gate 1 is a performance question with a known fallback. Gate 5 is a "does the tooling still look like this" question, not a "does this work" question — `--broadcast` writing to Sepolia is already proven by a working project. There is no remaining scenario that forces a pivot to Recall or Assign.

---

## 5. Solidity signatures we're committing to now

### `IAllowlistChecker` (Uniswap) — what we implement

✅ **Confirmed verbatim Sep 5** against the official deploy guide. Exact import paths:

```solidity
import {IAllowlistChecker} from "@uniswap/v4-periphery/src/hooks/permissionedPools/interfaces/IAllowlistChecker.sol";
import {PermissionFlag, PermissionFlags} from "@uniswap/v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

interface IAllowlistChecker {
    function checkAllowlist(address account, address tokenAddress)
        external view returns (PermissionFlag);
}
```

### `PermissionFlag` and library (Uniswap)

✅ **Verified from source Sep 5.** It is `bytes2`, not `uint16`, and it ships global operators:

```solidity
// From @uniswap/v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol
type PermissionFlag is bytes2;

using {or as |} for PermissionFlag global;
using {and as &} for PermissionFlag global;
using {eq as ==} for PermissionFlag global;

library PermissionFlags {
    PermissionFlag constant NONE              = PermissionFlag.wrap(0x0000);
    PermissionFlag constant SWAP_ALLOWED      = PermissionFlag.wrap(0x0001);
    PermissionFlag constant LIQUIDITY_ALLOWED = PermissionFlag.wrap(0x0002);
    PermissionFlag constant ALL_ALLOWED       = PermissionFlag.wrap(0xFFFF);
}
```

### `IPermissionedRegistry` (ENSv2) — what we call

✅ **Verified from source Sep 5** (`contracts/src/registry/interfaces/IPermissionedRegistry.sol`). Rev 2 briefly replaced this with the internal `Entry` struct by mistake; this is the real one.

```solidity
// From @ensdomains/contracts-v2/contracts/src/registry/interfaces/IPermissionedRegistry.sol
interface IPermissionedRegistry {
    enum Status { AVAILABLE, RESERVED, REGISTERED }   // NB: no EXPIRED member

    struct State {
        Status  status;        // getStatus()
        uint64  expiry;        // getExpiry()
        address latestOwner;   // latestOwnerOf()
        uint256 tokenId;       // getTokenId()
        uint256 resource;      // getResource()  -- uint256, not bytes32
    }

    function register(
        string calldata label,
        address owner,
        IRegistry subregistry,   // address(0) if no child registry
        address resolver,
        uint256 roleBitmap,      // roles granted to owner on the new name
        uint64 expiry            // ABSOLUTE unix timestamp
    ) external returns (uint256 tokenId);

    function renew(uint256 anyId, uint64 newExpiry) external;

    function getState(uint256 anyId) external view returns (State memory);

    // PermissionedRegistry OVERRIDES this to take anyId (labelhash | tokenId |
    // resource) and resolve getResource() internally. Pass state.resource.
    function hasRoles(uint256 anyId, uint256 roleBitmap, address account)
        external view returns (bool);

    function getResource(uint256 anyId) external view returns (uint256 resource);
    function getStatus(uint256 anyId) external view returns (Status status);

    function setSubregistry(uint256 anyId, address subregistry) external;

    function grantRootRoles(uint256 roleBitmap, address account) external returns (bool);
}

interface IRegistry {
    // Takes a LABEL STRING, not a labelhash. We avoid needing this — getState
    // already hands back the subregistry pointer.
    function getSubregistry(string calldata label) external view returns (IRegistry);
    function getResolver(string calldata label) external view returns (address);
}
```

### `ETHRegistrar` (ENSv2) — registering `issuer.eth` itself

A **different call with different conventions** from subname registration, and the plan previously conflated the two.

```solidity
// Commit–reveal is MANDATORY:
//   1. commit(makeCommitment(...))
//   2. wait MIN_COMMITMENT_AGE = 60 seconds  (commitment dies after ~24h)
//   3. register(...) with identical params
ETHRegistrar.register(
    string label,
    address owner,
    bytes32 secret,
    IRegistry subregistry,
    address resolver,
    uint64 duration,        // SECONDS, not an absolute expiry. MIN_REGISTER_DURATION applies.
    IERC20 paymentToken,    // ENS MockUSDC 0xcbfd80f74375c54e545af34788ff465f96f66f05
    bytes32 referrer
);

ETHRegistrar.renew(string label, uint64 duration, IERC20 paymentToken, bytes32 referrer);
```

Costs real money: 5+ character names are $8/yr. Pick a 5+ character parent name. Budget for the payment token before Day 3.

### Our new roles

```solidity
// src/checker/LedgerRoles.sol
library LedgerRoles {
    // VALUES VERIFIED against RegistryRolesLib.sol (contracts-v2) on Sep 5.
    //
    // Roles are one 4-bit nybble each: constants are 1 << (4 * N).
    // Regular roles occupy bits 0-127; the admin twin of a role is ROLE << 128.
    //
    // RegistryRolesLib assigns nybbles 0-9 and 30-31:
    //   0 REGISTRAR   1 REGISTER_RESERVED  2 SET_PARENT   3 UNREGISTER
    //   4 RENEW       5 SET_SUBREGISTRY    6 SET_RESOLVER 7 CAN_TRANSFER(admin)
    //   8 WAS_RESERVED 9 SET_URI          30 CAN_NAME    31 UPGRADE
    //
    // Nybbles 10-29 are free. We take 16 and 17 — mid-range, well clear of both
    // the assigned low block and the reserved 30/31 upgrade roles.
    //
    // The earlier values (1 << 4, 1 << 8) COLLIDED with ROLE_REGISTER_RESERVED
    // and ROLE_SET_PARENT respectively. Do not reintroduce them.
    //
    // DO NOT grant these on ROOT_RESOURCE (0x0) as an "optimisation". Each
    // role nybble stores a COUNT capped at 15, so a shared resource caps the
    // entire product at 15 eligible investors. One resource per name is the
    // only design that scales.
    uint256 constant ROLE_ELIGIBLE_SWAP      = 1 << 64;   // nybble 16
    uint256 constant ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;   // nybble 17
}
```

### `ENSAllowlistChecker` (our contract)

```solidity
// src/checker/ENSAllowlistChecker.sol
contract ENSAllowlistChecker is IAllowlistChecker, ERC165 {
    struct PathHop {
        uint256 labelhash;
        address registry;
    }

    // Populated by MintAttestor at mint time. Cache is NAME PATH ONLY —
    // status/expiry/roles are always re-read from registries.
    mapping(address account => PathHop[]) internal path;
    address public immutable MINT_ATTESTOR;

    error OnlyMintAttestor();

    modifier onlyAttestor() {
        if (msg.sender != MINT_ATTESTOR) revert OnlyMintAttestor();
        _;
    }

    constructor(address mintAttestor) {
        MINT_ATTESTOR = mintAttestor;
    }

    // Called by MintAttestor on successful CRE-attested mint.
    function recordPath(address account, PathHop[] calldata newPath) external onlyAttestor {
        delete path[account];
        for (uint256 i = 0; i < newPath.length; i++) {
            path[account].push(newPath[i]);
        }
    }

    /// @inheritdoc IAllowlistChecker
    function checkAllowlist(address account, address /* tokenAddress */)
        external view returns (PermissionFlag)
    {
        PathHop[] memory p = path[account];
        if (p.length == 0) return PermissionFlags.NONE;

        // Walk from investor up to issuer.
        // p[0] = investor, p[p.length - 1] = issuer.
        bool hasSwap;
        bool hasLiq;

        for (uint256 i = 0; i < p.length; i++) {
            IPermissionedRegistry registry = IPermissionedRegistry(p[i].registry);
            IPermissionedRegistry.State memory state = registry.getState(p[i].labelhash);

            // Any lapsed or non-registered ancestor collapses the whole subtree.
            // status folds in ownership; expiry is checked separately so that an
            // unregistered-but-unexpired entry cannot slip through.
            if (state.status != IPermissionedRegistry.Status.REGISTERED) {
                return PermissionFlags.NONE;
            }
            if (state.expiry <= block.timestamp) {
                return PermissionFlags.NONE;
            }

            // Only capture role bits on the leaf (investor).
            if (i == 0) {
                // state.resource is version-stamped by the registry; an expired
                // name reports eacVersionId + 1, so stale grants cannot match.
                hasSwap = registry.hasRoles(state.resource, LedgerRoles.ROLE_ELIGIBLE_SWAP, account);
                hasLiq  = registry.hasRoles(state.resource, LedgerRoles.ROLE_ELIGIBLE_LIQUIDITY, account);
            }
        }

        // PermissionFlag is bytes2 with a global `|` operator — assemble with
        // the operators, never via uint16 casts (which do not compile).
        PermissionFlag flag = PermissionFlags.NONE;
        if (hasSwap) flag = flag | PermissionFlags.SWAP_ALLOWED;
        if (hasLiq)  flag = flag | PermissionFlags.LIQUIDITY_ALLOWED;
        return flag;
    }

    // Override list must name both bases, per the docs' reference checker.
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC165, IERC165) returns (bool)
    {
        return interfaceId == type(IAllowlistChecker).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
```

✅ **`account` is the trader's address — Gate 2 closed from source.** `PermissionedV4Router` and `PermissionedPositionManager` both pass `msgSender()`, and the recipient check passes `recipient`; `PermissionsAdapter.isAllowed` forwards either straight into `checkAllowlist`. See §0.

Note `IAllowlistChecker` already extends `IERC165`, and v4-periphery ships a `BaseAllowListChecker` abstract we could inherit rather than hand-wiring ERC-165. Worth a look on Day 2 — inheriting the sponsor's own base contract is a small credibility win in a Uniswap-judged submission.

### `MintAttestor` (CRE receiver)

**Rewritten Sep 5** against `SamAg19/LienFi`'s `ReceiverTemplate.sol`, a working forwarder receiver on Sepolia. Two changes from the Sep-3 draft: inherit the template rather than hand-rolling `IReceiver`, and **drop the dynamic `PathHop[]` from the report** — every working CRE report is a flat, statically-typed ABI tuple.

```solidity
// src/cre/MintAttestor.sol
contract MintAttestor is ReceiverTemplate {
    ENSAllowlistChecker public immutable CHECKER;
    SubnameRegistrar   public immutable REGISTRAR;
    bytes32 public immutable EXPECTED_WORKFLOW_ID;

    error UnexpectedWorkflow(bytes32 workflowId);

    // ReceiverTemplate takes the KeystoneForwarder address and gates onReport on it.
    constructor(address forwarder, ENSAllowlistChecker checker, SubnameRegistrar registrar, bytes32 workflowId)
        ReceiverTemplate(forwarder)
    {
        CHECKER = checker;
        REGISTRAR = registrar;
        EXPECTED_WORKFLOW_ID = workflowId;
    }

    /// @dev metadata is abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner);
    ///      ReceiverTemplate._decodeMetadata unpacks it. Forwarder auth is already enforced by the base.
    function _processReport(bytes calldata metadata, bytes calldata report) internal override {
        (bytes32 workflowId, , ) = _decodeMetadata(metadata);
        if (workflowId != EXPECTED_WORKFLOW_ID) revert UnexpectedWorkflow(workflowId);

        // FLAT tuple — matches encodeAbiParameters/parseAbiParameters on the workflow side.
        // No dynamic arrays: CRE reports in practice carry scalars only.
        (
            address wallet,
            bytes32 labelBytes,      // the LABEL itself, not its hash - see note
            address brokerRegistry,
            uint256 roleBitmap,
            uint64  expiry,
            bool    approved
        ) = abi.decode(report, (address, bytes32, address, uint256, uint64, bool));

        if (!approved) return;   // REJECT verdicts are a no-op on-chain

        string memory label = LibLabelBytes.toString(labelBytes);
        REGISTRAR.registerFromAttestation(wallet, label, brokerRegistry, roleBitmap, expiry);
        CHECKER.recordPath(wallet, brokerRegistry, LibLabel.id(label));
    }
}
```

**Why `bytes32 labelBytes` and not a labelhash.** `IPermissionedRegistry.register` takes `string calldata label`, and a labelhash cannot be reversed. But `string` is a dynamic type, which the flat-report constraint rules out. So the report carries the **label itself right-padded into `bytes32`** and the receiver converts it back — demo labels (`alice`, `mm`, `retail`, `bob`) are far under 32 bytes. `LibLabelBytes.toString` is ~10 lines: trim trailing zero bytes, return the remainder. The checker then derives the labelhash on-chain via `LibLabel.id(label)` so the two can never disagree.

⚠️ **This caps investor labels at 32 bytes.** Fine for the demo and worth one line in `FEEDBACK.md`; a production system would put the label in a side mapping keyed by `applicationId` and have the report reference that key.

**How the path gets recorded without shipping an array.** The investor's path is always exactly three hops — `investor → broker → issuer` — and the checker already knows the issuer registry (it is deployment-time constant). So the report needs only the leaf `labelhash` and the `brokerRegistry` address; `recordPath` reconstructs the full walk. If the hierarchy ever needs to be deeper than three levels, the report gains one more `(labelhash, registry)` pair rather than an array.

Two consequences worth noting:
1. **`ReceiverTemplate` already does forwarder gating and ERC-165**, so the `onlyForwarder` modifier in the Sep-3 draft is redundant — the base's `onReport` reverts with `ReceiverTemplate__NotForwarder` before dispatching.
2. **Workflow-ID validation is ours to add.** The template decodes metadata but does not check it; without the `EXPECTED_WORKFLOW_ID` guard, *any* workflow routed through the same forwarder could mint subnames. This is the one piece of the receiver that is genuinely security-relevant and it is not in the template.

### `SubnameRegistrar` (mirrors ENS `SimpleSubnameRegistrar`, gated by MintAttestor)

```solidity
// src/registrar/SubnameRegistrar.sol
contract SubnameRegistrar {
    IPermissionedRegistry public immutable ISSUER_REGISTRY;   // root under issuer.eth
    address public immutable MINT_ATTESTOR;
    address public immutable RESOLVER;                        // shared PermissionedResolver

    modifier onlyAttestor() {
        if (msg.sender != MINT_ATTESTOR) revert OnlyMintAttestor();
        _;
    }

    // Called only by MintAttestor after a CRE APPROVE verdict.
    // Flat params, matching the flat CRE report tuple (no Verdict struct).
    function registerFromAttestation(
        address wallet,
        string calldata label,
        address brokerRegistry,
        uint256 roleBitmap,
        uint64  expiry
    ) external onlyAttestor returns (uint256 tokenId) {
        tokenId = IPermissionedRegistry(brokerRegistry).register(
            label,
            wallet,
            IRegistry(address(0)),      // investors have no child registry
            RESOLVER,
            roleBitmap,                 // ROLE_ELIGIBLE_SWAP | ROLE_ELIGIBLE_LIQUIDITY
            expiry
        );
    }
}
```

Two things to note about this shape (both intentional):
1. **Investors get their eligibility roles at registration.** No follow-up tx. The bitmap passed to `register()` is what `hasRoles` will report against.
2. **We do NOT grant `ROLE_SET_SUBREGISTRY` or `ROLE_CAN_TRANSFER_ADMIN` to investors.** They are leaves and non-transferable inside our system (position NFTs from the pool are already non-transferable per the Permissioned Pools standard — this makes it end-to-end).

---

## 6. Build plan — 10 days, 2 builders

Roles are as in the schedule from your Ideas file, with concrete Sep 4 gates baked in.

### Legend
- 🅰️ = Builder A (contracts/Solidity/Foundry)
- 🅱️ = Builder B (CRE/Privy/frontend/off-chain)
- 🔀 = Joint / integration
- 🎯 = Verification gate — do not pass without a green tick

### Sep 4 (Thu) — Day 1: verification & setup

| Time | Owner | Task | Deliverable |
|---|---|---|---|
| 0h–2h | 🔀 | Repo skeleton (Foundry + Next.js). `foundry.toml` with ENSv2 remappings. `forge install ensdomains/contracts-v2` and `forge install Uniswap/v4-periphery`. `.env.example` for RPCs and Sepolia key. First commit. | Empty but installable repo |
| 2h–6h | 🅰️ | 🎯 **Gate 1** (the only remaining contract-side gate): deploy a trivial contract that reads `getState(labelhash)` from the hackathon `ETHRegistry` on Sepolia. Measure gas for a 3-hop synthetic walk. | Green tick or drop to 2-hop |
| 2h–6h | 🅱️ | 🎯 **Gate 5:** `cre init --template=hello-confidential-workflows-ts`, then run `cre workflow simulate … --broadcast` end-to-end and confirm a forwarder tx lands on Sepolia. Diff the generated SDK shapes against §2 — LienFi's are ~6 months old (risk #21). Submit the beta request in Discord as a nice-to-have, **not a blocker**: simulation needs no enrollment. | Simulated workflow writing to Sepolia |
| 1h–2h | 🅱️ | Acquire ENS `MockUSDC` (`0xcbfd80f7…f05`, hackathon deployment) on Sepolia — it is the **ETHRegistrar payment token** and silently blocks Day 3. Pick a 5+ character parent name ($8/yr tier). | Funded registrant wallet |
| 2h–3h | 🅰️ | Vendor the source we verified against so the team reads the same code the spec was written from: `forge install ensdomains/contracts-v2 Uniswap/v4-periphery`. Sanity-check that `RegistryRolesLib`, `IPermissionedRegistry` and `PermissionFlags` match §0/§5 at the pinned commit. | Pinned deps, spec confirmed |
| 6h–8h | 🔀 | Stand-up: Gate 1 + Gate 5 review | Go/no-go recorded in README |

> **Status Sep 5 — Gates 2, 3 and 4 are closed and need no Day-1 time.** They were resolved by reading `Uniswap/v4-periphery` and `ensdomains/contracts-v2` source: `account` is the end trader, our role bits collided and have been moved, and the on-camera lapse works on live Sepolia. See §4. Old Gates for the interface signature and Sepolia deployment were cleared earlier by documentation review. **No open question can now force a pivot** — Day 1 is setup plus one performance measurement.

### Sep 5 (Fri) — Day 2: skeletons

| Owner | Task |
|---|---|
| 🅰️ | Write `LedgerRoles.sol`, `ENSAllowlistChecker.sol` (hardcoded trivial path first, no attestor gating yet), Foundry tests for hierarchy walk with mocked registries |
| 🅱️ | **Use the live Sepolia factory — no self-deploy needed.** Full path: deploy a permissioned test token with an issuer allowlist → `factory.createPermissionsAdapter(token, issuerAdmin, IssuerAllowlistCheckerFlat)` at `0xE6B0d9...` → allowlist the adapter on the token → transfer 1 wei → `depositForVerification(1)` → `updateAllowedWrapper` for `PermissionedPositionManager`, Universal Router, `V4Quoter`, `MixedRouteQuoterV2` → `updateAllowedHook(PermissionedHooks, true)` → create the pool with the adapter as currency → `updateSwappingEnabled(true)` → end-to-end swap with the flat checker |
| 🔀 | End-of-day: swap works with flat checker; hierarchy walk passes tests |

### Sep 6 (Sat) — Day 3: real ENSv2 wiring

| Owner | Task |
|---|---|
| 🅰️ | Foundry integration test against **live ENSv2 Sepolia**. Register the parent via `ETHRegistrar` — **this is a 3-step commit–reveal, not one call**: `commit(makeCommitment(...))` → wait 60s (`MIN_COMMITMENT_AGE`) → `register(label, owner, secret, subregistry, resolver, duration_in_seconds, MockUSDC, referrer)`, paying $8/yr in `MockUSDC`. Use a 5+ char name (`ledger-demo-<n>.eth`). Then: deploy a `UserRegistry` via `VerifiableFactory`, `initialize()` with `ROLE_REGISTRAR_ADMIN \| ROLE_RENEW_ADMIN`, wire under the parent via `setSubregistry`, register `brokerA` **with a short expiry for the demo lapse**, deploy the broker `UserRegistry`, wire under `brokerA`, register `alice` with `ROLE_ELIGIBLE_SWAP`. Subname registration is the *other* call — `IPermissionedRegistry.register`, absolute expiry, no payment, no commit–reveal |
| 🅱️ | Issuer console skeleton (Next.js): sign in with Privy embedded wallet, "Submit application" form. Backend endpoint stub that queues the CRE workflow |
| 🔀 | End-of-day: real Sepolia hierarchy exists; walking it from `ENSAllowlistChecker` returns correct flags |

### Sep 7 (Sun) — Day 4: CRE verdict → mint path

| Owner | Task |
|---|---|
| 🅰️ | Write `MintAttestor.sol` and `SubnameRegistrar.sol`. Wire `ENSAllowlistChecker.recordPath` behind `onlyAttestor`. Deploy all three on Sepolia. Grant `ROLE_REGISTRAR` on each broker's `UserRegistry` to `SubnameRegistrar` (via `grantRootRoles`) |
| 🅱️ | Build the workflow per §2: `handlerInTee(evmClient.logTrigger(...), onApplicationSubmitted, {})`; inside the enclave `runtime.getSecrets([KYC_API_TOKEN, ELIGIBILITY_RULEBOOK])` and call the mock KYC endpoint; **put the rulebook thresholds in the Vault-DON secret, not in `main.ts`** (risk #20 — the source is public and explicitly unprotected); cross back via `usingTheDons()`, encode the **flat** ABI tuple, `evmClient.writeReport` to the Sepolia MintAttestor. Run with `--broadcast`. |
| 🔀 | End-of-day: `cre workflow simulate` produces an APPROVE verdict, `writeReport` lands on Sepolia MintAttestor, MintAttestor writes to registrar, subname minted, `ENSAllowlistChecker.checkAllowlist(alice_address, USDC)` returns `SWAP_ALLOWED` |

### Sep 8 (Mon) — Day 5: expiry, adversarial, invariants

| Owner | Task |
|---|---|
| 🅰️ | Foundry `warp`-based tests: expire `brokerA.issuer.eth` → verify `checkAllowlist` for both `alice` and `mm` returns 0. Expire `alice` only → verify `mm` still works. Register `mm.brokerA.issuer.eth` with both roles, test bit assembly. Adversarial: forge event decode with malicious path (should revert or return 0) |
| 🅱️ | CRE workflow: REJECT path (score below threshold → no `writeReport`, or emit REJECT verdict that MintAttestor filters). Second broker `brokerB.issuer.eth` registered end-to-end |
| 🔀 | End-of-day: the money-shot demo runs on the CLI via cast scripts |

### Sep 9 (Tue) — Day 6: swap-path end-to-end

| Owner | Task |
|---|---|
| 🅰️ | **The checker swap is an on-camera beat:** the adapter was created on Day 2 with the flat checker; now call `PermissionsAdapter.updateAllowListChecker(ENSAllowlistChecker)` and the same pool becomes hierarchically permissioned with one transaction. Full swap flow: mint the permissioned token to `alice`, approve the permissioned Universal Router (`0x54C707...`), execute swap. Verify `addLiquidity` via **`PermissionedPositionManager`** (`0xf99D55...`, *not* the standard v4 `PositionManager`) reverts for `alice` and succeeds for `mm` minting **to itself** (caller == recipient, since `LIQUIDITY_ALLOWED` is checked against both) |
| 🅱️ | Issuer console v1: application form, list of active brokers with expiry countdown, list of active investors per broker, ability to expire a broker (for the demo) via `pause` or by fast-forwarding block time on a local Anvil mirror (Sepolia can't be time-warped) |
| 🔀 | End-of-day: full user story executes on-chain on Sepolia |

### Sep 10 (Wed) — Day 7: gas benchmarks & polish

| Owner | Task |
|---|---|
| 🅰️ | Gas benchmark harness: measure `checkAllowlist` gas for 10 / 1,000 / 10,000 investors registered. Compare to `IssuerAllowlistCheckerFlat` baseline. Produce `bench/RESULTS.md` |
| 🅱️ | Console polish: two-tier investor view (retail vs MM), on-chain event stream (registrations + attestations), attestation trail per subname (workflow ID + report hash) |

### Sep 11 (Thu) — Day 8: integration, docs, adversarial retests

| Owner | Task |
|---|---|
| 🅰️ | Adversarial retests: role-nybble collision test (verify our custom roles don't accidentally trigger `RegistryRolesLib` behaviour), token-regeneration test (mint → cause a role change → `TokenRegenerated` → checker still works because we don't cache token IDs) |
| 🅱️ | `FEEDBACK.md` first draft. README with "Relevant Contracts and Lines of Code" section for Uniswap. |

### Sep 12 (Fri) — Day 9: video + submission form

| Owner | Task |
|---|---|
| 🅰️ | Record demo video (target 90 seconds): retail swap, retail addLiquidity revert, MM both operations, broker name lapse, both investors cut off. |
| 🅱️ | Submit `developers.uniswap.org/hackathon-feedback` with FEEDBACK.md link. Final README pass. |
| 🔀 | Practice the demo 3× live to confirm no flakiness |

### Sep 13 (Sat) — Day 10: submission + buffer

| Owner | Task |
|---|---|
| 🔀 | Submit on ETHGlobal portal. Buffer for any last-minute fixes. |

---

## 7. Repo layout

```
ledger/
├── contracts/                       (Foundry)
│   ├── src/
│   │   ├── checker/
│   │   │   ├── ENSAllowlistChecker.sol       ⭐ core Uniswap integration point
│   │   │   ├── IssuerAllowlistCheckerFlat.sol   (baseline for benchmarks only)
│   │   │   └── LedgerRoles.sol
│   │   ├── registrar/
│   │   │   └── SubnameRegistrar.sol
│   │   └── cre/
│   │       └── MintAttestor.sol
│   ├── script/
│   │   ├── DeployIssuerHierarchy.s.sol
│   │   ├── DeployChecker.s.sol
│   │   └── WirePermissionsAdapter.s.sol
│   ├── test/
│   │   ├── ENSAllowlistChecker.t.sol
│   │   ├── ExpiryCascade.t.sol
│   │   ├── AdversarialPath.t.sol
│   │   └── SwapIntegration.t.sol
│   ├── bench/
│   │   ├── GasBench.t.sol
│   │   └── RESULTS.md
│   └── foundry.toml
│
├── cre/                             (CRE workflow)
│   ├── my-workflow/
│   │   ├── workflow.ts              ⭐ handlerInTee, KYC scoring, verdict
│   │   ├── config.staging.json
│   │   ├── secrets.yaml
│   │   └── project.yaml             (Sepolia RPC preconfigured)
│   ├── kyc-mock/                    (deterministic mock endpoint)
│   │   └── server.ts
│   └── .env.example
│
├── console/                         (Next.js issuer console)
│   ├── app/
│   ├── components/
│   ├── lib/
│   │   ├── privy.ts
│   │   ├── ensv2.ts
│   │   └── uniswap.ts
│   └── package.json
│
├── FEEDBACK.md                      ⭐ Uniswap requirement
├── README.md                        ⭐ points to contract addresses + code lines
└── docs/
    ├── ARCHITECTURE.md              (this spec, condensed)
    ├── DEMO.md                      (money-shot script)
    └── CRE_ENROLLMENT.md            (production path)
```

---

## 8. Known risks and mitigations (honest list)

| # | Risk | Probability | Impact | Mitigation |
|---|---|---|---|---|
| 1 | ENSv2 tokenIDs mutate on role change → our path index breaks | ✅ **Confirmed Low Sep 5.** `tokenVersionId` bumps on *every* role grant/revoke, but we index by labelhash and never read token IDs | None | Still worth the explicit `TokenRegenerated` test on Sep 8 as a regression guard |
| 2 | ~~`PermissionsAdapter` not deployed on Sepolia~~ | — | — | ✅ **RETIRED Sep 5.** Factory, position manager, hooks, router and quoters are all live on Sepolia. ~1 day of contingency released. |
| 3 | CRE beta access not granted before Sep 13 | High (private beta) | ✅ **Zero — now verified.** Docs: *"Do not wait for early access. Simulate confidential workflows in minutes."* And `cre workflow simulate --broadcast` writes a real forwarder tx to Sepolia (proven in `SamAg19/LienFi`) | Run the demo on the simulator with `--broadcast`; README documents the production enrollment path |
| 20 | 🔴 **The rulebook is written in `main.ts` and is therefore public**, making "compliance without leaking rules" false | **High if unaddressed** — it is the natural way to write it, and our repo must be public | **High** — it is the CRE prize's whole premise | Rulebook thresholds live in the `ELIGIBILITY_RULEBOOK` Vault-DON secret; `main.ts` holds only a generic evaluator. Docs are explicit that source and binary are not protected. Verify on Day 4 by reading our own repo as a judge would |
| 21 | LienFi's SDK shapes (`EVMClient`, `writeReport`, `logTrigger`) are ~6 months old and may have drifted | Medium | Low — an afternoon of signature fixes | Day 1 runs a fresh `cre init` and diffs the generated template against §2 before any workflow code is written |
| 4 | 3-hop hierarchy walk exceeds beforeSwap gas budget | Low (estimate ~120k) | Medium | Fallback: 2-hop (issuer → investor, no broker layer) — loses "broker lapse" demo moment, so this is a real downgrade |
| 5 | `issuer.eth` (or the specific name we choose) is registered by someone else on Sepolia | Medium | Low | Pick a fresh name like `ledger-hack-<random>.eth`; the demo still works with any parent name |
| 6 | Sepolia RPC flakiness during live demo | Medium | High | Pre-cache a backup Alchemy + Infura key; script the demo idempotently so a re-run works |
| 7 | ~~Custom role bits collide with existing `RegistryRolesLib` roles~~ | — | — | ✅ **MATERIALISED AND FIXED Sep 5.** They did collide: `1<<4` = `ROLE_REGISTER_RESERVED`, `1<<8` = `ROLE_SET_PARENT`. Moved to nybbles 16/17. Residual risk is now only that ENS adds roles in 10–29 later — negligible for a hackathon |
| 8 | ~~`checkAllowlist` called with `tokenAddress` we haven't handled~~ | — | — | ✅ **RETIRED Sep 5.** Uniswap's own reference checker ignores `tokenAddress` and returns `permissions[account]`. Ignoring it is idiomatic. |
| 9 | Privy embedded wallet doesn't sign v4 swap transactions well on mobile | Medium | Low (desktop demo only) | Demo on desktop |
| 10 | Grant call ordering wrong (`grantRootRoles` requires `_ADMIN` variant) | Low, but subtle | Fatal to registration path | Follow the tutorial's setup script exactly; `UserRegistry.initialize()` bitmap must include `ROLE_REGISTRAR_ADMIN | ROLE_RENEW_ADMIN` |
| 11 | ~~`beforeSwap` passes the router as `account`, not the trader~~ | — | — | ✅ **RETIRED Sep 5.** Source confirms `msgSender()` — the end trader — on both swap and liquidity paths. The architecture is sound |
| 11b | Swaps that bypass the permissioned Universal Router skip the `SWAP_ALLOWED` check, since the gate lives in the router rather than a hook | Low for our demo (we control the client) | Low | Noted in §0. Our console routes everything through the permissioned Universal Router. Worth one sentence in `FEEDBACK.md` — the docs say `beforeSwap` enforces this and the source says the router does |
| 12 | Liquidity mint reverts because `LIQUIDITY_ALLOWED` is checked against **both** caller and recipient and we only provisioned one | Medium | Low — costs an afternoon of confusion | Demo has `mm` mint to itself so caller == recipient. Documented in §2; do not let the console mint on a user's behalf |
| 13 | Demo overclaims that expiry "freezes" investors, when decreases and burns are never gated | Was High before Sep 5 | Medium — a knowledgeable judge catches it | Script says "can no longer trade or add exposure." Call the withdrawal carve-out out loud in the video as a design property |
| 14 | ~~Money shot needs a lapse, but Sepolia cannot be time-warped~~ | — | — | ✅ **RETIRED Sep 5.** No minimum subname duration and no parent clamp — register `brokerA` with a ~10-minute expiry and let it lapse on live Sepolia. Anvil fallback dropped |
| 17 | ~~Checker computes the resource wrongly~~ | — | — | ✅ **RETIRED Sep 5.** No manual derivation exists: `getState` returns `resource`, and `hasRoles` takes `anyId` and resolves internally. Keep the re-registration Foundry test anyway — it is the cheapest proof of the expiry story |
| 19 | This spec's Solidity was written against docs and read source, but **has never been compiled** | High — three transcription-level errors were already found this way (`uint16` vs `bytes2`, `State` vs `Entry`, colliding role bits) | Low individually, but they cost debugging time on Day 2 | Day 1 vendors both dependencies at pinned commits and diffs §0/§5 against the real files. Treat every signature in §5 as "verified by reading", not "verified by compiling", until Day 2 |
| 18 | Day 3 blocked on not having the `ETHRegistrar` payment token | Medium | Half a day | Acquire `MockUSDC` on Day 1 (added to §6). Pick a 5+ char name to stay in the $8/yr tier |
| 15 | Missing `updateAllowedWrapper` / `updateAllowedHook` approvals present as checker bugs | Medium | Low, but burns hours in the wrong file | Assert all five approvals in the deploy script and re-assert them in a console health check. First debugging question for any permission failure is "are the wrappers registered?", not "is the checker wrong?" |
| 16 | Console confuses the virtual token (pool currency = adapter) with the underlying (wallet balance) | Medium | Low | Name them distinctly in `console/lib/uniswap.ts`; never let a variable be called just `token` |

---

## 9. What we're explicitly not building

Naming these to prevent scope creep in weeks of enthusiasm:

- **No custom v4 hook.** We use the Uniswap-deployed `PermissionedHook`. Writing our own would triple the contract surface.
- **No `Recall` unwind flow.** That was Idea 2 in the candidates list — a natural extension but scope for hackathon-2.
- **No `Assign` secondary-market position transfer.** Idea 3, same reasoning.
- **No production KYC provider integration.** Mock endpoint only, deterministic per applicationId.
- **No mainnet deploy.** Sepolia only. Real fund issuance is regulatory work.
- **No mobile support.** Desktop demo only.
- **No indexer/subgraph.** Console reads directly from Sepolia via viem. Adding subgraph is a Day-12 stretch if we have time.
- **No Privy policy engine.** Privy is console sign-in and nothing else. Server Wallets, signer quorums and transaction policies are explicitly out of scope — the §0 subsection describing them was cut on Sep 5 precisely because it invited this scope creep.

---

## 10. Success criteria for the submission

**We ship if by end of Sep 12 we can:**

1. Deploy a permissioned test token and a `PermissionsAdapter` (via the **live Sepolia factory** at `0xE6B0d9...` — we deploy no Uniswap infrastructure), plus our `ENSAllowlistChecker`, `SubnameRegistrar`, `MintAttestor` on Sepolia. All addresses verified on Etherscan. Pool created against the deployed `PermissionedHooks`.
2. Register `issuer.eth` (or equivalent), `brokerA.issuer.eth`, `brokerB.issuer.eth`, and at least three investor subnames end-to-end via the CRE flow.
3. Execute a live swap on Sepolia that passes through `beforeSwap` → `PermissionsAdapter.checkAllowlist` → our checker → returns the right flag → swap executes.
4. Execute a live `addLiquidity` attempt **through `PermissionedPositionManager`** that gets rejected on a swap-only investor and succeeds on an MM investor minting to itself.
5. Run the money-shot demo end-to-end: expire a broker name (short expiry set at registration, or an Anvil fork of Sepolia if the registry enforces a long minimum) and show both investors **unable to swap or add liquidity** with no revocation transaction. Withdrawal remains open — stated as a design property, not hidden.
6. Include `FEEDBACK.md` with real observations from working with Uniswap Permissioned Pools.
7. Video ≤ 3 min. Live demo link. Public repo.

If we get 1–5 done we've cleared every listed prize requirement. 6 and 7 are the delivery.

---

## Appendix A: source citations

Every load-bearing claim in this spec was verified against a source on Sep 3 2026. If any of these change between now and Sep 4, we adjust Day-1 accordingly.

- **Uniswap Permissioned Pools official docs — re-verified directly Sep 5 2026** (these supersede the KuCoin/MetaEra walkthrough as the source of truth for §0):
  - `developers.uniswap.org/docs/protocols/v4-hooks/permissioned-pools/overview`
  - `developers.uniswap.org/docs/protocols/v4-hooks/permissioned-pools/architecture`
  - `developers.uniswap.org/docs/protocols/v4-hooks/permissioned-pools/deploy-a-permissioned-pool` ← factory/hook/router addresses for mainnet + Sepolia, reference `IAllowlistChecker` implementation, `depositForVerification`, wrapper approvals
  - `developers.uniswap.org/docs/protocols/v4-hooks/permissioned-pools/provide-liquidity` ← double `LIQUIDITY_ALLOWED` check, `TransferDisabled`, `unwindPosition`, ungated decreases/burns
- Uniswap Permissioned Pools reference implementation: `github.com/Uniswap/v4-periphery` (`src/hooks/permissionedPools/`). **Still needed** to close Gate 2 — the docs never state which address reaches `checkAllowlist` in `beforeSwap`.
- Uniswap v4 core deployments (PoolManager, PositionManager, Universal Router) across chains: `docs.uniswap.org/contracts/v4/deployments`.
- **ENSv2 — ETHOnline 2026 preview docs build, re-verified directly Sep 5 2026.** Host: `feature-permres-inode-refact.docs-bao.pages.dev`. This build is **ahead of the live `docs.ens.domains` site** and includes the Permissioned Resolver / inode refactor; prefer it over the live site for the duration of the hackathon. Pages read:
  - `/ensv2/overview` — hierarchy model, 28-day grace, per-account Permissioned Resolver proxies
  - `/ensv2/enhanced-access-control` — nybble bitmap layout, 32+32 roles, 15-holder cap per role per resource, `hasRoles` signature, `ROOT_RESOURCE`
  - `/ensv2/permissioned-registry` — the real `State` struct, `anyId` polymorphism, expiry predicate
  - `/ensv2/registry-hierarchy` — `getSubregistry(string)`, top-down resolution, "a subname token guarantees nothing in isolation"
  - `/ensv2/eth-registrar` — commit–reveal, `MIN_COMMITMENT_AGE` 60s, duration-in-seconds, ERC20 pricing, grace + premium periods
  - `/ensv2/mutable-token-ids` — `eacVersionId` / `tokenVersionId`, resource and token-ID derivation, `TokenRegenerated`
  - `/llms-full.txt` — checked for role constants; **does not contain them**
- ENSv2 **hackathon** deployment addresses: `/learn/deployments` on the preview build. ⚠️ These differ from the standard ENSv2 Sepolia beta — the docs list them as a *dedicated hackathon deployment*. The §0 table was replaced wholesale on Sep 5.

### Contract source read directly (Sep 5 2026) — the authority for §0 and §5

Documentation was insufficient for several load-bearing questions; these files were read via the GitHub API and are the source of truth where they disagree with any doc page.

**`Uniswap/v4-periphery`, `src/hooks/permissionedPools/`:**
- `PermissionsAdapter.sol` — `isAllowed` forwarding `account` into `checkAllowlist`; ERC-165 gate in `_updateAllowListChecker`; `depositForVerification`; the `_update` invariant that only the PoolManager may hold the virtual token
- `PermissionedV4Router.sol` — **Gate 2**: `_pay` / `_take` calling `isAllowed(msgSender(), SWAP_ALLOWED)`; `_validatePoolKey` hook allow-listing
- `PermissionedPositionManager.sol` — the two `LIQUIDITY_ALLOWED` checks (`_checkRecipientAllowed(recipient)` and `_pay(msgSender())`), `TransferDisabled`, `unwindPosition`, ungated decrease/burn
- `interfaces/IAllowlistChecker.sol` — extends `IERC165`; the `tokenAddress` rationale
- `libraries/PermissionFlags.sol` — **`type PermissionFlag is bytes2`** with global `|`/`&`/`==`; `NONE` and `ALL_ALLOWED`
- `BaseAllowListChecker.sol` — abstract base we may inherit
- ⚠️ **There is no hook contract in this directory.** Swap enforcement lives in the router.

**`ensdomains/contracts-v2`, `contracts/src/`:**
- `registry/libraries/RegistryRolesLib.sol` — **Gate 3**: the full assigned-nybble table (§0)
- `registry/interfaces/IPermissionedRegistry.sol` — the real `State` struct and `Status` enum
- `registry/PermissionedRegistry.sol` — `getState`, `_constructResource` (incl. the `eacVersionId + 1`-when-expired behaviour), `_isExpired`, the `hasRoles(anyId, …)` override, `getSubregistry`/`getResolver` returning `address(0)` when expired (**the parent-expiry cascade**), and `CannotSetPastExpiry` / `CannotReduceExpiry`

Both repos should be vendored at pinned commits on Day 1 (§6) so the team builds against exactly what was read.
- **Chainlink CRE — verified Sep 5 2026:**
  - `docs.chain.link/cre/concepts/confidential-workflows` — the TEE model and the **confidentiality boundary**, including the explicit exclusion of source code and compiled binary, and of reports/calldata. This is the page that forces the rulebook into Vault-DON secrets.
  - `docs.chain.link/cre/guides/workflow/using-confidential-workflows/making-workflow-confidential-ts` — `handlerInTee`, `TeeConstraint`, `runtime.getSecrets`, `HTTPClient.sendRequest(runtime, …)`, `usingTheDons()`.
  - `docs.chain.link/cre/reference/sdk/confidential-workflows-client-ts` — exact signatures for `handlerInTee`, `TeeRuntime<C>`, `getSecret`/`getSecrets`, `usingTheDons`, `reportFromDon`.
  - `docs.chain.link/cre/privacy` — Confidential Workflows vs Confidential HTTP.
- **`github.com/SamAg19/LienFi`** (Builder B's prior project; four CRE workflows live on Sepolia) — the **`--broadcast` flag** that makes `cre workflow simulate` write a real KeystoneForwarder transaction; `EVMClient` / `writeReport` / `logTrigger` usage; flat statically-typed report payloads; `ReceiverTemplate.sol` (forwarder gating, `_decodeMetadata` layout); `project.yaml` / `workflow.yaml` shape. ⚠️ Last pushed 2026-03-09 — treat the SDK shapes as ~6 months old and reconcile against a fresh `cre init` on Day 1 (risk #21).
- ~~Privy policy fields, signer semantics, DENY-beats-ALLOW rule: `docs.privy.io`.~~ **Removed Sep 5** along with the §0 Privy subsection — it documented Server Wallets, a product this build does not use. Privy is console auth only.
