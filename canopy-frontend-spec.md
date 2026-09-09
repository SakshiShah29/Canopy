# Canopy — Frontend Specification

## Table of Contents

1. Design System
2. Tech Stack & Dependencies
3. Landing Page
4. Dashboard Shell & Role Detection
5. Issuer Dashboard
6. Broker Dashboard
7. Investor Dashboard
8. Apply View
9. CRE Terminal Page
10. Explorer Page
11. Shared Components
12. 3D Video & Asset Sources
13. Logo Generation Prompt
14. Cover Image / OG Image Generation Prompt
15. Presentation Slide Prompts

---

## 1. Design System

### Color Tokens

```css
:root {
  /* Backgrounds */
  --bg-root: #050505;
  --bg-surface: rgba(255, 255, 255, 0.03);
  --bg-surface-hover: rgba(255, 255, 255, 0.06);
  --bg-glass: rgba(255, 255, 255, 0.04);
  --bg-glass-border: rgba(255, 255, 255, 0.08);
  --bg-glass-hover: rgba(255, 255, 255, 0.07);

  /* Primary — Emerald (the canopy) */
  --primary-50: #ECFDF5;
  --primary-100: #D1FAE5;
  --primary-200: #A7F3D0;
  --primary-300: #6EE7B7;
  --primary-400: #34D399;
  --primary-500: #10B981;
  --primary-600: #059669;
  --primary-700: #047857;
  --primary-800: #065F46;
  --primary-900: #064E3B;

  /* Secondary — Amber (warmth, expiry warning) */
  --amber-50: #FFFBEB;
  --amber-300: #FCD34D;
  --amber-400: #FBBF24;
  --amber-500: #F59E0B;
  --amber-600: #D97706;

  /* Danger — Red (expired, reverted) */
  --danger-400: #F87171;
  --danger-500: #EF4444;
  --danger-600: #DC2626;

  /* Text */
  --text-primary: #F5F0E8;       /* warm cream — never pure white */
  --text-secondary: #A8A29E;     /* stone-400 */
  --text-muted: #78716C;         /* stone-500 */
  --text-inverse: #050505;

  /* Borders */
  --border-subtle: rgba(255, 255, 255, 0.06);
  --border-default: rgba(255, 255, 255, 0.10);
  --border-focus: var(--primary-500);

  /* Role badge colors */
  --badge-swap: #34D399;          /* emerald-400 */
  --badge-liquidity: #60A5FA;     /* blue-400 */
  --badge-expired: #EF4444;       /* red-500 */
  --badge-pending: #FBBF24;       /* amber-400 */
}
```

### Tailwind Config Overrides

```js
// tailwind.config.ts
module.exports = {
  theme: {
    extend: {
      colors: {
        canopy: {
          50: '#ECFDF5', 100: '#D1FAE5', 200: '#A7F3D0',
          300: '#6EE7B7', 400: '#34D399', 500: '#10B981',
          600: '#059669', 700: '#047857', 800: '#065F46',
          900: '#064E3B',
        },
        cream: '#F5F0E8',
        surface: 'rgba(255, 255, 255, 0.03)',
      },
      fontFamily: {
        display: ['Fraunces', 'serif'],
        body: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      backdropBlur: {
        glass: '24px',
      },
      backgroundImage: {
        'glass-gradient': 'linear-gradient(135deg, rgba(255,255,255,0.05), rgba(255,255,255,0.02))',
      },
    },
  },
}
```

### Typography Scale

| Use | Font | Weight | Size | Tracking |
|---|---|---|---|---|
| Hero headline | Fraunces | 700 (Bold) | `text-6xl` / `text-7xl` on desktop | `-0.02em` |
| Section heading | Fraunces | 600 (SemiBold) | `text-3xl` / `text-4xl` | `-0.01em` |
| Card title | Inter | 600 | `text-lg` | `0` |
| Body text | Inter | 400 | `text-sm` / `text-base` | `0` |
| Label / caption | Inter | 500 | `text-xs` | `0.05em` (uppercase) |
| Code / terminal | JetBrains Mono | 400 | `text-sm` | `0` |
| Badge | Inter | 600 | `text-xs` | `0.05em` (uppercase) |
| Countdown timer | JetBrains Mono | 700 | `text-2xl` | `0.02em` |

### Google Fonts import

```html
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;600;700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
```

### Glassmorphism Card (reused everywhere in dashboard)

```css
.glass-card {
  background: linear-gradient(135deg, rgba(255,255,255,0.05), rgba(255,255,255,0.02));
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 16px;
  padding: 24px;
}
.glass-card:hover {
  background: linear-gradient(135deg, rgba(255,255,255,0.07), rgba(255,255,255,0.03));
  border-color: rgba(255, 255, 255, 0.12);
}
```

As a Tailwind utility class composition (use this everywhere):
```
className="bg-glass-gradient backdrop-blur-glass border border-white/[0.08] rounded-2xl p-6 hover:border-white/[0.12] transition-all duration-300"
```

### Shadcn/ui Components to Install

```bash
npx shadcn@latest add button badge card tabs separator tooltip dialog
npx shadcn@latest add dropdown-menu avatar scroll-area progress
npx shadcn@latest add sonner          # toast notifications
```

Override the shadcn theme in `globals.css` to match our palette. The default shadcn dark theme uses slate — replace with our stone/cream values.

### Icon Library

