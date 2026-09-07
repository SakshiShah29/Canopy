# Canopy CRE Implementation — Step-by-Step

> **Builder B's working document.** Every SDK signature, type shape, and file change is
> verified against `@chainlink/cre-sdk@1.18.0` and Gate 5's simulation output (Sep 6).
> Where the spec and the SDK disagree, the SDK wins — document the difference and move on.

---

## 0. What We Have (post-Gate 5)

```
cre/
├── project.yaml                     # Sepolia RPC ✅
├── secrets.yaml                     # 1 secret (API_TOKEN) — needs 2 more
├── .env / .env.example              # placeholder private key — needs real values
└── eligibility-workflow/
    ├── main.ts                      # Runner boilerplate ✅ (no change needed)
    ├── workflow.ts                  # hello-confidential template — FULL REWRITE
    ├── workflow.yaml                # staging/prod targets — needs name + path updates
    ├── workflow.test.ts             # template tests — FULL REWRITE
    ├── config.staging.json          # cron config — NEW SHAPE
    ├── config.production.json       # same — NEW SHAPE
    ├── package.json                 # deps ✅
    └── tsconfig.json                # ✅
```

## 1. Architecture

```
                          SEPOLIA                         MAINNET
                         ┌──────────────────┐           ┌──────────────────┐
ApplicationSubmitted ──▶ │ logTrigger (DON)  │           │ Chainalysis      │
event (no PII)           └────────┬─────────┘           │ Sanctions Oracle │
                                  │                     │ 0x40C579...      │
                         ┌────────▼─────────────────────┴──────────────────┐
                         │              AWS NITRO ENCLAVE (TEE)             │
                         │                                                  │
                         │  1. getSecrets → KYC_API_TOKEN,                 │
                         │                  ELIGIBILITY_RULEBOOK            │
                         │                                                  │
                         │  2. HTTP POST mainnet RPC → eth_call            │
                         │     Chainalysis isSanctioned(wallet) → bool     │
                         │     (real OFAC data, free, no API key)          │
                         │                                                  │
                         │  3. HTTP GET GoPlus Security API                │
                         │     /api/v1/address_security/{wallet}           │
                         │     → sanctioned, mixer, phishing, malicious   │
                         │     (real risk data, API key is a secret)       │
                         │                                                  │
                         │  4. HTTP GET Etherscan API                      │
                         │     /api?module=account&action=txlist&sort=asc  │
                         │     → wallet age, tx count                      │
                         │     (real on-chain history, API key is secret)  │
                         │                                                  │
                         │  5. Look up effective policy from RULEBOOK      │
                         │     issuerPolicy = book["acme/_default"]        │
                         │     brokerPolicy = book["acme/prime"]           │
                         │     effective = combine(issuer, broker)          │
                         │                                                  │
                         │  6. Evaluate:                                    │
                         │     chainalysis sanctioned? → HARD REJECT       │
                         │     goplus sanctioned/mixer? → HARD REJECT      │
                         │     riskScore < minScore? → REJECT              │
                         │     walletAge < minAgeDays? → REJECT            │
                         │     → approved, tier, roleBitmap, expiry        │
                         │                                                  │
                         │  ═══════════ usingTheDons() ═══════════════     │
                         │  ONLY the verdict crosses out:                  │
                         │  (kind, subject, label, registry, roles,        │
                         │   expiry, approved)                             │
                         │                                                  │
                         └────────┬────────────────────────────────────────┘
                                  │
                         ┌────────▼─────────┐
                         │ report + writeReport │
                         │ → MintAttestor    │
                         │ → SubnameRegistrar│
                         │ → subname minted  │
                         └──────────────────┘
```

### Confidentiality Boundary — What Is and Isn't Protected

| Protected (inside enclave) | NOT protected (public) |
|---|---|
| Vault-DON secrets (API keys, RULEBOOK thresholds) | Source code, compiled WASM binary |
| Chainalysis raw response | That we call Chainalysis |
| GoPlus raw risk profile | That we call GoPlus |
| Etherscan raw tx history | That we call Etherscan |
| The computed risk score | The scoring formula (in source) |
| Effective policy (merged issuer + broker) | The policy field names (policy-schema.md) |
| Which specific factors caused a rejection | The binary verdict (approved/rejected) |
| Applicant's risk data | Report tuple (on-chain calldata) |

**One-liner:** "The code is public, the criteria are not, the wallet's risk profile never leaves the enclave, and the scoring uses real compliance data."

