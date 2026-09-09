"use client";

import { useEffect, useState } from "react";

export interface CountdownState {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
  totalSeconds: number;
  isExpired: boolean;
  isCritical: boolean; // < 60 seconds remaining
  formatted: string;
}

export function useCountdown(expiryUnix: bigint | undefined): CountdownState {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));

  useEffect(() => {
    const id = setInterval(() => {
      setNow(Math.floor(Date.now() / 1000));
    }, 1000);
    return () => clearInterval(id);
  }, []);

  if (!expiryUnix) {
    return {
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0,
      totalSeconds: 0,
      isExpired: true,
      isCritical: false,
      formatted: "--:--:--",
    };
  }

  const expiry = Number(expiryUnix);
  const remaining = Math.max(0, expiry - now);

  const days = Math.floor(remaining / 86400);
  const hours = Math.floor((remaining % 86400) / 3600);
  const minutes = Math.floor((remaining % 3600) / 60);
  const seconds = remaining % 60;

  const pad = (n: number) => n.toString().padStart(2, "0");

  let formatted: string;
  if (days > 0) {
    formatted = `${days}d ${pad(hours)}h ${pad(minutes)}m ${pad(seconds)}s`;
  } else {
    formatted = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
  }

  return {
    days,
    hours,
    minutes,
    seconds,
    totalSeconds: remaining,
    isExpired: remaining === 0,
    isCritical: remaining > 0 && remaining < 60,
    formatted,
  };
}
