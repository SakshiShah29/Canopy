/**
 * Static hierarchy config — mirrors contracts/script/hierarchy.json.
 *
 * Registry addresses are NOT enumerable on-chain, so we maintain this mapping.
 * In production these would come from an indexer; for the hackathon they're
 * resolved at runtime via getSubregistry() calls starting from ETHRegistry.
 */

export interface InvestorConfig {
  label: string;
  wallet: string; // empty = deterministic placeholder (can't sign)
  swap: boolean;
  liquidity: boolean;
}

export interface BrokerConfig {
  label: string;
  ttl: number; // 0 = env default (short for demo)
  investors: InvestorConfig[];
  registryAddress?: `0x${string}`; // populated at runtime
}

export interface IssuerConfig {
  label: string;
  ttl: number;
  brokers: BrokerConfig[];
  registryAddress?: `0x${string}`; // populated at runtime
}

export interface HierarchyConfig {
  platformLabel: string;
  issuers: IssuerConfig[];
}

export const hierarchyConfig: HierarchyConfig = {
  platformLabel: "canopy",
  issuers: [
    {
      label: "acme",
      ttl: 31_536_000,
      brokers: [
        {
          label: "prime",
          ttl: 0,
          investors: [
            { label: "alice", wallet: "", swap: true, liquidity: false },
            { label: "mm", wallet: "", swap: true, liquidity: true },
          ],
        },
        {
          label: "delta",
          ttl: 2_592_000,
          investors: [],
        },
      ],
    },
    {
      label: "zenith",
      ttl: 31_536_000,
      brokers: [
        {
          label: "prime",
          ttl: 7_776_000,
          investors: [
            { label: "bob", wallet: "", swap: true, liquidity: false },
            { label: "mm2", wallet: "", swap: true, liquidity: true },
          ],
        },
      ],
    },
  ],
};
