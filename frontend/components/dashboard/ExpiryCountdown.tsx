"use client";

import { useCountdown } from "@/hooks/use-countdown";
import { cn } from "@/lib/utils";

interface ExpiryCountdownProps {
  expiry: bigint | undefined;
  variant?: "hero" | "inline" | "large";
}

function countdownColor(cd: { isExpired: boolean; isCritical: boolean; totalSeconds: number }) {
  if (cd.isExpired) return "text-red-400";
  if (cd.isCritical) return "text-red-400 animate-pulse";
  if (cd.totalSeconds < 86400 * 7) return "text-amber-300";
  return "text-[#FFFBB8]";
}

export function ExpiryCountdown({
  expiry,
  variant = "inline",
}: ExpiryCountdownProps) {
  const cd = useCountdown(expiry);

  if (variant === "large") {
    return (
      <div className="flex items-baseline gap-1 font-mono font-bold tracking-[0.02em]">
        {[
          { val: cd.days, label: "D" },
          { val: cd.hours, label: "H" },
          { val: cd.minutes, label: "M" },
          { val: cd.seconds, label: "S" },
        ].map((seg, i) => (
          <div key={seg.label} className="flex items-baseline">
            {i > 0 && (
              <span className="mx-1 text-2xl text-[#FFFBB8]/20 md:mx-2 md:text-3xl">:</span>
            )}
            <span
              className={cn("text-4xl md:text-5xl", countdownColor(cd))}
            >
              {seg.val.toString().padStart(2, "0")}
            </span>
            <span className="ml-0.5 text-xs text-[#F5F0E8]/30 md:text-sm">
              {seg.label}
            </span>
          </div>
        ))}
      </div>
    );
  }

  if (variant === "hero") {
    return (
      <div
        className={cn(
          "relative overflow-hidden rounded-2xl border border-[#FFFBB8]/[0.08] bg-gradient-to-br from-[#FFFBB8]/[0.04] to-[#1a1710]/80 p-6 backdrop-blur-[24px]",
          cd.isExpired
            ? "border-red-500/30"
            : cd.isCritical
              ? "border-red-500/50 animate-glow-pulse"
              : ""
        )}
      >
        <div className="mb-3 flex items-center gap-2 text-xs font-medium uppercase tracking-[0.15em] text-[#F5F0E8]/40">
          {cd.isExpired ? "EXPIRED" : "TIME REMAINING"}
        </div>
        <div
          className={cn(
            "font-mono text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl",
            countdownColor(cd)
          )}
        >
          {cd.formatted}
        </div>
        {cd.totalSeconds > 0 && cd.totalSeconds < 300 && (
          <p className="mt-3 text-sm text-red-400/80">
            Broker expiry imminent — investor eligibility will cascade
          </p>
        )}
      </div>
    );
  }

  // Inline
  return (
    <span
      className={cn(
        "font-mono text-xs font-bold tabular-nums tracking-[0.02em]",
        countdownColor(cd)
      )}
    >
      {cd.formatted}
    </span>
  );
}
