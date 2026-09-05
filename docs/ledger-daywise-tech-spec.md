# Ledger — Day-by-Day Technical Spec

**Derived from:** `ledger-spec-and-plan.md` (Rev 3, Sep 5 2026 — source-verified)
**Event:** ETHOnline 2026, Sep 4 – Sep 13 · **9 working days, Days 1–2 compressed into Sep 5**
**Builders:** A (contracts/Solidity/Foundry) · B (CRE/frontend/off-chain)

This document is the working schedule. The master spec is the reference for *why*; this one is the reference for *what to do next*. Where they disagree, the master spec wins — tell the other person and fix this file.

---

## Status as of Sep 5

Verification work originally scheduled for Sep 4 has already been completed by reading contract source. **Do not redo it.** That is what makes compressing Days 1–2 into today feasible.

| Gate | Status |
|---|---|
| `IAllowlistChecker` signature | ✅ Closed — matches spec exactly |
| Permissioned Pools on Sepolia | ✅ Closed — all six contracts live, we deploy none |
| **Gate 2** — which address reaches `checkAllowlist` | ✅ Closed — it is the **end trader** (`msgSender()`) |
| **Gate 3** — role-bit collision | ✅ Closed — original bits collided, values moved to `1<<64` / `1<<68` |
| **Gate 4** — on-camera expiry lapse | ✅ Closed — no minimum subname duration, no parent clamp |
| CRE simulate → Sepolia | ✅ Closed — `--broadcast` writes a real forwarder tx; beta enrollment not required |
| **Gate 1** — hierarchy walk gas cost | ⬜ **Open** — Builder A, **Sep 5** (may slip to Sep 6 am) |
| **Gate 5** — fresh `cre init` SDK drift | ⬜ **Open** — Builder B, **Sep 6** — hard deadline, no slack behind it |

**Nothing remaining can force a pivot.** Gate 1 has a known fallback (2-hop hierarchy). Gate 5 has a known fallback (Confidential HTTP).

---

## Ownership

| | Builder A | Builder B |
|---|---|---|
| **Owns** | `contracts/` — all Solidity, Foundry tests, deploy scripts, gas benchmarks | `cre/` and `console/` — workflow, mock KYC, Next.js console |
| **Deploys** | Checker, registrar, attestor, ENS hierarchy | Permissions adapter, pool, test token |
| **Writes** | `bench/RESULTS.md`, demo video | `FEEDBACK.md`, `README.md`, submission forms |

**Both commit daily starting today.** A single-commit final-day history disqualifies the Uniswap submission.

### Interface contract between the two tracks

These are the only things that cross the boundary. Agree them in today's first hour and don't change them silently.

1. **The CRE report tuple** — Builder B encodes it, Builder A decodes it. Must match byte for byte:
   ```
   address wallet, bytes32 labelBytes, address brokerRegistry,
   uint256 roleBitmap, uint64 expiry, bool approved
   ```
2. **`ApplicationSubmitted` event** — Builder A defines, console emits, workflow triggers on it. Contains **no PII** (triggers run on Workflow DON nodes, not in the enclave).
3. **Deployed addresses** — one shared `deployments.json` at repo root, updated by whoever deploys.

---

## Constants reference

Everything below is source-verified. Copy from here, not from memory.

### Uniswap Permissioned Pools — Sepolia

| Contract | Address |
|---|---|
| `PermissionsAdapterFactory` | `0xE6B0d96919334C33d06266d1420F97f6f434fA2B` |
| `PermissionedPositionManager` | `0xf99D553912084c99F6299291b75Fe9B7119Aa1A7` |
| `PermissionedHooks` | `0x51247E2291d290d17C08813A175AC86465EdE8c0` |
| Universal Router (permissioned build) | `0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7` |
| `V4Quoter` | `0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227` |
| `MixedRouteQuoterV2` | `0x4745F77b56a0E2294426E3936dc4Fab68d9543Cd` |

### ENSv2 — **hackathon deployment** (not the standard Sepolia beta)

