"use client";

import { useCountdown } from "@/hooks/use-countdown";
import { cn } from "@/lib/utils";

interface ExpiryCountdownProps {
  expiry: bigint | undefined;
  variant?: "hero" | "inline" | "large";
}

export function ExpiryCountdown({
  expiry,
  variant = "inline",
}: ExpiryCountdownProps) {
  const cd = useCountdown(expiry);

  if (variant === "large") {
    // Huge countdown for broker identity card — text-4xl/5xl JetBrains Mono bold
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
              <span className="mx-1 text-2xl text-stone-600 md:mx-2 md:text-3xl">:</span>
            )}
            <span
              className={cn(
                "text-4xl md:text-5xl",
                cd.isExpired
                  ? "text-red-400"
                  : cd.isCritical
                    ? "text-red-400 animate-pulse"
                    : cd.totalSeconds < 86400 * 7
                      ? "text-amber-400"
                      : "text-canopy-400"
              )}
            >
              {seg.val.toString().padStart(2, "0")}
            </span>
            <span className="ml-0.5 text-xs text-stone-500 md:text-sm">{seg.label}</span>
          </div>
        ))}
      </div>
    );
  }

  if (variant === "hero") {
    // Hero banner style on dashboard
    return (
      <div
        className={cn(
          "glass-card relative overflow-hidden",
          cd.isExpired
            ? "border-red-500/30"
            : cd.isCritical
              ? "border-red-500/50 animate-glow-pulse"
              : ""
        )}
      >
        <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wider text-stone-500 mb-3">
          {cd.isExpired ? "EXPIRED" : "TIME REMAINING"}
        </div>
        <div
          className={cn(
            "font-mono text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl",
            cd.isExpired
              ? "text-red-400"
              : cd.isCritical
                ? "text-red-400"
                : cd.totalSeconds < 86400 * 7
                  ? "text-amber-400"
                  : "text-canopy-400"
          )}
        >
          {cd.formatted}
        </div>
        {cd.totalSeconds > 0 && cd.totalSeconds < 300 && (
          <p className="mt-2 text-sm text-red-400/80">
            Broker expiry imminent — investor eligibility will cascade
          </p>
        )}
      </div>
    );
  }

  // Inline: small monospace countdown for table rows
  return (
    <span
      className={cn(
        "font-mono text-xs font-bold tabular-nums tracking-[0.02em]",
        cd.isExpired
          ? "text-red-400"
          : cd.isCritical
            ? "text-red-400 animate-pulse"
            : cd.totalSeconds < 86400 * 7
              ? "text-amber-400"
              : "text-canopy-400"
      )}
    >
      {cd.formatted}
    </span>
  );
}