---

## 2. Trigger — `ApplicationSubmitted` Event

### Event Signature (from updated spec, Sep 6)

```solidity
event ApplicationSubmitted(
    bytes32 indexed applicationId,
    address indexed wallet,
    address indexed issuer,      // which issuer's registry/pool
    address broker,              // which broker's registry (NOT indexed — 3 max)
    string  brokerPath,          // "acme/prime" — the policy key
    uint8   requestedTier        // 0 = retail (swap), 1 = MM (swap + liquidity)
);
```

**Topic 0 (event signature hash):**
```
keccak256("ApplicationSubmitted(bytes32,address,address,address,string,uint8)")
```

Compute at build time with viem:
```typescript
import { keccak256, toHex } from 'viem'

const APPLICATION_SUBMITTED_TOPIC = keccak256(
  toHex("ApplicationSubmitted(bytes32,address,address,address,string,uint8)")
)
```

### logTrigger Registration

```typescript
import { cre, logTriggerConfig, EVMClient, getNetwork } from '@chainlink/cre-sdk'

const sepoliaNetwork = getNetwork({
  chainFamily: 'evm',
  chainSelectorName: 'ethereum-testnet-sepolia',
  isTestnet: true,
})

const sepoliaClient = new EVMClient(sepoliaNetwork.chainSelector)

const trigger = sepoliaClient.logTrigger(
  logTriggerConfig({
    addresses: [config.applicationContractAddress],   // hex string, 0x-prefixed
    topics: [[APPLICATION_SUBMITTED_TOPIC]],           // hex string, 0x-prefixed
    confidence: 'FINALIZED',                           // or 'LATEST' for speed
  })
)
```

**SDK detail (verified):** `logTriggerConfig` accepts hex strings and converts them to
base64 internally via `validateHexByteLength` → `hexToBase64`. Do NOT pre-convert.

### Trigger Output — `Log` Type

The handler receives a `Log` object (from `client_pb.d.ts`):

```typescript
type Log = {
  address: Uint8Array       // 20 bytes — contract that emitted
  topics: Uint8Array[]      // each 32 bytes — indexed params
  data: Uint8Array          // ABI-encoded non-indexed params
  txHash: Uint8Array        // 32 bytes
  blockHash: Uint8Array     // 32 bytes
  eventSig: Uint8Array      // 32 bytes — keccak256 of event sig
  blockNumber?: BigInt
  txIndex: number
  logIndex: number
}
```

### Decoding the Log

```typescript
import { decodeAbiParameters, parseAbiParameters } from 'viem'

function decodeApplicationSubmitted(log: Log) {
  // Indexed params are in topics[1..3] — each is 32 bytes, left-padded
  const applicationId = bytesToHex(log.topics[1])  // bytes32
  const wallet = bytesToAddress(log.topics[2])      // address (last 20 bytes of 32)
  const issuer = bytesToAddress(log.topics[3])      // address

  // Non-indexed params are ABI-encoded in log.data
  const [broker, brokerPath, requestedTier] = decodeAbiParameters(
    parseAbiParameters('address broker, string brokerPath, uint8 requestedTier'),
    bytesToHex(log.data)
  )

  return { applicationId, wallet, issuer, broker, brokerPath, requestedTier }
}

// Helper — extract address from 32-byte padded topic
function bytesToAddress(topic: Uint8Array): `0x${string}` {
  return `0x${Buffer.from(topic.slice(12)).toString('hex')}` as `0x${string}`
}

function bytesToHex(bytes: Uint8Array): `0x${string}` {
  return `0x${Buffer.from(bytes).toString('hex')}` as `0x${string}`
}
```

---

## 3. Secrets

### secrets.yaml (updated)

```yaml
secretsNames:
    KYC_API_TOKEN:
        - SECRET_KYC_API_TOKEN
    ELIGIBILITY_RULEBOOK:
        - SECRET_ELIGIBILITY_RULEBOOK
    ETHERSCAN_API_KEY:
        - SECRET_ETHERSCAN_API_KEY
```

### .env

