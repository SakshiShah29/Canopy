import { keccak256, toHex, type Address } from "viem";
import { publicClient } from "./client";
import {
  addresses,
  IPermissionedRegistryAbi,
  STATUS,
} from "./contracts";
import { hierarchyConfig } from "./hierarchy";
import { getSubregistry } from "./ensv2";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type BrokerTerms = {
  /** The broker's own registry address */
  registry: Address;
  /** The issuer's registry address (where the broker's state lives) */
  issuerRegistry: Address;
  /** Human-readable label (e.g., "prime") */
  label: string;
  /** Issuer this broker sits under */
  issuerLabel: string;
  /** Absolute Unix timestamp when the broker's name expires */
  expiry: bigint;
  /** Whether the broker's name is currently alive */
  alive: boolean;
  /** The on-chain policy hash, if set */
  policyHash: string | null;
  /** Number of known investors under this broker */
  investorCount: number;
  /** ENS full name (e.g., "prime.acme.canopy.eth") */
  ensName: string;
  /** Whether this broker supports MM tier */
  supportsMM: boolean;
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function labelHash(label: string): bigint {
  return BigInt(keccak256(toHex(label)));
}

// Cache issuer registry lookups to avoid repeated on-chain calls
const issuerRegistryCache = new Map<string, Address>();

async function resolveIssuerRegistry(
  issuerLabel: string
): Promise<Address | null> {
  const cached = issuerRegistryCache.get(issuerLabel);
  if (cached) return cached;

  // ETHRegistry → canopy → issuer
  const canopyRegistry = await getSubregistry(
    addresses.ethRegistry,
    hierarchyConfig.platformLabel
  );
  if (!canopyRegistry) return null;

  const issuerReg = await getSubregistry(canopyRegistry, issuerLabel);
  if (issuerReg) issuerRegistryCache.set(issuerLabel, issuerReg);
  return issuerReg;
}

// ---------------------------------------------------------------------------
// Read single broker terms
// ---------------------------------------------------------------------------

export async function getBrokerTerms(
  issuerRegistry: Address,
  brokerLabel: string,
  issuerLabel: string
): Promise<BrokerTerms> {
  const now = BigInt(Math.floor(Date.now() / 1000));
  let expiry = BigInt(0);
  let alive = false;

  try {
    const result = await publicClient.readContract({
      address: issuerRegistry,
      abi: IPermissionedRegistryAbi,
      functionName: "getState",
      args: [labelHash(brokerLabel)],
    });
    const s = result as {
      status: number;
      expiry: bigint;
      latestOwner: Address;
      tokenId: bigint;
      resource: bigint;
    };
    expiry = s.expiry;
    alive = s.status === STATUS.REGISTERED && s.expiry > now;
  } catch {
    // Contract call failed
  }

  // Resolve broker's own registry
  const brokerRegistry = await getSubregistry(issuerRegistry, brokerLabel);

  // Get investor info from hierarchy config
  const issuerConfig = hierarchyConfig.issuers.find(
    (i) => i.label === issuerLabel
  );
  const brokerConfig = issuerConfig?.brokers.find(
    (b) => b.label === brokerLabel
  );
  const investors = brokerConfig?.investors ?? [];
  const supportsMM = investors.some((inv) => inv.liquidity);

  return {
    registry:
      brokerRegistry ??
      ("0x0000000000000000000000000000000000000000" as Address),
    issuerRegistry,
    label: brokerLabel,
    issuerLabel,
    expiry,
    alive,
    policyHash: null, // Policy Chain not deployed yet
    investorCount: investors.length,
    ensName: `${brokerLabel}.${issuerLabel}.canopy.eth`,
    supportsMM,
  };
}

// ---------------------------------------------------------------------------
// Read all broker terms for an issuer
// ---------------------------------------------------------------------------

export async function getAllBrokerTerms(
  issuerLabel: string
): Promise<BrokerTerms[]> {
  const issuerRegistry = await resolveIssuerRegistry(issuerLabel);
  if (!issuerRegistry) return [];

  const issuerConfig = hierarchyConfig.issuers.find(
    (i) => i.label === issuerLabel
  );
  if (!issuerConfig) return [];

  return Promise.all(
    issuerConfig.brokers.map((b) =>
      getBrokerTerms(issuerRegistry, b.label, issuerLabel)
    )
  );
}

// ---------------------------------------------------------------------------
// Format duration helper
// ---------------------------------------------------------------------------

export function formatTimeRemaining(expiry: bigint, nowSeconds: number): string {
  const remaining = Number(expiry) - nowSeconds;
  if (remaining <= 0) return "Expired";

  const days = Math.floor(remaining / 86400);
  const hours = Math.floor((remaining % 86400) / 3600);
  const minutes = Math.floor((remaining % 3600) / 60);
  const seconds = remaining % 60;

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

export type UrgencyLevel = "stable" | "expiring-soon" | "critical" | "expired";

export function getUrgency(expiry: bigint, nowSeconds: number): UrgencyLevel {
  const remaining = Number(expiry) - nowSeconds;
  if (remaining <= 0) return "expired";
  if (remaining < 86400) return "critical"; // < 1 day
  if (remaining < 604800) return "expiring-soon"; // < 7 days
  return "stable";
}
