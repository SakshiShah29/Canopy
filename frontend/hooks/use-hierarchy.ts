"use client";

import { useCallback, useEffect, useState } from "react";
import { buildHierarchyTree, type NodeState } from "@/lib/ensv2";

const POLL_INTERVAL = 5_000;

export function useHierarchy() {
  const [tree, setTree] = useState<NodeState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const t = await buildHierarchyTree();
      setTree(t);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load hierarchy");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, POLL_INTERVAL);
    return () => clearInterval(id);
  }, [refresh]);

  return { tree, loading, error, refresh };
}
