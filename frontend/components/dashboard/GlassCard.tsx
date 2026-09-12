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
        "rounded-2xl border border-[#FFFBB8]/[0.08] bg-gradient-to-br from-[#FFFBB8]/[0.04] to-[#1a1710]/80 p-6 backdrop-blur-[24px] transition-all duration-300",
        hover &&
          "hover:border-[#FFFBB8]/[0.15] hover:from-[#FFFBB8]/[0.07] hover:to-[#1a1710]/90 hover:shadow-[0_0_40px_rgba(255,251,184,0.04)]",
        className
      )}
    >
      {children}
    </div>
  );
}
