---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/StableThreads.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.963225+00:00
---

# archive/apps-loom-react/src/helm/StableThreads.tsx

```tsx
/**
 * StableThreads — DB2 of the Dimensional Second Brain workstream.
 *
 * Renders the top-N stable threads from the Pask kernel as a sparse
 * strip above the AttentionSurface. Refreshes every stability_window_ms
 * (60s). Clicking a thread sets it as the active context for the
 * AttentionEngine's graph-proximity factor (DB5).
 */

import React, { useState, useEffect, useRef } from 'react';
import type { PaskGraph, PaskStableThread } from '../services/PaskGraph';

export interface StableThreadsProps {
  paskGraph: PaskGraph;
  onThreadSelect: (cellId: string | null) => void;
  activeContextCellId?: string | null;
  className?: string;
}

type SourceFilter = 'all' | 'helm' | 'obs' | 'nx' | 'ingest' | 'oddjobz';

const REFRESH_MS = 60_000;
const MIN_INTERACTIONS_DISPLAY = 3;

function sourceLabel(cellId: string): string {
  if (cellId.startsWith('helm:')) return 'helm';
  if (cellId.startsWith('obs:')) return 'vault';
  if (cellId.startsWith('nx:')) return 'notion';
  return cellId.split(':')[0] ?? '?';
}

function humanLabel(cellId: string): string {
  // Strip the namespace prefix for display: 'helm:item:abc' → 'abc'
  const parts = cellId.split(':');
  if (parts.length >= 3) return parts.slice(2).join(':');
  if (parts.length === 2) return parts[1];
  return cellId;
}

function HState({ value }: { value: number }) {
  const abs = Math.abs(value);
  const cls = abs < 0.005 ? 'text-green-400' : abs < 0.02 ? 'text-yellow-400' : 'text-zinc-400';
  return <span className={`font-mono text-xs ${cls}`}>{value.toFixed(3)}</span>;
}

export function StableThreads({
  paskGraph,
  onThreadSelect,
  activeContextCellId,
  className = '',
}: StableThreadsProps) {
  const [threads, setThreads] = useState<PaskStableThread[]>([]);
  const [filter, setFilter] = useState<SourceFilter>('all');
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    function refresh() {
      const prefix = filter === 'all' ? undefined : `${filter}:`;
      const raw = paskGraph.stableThreads({ limit: 20, sourcePrefix: prefix });
      setThreads(raw.filter(t => t.trafficCount >= MIN_INTERACTIONS_DISPLAY));
    }

    refresh();
    timerRef.current = setInterval(refresh, REFRESH_MS);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [paskGraph, filter]);

  // Don't render until at least one stable thread exists — avoids a distracting
  // empty strip during cold start.
  if (threads.length === 0) return null;

  return (
    <div className={`stable-threads-strip border-b border-zinc-800 bg-zinc-950 px-3 py-2 ${className}`}>
      <div className="flex items-center gap-2 mb-1.5">
        <span className="text-xs font-medium text-zinc-400 uppercase tracking-wider">Threads</span>
        <div className="flex gap-1 ml-auto">
          {(['all', 'helm', 'obs', 'nx', 'ingest', 'oddjobz'] as SourceFilter[]).map(s => (
            <button
              key={s}
              onClick={() => setFilter(s)}
              className={`px-1.5 py-0.5 rounded text-xs transition-colors ${
                filter === s
                  ? 'bg-zinc-700 text-zinc-100'
                  : 'text-zinc-500 hover:text-zinc-300'
              }`}
            >
              {s === 'obs' ? 'vault' : s === 'nx' ? 'notion' : s}
            </button>
          ))}
        </div>
      </div>

      <ol className="flex flex-wrap gap-1">
        {threads.map(t => {
          const isActive = activeContextCellId === t.cellId;
          return (
            <li key={t.cellId} className="contents">
              <button
                title={t.cellId}
                onClick={() => onThreadSelect(isActive ? null : t.cellId)}
                className={`
                  flex items-center gap-1.5 px-2 py-1 rounded text-xs transition-colors
                  ${isActive
                    ? 'bg-indigo-600 text-white'
                    : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700 hover:text-zinc-100'}
                `}
              >
                <span className="max-w-[140px] truncate">{humanLabel(t.cellId)}</span>
                <span className="text-zinc-500 text-[10px] shrink-0">
                  {sourceLabel(t.cellId)}
                </span>
                <span className="text-zinc-600 text-[10px] shrink-0">n={t.trafficCount}</span>
                <HState value={t.hState} />
              </button>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

```
