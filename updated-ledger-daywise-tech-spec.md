# Canopy — Day-by-Day Technical Spec

> **The project is named Canopy.** It was called Ledger through the planning docs; contract and
> library names use `Canopy*` (e.g. `CanopyRoles`). `canopy.eth` — 6 characters, so the $8/yr tier,
> and confirmed available on the hackathon deployment — is the **platform root**, not an issuer.

> ### ⚠️ Model change — Sep 6
>
> Canopy was single-issuer through Sep 5: `canopy.eth` *was* the issuer. It is now a **platform that
> onboards many issuers**, each of whom onboards brokers, who introduce investors.
>
> Three consequences run through everything below:
> 1. The hierarchy gains a level — platform → issuer → broker → investor.
> 2. **A broker onboarded by several issuers holds several names**, one under each. A name has one
>    parent; two issuers means two names, two registries, two independent books.
> 3. **Each issuer gets their own pool and their own checker.** Eligibility is issuer-scoped: being
>    good for Acme's pool says nothing about Zenith's.
>
> Sections marked **[new Sep 6]** or **[changed Sep 6]** are the delta. Nothing about the Uniswap
> integration, the role constants, or the expiry mechanism changed.

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
| **Gate 1** — hierarchy walk gas cost | ✅ **Closed Sep 5** · ⚠️ **confirm Sep 6** — 3-hop cold walk **65,839** against a 120k budget, **~17.9k/hop** against a 40k limit. The fourth level does **not** add a hop: `ROOT_ANCHOR` moves from `.eth` to the platform registry, so the walk is still two ancestor checks. Re-run `Gate1HierarchyGas.t.sol` against the 4-level tree — expected unchanged |
| **Gate 5** — fresh `cre init` SDK drift | ⬜ **Open** — Builder B, **Sep 6** — hard deadline, no slack behind it |

**Only Gate 5 remains, and it cannot force a pivot** — it has a known fallback (Confidential HTTP).

**Both of Gate 5's follow-up questions are answered from the docs [resolved Sep 7]** — no experiment
needed:

- **The enclave cannot do EVM reads.** *"Workflow triggers, chain reads, and chain writes… always
  execute on Workflow DON nodes, never inside the enclave."* So `EVMClient.callContract` inside
  `handlerInTee` is unavailable, and the HTTP `eth_call` the workflow uses for the Chainalysis
  oracle is the only route to on-chain data from inside the boundary — not the cautious choice, the
  only one. The same technique reads the `canopy:policy` text record when policy-hash verification
  lands.
- **In-enclave fetches do not need to be deterministic across nodes.** *"Trust derives from enclave
  attestation, not DON consensus."* One attested enclave does the work, so `Date.now()` in the
  GoPlus signature and in `expiry` is fine.

⚠️ **A third thing the docs say, which the workflow currently violates:** *"Logging within enclave
execution logic should be avoided in production workflows."* `workflow.ts` logs the verdict
**reason** (`SCORE_BELOW_THRESHOLD`, `MIXER_ASSOCIATED`, …) from inside the TEE handler — and
`cre/CRE-IMPLEMENTATION.md`'s own confidentiality table lists *which specific factors caused a
rejection* as protected. That one line is the only place our own confidentiality claim is
contradicted by our own code.

**Confidential workflows are simulation-only in the beta.** That is why we run on
`MockKeystoneForwarder`, and it is what the video has to say — a *simulated* confidential workflow
broadcasting real transactions, not a deployed one.

---

## Ownership

| | Builder A | Builder B |
|---|---|---|
| **Owns** | `contracts/` — all Solidity, Foundry tests, deploy scripts, gas benchmarks | `cre/` and `frontend/` — workflow, mock KYC, Next.js console |
| **Deploys** | Registrar, attestor, the whole ENS hierarchy, **one issuer registry and one checker per issuer**, bootstrap investor subnames | **One permissioned test token, adapter and pool per issuer** (two) |
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
   uint8   kind,             // 0 = investor.  1 = broker — reserved, see Day 7
   address subject,          // the wallet the name is registered to
   bytes32 labelBytes,
   address parentRegistry,   // the registry the name is minted into
   uint256 roleBitmap, uint64 expiry, bool approved
   ```

   **[changed Sep 6]** `brokerRegistry` → `parentRegistry`: with issuers in the tree, the parent is
   a *broker's* registry for an investor and an *issuer's* registry for a broker. `wallet` →
   `subject` for the same reason.

   **`kind` is a discriminator, and only `0` is ever emitted.** It is not a placeholder for a planned
   feature — broker registration via CRE was considered and rejected on the merits (see "Who
   registers what"). It earns its byte as a **decode guard**: `abi.decode` of a differently-shaped
   report can succeed and yield garbage rather than revert, so the attestor asserts what it is
   looking at before acting on it. Any future change to this tuple is then additive rather than a
   silent mis-decode.

2. **`ApplicationSubmitted` event** — Builder A defines, console emits, workflow triggers on it:

   ```solidity
   event ApplicationSubmitted(
       bytes32 indexed applicationId,
       address indexed wallet,      // always msg.sender
       address indexed issuer,      // DERIVED — which issuer's registry, and therefore which pool
       address broker,              // which broker's registry the applicant applies through
       string  brokerPath,          // DERIVED — "acme/prime", the policy key
       string  label,               // the subname requested
       uint8   requestedTier        // 0 = retail (swap), 1 = market maker (swap + liquidity)
   );
   ```

   Emitted by **`contracts/src/cre/ApplicationContract.sol`** (Builder A). CRE's `logTrigger`
   filters on a contract address, so a backend endpoint cannot emit this — it sends a transaction
   to a contract that does. This is the entrance to the flow; `MintAttestor` is the exit.

   **`issuer` and `brokerPath` are derived on-chain, not passed in [changed Sep 7].** The contract
   walks `getParent()` from the broker's registry to the platform root (`LibCanopyPath`). This is
   not tidiness: `brokerPath` is the key into the confidential rulebook, so a caller who could name
   it would pick the loosest entry in the book — be evaluated under `zenith/_default` while being
   minted into a broker whose real policy is far stricter. The mint would land correctly and the
   *evaluation* would be wrong, which is the hardest kind of hole to notice.

   `submitApplication(address broker, string label, uint8 requestedTier)` is therefore the whole
   signature. `wallet` is `msg.sender`, so an applicant proves control of the address they are
   applying for; a `wallet` parameter would let anyone apply in someone else's name.

   Contains **no PII** — triggers run on Workflow DON nodes, not in the enclave. Issuer, broker and
   broker path are not PII, so carrying them here is safe.

   **`issuer` is required [new Sep 6].** An applicant applies *to a specific issuer, through* a
   specific broker. The pair decides which pool the eligibility is good for and which policy
   evaluates them.

   ⚠️ **Solidity allows three indexed parameters.** Adding `issuer` demotes `broker` to unindexed.
   **That changes Builder B's log filter** — but filtering by issuer is what a per-issuer workflow
   wants anyway.

   **`brokerPath` is required [new Sep 6].** The rulebook is keyed by label path, not by registry
   address, because addresses move every time we redeploy and label paths don't. The alternative —
   recovering the path in the workflow by walking `getParent()` twice — is two EVM reads inside the
   enclave on the highest-risk day.

   `broker` carries the registry the subname is minted into. Resolving it inside the enclave would
   put a lookup in the TEE for a value that is not secret. The broker is an *input* to the
   application, not something CRE decides.

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

   **[changed Sep 6]** One wallet may now legitimately hold *several* subnames — one per issuer it
   is eligible under. The old "every investor needs a distinct address" rule becomes **distinct
   within an issuer**.

6. **The policy hash [new Sep 6].** Builder B authors the issuer and broker policies and holds the
   bodies in the CRE Vault secret. Builder A writes their **hashes** into ENS text records. Only the
   hash crosses the boundary — it travels in `script/hierarchy.json` as `policyHash`. See "Where
   policy lives".

---

## The end-to-end flow

This is the demo, and it is also the acceptance test. Everything else in this document exists to
make these fifteen beats run.

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

### The hierarchy [new Sep 6]

```
.eth   (ETHRegistry — ENS itself, above our world)
└── canopy.eth                          PLATFORM root
    ├── acme.canopy.eth                 issuer 1  ──▶ pool 1, acmeChecker
    │   ├── prime.acme.canopy.eth       broker
    │   │   ├── alice                   retail    (SWAP)
    │   │   └── mm                      market maker (SWAP | LIQUIDITY)
    │   └── delta.acme.canopy.eth       broker, stricter policy
    └── zenith.canopy.eth               issuer 2  ──▶ pool 2, zenithChecker
        └── prime.zenith.canopy.eth     THE SAME BROKER, a second name
            ├── bob                     retail
            └── mm2                     Zenith's market maker
