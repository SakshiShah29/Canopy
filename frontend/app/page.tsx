"use client";

import { CanopyHero } from "@/components/landing/CanopyHero";
import { HowItWorks } from "@/components/landing/HowItWorks";
import { Sponsors } from "@/components/landing/Sponsors";
import { Footer } from "@/components/landing/Footer";

export default function Home() {
  return (
    <main className="min-h-screen bg-[#050505]">
      <CanopyHero />
      <HowItWorks />
      <Sponsors />
      <Footer />
    </main>
  );
}
