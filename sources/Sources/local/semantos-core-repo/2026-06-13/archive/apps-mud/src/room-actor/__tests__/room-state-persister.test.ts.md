---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/room-state-persister.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.848082+00:00
---

# archive/apps-mud/src/room-actor/__tests__/room-state-persister.test.ts

```ts
/**
 * Persister tests — verify that snapshots are forwarded to the
 * underlying CellStore via batched effect-driven writes, and that
 * `flush()` waits for pending puts.
 */

import { describe, expect, test } from 'bun:test';

import {
  makeRoomStatePersister,
  type RoomStateSnapshot,
} from '../room-state-persister';

import type { CellStore } from '../../../../../core/protocol-types/src/cell-store';

interface RecordedPut {
  path: string;
  bytes: Uint8Array;
}

function fakeCellStore(): { store: CellStore; puts: RecordedPut[] } {
  const puts: RecordedPut[] = [];
  const store = {
    put(path: string, bytes: Uint8Array): Promise<{ versionId: string }> {
      puts.push({ path, bytes });
      return Promise.resolve({ versionId: `v${puts.length}` });
    },
    get: () => Promise.resolve(null),
    history: () => Promise.resolve([]),
    verify: () => Promise.resolve(true),
  } as unknown as CellStore;
  return { store, puts };
}

function snapshot(turn: number): RoomStateSnapshot {
  return {
    cellId: `c-${turn}`,
    roomId: 'r1',
    turn,
    occupants: [],
    aliveMonsters: 0,
    itemCount: 0,
    previousCellId: turn > 0 ? `c-${turn - 1}` : null,
  };
}

describe('makeRoomStatePersister', () => {
  test('enqueued snapshots are forwarded to CellStore', async () => {
    const { store, puts } = fakeCellStore();
    const persister = makeRoomStatePersister({ cellStore: store });

    persister.enqueue(snapshot(1));
    persister.enqueue(snapshot(2));
    persister.enqueue(snapshot(3));
    await persister.flush();

    expect(puts).toHaveLength(3);
    expect(puts[0].path).toBe('mud/rooms/r1/state');
    const decoded = JSON.parse(new TextDecoder().decode(puts[0].bytes));
    expect(decoded.turn).toBe(1);

    persister.dispose();
  });

  test('dispose stops accepting new snapshots', async () => {
    const { store, puts } = fakeCellStore();
    const persister = makeRoomStatePersister({ cellStore: store });

    persister.enqueue(snapshot(1));
    await persister.flush();
    expect(puts).toHaveLength(1);

    persister.dispose();
    persister.enqueue(snapshot(2)); // should be ignored
    await persister.flush();
    expect(puts).toHaveLength(1);
  });

  test('custom path function is honored', async () => {
    const { store, puts } = fakeCellStore();
    const persister = makeRoomStatePersister({
      cellStore: store,
      pathFor: (id) => `custom/${id}`,
    });

    persister.enqueue(snapshot(1));
    await persister.flush();

    expect(puts[0].path).toBe('custom/r1');
    persister.dispose();
  });
});

```
