"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { ArrowDownUp, CheckCircle, XCircle, Loader2 } from "lucide-react";
import { usePrivy } from "@privy-io/react-auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { buildSwapTx } from "@/lib/uniswap";
import { toast } from "sonner";

interface SwapPanelProps {
  disabled?: boolean;
  disabledReason?: string;
}

export function SwapPanel({ disabled, disabledReason }: SwapPanelProps) {
  const { sendTransaction, authenticated } = usePrivy();
  const [amount, setAmount] = useState("");
  const [zeroForOne, setZeroForOne] = useState(true);
  const [pending, setPending] = useState(false);

  async function handleSwap(e: React.FormEvent) {
    e.preventDefault();
    if (!authenticated || !amount || disabled) return;

    setPending(true);
    try {
      const tx = buildSwapTx(amount, zeroForOne);
      const receipt = await sendTransaction({
        to: tx.to,
        data: tx.data,
        value: tx.value,
      });
      toast.success("Swap successful", {
        description: receipt.hash.slice(0, 18) + "...",
      });
    } catch (err) {
      toast.error("Swap failed", {
        description: err instanceof Error ? err.message : "Transaction reverted",
      });
    } finally {
      setPending(false);
    }
  }

  return (
    <GlassCard
      className={disabled ? "opacity-50 pointer-events-none" : ""}
      hover={!disabled}
    >
      <h3 className="mb-4 flex items-center gap-2 text-lg font-semibold" style={{ color: "#F5F0E8" }}>
        <ArrowDownUp className="h-5 w-5 text-canopy-400" />
        Swap
      </h3>

      <form onSubmit={handleSwap} className="space-y-4">
        <div>
          <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-stone-500">
            {zeroForOne ? "ETH Amount" : "Token Amount"}
          </label>
          <Input
            type="number"
            step="0.001"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.01"
            className="border-white/[0.08] bg-white/[0.04] font-mono"
          />
        </div>

        <button
          type="button"
          onClick={() => setZeroForOne(!zeroForOne)}
          className="mx-auto flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] transition-colors hover:bg-white/[0.06]"
        >
          <ArrowDownUp className="h-4 w-4 text-stone-500" />
        </button>

        <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-center text-sm text-stone-400">
          {zeroForOne ? "ETH → Canopy Token" : "Canopy Token → ETH"}
        </div>

        <Button
          type="submit"
          disabled={!authenticated || !amount || pending || disabled}
          className="w-full bg-canopy-500 text-black hover:bg-canopy-500/90"
        >
          {pending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Swapping...
            </>
          ) : disabled ? (
            disabledReason ?? "Insufficient Tier"
          ) : (
            "Execute Swap"
          )}
        </Button>
      </form>
    </GlassCard>
  );
}