Use `lucide-react` (comes with shadcn). Key icons:
- `Shield` — eligibility/access
- `TreePine` / `Network` — hierarchy
- `Timer` — expiry countdown
- `ArrowLeftRight` — swap
- `Droplets` — liquidity
- `Terminal` — CRE view
- `Eye` / `EyeOff` — confidential/visible
- `CheckCircle` / `XCircle` — approved/rejected
- `Wallet` — connect

---

## 2. Tech Stack & Dependencies

```bash
npx create-next-app@latest frontend --typescript --tailwind --app --no-src-dir
cd frontend

# Core
npm install @privy-io/react-auth viem

# UI
npx shadcn@latest init    # choose: New York style, Zinc base, CSS variables: yes
npm install framer-motion  # for page transitions and mount animations
npm install clsx tailwind-merge  # utility for className merging

# Aceternity / ReactBits (copy components, not npm packages)
# - Squiggly text: copy from https://ui.aceternity.com/components/squiggly-text
# - Noise background: copy from https://ui.aceternity.com/components/noise-background
# - Text loop: copy from https://reactbits.dev/text-animations/text-loop

# Visualization
npm install @visx/hierarchy @visx/group  # tree visualization for explorer
npm install d3-hierarchy                  # tree layout computation
```

### File Structure

```
frontend/
├── app/
│   ├── layout.tsx              # root layout: fonts, Privy provider, noise bg
│   ├── page.tsx                # landing page (public)
│   ├── dashboard/
│   │   ├── layout.tsx          # dashboard shell: sidebar + role detection
│   │   ├── page.tsx            # redirects to role-specific view
│   │   ├── issuer/
│   │   │   └── page.tsx
│   │   ├── broker/
│   │   │   └── page.tsx
│   │   ├── investor/
│   │   │   └── page.tsx
│   │   ├── apply/
│   │   │   └── page.tsx
│   │   ├── cre/
│   │   │   └── page.tsx        # CRE terminal page
│   │   └── explorer/
│   │       └── page.tsx        # hierarchy tree explorer
│   └── globals.css
├── components/
│   ├── ui/                     # shadcn components (auto-generated)
│   ├── landing/
│   │   ├── Hero.tsx
│   │   ├── HowItWorks.tsx
│   │   ├── Sponsors.tsx
│   │   └── Footer.tsx
│   ├── dashboard/
│   │   ├── Sidebar.tsx
│   │   ├── TopBar.tsx
│   │   ├── GlassCard.tsx
│   │   ├── ExpiryCountdown.tsx
│   │   ├── RoleBadge.tsx
│   │   ├── HierarchyTree.tsx
│   │   ├── BrokerRow.tsx
│   │   ├── InvestorRow.tsx
│   │   ├── PoolStatus.tsx
│   │   └── AttestationTrail.tsx
│   ├── cre/
│   │   ├── TerminalView.tsx
│   │   ├── TerminalLine.tsx
│   │   └── WorkflowStep.tsx
│   ├── actions/
│   │   ├── SwapPanel.tsx
│   │   ├── LiquidityPanel.tsx
│   │   └── ApplicationForm.tsx
│   └── shared/
│       ├── ConnectButton.tsx
│       ├── SquigglyText.tsx    # copied from aceternity
│       ├── NoiseBackground.tsx # copied from aceternity
│       └── TextLoop.tsx        # copied from reactbits
├── lib/
│   ├── canopy.ts               # contract interaction (written by Builder A)
│   ├── privy.ts                # privy config
│   ├── ensv2.ts                # ENS hierarchy reads
│   ├── role-detect.ts          # wallet → role resolution
│   ├── constants.ts            # addresses, ABIs
│   └── utils.ts
├── hooks/
│   ├── useRole.ts              # returns { role, issuerName, brokerName, investorName }
│   ├── useHierarchy.ts         # returns full tree for a given issuer
│   ├── useExpiry.ts            # countdown hook
│   └── useCREStream.ts         # streams CRE workflow events for terminal view
├── public/
│   ├── canopy-hero.mp4         # 3D nature video loop
│   ├── logo.svg
│   └── og-image.png
└── next.config.ts
```

---

## 3. Landing Page

Based on the Prisma hero component. Uses the same fullscreen video background pattern with noise overlay, gradient darkening, and bottom-aligned huge text.

### Required CSS — add to `globals.css`

```css
/* Noise overlay texture — same as Prisma reference */
.noise-overlay {
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E");
  background-repeat: repeat;
}
```

### Component: `components/landing/CanopyHero.tsx`

