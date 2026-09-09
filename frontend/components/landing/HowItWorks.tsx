"use client";

import { motion } from "framer-motion";
import {
  TreePine,
  ArrowLeftRight,
  Shield,
  Clock,
  Layers,
  Lock,
  Zap,
  Users,
} from "lucide-react";

const features = [
  {
    icon: TreePine,
    title: "ENS Hierarchy",
    description:
      "Platform → Issuer → Broker → Investor. One name tree governs the entire compliance chain.",
  },
  {
    icon: ArrowLeftRight,
    title: "Permissioned Pools",
    description:
      "Every swap and liquidity action checks eligibility by walking the name tree in real time.",
  },
  {
    icon: Shield,
    title: "Confidential KYC",
    description:
      "Identity checks run inside a TEE. Only the verdict is published on-chain — never the data.",
  },
  {
    icon: Clock,
    title: "Expiry Cascades",
    description:
      "When a broker's name lapses, every investor beneath it loses access instantly. No revocation tx needed.",
  },
  {
    icon: Layers,
    title: "Tiered Access",
    description:
      "Two tiers: retail investors get swap-only, market makers get swap + liquidity provision.",
  },
  {
    icon: Lock,
    title: "Zero Admin Keys",
    description:
      "No multisig. No admin. Compliance state lives entirely in the ENS registry — immutable and verifiable.",
  },
  {
    icon: Zap,
    title: "Uniswap v4 Hooks",
    description:
      "Custom hook checks allowlist on every pool interaction. Seamless integration with the v4 singleton.",
  },
  {
    icon: Users,
    title: "Multi-Issuer",
    description:
      "Multiple issuers operate under one platform. Each manages their own brokers and investor books independently.",
  },
];

export const HowItWorks = () => (
  <section className="mx-auto max-w-7xl px-4 py-24 sm:px-6 md:px-10">
    <motion.h2
      initial={{ y: 20, opacity: 0 }}
      whileInView={{ y: 0, opacity: 1 }}
      viewport={{ once: true }}
      transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
      className="mb-4 text-center font-display text-3xl font-semibold tracking-tight text-[#F5F0E8] md:text-4xl"
    >
      How it works
    </motion.h2>
    <motion.p
      initial={{ y: 16, opacity: 0 }}
      whileInView={{ y: 0, opacity: 1 }}
      viewport={{ once: true }}
      transition={{ duration: 0.6, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
      className="mx-auto mb-14 max-w-xl text-center text-sm leading-relaxed text-stone-500 md:text-base"
    >
      Three protocols. One compliance layer. No admin keys.
    </motion.p>

    <div className="grid grid-cols-1 gap-px overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.04] sm:grid-cols-2 lg:grid-cols-4">
      {features.map((feature, i) => (
        <motion.div
          key={feature.title}
          initial={{ y: 24, opacity: 0 }}
          whileInView={{ y: 0, opacity: 1 }}
          viewport={{ once: true }}
          transition={{
            duration: 0.5,
            delay: i * 0.06,
            ease: [0.16, 1, 0.3, 1],
          }}
          className="group relative border border-white/[0.04] bg-[#0a0a0a] p-6 transition-colors hover:bg-[#111]"
        >
          <feature.icon
            className="mb-5 h-5 w-5 text-stone-500 transition-colors group-hover:text-canopy-400"
            strokeWidth={1.5}
          />
          <h3 className="mb-2 text-sm font-semibold text-[#F5F0E8] md:text-base">
            {feature.title}
          </h3>
          <p className="text-xs leading-relaxed text-stone-500 md:text-sm">
            {feature.description}
          </p>
        </motion.div>
      ))}
    </div>
  </section>
);
