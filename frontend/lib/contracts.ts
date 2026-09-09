import deployments from "../deployments.json";

// ---------------------------------------------------------------------------
// Addresses
// ---------------------------------------------------------------------------

export const addresses = {
  // ENS v2
  rootRegistry: deployments.ens.RootRegistry as `0x${string}`,
  ethRegistry: deployments.ens.ETHRegistry as `0x${string}`,
  ethRegistrar: deployments.ens.ETHRegistrar as `0x${string}`,
  labelStore: deployments.ens.LabelStore as `0x${string}`,

  // Canopy
  canopyTestToken: deployments.canopy.CanopyTestToken as `0x${string}`,
  issuerChecker:
    deployments.canopy.IssuerAllowlistCheckerFlat as `0x${string}`,
  permissionsAdapter: deployments.canopy.PermissionsAdapter as `0x${string}`,

  // Uniswap
  poolManager: deployments.uniswap.PoolManager as `0x${string}`,
  universalRouter: deployments.uniswap.UniversalRouter as `0x${string}`,
  v4Quoter: deployments.uniswap.V4Quoter as `0x${string}`,
  permissionedPositionManager:
    deployments.uniswap.PermissionedPositionManager as `0x${string}`,
  permissionedHooks: deployments.uniswap.PermissionedHooks as `0x${string}`,

  // Pool
  pool: {
    currency0: deployments.pool.currency0 as `0x${string}`,
    currency1: deployments.pool.currency1 as `0x${string}`,
    fee: deployments.pool.fee,
    tickSpacing: deployments.pool.tickSpacing,
    hooks: deployments.pool.hooks as `0x${string}`,
    poolId: deployments.pool.poolId as `0x${string}`,
  },

  // CRE
  applicationContract: deployments.cre.ApplicationContract as `0x${string}`,
  mintAttestor: deployments.cre.MintAttestor as `0x${string}`,
} as const;

// ---------------------------------------------------------------------------
// ABIs (minimal — only the functions we call from the frontend)
// ---------------------------------------------------------------------------

export const IPermissionedRegistryAbi = [
  {
    type: "function",
    name: "getState",
    inputs: [{ name: "anyId", type: "uint256" }],
    outputs: [
      {
        name: "state",
        type: "tuple",
        components: [
          { name: "status", type: "uint8" },
          { name: "expiry", type: "uint64" },
          { name: "latestOwner", type: "address" },
          { name: "tokenId", type: "uint256" },
          { name: "resource", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "register",
    inputs: [
      { name: "label", type: "string" },
      { name: "owner", type: "address" },
      { name: "registry", type: "address" },
      { name: "resolver", type: "address" },
      { name: "roleBitmap", type: "uint256" },
      { name: "expiry", type: "uint64" },
    ],
    outputs: [{ name: "tokenId", type: "uint256" }],
    stateMutability: "nonpayable",
  },
] as const;

export const IRegistryAbi = [
  {
    type: "function",
    name: "getParent",
    inputs: [],
    outputs: [
      { name: "parent", type: "address" },
      { name: "label", type: "string" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getSubregistry",
    inputs: [{ name: "label", type: "string" }],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
] as const;

export const IssuerAllowlistCheckerFlatAbi = [
  {
    type: "function",
    name: "checkAllowlist",
    inputs: [
      { name: "account", type: "address" },
      { name: "", type: "address" },
    ],
    outputs: [{ name: "", type: "bytes2" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "allowed",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

export const ApplicationContractAbi = [
  {
    type: "function",
    name: "submitApplication",
    inputs: [
      { name: "broker", type: "address" },
      { name: "label", type: "string" },
      { name: "requestedTier", type: "uint8" },
    ],
    outputs: [{ name: "applicationId", type: "bytes32" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "submitApplicationFor",
    inputs: [
      { name: "wallet", type: "address" },
      { name: "issuer", type: "address" },
      { name: "broker", type: "address" },
      { name: "brokerPath", type: "string" },
      { name: "label", type: "string" },
      { name: "requestedTier", type: "uint8" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "ApplicationSubmitted",
    inputs: [
      { name: "applicationId", type: "bytes32", indexed: true },
      { name: "wallet", type: "address", indexed: true },
      { name: "issuer", type: "address", indexed: true },
      { name: "broker", type: "address", indexed: false },
      { name: "brokerPath", type: "string", indexed: false },
      { name: "label", type: "string", indexed: false },
      { name: "requestedTier", type: "uint8", indexed: false },
    ],
    anonymous: false,
  },
] as const;

export const PermissionsAdapterAbi = [
  {
    type: "function",
    name: "isAllowed",
    inputs: [
      { name: "account", type: "address" },
      { name: "permission", type: "bytes2" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "allowListChecker",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swappingEnabled",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

export const MintAttestorAbi = [
  {
    type: "event",
    name: "VerdictReceived",
    inputs: [
      { name: "subject", type: "address", indexed: true },
      { name: "approved", type: "bool", indexed: false },
      { name: "roleBitmap", type: "uint256", indexed: false },
      { name: "expiry", type: "uint64", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "SubnameMinted",
    inputs: [
      { name: "subject", type: "address", indexed: true },
      { name: "parentRegistry", type: "address", indexed: true },
      { name: "issuerRegistry", type: "address", indexed: true },
    ],
    anonymous: false,
  },
] as const;

// ---------------------------------------------------------------------------
// Permission flags (bytes2)
// ---------------------------------------------------------------------------

export const PERMISSION_SWAP = "0x0001" as `0x${string}`;
export const PERMISSION_LIQUIDITY = "0x0002" as `0x${string}`;
export const PERMISSION_BOTH = "0x0003" as `0x${string}`;

// ENS registration status codes
export const STATUS = {
  AVAILABLE: 0,
  REGISTERED: 1,
  EXPIRED: 2,
} as const;
