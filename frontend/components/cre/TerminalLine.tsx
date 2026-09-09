"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

export interface TerminalLineData {
  timestamp: string;
  text: string;
  type?: "normal" | "success" | "error" | "warning" | "muted" | "confidential";
  indent?: number;
  prefix?: string;
}

interface TerminalLineProps {
  line: TerminalLineData;
  index: number;
}

const typeStyles: Record<string, string> = {
  normal: "text-stone-300",
  success: "text-canopy-400",
  error: "text-red-400",
  warning: "text-amber-400",
  muted: "text-stone-600",
  confidential: "text-stone-600",
};

export function TerminalLine({ line, index }: TerminalLineProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 5 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        duration: 0.3,
        delay: index * 0.2,
        ease: [0.16, 1, 0.3, 1],
      }}
      className="flex gap-2 font-mono text-sm leading-relaxed"
    >
      {line.timestamp && (
        <span className="shrink-0 text-stone-600">[{line.timestamp}]</span>
      )}
      {line.prefix && (
        <span className="shrink-0 text-stone-500">{line.prefix}</span>
      )}
      <span
        className={cn(typeStyles[line.type ?? "normal"])}
        style={{ paddingLeft: (line.indent ?? 0) * 16 }}
      >
        {line.text}
      </span>
    </motion.div>
  );
}
