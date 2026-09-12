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
  { label: "Marketplace", href: "/dashboard/marketplace" },
];

const roleBadgeStyles: Record<string, string> = {
  issuer: "bg-[#FFFBB8]/15 text-[#FFFBB8] border-[#FFFBB8]/25",
  broker: "bg-amber-300/15 text-amber-300 border-amber-300/25",
  investor: "bg-[#FFFBB8]/15 text-[#FFFBB8] border-[#FFFBB8]/25",
  applicant: "bg-[#F5F0E8]/10 text-[#F5F0E8]/40 border-[#F5F0E8]/15",
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
                  ? "text-[#FFFBB8]"
                  : "text-[#F5F0E8]/40 hover:text-[#F5F0E8]/80"
              )}
            >
              {item.label}
            </Link>
          );
        })}

        {/* Spacer */}
        <div className="hidden w-px self-stretch bg-[#FFFBB8]/[0.08] sm:block" />

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
              <span className="hidden rounded-full border border-[#FFFBB8]/[0.08] bg-[#FFFBB8]/[0.04] px-2.5 py-1 font-mono text-[10px] text-[#F5F0E8]/40 md:inline-flex">
                {shortAddress}
              </span>
            )}
            <button
              onClick={logout}
              className="text-[#F5F0E8]/30 transition-colors hover:text-[#F5F0E8]/60"
            >
              <LogOut className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <Button
            onClick={login}
            size="sm"
            className="bg-[#FFFBB8] text-[#1a1710] font-semibold hover:bg-[#FFFBB8]/90 text-xs"
          >
            <Wallet className="mr-1.5 h-3.5 w-3.5" />
            Connect
          </Button>
        )}
      </div>
    </nav>
  );
}
