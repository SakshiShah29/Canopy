"use client";

import { useState } from "react";
import { ArrowDownUp, Loader2 } from "lucide-react";
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
      <h3 className="mb-4 flex items-center gap-2 font-display text-lg font-semibold text-[#F5F0E8]">
        <ArrowDownUp className="h-5 w-5 text-[#FFFBB8]" />
        Swap
      </h3>

      <form onSubmit={handleSwap} className="space-y-4">
        <div>
          <label className="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.15em] text-[#F5F0E8]/30">
            {zeroForOne ? "ETH Amount" : "Token Amount"}
          </label>
          <Input
            type="number"
            step="0.001"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.01"
            className="border-[#FFFBB8]/[0.08] bg-[#FFFBB8]/[0.03] font-mono text-[#F5F0E8] placeholder:text-[#F5F0E8]/20"
          />
        </div>

        <button
          type="button"
          onClick={() => setZeroForOne(!zeroForOne)}
          className="mx-auto flex h-8 w-8 items-center justify-center rounded-full border border-[#FFFBB8]/[0.1] transition-colors hover:bg-[#FFFBB8]/[0.06]"
        >
          <ArrowDownUp className="h-4 w-4 text-[#F5F0E8]/30" />
        </button>

        <div className="rounded-xl border border-[#FFFBB8]/[0.06] bg-[#FFFBB8]/[0.02] p-3 text-center text-sm text-[#F5F0E8]/40">
          {zeroForOne ? "ETH → Canopy Token" : "Canopy Token → ETH"}
        </div>

        <Button
          type="submit"
          disabled={!authenticated || !amount || pending || disabled}
          className="w-full bg-[#FFFBB8] text-[#1a1710] font-semibold hover:bg-[#FFFBB8]/90 disabled:opacity-40"
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
