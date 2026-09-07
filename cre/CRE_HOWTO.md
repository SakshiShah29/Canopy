# How to Run the CRE Eligibility Workflow

## Prerequisites

1. **CRE CLI** installed (`cre` command available)
2. **Foundry** installed (`cast` command available)
3. **`.env` file** at `cre/.env` with these secrets:
   ```
   SECRET_GOPLUS_APP_KEY=<your GoPlus app key>
   SECRET_GOPLUS_APP_SECRET=<your GoPlus app secret>
   SECRET_ETHERSCAN_API_KEY=<your Etherscan API key>
   SECRET_ELIGIBILITY_RULEBOOK=<JSON rulebook>
   ```
4. A funded Sepolia wallet (for submitting the on-chain application tx)

## Step 1: Submit an Application

The `ApplicationContract` on Sepolia emits an `ApplicationSubmitted` event that the CRE workflow watches.

### For your own wallet:
```bash
cast send 0x488fe44CD310D25010a50FdE943f133148B34036 \
  "submitApplication(address,address,string,uint8)" \
  <ISSUER_ADDRESS> \
  <BROKER_ADDRESS> \
  "acme/prime" \
  1 \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --private-key <YOUR_PRIVATE_KEY>
```

### For testing with any arbitrary wallet address:
```bash
cast send 0x488fe44CD310D25010a50FdE943f133148B34036 \
  "submitApplicationFor(address,address,address,string,uint8)" \
  <WALLET_TO_CHECK> \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  "acme/prime" \
  1 \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --private-key <YOUR_PRIVATE_KEY>
```

**Important:** The `brokerPath` parameter (e.g. `"acme/prime"`) must match a key in your `ELIGIBILITY_RULEBOOK` secret, or at minimum `<issuerLabel>/_default` must exist.

Copy the `transactionHash` from the output — you'll need it for Step 2.

## Step 2: Simulate the CRE Workflow

```bash
cd cre
cre workflow simulate ./eligibility-workflow \
  --evm-tx-hash <TX_HASH> \
  --evm-event-index 0 \
  -e .env \
  -g
```

### Flags:
| Flag | Purpose |
|---|---|
| `--evm-tx-hash` | The Sepolia tx hash from Step 1 |
| `--evm-event-index 0` | Which log event in the tx to replay (always `0` for single-event txs) |
| `-e .env` | Load secrets from the `.env` file |
| `-g` | Enable debug logging (verbose output) |

## What Happens Inside

1. **Trigger** — CRE replays the `ApplicationSubmitted` event from the tx
2. **TEE Handler** — The WASM binary runs inside a simulated TEE enclave:
   - Decodes the event to extract `wallet`, `brokerPath`, `requestedTier`
   - Calls **Chainalysis Oracle** on mainnet (`isSanctioned` — hard reject if true)
   - Calls **GoPlus** `address_security` API (phishing, mixer, honeypot flags)
   - Calls **Etherscan** `txlist` API (wallet age from first tx)
   - Looks up policy from the secret `ELIGIBILITY_RULEBOOK`
   - Computes risk score and evaluates against policy thresholds
3. **Consensus** — DON nodes agree on the verdict
4. **Chain Write** — Signed report is delivered to `MintAttestor` on Sepolia

## Reading the Output

Look for `[USER LOG]` lines in the output:

```
[USER LOG] Processing application: wallet=0x..., brokerPath=acme/prime
[USER LOG] GoPlus flags: {...}
[USER LOG] WalletAgeDays=101, RiskScore=45
[USER LOG] Verdict: approved=false reason=SCORE_BELOW_THRESHOLD
```

The final line will be either:
- `"APPROVED"` — wallet passed all checks
- `"REJECTED:<REASON>"` — wallet failed, with reason like:
  - `SANCTIONED_CHAINALYSIS` — Chainalysis Oracle flagged the address
  - `SCORE_BELOW_THRESHOLD` — GoPlus flags dropped the risk score below policy minimum
  - `WALLET_TOO_NEW` — Wallet age below policy minimum
  - `TIER_EXCEEDS_MAX` — Requested tier above policy maximum
  - `GOPLUS_SANCTIONED` — GoPlus sanctioned flag
  - `GOPLUS_MIXER` — GoPlus mixer flag

## Deployed Contracts (Sepolia)

| Contract | Address |
|---|---|
| ApplicationContract | `0x488fe44CD310D25010a50FdE943f133148B34036` |
| MintAttestor | `0x5B9EED286356575E160C4C3F8724F6bC3433a9CF` |
| KeystoneForwarder | `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` |
