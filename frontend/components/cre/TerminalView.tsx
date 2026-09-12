"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { ScrollArea } from "@/components/ui/scroll-area";
import { TerminalLine, type TerminalLineData } from "./TerminalLine";

function getTimeStr(): string {
  const d = new Date();
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}:${d.getSeconds().toString().padStart(2, "0")}`;
}

function buildLines(): TerminalLineData[] {
  const t = getTimeStr;
  return [
    { timestamp: "", text: "$ cre workflow simulate eligibility --broadcast", type: "normal" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Application received", prefix: "", type: "normal" },
    { timestamp: "", text: "applicationId: 0xa3f2...89b1", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "wallet: 0xAbC1...DeF4", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "issuer: acme.canopy.eth", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "broker: prime", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "requestedTier: retail (swap only)", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Entering TEE enclave (AWS Nitro, us-west-2)", type: "normal" },
    { timestamp: "", text: "\u250C\u2500\u2500\u2500 CONFIDENTIAL BOUNDARY \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502", indent: 2, type: "confidential" },
    { timestamp: t(), text: "\u2502 \uD83D\uDD10 Fetching secrets...", indent: 2, type: "normal" },
    { timestamp: "", text: "\u2502    KYC_API_TOKEN         \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588 (hidden)", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502    ELIGIBILITY_RULEBOOK  \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588 (hidden)", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502", indent: 2, type: "confidential" },
    { timestamp: t(), text: "\u2502 \uD83C\uDF10 Calling KYC endpoint...", indent: 2, type: "normal" },
    { timestamp: "", text: "\u2502    POST https://kyc-api.mock/verify", indent: 2, type: "muted" },
    { timestamp: "", text: "\u2502    Status: 200 OK", indent: 2, type: "success" },
    { timestamp: "", text: "\u2502    Response: \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588 (protected)", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502", indent: 2, type: "confidential" },
    { timestamp: t(), text: "\u2502 \uD83D\uDCCA Evaluating eligibility...", indent: 2, type: "normal" },
    { timestamp: "", text: "\u2502    Criteria:  \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588 (protected)", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502    Score:     \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588 (protected)", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2502    Decision:  \u2705 APPROVED", indent: 2, type: "success" },
    { timestamp: "", text: "\u2502", indent: 2, type: "confidential" },
    { timestamp: "", text: "\u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518", indent: 2, type: "confidential" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Crossing back via usingTheDons()", type: "normal" },
    { timestamp: "", text: "\u26A0 Everything past this point is PUBLIC", indent: 1, type: "warning" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Verdict (public):", type: "normal" },
    { timestamp: "", text: "wallet:       0xAbC1...DeF4", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "label:        alice", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "broker:       prime.acme.canopy.eth", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "roleBitmap:   0x0000...0001 (SWAP_ALLOWED)", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "expiry:       2026-09-12T00:00:00Z", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "approved:     true", indent: 2, type: "success", prefix: "" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Writing DON-signed report...", type: "normal" },
    { timestamp: "", text: "\u2192 MintAttestor (0x5B9E...bCF)", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "txHash: 0x91af...c3b2", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: t(), text: "\u25B8 Subname minted \u2713", type: "success" },
    { timestamp: "", text: "alice.prime.acme.canopy.eth", indent: 2, type: "success", prefix: "" },
    { timestamp: "", text: "Roles: ELIGIBLE_SWAP (1<<64)", indent: 2, type: "muted", prefix: "" },
    { timestamp: "", text: "", type: "normal" },
    { timestamp: "", text: "\u2705 Workflow complete", type: "success" },
  ];
}

export function TerminalView() {
  const [visibleCount, setVisibleCount] = useState(0);
  const [lines] = useState(() => buildLines());

  useEffect(() => {
    if (visibleCount >= lines.length) return;
    const timer = setTimeout(
      () => setVisibleCount((c) => c + 1),
      visibleCount === 0 ? 500 : 200
    );
    return () => clearTimeout(timer);
  }, [visibleCount, lines.length]);

  return (
    <div className="overflow-hidden rounded-2xl border border-[#FFFBB8]/[0.08]">
      {/* Terminal chrome */}
      <div className="flex items-center gap-2 border-b border-[#FFFBB8]/[0.06] bg-[#0e0d08] px-4 py-3">
        <span className="h-3 w-3 rounded-full bg-red-500/80" />
        <span className="h-3 w-3 rounded-full bg-amber-400/80" />
        <span className="h-3 w-3 rounded-full bg-[#FFFBB8]/60" />
        <span className="ml-4 text-xs text-[#F5F0E8]/30">
          Canopy CRE &middot; Confidential Workflow
        </span>
      </div>

      {/* Terminal body */}
      <ScrollArea className="h-[600px] bg-[#0e0d08] p-6">
        <div className="space-y-1">
          {lines.slice(0, visibleCount).map((line, i) => (
            <TerminalLine key={i} line={line} index={i} />
          ))}
          {visibleCount < lines.length && (
            <span className="inline-block h-4 w-2 bg-[#FFFBB8] animate-caret" />
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