| Contract | Address |
|---|---|
| `RootRegistry` | `0xe7f0d5724f8337e3aa9a9910540341ff4273fed9` |
| `ETHRegistry` | `0x1d78834d97c1d7b1a38c1dedbd1a287cfed3971e` |
| `ETHRegistrar` | `0x7d1b7f586a62ac3f54b9a396849757814283270b` |
| `VerifiableFactory` | `0x894bc9cc8ff1ad96b8a288c86a8c71d662c07780` |
| `UserRegistryImpl` | `0x47b442d0cf617c41cabaff5f02f44dd1e5f72546` |
| `PermissionedResolverImpl` | `0xa9d3814ab151bf6e37a427432795371a8361614e` |
| `UniversalResolverV2` | `0xfea8d4b7fcce0b8765c793d6695eac384aaa458f` |
| `UpgradableUniversalResolverProxy` | `0xd26f2040d083af1cd2962ba303f4bea0c4faf142` |
| `LabelStore` | `0xd7351f76866123a7e49381f38a30a96adba7e855` |
| `MockUSDC` (registrar payment token) | `0xcbfd80f74375c54e545af34788ff465f96f66f05` |
| `DefaultReverseRegistrarAdapter` | `0x0a8d7ed4061548fb3cb192d0cbe9e1a57b3b1ae9` |

### Types and values

```solidity
// Uniswap — PermissionFlag is bytes2, NOT uint16. Has global | & == operators.
type PermissionFlag is bytes2;
NONE = 0x0000;  SWAP_ALLOWED = 0x0001;  LIQUIDITY_ALLOWED = 0x0002;  ALL_ALLOWED = 0xFFFF;

// ENS — the real State struct returned by getState(anyId)
enum Status { AVAILABLE, RESERVED, REGISTERED }   // no EXPIRED member
struct State { Status status; uint64 expiry; address latestOwner; uint256 tokenId; uint256 resource; }

// Our roles — nybbles 16 and 17, in the free range 10–29
uint256 ROLE_ELIGIBLE_SWAP      = 1 << 64;
uint256 ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;
```

**`RegistryRolesLib` assigned nybbles — do not reuse:** 0 `REGISTRAR` (`1<<0`), 1 `REGISTER_RESERVED` (`1<<4`), 2 `SET_PARENT` (`1<<8`), 3 `UNREGISTER` (`1<<12`), 4 `RENEW` (`1<<16`), 5 `SET_SUBREGISTRY` (`1<<20`), 6 `SET_RESOLVER` (`1<<24`), 7 `CAN_TRANSFER` (admin only, `(1<<28)<<128`), 8 `WAS_RESERVED` (`1<<32`), 9 `SET_URI` (`1<<36`), 30 `CAN_NAME` (`1<<120`), 31 `UPGRADE` (`1<<124`). Admin twin of any role is `ROLE << 128`.

---

## Critical path

```
Sep 5   A: vendor deps           B: MockUSDC (hour 1) ───────────┐
 D1+2   A: checker + mock tests  B: adapter + pool + flat swap    │
        A: Gate 1 gas                                            │
          │                                                      │
Sep 6   A: live ENS hierarchy ◄───────── needs MockUSDC ─────────┘
  D3      │                      B: Gate 5 cre init  ────────────┐
          │                      B: console skeleton             │
          │                                                      │
Sep 7   A: attestor + registrar  B: CRE workflow ◄───── needs Gate 5
  D4      └──────────┬───────────────────┘
                     ▼  first full integration — CRE → mint → checker
Sep 8   A: expiry/adversarial    B: REJECT path + brokerB
Sep 9   A: swap + liquidity      B: console v1
                     ▼  full user story on Sepolia
Sep 10–11  benchmarks, docs, retests
Sep 12     video + submission
Sep 13     submit + buffer
```

**Three hard dependencies to protect:**
- **MockUSDC blocks Sep 6.** Builder B acquires it in the first hour today. Without it Builder A cannot register the parent name.
- **Gate 5 blocks Sep 7.** Moved off today because Builder B cannot fit it alongside the pool work. It now has a hard deadline of end of Sep 6, with nothing behind it.
- **Sep 7 is the first real integration.** Both tracks must land. Neither builder starts Sep 7 work before their Sep 6 deliverable is green.

⚠️ **The buffer is spent.** Compressing Days 1–2 into today puts the schedule back on its original dates from Sep 6, but removes the slack that absorbed a bad day. From here, a slipped day pushes everything. The first place to buy time back is Sep 10–11 (benchmarks and polish), not Sep 7.

