"use client";

import { motion } from "framer-motion";
import { Loader2, RefreshCw } from "lucide-react";
import { useHierarchy } from "@/hooks/use-hierarchy";
import { HierarchyTreeViz } from "@/components/dashboard/HierarchyTree";
import { Button } from "@/components/ui/button";

export default function ExplorerPage() {
  const { tree, loading, error, refresh } = useHierarchy();

  return (
    <div className="space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center justify-between"
      >
        <div>
          <h1
            className="font-display text-2xl font-semibold tracking-tight md:text-3xl"
            style={{ color: "#F5F0E8" }}
          >
            Explorer
          </h1>
          <p className="text-sm text-stone-400">
            Interactive ENS hierarchy tree
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={refresh}
          disabled={loading}
          className="text-stone-500"
        >
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <RefreshCw className="h-4 w-4" />
          )}
        </Button>
      </motion.div>

      {error && (
        <div className="glass-card border-red-500/30 text-sm text-red-400">
          {error}
        </div>
      )}

      {loading && !tree ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-canopy-400" />
        </div>
      ) : tree ? (
        <HierarchyTreeViz tree={tree} width={1000} height={650} />
      ) : null}
    </div>
  );
}
