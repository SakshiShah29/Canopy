import { type Address } from "viem";
import { publicClient } from "./client";
import { addresses, IPermissionedRegistryAbi } from "./contracts";
import { getSubregistry, labelhash } from "./ensv2";
import { hierarchyConfig } from "./hierarchy";

export type Role = "issuer" | "broker" | "investor" | "applicant";

export interface RoleInfo {
  role: Role;
  issuerName?: string;
  brokerName?: string;
  investorName?: string;
  registryAddress?: Address;
}

const PLATFORM_ADMIN = "0xcE1606F346726d8714985b680B84dD6959fb4186";

/**
 * Detect the user's role in the Canopy hierarchy.
 * Walks the ENS tree checking ownership at each level.
 */
export async function detectRole(address: string): Promise<RoleInfo> {
  const addr = address.toLowerCase();

  // 0. Platform admin
  if (addr === PLATFORM_ADMIN.toLowerCase()) {
    return { role: "issuer", issuerName: "platform-admin" };
  }

  // Get canopy registry
  const canopyRegistry = await getSubregistry(
    addresses.ethRegistry,
    hierarchyConfig.platformLabel
  );
  if (!canopyRegistry) return { role: "applicant" };

  // 1. Check issuer level
  for (const issuer of hierarchyConfig.issuers) {
    try {
      const state = await publicClient.readContract({
        address: canopyRegistry,
        abi: IPermissionedRegistryAbi,
        functionName: "getState",
        args: [labelhash(issuer.label)],
      });
      const s = state as { latestOwner: Address };
      if (s.latestOwner.toLowerCase() === addr) {
        return {
          role: "issuer",
          issuerName: issuer.label,
          registryAddress: canopyRegistry,
        };
      }
    } catch {
      continue;
    }

    // 2. Check broker level under this issuer
    const issuerRegistry = await getSubregistry(canopyRegistry, issuer.label);
    if (!issuerRegistry) continue;

    for (const broker of issuer.brokers) {
      try {
        const state = await publicClient.readContract({
          address: issuerRegistry,
          abi: IPermissionedRegistryAbi,
          functionName: "getState",
          args: [labelhash(broker.label)],
        });
        const s = state as { latestOwner: Address };
        if (s.latestOwner.toLowerCase() === addr) {
          return {
            role: "broker",
            issuerName: issuer.label,
            brokerName: broker.label,
            registryAddress: issuerRegistry,
          };
        }
      } catch {
        continue;
      }

      // 3. Check investor level under this broker
      const brokerRegistry = await getSubregistry(
        issuerRegistry,
        broker.label
      );
      if (!brokerRegistry) continue;

      for (const investor of broker.investors) {
        try {
          const state = await publicClient.readContract({
            address: brokerRegistry,
            abi: IPermissionedRegistryAbi,
            functionName: "getState",
            args: [labelhash(investor.label)],
          });
          const s = state as { latestOwner: Address };
          if (s.latestOwner.toLowerCase() === addr) {
            return {
              role: "investor",
              issuerName: issuer.label,
              brokerName: broker.label,
              investorName: investor.label,
              registryAddress: brokerRegistry,
            };
          }
        } catch {
          continue;
        }
      }
    }
  }

  return { role: "applicant" };
}
