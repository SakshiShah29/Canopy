import { keccak256, toHex, type Address } from "viem";
import { publicClient } from "./client";
import {
  addresses,
  IPermissionedRegistryAbi,
  IRegistryAbi,
  IssuerAllowlistCheckerFlatAbi,
  STATUS,
} from "./contracts";
import {
  hierarchyConfig,
  type BrokerConfig,
  type IssuerConfig,
} from "./hierarchy";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface RegistryState {
  status: number;
  expiry: bigint;
  latestOwner: Address;
  tokenId: bigint;
  resource: bigint;
}

export interface NodeState {
  label: string;
  fullName: string;
  registryAddress: Address;
  state: RegistryState | null;
  isAlive: boolean;
  children: NodeState[];
  level: "platform" | "issuer" | "broker" | "investor";
  swap: boolean;
  liquidity: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export function labelhash(label: string): bigint {
  return BigInt(keccak256(toHex(label)));
}

export function isAlive(state: RegistryState | null): boolean {
  if (!state) return false;
  return (
    state.status === STATUS.REGISTERED &&
    state.expiry > BigInt(Math.floor(Date.now() / 1000))
  );
}

// ---------------------------------------------------------------------------
// On-chain reads
// ---------------------------------------------------------------------------

export async function getRegistryState(
  registryAddress: Address,
  label: string
): Promise<RegistryState | null> {
  try {
    const result = await publicClient.readContract({
      address: registryAddress,
      abi: IPermissionedRegistryAbi,
      functionName: "getState",
      args: [labelhash(label)],
    });
    const s = result as {
      status: number;
      expiry: bigint;
      latestOwner: Address;
      tokenId: bigint;
      resource: bigint;
    };
    return {
      status: s.status,
      expiry: s.expiry,
      latestOwner: s.latestOwner,
      tokenId: s.tokenId,
      resource: s.resource,
    };
  } catch {
    return null;
  }
}

export async function getSubregistry(
  registryAddress: Address,
  label: string
): Promise<Address | null> {
  try {
    const result = await publicClient.readContract({
      address: registryAddress,
      abi: IRegistryAbi,
      functionName: "getSubregistry",
      args: [label],
    });
    const addr = result as Address;
    if (addr === "0x0000000000000000000000000000000000000000") return null;
    return addr;
  } catch {
    return null;
  }
}

export async function checkAllowlist(
  account: Address,
  checkerAddress: Address = addresses.issuerChecker
): Promise<`0x${string}` | null> {
  try {
    const result = await publicClient.readContract({
      address: checkerAddress,
      abi: IssuerAllowlistCheckerFlatAbi,
      functionName: "checkAllowlist",
      args: [account, addresses.permissionsAdapter],
    });
    return result as `0x${string}`;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Hierarchy tree builder
// ---------------------------------------------------------------------------

export async function buildHierarchyTree(): Promise<NodeState> {
  const ethRegistry = addresses.ethRegistry;

  // Get canopy subregistry from ETHRegistry
  const canopyRegistry = await getSubregistry(
    ethRegistry,
    hierarchyConfig.platformLabel
  );

  const issuerNodes: NodeState[] = [];

  if (canopyRegistry) {
    for (const issuer of hierarchyConfig.issuers) {
      const issuerState = await getRegistryState(canopyRegistry, issuer.label);
      const issuerRegistry = await getSubregistry(canopyRegistry, issuer.label);

      const brokerNodes: NodeState[] = [];

      if (issuerRegistry) {
        for (const broker of issuer.brokers) {
          const brokerState = await getRegistryState(
            issuerRegistry,
            broker.label
          );
          const brokerRegistry = await getSubregistry(
            issuerRegistry,
            broker.label
          );

          const investorNodes: NodeState[] = [];

          if (brokerRegistry) {
            for (const investor of broker.investors) {
              const investorState = await getRegistryState(
                brokerRegistry,
                investor.label
              );
              investorNodes.push({
                label: investor.label,
                fullName: `${investor.label}.${broker.label}.${issuer.label}.canopy.eth`,
                registryAddress: brokerRegistry,
                state: investorState,
                isAlive: isAlive(investorState),
                children: [],
                level: "investor",
                swap: investor.swap,
                liquidity: investor.liquidity,
              });
            }
          }

          brokerNodes.push({
            label: broker.label,
            fullName: `${broker.label}.${issuer.label}.canopy.eth`,
            registryAddress: issuerRegistry,
            state: brokerState,
            isAlive: isAlive(brokerState),
            children: investorNodes,
            level: "broker",
            swap: false,
            liquidity: false,
          });
        }
      }

      issuerNodes.push({
        label: issuer.label,
        fullName: `${issuer.label}.canopy.eth`,
        registryAddress: canopyRegistry,
        state: issuerState,
        isAlive: isAlive(issuerState),
        children: brokerNodes,
        level: "issuer",
        swap: false,
        liquidity: false,
      });
    }
  }

  return {
    label: "canopy",
    fullName: "canopy.eth",
    registryAddress: ethRegistry,
    state: null,
    isAlive: true,
    children: issuerNodes,
    level: "platform",
    swap: false,
    liquidity: false,
  };
}
