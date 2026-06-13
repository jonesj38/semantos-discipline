---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/game-events.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.781342+00:00
---

# archive/apps-poker-agent/src/game-loop/game-events.ts

```ts
/**
 * Per-game `GameEvent` bus + emit helper.
 *
 * Replaces the legacy callback injection. Callers subscribe to
 * `getGameEventBus(gameId).on(...)`. The facade still honours an
 * `onEvent` config callback by piping through this bus.
 */

import { eventBus, type EventBus } from '@semantos/state';

import type { GameEvent } from './types';

const buses = new Map<string, EventBus<GameEvent>>();

export function getGameEventBus(gameId: string): EventBus<GameEvent> {
  const existing = buses.get(gameId);
  if (existing) return existing;
  const bus = eventBus<GameEvent>();
  buses.set(gameId, bus);
  return bus;
}

export function resetGameEventBuses(): void {
  buses.clear();
}

export interface EmitGameEventArgs {
  gameId: string;
  matchId?: number;
  type: GameEvent['type'];
  handNumber: number;
  data: Record<string, unknown>;
}

/** Emit a fully-shaped `GameEvent` onto the per-game bus. */
export function emitGameEvent(args: EmitGameEventArgs): void {
  getGameEventBus(args.gameId).emit({
    type: args.type,
    matchId: args.matchId,
    gameId: args.gameId,
    handNumber: args.handNumber,
    ts: Date.now(),
    data: args.data,
  });
}

```
