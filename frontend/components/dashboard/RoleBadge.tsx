"use client";

import {
  ArrowLeftRight,
  Droplets,
  XCircle,
  Timer,
} from "lucide-react";
import { cn } from "@/lib/utils";

type RoleType = "swap" | "liquidity" | "expired" | "pending";

const config: Record<
  RoleType,
  { bg: string; text: string; border: string; icon: typeof ArrowLeftRight; label: string }
> = {
  swap: {
    bg: "bg-canopy-400/20",
    text: "text-canopy-400",
    border: "border-canopy-400/30",
    icon: ArrowLeftRight,
    label: "SWAP",
  },
  liquidity: {
    bg: "bg-blue-400/20",
    text: "text-blue-400",
    border: "border-blue-400/30",
    icon: Droplets,
    label: "LIQUIDITY",
  },
  expired: {
    bg: "bg-red-500/20",
    text: "text-red-400",
    border: "border-red-500/30",
    icon: XCircle,
    label: "EXPIRED",
  },
  pending: {
    bg: "bg-amber-400/20",
    text: "text-amber-400",
    border: "border-amber-400/30",
    icon: Timer,
    label: "PENDING",
  },
};

interface RoleBadgeProps {
  role: RoleType;
  className?: string;
}

export function RoleBadge({ role, className }: RoleBadgeProps) {
  const c = config[role];
  const Icon = c.icon;
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-semibold uppercase tracking-wider",
        c.bg,
        c.text,
        c.border,
        className
      )}
    >
      <Icon className="h-3 w-3" />
      {c.label}
    </span>
  );
}

/** Convenience: show appropriate badges given swap/liquidity/alive booleans */
export function RoleBadges({
  swap,
  liquidity,
  alive,
}: {
  swap: boolean;
  liquidity: boolean;
  alive: boolean;
}) {
  if (!alive) return <RoleBadge role="expired" />;
  return (
    <div className="flex items-center gap-1.5">
      {swap && <RoleBadge role="swap" />}
      {liquidity && <RoleBadge role="liquidity" />}
    </div>
  );
}
