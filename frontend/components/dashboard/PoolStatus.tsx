"use client";

import { useEffect, useState } from "react";
import { Activity, Users, Briefcase } from "lucide-react";
import { GlassCard } from "./GlassCard";
import { publicClient } from "@/lib/client";
import { addresses, PermissionsAdapterAbi } from "@/lib/contracts";
import { type NodeState } from "@/lib/ensv2";

interface PoolStatusProps {
  tree: NodeState;
}

export function PoolStatus({ tree }: PoolStatusProps) {
  const [swappingEnabled, setSwappingEnabled] = useState<boolean | null>(null);

  useEffect(() => {
    publicClient
      .readContract({
        address: addresses.permissionsAdapter,
        abi: PermissionsAdapterAbi,
        functionName: "swappingEnabled",
      })
      .then((r) => setSwappingEnabled(r as boolean))
      .catch(() => setSwappingEnabled(null));
  }, []);

  // Count brokers and investors
  const allBrokers = tree.children.flatMap((i) => i.children);
  const activeBrokers = allBrokers.filter((b) => b.isAlive);
  const expiringBrokers = allBrokers.filter((b) => {
    if (!b.state?.expiry || !b.isAlive) return false;
    const remaining = Number(b.state.expiry) - Math.floor(Date.now() / 1000);
    return remaining < 86400 * 7;
  });

  const allInvestors = allBrokers.flatMap((b) => b.children);
  const swapInvestors = allInvestors.filter((i) => i.swap && !i.liquidity);
  const mmInvestors = allInvestors.filter((i) => i.liquidity);

  return (
    <div className="grid gap-4 sm:grid-cols-3">
      <GlassCard>
        <Activity className="mb-3 h-5 w-5 text-canopy-400" />
        <p className="text-xs font-medium uppercase tracking-wider text-stone-500">
          Pool Status
        </p>
        <p className="mt-1 text-2xl font-bold" style={{ color: "#F5F0E8" }}>
          {swappingEnabled === null
            ? "..."
            : swappingEnabled
              ? "LIVE"
              : "PAUSED"}
        </p>
        <p className="mt-1 truncate font-mono text-[10px] text-stone-600">
          {addresses.permissionsAdapter}
        </p>
      </GlassCard>

      <GlassCard>
        <Briefcase className="mb-3 h-5 w-5 text-blue-400" />
        <p className="text-xs font-medium uppercase tracking-wider text-stone-500">
          Active Brokers
        </p>
        <p className="mt-1 text-2xl font-bold" style={{ color: "#F5F0E8" }}>
          {activeBrokers.length}
        </p>
        {expiringBrokers.length > 0 && (
          <p className="mt-1 text-xs text-amber-400">
            {expiringBrokers.length} expiring soon
          </p>
        )}
      </GlassCard>

      <GlassCard>
        <Users className="mb-3 h-5 w-5 text-purple-400" />
        <p className="text-xs font-medium uppercase tracking-wider text-stone-500">
          Total Investors
        </p>
        <p className="mt-1 text-2xl font-bold" style={{ color: "#F5F0E8" }}>
          {allInvestors.length}
        </p>
        <p className="mt-1 text-xs text-stone-500">
          {swapInvestors.length} swap &middot; {mmInvestors.length} MM
        </p>
      </GlassCard>
    </div>
  );
}
