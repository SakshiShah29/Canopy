# Canopy — Day-by-Day Technical Spec

> **The project is named Canopy.** It was called Ledger through the planning docs; contract and
> library names use `Canopy*` (e.g. `CanopyRoles`). The parent name is `canopy.eth` — 6 characters,
> so the $8/yr tier, and confirmed available on the hackathon deployment.

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
| **Gate 4** — on-camera expiry lapse | ✅ Closed — no minimum **subname** duration, no parent clamp (the 28-day minimum applies only to the parent, via the registrar) |
| CRE simulate → Sepolia | ✅ Closed — `--broadcast` writes a real forwarder tx; beta enrollment not required |
| **Gate 1** — hierarchy walk gas cost | ✅ **Closed Sep 5** — 3-hop cold walk **65,839** against a 120k budget, **~17.9k/hop** against a 40k limit. Keep the 3-level hierarchy; the 2-hop fallback is not needed |
| **Gate 5** — fresh `cre init` SDK drift | ⬜ **Open** — Builder B, **Sep 6** — hard deadline, no slack behind it |

**Only Gate 5 remains, and it cannot force a pivot** — it has a known fallback (Confidential HTTP).

---

## Ownership

| | Builder A | Builder B |
|---|---|---|
| **Owns** | `contracts/` — all Solidity, Foundry tests, deploy scripts, gas benchmarks | `cre/` and `frontend/` — workflow, mock KYC, Next.js console |
| **Deploys** | Checker, registrar, attestor, ENS hierarchy, **both investor subnames** | Permissions adapter, pool, permissioned test token |
| **Writes** | `frontend/lib/canopy.ts` (the shared module), the end-to-end runner, demo video | `FEEDBACK.md`, `README.md`, submission forms |

**Both commit daily starting today.** A single-commit final-day history disqualifies the Uniswap submission.

**`frontend/lib/canopy.ts` is a deliberate exception to the ownership split.** It lives in Builder
B's directory but is written by Builder A, because it is contract knowledge rather than UI — the
adapter-vs-underlying distinction, Permit2 approvals, the caller == recipient rule. It is a boundary
artifact like `deployments.json`. Builder B owns everything that renders.

### Interface contract between the two tracks

These are the only things that cross the boundary. Agree them in today's first hour and don't change them silently.

1. **The CRE report tuple** — Builder B encodes it, Builder A decodes it. Must match byte for byte:
   ```
   address wallet, bytes32 labelBytes, address brokerRegistry,
   uint256 roleBitmap, uint64 expiry, bool approved
   ```
2. **`ApplicationSubmitted` event** — Builder A defines, console emits, workflow triggers on it:

   ```solidity
   event ApplicationSubmitted(
       bytes32 indexed applicationId,
       address indexed wallet,
       address indexed broker,      // which broker's registry the applicant is applying through
       uint8   requestedTier        // 0 = retail (swap), 1 = market maker (swap + liquidity)
   );
   ```

   Contains **no PII** — triggers run on Workflow DON nodes, not in the enclave. A broker address
   is not PII, so carrying it here is safe.

   **`broker` is required and was previously missing.** The workflow must emit a report containing
   `brokerRegistry`, but the trigger never told it which broker. The alternative — resolving it
   inside the enclave from the application payload — puts a lookup in the TEE for a value that is
   not secret. The broker is an *input* to the application, not something CRE decides.

   `requestedTier` is what the applicant *asks for*. CRE decides what they actually get, and may
   approve a lower tier or reject outright.
3. **Deployed addresses** — one shared `deployments.json` at repo root, updated by whoever deploys.
4. **`frontend/lib/canopy.ts`** — every on-chain read and write, exported as plain functions. The
   runner and the UI both import it; neither talks to a contract directly. Builder A writes it,
   Builder B consumes it.
5. **The investor wallet addresses.** Builder B decides how investors sign (Privy embedded wallet as
   signer, or injected); Builder A registers the subnames **to those exact addresses**. Changing the
   wallet strategy afterwards means re-registering, and a subname is not trivially movable. Settle
   this before Day 4 mints anything for real.

