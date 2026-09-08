/**
 * Minimal ABIs — only the functions Canopy actually calls.
 *
 * Hand-written rather than generated from `forge build` output, because the console and the e2e
 * runner both need these and neither should depend on `contracts/out/` existing. They are small
 * enough to read, which matters more here than completeness: every one of these is a security
 * boundary or a demo beat.
 */

export const applicationContractAbi = [
  {
    type: 'function',
    name: 'submitApplication',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'broker', type: 'address' },
      { name: 'label', type: 'string' },
      { name: 'requestedTier', type: 'uint8' },
    ],
    outputs: [{ name: 'applicationId', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'submitApplicationFor',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'wallet', type: 'address' },
      { name: 'broker', type: 'address' },
      { name: 'label', type: 'string' },
      { name: 'requestedTier', type: 'uint8' },
    ],
    outputs: [{ name: 'applicationId', type: 'bytes32' }],
  },
  {
    type: 'event',
    name: 'ApplicationSubmitted',
    inputs: [
      { name: 'applicationId', type: 'bytes32', indexed: true },
      { name: 'wallet', type: 'address', indexed: true },
      { name: 'issuer', type: 'address', indexed: true },
      { name: 'broker', type: 'address', indexed: false },
      { name: 'brokerPath', type: 'string', indexed: false },
      { name: 'label', type: 'string', indexed: false },
      { name: 'requestedTier', type: 'uint8', indexed: false },
    ],
  },
] as const

export const checkerAbi = [
  {
    type: 'function',
    name: 'checkAllowlist',
    stateMutability: 'view',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'tokenAddress', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bytes2' }],
  },
  {
    type: 'function',
    name: 'leafOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [
      { name: 'registry', type: 'address' },
      { name: 'labelhash', type: 'uint256' },
    ],
  },
  {
    type: 'function',
    name: 'ISSUER_REGISTRY',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    type: 'function',
    name: 'PERMISSIONED_TOKEN',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    type: 'function',
    name: 'ROOT_ANCHOR',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
] as const

/**
 * `getState` returns the struct as a single tuple. `getSubregistry` is what makes a parent link
 * authoritative — the walk compares it against the registry it is standing in, so anything reading
 * the hierarchy off-chain has to do the same or it will show a tree the checker does not believe.
 */
export const registryAbi = [
  {
    type: 'function',
    name: 'getState',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [
      {
        name: 'state',
        type: 'tuple',
        components: [
          { name: 'status', type: 'uint8' },
          { name: 'expiry', type: 'uint64' },
          { name: 'latestOwner', type: 'address' },
          { name: 'tokenId', type: 'uint256' },
          { name: 'resource', type: 'uint256' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'getParent',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'parent', type: 'address' },
      { name: 'label', type: 'string' },
    ],
  },
  {
    type: 'function',
    name: 'getSubregistry',
    stateMutability: 'view',
    inputs: [{ name: 'label', type: 'string' }],
    outputs: [{ name: '', type: 'address' }],
  },
] as const

export const erc20Abi = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'decimals',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const

/** Canonical Permit2, same address on every chain. */
export const permit2Abi = [
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'token', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
      { name: 'nonce', type: 'uint48' },
    ],
  },
] as const

export const positionManagerAbi = [
  {
    type: 'function',
    name: 'modifyLiquidities',
    stateMutability: 'payable',
    inputs: [
      { name: 'unlockData', type: 'bytes' },
      { name: 'deadline', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'nextTokenId',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'ownerOf',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'address' }],
  },
] as const

/**
 * The adapter is the pool's currency. Beat 5 is one call on it: swapping the flat baseline checker
 * for the hierarchical one turns a permissioned pool into a Canopy pool without touching the pool.
 */
export const permissionsAdapterAbi = [
  {
    type: 'function',
    name: 'updateAllowListChecker',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newAllowListChecker', type: 'address' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'allowListChecker',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    type: 'function',
    name: 'swappingEnabled',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'isAllowed',
    stateMutability: 'view',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'permission', type: 'bytes2' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const

/** Registry writes the runner needs for beat 15. Reads live in `registryAbi`. */
export const registryWriteAbi = [
  {
    type: 'function',
    name: 'register',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'label', type: 'string' },
      { name: 'owner', type: 'address' },
      { name: 'subregistry', type: 'address' },
      { name: 'resolver', type: 'address' },
      { name: 'roleBitmap', type: 'uint256' },
      { name: 'expires', type: 'uint64' },
    ],
    outputs: [{ name: 'tokenId', type: 'uint256' }],
  },
] as const

export const universalRouterAbi = [
  {
    type: 'function',
    name: 'execute',
    stateMutability: 'payable',
    inputs: [
      { name: 'commands', type: 'bytes' },
      { name: 'inputs', type: 'bytes[]' },
      { name: 'deadline', type: 'uint256' },
    ],
    outputs: [],
  },
] as const