```bash
CRE_ETH_PRIVATE_KEY=<sepolia-private-key-with-gas>

# Vault-DON secrets — released only into attested enclaves
SECRET_KYC_API_TOKEN=<goplus-api-key>
SECRET_ELIGIBILITY_RULEBOOK='{"acme/_default":{"version":1,"minScore":60,"minAgeDays":30,"maxTier":1,"expiryDays":365,"jurisdictions":{"allow":["US","GB","SG"],"deny":["IR","KP","SY"]}},"acme/prime":{"version":1,"minScore":70,"expiryDays":90},"acme/delta":{"version":1,"minScore":90,"maxTier":0,"expiryDays":30},"zenith/_default":{"version":1,"minScore":65,"maxTier":1,"expiryDays":180}}'
SECRET_ETHERSCAN_API_KEY=<etherscan-api-key>
```

### Fetching Inside the Enclave

```typescript
const secrets = runtime.getSecrets([
  { id: "KYC_API_TOKEN" },
  { id: "ELIGIBILITY_RULEBOOK" },
  { id: "ETHERSCAN_API_KEY" },
]).result()

const goplusApiKey = secrets["KYC_API_TOKEN"].value
const rulebook = JSON.parse(secrets["ELIGIBILITY_RULEBOOK"].value)
const etherscanKey = secrets["ETHERSCAN_API_KEY"].value
```

**SDK constraint (verified):**
- Max 5 `getSecrets` calls per execution (`SecretsConcurrencyLimit`)
- Max 2 KB per secret ciphertext (`CipherTextSize`)
- Max 27 KB total secrets per workflow (`WASMSecretsSizeLimit`)
- The ELIGIBILITY_RULEBOOK JSON must stay under 2 KB. The example above is ~450 bytes.

---

## 4. Data Sources — Three Real Compliance Checks

### 4a. Chainalysis Sanctions Oracle (mainnet, on-chain)

The Chainalysis free sanctions oracle at `0x40C57923924B5c5c5455c48D93317139ADDaC8fb` on
Ethereum mainnet. `isSanctioned(address) → bool`. No API key. Free `eth_call`.

**Called via HTTP POST to a mainnet RPC from inside the enclave:**

```typescript
const httpClient = new cre.capabilities.HTTPClient()

const chainalysisCalldata = encodeFunctionData({
  abi: [{
    name: 'isSanctioned',
    type: 'function',
    inputs: [{ name: 'addr', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  }],
  functionName: 'isSanctioned',
  args: [wallet],
})

const rpcResponse = httpClient.sendRequest(runtime, {
  url: 'https://ethereum-rpc.publicnode.com',
  method: 'POST',
  multiHeaders: { 'Content-Type': { values: ['application/json'] } },
  body: JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'eth_call',
    params: [{
      to: '0x40C57923924B5c5c5455c48D93317139ADDaC8fb',
      data: chainalysisCalldata,
    }, 'latest'],
  }),
}).result()

const rpcResult = JSON.parse(text(rpcResponse))
const isSanctioned = decodeFunctionResult({
  abi: [{
    name: 'isSanctioned',
    type: 'function',
    inputs: [{ name: 'addr', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  }],
  functionName: 'isSanctioned',
  data: rpcResult.result,
}) as boolean
```

**Why HTTP `eth_call` instead of `EVMClient.callContract`:**
- `callContract` is an EVM capability — it runs on DON nodes, not inside the TEE.
  Whether it works inside `handlerInTee` is Gate 5's open question. HTTP is guaranteed.
- The RPC is a public endpoint. No secret needed. The raw response (sanctioned: true/false)
  stays inside the enclave.

**Why mainnet, not Sepolia:**
- The oracle is only deployed on mainnet. No Sepolia deployment exists.
- The wallet address `0xabc...` is the same across all chains.
- A sanctioned wallet is sanctioned everywhere — chain doesn't matter.
- This makes it **real** — judges can verify the oracle on Etherscan.

### 4b. GoPlus Security API (off-chain, real risk data)

```typescript
const goplusResponse = httpClient.sendRequest(runtime, {
  url: `https://api.gopluslabs.io/api/v1/address_security/${wallet}?chain_id=1`,
  method: 'GET',
  multiHeaders: {
    'Authorization': { values: [`Bearer ${goplusApiKey}`] },
  },
}).result()

const goplusResult = JSON.parse(text(goplusResponse)).result

