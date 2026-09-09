import { Providers } from "@/components/providers";
import { Navbar } from "@/components/dashboard/Navbar";
import { DashboardBackground } from "@/components/dashboard/DashboardBackground";
import { Toaster } from "@/components/ui/sonner";

export const dynamic = "force-dynamic";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Providers>
      <div className="relative min-h-screen">
        <DashboardBackground />
        <div className="relative z-10 pointer-events-none">
          <div className="pointer-events-auto">
            <Navbar />
          </div>
          <main className="pointer-events-auto mx-auto max-w-6xl px-4 py-6 sm:px-6 md:px-10">
            {children}
          </main>
        </div>
      </div>
      <Toaster />
    </Providers>
  );
}