```

**Why `prime` appears twice.** A name has exactly one parent, so a broker onboarded by two issuers
holds two names in two registries. This is the mechanism, not a workaround: Acme dropping Prime must
not touch Zenith's relationship with Prime, and two names give you that for free. Each issuer's grant
expires on its own schedule.

The same follows for investors. `alice` under `prime.acme` and `alice` under `prime.zenith` are two
names for one wallet, and **each requires its own application** — see below.

### Who registers what

| What | Registered by | CRE involved? |
|---|---|---|
| `canopy.eth` | the platform — `DeployIssuerHierarchy` | no |
| `acme`, `zenith` | the platform — `DeployIssuerHierarchy` | no |
| `prime`, `delta`, … under each issuer | **the issuer** — `DeployIssuerHierarchy` | no |
| `alice`, `mm`, `bob`, … | `MintAttestor`, on a CRE verdict | **yes** |

**Issuers are onboarded by the platform.** A commercial contract; the root of trust has to sit
somewhere. Not a CRE decision, and deliberately so.

**Brokers are onboarded by their issuer, not by CRE [decided Sep 6].** Acme's admin key registers
`prime` in Acme's registry with an expiry. Routing this through CRE was considered and rejected: it
would buy third-party verifiability of a decision the issuer is entitled to make unilaterally, and
nothing else. In particular it would **not** add the expiry cascade — that is a property of the
*name*, not of who minted it, so Acme registering `prime` for 90 days gives the identical
non-transaction revocation.

**This is a decision on the merits, not a deferral.** It is not parked on a later day and it is not
a stretch goal: spare capacity should go somewhere that buys more. It is written up here so nobody
re-proposes it in week two without new information.

**Investors apply to an issuer, through a broker.** The applicant names both; CRE decides only
**approved or not** and **at what tier**, against that broker's policy under that issuer. It never
decides *under whom* — issuer and broker are inputs, and `parentRegistry` rides in the report so
`MintAttestor` knows where to mint.

**One application per (issuer, broker) pair.** Being onboarded by Prime does *not* grant access to
every issuer Prime works with. If it did, Zenith's pool would admit an account Zenith's rulebook
never evaluated — which is the first thing a judge probes. Alice wanting Zenith's pool applies again
and Zenith's policy gets a say.

**Only a CRE verdict can mint eligibility.** The broker never sends the transaction;
`MintAttestor` does, holding `ROLE_REGISTRAR` on each broker registry. A broker cannot onboard a
client who failed the check. That is what makes the cascade meaningful: a broker controls nothing
about eligibility except their own name staying alive, and when it lapses everyone they introduced
goes with them.

Investors registered directly by the deploy script are **bootstrap only** — Day 3 precedes CRE, and
the demo needs its cast guaranteed present. Everyone after that arrives through the product.

### Cross-issuer isolation [new Sep 6]

**One checker per issuer pool**, each with a new immutable `ISSUER_REGISTRY` that the upward walk
must **pass through** before it terminates at `ROOT_ANCHOR`.

Without it, every checker under one platform root admits every issuer's investors: the walk asserts
only *"reaches `ROOT_ANCHOR`"*, which under a shared root degrades to *"is somewhere in Canopy"*.
Acme's pool would admit Zenith's clients.

This is the multi-tenant twin of the `setParent` trap — a happy-path test never catches it, and the
failure grants rather than denies. Both are guarded by fork tests.

One checker per issuer rather than one multi-tenant checker, because it keeps `leafOf` as
`mapping(address => Leaf)`: each checker holds its own leaf per wallet, so a wallet eligible under
both issuers needs no storage change. A single shared checker would need
`mapping(account => mapping(issuer => Leaf))`, and getting that wrong means Zenith's mint silently
overwrites Acme's and revokes it.

### The fifteen beats

Setup (idempotent, off camera): **two** permissioned tokens + adapters + pools, each with the flat
checker (B); platform root, two issuers, brokers, registries, attestor, registrar, two checkers (A);
investors holding the right underlying token with Permit2 approved; **Zenith's pool seeded with depth
by its own market maker**, so beat 10 has somewhere to trade.

| # | Beat | Proves |
|---|---|---|
| 1 | `alice` applies **to Acme through `prime`** → CRE **APPROVE** → subname minted under `prime.acme` with `ROLE_ELIGIBLE_SWAP` | the CRE mint path |
| 2 | A second applicant → CRE **REJECT** → no subname, no access | the engine actually discriminates |
| 3 | That same applicant re-applies **through `delta`** (stricter policy, same issuer) → still **REJECT**; a borderline applicant passes under `prime` and fails under `delta` | **per-broker criteria are real** — one engine, two rulebooks, neither disclosed |
| 4 | `mm` applies → APPROVE with **both** role bits | two tiers exist |
| 5 | `acmeAdapter.updateAllowListChecker(acmeChecker)` | one transaction turns a flat permissioned pool into a hierarchical one |
| 6 | `mm` adds liquidity on **Acme's** pool (caller == recipient) → **succeeds** | the MM tier, and the pool gets depth |
| 7 | `alice` swaps on Acme's pool → **succeeds** | the retail tier |
| 8 | `alice` attempts `addLiquidity` → **reverts** | **the tier split.** Two successes prove nothing; the refusal is the proof |
| 9 | `alice` attempts a swap on **Zenith's** pool → **reverts** | **cross-issuer isolation.** Eligibility is issuer-scoped, enforced on-chain |
| 10 | `bob`, onboarded by `prime` **under Zenith**, swaps on Zenith's pool → **succeeds** | one broker, two issuers, two independent books |
| 11 | **Acme's `prime` lapses** — countdown to zero, **no transaction sent** | the money shot |
| 12 | `alice` and `mm` both attempt swaps on Acme → **both revert `Unauthorized`** | the chain refusing, not our UI greying out |
| 13 | `bob` swaps on Zenith → **still succeeds** | **containment.** One issuer dropped one broker; the same broker's other book is untouched |
| 14 | `mm` removes liquidity → **succeeds** | not frozen. Exposure can always be unwound |
| 15 | Acme re-registers `prime` → its investors stay dead | version-stamped resources; a lapsed broker cannot resurrect their book |

**Ordering is load-bearing.** Beat 6 must precede beat 7 — the pool needs depth before anyone can
swap. Beat 5 must precede 6–8, or the flat checker is still answering. Beat 10 needs Zenith's pool
already seeded, which is why that is setup rather than a beat.

**Why 2, 3, 8, 9, 12, 13, 14 and 15 are not optional.** Each closes a hole a judge would otherwise
find: beat 2 that the rulebook ever says no; beat 3 that "per-broker criteria" is a real mechanism
and not a config file we describe; beat 8 that tiers are real; beat 9 that one issuer's approval is
not a platform-wide pass; beat 12 that the cut-off is enforced on-chain rather than by our frontend;
beat 13 that the cascade is *scoped* — without it the lapse looks like a global kill switch; beat 14
that we have not trapped anyone's funds, since decreases and burns are never gated in the standard
and a knowledgeable judge is already wondering; beat 15 that the cascade cannot be undone by
re-registering.

**Beats 9 and 13 are the two the new model exists to prove.** Isolation and containment. Both must
be *reverts and successes on-chain*, never a badge going dark — a read-only demonstration is exactly
the version a judge discounts.

**Beat 11 is never a button.** Expiry is time passing. The only control that could force it is
`unregister`, which is exactly the revocation transaction the pitch claims is unnecessary — filming
it would refute the thesis. Setup between takes uses
`contracts/script/deploy-hierarchy.sh --reset-broker`, off camera.

**Beat 11 also has to be uncut**, and the badges must change with nobody touching the page. The chain
does not push, so the console polls. If the moment needs a refresh, the judge sees a click.

**The runner asserts all fifteen; the video films about six** — 6, 7, 8, 11, 12, 13, with 14 if there
is room. See Day 9.

---

## Where policy lives [new Sep 6]

Each broker may onboard investors on their own criteria, tighter than their issuer's floor. The
policy has to be confidential, readable from the enclave, and controlled by the broker. **No single
location gives all three:**

| where | stays confidential | enclave can read it | broker can write it |
|---|---|---|---|
| repo (`main.ts`, a JSON file) | ❌ a public repo is a prize requirement | ✅ | ❌ |
| on-chain (contract storage, text record) | ❌ | ✅ | ✅ |
| **CRE Vault DON secret** | ✅ | ✅ | ❌ owner-scoped |
| broker's own endpoint / IPFS | broker's choice | ✅ via `ConfidentialHTTPClient` | ✅ |

So it is split across three artifacts:

| artifact | where | public? | owned by |
|---|---|---|---|
| policy **body** — the values | Vault DON secret `ELIGIBILITY_RULEBOOK` | no | B |
| policy **hash** | ENS text record `canopy:policy` on the broker's own name | yes | A (deploy script) |
| policy **schema** — field list + combination rules | `cre/policy-schema.md` + a TS type, in the repo | **yes, deliberately** | B |

Publishing the schema is not a leak — it is what makes the CRE claim checkable. A judge reads exactly
what a policy can express and confirms none of the discriminating values are in the code.

### The body

One secret, one JSON object, flat keys on a **label path** — not a registry address, because
addresses move every time we redeploy and label paths don't:

```json
{
  "acme/_default":   { "version": 1, "minScore": 70, "maxTier": 1, "expiryDays": 365,
                       "jurisdictions": { "allow": ["US-NY","GB","SG"], "deny": ["IR","KP"] } },
  "acme/prime":      { "version": 1, "minScore": 80, "expiryDays": 90 },
  "acme/delta":      { "version": 1, "minScore": 90, "maxTier": 0, "expiryDays": 30 },
  "zenith/_default": { "version": 1, "minScore": 75, "maxTier": 1, "expiryDays": 180 }
}
```

Broker entries are **overrides, not complete policies**: anything absent inherits the issuer default.

`expiryDays` is the field to point at in the demo — `expiry` is already in the report tuple, so a
broker choosing 30 vs 365 shows up **on-chain as different subname expiries with no new machinery**,
and feeds the existing cascade. A conservative broker's book turns over quarterly. That is
per-broker configuration a judge can see in a block explorer, which beats a threshold nobody can.

### A broker may tighten, never loosen

Combination is per field type, applied **inside the enclave** so the effective policy is never
disclosed:

| field type | combination | effect |
|---|---|---|
| numeric threshold (`minScore`, `minAge`) | `max(issuer, broker)` | broker can raise the bar |
| allowlist (`jurisdictions.allow`, `accreditation`) | intersection | broker can only narrow |
| denylist (`jurisdictions.deny`) | union | broker can only add |
| `maxTier` | `min(issuer, broker)` | a retail-only broker cannot mint an MM |
| `expiryDays` | `min(issuer, broker)` | broker cannot outlive the issuer's ceiling |

This is what a compliance control *is*: the issuer sets the rules and gives up the discretion to make
exceptions for a broker they want business with.

### The hash

Text record on the broker's own name, **scheme-prefixed**:

```
canopy:policy = "keccak256:0x8f3a…"
```

The prefix is why this design does not foreclose the broker-hosted version: it becomes
`ipfs://bafy…` later and the workflow switches on the prefix. Nothing else moves — not the record
key, not the role grant, not the deploy script.