// Fields returned by GoPlus:
// goplusResult.sanctioned        — "0" or "1"
// goplusResult.mixer             — "0" or "1" (Tornado Cash etc.)
// goplusResult.phishing_activities — "0" or "1"
// goplusResult.honeypot_related_address — "0" or "1"
// goplusResult.malicious_mining_activities — "0" or "1"
// goplusResult.blacklist_doubt   — "0" or "1"
```

**What this gives us that Chainalysis doesn't:**
- Mixer usage (Tornado Cash interaction)
- Phishing links
- Honeypot associations
- Malicious mining activity
- General blacklist suspicion

All of this stays inside the enclave. Only the pass/fail verdict leaves.

### 4c. Etherscan API (off-chain, wallet history)

```typescript
const etherscanResponse = httpClient.sendRequest(runtime, {
  url: `https://api.etherscan.io/v2/api?chainid=1&module=account&action=txlist&address=${wallet}&startblock=0&endblock=99999999&page=1&offset=1&sort=asc&apikey=${etherscanKey}`,
  method: 'GET',
}).result()

const etherscanResult = JSON.parse(text(etherscanResponse))
const firstTx = etherscanResult.result?.[0]
const walletAgeDays = firstTx
  ? Math.floor((Date.now() / 1000 - Number(firstTx.timeStamp)) / 86400)
  : 0  // no history = brand new wallet
```

**What this gives us:**
- Wallet age (days since first transaction) — fresh wallets are suspicious
- Existence verification — a wallet with zero history is a red flag

---

## 5. Policy Evaluation

### ELIGIBILITY_RULEBOOK Structure

```typescript
type PolicyEntry = {
  version: number
  minScore?: number        // minimum acceptable risk score (0-100)
  minAgeDays?: number      // minimum wallet age in days
  maxTier?: number         // 0 = retail only, 1 = retail + MM
  expiryDays?: number      // subname TTL in days
  jurisdictions?: {
    allow?: string[]       // allowed jurisdictions
    deny?: string[]        // denied jurisdictions
  }
}

type Rulebook = Record<string, PolicyEntry>
// Keys: "acme/_default", "acme/prime", "acme/delta", "zenith/_default", etc.
```

### Policy Lookup

```typescript
function lookupPolicy(rulebook: Rulebook, brokerPath: string): PolicyEntry {
  // brokerPath is "acme/prime" or "zenith/prime"
  const issuerLabel = brokerPath.split('/')[0]  // "acme"
  const issuerDefault = rulebook[`${issuerLabel}/_default`]
  const brokerOverride = rulebook[brokerPath]

  if (!issuerDefault) throw new Error(`No issuer default for ${issuerLabel}`)

  // If no broker-specific override, use issuer default as-is
  if (!brokerOverride) return issuerDefault

  // Combine: broker may TIGHTEN, never loosen
  return {
    version: brokerOverride.version ?? issuerDefault.version,
    minScore:   Math.max(issuerDefault.minScore ?? 0, brokerOverride.minScore ?? 0),
    minAgeDays: Math.max(issuerDefault.minAgeDays ?? 0, brokerOverride.minAgeDays ?? 0),
    maxTier:    Math.min(issuerDefault.maxTier ?? 1, brokerOverride.maxTier ?? 1),
    expiryDays: Math.min(issuerDefault.expiryDays ?? 365, brokerOverride.expiryDays ?? 365),
    jurisdictions: {
      allow: intersect(issuerDefault.jurisdictions?.allow, brokerOverride.jurisdictions?.allow),
      deny: union(issuerDefault.jurisdictions?.deny, brokerOverride.jurisdictions?.deny),
    },
  }
}

function intersect(a?: string[], b?: string[]): string[] | undefined {
  if (!a) return b
  if (!b) return a
  return a.filter(x => b.includes(x))
}

