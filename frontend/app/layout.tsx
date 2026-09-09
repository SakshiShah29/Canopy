import type { Metadata } from "next";
import {
  Inter,
  JetBrains_Mono,
  Fraunces,
} from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
});

const fraunces = Fraunces({
  variable: "--font-fraunces",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Canopy — ENS Permissioned Pools",
  description:
    "Hierarchical ENS eligibility for Uniswap v4 permissioned pools",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${jetbrainsMono.variable} ${fraunces.variable} dark h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-[#050505] text-[#F5F0E8]">
        {children}
      </body>
    </html>
  );
}
