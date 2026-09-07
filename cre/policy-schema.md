# Canopy Policy Schema

> **This file is public by design.** It describes what a policy *can* express, not what
> any particular policy *says*. Publishing the schema is what makes the CRE confidentiality
> claim checkable: a judge reads the field list and confirms none of the discriminating
> values are in the source code.

## Rulebook Structure

The `ELIGIBILITY_RULEBOOK` is a Vault-DON secret — a JSON object keyed by **label path**:

```
{
  "<issuer>/_default": { ... },   // issuer's floor policy
  "<issuer>/<broker>": { ... }    // broker's override (optional)
}
```

Broker entries are **overrides**, not complete policies. Missing fields inherit from the
issuer default.

## Fields

| Field | Type | Description |
|---|---|---|
| `version` | `number` | Schema version (always 1 this week) |
| `minScore` | `number` | Minimum acceptable risk score (0–100). The scoring formula is public; the threshold is not. |
| `minAgeDays` | `number` | Minimum wallet age in days since first on-chain transaction |
| `maxTier` | `number` | Maximum tier the broker can approve. `0` = retail (swap only), `1` = market maker (swap + liquidity) |
| `expiryDays` | `number` | Subname TTL in days. Becomes the on-chain `expiry` in the report. |
| `jurisdictions.allow` | `string[]` | Allowed jurisdiction codes |
| `jurisdictions.deny` | `string[]` | Denied jurisdiction codes |

## Combination Rules — Broker May Tighten, Never Loosen

When a broker override exists, it is combined with the issuer default using these rules:

| Field type | Rule | Effect |
|---|---|---|
| Numeric threshold (`minScore`, `minAgeDays`) | `max(issuer, broker)` | Broker can raise the bar |
| Allowlist (`jurisdictions.allow`) | intersection | Broker can only narrow |
| Denylist (`jurisdictions.deny`) | union | Broker can only add |
| `maxTier` | `min(issuer, broker)` | Retail-only broker cannot mint an MM |
| `expiryDays` | `min(issuer, broker)` | Broker cannot outlive issuer's ceiling |

This is what a compliance control *is*: the issuer sets the rules and gives up the
discretion to make exceptions.

## Data Sources

The workflow evaluates these against the policy thresholds:

| Source | What it provides | Confidential? |
|---|---|---|
| Chainalysis Sanctions Oracle (mainnet) | Binary OFAC sanctions check | Evaluated inside TEE |
| GoPlus Security API | Risk profile: sanctions, mixer, phishing, malicious activity | Raw response stays in enclave |
| Etherscan API | Wallet age (first transaction timestamp) | Raw history stays in enclave |

## What Leaves the Enclave

Only the verdict tuple crosses the confidentiality boundary:

```
uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
uint256 roleBitmap, uint64 expiry, bool approved
```

No raw API responses. No scores. No thresholds. No PII.
