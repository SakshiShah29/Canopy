# CRE Eligibility Workflow — Test Results

All tests run on Sepolia (chainId 11155111) against mainnet data sources.

---

## Test 1: Vitalik Buterin (Clean Wallet)

**Address:** `0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045`
**Tx Hash:** _(submitted via `submitApplicationFor`)_
**Verdict:** `APPROVED`

| Check | Result |
|---|---|
| Chainalysis Oracle | `isSanctioned = false` |
| GoPlus address_security | No flags |
| Etherscan wallet age | Well over 30 days |
| Risk Score | High (no deductions) |

**CRE Logs:**
```
[USER LOG] Processing application: wallet=0xd8da6bf26964af9d7eed9e03e53415d37aa96045, brokerPath=acme/prime
[USER LOG] Verdict: approved=true
"APPROVED"
```
**Status:** `completed` (all 6 steps: 4 HTTP + consensus + chain write)

---

## Test 2: Tornado Cash Sanctioned Address

**Address:** `0x7F367cC41522cE07553e823bf3be79A889DEbe1B`
**Tx Hash:** _(submitted via `submitApplicationFor`)_
**Verdict:** `REJECTED:SANCTIONED_CHAINALYSIS`

| Check | Result |
|---|---|
| Chainalysis Oracle | `isSanctioned = true` ← **hard reject** |
| GoPlus address_security | Skipped (short-circuit) |
| Etherscan wallet age | Skipped (short-circuit) |
| Risk Score | N/A |

**CRE Logs:**
```
[USER LOG] Processing application: wallet=0x7f367cc41522ce07553e823bf3be79a889debe1b, brokerPath=acme/prime
[USER LOG] Verdict: approved=false reason=SANCTIONED_CHAINALYSIS
"REJECTED:SANCTIONED_CHAINALYSIS"
```
**Status:** `completed`

---

## Test 3: Known Phishing Address

**Address:** `0x6D8c070338eC3d297f1D0ECEEA296bd7E13a32b9`
**Tx Hash:** `0x4612fc8f46ecf3f0459540750b94b331d2c7deb0d5238cb46cb7c2432b51cfc4`
**Verdict:** `REJECTED:SCORE_BELOW_THRESHOLD`

| Check | Result |
|---|---|
| Chainalysis Oracle | `isSanctioned = false` (passed) |
| GoPlus `phishing_activities` | **`"1"` — flagged** (-40 pts) |
| GoPlus `blacklist_doubt` | **`"1"` — flagged** (-15 pts) |
| Etherscan wallet age | 101 days (no deduction) |
| Risk Score | **45** (below policy minimum of 60) |

**GoPlus Raw Response:**
```json
{
  "cybercrime": "0",
  "money_laundering": "0",
  "number_of_malicious_contracts_created": "0",
  "gas_abuse": "0",
  "financial_crime": "0",
  "darkweb_transactions": "0",
  "reinit": "0",
  "phishing_activities": "1",
  "contract_address": "0",
  "fake_kyc": "0",
  "blacklist_doubt": "1",
  "fake_standard_interface": "0",
  "data_source": "GoPlus",
  "stealing_attack": "0",
  "blackmail_activities": "0",
  "sanctioned": "0",
  "malicious_mining_activities": "0",
  "mixer": "0",
  "fake_token": "0",
  "honeypot_related_address": "0"
}
```

**CRE Logs:**
```
[USER LOG] Processing application: wallet=0x6d8c070338ec3d297f1d0eceea296bd7e13a32b9, brokerPath=acme/prime
[USER LOG] GoPlus flags: {"cybercrime":"0","money_laundering":"0","number_of_malicious_contracts_created":"0","gas_abuse":"0","financial_crime":"0","darkweb_transactions":"0","reinit":"0","phishing_activities":"1","contract_address":"0","fake_kyc":"0","blacklist_doubt":"1","fake_standard_interface":"0","data_source":"GoPlus","stealing_attack":"0","blackmail_activities":"0","sanctioned":"0","malicious_mining_activities":"0","mixer":"0","fake_token":"0","honeypot_related_address":"0"}
[USER LOG] WalletAgeDays=101, RiskScore=45
[USER LOG] Verdict: approved=false reason=SCORE_BELOW_THRESHOLD
"REJECTED:SCORE_BELOW_THRESHOLD"
```
**Status:** `completed`

---

## Summary

| Test | Address Type | Verdict | Rejection Path |
|---|---|---|---|
| Vitalik | Clean wallet | APPROVED | — |
| Tornado Cash | OFAC sanctioned | REJECTED | Chainalysis hard reject |
| Phishing addr | GoPlus flagged | REJECTED | Risk score 45 < 60 threshold |

All three data sources (Chainalysis Oracle, GoPlus, Etherscan) are called with real API keys inside the CRE TEE enclave. The pipeline covers all rejection paths: sanctions, risk scoring, and policy thresholds.