---

# Sep 5 (Fri) — Day 1+2 combined: setup, Gate 1, checker, and a working pool

> **Days 1 and 2 are compressed into today.** Everything from Sep 6 onward keeps its original date, so the schedule is back on plan from tomorrow. The cost is that **the Day-1 slack is gone** — if today overruns, it eats Day 3, which is the heaviest contract day. Protect it by following the priority order below rather than working strictly top to bottom.

**Objective:** installable repo · Gate 1 answered · checker passing mocked tests · a swap executing on a permissioned pool with the flat checker.

### Priority order — if the day runs short, drop from the bottom

| Priority | Item | Owner | Why |
|---|---|---|---|
| **P0** | Repo skeleton | 🔀 | Blocks literally everything |
| **P0** | Acquire `MockUSDC` | 🅱️ | Blocks Day 3 registration. **Do this in the first hour.** |
| **P0** | Vendor + verify dependencies | 🅰️ | Blocks all Solidity |
| **P1** | Adapter → pool → flat swap | 🅱️ | Day 6 depends on the pool existing |
| **P1** | `ENSAllowlistChecker` + mocked tests | 🅰️ | Day 3 validates against it |
| **P2** | Gate 1 gas measurement | 🅰️ | Only decides 3-hop vs 2-hop; can slip to Day 3 morning |
| **P3** | ~~Gate 5 (`cre init`)~~ | 🅱️ | **Moved to Sep 6** — see below |

**Gate 5 has moved to Day 3.** Builder B cannot realistically do MockUSDC, the whole adapter/pool/swap sequence, *and* CRE tooling in one day. Day 3's console skeleton is the lightest B task in the schedule, so Gate 5 goes there. CRE work proper doesn't begin until Day 4, so this costs nothing — but it does mean **Gate 5 must be green by end of Sep 6**, with no further slack.

### 🔀 Joint — first hour

Repo skeleton per §7 of the master spec:

```
ledger/
├── contracts/   (Foundry)
├── cre/         (CRE workflow + kyc-mock)
├── console/     (Next.js)
├── deployments.json
├── FEEDBACK.md
└── README.md
```

- `foundry.toml` with ENSv2 + v4-periphery remappings
- `.env.example`: Sepolia RPC (primary + backup), deployer key, Etherscan key
- Agree the **interface contract** (report tuple, `ApplicationSubmitted` event, `deployments.json`) before splitting up
- First commit, both authors

Then split. Nothing below blocks across tracks today.

---

### 🅰️ Builder A

**1. Vendor the verified source — P0, do first.**
```bash
forge install ensdomains/contracts-v2
forge install Uniswap/v4-periphery
```
Confirm against §0/§5 of the master spec:
- `contracts/src/registry/libraries/RegistryRolesLib.sol` — nybble table matches
- `contracts/src/registry/interfaces/IPermissionedRegistry.sol` — `State` struct and `Status` enum match
- `src/hooks/permissionedPools/libraries/PermissionFlags.sol` — `bytes2`, four constants

*If any file has drifted, stop and flag it before writing code.* Risk #19: this spec's Solidity has been verified by reading, never by compiling. Pin the commits.

**2. Write the checker — P1.**

`contracts/src/checker/LedgerRoles.sol` — the two role constants with the full "why nybble 16/17" comment block, including the warning never to grant on `ROOT_RESOURCE` (each role nybble stores a count capped at **15 holders per role per resource**; a shared resource would cap the product at 15 investors).

`contracts/src/checker/ENSAllowlistChecker.sol` — hardcoded path first, no attestor gating yet. Core loop:
```solidity
for (uint256 i = 0; i < p.length; i++) {
    State memory state = IPermissionedRegistry(p[i].registry).getState(p[i].labelhash);
    if (state.status != Status.REGISTERED)   return PermissionFlags.NONE;
    if (state.expiry <= block.timestamp)      return PermissionFlags.NONE;
    if (i == 0) {
        hasSwap = registry.hasRoles(state.resource, ROLE_ELIGIBLE_SWAP, account);
        hasLiq  = registry.hasRoles(state.resource, ROLE_ELIGIBLE_LIQUIDITY, account);
    }
}
PermissionFlag flag = PermissionFlags.NONE;
if (hasSwap) flag = flag | PermissionFlags.SWAP_ALLOWED;
if (hasLiq)  flag = flag | PermissionFlags.LIQUIDITY_ALLOWED;
return flag;
```

