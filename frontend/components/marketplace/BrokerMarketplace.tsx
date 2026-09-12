"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { Store, Loader2 } from "lucide-react";
import { usePrivy } from "@privy-io/react-auth";
import { BrokerCard } from "./BrokerCard";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { useBrokerTerms } from "@/hooks/useBrokerTerms";
import { hierarchyConfig } from "@/lib/hierarchy";
import { encodeSubmitApplication } from "@/lib/application";
import { type BrokerTerms } from "@/lib/broker-marketplace";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

const issuers = hierarchyConfig.issuers.map((i) => i.label);

export function BrokerMarketplace() {
  const [selectedIssuer, setSelectedIssuer] = useState(issuers[0]);
  const { brokers, loading, now } = useBrokerTerms(selectedIssuer);
  const { sendTransaction, authenticated, login } = usePrivy();
  const router = useRouter();
  const [applying, setApplying] = useState<string | null>(null);

  async function handleApply(broker: BrokerTerms, tier: 0 | 1) {
    if (!authenticated) {
      login();
      return;
    }

    const label = window.prompt(
      `Choose your subname label under ${broker.ensName}:`,
      ""
    );
    if (!label) return;

    setApplying(`${broker.label}-${tier}`);
    try {
      const tx = encodeSubmitApplication(broker.registry, label, tier);
      const receipt = await sendTransaction({
        to: tx.to,
        data: tx.data,
        value: tx.value,
      });
      toast.success("Application submitted!", {
        description: `${label}.${broker.ensName} — Tx: ${receipt.hash.slice(0, 18)}...`,
      });
      router.push("/dashboard/cre");
    } catch (err) {
      toast.error("Application failed", {
        description:
          err instanceof Error ? err.message : "Transaction reverted",
      });
    } finally {
      setApplying(null);
    }
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <Store className="h-5 w-5 text-[#FFFBB8]" />
          <div>
            <h2 className="font-display text-xl font-semibold text-[#F5F0E8] sm:text-2xl">
              Broker Marketplace
            </h2>
            <p className="text-xs text-[#F5F0E8]/30 sm:text-sm">
              Compare brokers and choose your compliance tradeoff
            </p>
          </div>
        </div>

        {/* Issuer switcher */}
        <div className="flex rounded-xl border border-[#FFFBB8]/[0.08] bg-[#FFFBB8]/[0.03] p-1">
          {issuers.map((label) => (
            <button
              key={label}
              onClick={() => setSelectedIssuer(label)}
              className={cn(
                "rounded-lg px-4 py-1.5 text-xs font-medium capitalize transition-all sm:text-sm",
                selectedIssuer === label
                  ? "bg-[#FFFBB8]/15 text-[#FFFBB8]"
                  : "text-[#F5F0E8]/30 hover:text-[#F5F0E8]/60"
              )}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {/* Info banner */}
      <GlassCard className="!p-4" hover={false}>
        <p className="text-xs leading-relaxed text-[#F5F0E8]/30 sm:text-sm">
          Brokers compete for investors by offering different terms. Eligibility
          criteria are confidential, but their consequences are public — expiry
          length, tier ceiling, investor count. Choose the broker whose tradeoffs
          match your needs.
        </p>
      </GlassCard>

      {/* Broker grid */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-6 w-6 animate-spin text-[#FFFBB8]/40" />
        </div>
      ) : brokers.length === 0 ? (
        <GlassCard hover={false} className="text-center !py-12">
          <p className="text-sm text-[#F5F0E8]/20">
            No brokers found for {selectedIssuer}.canopy.eth
          </p>
        </GlassCard>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          <AnimatePresence mode="popLayout">
            {brokers.map((broker) => (
              <motion.div
                key={`${broker.issuerLabel}-${broker.label}`}
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -16 }}
                transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
              >
                <BrokerCard broker={broker} now={now} onApply={handleApply} />
                {(applying === `${broker.label}-0` ||
                  applying === `${broker.label}-1`) && (
                  <div className="mt-2 flex items-center justify-center gap-2 text-xs text-[#FFFBB8]">
                    <Loader2 className="h-3 w-3 animate-spin" />
                    Submitting application...
                  </div>
                )}
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      )}
    </div>
  );
}
