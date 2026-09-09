"use client";

import { useMemo, useState } from "react";
import { Group } from "@visx/group";
import { hierarchy, Tree } from "@visx/hierarchy";
import { type HierarchyPointNode } from "d3-hierarchy";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
import { type NodeState } from "@/lib/ensv2";
import { ExpiryCountdown } from "./ExpiryCountdown";
import { RoleBadges } from "./RoleBadge";
import { GlassCard } from "./GlassCard";
import { cn } from "@/lib/utils";

interface HierarchyTreeProps {
  tree: NodeState;
  width?: number;
  height?: number;
}

const NODE_WIDTH = 180;
const NODE_HEIGHT = 80;

const levelColors: Record<string, string> = {
  platform: "#FFFBB8",
  issuer: "#FBBF24",
  broker: "#60A5FA",
  investor: "#A78BFA",
};

function TreeNode({
  node,
  onSelect,
}: {
  node: HierarchyPointNode<NodeState>;
  onSelect: (n: NodeState) => void;
}) {
  const d = node.data;
  const color = levelColors[d.level] ?? "#F5F0E8";

  return (
    <Group top={node.y} left={node.x}>
      <foreignObject
        x={-NODE_WIDTH / 2}
        y={-NODE_HEIGHT / 2}
        width={NODE_WIDTH}
        height={NODE_HEIGHT}
        className="overflow-visible"
      >
        <button
          onClick={() => onSelect(d)}
          className={cn(
            "flex h-full w-full flex-col items-center justify-center rounded-xl border px-3 py-2 text-center transition-all duration-200",
            "bg-gradient-to-br from-white/[0.06] to-white/[0.02] backdrop-blur-[16px]",
            d.isAlive || d.level === "platform"
              ? "border-white/[0.10] hover:border-white/[0.20]"
              : "border-red-500/30 opacity-60"
          )}
        >
          <span className="text-[10px] font-medium uppercase tracking-wider" style={{ color }}>
            {d.level}
          </span>
          <span className="mt-0.5 truncate font-mono text-xs" style={{ color: "#F5F0E8" }}>
            {d.label}
          </span>
          {d.level === "broker" && d.state && (
            <span className="mt-1">
              <ExpiryCountdown expiry={d.state.expiry} variant="inline" />
            </span>
          )}
          {d.level === "investor" && (
            <span className="mt-1">
              <RoleBadges swap={d.swap} liquidity={d.liquidity} alive={d.isAlive} />
            </span>
          )}
        </button>
      </foreignObject>
    </Group>
  );
}

export function HierarchyTreeViz({ tree, width = 900, height = 600 }: HierarchyTreeProps) {
  const [selected, setSelected] = useState<NodeState | null>(null);

  const root = useMemo(
    () =>
      hierarchy(tree, (d) => (d.children.length > 0 ? d.children : null)),
    [tree]
  );

  const margin = { top: 60, left: 40, right: 40, bottom: 60 };
  const innerW = width - margin.left - margin.right;
  const innerH = height - margin.top - margin.bottom;

  return (
    <div className="flex gap-6">
      <div className="flex-1 overflow-auto rounded-2xl border border-white/[0.08] bg-[#0C0C0C]">
        <svg width={width} height={height}>
          <Tree<NodeState>
            root={root}
            size={[innerW, innerH]}
          >
            {(treeData) => (
              <Group top={margin.top} left={margin.left}>
                {/* Links */}
                {treeData.links().map((link, i) => (
                  <line
                    key={i}
                    x1={link.source.x}
                    y1={link.source.y + NODE_HEIGHT / 2}
                    x2={link.target.x}
                    y2={link.target.y - NODE_HEIGHT / 2}
                    stroke="rgba(52, 211, 153, 0.2)"
                    strokeWidth={1.5}
                  />
                ))}
                {/* Nodes */}
                {treeData.descendants().map((node, i) => (
                  <TreeNode key={i} node={node as unknown as HierarchyPointNode<NodeState>} onSelect={setSelected} />
                ))}
              </Group>
            )}
          </Tree>
        </svg>
      </div>

      {/* Detail panel */}
      {selected && (
        <GlassCard className="w-72 shrink-0 !p-5">
          <h3
            className="font-mono text-sm font-medium"
            style={{ color: "#F5F0E8" }}
          >
            {selected.fullName}
          </h3>
          <div className="mt-3 space-y-2 text-xs text-stone-400">
            <div className="flex justify-between">
              <span className="text-stone-500">Level</span>
              <span className="capitalize">{selected.level}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-stone-500">Status</span>
              <span className={selected.isAlive ? "text-canopy-400" : "text-red-400"}>
                {selected.isAlive ? "REGISTERED" : "EXPIRED"}
              </span>
            </div>
            {selected.state?.expiry && (
              <div className="flex justify-between">
                <span className="text-stone-500">Expiry</span>
                <span>
                  {new Date(Number(selected.state.expiry) * 1000).toISOString().slice(0, 19)}
                </span>
              </div>
            )}
            {selected.state?.latestOwner && (
              <div className="flex justify-between">
                <span className="text-stone-500">Owner</span>
                <span className="font-mono">
                  {selected.state.latestOwner.slice(0, 6)}...
                  {selected.state.latestOwner.slice(-4)}
                </span>
              </div>
            )}
            {selected.state?.resource !== undefined && selected.state.resource !== BigInt(0) && (
              <div className="flex justify-between">
                <span className="text-stone-500">Resource</span>
                <span className="font-mono">
                  {selected.state.resource.toString(16).slice(0, 8)}...
                </span>
              </div>
            )}
            <div className="flex justify-between">
              <span className="text-stone-500">Registry</span>
              <span className="font-mono">
                {selected.registryAddress.slice(0, 6)}...
                {selected.registryAddress.slice(-4)}
              </span>
            </div>
          </div>
          <button
            onClick={() => setSelected(null)}
            className="mt-4 text-xs text-stone-500 hover:text-stone-400"
          >
            Close
          </button>
        </GlassCard>
      )}
    </div>
  );
}