**Three things that will bite:**
- `PermissionFlag` is `bytes2`. Assemble with the global `|` operator. **Any `uint16` cast will not compile.**
- Use `state.resource` directly. Do **not** derive it by hand — `hasRoles` also accepts a raw `anyId` and resolves internally.
- `supportsInterface` needs `override(ERC165, IERC165)`. Consider inheriting v4-periphery's own `BaseAllowListChecker` instead of hand-wiring ERC-165 — inheriting the sponsor's base contract is a small credibility win.

`test/ENSAllowlistChecker.t.sol` — mocked registries. Cover: happy path both roles, swap-only, expired leaf, expired ancestor, empty path, non-REGISTERED status.

**3. 🎯 Gate 1 — hierarchy walk gas — P2.**
Deploy a throwaway contract that calls `getState(labelhash)` on the hackathon `ETHRegistry` (`0x1d78834d…`). Measure a synthetic 3-hop walk.

- **Pass:** ≤ 120k gas
- **Fail (>40k/hop):** drop to a 2-hop hierarchy (issuer → investor, no broker layer). This loses the broker-lapse demo moment — a real downgrade, so measure carefully before calling it.
- Expect it to come in *under* the original estimate: `getState` returns the subregistry pointer in the same call, so there's no separate pointer `SLOAD` per hop.

If the day is running short, this is the one to push to tomorrow morning — but **do not start Day 3's hierarchy work before it's answered**, since a 2-hop outcome changes what you build.

---

### 🅱️ Builder B

**1. Acquire `MockUSDC` — P0, first hour, before anything else.**
`0xcbfd80f74375c54e545af34788ff465f96f66f05`. This is the **ETHRegistrar payment token**, not a pool asset. It silently blocks Builder A's Day 3, and Day 3 is now the day with no slack behind it.

Also pick the parent name now — **5+ characters** to stay in the $8/yr tier (3 chars are $640/yr). Suggest `ledger-demo-<n>.eth`. Record both in `deployments.json`.

**2. Adapter → pool → swap — P1, the rest of the day.**

**Use the live Sepolia factory. Deploy no Uniswap infrastructure.** Ordered sequence — every step is required:

