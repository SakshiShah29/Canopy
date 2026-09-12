"use client";

import { useState, useEffect, useCallback } from "react";
import {
  getAllBrokerTerms,
  type BrokerTerms,
} from "@/lib/broker-marketplace";

/**
 * Hook that polls broker terms every 5s and ticks a client-side clock every 1s
 * for smooth countdown display between polls.
 */
export function useBrokerTerms(issuerLabel: string) {
  const [brokers, setBrokers] = useState<BrokerTerms[]>([]);
  const [loading, setLoading] = useState(true);
  const [now, setNow] = useState(Math.floor(Date.now() / 1000));

  const fetchBrokers = useCallback(async () => {
    if (!issuerLabel) return;
    try {
      const terms = await getAllBrokerTerms(issuerLabel);
      setBrokers(terms);
    } catch (err) {
      console.error("Failed to fetch broker terms:", err);
    } finally {
      setLoading(false);
    }
  }, [issuerLabel]);

  // Poll on-chain data every 5s
  useEffect(() => {
    fetchBrokers();
    const interval = setInterval(fetchBrokers, 5000);
    return () => clearInterval(interval);
  }, [fetchBrokers]);

  // Client-side 1s tick for smooth countdown
  useEffect(() => {
    const tick = setInterval(
      () => setNow(Math.floor(Date.now() / 1000)),
      1000
    );
    return () => clearInterval(tick);
  }, []);

  return { brokers, loading, now };
}
