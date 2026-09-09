<p align="center">
  <img src="./frontend/public/logoAndName.png" alt="Canopy Banner" width="400" />
</p>

<h1 align="center">Canopy</h1>
<p align="center"><i>Hierarchical, Expiring Eligibility for Permissioned DeFi Pools</i></p>

<p align="center">
  A multi-issuer permissioned pool system on Uniswap v4 where eligibility is derived from an ENSv2 name hierarchy. Issuers onboard brokers, brokers introduce investors &mdash; and when a broker's name expires, every investor beneath them is automatically cut off without a single on-chain transaction. KYC decisions happen privately inside a Chainlink CRE confidential workflow (AWS Nitro enclave), and only the approve/reject verdict reaches the chain. Investors retain full withdrawal rights at all times &mdash; funds are never trapped.
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/Built%20on-Uniswap%20v4-FF007A?style=for-the-badge&logo=uniswap&logoColor=white" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Names-ENSv2-5284FF?style=for-the-badge" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Confidential-Chainlink%20CRE-375BD2?style=for-the-badge" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Network-Sepolia-6B7280?style=for-the-badge&logo=ethereum&logoColor=white" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Hackathon-ETHOnline%202026-00D632?style=for-the-badge" /></a>
</p>

<p align="center">
  <a href="#-the-problem">Problem</a> &bull;
  <a href="#-how-canopy-works">How It Works</a> &bull;
  <a href="#-the-hierarchy">The Hierarchy</a> &bull;
  <a href="#-system-flow">System Flow</a> &bull;
  <a href="#-smart-contracts">Contracts</a> &bull;
  <a href="#-integrations">Integrations</a> &bull;
  <a href="#-deployed-contracts">Deployed</a> &bull;
  <a href="#-quick-start">Quick Start</a>
</p>

---

## Deployed on Sepolia