Issuer defaults get the same treatment one level up, so an issuer cannot quietly rewrite their own
floor either.

⚠️ **Canonicalize before hashing** — sorted keys, no whitespace, UTF-8, integers (RFC 8785 if you
want a spec to cite). A hash over pretty-printed JSON breaks the first time an editor reformats it,
and it breaks intermittently.

**The role that makes it the broker's:** grant them `ROLE_SET_RESOLVER` (`1<<24`) scoped to their own
name's resource in the issuer's registry, at registration. They can update their pointer; the issuer
cannot.

### What the workflow does

```
1. trigger → (issuer, broker, brokerPath, wallet, requestedTier)
2. book = getSecrets(["ELIGIBILITY_RULEBOOK", "KYC_API_TOKEN"])
3. issuerPolicy = book["acme/_default"];  brokerPolicy = book["acme/prime"]
4. assert keccak(canonical(p)) == textRecord(<name>, "canopy:policy")   for both
5. effective = combine(issuerPolicy, brokerPolicy)
6. evaluate the applicant against effective
7. expiry = now + effective.expiryDays
```

**Step 4 needs no confidentiality** — both sides of the comparison are public. If Gate 5 finds the
enclave cannot do EVM reads, move the check outside it with no loss. The design survives either
answer.

**Updating a policy is two non-atomic writes** (secret, then record). In between, the hashes disagree
and the workflow **rejects every application**. That is the correct failure mode and matches the
checker — fail closed, never grant on an inconsistent view. Do not "fix" it into a warning.

**One workflow, not one per broker.** `MintAttestor` gates on a single `EXPECTED_WORKFLOW_ID`; N
workflows would mean a mapping in the attestor and a registration step per broker, and onboarding a
broker would stop being a config change.

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

### Canopy's own constants [new Sep 6]

