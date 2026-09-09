"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Send, Loader2 } from "lucide-react";
import { usePrivy } from "@privy-io/react-auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { encodeSubmitApplication } from "@/lib/application";
import { hierarchyConfig } from "@/lib/hierarchy";
import { toast } from "sonner";

export function ApplicationForm() {
  const { sendTransaction, authenticated } = usePrivy();
  const router = useRouter();
  const [issuer, setIssuer] = useState("");
  const [broker, setBroker] = useState("");
  const [label, setLabel] = useState("");
  const [tier, setTier] = useState("0");
  const [pending, setPending] = useState(false);

  const selectedIssuer = hierarchyConfig.issuers.find((i) => i.label === issuer);
  const brokers = selectedIssuer?.brokers ?? [];

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!authenticated || !broker || !label) return;

    setPending(true);
    try {
      const tx = encodeSubmitApplication(
        broker as `0x${string}`,
        label,
        parseInt(tier)
      );
      const receipt = await sendTransaction({
        to: tx.to,
        data: tx.data,
        value: tx.value,
      });
      toast.success("Application submitted!", {
        description: `Tx: ${receipt.hash.slice(0, 18)}...`,
      });
      // Redirect to CRE terminal to watch the workflow
      router.push("/dashboard/cre");
    } catch (err) {
      toast.error("Application failed", {
        description: err instanceof Error ? err.message : "Transaction reverted",
      });
    } finally {
      setPending(false);
    }
  }

  return (
    <GlassCard className="mx-auto max-w-lg !p-8">
      <h2
        className="mb-6 text-center font-display text-2xl font-semibold"
        style={{ color: "#F5F0E8" }}
      >
        Apply for Pool Access
      </h2>

      <form onSubmit={handleSubmit} className="space-y-5">
        <div>
          <label className="mb-1.5 block text-xs font-medium uppercase tracking-wider text-stone-500">
            Select Issuer
          </label>
          <Select value={issuer} onValueChange={(v) => setIssuer(v ?? "")}>
            <SelectTrigger className="border-white/[0.08] bg-white/[0.04]">
              <SelectValue placeholder="Choose issuer..." />
            </SelectTrigger>
            <SelectContent>
              {hierarchyConfig.issuers.map((i) => (
                <SelectItem key={i.label} value={i.label}>
                  {i.label}.canopy.eth
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium uppercase tracking-wider text-stone-500">
            Select Broker
          </label>
          <Select
            value={broker}
            onValueChange={(v) => setBroker(v ?? "")}
            disabled={!issuer}
          >
            <SelectTrigger className="border-white/[0.08] bg-white/[0.04]">
              <SelectValue placeholder="Choose broker..." />
            </SelectTrigger>
            <SelectContent>
              {brokers.map((b) => (
                <SelectItem key={b.label} value={b.label}>
                  {b.label}.{issuer}.canopy.eth
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium uppercase tracking-wider text-stone-500">
            Requested Tier
          </label>
          <div className="space-y-2">
            <label className="flex items-center gap-3 rounded-lg border border-white/[0.08] bg-white/[0.02] p-3 cursor-pointer transition-colors hover:border-white/[0.12]">
              <input
                type="radio"
                name="tier"
                value="0"
                checked={tier === "0"}
                onChange={() => setTier("0")}
                className="accent-canopy-500"
              />
              <div>
                <p className="text-sm font-medium" style={{ color: "#F5F0E8" }}>
                  Retail (swap only)
                </p>
              </div>
            </label>
            <label className="flex items-center gap-3 rounded-lg border border-white/[0.08] bg-white/[0.02] p-3 cursor-pointer transition-colors hover:border-white/[0.12]">
              <input
                type="radio"
                name="tier"
                value="1"
                checked={tier === "1"}
                onChange={() => setTier("1")}
                className="accent-canopy-500"
              />
              <div>
                <p className="text-sm font-medium" style={{ color: "#F5F0E8" }}>
                  Market Maker (swap + liquidity)
                </p>
              </div>
            </label>
          </div>
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium uppercase tracking-wider text-stone-500">
            Preferred Label
          </label>
          <Input
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            placeholder="alice"
            className="border-white/[0.08] bg-white/[0.04] font-mono"
          />
          {label && issuer && broker && (
            <p className="mt-1.5 text-xs text-stone-500">
              Will register: {label}.{broker}.{issuer}.canopy.eth
            </p>
          )}
        </div>

        <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-xs text-stone-500 leading-relaxed">
          Your KYC data will be processed inside a Chainlink CRE trusted
          execution environment. No personal information is stored on-chain.
          Only the verdict (approved/rejected) is published.
        </div>

        <Button
          type="submit"
          disabled={!authenticated || !broker || !label || pending}
          className="w-full bg-canopy-500 text-black hover:bg-canopy-500/90"
        >
          {pending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Processing...
            </>
          ) : (
            <>
              <Send className="mr-2 h-4 w-4" />
              Submit Application
            </>
          )}
        </Button>
      </form>
    </GlassCard>
  );
}
