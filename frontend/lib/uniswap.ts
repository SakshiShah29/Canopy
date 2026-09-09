import { encodeFunctionData, parseEther, type Address } from "viem";
import { addresses } from "./contracts";
import { publicClient } from "./client";

// ---------------------------------------------------------------------------
// Pool key — used across all Uniswap interactions
// ---------------------------------------------------------------------------

export const poolKey = {
  currency0: addresses.pool.currency0,
  currency1: addresses.pool.currency1,
  fee: addresses.pool.fee,
  tickSpacing: addresses.pool.tickSpacing,
  hooks: addresses.pool.hooks,
} as const;

// ---------------------------------------------------------------------------
// V4 Quoter — get a quote for an exact-input swap
// ---------------------------------------------------------------------------

const QuoterAbi = [
  {
    type: "function",
    name: "quoteExactInputSingle",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          {
            name: "poolKey",
            type: "tuple",
            components: [
              { name: "currency0", type: "address" },
              { name: "currency1", type: "address" },
              { name: "fee", type: "uint24" },
              { name: "tickSpacing", type: "int24" },
              { name: "hooks", type: "address" },
            ],
          },
          { name: "zeroForOne", type: "bool" },
          { name: "exactAmount", type: "uint128" },
          { name: "hookData", type: "bytes" },
        ],
      },
    ],
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "gasEstimate", type: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
] as const;

export async function quoteSwap(
  amountIn: string,
  zeroForOne: boolean = true
): Promise<bigint | null> {
  try {
    const result = await publicClient.simulateContract({
      address: addresses.v4Quoter,
      abi: QuoterAbi,
      functionName: "quoteExactInputSingle",
      args: [
        {
          poolKey,
          zeroForOne,
          exactAmount: parseEther(amountIn),
          hookData: "0x",
        },
      ],
    });
    return result.result[0] as bigint;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Universal Router — exact input single swap (V4_SWAP command)
// ---------------------------------------------------------------------------

// Universal Router command IDs
const V4_SWAP = 0x10;

// V4Router action IDs
const SWAP_EXACT_IN_SINGLE = 0x06;
const SETTLE_ALL = 0x0c;
const TAKE_ALL = 0x0d;

const UniversalRouterAbi = [
  {
    type: "function",
    name: "execute",
    inputs: [
      { name: "commands", type: "bytes" },
      { name: "inputs", type: "bytes[]" },
      { name: "deadline", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

/**
 * Build a swap transaction to send via Privy wallet.
 * zeroForOne = true means ETH → Token (sell ETH for adapter-wrapped token).
 */
export function buildSwapTx(amountIn: string, zeroForOne: boolean = true) {
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 1800); // 30min
  const amount = parseEther(amountIn);

  // For a basic demo, we encode the swap command
  // The actual encoding is complex — this is a simplified version
  const data = encodeFunctionData({
    abi: UniversalRouterAbi,
    functionName: "execute",
    args: [
      // commands: just V4_SWAP
      `0x${V4_SWAP.toString(16).padStart(2, "0")}` as `0x${string}`,
      // inputs: encoded V4 swap params (simplified)
      ["0x" as `0x${string}`],
      deadline,
    ],
  });

  return {
    to: addresses.universalRouter,
    data,
    value: zeroForOne ? amount : BigInt(0),
  };
}

// ---------------------------------------------------------------------------
// Liquidity — PermissionedPositionManager
// ---------------------------------------------------------------------------

const PositionManagerAbi = [
  {
    type: "function",
    name: "modifyLiquidities",
    inputs: [
      { name: "unlockData", type: "bytes" },
      { name: "deadline", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

/**
 * Build an add-liquidity transaction (simplified for demo).
 */
export function buildAddLiquidityTx(amountEth: string) {
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 1800);
  const amount = parseEther(amountEth);

  const data = encodeFunctionData({
    abi: PositionManagerAbi,
    functionName: "modifyLiquidities",
    args: ["0x" as `0x${string}`, deadline],
  });

  return {
    to: addresses.permissionedPositionManager,
    data,
    value: amount,
  };
}