1. Deploy a **permissioned test token with an issuer allowlist**. (Not ENS's MockUSDC — the adapter must be allowlistable on the underlying token, and MockUSDC has no allowlist.)
2. `factory.createPermissionsAdapter(token, issuerAdmin, IssuerAllowlistCheckerFlat)` at `0xE6B0d9…`
   — the checker is supplied **at creation**. Start with the flat baseline checker; swapping it for the real one on Day 6 is an on-camera beat.
3. Allowlist the adapter on the token, transfer it 1 wei, then `adapter.depositForVerification(1)`
4. Register all wrappers and the hook:
   ```solidity
   adapter.updateAllowedWrapper(permissionedPositionManager, true);
   adapter.updateAllowedWrapper(universalRouter, true);
   adapter.updateAllowedWrapper(v4Quoter, true);
   adapter.updateAllowedWrapper(mixedRouteQuoterV2, true);
   adapter.updateAllowedHook(IHooks(permissionedHooks), true);
   ```
5. Create the pool with **the adapter as currency** (not the underlying token)
6. `adapter.updateSwappingEnabled(true)` — off by default; swaps revert `SwappingDisabled`
7. End-to-end swap through the permissioned Universal Router with the flat checker

**Trap:** if step 4 is incomplete, everything fails in a way that looks like a checker bug. When debugging any permission failure, the first question is always *"are the wrappers registered?"* — not *"is the checker wrong?"*

Also write `contracts/src/checker/IssuerAllowlistCheckerFlat.sol` (or take Builder A's) — the flat baseline, used here and later as the gas benchmark comparison.

---

### 🔀 Sync — end of day

**Done when:** a swap executes on a permissioned pool with the flat checker, *and* the hierarchy walk passes mocked tests, *and* MockUSDC is in hand.

Record in the README: Gate 1 gas number (or that it's deferred to tomorrow), pool + adapter addresses, chosen parent name.

**Standing check from here on:** the schedule now has no slack before Day 4's integration. At each end-of-day sync, say out loud whether tomorrow's dependency is actually satisfied — MockUSDC for Day 3, hierarchy + Gate 5 for Day 4.

---

# Sep 6 (Sat) — Day 3: real ENSv2 wiring

**Objective:** a real three-level hierarchy exists on Sepolia and the checker returns correct flags walking it.

### 🅰️ Builder A — the hierarchy

**Registering the parent is a 3-step commit–reveal, not one call.** This is the step most likely to eat the morning.

```solidity
// 1. commit
bytes32 commitment = registrar.makeCommitment(label, owner, secret, subregistry, resolver, duration, referrer);
registrar.commit(commitment);

// 2. wait MIN_COMMITMENT_AGE = 60 seconds  (commitment dies after ~24h)

// 3. register — duration in SECONDS, paid in MockUSDC
registrar.register(label, owner, secret, subregistry, resolver, duration, MOCK_USDC, referrer);
```

Then build the hierarchy — note subname registration is **the other call**, with an absolute expiry, no payment and no commit–reveal:

1. Deploy `IssuerRootRegistry` (a `UserRegistry`) via `VerifiableFactory` (`0x894bc9cc…`)
2. `initialize()` with a bitmap including at minimum `ROLE_REGISTRAR_ADMIN | ROLE_RENEW_ADMIN`
3. `setSubregistry(...)` on the parent to wire it in
4. Register `brokerA` — **with a deliberately short expiry** (~10 min) for the demo lapse. No minimum duration, no clamp to the parent's expiry; only `CannotSetPastExpiry` applies.
5. Deploy `BrokerARegistry`, wire under `brokerA`
6. Register `alice` in `BrokerARegistry` with `ROLE_ELIGIBLE_SWAP`

**Trap:** `grantRootRoles` requires the `_ADMIN` variant of the role being granted. Follow the ENS tutorial setup ordering exactly — getting this wrong is fatal to the registration path and subtle to debug (risk #10).

Write `script/DeployIssuerHierarchy.s.sol` so this is repeatable and idempotent. You will run it many times.

### 🅱️ Builder B — Gate 5, then console skeleton

**1. 🎯 Gate 5 — CRE tooling (moved here from Day 1). Must be green by end of today — there is no slack behind it.**

```bash
cre init --template=hello-confidential-workflows-ts
cre workflow simulate my-workflow --target staging-settings \
  --non-interactive --trigger-index 0 --broadcast --verbose
```

- **Pass:** a KeystoneForwarder transaction lands on Sepolia. Grab the tx hash from the output.
- **Then diff** the generated SDK shapes against §2 of the master spec. The confidential APIs (`handlerInTee`, `TeeRuntime`, `usingTheDons`) come from current docs; the `EVMClient` / `writeReport` / `logTrigger` shapes come from LienFi and are ~6 months old (risk #21). Write down every difference — you build against these tomorrow.
- **Fail:** fall back to Confidential HTTP (`ConfidentialHTTPClient`) — LienFi proves that path works end to end.

Submit the beta access request in Chainlink Discord as a nice-to-have. **It is not a blocker** — docs say *"Do not wait for early access."*

**2. Console skeleton.**

Next.js app:
- Privy embedded wallet sign-in (**console auth only** — no Server Wallets, no policy engine; that's explicitly out of scope)
- "Submit application" form → backend endpoint stub
- The endpoint emits `ApplicationSubmitted(applicationId, wallet, requestedTier)` — **no PII in the event**, since triggers run on Workflow DON nodes outside the enclave

Start `console/lib/uniswap.ts` and `console/lib/ensv2.ts`.

**Naming trap for `uniswap.ts`:** the pool's currency is the **adapter**; the investor's wallet holds the **underlying**. Never call a variable just `token`. Getting this wrong produces "insufficient balance" against a wallet that visibly has funds.

**If today runs short, cut console polish, not Gate 5.** The console skeleton only needs to emit `ApplicationSubmitted` for Day 4 to proceed — styling and layout can wait until Day 6. Gate 5 cannot: Day 4 is the first day both tracks must land, and starting CRE work against unverified SDK shapes is how that day gets lost.

### 🔀 Sync — end of day

**Done when:** the real Sepolia hierarchy exists and `ENSAllowlistChecker` walking it returns `SWAP_ALLOWED` for `alice` and `NONE` for an unknown address.

---

# Sep 7 (Sun) — Day 4: CRE verdict → mint path

**Objective:** the first full integration. An APPROVE verdict from a simulated confidential workflow mints a subname on Sepolia and the checker reflects it.

**Both tracks must land today.** This is the highest-risk day in the schedule.

### 🅰️ Builder A — attestor + registrar

**`contracts/src/cre/MintAttestor.sol`** — inherit LienFi's `ReceiverTemplate` (forwarder gating, ERC-165, metadata decode already done):

```solidity
function _processReport(bytes calldata metadata, bytes calldata report) internal override {
    (bytes32 workflowId, , ) = _decodeMetadata(metadata);
    if (workflowId != EXPECTED_WORKFLOW_ID) revert UnexpectedWorkflow(workflowId);

    (address wallet, bytes32 labelBytes, address brokerRegistry,
     uint256 roleBitmap, uint64 expiry, bool approved)
        = abi.decode(report, (address, bytes32, address, uint256, uint64, bool));

    if (!approved) return;   // REJECT is a no-op on-chain

    string memory label = LibLabelBytes.toString(labelBytes);
    REGISTRAR.registerFromAttestation(wallet, label, brokerRegistry, roleBitmap, expiry);
    CHECKER.recordPath(wallet, brokerRegistry, LibLabel.id(label));
}
```

**Two things worth understanding, not just copying:**
- The workflow-ID check is **ours to add** — `ReceiverTemplate` decodes metadata but doesn't validate it. Without this guard, *any* workflow routed through the same forwarder could mint subnames. This is the security-relevant line in the contract.
- `labelBytes` carries the **label itself**, right-padded into `bytes32` — not its hash. `register()` needs a `string` and a hash can't be reversed, but `string` is dynamic and CRE reports are flat. `LibLabelBytes.toString` is ~10 lines: trim trailing zero bytes. This caps labels at 32 bytes — fine for the demo, worth a line in `FEEDBACK.md`.

**`contracts/src/registrar/SubnameRegistrar.sol`** — flat params matching the report, `onlyAttestor`, calling `IPermissionedRegistry.register` into the broker's registry.

Then: deploy all three, wire `recordPath` behind `onlyAttestor`, and grant `ROLE_REGISTRAR` on each broker `UserRegistry` to `SubnameRegistrar` via `grantRootRoles`.

### 🅱️ Builder B — the confidential workflow

```ts
handlerInTee(
  evmClient.logTrigger({ addresses: [...], topics: [...] }),
  onApplicationSubmitted,
  {},                    // any registered TEE, any region
)
```

Inside the enclave:
```ts
const secrets = runtime.getSecrets([
  { id: "KYC_API_TOKEN" },
  { id: "ELIGIBILITY_RULEBOOK" },
]).result()
```

> **🔴 The rulebook goes in the Vault-DON secret, not in `main.ts`.**
> CRE docs are explicit: *"your handler's source code and compiled binary are not confidential just because part of its logic runs inside an enclave."* Our repo must be public to win the prize. If the thresholds are written as TypeScript, the "compliance without leaking rules" claim is **false** — which is the CRE prize's entire premise (risk #20).
> `main.ts` holds a generic evaluator. All discriminating values — score thresholds, tier boundaries, jurisdictions — come from `ELIGIBILITY_RULEBOOK`.

Crossing back out:
```ts
const donRuntime = runtime.usingTheDons()   // everything past here is NOT confidential
const report = donRuntime.report({ encodedPayload: hexToBase64(reportData),
  encoderName: "evm", signingAlgo: "ecdsa", hashingAlgo: "keccak256" }).result()
evmClient.writeReport(donRuntime, { receiver: mintAttestorAddress, report, gasConfig: { gasLimit } })
```

Report payload — flat tuple, **no dynamic arrays**:
```
address wallet, bytes32 labelBytes, address brokerRegistry, uint256 roleBitmap, uint64 expiry, bool approved
```

Also build `cre/kyc-mock/server.ts` — deterministic responses keyed by `applicationId` so the demo is repeatable.

Run everything with `--broadcast`.

### 🔀 Sync — end of day

**Done when this full chain works:** `cre workflow simulate --broadcast` → APPROVE verdict → forwarder tx on Sepolia → `MintAttestor.onReport` → `SubnameRegistrar` mints the subname → `ENSAllowlistChecker.checkAllowlist(alice, token)` returns `SWAP_ALLOWED`.

If the chain breaks, debug from the on-chain end backwards — the forwarder tx hash in the CRE output tells you whether the problem is before or after the chain boundary.

---

# Sep 8 (Mon) — Day 5: expiry, adversarial, invariants

**Objective:** the money-shot demo runs from the CLI.

### 🅰️ Builder A — the tests that prove the thesis

`test/ExpiryCascade.t.sol`:
- Register `mm.brokerA` with **both** roles; assert bit assembly returns `SWAP_ALLOWED | LIQUIDITY_ALLOWED`
- Expire `brokerA` → assert **both** `alice` and `mm` return `NONE`. This is the money shot.
- Expire `alice` only → assert `mm` still works
- **Re-registration test:** expire a name, re-register it, assert the old role grants no longer satisfy `checkAllowlist`. This proves the `eacVersionId` story — a lapsed broker cannot resurrect their book by re-registering. Cheapest possible proof of the strongest claim in the pitch.

`test/AdversarialPath.t.sol`:
- Malicious/forged path → must return `NONE` or revert, never grant
- Path with a registry that isn't a real registry
- `recordPath` called by a non-attestor → reverts

### 🅱️ Builder B — REJECT path + second broker

- Workflow REJECT branch: score below threshold → either no `writeReport`, or a REJECT verdict that `MintAttestor` filters (`if (!approved) return;`). Test both.
- Register `brokerB.issuer.eth` end-to-end through the full CRE flow, with `bob` under it holding `ROLE_ELIGIBLE_SWAP`. This proves the hierarchy generalises past one broker.

### 🔀 Sync — end of day

**Done when:** the money-shot sequence runs from `cast` scripts, start to finish, with no manual steps.

---

# Sep 9 (Tue) — Day 6: swap path end-to-end

**Objective:** the full user story executes on live Sepolia.

### 🅰️ Builder A — the checker swap and the liquidity split

**The on-camera beat:** the adapter was created on Day 2 with the flat checker. Now:
```solidity
adapter.updateAllowListChecker(ensAllowlistChecker);
```
One transaction turns a flat permissioned pool into a hierarchical one. Film this.

Then prove the tier split:
- Mint the permissioned token to `alice`, approve the permissioned Universal Router (`0x54C707…`), execute a swap → **succeeds**
- `alice` attempts `addLiquidity` via `PermissionedPositionManager` (`0xf99D55…`, **not** the standard v4 `PositionManager`) → **reverts**
- `mm` swaps → succeeds; `mm` adds liquidity → succeeds

**`mm` must mint to itself.** `LIQUIDITY_ALLOWED` is checked **twice against two different addresses**: the position manager checks the `recipient`, the hook's `beforeAddLiquidity` checks the `caller`. Keeping caller == recipient means one name and one role grant satisfy both. Never let the console mint on a user's behalf.

### 🅱️ Builder B — console v1

- Application form (wired to the real workflow now)
- Active brokers with **live expiry countdown** — this is what makes the lapse legible on camera
- Active investors per broker, with their role bits shown as two distinct badges (swap / liquidity)
- A control to trigger the broker lapse for the demo

**Note:** the earlier plan hedged with an Anvil mirror because Sepolia can't be time-warped. That's no longer needed — `brokerA` is registered with a ~10-minute expiry and lapses for real. Build the countdown against the real chain.

### 🔀 Sync — end of day

**Done when:** the complete user story — application → CRE verdict → subname mint → swap → liquidity split → broker lapse → both cut off — executes on Sepolia.

---

# Sep 10 (Wed) — Day 7: benchmarks & polish

### 🅰️ Builder A

`bench/GasBench.t.sol` + `bench/RESULTS.md`. Measure `checkAllowlist` gas at 10 / 1,000 / 10,000 registered investors, against the `IssuerAllowlistCheckerFlat` baseline.

The interesting result is that our cost is **flat in the number of investors** — it's a function of hierarchy depth, not registry size — whereas the flat checker's storage grows linearly. Present it that way; it's the quantitative argument for the whole design.

### 🅱️ Builder B

Console polish:
- Two-tier investor view (retail vs MM) with the role bits visible
- On-chain event stream: registrations + attestations
- Attestation trail per subname: workflow ID + report hash, so a judge can verify the CRE provenance of any name

---

# Sep 11 (Thu) — Day 8: docs & adversarial retests

### 🅰️ Builder A

- **Role-nybble collision test.** Assert our `1<<64` / `1<<68` grants do not trigger any `RegistryRolesLib` behaviour. The original values collided with `ROLE_REGISTER_RESERVED` and `ROLE_SET_PARENT`; this test is the regression guard.
- **Token-regeneration test.** Mint → change a role (which bumps `tokenVersionId` and regenerates the token) → assert the checker still works, because we index by labelhash and never touch token IDs.

### 🅱️ Builder B

**`FEEDBACK.md`** — real observations from the build. Strong candidates, all found during verification:
- Docs say `beforeSwap` enforces `SWAP_ALLOWED`; the source shows `PermissionedV4Router._pay`/`._take` doing it. There is no hook contract in `src/hooks/permissionedPools/`.
- The docs never state which address reaches `checkAllowlist` — it took reading the router source to establish it's the end trader.
- `LIQUIDITY_ALLOWED` being checked against both caller and recipient is easy to miss and produces confusing failures.
- `PermissionFlag` being `bytes2` rather than a numeric type surprises anyone assembling flags by hand.

**`README.md`** with the Uniswap-required "Relevant Contracts and Lines of Code" section, plus one sentence on routing: allowlisting is a separate Uniswap Labs process for their hosted interface, out of scope here, not a gap in the integration.

---

# Sep 12 (Fri) — Day 9: video & submission

### 🅰️ Builder A — the video (target 90s)

Sequence: retail swaps ✓ → retail `addLiquidity` reverts ✗ → MM does both ✓ → **broker name lapses, no transaction sent** → both investors cut off.

**Two things to say out loud, because a knowledgeable judge is listening for them:**
1. *"They can no longer trade or add exposure"* — **not** *"they're frozen."* Decreases and burns are never gated in the standard; withdrawal stays open by design. Naming this shows command of the spec rather than hiding a gap.
2. *"The code is public, the criteria are not, and the applicant's data never leaves the enclave."* Don't claim the logic is confidential — the docs are explicit that source and binaries aren't protected.

Worth a beat if it fits: a lapsed broker who re-registers **cannot** resurrect their book, because the EAC resource is version-stamped and the old grants are orphaned.

### 🅱️ Builder B

- Submit `developers.uniswap.org/hackathon-feedback` linking to `FEEDBACK.md`
- Final README pass; verify every contract address in the README matches `deployments.json`

### 🔀 Joint

**Practice the demo 3× live.** Sepolia RPC flakiness is a Medium-probability, High-impact risk — have a backup RPC key ready and make every demo script idempotent so a re-run works.

---

# Sep 13 (Sat) — Day 10: submit

### 🔀 Joint

Submit on the ETHGlobal portal. Buffer for last-minute fixes.

**Pre-submission checklist:**
- [ ] Public repo, daily commits from both builders
- [ ] `FEEDBACK.md` present; Uniswap feedback form submitted with a link to it
- [ ] README points to the relevant contracts and lines of code
- [ ] All Sepolia addresses verified on Etherscan
- [ ] Video ≤ 3 min, live demo link
- [ ] ENSv2 features demonstrably central, no hard-coded values
- [ ] CRE section documents the production enrollment path (we demo on the simulator)

---

## Definition of done

From §10 of the master spec — we ship if all of the following are true by end of Sep 12:

1. Adapter created via the live Sepolia factory; our checker, registrar and attestor deployed and verified
2. Parent name, two brokers, and ≥3 investor subnames registered end-to-end through the CRE flow
3. A live Sepolia swap passing through the router → adapter → our checker → correct flag → executes
4. A live `addLiquidity` rejected for a swap-only investor and accepted for an MM
5. The money shot: broker name lapses, both investors cut off, no revocation transaction
6. `FEEDBACK.md` with real observations
7. Video ≤ 3 min, live demo link, public repo

**1–5 clear every listed prize requirement. 6–7 are the delivery.**
