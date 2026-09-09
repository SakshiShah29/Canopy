"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useRole } from "@/hooks/useRole";
import { Loader2 } from "lucide-react";

export default function DashboardRedirect() {
  const router = useRouter();
  const { role, loading } = useRole();

  useEffect(() => {
    if (loading) return;

    switch (role) {
      case "issuer":
        router.replace("/dashboard/issuer");
        break;
      case "broker":
        router.replace("/dashboard/broker");
        break;
      case "investor":
        router.replace("/dashboard/investor");
        break;
      case "applicant":
      default:
        router.replace("/dashboard/apply");
        break;
    }
  }, [role, loading, router]);

  return (
    <div className="flex flex-1 items-center justify-center py-32">
      <div className="flex flex-col items-center gap-4">
        <Loader2 className="h-8 w-8 animate-spin text-canopy-400" />
        <p className="text-sm text-stone-400">Detecting your role...</p>
      </div>
    </div>
  );
}