| Contract | Address |
|----------|---------|
| **ENSAllowlistChecker** | Deployed per issuer via `DeployIssuerHierarchy` |
| **MintAttestor** | [`0x5B9EED286356575E160C4C3F8724F6bC3433a9CF`](https://sepolia.etherscan.io/address/0x5B9EED286356575E160C4C3F8724F6bC3433a9CF) |
| **ApplicationContract** | [`0x488fe44CD310D25010a50FdE943f133148B34036`](https://sepolia.etherscan.io/address/0x488fe44CD310D25010a50FdE943f133148B34036) |
| **CanopyTestToken** | [`0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920`](https://sepolia.etherscan.io/address/0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920) |
| **PermissionsAdapter** | [`0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9`](https://sepolia.etherscan.io/address/0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9) |
| **IssuerAllowlistCheckerFlat** | [`0x2bd99Ec49bafea1E765f23Fc3bCaFdfaE86b3DB4`](https://sepolia.etherscan.io/address/0x2bd99Ec49bafea1E765f23Fc3bCaFdfaE86b3DB4) |

---

## The Problem

Permissioned pools on Uniswap v4 let issuers restrict who can trade tokenized assets. But managing that access list creates real operational pain:

| Gap | Why It Matters |
|-----|---------------|
| **Revoking a broker's entire book is O(n)** | If a broker loses their license, the issuer must send one transaction per investor to revoke access. 10,000 investors = 10,000 transactions. Expensive, slow, and error-prone. |
| **KYC decisions are either opaque or public** | On-chain storage leaks who was evaluated and why. Off-chain decisions are unverifiable. Neither is acceptable for regulated assets. |
| **Flat allowlists don't expire** | Investors approved once stay approved forever unless manually removed. There is no automatic expiry, no tiered access, no hierarchical control. |
| **No issuer isolation** | A single allowlist for multiple issuers means one issuer's approval leaks into another's pool. Each issuer needs independent control over their own eligibility. |

**No existing solution provides automatic cascade revocation, confidential KYC, tiered access, and multi-issuer isolation simultaneously.**

---

## How Canopy Works

Canopy replaces flat allowlists with an **ENS name hierarchy** where eligibility is structural, not stored:

> *An issuer (Acme) onboards brokers. A broker (Prime) introduces investors. Each gets an ENS subname with an expiry date. When Prime's name lapses, every investor under Prime &mdash; Alice, the market maker, everyone &mdash; is automatically blocked. No transaction sent. No admin action. Time passing is the revocation.*

### The Lifecycle

| Phase | What Happens | Trust Model |
|-------|-------------|-------------|
| **A. Platform Setup** | `canopy.eth` registered as the platform root. Issuers (`acme.canopy.eth`, `zenith.canopy.eth`) and brokers (`prime.acme.canopy.eth`) registered with expiry dates. Each issuer gets their own pool and checker. | Deploy script, one-time setup |
| **B. Investor Application** | Investor calls `submitApplication(broker, label, tier)` on `ApplicationContract`. Issuer and broker path are derived on-chain &mdash; the applicant cannot pick a looser policy. | `msg.sender` proves wallet ownership |
| **C. Confidential KYC** | CRE workflow triggers on `ApplicationSubmitted`. Inside an AWS Nitro enclave: fetches KYC API token and eligibility rulebook from Vault-DON, evaluates the applicant, outputs a verdict. Score thresholds and tier rules are secrets. | TEE attestation; secrets never leave the enclave |
| **D. Subname Minting** | `MintAttestor` receives the DON-signed report. On APPROVE: registers the investor's subname with eligibility roles (`ROLE_ELIGIBLE_SWAP` and/or `ROLE_ELIGIBLE_LIQUIDITY`) and records the leaf path in the issuer's checker. | KeystoneForwarder + workflow ID validation |
| **E. Pool Access** | On every swap or liquidity action, `ENSAllowlistChecker` walks the hierarchy upward from the investor's subname: is the leaf alive? Is the broker alive? Does the walk pass through the correct issuer and reach the platform root? Any dead name = access denied. | Fail-closed; checked at the protocol level by Uniswap v4 hooks |
| **F. Cascade Expiry** | Broker's name expires (a countdown, not a button). `getSubregistry()` returns `0x0`. Every investor under that broker fails the hierarchy walk. **Zero transactions.** | Time-based; enforced by ENSv2 |
| **G. Withdrawal** | Investors can always remove liquidity &mdash; decreases and burns are never gated in the Uniswap v4 permissioned pool standard. Funds are never trapped. | Unconditional exit rights |

### Key Features

- **Cascade Revocation** &mdash; When a broker's name expires, all downstream investors are automatically ineligible. No revocation transaction needed. The chain enforces it, not the UI.
- **Two-Tier Access** &mdash; Retail investors get `SWAP_ALLOWED` only. Market makers get `SWAP_ALLOWED | LIQUIDITY_ALLOWED`. The pool enforces the split &mdash; a retail investor literally cannot add liquidity.
- **Confidential KYC** &mdash; The eligibility rulebook and KYC API token live in Vault-DON secrets. Evaluation happens inside an AWS Nitro enclave. Only the approve/reject verdict is on-chain. Source code is public; the data computed over it is not.
- **Multi-Issuer Isolation** &mdash; Each issuer has their own pool and checker. Being eligible under Acme says nothing about Zenith. One checker per issuer, enforced by an `ISSUER_REGISTRY` immutable.
- **Per-Broker Policy** &mdash; Each broker can tighten (never loosen) the issuer's floor: higher score threshold, shorter expiry, narrower jurisdictions. Policy bodies are Vault-DON secrets; only their hashes are on-chain.
- **Fail-Closed** &mdash; Missing leaf path, dead ancestor, expired name, wrong issuer &mdash; all return `NONE`. The system never grants spurious access.

---

## The Hierarchy

```
.eth   (ETHRegistry — ENS itself)
└── canopy.eth                              PLATFORM ROOT  (365 days)
    ├── acme.canopy.eth                     ISSUER 1  ──▶ pool 1, acmeChecker
    │   ├── prime.acme.canopy.eth           broker        (10 min for demo)
    │   │   ├── alice.prime.acme...         retail        (SWAP only, 60 days)
    │   │   └── mm.prime.acme...            market maker  (SWAP + LIQUIDITY, 60 days)
    │   └── delta.acme.canopy.eth           broker        (stricter policy, 30 days)
    └── zenith.canopy.eth                   ISSUER 2  ──▶ pool 2, zenithChecker
        └── prime.zenith.canopy.eth         SAME BROKER, independent name
            ├── bob.prime.zenith...         retail
            └── mm2.prime.zenith...         market maker
```

**Why `prime` appears twice:** A name has exactly one parent. A broker onboarded by two issuers holds two names in two registries. Acme dropping Prime does not touch Zenith's relationship with Prime. Two names give you that for free.

**Why three+ levels:** The platform root is long-lived (1 year). Issuers are medium-lived. Brokers are short-lived (the cascade point). Investors inherit their broker's mortality.

---

## System Flow

```
                                    CANOPY

  INVESTOR APPLICATION
  ─────────────────────────────────────────────────────────────────
   Investor
     │  submitApplication(brokerRegistry, label, requestedTier)
     ▼
   ApplicationContract
     │  wallet = msg.sender (proves control)
     │  issuer = derived on-chain via LibCanopyPath (cannot be faked)
     │  brokerPath = derived on-chain (rulebook key, e.g. "acme/prime")
     │  check label not already taken
     │
     └──▶ emit ApplicationSubmitted(applicationId, wallet, issuer,
                                     broker, brokerPath, label, tier)


  CONFIDENTIAL KYC (inside AWS Nitro enclave)
  ─────────────────────────────────────────────────────────────────
   CRE Workflow DON (logTrigger on ApplicationSubmitted)
     │
     ├─(1)─▶ Fetch secrets from Vault-DON:
     │         • KYC_API_TOKEN (stays in enclave)
     │         • ELIGIBILITY_RULEBOOK (keyed by broker path)
     │
     ├─(2)─▶ Resolve policy:
     │         issuerPolicy = rulebook["acme/_default"]
     │         brokerPolicy = rulebook["acme/prime"]
     │         effective = combine(issuer, broker)  // broker tightens, never loosens
     │
     ├─(3)─▶ Evaluate applicant:
     │         • Chainalysis sanctions check (fail-closed)
     │         • GoPlus risk scoring
     │         • Score vs threshold, tier assignment, expiry calculation
     │
     ├─(4)─▶ Produce verdict:
     │         (kind=0, subject, labelBytes, parentRegistry,
     │          roleBitmap, expiry, approved)
     │
     └─(5)─▶ DON consensus → signed report → KeystoneForwarder


  ON-CHAIN MINTING
  ─────────────────────────────────────────────────────────────────
   KeystoneForwarder
     │  writeReport(metadata, report)
     ▼
   MintAttestor.onReport(metadata, report)
     │  verify caller == KeystoneForwarder
     │  verify workflowId == allowedWorkflowId
     │  decode verdict, assert kind == 0
     │
     │  if NOT approved → emit VerdictReceived, return (silent no-op)
     │
     │  if approved:
     │    derive issuerRegistry from parentRegistry via LibCanopyPath
     │    register subname in broker's registry (with roles + expiry)
     │    record leaf path in issuer's ENSAllowlistChecker
     │
     └──▶ emit SubnameMinted(subject, parentRegistry, issuerRegistry)


  POOL ACCESS CHECK (every swap / liquidity action)
  ─────────────────────────────────────────────────────────────────
   Uniswap v4 PermissionedHooks
     │  checkAllowlist(account, permissionedToken)
     ▼
   ENSAllowlistChecker
     │  look up leaf: mapping(account → Leaf{registry, labelhash})
     │
     │  ┌─── Hierarchy Walk (~17.9k gas/hop) ───────────────┐
     │  │  1. Read leaf subname state → alive? has roles?    │
     │  │  2. Walk to parent (broker) → alive?               │
     │  │  3. Walk to parent (issuer) → is ISSUER_REGISTRY?  │
     │  │  4. Walk to parent (platform) → is ROOT_ANCHOR?    │
     │  │  Any failure at any step → return NONE             │
     │  └───────────────────────────────────────────────────┘
     │
     └──▶ return SWAP_ALLOWED | LIQUIDITY_ALLOWED | NONE


  CASCADE EXPIRY (the product)
  ─────────────────────────────────────────────────────────────────
   Time passes. Broker's name expires.
     │
     │  getSubregistry(brokerLabelhash) → 0x0
     │  (no transaction sent — expiry is a clock, not a button)
     │
     │  Every investor under that broker:
     │    hierarchy walk hits dead broker → returns NONE
     │    swap attempt → reverts Unauthorized
     │    remove liquidity → still succeeds (funds never trapped)
     │
     └──▶ Re-registering the broker creates a FRESH resource
          → old investor grants are orphaned, not resurrected
```

---

## Smart Contracts

| Contract | Purpose |
|----------|---------|
| **ENSAllowlistChecker.sol** | Uniswap v4 `IAllowlistChecker` &mdash; walks the ENSv2 hierarchy upward from a leaf subname, checking every ancestor is alive and the walk passes through the correct issuer. Returns `SWAP_ALLOWED`, `LIQUIDITY_ALLOWED`, or `NONE`. |
| **IssuerAllowlistCheckerFlat.sol** | Baseline flat `mapping(account → PermissionFlag)` checker. Used initially, switched to the hierarchical checker in one transaction during the demo. |
| **CanopyRoles.sol** | Role constants: `ROLE_ELIGIBLE_SWAP` (nybble 16, `1<<64`) and `ROLE_ELIGIBLE_LIQUIDITY` (nybble 17, `1<<68`). In ENSv2's free nybble range &mdash; no collision with protocol roles. |
| **MintAttestor.sol** | CRE report receiver. Validates the KeystoneForwarder and workflow ID, decodes the verdict, registers the investor's subname, and records the leaf path in the correct issuer's checker. |
| **ApplicationContract.sol** | Entry point for eligibility applications. Derives issuer and broker path on-chain (preventing policy-shopping), checks for label collisions, and emits `ApplicationSubmitted` for the CRE logTrigger. |
| **LibCanopyPath.sol** | Walks the ENSv2 hierarchy from a registry to the platform root, building the label path string and extracting the issuer registry. |
| **IReceiver.sol** | Vendored Chainlink CRE receiver interface with ERC-165 support. |
| **CanopyTestToken.sol** | ERC-20 test token with allowlist-gated transfers, used as the underlying asset in the permissioned pool. |

### Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Upward walk, not stored path | Only the leaf is recorded; ancestors are discovered on-chain at check time. A stored path goes stale when the hierarchy changes. |
| One checker per issuer | Prevents `mapping(account → Leaf)` collisions. A shared checker would need `mapping(account → mapping(issuer → Leaf))`, and a bug silently overwrites one issuer's grant with another's. |
| Per-name EAC resources | Nybbles are 4-bit counters capped at 15 holders. A shared resource would cap the platform at 15 investors. Per-name scales to unlimited. |
| Fresh resource on re-registration | Old grants are orphaned, not resurrected. A lapsed broker cannot resurrect their book by re-registering. |
| `ISSUER_REGISTRY` immutable | The walk must pass through the issuer's registry, not just reach the platform root. Without it, every issuer's checker admits every other issuer's investors. |
| Fail-closed everywhere | Missing leaf, dead ancestor, wrong terminus, expired name, exceeding `MAX_HOPS` &mdash; all return `NONE`. |
| `wallet = msg.sender` in applications | Prevents anyone from applying in someone else's name. |
| Derived `brokerPath` | The rulebook key is computed on-chain from the registry hierarchy, not supplied by the caller. A caller who could name the path would pick the loosest policy. |

---

## Integrations

| Integration | Role in Canopy | How It's Used |
|-------------|---------------|---------------|
| **Uniswap v4** | Permissioned pool infrastructure | `PermissionedHooks` call `ENSAllowlistChecker` on every swap and liquidity action. `PermissionsAdapter` wraps the underlying token. Pool enforces tier splits at the protocol level. |
| **ENSv2** | Hierarchical identity and expiry | Four-level name hierarchy (platform → issuer → broker → investor). Subname expiry drives cascade revocation. EAC roles encode eligibility tiers. `getSubregistry()` returning `0x0` on expiry is the core mechanism. |
| **Chainlink CRE** | Confidential KYC engine | `handlerInTee` workflow runs inside an AWS Nitro enclave. Fetches secrets from Vault-DON, calls KYC API, evaluates applicant against a per-broker policy, produces a signed verdict. Only the verdict leaves the enclave. |

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Smart Contracts** | Solidity 0.8.26 + Foundry (Cancun EVM) | Checker, attestor, application contract, deploy scripts |
| **Pool Framework** | Uniswap v4-core + v4-periphery | Permissioned hooks, adapter, position manager, router |
| **Name System** | ENSv2 (contracts-v2) | Hierarchical registries, EAC roles, subname expiry |
| **Confidential Compute** | Chainlink CRE (AWS Nitro) | TEE-based KYC evaluation, Vault-DON secrets |
| **CRE Workflow** | TypeScript + CRE SDK | `handlerInTee` workflow, GoPlus risk scoring, Chainalysis sanctions |
| **Frontend** | Next.js + Tailwind CSS | Application console, eligibility dashboard, lapse countdown |
| **Chain Interaction** | viem + wagmi | Contract reads/writes, wallet integration |
| **Network** | Ethereum Sepolia | All deployments (ENSv2 hackathon instance + Uniswap v4 permissioned pools) |

---

## Deployed Contracts

### Canopy Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| ApplicationContract | [`0x488fe44CD310D25010a50FdE943f133148B34036`](https://sepolia.etherscan.io/address/0x488fe44CD310D25010a50FdE943f133148B34036) |
| MintAttestor | [`0x5B9EED286356575E160C4C3F8724F6bC3433a9CF`](https://sepolia.etherscan.io/address/0x5B9EED286356575E160C4C3F8724F6bC3433a9CF) |
| CanopyTestToken | [`0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920`](https://sepolia.etherscan.io/address/0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920) |
| IssuerAllowlistCheckerFlat | [`0x2bd99Ec49bafea1E765f23Fc3bCaFdfaE86b3DB4`](https://sepolia.etherscan.io/address/0x2bd99Ec49bafea1E765f23Fc3bCaFdfaE86b3DB4) |
| PermissionsAdapter | [`0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9`](https://sepolia.etherscan.io/address/0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9) |
| KeystoneForwarder (Mock) | [`0xF8344CFd5c43616a4366C34E3EEE75af79a74482`](https://sepolia.etherscan.io/address/0xF8344CFd5c43616a4366C34E3EEE75af79a74482) |

### ENSv2 &mdash; Hackathon Deployment (Sepolia)

> **These are NOT the standard Sepolia ENSv2 Beta addresses.** This is a dedicated deployment for ETHOnline 2026.

| Contract | Address |
|----------|---------|
| RootRegistry | [`0xe7f0d5724f8337e3aa9a9910540341ff4273fed9`](https://sepolia.etherscan.io/address/0xe7f0d5724f8337e3aa9a9910540341ff4273fed9) |
| ETHRegistry | [`0x1d78834d97c1d7b1a38c1dedbd1a287cfed3971e`](https://sepolia.etherscan.io/address/0x1d78834d97c1d7b1a38c1dedbd1a287cfed3971e) |
| ETHRegistrar | [`0x7d1b7f586a62ac3f54b9a396849757814283270b`](https://sepolia.etherscan.io/address/0x7d1b7f586a62ac3f54b9a396849757814283270b) |
| VerifiableFactory | [`0x894bc9cc8ff1ad96b8a288c86a8c71d662c07780`](https://sepolia.etherscan.io/address/0x894bc9cc8ff1ad96b8a288c86a8c71d662c07780) |
| UserRegistryImpl | [`0x47b442d0cf617c41cabaff5f02f44dd1e5f72546`](https://sepolia.etherscan.io/address/0x47b442d0cf617c41cabaff5f02f44dd1e5f72546) |
| UniversalResolverV2 | [`0xfea8d4b7fcce0b8765c793d6695eac384aaa458f`](https://sepolia.etherscan.io/address/0xfea8d4b7fcce0b8765c793d6695eac384aaa458f) |
| MockUSDC | [`0xcbfd80f74375c54e545af34788ff465f96f66f05`](https://sepolia.etherscan.io/address/0xcbfd80f74375c54e545af34788ff465f96f66f05) |

### Uniswap v4 Permissioned Pools (Sepolia)

| Contract | Address |
|----------|---------|
| PoolManager | [`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`](https://sepolia.etherscan.io/address/0xE03A1074c86CFeDd5C142C4F04F1a1536e203543) |
| PermissionsAdapterFactory | [`0xE6B0d96919334C33d06266d1420F97f6f434fA2B`](https://sepolia.etherscan.io/address/0xE6B0d96919334C33d06266d1420F97f6f434fA2B) |
| PermissionedPositionManager | [`0xf99D553912084c99F6299291b75Fe9B7119Aa1A7`](https://sepolia.etherscan.io/address/0xf99D553912084c99F6299291b75Fe9B7119Aa1A7) |
| PermissionedHooks | [`0x51247E2291d290d17C08813A175AC86465EdE8c0`](https://sepolia.etherscan.io/address/0x51247E2291d290d17C08813A175AC86465EdE8c0) |
| Universal Router | [`0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7`](https://sepolia.etherscan.io/address/0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7) |
| V4Quoter | [`0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227`](https://sepolia.etherscan.io/address/0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227) |

---

## The Demo &mdash; Fifteen Beats

Setup (off-camera): two permissioned pools (Acme's and Zenith's), platform root, issuers, brokers, registries, checkers, attestor.

| # | Beat | Proves |
|---|------|--------|
| 1 | `alice` applies to Acme through `prime` → CRE **APPROVE** → subname minted with `ROLE_ELIGIBLE_SWAP` | CRE mint path works |
| 2 | Second applicant → CRE **REJECT** → no subname | The engine discriminates |
| 3 | Same applicant re-applies through `delta` (stricter policy) → still **REJECT** | Per-broker criteria are real |
| 4 | `mm` applies → APPROVE with **both** role bits | Two tiers exist |
| 5 | `acmeAdapter.updateAllowListChecker(acmeChecker)` | One tx: flat → hierarchical |
| 6 | `mm` adds liquidity on Acme's pool → **succeeds** | MM tier + pool depth |
| 7 | `alice` swaps on Acme's pool → **succeeds** | Retail tier |
| 8 | `alice` attempts `addLiquidity` → **reverts** | **The tier split** |
| 9 | `alice` swaps on Zenith's pool → **reverts** | **Cross-issuer isolation** |
| 10 | `bob` (under Zenith's `prime`) swaps on Zenith's pool → **succeeds** | One broker, two issuers, two independent books |
| 11 | **Acme's `prime` lapses** &mdash; countdown to zero, **no transaction sent** | **The money shot** |
| 12 | `alice` and `mm` attempt swaps → **both revert `Unauthorized`** | The chain refusing, not the UI |
| 13 | `bob` swaps on Zenith → **still succeeds** | **Containment** &mdash; one issuer's lapse doesn't touch another |
| 14 | `mm` removes liquidity → **succeeds** | Funds not trapped |
| 15 | Acme re-registers `prime` → investors stay dead | Fresh resource orphans old grants |

**Beat 11 is never a button.** Expiry is time passing. The demo films a countdown reaching zero with nobody touching anything.

---

## Gas Benchmarks

Hierarchy walk cost measured against deployed ENSv2 contracts:

| Depth | Cold (gas) | Warm (gas) | Marginal per hop |
|------:|----------:|----------:|----------------:|
| 1 (leaf only) | 29,982 | 10,965 | &mdash; |
| 2 (+1 ancestor) | 47,907 | 16,390 | 17,925 |
| 3 (+2 ancestors) | **65,839** | 21,822 | 17,932 |

**~17.9k per hop** against a 40k budget. The walk is flat in the number of investors &mdash; eligibility is read from the investor's own subname, not from a list.

| Operation | Flat Allowlist | ENS Hierarchy |
|-----------|:---:|:---:|
| Lookup | O(1), 1 SLOAD | O(depth), ~17.9k/hop |
| Revoke one investor | 1 tx | 1 tx or let subname lapse |
| Revoke broker's entire book | **1 tx per investor** | **0 tx** &mdash; broker lapses |

---

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (run `foundryup`)
- Node.js >= 18
- Sepolia RPC endpoint
- Deployer private key with Sepolia ETH

### 1. Clone & Install

```bash
git clone https://github.com/SakshiShah29/Canopy.git
cd Canopy
git submodule update --init --recursive
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:

| Variable | Purpose |
|----------|---------|
| `SEPOLIA_RPC_URL` | Sepolia RPC endpoint |
| `DEPLOYER_PRIVATE_KEY` | Deployer wallet (0x-prefixed) |
| `ETHERSCAN_API_KEY` | For contract verification |
| `BROKER_TTL` | Default broker name lifetime (seconds). Use `600` for filming the lapse demo. |
| `LEAF_TTL` | Investor subname lifetime (seconds). Default: 60 days. |

### 3. Build & Test Contracts

```bash
cd contracts
forge build
forge test
```

### 4. Deploy the ENS Hierarchy

```bash
cd contracts
bash script/deploy-hierarchy.sh deploy
```

This runs the 5-phase idempotent deployment: commit parent → register parent → build hierarchy → deploy checkers → verify.

### 5. Deploy CRE Contracts

```bash
forge script script/DeployCREContracts.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast
```

### 6. Run the CRE Workflow (Simulated)

```bash
cd cre/eligibility-workflow
bun install
cre workflow simulate my-workflow --target staging-settings \
    --non-interactive --trigger-index 0 --broadcast
```

`--broadcast` writes a real `KeystoneForwarder` transaction on Sepolia.

### 7. Launch Frontend

```bash
cd frontend
npm install
npm run dev
# http://localhost:3000
```

---

## Project Structure

```
canopy/
├── contracts/                              # Solidity (Foundry, solc 0.8.26, Cancun)
│   ├── src/
│   │   ├── checker/
│   │   │   ├── CanopyRoles.sol            # Role constants (1<<64, 1<<68)
│   │   │   ├── ENSAllowlistChecker.sol    # Hierarchical eligibility checker
│   │   │   └── IssuerAllowlistCheckerFlat.sol  # Flat baseline checker
│   │   ├── cre/
│   │   │   ├── ApplicationContract.sol    # Application entry point
│   │   │   ├── MintAttestor.sol           # CRE verdict receiver + subname minter
│   │   │   ├── LibCanopyPath.sol          # Hierarchy path derivation
│   │   │   └── IReceiver.sol              # Vendored CRE receiver interface
│   │   └── CanopyTestToken.sol            # ERC-20 test token
│   ├── test/
│   │   ├── ENSAllowlistChecker.t.sol      # 45+ tests for hierarchy checker
│   │   ├── IssuerAllowlistCheckerFlat.t.sol
│   │   ├── Dependencies.t.sol             # Pins all upstream assumptions
│   │   ├── cre/
│   │   │   └── CREBoundary.t.sol          # CRE integration tests
│   │   ├── fork/
│   │   │   └── HierarchyRehearsal.t.sol   # Fork tests against live ENSv2
│   │   ├── gas/
│   │   │   ├── Gate1HierarchyGas.t.sol    # Gas benchmarks
│   │   │   └── Gate1ForkCrossCheck.t.sol
│   │   └── mocks/
│   │       ├── MockRegistry.sol
│   │       └── StubLabelStore.sol
│   ├── script/
│   │   ├── DeployIssuerHierarchy.s.sol    # 5-phase hierarchy deploy
│   │   ├── DeployCREContracts.s.sol       # Attestor + application contract
│   │   ├── DeployPermissionedPool.s.sol   # Pool + adapter setup
│   │   ├── SeedAndSwap.s.sol              # Liquidity + test swap
│   │   ├── deploy-hierarchy.sh            # Shell orchestrator
│   │   └── hierarchy.json                 # Declarative broker/investor config
│   └── lib/
│       ├── contracts-v2/                  # ENSv2 source (forge submodule)
│       ├── v4-periphery/                  # Uniswap v4 (forge submodule)
│       └── forge-std/
│
├── cre/                                    # Chainlink CRE Confidential Workflow
│   └── eligibility-workflow/
│       ├── workflow.ts                    # Core logic (policy, scoring, verdict)
│       ├── workflow.test.ts               # Unit tests
│       ├── main.ts                        # Entry point
│       ├── workflow.yaml                  # Trigger + receiver definition
│       ├── secrets.yaml                   # Vault-DON secret mapping
│       ├── policy-schema.md               # Published policy schema
│       ├── CRE-IMPLEMENTATION.md          # Technical deep-dive
│       ├── config.production.json
│       └── config.staging.json
│
├── frontend/                               # Next.js application console
│   ├── app/
│   │   ├── page.tsx
│   │   ├── layout.tsx
│   │   └── globals.css
│   ├── public/
│   │   ├── logo.png                       # Canopy logo
│   │   ├── logoAndName.png                # Logo + wordmark
│   │   └── name.png                       # Wordmark only
│   ├── package.json
│   └── next.config.ts
│
├── deployments.json                        # Shared address book (Sepolia)
├── .env.example                            # Environment template
├── updated-ledger-daywise-tech-spec.md     # Working schedule + full spec
└── README.md
```

---

## How the Cascade Works &mdash; Visually

```
BEFORE: broker alive                    AFTER: broker expired
─────────────────────                   ─────────────────────

canopy.eth ✅                           canopy.eth ✅
└── acme.canopy.eth ✅                  └── acme.canopy.eth ✅
    └── prime.acme... ✅ (alive)            └── prime.acme... ❌ (EXPIRED)
        ├── alice ✅ → SWAP_ALLOWED             ├── alice ❌ → NONE
        └── mm ✅    → ALL_ALLOWED              └── mm ❌    → NONE

        Zero transactions sent.
        Time passing is the revocation.
```

---

## Team

Built for [ETHOnline 2026](https://ethglobal.com/events/ethonline2026) (Sep 4 &ndash; Sep 13).

---

## License

MIT License &mdash; see [LICENSE](./LICENSE) for details.

---

<p align="center">
  <img src="./frontend/public/logo.png" alt="Canopy Logo" width="80" />
</p>

<p align="center">
  <i>Built for ETHOnline 2026</i><br/>
  <i>Powered by <a href="https://uniswap.org">Uniswap v4</a> &bull; <a href="https://ens.domains">ENSv2</a> &bull; <a href="https://chain.link">Chainlink CRE</a></i>
</p>