| | Value | |
|---|---|---|
| ENS text record key | `canopy:policy` | set on issuer and broker names |
| record value, now | `keccak256:0x…` | hash of the canonical policy JSON |
| record value, later | `ipfs://…` | the broker-hosted upgrade; workflow switches on the prefix |
| broker registry salt | `keccak256("canopy.broker.v1.", issuerLabel, brokerLabel)` | **must include the issuer** — see Day 3 |
| address-book key | `registry_<issuer>_<broker>` | **must include the issuer** — see Day 3 |
| policy key | `"<issuerLabel>/<brokerLabel>"`, `"<issuerLabel>/_default"` | label path, not address |

**`PermissionedResolverImpl` (`0xa9d3814a…`) moves from "listed" to "used" [new Sep 6].** We set no
resolver on any name until now. ⚠️ **Unverified:** whether it is shared or needs a proxy per name.
Check on Day 3 before the text-record write goes into the script.

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
Sep 6   A: live ENS hierarchy    A: 2 checkers ◄─ needs token ────┘
  D3      A: platform+2 issuers  B: Gate 5 cre init  ────────────┐
          │                      B: console skeleton             │
          │                                                      │
Sep 7   A: attestor + registrar  B: CRE workflow ◄───── needs Gate 5
  D4      └──────────┬───────────────────┘
                     ▼  first full integration — CRE → mint → checker
Sep 8   A: runner + cascade tests   B: REJECT path + SECOND POOL
Sep 9   A: harden the module        B: console v1
                     ▼  full user story on Sepolia, both issuers