```tsx
"use client";

import { motion, useInView } from "framer-motion";
import { ArrowRight, Play } from "lucide-react";
import { useRef } from "react";
import Link from "next/link";

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
  { label: "GitHub", href: "https://github.com/YOUR_REPO" },
];

/* ---------------- Hero ---------------- */
const CanopyHero = () => {
  return (
    <section className="h-screen w-full">
      <div className="relative h-full w-full overflow-hidden rounded-2xl md:rounded-[2rem]">

        {/* Background video — using the Prisma cinematic footage */}
        <video
          autoPlay
          loop
          muted
          playsInline
          className="absolute inset-0 h-full w-full object-cover"
          src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260405_170732_8a9ccda6-5cff-4628-b164-059c500a2b41.mp4"
        />
        {/* Dark cinematic atmospheric video — final, no replacement needed */}

        {/* Noise overlay — same as Prisma */}
        <div className="noise-overlay pointer-events-none absolute inset-0 opacity-[0.7] mix-blend-overlay" />

        {/* Gradient overlay — darkens top and bottom for text readability */}
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/30 via-transparent to-black/60" />

        {/* Navbar — centered, drops down from top with rounded bottom */}
        <nav className="absolute left-1/2 top-0 z-20 -translate-x-1/2">
          <div className="flex items-center gap-3 rounded-b-2xl bg-black px-4 py-2 sm:gap-6 md:gap-12 md:rounded-b-3xl md:px-8 lg:gap-14">
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

        {/* Hero content — bottom-aligned, same grid as Prisma */}
        <div className="absolute bottom-0 left-0 right-0 px-4 pb-2 sm:px-6 md:px-10">
          <div className="grid grid-cols-12 items-end gap-4">

            {/* Left: huge title */}
            <div className="col-span-12 lg:col-span-8">
              <h1
                className="font-display font-medium leading-[0.85] tracking-[-0.07em] text-[22vw] sm:text-[20vw] md:text-[18vw] lg:text-[16vw] xl:text-[15vw] 2xl:text-[16vw]"
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
                {/* Primary CTA — emerald */}
                <Link
                  href="/dashboard"
                  className="group inline-flex items-center gap-2 rounded-full py-1 pl-5 pr-1 text-sm font-medium text-black transition-all hover:gap-3 sm:text-base"
                  style={{ backgroundColor: "#10B981" }}
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
```

### Page: `app/page.tsx`

```tsx
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
```

### Color mapping from Prisma → Canopy

| Element | Prisma value | Canopy value | Why |
|---|---|---|---|
| Hero text | `#E1E0CC` | `#F5F0E8` | Our cream — slightly warmer and brighter |
| Nav text | `rgba(225, 224, 204, 0.8)` | `rgba(245, 240, 232, 0.8)` | Same cream at 80% |
| Description text | `text-primary/70` | `rgba(245, 240, 232, 0.7)` | Explicit cream at 70% |
| Primary CTA bg | `bg-primary` (shadcn default) | `#10B981` | Canopy emerald |
| CTA text | `text-black` | `text-black` | Same — dark text on emerald |
| Arrow icon bg | `bg-black` | `bg-black` | Same |
| Gradient overlay | `from-black/30 via-transparent to-black/60` | Same | Unchanged |
| Noise opacity | `0.7` | `0.7` | Same |
| Font | System default | `font-display` (Fraunces) | Our display serif |

### What changed from the Prisma component

1. **Title:** `"Prisma"` → `"Canopy"`, uses `font-display` class (Fraunces)
2. **Slightly smaller text:** `text-[26vw]` → `text-[22vw]` because "Canopy" is 6 chars vs Prisma's 6 — same, but we leave room for the asterisk
3. **Description text:** their artist network blurb → our one-liner pitch
4. **Two CTAs** instead of one: "Launch App" (emerald, links to `/dashboard`) + "Watch Demo" (ghost border)
5. **Nav items:** their 5 editorial links → our 3 functional links (Docs, Explorer, GitHub)
6. **Colors:** `#E1E0CC` → `#F5F0E8` everywhere (our cream)
7. **Video src:** currently using the Prisma reference video URL — replace with your own once generated

### How It Works Section (below the hero fold)

```tsx
// components/landing/HowItWorks.tsx
"use client";

import { motion } from "framer-motion";
import { TreePine, ArrowLeftRight, Shield } from "lucide-react";

const cards = [
  {
    icon: TreePine,
    title: "Registry",
    tech: "ENSv2",
    description:
      "Stores the issuer → broker → investor hierarchy with expiry dates. When a broker's name lapses, every investor beneath it loses access instantly.",
  },
  {
    icon: ArrowLeftRight,
    title: "Trading Pool",
    tech: "Uniswap v4",
    description:
      "Before every swap or liquidity action, the pool checks eligibility by walking up the name tree. Two tiers: retail (swap only) and market maker (swap + liquidity).",
  },
  {
    icon: Shield,
    title: "KYC Engine",
    tech: "Chainlink CRE",
    description:
      "Evaluates identity checks privately inside a trusted execution environment. Only the verdict — approved or rejected — is published on-chain. The criteria and applicant data never leave the enclave.",
  },
];

export const HowItWorks = () => (
  <section className="mx-auto max-w-6xl px-4 py-24 sm:px-6 md:px-10">
    <motion.h2
      initial={{ y: 20, opacity: 0 }}
      whileInView={{ y: 0, opacity: 1 }}
      viewport={{ once: true }}
      transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
      className="mb-12 text-center font-display text-3xl font-semibold tracking-tight md:text-4xl"
      style={{ color: "#F5F0E8" }}
    >
      Three layers. One check.
    </motion.h2>

    <div className="grid gap-6 md:grid-cols-3">
      {cards.map((card, i) => (
        <motion.div
          key={card.title}
          initial={{ y: 30, opacity: 0 }}
          whileInView={{ y: 0, opacity: 1 }}
          viewport={{ once: true }}
          transition={{
            duration: 0.6,
            delay: i * 0.15,
            ease: [0.16, 1, 0.3, 1],
          }}
          className="rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.05] to-white/[0.02] p-6 backdrop-blur-[24px] transition-all duration-300 hover:border-white/[0.12]"
        >
          <card.icon className="mb-4 h-8 w-8 text-canopy-400" />
          <h3
            className="mb-1 text-lg font-semibold"
            style={{ color: "#F5F0E8" }}
          >
            {card.title}
          </h3>
          <p className="mb-3 text-xs font-medium uppercase tracking-wider text-canopy-400">
            {card.tech}
          </p>
          <p className="text-sm leading-relaxed text-stone-400">
            {card.description}
          </p>
        </motion.div>
      ))}
    </div>
  </section>
);
```

