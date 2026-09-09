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

  // Find the demo broker (prime under acme — the one with short TTL)
  const demoBroker = tree?.children
    .flatMap((issuer) => issuer.children)
    .find((broker) => broker.label === "prime" && broker.state);

  const allBrokers = tree?.children.flatMap((issuer) => issuer.children) ?? [];

  return (
    <div className="space-y-6">
      {/* Page header */}
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center justify-between"
      >
        <div>
          <h1
            className="font-display text-2xl font-semibold tracking-tight md:text-3xl"
            style={{ color: "#F5F0E8" }}
          >
            Issuer Dashboard
          </h1>
          <p className="text-sm text-stone-400">
            Pool overview and broker management
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={refresh}
          disabled={loading}
          className="text-stone-500"
        >
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <RefreshCw className="h-4 w-4" />
          )}
        </Button>
      </motion.div>

      {/* Hero countdown for demo broker */}
      {demoBroker && (
        <ExpiryCountdown expiry={demoBroker.state?.expiry} variant="hero" />
      )}

      {/* Pool stats */}
      {tree && <PoolStatus tree={tree} />}

      {/* Error */}
      {error && (
        <div className="glass-card border-red-500/30 text-sm text-red-400">
          {error}
        </div>
      )}

      {/* Loading */}
      {loading && !tree && (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-canopy-400" />
        </div>
      )}

      {/* Brokers section */}
      {tree && (
        <div>
          <div className="mb-4 flex items-center justify-between">
            <h2
              className="font-display text-lg font-semibold"
              style={{ color: "#F5F0E8" }}
            >
              Brokers
            </h2>
          </div>
          <ScrollArea className="max-h-[600px]">
            <div className="space-y-3">
              {allBrokers.map((broker) => (
                <BrokerRow key={broker.fullName} broker={broker} />
              ))}
              {allBrokers.length === 0 && (
                <p className="py-8 text-center text-sm text-stone-500">
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