---

## The end-to-end flow

This is the demo, and it is also the acceptance test. Everything else in this document exists to
make these eleven beats run.

### Terminal first, then the visual

The flow is proved in the terminal **once CRE lands (Day 4)**, before any of it is on screen. That
way the shape of the thing is known — every revert, every ordering constraint, every approval — and
the UI becomes presentation rather than discovery.

**This only works if both share one implementation.** If the runner is `cast` and Foundry scripts,
none of it is reusable: the frontend would rewrite every call in viem, the two would drift, and the
terminal run would prove nothing about the version on camera.

So the runner is **TypeScript/viem over `frontend/lib/canopy.ts`** — the same module the UI imports.

```
frontend/lib/canopy.ts        eligibilityOf() hierarchyOf() swap()
                              addLiquidity() removeLiquidity() apply()
        ├── scripts/e2e.ts    the runner: calls them in order, asserts, prints
        └── the console       buttons calling the same functions
```

Nothing outside that module talks to a contract directly.

### Who registers what

| What | Registered by | CRE involved? |
|---|---|---|
| `canopy.eth` | the issuer — `DeployIssuerHierarchy` | no |
| `brokerA`, `brokerB`, … | the issuer — `DeployIssuerHierarchy` | no |
| `alice`, `mm`, `bob` | `SubnameRegistrar`, on a CRE verdict | **yes** |

**Brokers are infrastructure.** Onboarding one reflects a distribution agreement the issuer already
signed: register the name, deploy them a `UserRegistry`, wire `setParent`. No compliance check.

**Investors apply *through* a broker.** The applicant names their broker; CRE decides only
**approved or not** and **at what tier**. It never decides *under whom* — the broker is an input to
the application, and `brokerRegistry` rides in the report so `MintAttestor` knows where to mint.

**Only a CRE verdict can mint eligibility.** The broker never sends the transaction;
`SubnameRegistrar` does, holding `ROLE_REGISTRAR` on each broker registry. A broker cannot onboard a
client who failed the check. That is exactly what makes the cascade meaningful: a broker controls
nothing about eligibility except their own name staying alive, and when it lapses everyone they
introduced goes with them.

Investors registered directly by the deploy script are **bootstrap only** — Day 3 precedes CRE, and
the demo needs `alice` and `mm` guaranteed present. Everyone after that arrives through the product.

### The eleven beats

Setup (idempotent, off camera): permissioned token + adapter + pool with the flat checker (B); ENS
parent, registries, attestor, registrar (A); both investors holding the underlying token with Permit2
approved.

| # | Beat | Proves |
|---|---|---|
| 1 | `alice` applies → CRE **APPROVE** → subname minted with `ROLE_ELIGIBLE_SWAP` | the CRE mint path |
| 2 | A second applicant → CRE **REJECT** → no subname, no access | the engine actually discriminates |
| 3 | `mm` applies → APPROVE with **both** role bits | two tiers exist |
| 4 | `adapter.updateAllowListChecker(ensAllowlistChecker)` | one transaction turns a flat permissioned pool into a hierarchical one |
| 5 | `mm` adds liquidity (caller == recipient) → **succeeds** | the MM tier, and the pool gets depth |
| 6 | `alice` swaps → **succeeds** | the retail tier |
| 7 | `alice` attempts `addLiquidity` → **reverts** | **the tier split.** Two successes prove nothing; the refusal is the proof |
| 8 | `brokerA` lapses — countdown to zero, **no transaction sent** | the money shot |
| 9 | `alice` and `mm` both attempt swaps → **both revert `Unauthorized`** | the chain refusing, not our UI greying out |
| 10 | `mm` removes liquidity → **succeeds** | not frozen. Exposure can always be unwound |
| 11 | `brokerA` re-registers → investors stay dead | version-stamped resources; a lapsed broker cannot resurrect their book |

