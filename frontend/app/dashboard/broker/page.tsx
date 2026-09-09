"use client";

import { motion } from "framer-motion";
import { Loader2 } from "lucide-react";
import { useRole } from "@/hooks/useRole";
import { useHierarchy } from "@/hooks/use-hierarchy";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { ExpiryCountdown } from "@/components/dashboard/ExpiryCountdown";
import { InvestorRow } from "@/components/dashboard/InvestorRow";
import { ScrollArea } from "@/components/ui/scroll-area";

export default function BrokerDashboard() {
  const { issuerName, brokerName } = useRole();
  const { tree, loading } = useHierarchy();

  // Find this broker in the tree
  const broker = tree?.children
    .find((i) => i.label === issuerName)
    ?.children.find((b) => b.label === brokerName);

  const fullName = broker?.fullName ?? `${brokerName}.${issuerName}.canopy.eth`;

  return (
    <div className="space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
      >
        <h1
          className="font-display text-2xl font-semibold tracking-tight md:text-3xl"
          style={{ color: "#F5F0E8" }}
        >
          Broker Dashboard
        </h1>
      </motion.div>

      {loading && !tree ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-canopy-400" />
        </div>
      ) : (
        <>
          {/* Broker Identity Card */}
          <GlassCard className="!p-8">
            <p className="font-mono text-sm text-stone-400">{fullName}</p>
            {issuerName && (
              <p className="mt-1 text-xs text-stone-500">
                Issuer: {issuerName}.canopy.eth
              </p>
            )}
            <div className="mt-6">
              <p className="mb-3 text-xs font-medium uppercase tracking-wider text-stone-500">
                YOUR LICENSE EXPIRES IN
              </p>
              <ExpiryCountdown
                expiry={broker?.state?.expiry}
                variant="large"
              />
            </div>
          </GlassCard>

          {/* Investors */}
          {broker && broker.children.length > 0 && (
            <div>
              <h2
                className="mb-4 font-display text-lg font-semibold"
                style={{ color: "#F5F0E8" }}
              >
                Active Investors
              </h2>
              <ScrollArea className="max-h-[400px]">
                <div className="space-y-2">
                  {broker.children.map((investor) => (
                    <InvestorRow
                      key={investor.fullName}
                      investor={investor}
                      brokerAlive={broker.isAlive}
                    />
                  ))}
                </div>
              </ScrollArea>
            </div>
          )}
        </>
      )}
    </div>
  );
}
