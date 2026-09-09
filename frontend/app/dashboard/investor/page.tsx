"use client";

import { motion } from "framer-motion";
import { Loader2 } from "lucide-react";
import { usePrivy } from "@privy-io/react-auth";
import { type Address } from "viem";
import { useRole } from "@/hooks/useRole";
import { useHierarchy } from "@/hooks/use-hierarchy";
import { useEligibility } from "@/hooks/use-eligibility";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { ExpiryCountdown } from "@/components/dashboard/ExpiryCountdown";
import { RoleBadges, RoleBadge } from "@/components/dashboard/RoleBadge";
import { SwapPanel } from "@/components/actions/SwapPanel";
import { LiquidityPanel } from "@/components/actions/LiquidityPanel";
import { cn } from "@/lib/utils";

export default function InvestorDashboard() {
  const { user } = usePrivy();
  const address = user?.wallet?.address as Address | undefined;
  const { issuerName, brokerName, investorName } = useRole();
  const { tree, loading } = useHierarchy();
  const eligibility = useEligibility(address);

  // Find the investor's broker
  const broker = tree?.children
    .find((i) => i.label === issuerName)
    ?.children.find((b) => b.label === brokerName);

  // Find the investor node
  const investor = broker?.children.find((i) => i.label === investorName);

  const alive = investor?.isAlive && broker?.isAlive;
  const fullName = investorName
    ? `${investorName}.${brokerName}.${issuerName}.canopy.eth`
    : "Loading...";

  const isSwapOnly = eligibility.canSwap && !eligibility.canProvideLiquidity;

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
          Investor Dashboard
        </h1>
      </motion.div>

      {loading && !tree ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-canopy-400" />
        </div>
      ) : (
        <>
          {/* Identity & Status Card */}
          <GlassCard
            className={cn(
              "!p-6",
              alive === false && "border-red-500/30"
            )}
          >
            <div className="flex items-center justify-between">
              <div>
                <p className="font-mono text-sm" style={{ color: "#F5F0E8" }}>
                  {fullName}
                </p>
                <div className="mt-2 flex items-center gap-2">
                  <span className="text-xs text-stone-500">Tier:</span>
                  {investor ? (
                    <RoleBadges
                      swap={investor.swap}
                      liquidity={investor.liquidity}
                      alive={alive ?? false}
                    />
                  ) : eligibility.canSwap || eligibility.canProvideLiquidity ? (
                    <RoleBadges
                      swap={eligibility.canSwap}
                      liquidity={eligibility.canProvideLiquidity}
                      alive={true}
                    />
                  ) : (
                    <RoleBadge role="pending" />
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span
                  className={cn(
                    "flex items-center gap-1.5 text-sm font-medium",
                    alive ? "text-canopy-400" : "text-red-400"
                  )}
                >
                  <span
                    className={cn(
                      "h-2 w-2 rounded-full",
                      alive ? "bg-canopy-400" : "bg-red-400"
                    )}
                  />
                  {alive ? "ELIGIBLE" : "ACCESS REVOKED"}
                </span>
              </div>
            </div>

            {broker && (
              <div className="mt-4 flex items-center gap-2 text-xs text-stone-500">
                <span>
                  Broker: {broker.fullName} (expires in{" "}
                  <ExpiryCountdown
                    expiry={broker.state?.expiry}
                    variant="inline"
                  />
                  )
                </span>
              </div>
            )}

            {alive === false && (
              <p className="mt-3 text-sm text-red-400/80">
                ACCESS REVOKED — your broker&apos;s license has expired
              </p>
            )}
          </GlassCard>

          {/* Action Panels */}
          <div className="grid gap-6 md:grid-cols-2">
            <SwapPanel
              disabled={!alive || !eligibility.canSwap}
              disabledReason={
                !alive ? "Access revoked" : "No SWAP permission"
              }
            />
            <LiquidityPanel
              disabled={!alive || !eligibility.canProvideLiquidity}
              disabledReason={
                !alive
                  ? "Access revoked"
                  : isSwapOnly
                    ? "Requires LIQUIDITY tier"
                    : "No LIQUIDITY permission"
              }
            />
          </div>
        </>
      )}
    </div>
  );
}
