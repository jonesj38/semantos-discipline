---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/TPSCounter.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.959155+00:00
---

# archive/apps-loom-react/src/swarm/TPSCounter.tsx

```tsx
/**
 * DH5.2 — TPSCounter: Live TPS, sparkline, progress toward 1.5M target.
 */

import { useMemo } from 'react';
import { useSwarmDashboard } from './SwarmDashboardProvider';

const TARGET_CELLS = 1_500_000;

function trendArrow(history: number[]): string {
  if (history.length < 2) return '\u2192'; // →
  const curr = history[0];
  const prev = history[1];
  if (curr > prev) return '\u25B2'; // ▲
  if (curr < prev) return '\u25BC'; // ▼
  return '\u2192'; // →
}

function tpsColorClass(tps: number): string {
  if (tps >= 1000) return 'text-swarm-success';
  if (tps >= 500) return 'text-swarm-warning';
  return 'text-swarm-error';
}

function progressColorClass(tps: number): string {
  if (tps >= 1000) return 'bg-swarm-success';
  if (tps >= 500) return 'bg-swarm-warning';
  return 'bg-swarm-error';
}

function formatEta(tps: number, remaining: number): string {
  if (tps <= 0) return '--';
  const seconds = remaining / tps;
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${mins}m`;
}

function Sparkline({ data, width = 200, height = 32 }: { data: number[]; width?: number; height?: number }) {
  if (data.length < 2) return null;

  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const range = max - min || 1;

  // Data is newest-first; reverse for left-to-right chronological display
  const chronological = [...data].reverse();
  const points = chronological.map((v, i) => {
    const x = (i / (chronological.length - 1)) * width;
    const y = height - ((v - min) / range) * (height - 4) - 2;
    return `${x},${y}`;
  }).join(' ');

  const avg = data.reduce((a, b) => a + b, 0) / data.length;
  const avgY = height - ((avg - min) / range) * (height - 4) - 2;

  return (
    <svg width={width} height={height} className="block">
      {/* Average line */}
      <line x1={0} y1={avgY} x2={width} y2={avgY} stroke="#555577" strokeWidth={1} strokeDasharray="2,2" />
      {/* Sparkline */}
      <polyline
        points={points}
        fill="none"
        stroke="#33cc33"
        strokeWidth={1.5}
      />
    </svg>
  );
}

export function TPSCounter() {
  const { state } = useSwarmDashboard();
  const { stats, tpsHistory } = state;

  const progress = useMemo(() => {
    const pct = Math.min((stats.totalCellsPublished / TARGET_CELLS) * 100, 100);
    return pct;
  }, [stats.totalCellsPublished]);

  const remaining = TARGET_CELLS - stats.totalCellsPublished;
  const arrow = trendArrow(tpsHistory);

  return (
    <div className="p-4 flex flex-col gap-3">
      <div className="text-xs font-bold text-gray-400 tracking-wider">LIVE TPS</div>

      {/* TPS number */}
      <div className="flex items-baseline gap-2">
        <span className={`text-3xl font-bold font-mono ${tpsColorClass(stats.tps)}`}>
          {stats.tps.toLocaleString()}
        </span>
        <span className="text-lg text-gray-400">TPS</span>
        <span className={`text-lg ${tpsColorClass(stats.tps)}`}>{arrow}</span>
      </div>

      {/* Progress bar */}
      <div>
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>{stats.totalCellsPublished.toLocaleString()} / {TARGET_CELLS.toLocaleString()}</span>
          <span>{progress.toFixed(1)}%</span>
        </div>
        <div className="w-full h-2 bg-gray-800 rounded">
          <div
            className={`h-full rounded transition-all duration-300 ${progressColorClass(stats.tps)}`}
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* ETA */}
      <div className="text-xs text-gray-500">
        ETA to target: <span className="text-gray-300 font-mono">{formatEta(stats.tps, remaining)}</span>
      </div>

      {/* Sparkline */}
      <Sparkline data={tpsHistory} />

      {/* Batch stats */}
      <div className="flex gap-4 text-xs text-gray-500">
        <span>Batches: <span className="text-gray-300 font-mono">{stats.totalBatchesAnchored}</span></span>
        <span>Avg/batch: <span className="text-gray-300 font-mono">{stats.avgCellsPerBatch.toFixed(1)}</span></span>
      </div>
    </div>
  );
}

```
