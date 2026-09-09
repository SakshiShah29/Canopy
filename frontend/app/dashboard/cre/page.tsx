"use client";

import { motion } from "framer-motion";
import { TerminalView } from "@/components/cre/TerminalView";

export default function CRETerminalPage() {
  return (
    <div className="space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
      >
        <h1
          className="font-display text-2xl font-semibold tracking-tight md:text-3xl"
          style={{ color: "#F5F0E8" }}
        >
          CRE Terminal
        </h1>
        <p className="text-sm text-stone-400">
          Watch the Chainlink CRE confidential workflow execute in real time
        </p>
      </motion.div>

      <TerminalView />
    </div>
  );
}