**Ordering is load-bearing.** Beat 5 must precede beat 6 — the pool needs depth before anyone can
swap. Beat 4 must precede 5–7, or the flat checker is still answering.

**Why 2, 7, 9, 10 and 11 are not optional.** Each closes a hole a judge would otherwise find: beat 2
that the rulebook ever says no; beat 7 that tiers are real; beat 9 that the cut-off is enforced
on-chain rather than by our frontend; beat 10 that we have not trapped anyone's funds — decreases and
burns are never gated in the standard, and a knowledgeable judge is already wondering; beat 11 that
the expiry cascade cannot be undone by re-registering.

**Beat 8 is never a button.** Expiry is time passing. The only control that could force it is
`unregister`, which is exactly the revocation transaction the pitch claims is unnecessary — filming
it would refute the thesis. Setup between takes uses
`contracts/script/deploy-hierarchy.sh --reset-broker`, off camera.

**Beat 8 also has to be uncut**, and the badges must change with nobody touching the page. The chain
does not push, so the console polls. If the moment needs a refresh, the judge sees a click.

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

### Live registrar values — read from Sepolia, Sep 5

| Constant | Value | |
|---|---:|---|
| `MIN_COMMITMENT_AGE` | 60 s | wait between `commit` and `register` |
| `MAX_COMMITMENT_AGE` | 86,400 s | commitment dies after 24h |
| `MIN_REGISTER_DURATION` | 2,419,200 s | **28 days — parent only**, subnames have no minimum |
| `GRACE_PERIOD` | 2,419,200 s | 28 days |
| `MockUSDC` decimals | 6 | `mint(address,uint256)` is **permissionless** |
| `canopy` / 5+ chars | 0.6137 USDC / 28d | ≈ $8/yr |
| 3-char names | 49.10 USDC / 28d | ≈ $640/yr |

### Selectors that differ from our pinned source

The hackathon deployment was built from a different commit than `contracts-v2@48b3e2d3`. Verify any
call not listed here before using it.

| Call | Deployed | Our pin |
|---|---|---|
| `UserRegistry` initializer | `initialize((address,uint256)[])` `0x37cb53a8` | `initialize(address,uint256)` |
| `ETHRegistrar.renew` | `renew((string,uint64,bytes32),address)` | `renew(string,uint64,IERC20,bytes32)` |

**`RegistryRolesLib` assigned nybbles — do not reuse:** 0 `REGISTRAR` (`1<<0`), 1 `REGISTER_RESERVED` (`1<<4`), 2 `SET_PARENT` (`1<<8`), 3 `UNREGISTER` (`1<<12`), 4 `RENEW` (`1<<16`), 5 `SET_SUBREGISTRY` (`1<<20`), 6 `SET_RESOLVER` (`1<<24`), 7 `CAN_TRANSFER` (admin only, `(1<<28)<<128`), 8 `WAS_RESERVED` (`1<<32`), 9 `SET_URI` (`1<<36`), 30 `CAN_NAME` (`1<<120`), 31 `UPGRADE` (`1<<124`). Admin twin of any role is `ROLE << 128`.

---

## Critical path