### Sponsors Strip

```tsx
// components/landing/Sponsors.tsx
export const Sponsors = () => (
  <section className="mx-auto max-w-4xl px-4 py-16 text-center">
    <p className="mb-6 text-xs font-medium uppercase tracking-widest text-stone-500">
      Built with
    </p>
    <div className="flex items-center justify-center gap-12">
      {/* Replace with actual SVG logos */}
      {["ENS", "Uniswap", "Chainlink"].map((name) => (
        <span
          key={name}
          className="text-lg font-medium text-stone-600 opacity-40 transition-opacity hover:opacity-80"
        >
          {name}
        </span>
      ))}
    </div>
  </section>
);
```

### Footer

```tsx
// components/landing/Footer.tsx
export const Footer = () => (
  <footer className="border-t border-white/[0.06] px-4 py-8 text-center">
    <p className="text-xs text-stone-500">
      Built for{" "}
      <a href="https://ethglobal.com/events/ethonline2026" className="underline hover:text-stone-400">
        ETHOnline 2026
      </a>{" "}
      ·{" "}
      <a href="https://github.com/YOUR_REPO" className="underline hover:text-stone-400">
        GitHub
      </a>
    </p>
  </footer>
);
```

### NPM dependencies for the landing page

```bash
npm install framer-motion lucide-react
```

These are already listed in the tech stack section but noting here explicitly — the landing page needs both.

---

## 4. Dashboard Shell & Role Detection

### Role Detection Logic (`lib/role-detect.ts`)

After wallet connection via Privy, query the ENS hierarchy to determine the user's role:

```typescript
async function detectRole(address: string): Promise<Role> {
  // 1. Check if address is platform admin (deployer)
  //    → compare against PLATFORM_ADMIN from constants

  // 2. Check if address owns an issuer subname (*.canopy.eth)
  //    → query IssuerRegistry.getState for each known issuer labelhash
  //    → if state.latestOwner === address → return { role: 'issuer', name: '...' }

  // 3. Check if address owns a broker subname (*.*.canopy.eth)
  //    → for each issuer, query their UserRegistry for known broker labelhashes
  //    → if state.latestOwner === address → return { role: 'broker', ... }

  // 4. Check if address owns an investor subname (*.*.*.canopy.eth)
  //    → for each broker registry, scan registered investors
  //    → if found → return { role: 'investor', ... }

  // 5. Fallback → return { role: 'applicant' } → route to Apply view
}
```

For the hackathon demo with a small set of known addresses, hardcode the lookup set in `constants.ts` from `deployments.json`. Full reverse-resolution is out of scope.

### Dashboard Layout

```
┌──────────────────────────────────────────────────────────────┐
│  TopBar: [Canopy logo]          [role badge]  [wallet avatar]│
├────────┬─────────────────────────────────────────────────────┤
│        │                                                     │
│ Side   │                                                     │
│ bar    │            Main Content Area                        │
│        │            (role-specific page)                     │
│ ────── │                                                     │
│ 📊 Dash│                                                     │
│ 🔍 Expl│                                                     │
│ 💻 CRE │                                                     │
│        │                                                     │
│        │                                                     │
│ ────── │                                                     │
│ ⚙ Set  │                                                     │
│        │                                                     │
└────────┴─────────────────────────────────────────────────────┘
```

**Sidebar** — glass card style, fixed left, 240px wide. Links:
- **Dashboard** (role-specific home)
- **Explorer** (hierarchy tree)
- **CRE Terminal** (workflow execution viewer)
- Separator
- **Settings** (wallet info, disconnect)

**TopBar** — glass card bottom border, 64px height:
- Left: Canopy logo (SVG, small)
- Center: current page title
- Right: role badge (`RoleBadge` component), wallet avatar from Privy, dropdown with disconnect

---

## 5. Issuer Dashboard

The issuer (e.g. owner of `acme.canopy.eth`) sees their entire book.

### Layout — 3 sections

**Section 1: Pool Overview (top row, 3 stat cards)**

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Pool Status     │  │  Active Brokers  │  │  Total Investors│
│  ● LIVE          │  │  2               │  │  5              │
│  0x54C7...b7     │  │  1 expiring soon │  │  3 swap · 2 MM  │
│  [glass card]    │  │  [glass card]    │  │  [glass card]   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

Each stat card: `GlassCard` with a `lucide` icon top-left, large number center, sublabel below.

**Section 2: Broker Table (main content)**