function union(a?: string[], b?: string[]): string[] | undefined {
  if (!a) return b
  if (!b) return a
  return [...new Set([...a, ...b])]
}
```

### Combination Rules (from spec)

| Field type | Rule | Effect |
|---|---|---|
| Numeric threshold (`minScore`, `minAgeDays`) | `max(issuer, broker)` | Broker can raise the bar |
| Allowlist (`jurisdictions.allow`) | intersection | Broker can only narrow |
| Denylist (`jurisdictions.deny`) | union | Broker can only add |
| `maxTier` | `min(issuer, broker)` | Retail-only broker can't mint an MM |
| `expiryDays` | `min(issuer, broker)` | Broker can't outlive issuer's ceiling |

### Risk Score Computation

```typescript
function computeRiskScore(goplus: GoPlusResult, walletAgeDays: number): number {
  let score = 100  // start at 100, deduct for risk factors

  // Hard disqualifiers — return 0 immediately
  if (goplus.sanctioned === '1') return 0
  if (goplus.mixer === '1') return 0

  // Deductions for risk factors
  if (goplus.phishing_activities === '1') score -= 40
  if (goplus.honeypot_related_address === '1') score -= 30
  if (goplus.malicious_mining_activities === '1') score -= 20
  if (goplus.blacklist_doubt === '1') score -= 15

  // Wallet age factor — newer wallets are riskier
  if (walletAgeDays < 7) score -= 30
  else if (walletAgeDays < 30) score -= 15
  else if (walletAgeDays < 90) score -= 5
  // 90+ days = no deduction

  return Math.max(0, score)
}
```

**This formula is public (it's in the source code).** That's fine — the THRESHOLDS
(`minScore: 70` vs `minScore: 90`) are in the secret RULEBOOK. A judge can read the
formula and confirm: "there are no hardcoded pass/fail decisions in the code."

### Evaluation

```typescript
function evaluate(
  riskScore: number,
  walletAgeDays: number,
  chainalysisSanctioned: boolean,
  goplus: GoPlusResult,
  policy: PolicyEntry,
  requestedTier: number,
): Verdict {
  // Layer 1: Chainalysis — HARD REJECT, no policy can override
  if (chainalysisSanctioned) {
    return { approved: false, reason: 'SANCTIONED_CHAINALYSIS' }
  }

  // Layer 2: GoPlus sanctions — HARD REJECT
  if (goplus.sanctioned === '1') {
    return { approved: false, reason: 'SANCTIONED_GOPLUS' }
  }

  // Layer 3: GoPlus mixer — HARD REJECT (Tornado Cash interaction)
  if (goplus.mixer === '1') {
    return { approved: false, reason: 'MIXER_ASSOCIATED' }
  }

  // Layer 4: Wallet age check
  if (walletAgeDays < (policy.minAgeDays ?? 0)) {
    return { approved: false, reason: 'WALLET_TOO_NEW' }
  }

  // Layer 5: Risk score check against policy threshold
  if (riskScore < (policy.minScore ?? 0)) {
    return { approved: false, reason: 'SCORE_BELOW_THRESHOLD' }
  }

  // Layer 6: Tier determination
  const actualTier = Math.min(requestedTier, policy.maxTier ?? 1)

  // Layer 7: Role bitmap
  const ROLE_ELIGIBLE_SWAP      = 1n << 64n
  const ROLE_ELIGIBLE_LIQUIDITY = 1n << 68n

  let roleBitmap = ROLE_ELIGIBLE_SWAP  // tier 0 = swap only
  if (actualTier >= 1) {
    roleBitmap = ROLE_ELIGIBLE_SWAP | ROLE_ELIGIBLE_LIQUIDITY  // tier 1 = both
  }

  // Layer 8: Expiry
  const expiry = BigInt(Math.floor(Date.now() / 1000) + (policy.expiryDays ?? 365) * 86400)

  return { approved: true, roleBitmap, expiry, tier: actualTier }
}
```

---

## 6. Report Encoding + On-Chain Delivery

### Report Tuple (interface contract with MintAttestor)

```
uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
uint256 roleBitmap, uint64 expiry, bool approved
```

- `kind` = `0` (investor). Decode guard — never any other value this week.
- `subject` = the wallet address
- `labelBytes` = label right-padded into bytes32 (e.g. "alice" → `0x616c696365000...000`)
- `parentRegistry` = the broker's registry address (where the subname is minted)
- `roleBitmap` = `ROLE_ELIGIBLE_SWAP` or `ROLE_ELIGIBLE_SWAP | ROLE_ELIGIBLE_LIQUIDITY`
- `expiry` = absolute Unix timestamp
- `approved` = true/false

### Encoding

```typescript
import { encodeAbiParameters, parseAbiParameters, stringToHex, hexToBase64 } from 'viem'

// Convert label string to bytes32 (right-padded)
const labelBytes = stringToHex(label, { size: 32 })

const reportData = encodeAbiParameters(
  parseAbiParameters(
    'uint8 kind, address subject, bytes32 labelBytes, address parentRegistry, uint256 roleBitmap, uint64 expiry, bool approved'
  ),
  [
    0,                    // kind = investor
    wallet,               // subject
    labelBytes,           // label as bytes32
    broker,               // parentRegistry (broker's registry)
    verdict.roleBitmap,   // role bits
    verdict.expiry,       // absolute Unix timestamp
    verdict.approved,     // true/false
  ]
)
```

### Crossing Back + Report + writeReport

```typescript
// ═══════════ CROSSING THE CONFIDENTIALITY BOUNDARY ═══════════
// Everything after usingTheDons() is NOT confidential.
// Only the verdict tuple crosses out — no raw API responses, no scores, no thresholds.
const donRuntime = runtime.usingTheDons()