Sep 10     A: benchmarks   B: polish + policy hash (cuttable)
Sep 11     docs, adversarial retests
Sep 12     video + submission
Sep 13     submit + buffer
```

**Hard dependencies to protect:**
- ~~**MockUSDC blocks Sep 6.**~~ **Retired Sep 5.** `MockUSDC.mint(address,uint256)` at `0xcbfd80f7…` is **permissionless** — verified by simulating it from two unrelated addresses. Builder A self-serves; this is no longer a cross-track dependency, and it was the hardest one in the plan.
- **Gate 5 blocks Sep 7.** Moved off Sep 5 because Builder B cannot fit it alongside the pool work. It now has a hard deadline of end of Sep 6, with nothing behind it.
- **Builder B's permissioned token blocks the *real* checker deployment.** `ENSAllowlistChecker.PERMISSIONED_TOKEN` is immutable, so the production checker cannot be deployed until that address exists. Smaller than the dependency it replaces: Sep 6's verification runs against a throwaway checker bound to any address, so nothing is blocked in the meantime. **[changed Sep 6] There are now two of these — one token per issuer, so two checkers.**
- **Sep 7 is the first real integration.** Both tracks must land. Neither builder starts Sep 7 work before their Sep 6 deliverable is green.
- **The second pool lands Sep 8 [new Sep 6].** It goes there because Sep 6 (Gate 5) and Sep 7 (CRE) are the two days with no slack, and Sep 8 is Builder B's lightest. ⚠️ **Ask today:** was the Sep 5 pool sequence a *parameterized script* or manual `cast` calls? A script makes pool 2 a re-run with new arguments — about an hour, since every trap in that sequence is already known. Manual makes it a re-do. If it was manual, parameterizing it costs an hour today and saves most of Sep 8; discovering that on Sep 8 is the bad version.

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
| ~~P2~~ | Gate 1 gas measurement | 🅰️ | ✅ **Done Sep 5** — 3-hop passes with headroom. The Sep 6 model change does not add a hop; confirm and move on |
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

**[changed Sep 6]** Arriving is now necessary but not sufficient — the walk must also **pass
through** the checker's `ISSUER_REGISTRY`. See "Cross-issuer isolation".

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

**3. 🎯 Gate 1 — hierarchy walk gas — ✅ CLOSED Sep 5.**

> **[Sep 6] Still closed after the model change.** The tree gained a level, but `ROOT_ANCHOR` moved
> from `.eth` to the platform registry, so the walk is the same two ancestor checks and the numbers
> below stand. Re-run `Gate1HierarchyGas.t.sol` against the 4-level tree to confirm rather than to
> discover.

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

**Objective:** a real **four-level** hierarchy exists on Sepolia — platform, two issuers, brokers,
investors — and **each issuer's checker** returns correct flags walking it, including denying the
other issuer's investors.

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

> **[changed Sep 6, built Sep 7] The tree is now four levels.** Steps 1–4 build the platform root,
> step 5 builds the issuers, and steps 6–8 repeat per issuer instead of once. The script phase list
> is `commitParent() → registerParent() → buildIssuers() → buildHierarchy() → deployCheckers()`,
> plus `grantAttestor(address)` on Day 4. `./script/deploy-hierarchy.sh` runs all of it.

1. Deploy `PlatformRootRegistry` (a `UserRegistry`) via `VerifiableFactory` (`0x894bc9cc…`)
   — **renamed from `IssuerRootRegistry`**, which now means something else

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

   **`ROLE_REGISTRAR_ADMIN` is the load-bearing entry.** `grantRootRoles` requires the `_ADMIN`
   twin of the role being granted, so this is what lets Day 4 hand `MintAttestor` its minting
   rights. Without it the grant is impossible after deployment and the registry has to be
   rebuilt.

   **[new Sep 6] Do this on every *issuer* registry too, not only broker registries.** Nothing this
   week mints into an issuer registry — brokers are registered by their issuer directly. Grant it
   anyway: it is one array entry, and it means any later need to mint under an issuer avoids
   `grantRootRoles` and its `_ADMIN` variant entirely. The trap below is the reason; a grant you
   never use costs nothing, and a grant you need after deployment costs an afternoon.

3. `setSubregistry(...)` on the parent to wire the parent → child pointer

4. **`setParent(parentRegistry, label)` on the child.** This is a *separate call* — `setSubregistry`
   does **not** wire the reverse pointer, and it is not optional.

   `ENSAllowlistChecker` walks **upward** from the investor's leaf and must terminate at
   `ROOT_ANCHOR` (the platform registry). A registry wired downward but never upward reports *no
   parent at all*, the walk stops early, and the checker denies everything. Miss this and it looks
   exactly like a broken checker. Requires `ROLE_SET_PARENT` on the child's root.

5. **[new Sep 6] Register each issuer under the platform root**, then deploy each an
   `IssuerRegistry` and wire **both** `setSubregistry` and `setParent`. Structurally identical to
   step 6 below, one level up — same call, no commit–reveal, no payment.

   Give issuers a **long** expiry. An issuer lapsing cascades to every broker and every investor
   beneath them, which is a bigger event than the one we are filming and not one we want by
   accident.

6. Register each broker **in its issuer's registry** — expiry is **absolute** and there is no
   minimum and no clamp to the parent's expiry; only `CannotSetPastExpiry` applies.

   Then deploy that broker a `BrokerRegistry` and wire **both** `setSubregistry` and `setParent`.

   Also grant the broker `ROLE_SET_RESOLVER` (`1<<24`) **scoped to their own name's resource** in
   the issuer's registry, so the policy pointer is theirs to update and not the issuer's. Write the
   `canopy:policy` text record if `policyHash` is present in the config; skip it silently if not, so
   the script keeps working before Builder B has authored any policies.

   **Make the expiry a per-broker script parameter, not a global constant.** The ~10-minute expiry is
   for *filming only*, and a global short TTL expires every broker at once — which on camera looks
   like a global kill switch rather than a scoped cascade, destroying beat 13. Use ~30 days for
   development and pass the short value only for the one broker being filmed.

   ⚠️ **Two collisions that only appear once a broker label repeats under two issuers** — which is
   exactly what `prime` does, so this is not hypothetical:

   - **The `VerifiableFactory` salt must include the issuer.** Proxy addresses are deterministic in
     `(msg.sender, salt)`. With a salt over the broker label alone, `prime` under Acme and `prime`
     under Zenith resolve to the **same proxy address** — and the script's idempotency check (code at
     the predicted address → skip) would then hand Zenith's Prime the registry belonging to Acme's
     Prime. Acme's expiry would silently cut off Zenith's investors. Salt over
     `(issuerLabel, brokerLabel)`.
   - **The address-book key must include the issuer.** `registry_<broker>` is written twice; use
     `registry_<issuer>_<broker>`.

7. Register the bootstrap investors in each broker's registry — the tier split needs two under one
   broker, and beat 13 needs a second issuer's book to survive:

   | Name | Under | Persona | Roles |
   |---|---|---|---|
   | `alice` | `prime.acme` | retail | `ROLE_ELIGIBLE_SWAP` |
   | `mm` | `prime.acme` | market maker | `ROLE_ELIGIBLE_SWAP \| ROLE_ELIGIBLE_LIQUIDITY` |
   | `bob` | `prime.zenith` | retail | `ROLE_ELIGIBLE_SWAP` |
   | `mm2` | `prime.zenith` | market maker, seeds pool 2 | `ROLE_ELIGIBLE_SWAP \| ROLE_ELIGIBLE_LIQUIDITY` |

   `alice` and `mm` go under the *same* broker — that is what makes beat 11 land, since one expiry
   takes out both tiers at once. `bob` sits under the *same broker under a different issuer*, which
   is what makes beat 13 land.

   Register them to the addresses Builder B's wallets will actually sign from (interface contract
   item 5). A subname is not trivially movable afterwards.

   **[changed Sep 6]** The script's "every investor needs a distinct address" guard becomes
   **distinct within an issuer**. One wallet holding a name under both issuers is now correct, and
   the old global guard would reject it.

8. **Deploy one `ENSAllowlistChecker` per issuer and record every bootstrap investor's path**, or
   the end-of-day check cannot run.

   `recordPath` is `onlyAttestor` and `MintAttestor` does not exist until Day 4, so deploy with
   `attestor` set to the deployer EOA, record manually, and re-point `setAttestor` at `MintAttestor`
   tomorrow — which is why it is owner-settable.

   **[changed Sep 6] `ROOT_ANCHOR` is the platform registry, not `ETHRegistry`.** Anchoring at
   `.eth` would add a fourth hop purely to check that `canopy.eth` — our own name, which we renew —
   has not lapsed. Anchored at the platform registry the walk is still two ancestor checks (the
   broker's name in the issuer's registry, the issuer's name in the platform registry), so **the
   issuer's expiry still cascades and Gate 1's number does not move**.

   **[new Sep 6] `ISSUER_REGISTRY` is a second immutable**, and the walk must pass through it. See
   "Cross-issuer isolation" — without it, every issuer's checker admits every other issuer's
   investors.

   `PERMISSIONED_TOKEN` is **immutable** and there are now two of them, one per issuer, read from
   `PERMISSIONED_TOKEN_ACME` / `PERMISSIONED_TOKEN_ZENITH`. They are separate variables on purpose:
   two checkers bound to the same token would answer for each other's pool and quietly undo the
   isolation. If Builder B's addresses are not ready, each falls back to a per-issuer placeholder
   and prints a warning; that tests the walk without waiting.

   **`resetBroker` now takes `(issuer, broker)`** — `ISSUER=acme BROKER=prime` for the shell
   driver. A broker label can appear under several issuers, and re-arming the wrong one silently
   resets the broker that is supposed to *survive* the filmed lapse.

**Trap:** `grantRootRoles` requires the `_ADMIN` variant of the role being granted. Still applies to
anything granted *after* deployment — getting it wrong is fatal to the registration path and subtle
to debug (risk #10). Step 2's grant array is what makes `grantAttestor(address)` possible on Day 4.

Write `script/DeployIssuerHierarchy.s.sol` so this is repeatable and idempotent. You will run it many times.

**Idempotency has a concrete handle:** a `VerifiableFactory` proxy address is deterministic in
`(msg.sender, salt)` — the same deployer and salt always return the same address, and a different
sender with the same salt returns a different one. Have the script check for code at the predicted
address and skip redeployment rather than minting a second registry each run. **See step 6 for why
that same determinism is a hazard once a broker label repeats.**

**Config shape.** `script/hierarchy.json` nests one level deeper: `issuers[] → brokers[] →
investors[]`, with `ttl` on issuers and brokers and an optional `policyHash` per broker and per
issuer. A broker onboarded by two issuers appears as two entries with the same `label` under
different issuers — that is the intended way to express it.

**Fork rehearsal gains three cases** in `test/fork/HierarchyRehearsal.t.sol`, all against live
contracts: an issuer lapse cascading to every broker beneath it while the other issuer is untouched;
a broker dropped by one issuer keeping their book under the other (beat 13); and an investor under
one issuer denied by the other issuer's checker (beat 9).

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
- The endpoint emits `ApplicationSubmitted(applicationId, wallet, issuer, broker, brokerPath, requestedTier)` — see interface contract item 2. **No PII in the event**, since triggers run on Workflow DON nodes outside the enclave. The form must therefore ask **which issuer, and which broker under them** — both are inputs, not something CRE decides
- **[new Sep 6] The form is a two-step select:** pick the issuer, then pick from the brokers that
  issuer has onboarded. The same broker appearing under two issuers is expected, and picking it
  under Acme is a different application from picking it under Zenith

Do **not** start `lib/uniswap.ts` / `lib/ensv2.ts`. Those are superseded by
`frontend/lib/canopy.ts`, which Builder A writes on Day 5 once every piece of the flow exists. Two
half-written contract layers is how the runner and the console drift apart.

**Naming trap for `uniswap.ts`:** the pool's currency is the **adapter**; the investor's wallet holds the **underlying**. Never call a variable just `token`. Getting this wrong produces "insufficient balance" against a wallet that visibly has funds.

**If today runs short, cut console polish, not Gate 5.** The console skeleton only needs to emit `ApplicationSubmitted` for Day 4 to proceed — styling and layout can wait until Day 6. Gate 5 cannot: Day 4 is the first day both tracks must land, and starting CRE work against unverified SDK shapes is how that day gets lost.

### 🔀 Sync — end of day

**Done when:** the real Sepolia hierarchy exists four levels deep, `setParent` is wired on every child
registry, and **each issuer's** deployed `ENSAllowlistChecker` returns `SWAP_ALLOWED` for its own
investor, `NONE` for an unknown address, **and `NONE` for the other issuer's investor.** That last
assertion is beat 9 and the reason the model changed — do not call the day done without it.

**Confirm before starting Day 4:**
- whether each checker is bound to Builder B's real permissioned token or still a throwaway. If a
  throwaway, the real one must be deployed and re-pointed before the Day 4 integration, since
  `PERMISSIONED_TOKEN` is immutable — and there are now two.
- **whether Builder B's Sep 5 pool sequence was a parameterized script.** If not, parameterize it
  today. See "Hard dependencies".
- Gate 5's two new answers (enclave EVM reads, fetch determinism).

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

    (uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
     uint256 roleBitmap, uint64 expiry, bool approved)
        = abi.decode(report, (uint8, address, bytes32, address, uint256, uint64, bool));

    if (!approved) return;          // REJECT is a no-op on-chain
    if (kind != KIND_INVESTOR) revert UnsupportedKind(kind);   // see Day 7

    string memory label = LibLabelBytes.toString(labelBytes);
    REGISTRAR.registerFromAttestation(subject, label, parentRegistry, roleBitmap, expiry);

    // [new Sep 6] Which issuer's checker? Derive it on-chain rather than trusting the report:
    // parentRegistry is the broker's registry, so one getParent() hop gives the issuer's.
    (IRegistry issuerRegistry, ) = IRegistry(parentRegistry).getParent();
    ENSAllowlistChecker checker = checkerOf[address(issuerRegistry)];
    if (address(checker) == address(0)) revert NoCheckerForIssuer(address(issuerRegistry));
    checker.recordPath(subject, parentRegistry, LibLabel.id(label));
}
```