```
Sep 5   A: vendor deps           B: permissioned test token ─────┐
 D1+2   A: checker + mock tests  B: adapter + pool + flat swap    │
        A: Gate 1 gas ✅                                          │
          │                                                      │
Sep 6   A: live ENS hierarchy    A: real checker ◄─ needs token ─┘
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

**Hard dependencies to protect:**
- ~~**MockUSDC blocks Sep 6.**~~ **Retired Sep 5.** `MockUSDC.mint(address,uint256)` at `0xcbfd80f7…` is **permissionless** — verified by simulating it from two unrelated addresses. Builder A self-serves; this is no longer a cross-track dependency, and it was the hardest one in the plan.
- **Gate 5 blocks Sep 7.** Moved off Sep 5 because Builder B cannot fit it alongside the pool work. It now has a hard deadline of end of Sep 6, with nothing behind it.
- **Builder B's permissioned token blocks the *real* checker deployment.** `ENSAllowlistChecker.PERMISSIONED_TOKEN` is immutable, so the production checker cannot be deployed until that address exists. Smaller than the dependency it replaces: Sep 6's verification runs against a throwaway checker bound to any address, so nothing is blocked in the meantime.
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
| ~~P0~~ | ~~Acquire `MockUSDC`~~ | — | **Dropped.** `mint(address,uint256)` is permissionless; Builder A self-serves. No longer blocks anything. |
| **P0** | Vendor + verify dependencies | 🅰️ | Blocks all Solidity |
| **P1** | Adapter → pool → flat swap | 🅱️ | Day 6 depends on the pool existing |
| **P1** | `ENSAllowlistChecker` + mocked tests | 🅰️ | Day 3 validates against it |
| ~~P2~~ | Gate 1 gas measurement | 🅰️ | ✅ **Done Sep 5** — 3-hop passes with headroom; hierarchy stays 3-level |
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

**2. Write the checker — P1. ✅ Done Sep 5 — 45 tests passing.**

`contracts/src/checker/CanopyRoles.sol` — the two role constants, with the warning never to grant on
`ROOT_RESOURCE` (each role nybble stores a count capped at **15 holders per role per resource**; a
shared resource would cap the product at 15 investors).

`contracts/src/checker/ENSAllowlistChecker.sol` — **built as an upward walk, not a stored path.**
`IRegistry.getParent()` exists, so only the leaf is recorded and every ancestor is discovered
on-chain at check time. A stored path goes stale the moment the hierarchy changes, and the judging
checklist calls for no hard-coded values.

The walk must **arrive** at `ROOT_ANCHOR`; a null parent, a wrong terminus or more than `MAX_HOPS`
all deny. See Day 3 step 4 for why that is load-bearing.

`contracts/src/checker/IssuerAllowlistCheckerFlat.sol` — the flat baseline, also written Sep 5 so
Builder B is not blocked on it for adapter creation. It lives in Builder A's directory per the
ownership table; Builder B deploys it.

**Three things that will bite:**
- `PermissionFlag` is `bytes2`. Assemble with the global `|` operator. **Any `uint16` cast will not compile.**
- Use `state.resource` directly. Do **not** derive it by hand — `hasRoles` also accepts a raw `anyId` and resolves internally.
- The file is `BaseAllowListChecker.sol` but the contract is `BaseAllow**l**istChecker` — upstream casing mismatch. Importing by the filename's casing fails with a misleading "declaration not found". Logged in `FEEDBACK.md`.

`test/Dependencies.t.sol` pins every upstream assumption — flag values, the full nybble table, the
`State`/`Status` shape, the role-collision guard — so upstream drift breaks the build rather than the
demo. That retires risk #19: all 8 vendored sponsor sources are byte-identical to the copies this
spec was written against.

**3. 🎯 Gate 1 — hierarchy walk gas — ✅ CLOSED Sep 5. Keep the 3-level hierarchy.**

Measured against the **real** `PermissionedRegistry`, not a mock. Three checkers share one hierarchy
and differ only in `ROOT_ANCHOR`, which isolates the marginal cost of a hop from the fixed cost of
the leaf read — the fail criterion is per-hop, so the slope is what matters.

| Depth | Cold | Warm | Marginal |
|---:|---:|---:|---:|
| 1 (leaf only) | 29,982 | 10,965 | — |
| 2 (+1 ancestor) | 47,907 | 16,390 | 17,925 |
| 3 (+2 ancestors) | **65,839** | 21,822 | 17,932 |

**~17.9k per hop** against the 40k limit; **65,839** against the 120k budget. Near-perfectly linear,
so cost tracks hierarchy depth and nothing else.

Two numbers to quote correctly:
- **The real per-swap cost is 87,661, not 65,839.** A swap calls `isAllowed` twice — from
  `PermissionedV4Router._pay` and `._take` — so the second walk is warm at about a third the price.
- **Fork cross-check:** live `getState` costs 11,218 vs 8,822 for our locally compiled build, so the
  deployed contract is ~27% dearer. Carried through, the walk is ~73k (applied to the three
  `getState` calls) or ~84k (applied to the whole walk, conservative). Both clear the budget.

The walk is **flat in the number of investors** — eligibility is read from the investor's own subname
resource, not from a list. That is the Day 7 argument against the flat checker.

---

### 🅱️ Builder B

**1. ~~Acquire `MockUSDC`~~ — dropped.**
`mint(address,uint256)` on `0xcbfd80f74375c54e545af34788ff465f96f66f05` is permissionless, so Builder A mints their own. Nothing here blocks Day 3.

The parent name is settled: **`canopy.eth`** — 6 characters, so the $8/yr tier (verified: 0.6137 USDC for the 28-day minimum; 3-char names are ~$640/yr), and confirmed available. Record it in `deployments.json`.

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

**Done when:** a swap executes on a permissioned pool with the flat checker, *and* the hierarchy walk passes mocked tests.

Record in the README: the Gate 1 gas number, pool + adapter addresses, the permissioned test token address (Builder A needs it for the real checker), and the parent name.

**Standing check from here on:** the schedule has no slack before Day 4's integration. At each end-of-day sync, say out loud whether tomorrow's dependency is actually satisfied — the permissioned token for Day 3's real checker, hierarchy + Gate 5 for Day 4.

---

# Sep 6 (Sat) — Day 3: real ENSv2 wiring

**Objective:** a real three-level hierarchy exists on Sepolia and the checker returns correct flags walking it.

### 🅰️ Builder A — the hierarchy

> **Verified against the live chain on Sep 5 — do not re-derive.** All three registrar selectors
> match our pinned submodule (`commit` `0xf14fcbc8`, `makeCommitment` `0x1e966f07`, `register`
> `0xcff3e7c2`). `MIN_COMMITMENT_AGE` = 60s, `MAX_COMMITMENT_AGE` = 86,400s. All eight
> `ETHRegistry` calls below exist. The live `LabelStore` (`0xd7351f76…`) has permissionless
> `setLabel`, so reuse it rather than deploying one.
>
> **But the deployment is from a different commit than our pin.** Its `renew` is
> `renew((string,uint64,bytes32),address)`, not our source's
> `renew(string,uint64,IERC20,bytes32)`. Not on our path — we want names to lapse, not renew — but
> **verify the selector before using any call not listed above.** `cast selectors` on the deployed
> bytecode, then match against `cast sig`.

**Registering the parent is a 3-step commit–reveal, not one call.** This is the step most likely to eat the morning.

```solidity
// 1. commit
bytes32 commitment = registrar.makeCommitment(label, owner, secret, subregistry, resolver, duration, referrer);
registrar.commit(commitment);