```
┌──────────────────────────────────────────────────────────────┐
│  Brokers                                          [+ Onboard]│
├──────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟢 prime.acme.canopy.eth                              │  │
│  │    Investors: 3 (2 retail, 1 MM)                      │  │
│  │    Expiry: ██████████░░ 6d 14h 22m    [countdown]     │  │
│  │    Registry: 0x8a3F...                                │  │
│  │    [Expand ▾]                                         │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟢 apex.acme.canopy.eth                               │  │
│  │    Investors: 2 (2 retail)                            │  │
│  │    Expiry: █████████████ 29d 2h 11m                   │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

Each `BrokerRow` is a glass card with:
- Status dot: green (active), amber (expiring <7d), red (expired)
- Name in `font-mono text-sm text-cream`
- Investor count with tier breakdown
- **Expiry progress bar** — shadcn `Progress` component, color shifts green → amber → red as time runs down
- **Live countdown** in `font-mono text-2xl font-bold` — the ExpiryCountdown component, ticking every second
- Expandable: click to show investor list

**Inside expanded broker — Investor Rows:**

```
│  │ ┌──────────────────────────────────────────────────┐ │  │
│  │ │ alice.prime.acme.canopy.eth                      │ │  │
│  │ │ 0xAbC1...  [SWAP]  ● Active                     │ │  │
│  │ │ Attested: workflow#a3f2... · report#8b1c...      │ │  │
│  │ └──────────────────────────────────────────────────┘ │  │
│  │ ┌──────────────────────────────────────────────────┐ │  │
│  │ │ mm.prime.acme.canopy.eth                         │ │  │
│  │ │ 0xDeF4...  [SWAP] [LIQUIDITY]  ● Active          │ │  │
│  │ │ Attested: workflow#a3f2... · report#c4e7...      │ │  │
│  │ └──────────────────────────────────────────────────┘ │  │
```

**Role badges:**
- `[SWAP]` — small pill badge, `bg-canopy-400/20 text-canopy-400 border border-canopy-400/30 font-semibold text-xs uppercase tracking-wider px-2 py-0.5 rounded-full`
- `[LIQUIDITY]` — same shape, `bg-blue-400/20 text-blue-400 border border-blue-400/30`
- `[EXPIRED]` — `bg-red-500/20 text-red-400 border border-red-500/30`

**Section 3: Recent Events (bottom)**

Glass card with a scrolling event feed. Each event:
- `SubnameRegistered` — "alice.prime.acme.canopy.eth minted · 2m ago"
- `ApplicationSubmitted` — "Application pending for 0xAbC1... · 5m ago"
- `BrokerExpired` — "prime.acme.canopy.eth expired · just now" (danger highlight)

Use shadcn `ScrollArea` with max-height `320px`.

---

## 6. Broker Dashboard

Broker sees their own investors and their own expiry.

### Layout

**Top: Broker Identity Card (wide glass card)**

```
┌──────────────────────────────────────────────────────────────┐
│  prime.acme.canopy.eth                                       │
│  Issuer: Acme Corp (acme.canopy.eth)                        │
│                                                              │
│  YOUR LICENSE EXPIRES IN                                     │
│  ██████████████░░░░░░  06 : 14 : 22 : 47                    │
│                         D     H     M     S                  │
│  [glass card, countdown in font-mono text-4xl font-bold]    │
└──────────────────────────────────────────────────────────────┘
```

The expiry countdown here is **HUGE** — `text-4xl` or `text-5xl`, JetBrains Mono, bold. This is the thing the camera lingers on in the demo video. Make it unmissable.

**Below: Investor list + Application Pipeline (two-column)**

Left column: Active investors (same `InvestorRow` component as issuer view).
Right column: Pending applications (status: submitted → CRE processing → approved/rejected).

---

## 7. Investor Dashboard

Investor sees their own status and can trade.

### Layout

**Top: Identity & Status Card**

```
┌──────────────────────────────────────────────────────────────┐
│  alice.prime.acme.canopy.eth                    ● ELIGIBLE   │
│  Tier: [SWAP]                                                │
│  Broker: prime.acme.canopy.eth (expires in 6d 14h)          │
│  Attested: workflow#a3f2... · report#8b1c...                │
│  [glass card]                                                │
└──────────────────────────────────────────────────────────────┘
```

If investor has both badges, show both. If expired, the card border turns red and shows `● ACCESS REVOKED` in danger color.

**Below: Action Panels (two columns)**

```
┌────────────────────────────┐  ┌────────────────────────────┐
│  Swap                      │  │  Add Liquidity             │
│  ─────────────────────     │  │  ─────────────────────     │
│  From: [USDC ▾]  [100]    │  │  Token A: [USDC] [500]    │
│  To:   [WETH ▾]           │  │  Token B: [WETH] [0.2]    │
│                            │  │                            │
│  Rate: 1 USDC = 0.0004 ETH│  │  Range: [Full Range]      │
│                            │  │                            │
│  [ Execute Swap ]          │  │  [ Add Liquidity ]         │
│  [glass card]              │  │  [glass card]              │
│                            │  │  ⚠️ Requires LIQUIDITY tier │
└────────────────────────────┘  └────────────────────────────┘
```

- Swap panel: always active if `SWAP` badge is present
- Liquidity panel: active only if `LIQUIDITY` badge is present. If swap-only, the card has `opacity-50 pointer-events-none` and shows the warning text in amber. The button reads "Insufficient Tier" instead of "Add Liquidity"
- On expired investor: both panels disabled, red border, "ACCESS REVOKED — your broker's license has expired"
- On successful swap: `sonner` toast with green checkmark and tx hash link
- On revert: `sonner` toast with red X, showing the revert reason

---

## 8. Apply View

Shown when a connected wallet has no subname.

```
┌──────────────────────────────────────────────────────────────┐
│  Apply for Pool Access                                       │
│                                                              │
│  Select Issuer:    [ Acme Corp ▾ ]                          │
│  Select Broker:    [ Prime Capital ▾ ]                      │
│  Requested Tier:   ○ Retail (swap only)                     │
│                    ○ Market Maker (swap + liquidity)         │
│  Preferred Label:  [ alice ]                                │
│                                                              │
│  Your KYC data will be processed inside a Chainlink CRE     │
│  trusted execution environment. No personal information      │
│  is stored on-chain. Only the verdict (approved/rejected)    │
│  is published.                                               │
│                                                              │
│  [ Submit Application ]                                      │
│                                                              │
│  [glass card, centered, max-w-lg mx-auto]                   │
└──────────────────────────────────────────────────────────────┘
```

On submit: calls `ApplicationContract.submitApplication(...)` which emits `ApplicationSubmitted`. Show a "Processing..." state with a spinner, then redirect to the CRE Terminal page so the user (and judges) can watch the workflow execute.

---

## 9. CRE Terminal Page

**This is a dedicated page at `/dashboard/cre`.** Styled like a real terminal to show judges exactly what the CRE workflow does.

### Design

Full-width glass card with a **terminal chrome** — a top bar with three dots (red/amber/green) and a title "Canopy CRE · Confidential Workflow".

```
┌──────────────────────────────────────────────────────────────┐
│  ● ● ●   Canopy CRE · Confidential Workflow                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  $ cre workflow simulate eligibility --broadcast             │
│                                                              │
│  [12:04:01] ▸ Application received                          │
│             applicationId: 0xa3f2...89b1                     │
│             wallet: 0xAbC1...DeF4                            │
│             issuer: acme.canopy.eth                          │
│             broker: prime                                    │
│             requestedTier: retail (swap only)                │
│                                                              │
│  [12:04:02] ▸ Entering TEE enclave (AWS Nitro, us-west-2)  │
│             ┌─── CONFIDENTIAL BOUNDARY ──────────────────┐  │
│             │                                            │  │
│  [12:04:02] │ 🔐 Fetching secrets...                     │  │
│             │    KYC_API_TOKEN         ████████ (hidden)  │  │
│             │    ELIGIBILITY_RULEBOOK  ████████ (hidden)  │  │
│             │                                            │  │
│  [12:04:03] │ 🌐 Calling KYC endpoint...                 │  │
│             │    POST https://kyc-api.mock/verify         │  │
│             │    Status: 200 OK                           │  │
│             │    Response: ████████████ (protected)        │  │
│             │                                            │  │
│  [12:04:03] │ 📊 Evaluating eligibility...               │  │
│             │    Criteria:  ████████ (protected)           │  │
│             │    Score:     ████████ (protected)           │  │
│             │    Decision:  ✅ APPROVED                    │  │
│             │                                            │  │
│             └────────────────────────────────────────────┘  │
│                                                              │
│  [12:04:04] ▸ Crossing back via usingTheDons()              │
│             ⚠ Everything past this point is PUBLIC           │
│                                                              │
│  [12:04:04] ▸ Verdict (public):                             │
│             wallet:       0xAbC1...DeF4                      │
│             label:        alice                              │
│             broker:       prime.acme.canopy.eth              │
│             roleBitmap:   0x0000...0001 (SWAP_ALLOWED)       │
│             expiry:       2026-09-12T00:00:00Z               │
│             approved:     true                               │
│                                                              │
│  [12:04:05] ▸ Writing DON-signed report...                  │
│             → MintAttestor (0x7B2c...4F1a)                  │
│             txHash: 0x91af...c3b2                            │
│             [View on Etherscan ↗]                            │
│                                                              │
│  [12:04:06] ▸ Subname minted ✓                              │
│             alice.prime.acme.canopy.eth                      │
│             Roles: ELIGIBLE_SWAP (1<<64)                     │
│                                                              │
│  ✅ Workflow complete                                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Technical implementation