**Three things worth understanding, not just copying:**
- The workflow-ID check is **ours to add** — `ReceiverTemplate` decodes metadata but doesn't validate it. Without this guard, *any* workflow routed through the same forwarder could mint subnames. This is the security-relevant line in the contract.
- `labelBytes` carries the **label itself**, right-padded into `bytes32` — not its hash. `register()` needs a `string` and a hash can't be reversed, but `string` is dynamic and CRE reports are flat. `LibLabelBytes.toString` is ~10 lines: trim trailing zero bytes. This caps labels at 32 bytes — fine for the demo, worth a line in `FEEDBACK.md`.
- **[new Sep 6] The checker is derived from the chain, not read from the report.** `checkerOf` is an
  owner-set `mapping(address issuerRegistry => ENSAllowlistChecker)`, and the issuer registry comes
  from `getParent()` on the registry the name was minted into. A compromised workflow can therefore
  choose *what to mint*, but not *which issuer's pool the eligibility lands in*. Passing the checker
  address in the report would give that away for nothing.

**`kind` is decoded and rejected unless it is `KIND_INVESTOR`.** Nothing else is ever emitted — this
is a decode guard, not a feature flag. See interface contract item 1.

**`SubnameRegistrar` no longer exists [changed Sep 7].** `MintAttestor` calls
`IPermissionedRegistry.register` directly. The registrar never held logic of its own — it was a
pass-through with an `onlyAttestor` modifier — so collapsing the two removes a contract and a hop
without changing what is enforced.

**The grant moves with it: `MintAttestor` needs `ROLE_REGISTRAR` on every broker registry.** Run
`DeployIssuerHierarchy --sig "grantAttestor(address)"`, which also calls `setAttestor` on the
checker. Missing either half fails at the first real mint and reads as a checker bug.

Then: deploy the attestor and registrar, register **every** issuer's checker in `checkerOf`, and
point **each existing checker** (deployed Sep 6) at the attestor with `setAttestor` — replacing the
deployer EOA it was initialized with. Redeploy a checker only if it is still bound to a throwaway
token.

**`allowedWorkflowId` fails closed [new Sep 7].** The attestor rejects *every* report until
`setWorkflow(bytes32)` is called, because the workflow id does not exist until the workflow is
deployed. A permissive default would leave a live attestor accepting reports from any workflow on
the same forwarder during that window — which is the security-relevant line in the contract.

### Forwarders and ERC-165 — resolved Sep 7

| | Address | Used by |
|---|---|---|
| `MockKeystoneForwarder` | `0x15fC6ae953E024d975e77382eEeC56A9101f9F88` | `cre workflow simulate --broadcast` — **ours** |
| `KeystoneForwarder` (production) | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` | a deployed workflow |

**We run on the mock, and that is correct rather than a shortcut.** Confidential workflows are in
private beta and support simulation only, so `simulate --broadcast` is how reports reach Sepolia.

⚠️ **ERC-165 is required, and its absence is invisible to us.** `KeystoneForwarder` calls
`supportsInterface(type(IReceiver).interfaceId)` before delivering; a receiver that does not answer
never receives a report. **The mock does not make that call** — confirmed by reading both deployed
bytecodes: `01ffc9a7` appears in the production forwarder and not in the mock, and neither
implements ERC-165 itself, so that constant is there to *call* receivers with. A missing
`supportsInterface` would therefore pass every demo we run and fail the moment the beta opens.
`MintAttestor` implements it, and a test pins `type(IReceiver).interfaceId == 0x805f2132`.

**Metadata layout** — 64 packed bytes, workflow id first, so `bytes32(metadata[:32])` is right:

| offset | size | field |
|---|---|---|
| 0 | 32 | `workflowId` |
| 32 | 10 | `workflowName` |
| 42 | 20 | `workflowOwner` |
| 62 | 2 | `reportId` |

The attestor requires only 32 bytes, not 64 — it validates the workflow id and nothing else, and
requiring more than it reads would make it depend on the mock and production forwarders packing
identically.

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

**[new Sep 6] `ELIGIBILITY_RULEBOOK` is now a keyed map, not one policy.** Resolve
`book[brokerPath]` over `book["<issuer>/_default"]`, and combine them with the tighten-only rules in
"Where policy lives" — a broker may raise a threshold, narrow an allowlist, add a denial or shorten
an expiry, never the reverse. `effective.expiryDays` becomes the report's `expiry`, which is how
per-broker policy becomes visible on-chain.

**One workflow, not one per broker.** `MintAttestor` gates on a single `EXPECTED_WORKFLOW_ID`, so N
workflows would mean a mapping in the attestor and a registration step per broker.

**Policy-hash verification is optional today, scheduled for Day 7.** If it fits, verify
`keccak(canonical(policy))` against the `canopy:policy` text record before evaluating; the comparison
uses only public values, so it can sit outside the enclave. If Day 4 is tight, skip it — reading the
keyed rulebook is the part Day 4 needs.

Crossing back out:
```ts
const donRuntime = runtime.usingTheDons()   // everything past here is NOT confidential
const report = donRuntime.report({ encodedPayload: hexToBase64(reportData),
  encoderName: "evm", signingAlgo: "ecdsa", hashingAlgo: "keccak256" }).result()
