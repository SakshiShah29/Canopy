"use client";

import { type NodeState } from "@/lib/ensv2";
import { RoleBadges } from "./RoleBadge";

interface InvestorRowProps {
  investor: NodeState;
  brokerAlive: boolean;
}

export function InvestorRow({ investor, brokerAlive }: InvestorRowProps) {
  const alive = investor.isAlive && brokerAlive;

  return (
    <div className="flex items-center justify-between rounded-xl border border-white/[0.06] bg-white/[0.02] px-4 py-3 transition-all hover:border-white/[0.10]">
      <div className="flex items-center gap-3">
        {/* Status dot */}
        <span
          className={`h-2 w-2 rounded-full ${alive ? "bg-canopy-400" : "bg-red-400"}`}
        />
        <div>
          <p className="font-mono text-sm" style={{ color: "#F5F0E8" }}>
            {investor.fullName}
          </p>
          {investor.state?.latestOwner &&
            investor.state.latestOwner !==
              "0x0000000000000000000000000000000000000000" && (
              <p className="font-mono text-[10px] text-stone-500">
                {investor.state.latestOwner.slice(0, 6)}...
                {investor.state.latestOwner.slice(-4)}
              </p>
            )}
        </div>
      </div>

      <div className="flex items-center gap-3">
        <RoleBadges
          swap={investor.swap}
          liquidity={investor.liquidity}
          alive={alive}
        />
      </div>
    </div>
  );
}
