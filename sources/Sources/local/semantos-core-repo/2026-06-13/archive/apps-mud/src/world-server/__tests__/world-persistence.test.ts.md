---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/world-persistence.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.845121+00:00
---

# archive/apps-mud/src/world-server/__tests__/world-persistence.test.ts

```ts
/**
 * Tests for `world-persistence.ts` — config / topology IO.
 *
 * Uses an in-memory CellStore via the shared MemoryAdapter.
 */

import { describe, test, expect } from 'bun:test';

import { MemoryAdapter } from '../../../../../core/protocol-types/src/adapters/memory-adapter';
import { CellStore } from '../../../../../core/protocol-types/src/cell-store';
import type { PlayerSession, WorldConfig } from '../../types';
import {
  WORLD_CONFIG_PATH,
  WORLD_TOPOLOGY_PATH,
  loadTopology,
  loadWorldConfig,
  persistPlayerSession,
  persistTopology,
  persistWorldConfig,
  playerSessionPath,
  roomStatePath,
  type TopologySnapshot,
} from '../world-persistence';

function makeStore(): CellStore {
  return new CellStore(new MemoryAdapter());
}

const cfg: WorldConfig = {
  name: 'test',
  roomCount: 3,
  maxPlayersPerRoom: 4,
  pvpEnabled: false,
  startRoomId: 'tavern',
};

describe('world-persistence — paths', () => {
  test('canonical cell paths are stable', () => {
    expect(WORLD_CONFIG_PATH).toBe('mud/world/config');
    expect(WORLD_TOPOLOGY_PATH).toBe('mud/world/topology');
    expect(playerSessionPath('p1')).toBe('mud/players/p1/session');
    expect(roomStatePath('r1')).toBe('mud/rooms/r1/state');
  });
});

describe('world-persistence — config', () => {
  test('persistWorldConfig + loadWorldConfig round-trips', async () => {
    const store = makeStore();
    await persistWorldConfig(store, cfg);
    const loaded = await loadWorldConfig(store);
    expect(loaded).not.toBeNull();
    expect(loaded!.name).toBe('test');
    expect(loaded!.roomCount).toBe(3);
    expect(loaded!.startRoomId).toBe('tavern');
  });

  test('loadWorldConfig returns null when not persisted', async () => {
    const store = makeStore();
    expect(await loadWorldConfig(store)).toBeNull();
  });
});

describe('world-persistence — topology', () => {
  test('persistTopology + loadTopology round-trips', async () => {
    const store = makeStore();
    const topo: TopologySnapshot = {
      r1: { name: 'Tavern', description: 'cozy', exits: [
        { direction: 'e', targetRoomId: 'r2', locked: false },
      ]},
      r2: { name: 'Crypt', description: 'cold', exits: [
        { direction: 'w', targetRoomId: 'r1', locked: false },
      ]},
    };
    await persistTopology(store, topo);
    const loaded = await loadTopology(store);
    expect(loaded).toEqual(topo);
  });

  test('loadTopology returns null when not persisted', async () => {
    const store = makeStore();
    expect(await loadTopology(store)).toBeNull();
  });
});

describe('world-persistence — session', () => {
  test('persistPlayerSession writes a JSON cell at the canonical path', async () => {
    const store = makeStore();
    const session: PlayerSession = {
      sessionId: 's1',
      playerId: 'p1',
      playerName: 'alice',
      currentRoomId: 'tavern',
      connectedAt: 1234,
    };
    persistPlayerSession(store, 'p1', session);

    // Fire-and-forget — give the microtask queue a tick to flush.
    await new Promise(r => setTimeout(r, 5));

    const cell = await store.get(playerSessionPath('p1'));
    expect(cell).not.toBeNull();
    const parsed = JSON.parse(new TextDecoder().decode(cell!.payload));
    expect(parsed.sessionId).toBe('s1');
    expect(parsed.playerName).toBe('alice');
    expect(parsed.currentRoomId).toBe('tavern');
  });
});

```
