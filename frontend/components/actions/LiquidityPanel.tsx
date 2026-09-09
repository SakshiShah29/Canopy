"use client";

import { useState } from "react";
import { Droplets, Loader2 } from "lucide-react";
import { usePrivy } from "@privy-io/react-auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { buildAddLiquidityTx } from "@/lib/uniswap";
import { toast } from "sonner";

interface LiquidityPanelProps {
  disabled?: boolean;
  disabledReason?: string;
}

export function LiquidityPanel({ disabled, disabledReason }: LiquidityPanelProps) {
  const { sendTransaction, authenticated } = usePrivy();
  const [amount, setAmount] = useState("");
  const [pending, setPending] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!authenticated || !amount || disabled) return;

    setPending(true);
    try {
      const tx = buildAddLiquidityTx(amount);
      const receipt = await sendTransaction({
        to: tx.to,
        data: tx.data,
        value: tx.value,
      });
      toast.success("Liquidity added", {
        description: receipt.hash.slice(0, 18) + "...",
      });
    } catch (err) {
      toast.error("Add liquidity failed", {
        description: err instanceof Error ? err.message : "Transaction reverted",
      });
    } finally {
      setPending(false);
    }
  }

  return (
    <GlassCard
      className={disabled ? "opacity-50" : ""}
      hover={!disabled}
    >
      <h3 className="mb-4 flex items-center gap-2 text-lg font-semibold" style={{ color: "#F5F0E8" }}>
        <Droplets className="h-5 w-5 text-blue-400" />
        Add Liquidity
      </h3>

      <form onSubmit={handleAdd} className="space-y-4">
        <div>
          <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-stone-500">
            ETH Amount
          </label>
          <Input
            type="number"
            step="0.001"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.1"
            className="border-white/[0.08] bg-white/[0.04] font-mono"
            disabled={disabled}
          />
        </div>

        <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-xs text-stone-500 space-y-1">
          <p>Pool: ETH / Canopy Token (via PermissionsAdapter)</p>
          <p>Fee: 0.3% | Tick spacing: 60</p>
          {disabled && (
            <p className="text-amber-400 font-medium">
              Requires LIQUIDITY tier
            </p>
          )}
        </div>

        <Button
          type="submit"
          disabled={!authenticated || !amount || pending || disabled}
          className="w-full bg-blue-500 text-white hover:bg-blue-500/90"
        >
          {pending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Adding Liquidity...
            </>
          ) : disabled ? (
            disabledReason ?? "Insufficient Tier"
          ) : (
            <>
              <Droplets className="mr-2 h-4 w-4" />
              Add Liquidity
            </>
          )}
        </Button>
      </form>
    </GlassCard>
  );
}