- Background: `bg-[#0C0C0C]` — slightly lighter than root bg
- Font: `font-mono text-sm`
- The "CONFIDENTIAL BOUNDARY" box: dashed border in `border-canopy-500/40`, with a subtle `bg-canopy-900/10` background
- Secret values: rendered as `████████` in `text-stone-600` — visually redacted
- Protected items: same treatment, grey blocks
- The decision line: `text-canopy-400` for APPROVED, `text-danger-400` for REJECTED
- Lines stream in with a typing animation (200ms delay between lines, using `framer-motion` `AnimatePresence` + staggered children)
- The `[View on Etherscan ↗]` is a real link to `sepolia.etherscan.io/tx/{hash}`

### Data source

This view reads from **Sepolia event logs** in real time:
1. `ApplicationSubmitted` event (from ApplicationContract)
2. Workflow execution status (mock — we simulate this client-side based on timing, since the CRE simulator runs off-chain and we can't stream its stdout to the browser)
3. `SubnameRegistered` event (from the broker's UserRegistry)
4. Report hash from the MintAttestor `ReportProcessed` event

For the hackathon, the "inside enclave" portion is **animated client-side** based on expected timing after the ApplicationSubmitted event. The on-chain events (application submitted, subname minted) are real and read from Sepolia logs.

---

## 10. Explorer Page

Interactive tree visualization of the full ENS hierarchy.

### Design

ENS-manager-app inspired — each node is a glass card, connected by lines.

```
                    ┌─────────────────────┐
                    │  canopy.eth          │
                    │  Platform Root       │
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              │                               │
    ┌─────────┴──────────┐         ┌─────────┴──────────┐
    │ acme.canopy.eth    │         │ zenith.canopy.eth   │
    │ Issuer · Pool 0x.. │         │ Issuer · Pool 0x.. │
    └─────────┬──────────┘         └─────────┬──────────┘
              │                               │
    ┌─────────┴──────────┐         ┌─────────┴──────────┐
    │ prime.acme...      │         │ prime.zenith...     │
    │ Broker             │         │ Broker              │
    │ ⏱ 6d 14h          │         │ ⏱ 29d 2h           │
    └────┬──────┬────────┘         └─────────┬──────────┘
         │      │                             │
    ┌────┴─┐ ┌──┴───┐                  ┌─────┴────┐
    │alice │ │ mm   │                  │  bob     │
    │[SWAP]│ │[SWAP]│                  │ [SWAP]   │
    │      │ │[LIQ] │                  │          │
    └──────┘ └──────┘                  └──────────┘
```

Use `@visx/hierarchy` with `d3-hierarchy` for the tree layout. Each node rendered as a glass card. Lines rendered as SVG paths with `stroke: rgba(52, 211, 153, 0.3)` (canopy-400 at 30%).

Clicking a node opens a detail panel (slide-in from right) showing:
- Full name
- Status (REGISTERED / expired)
- Expiry timestamp + countdown
- Role bitmap (raw hex + decoded labels)
- Resource hash
- Owner address
- Registry address

---

## 11. Shared Components

### `ExpiryCountdown.tsx`

```typescript
// Props: expiryTimestamp: number (unix seconds)
// Renders: DD : HH : MM : SS in font-mono
// Color: canopy-400 (>7d), amber-400 (1-7d), danger-400 (<1d)
// Updates every second via setInterval
// When expired: shows "EXPIRED" in danger-400, pulsing animation
```

This is THE most important visual component. It appears in:
- Broker rows (issuer dashboard)
- Broker identity card (broker dashboard)
- Investor dashboard (broker expiry warning)
- Explorer nodes

### `RoleBadge.tsx`

```typescript
// Props: role: 'swap' | 'liquidity' | 'expired' | 'pending'
// Renders: small pill badge with icon + label
// Variants:
//   swap:      bg-canopy-400/20 text-canopy-400 border-canopy-400/30 — "SWAP" with ArrowLeftRight icon
//   liquidity: bg-blue-400/20 text-blue-400 border-blue-400/30 — "LIQUIDITY" with Droplets icon
//   expired:   bg-red-500/20 text-red-400 border-red-500/30 — "EXPIRED" with XCircle icon
//   pending:   bg-amber-400/20 text-amber-400 border-amber-400/30 — "PENDING" with Timer icon
```

### `GlassCard.tsx`

```typescript
// Props: children, className, hover (boolean, default true)
// Base classes:
//   bg-gradient-to-br from-white/[0.05] to-white/[0.02]
//   backdrop-blur-[24px]
//   border border-white/[0.08]
//   rounded-2xl p-6
//   transition-all duration-300
// Hover (if enabled):
//   hover:border-white/[0.12] hover:from-white/[0.07] hover:to-white/[0.03]
```

### `AttestationTrail.tsx`

```typescript
// Props: workflowId, reportHash, policyHash (optional), txHash
// Renders: small monospace row showing:
//   Workflow: a3f2...89b1 · Report: 8b1c...4e2a · Policy: 7d91...f3c8
//   [View tx ↗] linking to Etherscan
// All hashes truncated to 4...4 with tooltip showing full value
```

---

## 12. 3D Video & Asset Sources

### Hero background video — FREE sources for nature/canopy footage:

1. **Pexels Videos** — https://www.pexels.com/search/videos/forest%20canopy/
   Search "forest canopy aerial", "tree canopy drone", "forest fog aerial"
   License: free for commercial use, no attribution needed

2. **Pixabay Videos** — https://pixabay.com/videos/search/forest%20canopy/
   Search "forest aerial drone", "trees fog"
   License: Pixabay License (free, no attribution)

3. **Coverr** — https://coverr.co/
   Search "nature", "forest", "aerial"
   License: free for commercial use

4. **Mixkit** — https://mixkit.co/free-stock-video/nature/
   Search "forest", "aerial nature", "trees"
   License: Mixkit License (free)

### Recommended search terms for the best results:
- "aerial forest canopy fog" — gives you that moody, dark, cinematic feel matching the Prisma vibe
- "drone forest sunrise" — golden hour + forest = exactly the Prisma screenshot aesthetic
- "abstract particles dark" — fallback if nature footage doesn't fit

### Video specs for Next.js:
- Format: MP4 (H.264)
- Resolution: 1920×1080 minimum
- Duration: 10-30 second loop
- File size: keep under 15MB for fast loading
- Apply CSS: `object-fit: cover; opacity: 0.4;` with a gradient overlay on top

---

## 13. Logo Generation Prompt

Feed this to an AI image generator (Midjourney, DALL-E, Ideogram):

```
Design a logo for "Canopy" — a Web3 compliance platform that uses hierarchical domain 
names for permission management. The logo should be:

STYLE: Modern, slightly cartoonish but refined. NOT corporate. NOT generic blockchain. 
Think of it like a friendly, premium tech brand — similar to Linear, Notion, or Vercel 
but with a nature twist.

SYMBOL: A stylized tree canopy viewed from below (looking up through the branches), 
forming a subtle network/hierarchy pattern where branches = nodes in a permission tree. 
The negative space between leaves could hint at a shield or checkmark shape. Keep it 
simple enough to work at 32×32px as a favicon.

COLOR: Emerald green (#10B981) as the primary, with a warm amber (#F59E0B) accent on 
one element (perhaps a single highlighted leaf or node). Dark background version and 
light/transparent version.

WORDMARK: "Canopy" in a rounded, slightly cursive serif font — warm and approachable 
but technical. Similar to the weight and feel of Fraunces or Playfair Display italic 
but with more personality. The "C" could subtly incorporate a curved branch.

DELIVERABLES: 
1. Icon only (square, for favicon and GitHub avatar)
2. Icon + wordmark horizontal (for navbar)
3. Icon + wordmark stacked (for splash/loading)

Background: transparent PNG and SVG.
Aspect ratio for icon: 1:1
Aspect ratio for horizontal: 4:1
```

---

## 14. Cover Image / OG Image Generation Prompt

For the GitHub repo social preview and ETHGlobal showcase card:

```
Create a wide cover image (1200×630px) for "Canopy" — a Web3 compliance platform.

SCENE: A dark, atmospheric aerial view of a forest canopy at dusk. The trees form a 
visible hierarchical network pattern — some branches glow emerald green (representing 
active connections), while one section of the canopy has gone dark/red (representing 
an expired broker whose investors lost access). 

In the dark section, there's a subtle fade — the leaves are visually wilting or 
becoming transparent, showing the cascade effect.

OVERLAY: The word "CANOPY" in large Fraunces Bold cream-colored text, centered. Below 
it in smaller Inter text: "Hierarchical compliance for permissioned pools."

Bottom strip: Three small logos — ENS, Uniswap, Chainlink — in muted white at 30% 
opacity.

MOOD: Cinematic, moody, dark with emerald and amber accents. Similar to the Prisma 
website aesthetic — dramatic clouds, golden hour lighting hitting the canopy edge.

STYLE: Photorealistic with a slight digital/generative art overlay — the network 
pattern in the branches should feel like it could be real but is subtly too geometric.

FORMAT: 1200×630px PNG, sRGB
```

---

## 15. Presentation Slide Prompts

### Slide 1 — Title

```
Create a presentation title slide (16:9, 1920×1080) with:
- Dark background (#050505) with subtle noise texture
- Large "CANOPY" in Fraunces Bold, cream (#F5F0E8), centered
- Below: "Hierarchical compliance for permissioned pools" in Inter 400, stone-400
- The Canopy logo icon top-left at ~80px
- A subtle emerald glow (#10B981 at 10% opacity, 200px blur radius) behind the text
- Bottom right: "ETHOnline 2026 · Built from scratch" in text-xs, text-muted
- Bottom left: three sponsor icons (ENS, Uniswap, Chainlink) at 30% opacity
```

### Slide 2 — The Problem

```
Create a presentation slide (16:9, dark bg #050505) showing:
- Heading: "10,000 investors. One rogue broker. 10,000 transactions." in Fraunces 600, cream
- Below: a simple visual — a flat list of 10,000 tiny dots (representing investors) with 
  red X marks appearing one by one, slowly. Next to it, a counter incrementing: 
  "Tx #1... Tx #2... Tx #9,999... Tx #10,000"
- Caption: "Today's allowlists are flat. Revocation is O(n)." in Inter, text-secondary
- Minimal, stark, letting the absurdity of the number speak
```

### Slide 3 — The Solution

```
Presentation slide (16:9, dark bg) showing:
- Heading: "One name expires. The whole book goes dark." in Fraunces 600, cream
- Center: the Canopy hierarchy diagram (issuer → broker → investors) as a tree, 
  with the broker node pulsing amber then going red, and all child nodes simultaneously 
  going dark
- Caption: "Revocation is O(1). Just let the name lapse." in Inter, text-secondary
- Emerald accent lines connecting the tree nodes
```

### Slide 4 — Architecture

```
Presentation slide (16:9, dark bg) showing the three-layer architecture:
- Three glass cards side by side:
  1. "Registry" — ENSv2 icon — "Stores the hierarchy with expiry"
  2. "Trading Pool" — Uniswap icon — "Checks every swap against the tree"  
  3. "KYC Engine" — Chainlink icon — "Evaluates in a TEE, only verdicts leave"
- Arrows flowing left to right between them
- Clean, minimal, no clutter
```

### Slide 5 — Demo

```
Presentation slide (16:9, dark bg) — just the text:
- Large centered: "Demo" in Fraunces 700, cream
- Below: "canopy.eth" in font-mono, canopy-400
- Subtle emerald glow behind
```

---

## Implementation Priority Order

For Builder B, build in this order:

1. **Landing page** — first impression, takes 2-3 hours with the video + aceternity components
2. **Dashboard shell** — sidebar, topbar, role detection, routing — 2-3 hours
3. **Issuer dashboard** — the primary demo view — 3-4 hours
4. **CRE terminal page** — the judge-facing CRE showcase — 2-3 hours
5. **Investor dashboard** — swap/liquidity panels — 2-3 hours
6. **Broker dashboard** — mostly reuses issuer components — 1-2 hours
7. **Explorer page** — tree visualization — 2-3 hours (cut if tight)
8. **Apply view** — the application form — 1 hour (cut if tight)

Total: ~18-24 hours of frontend work across the hackathon.

**Cut priority (if time is short):** Explorer page first, then Apply view. The demo video only needs the Issuer dashboard, CRE terminal, and the Investor dashboard for the swap/revert beats. Broker dashboard is nice-to-have for the on-camera broker-expiry moment but the Issuer view already shows the countdown.
