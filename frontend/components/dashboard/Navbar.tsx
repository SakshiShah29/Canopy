"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { usePrivy } from "@privy-io/react-auth";
import { Wallet, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useRole } from "@/hooks/useRole";
import { cn } from "@/lib/utils";

const navItems = [
  { label: "Dashboard", href: "/dashboard" },
  { label: "Explorer", href: "/dashboard/explorer" },
  { label: "CRE Terminal", href: "/dashboard/cre" },
  { label: "Apply", href: "/dashboard/apply" },
];

const roleBadgeStyles: Record<string, string> = {
  issuer: "bg-amber-400/20 text-amber-400 border-amber-400/30",
  broker: "bg-blue-400/20 text-blue-400 border-blue-400/30",
  investor: "bg-canopy-400/20 text-canopy-400 border-canopy-400/30",
  applicant: "bg-stone-400/20 text-stone-400 border-stone-400/30",
};

export function Navbar() {
  const pathname = usePathname();
  const { ready, authenticated, login, logout, user } = usePrivy();
  const { role } = useRole();

  const address = user?.wallet?.address;
  const shortAddress = address
    ? `${address.slice(0, 6)}...${address.slice(-4)}`
    : null;

  return (
    <nav className="sticky top-0 z-50 flex justify-center pt-0">
      <div className="flex items-center gap-3 rounded-b-2xl bg-black/90 px-5 py-3 backdrop-blur-xl sm:gap-5 md:gap-8 md:rounded-b-3xl md:px-8">
        {/* Logo */}
        <Link href="/" className="mr-2 flex shrink-0 items-center">
          <Image
            src="/name.png"
            alt="Canopy"
            width={200}
            height={50}
            className="h-9 w-auto sm:h-16"
          />
        </Link>

        {/* Nav links */}
        {navItems.map((item) => {
          const isActive =
            item.href === "/dashboard"
              ? pathname === "/dashboard" ||
                pathname === "/dashboard/issuer" ||
                pathname === "/dashboard/broker" ||
                pathname === "/dashboard/investor"
              : pathname.startsWith(item.href);

          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "hidden text-xs transition-colors sm:inline-block md:text-sm",
                isActive
                  ? "text-canopy-400"
                  : "text-[#F5F0E8]/60 hover:text-[#F5F0E8]"
              )}
            >
              {item.label}
            </Link>
          );
        })}

        {/* Spacer */}
        <div className="hidden w-px self-stretch bg-white/[0.08] sm:block" />

        {/* Role badge */}
        {authenticated && (
          <Badge
            variant="outline"
            className={cn(
              "hidden text-[10px] font-semibold uppercase tracking-wider sm:inline-flex",
              roleBadgeStyles[role] ?? roleBadgeStyles.applicant
            )}
          >
            {role}
          </Badge>
        )}

        {/* Wallet */}
        {ready && authenticated ? (
          <div className="flex items-center gap-2">
            {shortAddress && (
              <span className="hidden rounded-full border border-white/[0.08] bg-white/[0.04] px-2.5 py-1 font-mono text-[10px] text-stone-400 md:inline-flex">
                {shortAddress}
              </span>
            )}
            <button
              onClick={logout}
              className="text-stone-500 transition-colors hover:text-stone-300"
            >
              <LogOut className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <Button
            onClick={login}
            size="sm"
            className="bg-canopy-500 text-black hover:bg-canopy-500/90 text-xs"
          >
            <Wallet className="mr-1.5 h-3.5 w-3.5" />
            Connect
          </Button>
        )}
      </div>
    </nav>
  );
}
