"use client";

import { useCallback, useEffect, useState } from "react";
import { type Address } from "viem";
import { checkAllowlist } from "@/lib/ensv2";
import { PERMISSION_SWAP, PERMISSION_LIQUIDITY } from "@/lib/contracts";

const POLL_INTERVAL = 5_000;

export interface EligibilityFlags {
  raw: `0x${string}` | null;
  canSwap: boolean;
  canProvideLiquidity: boolean;
}

export function useEligibility(account: Address | undefined) {
  const [flags, setFlags] = useState<EligibilityFlags>({
    raw: null,
    canSwap: false,
    canProvideLiquidity: false,
  });
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    if (!account) {
      setFlags({ raw: null, canSwap: false, canProvideLiquidity: false });
      setLoading(false);
      return;
    }

    try {
      const result = await checkAllowlist(account);
      if (result) {
        const val = parseInt(result, 16);
        setFlags({
          raw: result,
          canSwap: (val & parseInt(PERMISSION_SWAP, 16)) !== 0,
          canProvideLiquidity:
            (val & parseInt(PERMISSION_LIQUIDITY, 16)) !== 0,
        });
      } else {
        setFlags({ raw: null, canSwap: false, canProvideLiquidity: false });
      }
    } catch {
      setFlags({ raw: null, canSwap: false, canProvideLiquidity: false });
    } finally {
      setLoading(false);
    }
  }, [account]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, POLL_INTERVAL);
    return () => clearInterval(id);
  }, [refresh]);

  return { ...flags, loading, refresh };
}
