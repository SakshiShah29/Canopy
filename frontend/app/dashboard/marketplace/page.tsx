"use client";

import { motion } from "framer-motion";
import { BrokerMarketplace } from "@/components/marketplace/BrokerMarketplace";

export default function MarketplacePage() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
      className="py-8"
    >
      <BrokerMarketplace />
    </motion.div>
  );
}
