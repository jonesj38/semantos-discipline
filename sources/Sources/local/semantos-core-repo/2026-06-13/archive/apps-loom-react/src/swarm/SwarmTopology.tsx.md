---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/SwarmTopology.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.959997+00:00
---

# archive/apps-loom-react/src/swarm/SwarmTopology.tsx

```tsx
/**
 * DH5.1 — SwarmTopology: Force-directed graph of 25 swarm nodes.
 *
 * Uses d3-force for physics simulation and Canvas 2D for rendering.
 * Nodes colored by persona; edges flash on cell publish events.
 */

import { useRef, useEffect, useCallback } from 'react';
import {
  forceSimulation,
  forceLink,
  forceManyBody,
  forceCenter,
  forceCollide,
  type SimulationNodeDatum,
  type SimulationLinkDatum,
} from 'd3-force';
import { useSwarmDashboard } from './SwarmDashboardProvider';
import { PERSONA_COLORS, type PersonaId, type NodeData, type EdgeData } from './types';

interface SimNode extends SimulationNodeDatum {
  id: string;
  persona: PersonaId | 'router';
  cellCount: number;
  activeTable?: string;
}

interface SimLink extends SimulationLinkDatum<SimNode> {
  lastFlash: number;
  cellCount: number;
}

const NODE_RADIUS = 14;
const ROUTER_RADIUS = 20;
const FLASH_DURATION_MS = 400;

function getNodeColor(persona: PersonaId | 'router'): string {
  if (persona === 'router') return '#888888';
  return PERSONA_COLORS[persona] ?? '#666666';
}

function getNodeLabel(node: SimNode): string {
  if (node.persona === 'router') return 'BR';
  return node.id.replace(/^bot-/, 'B').replace(/^172\.\d+\.\d+\./, '');
}

export function SwarmTopology() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const simRef = useRef<ReturnType<typeof forceSimulation<SimNode>> | null>(null);
  const animRef = useRef<number>(0);
  const nodesRef = useRef<SimNode[]>([]);
  const linksRef = useRef<SimLink[]>([]);

  const { state, selectNode } = useSwarmDashboard();
  const { nodes, edges, selectedNodeId } = state;

  // Rebuild simulation nodes/links when topology changes
  useEffect(() => {
    const simNodes: SimNode[] = [
      { id: 'border-router', persona: 'router', cellCount: 0 },
    ];

    for (const n of nodes) {
      const existing = nodesRef.current.find(sn => sn.id === n.id);
      simNodes.push({
        id: n.id,
        persona: n.persona,
        cellCount: n.cellCount,
        activeTable: n.activeTable,
        x: existing?.x,
        y: existing?.y,
        vx: existing?.vx,
        vy: existing?.vy,
      });
    }

    // If no real nodes yet, seed 25 placeholder bots
    if (nodes.length === 0) {
      const personas: PersonaId[] = ['nit', 'maniac', 'calculator', 'apex'];
      for (let i = 0; i < 25; i++) {
        simNodes.push({
          id: `bot-${i}`,
          persona: personas[i % 4],
          cellCount: 0,
        });
      }
    }

    const simLinks: SimLink[] = [];
    for (const e of edges) {
      simLinks.push({
        source: e.source,
        target: e.target,
        lastFlash: e.lastFlash,
        cellCount: e.cellCount,
      });
    }

    // Ensure all bots have a link to the router
    for (const n of simNodes) {
      if (n.id !== 'border-router' && !simLinks.find(l =>
        (typeof l.source === 'string' ? l.source : (l.source as SimNode).id) === n.id &&
        (typeof l.target === 'string' ? l.target : (l.target as SimNode).id) === 'border-router'
      )) {
        simLinks.push({
          source: n.id,
          target: 'border-router',
          lastFlash: 0,
          cellCount: 0,
        });
      }
    }

    nodesRef.current = simNodes;
    linksRef.current = simLinks;

    // Create or restart simulation
    if (simRef.current) {
      simRef.current.stop();
    }

    const canvas = canvasRef.current;
    const w = canvas?.width ?? 600;
    const h = canvas?.height ?? 400;

    simRef.current = forceSimulation<SimNode>(simNodes)
      .force('link', forceLink<SimNode, SimLink>(simLinks).id(d => d.id).distance(80).strength(0.3))
      .force('charge', forceManyBody().strength(-120))
      .force('center', forceCenter(w / 2, h / 2))
      .force('collide', forceCollide(NODE_RADIUS + 4))
      .alphaDecay(0.02)
      .on('tick', () => {}); // rendering done in RAF loop

  }, [nodes.length, edges.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // Update flash timestamps on edge changes without full rebuild
  useEffect(() => {
    for (const e of edges) {
      const simLink = linksRef.current.find(l => {
        const sId = typeof l.source === 'string' ? l.source : (l.source as SimNode).id;
        const tId = typeof l.target === 'string' ? l.target : (l.target as SimNode).id;
        return sId === e.source && tId === e.target;
      });
      if (simLink) {
        simLink.lastFlash = e.lastFlash;
        simLink.cellCount = e.cellCount;
      }
    }
  }, [edges]);

  // Canvas render loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    function draw() {
      if (!ctx || !canvas) return;
      const w = canvas.width;
      const h = canvas.height;
      const now = Date.now();

      ctx.clearRect(0, 0, w, h);

      // Draw edges
      for (const link of linksRef.current) {
        const src = link.source as SimNode;
        const tgt = link.target as SimNode;
        if (src.x == null || tgt.x == null) continue;

        const flashAge = now - link.lastFlash;
        const isFlashing = flashAge < FLASH_DURATION_MS;

        ctx.beginPath();
        ctx.moveTo(src.x, src.y!);
        ctx.lineTo(tgt.x, tgt.y!);
        ctx.strokeStyle = isFlashing
          ? `rgba(255, 255, 255, ${1 - flashAge / FLASH_DURATION_MS})`
          : '#333355';
        ctx.lineWidth = isFlashing ? 2 : 1;
        ctx.stroke();
      }

      // Draw table clusters
      const tables = new Map<string, SimNode[]>();
      for (const node of nodesRef.current) {
        if (node.activeTable) {
          const arr = tables.get(node.activeTable) ?? [];
          arr.push(node);
          tables.set(node.activeTable, arr);
        }
      }
      for (const [, tableNodes] of tables) {
        if (tableNodes.length < 2) continue;
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const n of tableNodes) {
          if (n.x != null && n.y != null) {
            minX = Math.min(minX, n.x);
            minY = Math.min(minY, n.y);
            maxX = Math.max(maxX, n.x);
            maxY = Math.max(maxY, n.y);
          }
        }
        const pad = 28;
        ctx.strokeStyle = '#555577';
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        ctx.strokeRect(minX - pad, minY - pad, maxX - minX + pad * 2, maxY - minY + pad * 2);
        ctx.setLineDash([]);
      }

      // Draw nodes
      for (const node of nodesRef.current) {
        if (node.x == null || node.y == null) continue;
        const r = node.persona === 'router' ? ROUTER_RADIUS : NODE_RADIUS;
        const color = getNodeColor(node.persona);
        const isSelected = node.id === selectedNodeId;

        // Selection ring
        if (isSelected) {
          ctx.beginPath();
          ctx.arc(node.x, node.y, r + 4, 0, Math.PI * 2);
          ctx.strokeStyle = '#ffffff';
          ctx.lineWidth = 2;
          ctx.stroke();
        }

        // Node circle
        ctx.beginPath();
        ctx.arc(node.x, node.y, r, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
        ctx.strokeStyle = '#1a1a2e';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Label
        ctx.fillStyle = '#e0e0e0';
        ctx.font = '10px Courier New';
        ctx.textAlign = 'center';
        ctx.fillText(getNodeLabel(node), node.x, node.y + r + 14);
      }

      animRef.current = requestAnimationFrame(draw);
    }

    animRef.current = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(animRef.current);
  }, [selectedNodeId]);

  // Resize canvas to container
  useEffect(() => {
    const container = containerRef.current;
    const canvas = canvasRef.current;
    if (!container || !canvas) return;

    const ro = new ResizeObserver(entries => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        canvas.width = width * devicePixelRatio;
        canvas.height = height * devicePixelRatio;
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;
        const ctx = canvas.getContext('2d');
        if (ctx) ctx.scale(devicePixelRatio, devicePixelRatio);
        // Re-center simulation
        if (simRef.current) {
          simRef.current.force('center', forceCenter(width / 2, height / 2));
          simRef.current.alpha(0.3).restart();
        }
      }
    });
    ro.observe(container);
    return () => ro.disconnect();
  }, []);

  // Click handling
  const handleClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    for (const node of nodesRef.current) {
      if (node.x == null || node.y == null) continue;
      const dx = node.x - x;
      const dy = node.y - y;
      const r = node.persona === 'router' ? ROUTER_RADIUS : NODE_RADIUS;
      if (dx * dx + dy * dy < (r + 4) * (r + 4)) {
        selectNode(node.id === selectedNodeId ? null : node.id);
        return;
      }
    }
    selectNode(null);
  }, [selectNode, selectedNodeId]);

  return (
    <div ref={containerRef} className="w-full h-full relative">
      <div className="absolute top-2 left-3 text-xs font-bold text-gray-400 tracking-wider">
        SWARM TOPOLOGY
      </div>
      <canvas
        ref={canvasRef}
        className="w-full h-full cursor-pointer"
        onClick={handleClick}
      />
    </div>
  );
}

```
