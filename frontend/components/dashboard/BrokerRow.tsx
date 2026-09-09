"use client";

import { useState } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";
import { type NodeState } from "@/lib/ensv2";
import { ExpiryCountdown } from "./ExpiryCountdown";
import { InvestorRow } from "./InvestorRow";
import { Progress } from "@/components/ui/progress";
import { cn } from "@/lib/utils";

interface BrokerRowProps {
  broker: NodeState;
}

export function BrokerRow({ broker }: BrokerRowProps) {
  const [expanded, setExpanded] = useState(false);

  const investors = broker.children;
  const retailCount = investors.filter((i) => i.swap && !i.liquidity).length;
  const mmCount = investors.filter((i) => i.liquidity).length;

  // Compute progress percentage (how much time has elapsed)
  const expiry = broker.state?.expiry ? Number(broker.state.expiry) : 0;
  const now = Math.floor(Date.now() / 1000);
  const remaining = Math.max(0, expiry - now);
  // Assume max TTL is 365 days for the bar
  const maxTTL = 365 * 86400;
  const progressPct = expiry > 0 ? Math.min(100, (remaining / maxTTL) * 100) : 0;

  const statusColor = !broker.isAlive
    ? "bg-red-400"
    : remaining < 86400 * 7
      ? "bg-amber-400"
      : "bg-canopy-400";

  return (
    <div className="glass-card !p-0 overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex w-full items-center justify-between p-5 text-left transition-colors hover:bg-white/[0.02]"
      >
        <div className="flex items-center gap-3">
          <span className={cn("h-2.5 w-2.5 rounded-full", statusColor)} />
          <div>
            <p className="font-mono text-sm font-medium" style={{ color: "#F5F0E8" }}>
              {broker.fullName}
            </p>
            <p className="mt-0.5 text-xs text-stone-500">
              Investors: {investors.length} ({retailCount} retail
              {mmCount > 0 && `, ${mmCount} MM`})
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          {/* Progress bar */}
          <div className="hidden w-32 sm:block">
            <Progress
              value={progressPct}
              className="h-1.5 bg-white/[0.06]"
            />
          </div>

          {/* Countdown */}
          <ExpiryCountdown expiry={broker.state?.expiry} variant="inline" />

          {/* Expand chevron */}
          {expanded ? (
            <ChevronDown className="h-4 w-4 text-stone-500" />
          ) : (
            <ChevronRight className="h-4 w-4 text-stone-500" />
          )}
        </div>
      </button>

      {/* Expanded investor list */}
      {expanded && investors.length > 0 && (
        <div className="border-t border-white/[0.06] p-4 space-y-2">
          {investors.map((investor) => (
            <InvestorRow
              key={investor.fullName}
              investor={investor}
              brokerAlive={broker.isAlive}
            />
          ))}
        </div>
      )}
    </div>
  );
}
