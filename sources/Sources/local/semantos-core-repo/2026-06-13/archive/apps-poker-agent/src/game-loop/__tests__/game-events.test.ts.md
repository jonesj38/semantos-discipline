---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/game-events.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.805544+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/game-events.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  emitGameEvent,
  getGameEventBus,
  resetGameEventBuses,
} from '../game-events';
import type { GameEvent } from '../types';

afterEach(() => resetGameEventBuses());

describe('game-events', () => {
  test('1. emit + on round-trips a fully-shaped GameEvent', () => {
    const captured: GameEvent[] = [];
    getGameEventBus('g1').on((e) => captured.push(e));
    emitGameEvent({
      gameId: 'g1',
      type: 'hand-start',
      handNumber: 5,
      data: { dealer: 'A' },
    });
    expect(captured).toHaveLength(1);
    expect(captured[0].type).toBe('hand-start');
    expect(captured[0].handNumber).toBe(5);
    expect(captured[0].data).toEqual({ dealer: 'A' });
    expect(typeof captured[0].ts).toBe('number');
  });

  test('2. distinct gameIds keep buses isolated', () => {
    const a: GameEvent[] = [];
    const b: GameEvent[] = [];
    getGameEventBus('g1').on((e) => a.push(e));
    getGameEventBus('g2').on((e) => b.push(e));
    emitGameEvent({ gameId: 'g1', type: 'phase', handNumber: 1, data: {} });
    expect(a.length).toBe(1);
    expect(b.length).toBe(0);
  });

  test('3. matchId passes through when set', () => {
    const captured: GameEvent[] = [];
    getGameEventBus('g1').on((e) => captured.push(e));
    emitGameEvent({
      gameId: 'g1',
      matchId: 42,
      type: 'tx',
      handNumber: 1,
      data: {},
    });
    expect(captured[0].matchId).toBe(42);
  });

  test('4. resetGameEventBuses wipes the registry', () => {
    let count = 0;
    getGameEventBus('g1').on(() => count++);
    resetGameEventBuses();
    emitGameEvent({ gameId: 'g1', type: 'phase', handNumber: 1, data: {} });
    expect(count).toBe(0);
  });
});

```