evmClient.writeReport(donRuntime, { receiver: mintAttestorAddress, report, gasConfig: { gasLimit } })
```

Report payload — flat tuple, **no dynamic arrays**:
```
uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
uint256 roleBitmap, uint64 expiry, bool approved
```
`kind` is always `0` this week. See interface contract item 1 for why it is carried anyway.

Also build `cre/kyc-mock/server.ts` — deterministic responses keyed by `applicationId` so the demo is repeatable.

**[new Sep 6] Publish `cre/policy-schema.md`** — the field list and the combination rules, in the
public repo. It is the artifact that makes the confidentiality claim checkable: a judge reads exactly
what a policy can express and confirms none of the values are in the code.

Run everything with `--broadcast`.

### 🔀 Sync — end of day

**Done when this full chain works:** `cre workflow simulate --broadcast` → APPROVE verdict → forwarder tx on Sepolia → `MintAttestor.onReport` mints the subname and records the leaf → `acmeChecker.checkAllowlist(alice, acmeToken)` returns `SWAP_ALLOWED` **and `zenithChecker.checkAllowlist(alice, zenithToken)` returns `NONE`.**

If the chain breaks, debug from the on-chain end backwards — the forwarder tx hash in the CRE output tells you whether the problem is before or after the chain boundary.

---

# Sep 8 (Mon) — Day 5: the whole flow in the terminal

**Objective:** all fifteen beats run start to finish from one command, on live Sepolia, with no
manual steps. Today is where the demo stops being a plan.

### 🅰️ Builder A — `lib/canopy.ts` and the runner

**This is today's main job, ahead of the tests.** CRE landed yesterday, so every piece of the flow
now exists; what is missing is one place that knows how to call them.

`frontend/lib/canopy.ts` — the shared module, plain viem, no React:

```ts
apply(wallet, issuer, broker, tier)      // beats 1-4: emits ApplicationSubmitted
eligibilityOf(wallet, issuer)            // the two badges, via that issuer's checker
hierarchyOf(wallet, issuer)              // leaf -> broker -> issuer -> platform, with expiries
issuersOf(wallet)                        // [new Sep 6] every issuer this wallet is eligible under
swap(account, issuer, amountIn)          // permissioned Universal Router  0x54C707...
addLiquidity(account, issuer, params)    // PermissionedPositionManager    0xf99D55...
removeLiquidity(account, issuer, tokenId) // beat 14 — must work after the lapse
```

**[changed Sep 6] Every function takes an issuer.** There is one adapter, one pool, one token and one
checker per issuer, so a call with no issuer is ambiguous — and the ambiguity resolves silently to
whichever one is listed first, which is the worst kind of bug to have on camera. `issuersOf` is what
the console needs to show a wallet that is eligible under one issuer and not another (beat 9).

Two things the module must get right, because they are the errors that cost hours:

- **adapter vs underlying.** The pool's currency is the adapter; the wallet holds the underlying.
  Keep them separately named in the types. Confusing them produces "insufficient balance" against a
  wallet that visibly has funds.
- **caller == recipient** for liquidity. `addLiquidity()` takes no recipient parameter, by design.

`scripts/e2e.ts` — the runner. Calls the module in beat order, asserts each outcome (including the
**four** that must *revert* — 8, 9, 12, 15), and prints a legible transcript. This is the acceptance
test and the rehearsal for the video.

It must be re-runnable: `--reset-broker` re-arms beat 11, and everything else is idempotent.

**[new Sep 6] The runner loops issuers.** Beats 9, 10 and 13 all compare one issuer against the
other, so the transcript should print a per-issuer eligibility matrix — wallet × issuer × flag — at
the top and again after the lapse. That table is the clearest single artifact the project produces,
and it is worth a screenshot in the README.

### 🅰️ Builder A — the tests that prove the thesis

`test/ExpiryCascade.t.sol`:
- Register `mm` under `prime.acme` with **both** roles; assert bit assembly returns `SWAP_ALLOWED | LIQUIDITY_ALLOWED`
- Expire Acme's `prime` → assert **both** `alice` and `mm` return `NONE`. This is the money shot.
- Expire `alice` only → assert `mm` still works
- **[new Sep 6] Containment:** expire Acme's `prime` → assert `bob`, under Zenith's `prime`, is unaffected. Beat 13.
- **[new Sep 6] Issuer cascade:** expire `acme` itself → assert every broker and investor beneath it returns `NONE`, and Zenith's are untouched
- **Re-registration test:** expire a name, re-register it, assert the old role grants no longer satisfy `checkAllowlist`. This proves the `eacVersionId` story — a lapsed broker cannot resurrect their book by re-registering. Cheapest possible proof of the strongest claim in the pitch.

`test/AdversarialPath.t.sol`:
- Malicious/forged path → must return `NONE` or revert, never grant
- Path with a registry that isn't a real registry
- `recordPath` called by a non-attestor → reverts
- **[new Sep 6] Cross-issuer:** a leaf legitimately registered under Zenith, recorded into Acme's checker, must return `NONE` — the walk reaches the platform root but never passes through `ISSUER_REGISTRY`. This is the test that would have caught the isolation hole, and it is the one that fails *open* if the guard is ever removed.

### 🅱️ Builder B — REJECT path, per-broker rejection, and **the second pool**

- Workflow REJECT branch: score below threshold → either no `writeReport`, or a REJECT verdict that `MintAttestor` filters (`if (!approved) return;`). Test both.
- **[new Sep 6] Beat 3 — the per-broker rejection.** A borderline applicant who passes under `prime`
  and fails under `delta`, same issuer, same engine, different policy. This is what makes
  "per-broker criteria" a demonstrated mechanism rather than a described one, and it costs one extra
  entry in the rulebook map.
- Onboard `bob` under **Zenith's** `prime` end-to-end through the full CRE flow, holding
  `ROLE_ELIGIBLE_SWAP`. This proves the hierarchy generalises past one broker *and* sets up beats 10
  and 13.

**[new Sep 6] The second pool — Zenith's.** Repeat the Sep 5 sequence with new arguments: a second
permissioned test token, `createPermissionsAdapter`, allowlist + `depositForVerification(1)`, all
four wrappers and the hook, create the pool, `updateSwappingEnabled(true)`.

It lands today because Sep 6 and Sep 7 have no slack and today is the lightest day. **It should be
about an hour if Sep 5's sequence was a parameterized script** — every trap in it is already known.
If it was manual `cast` calls, this is most of a day; that is why the "parameterize it" question is
on Sep 6's checklist rather than here.

Then seed it with depth: `mm2`, Zenith's market maker, adds liquidity. Beat 10 needs somewhere for
`bob` to trade.

**Do not share a token between the two pools.** The pool *is* the issuer's product — Acme issues one
asset, Zenith another. They share the rails, not the book.

### 🔀 Sync — end of day

**Done when:** `scripts/e2e.ts` runs all fifteen beats on live Sepolia, start to finish, no manual
steps — including the four that must revert (8, 9, 12, 15), the withdrawal that must still succeed
(14), and the two that carry the new model: **9, isolation, and 13, containment.**

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

**Beat 5 — the checker swap-over — is filmed today:**
```solidity
acmeAdapter.updateAllowListChecker(acmeChecker);
```
One transaction turns a flat permissioned pool into a hierarchical one. Zenith's adapter gets the
same treatment off camera — filming it twice proves nothing new.

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

- **[new Sep 6] An issuer switcher at the top level.** Every view is scoped to one issuer, and the
  switcher is what makes beats 9, 10 and 13 legible — the same wallet, the same broker, a different
  issuer, a different answer.
- Application form → `apply()`: pick issuer, then broker under that issuer, then tier (beats 1–4)
- Active brokers per issuer with **live expiry countdown** (beat 11)
- Investors per broker, role bits as two distinct badges (swap / liquidity)
- **Swap** and **Add liquidity** buttons per investor → `swap()`, `addLiquidity()` (beats 6–8)
- **Remove liquidity** for `mm` (beat 14)
- Surface revert reasons verbatim — `Unauthorized` from the router *is* the demo (beats 8, 9, 12)
- **[new Sep 6] A per-wallet eligibility matrix** — wallet × issuer × flag, straight from
  `issuersOf()`. It is how a viewer sees at a glance that eligibility is issuer-scoped, and it is the
  single view that changes most visibly at beat 11.
- **[new Sep 6] Show each broker's policy hash and its `expiryDays`, never the criteria.** That is
  the whole confidentiality claim rendered as a UI element: you can see *that* a broker has a policy
  and that it is pinned to their name, and you cannot see what it says.

**Poll `eligibilityOf()` on a short interval.** The chain does not push. If the badges only change on
refresh, the judge watches you click at the exact moment we claim nothing is clicked. This is the
single most important UI requirement in the build. **Poll both issuers** — beat 13 is Acme's badges
going dark while Zenith's stay lit, and that only lands if both are live on screen at once.

**There is no "trigger lapse" control.** Expiry is time passing; a button that forces it would be
`unregister`, the revocation transaction we claim is unnecessary. Setup between takes is
`deploy-hierarchy.sh --reset-broker`, off camera.

**Naming trap:** the pool's currency is the **adapter**; the wallet holds the **underlying**. Never a
variable called just `token`. `lib/canopy.ts` keeps them distinct — do not flatten it in the UI.

**Note:** the earlier plan hedged with an Anvil mirror because Sepolia can't be time-warped. That's no longer needed — Acme's `prime` is registered with a ~10-minute expiry and lapses for real. Build the countdown against the real chain. **Only that one name gets the short TTL**; every other broker keeps ~30 days, or the cascade looks global and beat 13 has nothing to show.

### 🔀 Sync — end of day

**Done when:** the complete user story — application → CRE verdict → subname mint → swap → liquidity split → broker lapse → both cut off, **with the other issuer's book visibly untouched** — executes on Sepolia, in the browser.

---

# Sep 10 (Wed) — Day 7: benchmarks & polish

### 🅰️ Builder A

`bench/GasBench.t.sol` + `bench/RESULTS.md`. Measure `checkAllowlist` gas at 10 / 1,000 / 10,000 registered investors, against the `IssuerAllowlistCheckerFlat` baseline.

The interesting result is that our cost is **flat in the number of investors** — it's a function of hierarchy depth, not registry size — whereas the flat checker's storage grows linearly. Present it that way; it's the quantitative argument for the whole design.

**[new Sep 6] Add a second axis: issuers.** The flat checker's storage grows with investors *and*
must be duplicated per issuer; ours adds one immutable per issuer and no per-investor storage at all.
Revoking a broker's book is one expiry in our design and O(investors) transactions in theirs —
**per issuer**. The multi-issuer model makes the existing argument stronger, so say it with the new
number rather than the old one.

### 🅱️ **Policy-hash verification [new Sep 6] — ~1h, do it if the day allows**

The workflow verifies `keccak(canonical(policy))` against the `canopy:policy` text record before
evaluating, and the console shows the hash. This is the piece deferred off Day 4 because Day 4 is
the day both tracks must land.

It turns "each broker has their own criteria" from a description into something a judge can check,
and it completes the attestation trail below — workflow ID, report hash, *and* the policy that
verdict was made against.

If the day is tight, cut it. Per-broker criteria still work without it; what is missing is the proof
that we did not quietly rewrite a broker's rules.

### 🅱️ Builder B

Console polish:
- Two-tier investor view (retail vs MM) with the role bits visible
- On-chain event stream: registrations + attestations
- Attestation trail per subname: workflow ID + report hash **+ the policy hash in force at the time**, so a judge can verify the CRE provenance of any name *and* what it was judged against

---

# Sep 11 (Thu) — Day 8: docs & adversarial retests

### 🅰️ Builder A

- **Role-nybble collision test.** Assert our `1<<64` / `1<<68` grants do not trigger any `RegistryRolesLib` behaviour. The original values collided with `ROLE_REGISTER_RESERVED` and `ROLE_SET_PARENT`; this test is the regression guard.
- **Token-regeneration test.** Mint → change a role (which bumps `tokenVersionId` and regenerates the token) → assert the checker still works, because we index by labelhash and never touch token IDs.
- **[new Sep 6] Salt-collision regression.** Two issuers, one shared broker label; assert their
  registries are at *different* addresses. Without an issuer in the salt they collide, and the
  failure mode is that one issuer's expiry silently cuts off the other's investors.
- **[new Sep 6] Policy clamp.** A broker policy attempting `minScore` below the issuer's floor, a
  wider jurisdiction allowlist, or a higher `maxTier` — assert each is clamped to the issuer's value,
  not applied. This is the compliance claim; an unclamped broker policy means a broker can approve
  someone their issuer would reject.
- **[new Sep 6] Optional hardening: an on-chain role clamp.** `MintAttestor` masks
  `roleBitmap &= ceilingOf[parentRegistry]`, so even a compromised workflow cannot mint an MM under a
  retail-only broker. Cheap, and it moves one compliance guarantee out of the enclave.

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

Shot in the console. The fifteen beats, trimmed to the six that carry the argument:

1. `mm` adds liquidity on Acme's pool ✓ (beat 6)
2. retail swaps ✓ (beat 7)
3. retail `addLiquidity` **reverts** ✗ (beat 8) — the tier split
4. **Acme's `prime` lapses, no transaction sent** (beat 11)
5. both its investors cut off, swaps revert on-chain (beat 12)
6. **`bob` — same broker, different issuer — still trades** (beat 13) — containment

**Beat 13 is the one the new model exists for**, and it costs about eight seconds: after the lapse,
switch to Zenith and swap. One broker, dropped by one issuer, still operating for the other. Without
it the video shows an expiry cascade; with it, it shows a *scoped* one.

**The lapse must be one uncut shot** — badges live, nothing clicked, badges dark. An edit there is
not evidence. Show both issuers on screen at once if the layout allows, so beat 5 and beat 6 are the
same shot: Acme's column goes dark while Zenith's stays lit. Set the TTL for *only that broker* so
the countdown crosses zero while recording, and re-arm between takes with
`deploy-hierarchy.sh --reset-broker` (off camera — it uses `unregister`).

If there is room, beat 14 is worth ten seconds: `mm` removes liquidity *after* being cut off. It
answers the "have you trapped their funds" question before a judge has to ask it.

Beat 9 (cross-issuer denial) is the one to cut first if time is short — beat 13 already demonstrates
issuer scoping, and does it more vividly.

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

1. **Two** adapters created via the live Sepolia factory, one per issuer; our two checkers, registrar and attestor deployed and verified
2. Platform name, **two issuers, a broker onboarded by both**, and ≥3 investor subnames registered end-to-end through the CRE flow
3. A live Sepolia swap passing through the router → adapter → our checker → correct flag → executes
4. A live `addLiquidity` rejected for a swap-only investor and accepted for an MM
5. The money shot: broker name lapses, both its investors cut off, no revocation transaction
6. **[new Sep 6] Containment:** the same broker's book under the *other* issuer keeps trading through that lapse
7. **[new Sep 6] Isolation:** an investor eligible under one issuer is refused on-chain by the other issuer's pool
8. `FEEDBACK.md` with real observations
9. Video ≤ 3 min, live demo link, public repo

**1–5 clear every listed prize requirement. 6–7 are what the multi-issuer model adds, and they are
the two a judge will probe first. 8–9 are the delivery.**

⚠️ **If the schedule slips, 6 and 7 are not the things to cut** — they are cheap (both are assertions
the runner already makes) and they are the difference between a platform and a single-tenant demo
with extra names in it. Cut the second *pool* before cutting these, and prove 7 with a read.
