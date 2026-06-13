---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/tx-stats-collector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.782270+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/tx-stats-collector.ts

```ts
/**
 * Stats collector — atom-backed aggregator for `BroadcastEvent`s
 * published by the engine on every tx build/broadcast.
 *
 * The previous engine kept stats in mutable class fields. Moving
 * them onto an atom + event bus means dashboards can subscribe
 * without polling, and tests can drive stats by emitting events
 * directly (no need to spin up the engine).
 *
 * Per the prompt-18 spec, both fire-and-forget and synchronous
 * modes emit `'broadcast'` events with their respective `buildMs`
 * + `broadcastMs` values.
 */

import { atom, eventBus, get, set, type Atom, type EventBus } from '@semantos/state';

import type { BroadcastEvent } from './types';

export interface DirectBroadcastStats {
  totalBroadcast: number;
  totalBuildMs: number;
  totalBroadcastMs: number;
  errors: string[];
}

const INITIAL_STATS: DirectBroadcastStats = {
  totalBroadcast: 0,
  totalBuildMs: 0,
  totalBroadcastMs: 0,
  errors: [],
};

const eventBusRegistry = new Map<string, EventBus<BroadcastEvent>>();
const statsAtomRegistry = new Map<string, Atom<DirectBroadcastStats>>();

export function getDirectBroadcastEvents(engineId: string): EventBus<BroadcastEvent> {
  const existing = eventBusRegistry.get(engineId);
  if (existing) return existing;
  const bus = eventBus<BroadcastEvent>();
  eventBusRegistry.set(engineId, bus);
  return bus;
}

export function getDirectBroadcastStatsAtom(
  engineId: string,
): Atom<DirectBroadcastStats> {
  const existing = statsAtomRegistry.get(engineId);
  if (existing) return existing;
  const a = atom<DirectBroadcastStats>({ ...INITIAL_STATS, errors: [] });
  statsAtomRegistry.set(engineId, a);
  return a;
}

export function resetDirectBroadcastStats(): void {
  eventBusRegistry.clear();
  statsAtomRegistry.clear();
}

export interface StatsCollectorHandle {
  /** Tear down the bus subscription. */
  dispose(): void;
}

/**
 * Wire the stats atom to the event bus. Returns a `dispose()` so
 * the facade or tests can detach. Idempotent — calling twice for
 * the same engineId returns the same handle but only one
 * subscription is kept.
 */
export function attachStatsCollector(engineId: string): StatsCollectorHandle {
  const bus = getDirectBroadcastEvents(engineId);
  const stats = getDirectBroadcastStatsAtom(engineId);

  const dispose = bus.on((event) => {
    const current = get(stats);
    if (event.type === 'broadcast') {
      set(stats, {
        ...current,
        totalBroadcast: current.totalBroadcast + 1,
        totalBuildMs: current.totalBuildMs + event.buildMs,
        totalBroadcastMs: current.totalBroadcastMs + event.broadcastMs,
      });
    } else if (event.type === 'broadcast-error') {
      set(stats, {
        ...current,
        errors: [...current.errors, `${event.label}: ${event.message}`],
      });
    }
  });
  return { dispose };
}

export interface SelectedStats {
  totalBroadcast: number;
  avgBuildMs: number;
  avgBroadcastMs: number;
  txPerSec: number;
  errors: string[];
}

/**
 * Atom-driven selector for the engine's `getStats()` method. The
 * facade reads here instead of mutating private fields.
 */
export function selectStats(engineId: string): SelectedStats {
  const s = get(getDirectBroadcastStatsAtom(engineId));
  const avgBuild = s.totalBroadcast > 0 ? s.totalBuildMs / s.totalBroadcast : 0;
  const avgBroadcast =
    s.totalBroadcast > 0 ? s.totalBroadcastMs / s.totalBroadcast : 0;
  const totalMs = s.totalBuildMs + s.totalBroadcastMs;
  const txPerSec = totalMs > 0 ? (s.totalBroadcast / totalMs) * 1000 : 0;
  return {
    totalBroadcast: s.totalBroadcast,
    avgBuildMs: Math.round(avgBuild),
    avgBroadcastMs: Math.round(avgBroadcast),
    txPerSec: parseFloat(txPerSec.toFixed(2)),
    errors: [...s.errors],
  };
}

```
