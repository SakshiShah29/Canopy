"use client";

import { useCallback, useEffect, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { detectRole, type RoleInfo } from "@/lib/role-detect";

export function useRole() {
  const { user, authenticated } = usePrivy();
  const [roleInfo, setRoleInfo] = useState<RoleInfo>({ role: "applicant" });
  const [loading, setLoading] = useState(true);

  const address = user?.wallet?.address;

  const refresh = useCallback(async () => {
    if (!authenticated || !address) {
      setRoleInfo({ role: "applicant" });
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const info = await detectRole(address);
      setRoleInfo(info);
    } catch {
      setRoleInfo({ role: "applicant" });
    } finally {
      setLoading(false);
    }
  }, [authenticated, address]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { ...roleInfo, loading, refresh };
}
