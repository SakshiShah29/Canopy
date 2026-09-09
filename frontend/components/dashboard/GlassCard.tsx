"use client";

import { cn } from "@/lib/utils";

interface GlassCardProps {
  children: React.ReactNode;
  className?: string;
  hover?: boolean;
}

export function GlassCard({
  children,
  className,
  hover = true,
}: GlassCardProps) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.05] to-white/[0.02] p-6 backdrop-blur-[24px] transition-all duration-300",
        hover && "hover:border-white/[0.12] hover:from-white/[0.07] hover:to-white/[0.03]",
        className
      )}
    >
      {children}
    </div>
  );
}