// 2. wait MIN_COMMITMENT_AGE = 60 seconds  (commitment dies after MAX_COMMITMENT_AGE = 24h)

// 3. register — duration in SECONDS, paid in MockUSDC (6 decimals), mint your own
registrar.register(label, owner, secret, subregistry, resolver, duration, MOCK_USDC, referrer);
```

**`MIN_REGISTER_DURATION` = 2,419,200s (28 days)** — the parent cannot be registered for less. This
is the registrar's floor and applies *only* to the parent; subnames have no minimum (see step 5).

Then build the hierarchy — note subname registration is **the other call**, with an absolute expiry, no payment and no commit–reveal:

1. Deploy `IssuerRootRegistry` (a `UserRegistry`) via `VerifiableFactory` (`0x894bc9cc…`)

2. **Initialize it through `deployProxy`'s third argument.** The deployed implementation takes an
   **array of grants**, not a single account and bitmap:

   ```solidity
   // initialize((address,uint256)[])  — selector 0x37cb53a8
   VERIFIABLE_FACTORY.deployProxy(
       USER_REGISTRY_IMPL,                       // 0x47b442d0…
       salt,
       abi.encodeCall(IUserRegistry.initialize, (grants))
   );
   ```

   Each grant is `(address account, uint256 roleBitmap)`. Include at minimum
   `ROLE_REGISTRAR_ADMIN | ROLE_RENEW_ADMIN` for the deployer.

   **Use the array to pre-grant `SubnameRegistrar`'s `ROLE_REGISTRAR` here**, rather than a
   separate `grantRootRoles` call on Day 4. That is one fewer transaction and it sidesteps the
   `_ADMIN` trap below at the one place you were most likely to hit it.

3. `setSubregistry(...)` on the parent to wire the parent → child pointer

4. **`setParent(parentRegistry, label)` on the child.** This is a *separate call* — `setSubregistry`
   does **not** wire the reverse pointer, and it is not optional.

   `ENSAllowlistChecker` walks **upward** from the investor's leaf and must terminate at
   `ROOT_ANCHOR` (the `.eth` registry). A registry wired downward but never upward reports *no
   parent at all*, the walk stops early, and the checker denies everything. Miss this and it looks
   exactly like a broken checker. Requires `ROLE_SET_PARENT` on the child's root.

5. Register `brokerA` — expiry is **absolute** and there is no minimum and no clamp to the parent's
   expiry; only `CannotSetPastExpiry` applies.

   **Make the expiry a script parameter, not a constant.** The ~10-minute expiry is for *filming
   only*. Set it on Sep 6 and `brokerA` is dead for the rest of the build, taking every downstream
   test with it. Use ~30 days for development and pass the short value only when recording.

6. Deploy `BrokerARegistry`, wire under `brokerA` — **both** `setSubregistry` and `setParent`

7. Register **both** investors in `BrokerARegistry` — the tier split needs two:

   | Name | Persona | Roles |
   |---|---|---|
   | `alice` | retail | `ROLE_ELIGIBLE_SWAP` |
   | `mm` | market maker | `ROLE_ELIGIBLE_SWAP \| ROLE_ELIGIBLE_LIQUIDITY` |

   `mm` was previously only ever created inside a mocked Foundry test, while Day 6 assumed it live on
   Sepolia. Both go under the *same* broker — that is what makes beat 8 land, since one expiry takes
   out both tiers at once.

   Register them to the addresses Builder B's wallets will actually sign from (interface contract
   item 5). A subname is not trivially movable afterwards.

8. **Deploy `ENSAllowlistChecker` and record `alice`'s path**, or the end-of-day check cannot run.

   `recordPath` is `onlyAttestor` and `MintAttestor` does not exist until Day 4, so deploy with
   `attestor` set to the deployer EOA, record manually, and re-point `setAttestor` at `MintAttestor`
   tomorrow — which is why it is owner-settable.

   `ROOT_ANCHOR` = `ETHRegistry 0x1d78834d…`. `PERMISSIONED_TOKEN` is **immutable**, so the real
   checker needs Builder B's permissioned test token. If that address is not ready, verify with a
   throwaway checker bound to any address and pass the same address to `checkAllowlist`; that tests
   the walk without waiting.

**Trap:** `grantRootRoles` requires the `_ADMIN` variant of the role being granted. Still applies to
anything granted *after* deployment — getting it wrong is fatal to the registration path and subtle
to debug (risk #10). Step 2's grant array is how you avoid needing it at all for `SubnameRegistrar`.

Write `script/DeployIssuerHierarchy.s.sol` so this is repeatable and idempotent. You will run it many times.

**Idempotency has a concrete handle:** a `VerifiableFactory` proxy address is deterministic in
`(msg.sender, salt)` — the same deployer and salt always return the same address, and a different
sender with the same salt returns a different one. Have the script check for code at the predicted
address and skip redeployment rather than minting a second registry each run.

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
- The endpoint emits `ApplicationSubmitted(applicationId, wallet, broker, requestedTier)` — see interface contract item 2. **No PII in the event**, since triggers run on Workflow DON nodes outside the enclave. The form must therefore ask *which broker* the applicant is applying through; that is an input, not something CRE decides

Do **not** start `lib/uniswap.ts` / `lib/ensv2.ts`. Those are superseded by
`frontend/lib/canopy.ts`, which Builder A writes on Day 5 once every piece of the flow exists. Two
half-written contract layers is how the runner and the console drift apart.

**Naming trap for `uniswap.ts`:** the pool's currency is the **adapter**; the investor's wallet holds the **underlying**. Never call a variable just `token`. Getting this wrong produces "insufficient balance" against a wallet that visibly has funds.

**If today runs short, cut console polish, not Gate 5.** The console skeleton only needs to emit `ApplicationSubmitted` for Day 4 to proceed — styling and layout can wait until Day 6. Gate 5 cannot: Day 4 is the first day both tracks must land, and starting CRE work against unverified SDK shapes is how that day gets lost.

### 🔀 Sync — end of day

**Done when:** the real Sepolia hierarchy exists, `setParent` is wired on every child registry, and a deployed `ENSAllowlistChecker` walking it returns `SWAP_ALLOWED` for `alice` and `NONE` for an unknown address.

**Confirm before starting Day 4:** whether the checker is bound to Builder B's real permissioned token or still a throwaway. If it is a throwaway, the real one must be deployed and re-pointed before the Day 4 integration, since `PERMISSIONED_TOKEN` is immutable.

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

Then: deploy the attestor and registrar, and point the **existing** checker (deployed Sep 6) at the attestor with `setAttestor` — replacing the deployer EOA it was initialized with. Redeploy the checker only if it is still bound to a throwaway token.

`SubnameRegistrar` needs `ROLE_REGISTRAR` on each broker registry. If Sep 6's grant array already included it, there is nothing to do; otherwise grant it via `grantRootRoles`, which needs the `_ADMIN` variant.

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

# Sep 8 (Mon) — Day 5: the whole flow in the terminal

**Objective:** all eleven beats run start to finish from one command, on live Sepolia, with no
manual steps. Today is where the demo stops being a plan.

### 🅰️ Builder A — `lib/canopy.ts` and the runner

**This is today's main job, ahead of the tests.** CRE landed yesterday, so every piece of the flow
now exists; what is missing is one place that knows how to call them.

`frontend/lib/canopy.ts` — the shared module, plain viem, no React:

```ts
apply(wallet, tier)                  // beats 1-3: emits ApplicationSubmitted
eligibilityOf(wallet)                // the two badges, via checkAllowlist
hierarchyOf(wallet)                  // the walk: leaf -> broker -> issuer -> .eth, with expiries
swap(account, amountIn)              // permissioned Universal Router  0x54C707...
addLiquidity(account, params)        // PermissionedPositionManager    0xf99D55...
removeLiquidity(account, tokenId)    // beat 10 — must work after the lapse
```

Two things the module must get right, because they are the errors that cost hours:

- **adapter vs underlying.** The pool's currency is the adapter; the wallet holds the underlying.
  Keep them separately named in the types. Confusing them produces "insufficient balance" against a
  wallet that visibly has funds.
- **caller == recipient** for liquidity. `addLiquidity()` takes no recipient parameter, by design.

`scripts/e2e.ts` — the runner. Calls the module in beat order, asserts each outcome (including the
two that must *revert*), and prints a legible transcript. This is the acceptance test and the
rehearsal for the video.

It must be re-runnable: `--reset-broker` re-arms beat 8, and everything else is idempotent.

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

**Done when:** `scripts/e2e.ts` runs all eleven beats on live Sepolia, start to finish, no manual
steps — including the two that must revert (7 and 9) and the withdrawal that must still succeed (10).

Everything the console needs now exists as a function. Tomorrow is wiring, not discovery. If the
runner is not green tonight, do not start the UI — building presentation over an unproven flow is how
Day 6 and Day 7 both get lost.

---

# Sep 9 (Tue) — Day 6: swap path end-to-end

**Objective:** the full user story executes on live Sepolia.

### 🅰️ Builder A — harden the module, support the console

The swap and liquidity paths already work — Day 5's runner exercised beats 1–11 end to end. Today is
about making them usable from a browser rather than a terminal.

- Wallet-agnostic signing in `lib/canopy.ts`: the runner passes a local account, the console passes
  the investor's wallet. Same functions, injected signer.
- Typed revert decoding, so the UI can print `Unauthorized` / `SwappingDisabled` rather than a raw
  panic. Beats 7 and 9 are *revert messages* — they have to be legible on camera.
- Support Builder B through the wiring. Day 6 is the first day the two tracks share a module.

**Beat 4 — the checker swap-over — is filmed today:**
```solidity
adapter.updateAllowListChecker(ensAllowlistChecker);
```
One transaction turns a flat permissioned pool into a hierarchical one.

**`mm` must mint to itself.** `LIQUIDITY_ALLOWED` is checked **twice against two different
addresses**: the position manager checks the `recipient`, the hook's `beforeAddLiquidity` checks the
`caller`. Keeping caller == recipient means one name and one role grant satisfy both. This is why the
console cannot mint on a user's behalf, and why `addLiquidity()` takes no recipient parameter.

Liquidity goes through `PermissionedPositionManager` (`0xf99D55…`), **not** the standard v4
`PositionManager`; swaps through the permissioned Universal Router (`0x54C707…`).

**`mm` must mint to itself.** `LIQUIDITY_ALLOWED` is checked **twice against two different addresses**: the position manager checks the `recipient`, the hook's `beforeAddLiquidity` checks the `caller`. Keeping caller == recipient means one name and one role grant satisfy both. Never let the console mint on a user's behalf.

### 🅱️ Builder B — console v1, over `lib/canopy.ts`

Every beat of the flow is now a UI affordance. The module already works — Day 5's runner proved it —
so this is wiring buttons to functions, not writing contract calls.

- Application form → `apply()` (beats 1–3)
- Active brokers with **live expiry countdown** (beat 8)
- Investors per broker, role bits as two distinct badges (swap / liquidity)
- **Swap** and **Add liquidity** buttons per investor → `swap()`, `addLiquidity()` (beats 5–7)
- **Remove liquidity** for `mm` (beat 10)
- Surface revert reasons verbatim — `Unauthorized` from the router *is* the demo (beats 7, 9)

**Poll `eligibilityOf()` on a short interval.** The chain does not push. If the badges only change on
refresh, the judge watches you click at the exact moment we claim nothing is clicked. This is the
single most important UI requirement in the build.

**There is no "trigger lapse" control.** Expiry is time passing; a button that forces it would be
`unregister`, the revocation transaction we claim is unnecessary. Setup between takes is
`deploy-hierarchy.sh --reset-broker`, off camera.

**Naming trap:** the pool's currency is the **adapter**; the wallet holds the **underlying**. Never a
variable called just `token`. `lib/canopy.ts` keeps them distinct — do not flatten it in the UI.

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

Shot in the console. The eleven beats, trimmed to the five that carry the argument: `mm` adds
liquidity ✓ → retail swaps ✓ → retail `addLiquidity` **reverts** ✗ → **broker name lapses, no
transaction sent** → both investors cut off, swaps revert on-chain.

**The lapse must be one uncut shot** — badges live, nothing clicked, badges dark. An edit there is
not evidence. Set `BROKER_TTL` so the countdown crosses zero while recording, and re-arm between
takes with `deploy-hierarchy.sh --reset-broker` (off camera — it uses `unregister`).

If there is room, beat 10 is worth ten seconds: `mm` removes liquidity *after* being cut off. It
answers the "have you trapped their funds" question before a judge has to ask it.

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
