"use client";

import { motion } from "framer-motion";
import { RefreshCw, Loader2 } from "lucide-react";
import { useHierarchy } from "@/hooks/use-hierarchy";
import { PoolStatus } from "@/components/dashboard/PoolStatus";
import { BrokerRow } from "@/components/dashboard/BrokerRow";
import { ExpiryCountdown } from "@/components/dashboard/ExpiryCountdown";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";

export default function IssuerDashboard() {
  const { tree, loading, error, refresh } = useHierarchy();

  const demoBroker = tree?.children
    .flatMap((issuer) => issuer.children)
    .find((broker) => broker.label === "prime" && broker.state);

  const allBrokers = tree?.children.flatMap((issuer) => issuer.children) ?? [];

  return (
    <div className="space-y-8">
      {/* Page header */}
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center justify-between"
      >
        <div>
          <h1 className="font-display text-2xl font-semibold tracking-tight text-[#F5F0E8] md:text-3xl">
            Issuer Dashboard
          </h1>
          <p className="mt-1 text-sm text-[#F5F0E8]/30">
            Pool overview and broker management
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={refresh}
          disabled={loading}
          className="text-[#F5F0E8]/30 hover:text-[#FFFBB8] hover:bg-[#FFFBB8]/10"
        >
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <RefreshCw className="h-4 w-4" />
          )}
        </Button>
      </motion.div>

      {/* Hero countdown */}
      {demoBroker && (
        <ExpiryCountdown expiry={demoBroker.state?.expiry} variant="hero" />
      )}

      {/* Pool stats */}
      {tree && <PoolStatus tree={tree} />}

      {error && (
        <div className="rounded-2xl border border-red-500/20 bg-red-500/5 p-4 text-sm text-red-400">
          {error}
        </div>
      )}

      {loading && !tree && (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-[#FFFBB8]/40" />
        </div>
      )}

      {/* Brokers section */}
      {tree && (
        <div>
          <div className="mb-4">
            <h2 className="font-display text-lg font-semibold text-[#F5F0E8]">
              Brokers
            </h2>
          </div>
          <ScrollArea className="max-h-[600px]">
            <div className="space-y-3">
              {allBrokers.map((broker) => (
                <BrokerRow key={broker.fullName} broker={broker} />
              ))}
              {allBrokers.length === 0 && (
                <p className="py-8 text-center text-sm text-[#F5F0E8]/20">
                  No brokers registered
                </p>
              )}
            </div>
          </ScrollArea>
        </div>
      )}
    </div>
  );
}
