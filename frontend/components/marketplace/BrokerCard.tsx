"use client";

import { Clock, Users, Shield, Layers, ArrowRight } from "lucide-react";
import { GlassCard } from "@/components/dashboard/GlassCard";
import { Button } from "@/components/ui/button";
import {
  formatTimeRemaining,
  getUrgency,
  type BrokerTerms,
  type UrgencyLevel,
} from "@/lib/broker-marketplace";
import { cn } from "@/lib/utils";

const urgencyConfig: Record<
  UrgencyLevel,
  { label: string; className: string; dotClass: string }
> = {
  stable: {
    label: "STABLE",
    className: "bg-[#FFFBB8]/10 text-[#FFFBB8] border-[#FFFBB8]/20",
    dotClass: "bg-[#FFFBB8]",
  },
  "expiring-soon": {
    label: "EXPIRING SOON",
    className: "bg-amber-300/10 text-amber-300 border-amber-300/20",
    dotClass: "bg-amber-300",
  },
  critical: {
    label: "EXPIRING",
    className: "bg-red-400/10 text-red-400 border-red-400/20 animate-pulse",
    dotClass: "bg-red-400",
  },
  expired: {
    label: "EXPIRED",
    className: "bg-[#F5F0E8]/5 text-[#F5F0E8]/30 border-[#F5F0E8]/10",
    dotClass: "bg-[#F5F0E8]/30",
  },
};

interface BrokerCardProps {
  broker: BrokerTerms;
  now: number;
  onApply: (broker: BrokerTerms, tier: 0 | 1) => void;
}

export function BrokerCard({ broker, now, onApply }: BrokerCardProps) {
  const urgency = getUrgency(broker.expiry, now);
  const config = urgencyConfig[urgency];
  const timeLeft = formatTimeRemaining(broker.expiry, now);
  const isExpired = urgency === "expired";
  const shortPolicy = broker.policyHash
    ? `${broker.policyHash.slice(0, 10)}...${broker.policyHash.slice(-8)}`
    : null;

  return (
    <GlassCard
      className={cn(
        "relative flex flex-col gap-5",
        isExpired && "opacity-50"
      )}
      hover={!isExpired}
    >
      {/* Header */}
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="truncate font-mono text-sm font-semibold text-[#F5F0E8] md:text-base">
            {broker.ensName}
          </h3>
          <p className="mt-0.5 text-xs text-[#F5F0E8]/20">
            under {broker.issuerLabel}.canopy.eth
          </p>
        </div>
        <span
          className={cn(
            "inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
            config.className
          )}
        >
          <span className={cn("h-1.5 w-1.5 rounded-full", config.dotClass)} />
          {config.label}
        </span>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-3">
        <div className="flex items-center gap-2 text-xs text-[#F5F0E8]/30">
          <Clock className="h-3.5 w-3.5 shrink-0" />
          <span>
            {isExpired ? (
              "Expired"
            ) : (
              <>
                Expires in{" "}
                <span className="font-mono font-medium text-[#FFFBB8]">
                  {timeLeft}
                </span>
              </>
            )}
          </span>
        </div>

        <div className="flex items-center gap-2 text-xs text-[#F5F0E8]/30">
          <Users className="h-3.5 w-3.5 shrink-0" />
          <span>
            <span className="font-mono font-medium text-[#F5F0E8]">
              {broker.investorCount}
            </span>{" "}
            investor{broker.investorCount !== 1 ? "s" : ""}
          </span>
        </div>

        <div className="flex items-center gap-2 text-xs text-[#F5F0E8]/30">
          <Layers className="h-3.5 w-3.5 shrink-0" />
          <span className="text-[#F5F0E8]">
            {broker.supportsMM ? "Retail + MM" : "Retail only"}
          </span>
        </div>

        <div className="flex items-center gap-2 text-xs text-[#F5F0E8]/30">
          <Shield className="h-3.5 w-3.5 shrink-0" />
          <span className="truncate">
            {shortPolicy ? (
              <span className="font-mono text-[#FFFBB8]/50">{shortPolicy}</span>
            ) : (
              <span className="italic text-[#F5F0E8]/15">No published policy</span>
            )}
          </span>
        </div>
      </div>

      {/* Apply buttons */}
      <div className="flex items-center gap-2 pt-1">
        <Button
          size="sm"
          disabled={isExpired}
          onClick={() => onApply(broker, 0)}
          className="flex-1 bg-[#FFFBB8] text-[#1a1710] font-semibold hover:bg-[#FFFBB8]/90 text-xs disabled:opacity-30"
        >
          Apply as Retail
          <ArrowRight className="ml-1.5 h-3 w-3" />
        </Button>
        {broker.supportsMM && (
          <Button
            size="sm"
            disabled={isExpired}
            onClick={() => onApply(broker, 1)}
            variant="outline"
            className="flex-1 border-[#FFFBB8]/20 text-[#FFFBB8] hover:bg-[#FFFBB8]/10 text-xs disabled:opacity-30"
          >
            Apply as MM
            <ArrowRight className="ml-1.5 h-3 w-3" />
          </Button>
        )}
      </div>
    </GlassCard>
  );
}
