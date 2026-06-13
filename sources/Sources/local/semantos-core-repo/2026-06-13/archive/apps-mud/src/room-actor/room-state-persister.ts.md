---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/room-state-persister.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.842222+00:00
---

# archive/apps-mud/src/room-actor/room-state-persister.ts

```ts
/**
 * Room state persister — batched, non-blocking CellStore writes.
 *
 * The legacy actor called `cellStore.put(...)` synchronously inside
 * `commitState`. The split routes the same operation through an effect
 * atom: each commit pushes a `RoomStateSnapshot` into a counter-bumped
 * atom, and the effect subscriber drains the queue without blocking
 * the action loop.
 *
 * Persistence is fire-and-forget (the entity cell via GameCellEngine
 * remains the source of truth); CellStore is the versioned, Merkle-
 * chained DAG index for room state history. Errors are swallowed and
 * routed to a `console.warn` — bringing down a room because a write
 * failed would be worse than the lost index entry.
 */

import { atom, effect, set, type Atom } from '@semantos/state';

import type { CellStore } from '../../../../core/protocol-types/src/cell-store';
import { Linearity } from '../../../../core/protocol-types/src/constants';

import type { RoomId } from '../types';

export interface RoomStateSnapshot {
  cellId: string;
  roomId: RoomId;
  turn: number;
  occupants: string[];
  aliveMonsters: number;
  itemCount: number;
  previousCellId: string | null;
}

export interface PersisterHandle {
  /** Queue a snapshot for batched persistence. Non-blocking. */
  enqueue(snapshot: RoomStateSnapshot): void;
  /** Force-flush queued writes synchronously (test/shutdown helper). */
  flush(): Promise<void>;
  /** Stop draining and dispose internal subscriptions. */
  dispose(): void;
  /** Internal: the tick atom — exposed for tests. */
  tickAtom: Atom<number>;
}

export interface MakePersisterArgs {
  cellStore: CellStore;
  /** Optional override for the cell-store key — defaults to `mud/rooms/<id>/state`. */
  pathFor?: (roomId: RoomId) => string;
}

const defaultPath = (roomId: RoomId) => `mud/rooms/${roomId}/state`;

/**
 * Build a non-blocking persister backed by `effect`. Snapshots are
 * pushed into a side queue; the effect subscribes to a tick atom that
 * advances on each enqueue, and drains the queue without ever writing
 * back to the tracked atom (avoiding effect self-reentry).
 *
 * CellStore auto-chains prevStateHash from the previous version at
 * each path, so order matters — we never reorder.
 */
export function makeRoomStatePersister(
  args: MakePersisterArgs,
): PersisterHandle {
  const tickAtom = atom(0);
  const queue: RoomStateSnapshot[] = [];
  const pendingWrites: Promise<unknown>[] = [];
  const path = args.pathFor ?? defaultPath;
  let disposed = false;

  const dispose = effect((track) => {
    track(tickAtom); // depend on the tick atom — fires on each enqueue
    if (disposed) return;
    while (queue.length > 0) {
      const snapshot = queue.shift()!;
      const bytes = encodeSnapshot(snapshot);
      const p = Promise.resolve(
        args.cellStore.put(path(snapshot.roomId), bytes, {
          linearity: Linearity.RELEVANT,
        }),
      ).catch((err: unknown) => {
        // eslint-disable-next-line no-console
        console.warn(`[room-state-persister] put failed: ${(err as Error).message}`);
      });
      pendingWrites.push(p);
    }
  });

  return {
    enqueue(snapshot) {
      if (disposed) return;
      queue.push(snapshot);
      set(tickAtom, tickAtom.value + 1);
    },
    async flush() {
      await Promise.all(pendingWrites.splice(0, pendingWrites.length));
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      dispose();
    },
    tickAtom,
  };
}

function encodeSnapshot(snapshot: RoomStateSnapshot): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(snapshot));
}

```
