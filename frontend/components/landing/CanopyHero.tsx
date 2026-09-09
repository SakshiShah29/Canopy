"use client";

import { motion, useInView } from "framer-motion";
import { ArrowRight, Play } from "lucide-react";
import { useRef } from "react";
import Link from "next/link";
import Image from "next/image";

/* ---------------- WordsPullUp (from Prisma, unchanged) ---------------- */
interface WordsPullUpProps {
  text: string;
  className?: string;
  showAsterisk?: boolean;
  style?: React.CSSProperties;
}

export const WordsPullUp = ({
  text,
  className = "",
  showAsterisk = false,
  style,
}: WordsPullUpProps) => {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true });
  const words = text.split(" ");

  return (
    <div ref={ref} className={`inline-flex flex-wrap ${className}`} style={style}>
      {words.map((word, i) => {
        const isLast = i === words.length - 1;
        return (
          <motion.span
            key={i}
            initial={{ y: 20, opacity: 0 }}
            animate={isInView ? { y: 0, opacity: 1 } : {}}
            transition={{
              duration: 0.6,
              delay: i * 0.08,
              ease: [0.16, 1, 0.3, 1],
            }}
            className="inline-block relative"
            style={{ marginRight: isLast ? 0 : "0.25em" }}
          >
            {word}
            {showAsterisk && isLast && (
              <span className="absolute top-[0.65em] -right-[0.3em] text-[0.31em]">
                *
              </span>
            )}
          </motion.span>
        );
      })}
    </div>
  );
};

/* ---------------- Nav items ---------------- */
const navItems = [
  { label: "Docs", href: "#" },
  { label: "Explorer", href: "/dashboard/explorer" },
  { label: "GitHub", href: "https://github.com/SakshiShah29/Canopy" },
];

/* ---------------- Hero ---------------- */
const CanopyHero = () => {
  return (
    <section className="h-screen w-full">
      <div className="relative h-full w-full overflow-hidden rounded-2xl md:rounded-[2rem]">

        {/* Background video */}
        <video
          autoPlay
          loop
          muted
          playsInline
          className="absolute inset-0 h-full w-full object-cover"
          src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260405_170732_8a9ccda6-5cff-4628-b164-059c500a2b41.mp4"
        />

        {/* Noise overlay */}
        <div className="noise-overlay pointer-events-none absolute inset-0 opacity-[0.7] mix-blend-overlay" />

        {/* Gradient overlay */}
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/30 via-transparent to-black/60" />

        {/* Navbar */}
        <nav className="absolute left-1/2 top-0 z-20 -translate-x-1/2">
          <div className="flex items-center gap-3 rounded-b-2xl bg-black px-5 py-3 sm:gap-6 md:gap-12 md:rounded-b-3xl md:px-8 md:py-4 lg:gap-14">
            <Link href="/" className="flex items-center">
              <Image src="/name.png" alt="Canopy" width={200} height={60} className="h-8 w-auto sm:h-10 md:h-10" />
            </Link>
            {navItems.map((item) => (
              <Link
                key={item.label}
                href={item.href}
                className="text-[10px] transition-colors sm:text-xs md:text-sm"
                style={{ color: "rgba(245, 240, 232, 0.8)" }}
                onMouseEnter={(e) =>
                  (e.currentTarget.style.color = "#F5F0E8")
                }
                onMouseLeave={(e) =>
                  (e.currentTarget.style.color = "rgba(245, 240, 232, 0.8)")
                }
              >
                {item.label}
              </Link>
            ))}
          </div>
        </nav>

        {/* Hero content */}
        <div className="absolute bottom-0 left-0 right-0 px-4 pb-2 sm:px-6 md:px-10">
          <div className="grid grid-cols-12 items-end gap-4">

            {/* Left: huge title */}
            <div className="col-span-12 lg:col-span-8">
              <h1
                className="font-display font-medium leading-[0.85] tracking-[-0.07em] pb-[0.3em] text-[22vw] sm:text-[20vw] md:text-[18vw] lg:text-[16vw] xl:text-[15vw] 2xl:text-[16vw]"
                style={{ color: "#F5F0E8" }}
              >
                <WordsPullUp text="Canopy" showAsterisk />
              </h1>
            </div>

            {/* Right: description + CTAs */}
            <div className="col-span-12 flex flex-col gap-5 pb-6 lg:col-span-4 lg:pb-10">

              <motion.p
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{
                  duration: 0.8,
                  delay: 0.5,
                  ease: [0.16, 1, 0.3, 1],
                }}
                className="text-xs sm:text-sm md:text-base"
                style={{ lineHeight: 1.2, color: "rgba(245, 240, 232, 0.7)" }}
              >
                Hierarchical compliance for permissioned pools.
                One name expires — the whole book goes dark.
                No revocation transactions. No admin. Just ENS.
              </motion.p>

              {/* Two CTAs side by side */}
              <motion.div
                initial={{ y: 20, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{
                  duration: 0.8,
                  delay: 0.7,
                  ease: [0.16, 1, 0.3, 1],
                }}
                className="flex items-center gap-3"
              >
                {/* Primary CTA — pastel yellow */}
                <Link
                  href="/dashboard"
                  className="group inline-flex items-center gap-2 rounded-full py-1 pl-5 pr-1 text-sm font-medium text-black transition-all hover:gap-3 sm:text-base"
                  style={{ backgroundColor: "#FFFBB8" }}
                >
                  Launch App
                  <span className="flex h-9 w-9 items-center justify-center rounded-full bg-black transition-transform group-hover:scale-110 sm:h-10 sm:w-10">
                    <ArrowRight
                      className="h-4 w-4"
                      style={{ color: "#F5F0E8" }}
                    />
                  </span>
                </Link>

                {/* Ghost CTA — watch demo */}
                <a
                  href="#demo"
                  className="group inline-flex items-center gap-2 rounded-full border py-1 pl-5 pr-1 text-sm font-medium transition-all hover:gap-3 sm:text-base"
                  style={{
                    borderColor: "rgba(245, 240, 232, 0.3)",
                    color: "#F5F0E8",
                  }}
                >
                  Watch Demo
                  <span
                    className="flex h-9 w-9 items-center justify-center rounded-full transition-transform group-hover:scale-110 sm:h-10 sm:w-10"
                    style={{ backgroundColor: "rgba(245, 240, 232, 0.1)" }}
                  >
                    <Play
                      className="h-4 w-4"
                      style={{ color: "#F5F0E8" }}
                    />
                  </span>
                </a>
              </motion.div>

            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export { CanopyHero };
