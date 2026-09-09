"use client";

import { PrivyProvider } from "@privy-io/react-auth";
import { sepolia } from "viem/chains";

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? ""}
      config={{
        appearance: {
          theme: "dark",
          accentColor: "#FFFBB8",
        },
        embeddedWallets: {
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
        },
        defaultChain: sepolia,
        supportedChains: [sepolia],
      }}
    >
      {children}
    </PrivyProvider>
  );
}