// Generate DON-signed report
const report = donRuntime.report({
  encodedPayload: hexToBase64(reportData),
  encoderName: 'evm',
  signingAlgo: 'ecdsa',
  hashingAlgo: 'keccak256',
}).result()

// Write report to MintAttestor on Sepolia
sepoliaClient.writeReport(donRuntime, {
  receiver: config.mintAttestorAddress,
  report,
  gasConfig: { gasLimit: '500000' },
}).result()
```

### What Happens On-Chain After This

1. `KeystoneForwarder` receives the DON-signed report on Sepolia
2. Forwards to `MintAttestor.onReport(metadata, report)`
3. `MintAttestor._processReport`:
   - Validates `workflowId` from metadata
   - Decodes report tuple
   - If `!approved` → returns (no-op)
   - If `kind != 0` → reverts
   - Calls `SubnameRegistrar.registerFromAttestation(subject, label, parentRegistry, roleBitmap, expiry)`
   - Derives issuer registry via `getParent()` on the broker registry
   - Calls `checker.recordPath(subject, parentRegistry, labelhash)` on that issuer's checker
4. Subname is minted. Checker reflects the eligibility. Pool access is live.

---

## 7. File Changes — Exact Diffs

### `secrets.yaml` — add 2 secrets

```yaml
secretsNames:
    KYC_API_TOKEN:
        - SECRET_KYC_API_TOKEN
    ELIGIBILITY_RULEBOOK:
        - SECRET_ELIGIBILITY_RULEBOOK
    ETHERSCAN_API_KEY:
        - SECRET_ETHERSCAN_API_KEY
```

### `project.yaml` — add mainnet RPC (for Chainalysis HTTP eth_call)

```yaml
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
    - chain-name: ethereum-mainnet
      url: https://ethereum-rpc.publicnode.com
```

Note: the mainnet RPC is used as an HTTP endpoint for the Chainalysis `eth_call`.
The workflow does NOT trigger on mainnet or write reports to mainnet.

### `workflow.yaml` — update names

```yaml
staging-settings:
  user-workflow:
    workflow-name: "canopy-eligibility-staging"
  workflow-artifacts:
    workflow-path: "./main.ts"
    config-path: "./config.staging.json"
    secrets-path: "../secrets.yaml"
```

### `config.staging.json` — new shape

```json
{
  "applicationContractAddress": "0x<APPLICATION_CONTRACT_ON_SEPOLIA>",
  "mintAttestorAddress": "0x<MINT_ATTESTOR_ON_SEPOLIA>",
  "mainnetRpcUrl": "https://ethereum-rpc.publicnode.com",
  "etherscanBaseUrl": "https://api.etherscan.io/v2/api",
  "goplusBaseUrl": "https://api.gopluslabs.io/api/v1",
  "chainalysisOracleAddress": "0x40C57923924B5c5c5455c48D93317139ADDaC8fb",
  "gasLimit": "500000"
}
```

### `.env` — full set

```bash
CRE_ETH_PRIVATE_KEY=<sepolia-private-key>

