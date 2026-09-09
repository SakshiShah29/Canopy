import { encodeFunctionData, type Address } from "viem";
import { addresses, ApplicationContractAbi } from "./contracts";

/**
 * Encode calldata for submitApplication.
 * The caller sends this via Privy's sendTransaction.
 */
export function encodeSubmitApplication(
  broker: Address,
  label: string,
  requestedTier: number
) {
  return {
    to: addresses.applicationContract,
    data: encodeFunctionData({
      abi: ApplicationContractAbi,
      functionName: "submitApplication",
      args: [broker, label, requestedTier],
    }),
    value: BigInt(0),
  };
}
