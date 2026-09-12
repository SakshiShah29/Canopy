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

  const expiry = broker.state?.expiry ? Number(broker.state.expiry) : 0;
  const now = Math.floor(Date.now() / 1000);
  const remaining = Math.max(0, expiry - now);
  const maxTTL = 365 * 86400;
  const progressPct = expiry > 0 ? Math.min(100, (remaining / maxTTL) * 100) : 0;

  const statusColor = !broker.isAlive
    ? "bg-red-400"
    : remaining < 86400 * 7
      ? "bg-amber-300"
      : "bg-[#FFFBB8]";

  return (
    <div className="overflow-hidden rounded-2xl border border-[#FFFBB8]/[0.08] bg-gradient-to-br from-[#FFFBB8]/[0.04] to-[#1a1710]/80 backdrop-blur-[24px] transition-all duration-300 hover:border-[#FFFBB8]/[0.15]">
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex w-full items-center justify-between p-5 text-left transition-colors hover:bg-[#FFFBB8]/[0.02]"
      >
        <div className="flex items-center gap-3">
          <span className={cn("h-2.5 w-2.5 rounded-full", statusColor)} />
          <div>
            <p className="font-mono text-sm font-medium text-[#F5F0E8]">
              {broker.fullName}
            </p>
            <p className="mt-0.5 text-xs text-[#F5F0E8]/30">
              {investors.length} investor{investors.length !== 1 ? "s" : ""} ({retailCount} retail
              {mmCount > 0 && `, ${mmCount} MM`})
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          <div className="hidden w-32 sm:block">
            <Progress
              value={progressPct}
              className="h-1.5 bg-[#FFFBB8]/[0.06]"
            />
          </div>

          <ExpiryCountdown expiry={broker.state?.expiry} variant="inline" />

          {expanded ? (
            <ChevronDown className="h-4 w-4 text-[#F5F0E8]/30" />
          ) : (
            <ChevronRight className="h-4 w-4 text-[#F5F0E8]/30" />
          )}
        </div>
      </button>

      {expanded && investors.length > 0 && (
        <div className="border-t border-[#FFFBB8]/[0.06] p-4 space-y-2">
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