# Vault-DON secrets
SECRET_KYC_API_TOKEN=<goplus-bearer-token>
SECRET_ETHERSCAN_API_KEY=<etherscan-api-key>
SECRET_ELIGIBILITY_RULEBOOK='{"acme/_default":{"version":1,"minScore":60,"minAgeDays":30,"maxTier":1,"expiryDays":365,"jurisdictions":{"allow":["US","GB","SG"],"deny":["IR","KP","SY"]}},"acme/prime":{"version":1,"minScore":70,"expiryDays":90},"acme/delta":{"version":1,"minScore":90,"maxTier":0,"expiryDays":30},"zenith/_default":{"version":1,"minScore":65,"maxTier":1,"expiryDays":180}}'
```

---

## 8. The Full Handler — Pseudocode

```typescript
export const onApplicationSubmitted = (
  runtime: TeeRuntime<Config>,
  log: Log,
): void => {
  const config = runtime.config

  // ── STEP 1: Decode the trigger event ──
  const { wallet, issuer, broker, brokerPath, requestedTier } =
    decodeApplicationSubmitted(log)

  // ── STEP 2: Fetch all secrets ──
  const secrets = runtime.getSecrets([
    { id: 'KYC_API_TOKEN' },
    { id: 'ELIGIBILITY_RULEBOOK' },
    { id: 'ETHERSCAN_API_KEY' },
  ]).result()

  const goplusApiKey = secrets['KYC_API_TOKEN'].value
  const rulebook: Rulebook = JSON.parse(secrets['ELIGIBILITY_RULEBOOK'].value)
  const etherscanKey = secrets['ETHERSCAN_API_KEY'].value

  // ── STEP 3: Chainalysis sanctions check (mainnet oracle via HTTP eth_call) ──
  const isSanctioned = checkChainalysis(runtime, config, wallet)

  // ── STEP 4: GoPlus risk assessment ──
  const goplusResult = checkGoPlus(runtime, goplusApiKey, wallet)

  // ── STEP 5: Etherscan wallet history ──
  const walletAgeDays = checkWalletAge(runtime, etherscanKey, wallet)

  // ── STEP 6: Look up and combine policy ──
  const effectivePolicy = lookupPolicy(rulebook, brokerPath)

  // ── STEP 7: Compute risk score ──
  const riskScore = computeRiskScore(goplusResult, walletAgeDays)

  // ── STEP 8: Evaluate against policy ──
  const verdict = evaluate(
    riskScore, walletAgeDays, isSanctioned,
    goplusResult, effectivePolicy, requestedTier
  )

  // ── STEP 9: Derive label from applicationId or wallet ──
  // The label is deterministic: use the brokerPath + truncated wallet
  // Or read from the event if the application contract assigns it
  const label = deriveLabel(wallet, brokerPath)

  // ── STEP 10: Encode the report tuple ──
  const reportData = encodeReportTuple(
    0,                // kind = investor
    wallet,           // subject
    label,            // → bytes32
    broker,           // parentRegistry
    verdict.roleBitmap ?? 0n,
    verdict.expiry ?? 0n,
    verdict.approved,
  )

  // ════════════ CROSSING THE CONFIDENTIALITY BOUNDARY ════════════
  const donRuntime = runtime.usingTheDons()

  const report = donRuntime.report({
    encodedPayload: hexToBase64(reportData),
    encoderName: 'evm',
    signingAlgo: 'ecdsa',
    hashingAlgo: 'keccak256',
  }).result()

  sepoliaClient.writeReport(donRuntime, {
    receiver: config.mintAttestorAddress,
    report,
    gasConfig: { gasLimit: config.gasLimit },
  }).result()
}
```

---

## 9. Handler Registration

```typescript
export function initWorkflow(config: Config) {
  const sepoliaNetwork = getNetwork({
    chainFamily: 'evm',
    chainSelectorName: 'ethereum-testnet-sepolia',
    isTestnet: true,
  })

  const sepoliaClient = new EVMClient(sepoliaNetwork.chainSelector)

  const trigger = sepoliaClient.logTrigger(
    logTriggerConfig({
      addresses: [config.applicationContractAddress],
      topics: [[APPLICATION_SUBMITTED_TOPIC]],
      confidence: 'FINALIZED',
    })
  )

  return [
    cre.handlerInTee(
      trigger,
      (runtime: TeeRuntime<Config>, log: Log) => onApplicationSubmitted(runtime, log),
      [{ tee: 'nitro', regions: ['us-west-2'] }],
    ),
  ]
}
```

---

## 10. Running

### Simulate (local, with real API calls)

```bash
cd cre
/Users/sakshishah/.cre/bin/cre workflow simulate eligibility-workflow \
  --target staging-settings \
  --non-interactive \
  --trigger-index 0 \
  --broadcast \
  --verbose
