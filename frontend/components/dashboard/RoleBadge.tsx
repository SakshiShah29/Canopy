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
    bg: "bg-[#FFFBB8]/15",
    text: "text-[#FFFBB8]",
    border: "border-[#FFFBB8]/25",
    icon: ArrowLeftRight,
    label: "SWAP",
  },
  liquidity: {
    bg: "bg-amber-300/15",
    text: "text-amber-300",
    border: "border-amber-300/25",
    icon: Droplets,
    label: "LIQUIDITY",
  },
  expired: {
    bg: "bg-red-500/15",
    text: "text-red-400",
    border: "border-red-500/25",
    icon: XCircle,
    label: "EXPIRED",
  },
  pending: {
    bg: "bg-[#F5F0E8]/10",
    text: "text-[#F5F0E8]/50",
    border: "border-[#F5F0E8]/15",
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
        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
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