```

- `--broadcast`: writes a REAL KeystoneForwarder tx to Sepolia
- `--trigger-index 0`: uses the first (only) trigger
- `--non-interactive`: no prompts
- Simulation compiles to WASM, makes real HTTP calls, uses real secrets

### What to Expect

```
[SIMULATION] Running trigger trigger=evm-log-trigger@1.0.0
[SIMULATION] Trigger requested TEE Execution...
[SIMULATOR]  step[1]  Capability: vault-secrets@1.0.0 - COMPLETED     ← secrets fetched
[SIMULATOR]  step[2]  Capability: http-actions@1.0.0 - COMPLETED      ← Chainalysis
[SIMULATOR]  step[3]  Capability: http-actions@1.0.0 - COMPLETED      ← GoPlus
[SIMULATOR]  step[4]  Capability: http-actions@1.0.0 - COMPLETED      ← Etherscan
[SIMULATOR]  step[5]  Capability: consensus@1.0.0 - COMPLETED         ← report signed
[SIMULATOR]  step[6]  Capability: evm-write@1.0.0 - COMPLETED         ← writeReport tx
```

---

## 11. Demo Scenarios

### Scenario 1: Clean Wallet → APPROVE under `prime`

- Chainalysis: not sanctioned
- GoPlus: all clear
- Etherscan: wallet age 200 days
- Risk score: 100
- Policy (`acme/prime`): `minScore: 70, maxTier: 1, expiryDays: 90`
- **Result:** APPROVE, `ROLE_ELIGIBLE_SWAP | ROLE_ELIGIBLE_LIQUIDITY`, expiry 90 days

### Scenario 2: Same Wallet → REJECT under `delta`

- Same data, same score: 100
- But `requestedTier: 1` (MM) and policy (`acme/delta`): `maxTier: 0`
- **Result:** APPROVE but tier clamped to 0, only `ROLE_ELIGIBLE_SWAP`, expiry 30 days
- (Or if `minScore: 90` and the wallet has some minor risk factors bringing it to 85 → REJECT)

### Scenario 3: Sanctioned Address → HARD REJECT

- Chainalysis: `isSanctioned = true`
- **Result:** REJECT immediately, no score computation, no report written

### Scenario 4: Mixer-Associated Wallet → HARD REJECT

- Chainalysis: clean
- GoPlus: `mixer = "1"` (interacted with Tornado Cash)
- **Result:** REJECT, `MIXER_ASSOCIATED`

### Scenario 5: Brand New Wallet → REJECT

- All APIs clean, but wallet age = 2 days
- Policy `minAgeDays: 30`
- **Result:** REJECT, `WALLET_TOO_NEW`

---

## 12. Open Questions (To Verify During Implementation)

1. **Can `EVMClient.callContract` be called inside `handlerInTee`?**
   Gate 5's simulation didn't test this. If yes, we could use CRE's native EVM read
   instead of HTTP `eth_call` for the Chainalysis oracle. Either way works — HTTP is
   the safe path.

2. **Must HTTP responses be deterministic across nodes for consensus?**
   The Chainalysis oracle is deterministic (same block → same result). GoPlus and
   Etherscan may have minor timing differences. The report is generated inside the TEE
   by a single node, then attested — so minor response variation shouldn't break
   consensus, but verify.

3. **Label derivation.**
   The `label` in the report tuple needs to match what the user expects. Options:
   - Passed in the `ApplicationSubmitted` event as an additional field
   - Derived deterministically (e.g., first 8 chars of wallet address)
   - Chosen by the user in the application form

4. **HTTP rate limits inside simulation.**
   SDK enforces: `req=120kb, resp=250kb, timeout=10s` for regular HTTP.
   All three API responses should be well under 250kb. Verify Etherscan's response
   size for wallets with many transactions (we only request `offset=1`).

---

## 13. Files To Create/Modify

| File | Action | Description |
|---|---|---|
| `cre/eligibility-workflow/workflow.ts` | **REWRITE** | Full handler: logTrigger → decode → 3 API calls → policy lookup → evaluate → report → writeReport |
| `cre/eligibility-workflow/config.staging.json` | **REWRITE** | New shape with contract addresses, API URLs |
| `cre/secrets.yaml` | **MODIFY** | Add ELIGIBILITY_RULEBOOK, ETHERSCAN_API_KEY |
| `cre/eligibility-workflow/workflow.yaml` | **MODIFY** | Rename to canopy-eligibility-staging |
| `cre/.env` | **MODIFY** | Add real keys |
| `cre/.env.example` | **MODIFY** | Add placeholder entries for all secrets |
| `cre/project.yaml` | **MODIFY** | Add mainnet RPC |
| `cre/eligibility-workflow/workflow.test.ts` | **REWRITE** | Tests for new handler |
| `cre/policy-schema.md` | **CREATE** | Public schema doc for judges |
| `contracts/src/cre/MintAttestor.sol` | **CREATE** | Builder A, but CRE depends on it |
| `contracts/src/cre/ReceiverTemplate.sol` | **CREATE** | Port from LienFi |
| `contracts/src/cre/IReceiver.sol` | **CREATE** | Port from LienFi |
