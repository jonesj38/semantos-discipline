---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.843326+00:00
---

# archive/apps-mud/src/room-actor/atoms.ts

```ts
/**
 * Per-room atom bundle for the prompt-23 room-actor split.
 *
 * The legacy `RoomActor` held its room state, players, consumed-cell
 * set, DAG history, and event listeners as instance fields. The split
 * promotes them to atoms so each system module (combat, inventory,
 * door, movement, persister) can read/write a single source of truth
 * without holding a back-reference to the actor.
 *
 * Atoms are keyed per room id and registered lazily. `resetRoomAtoms`
 * is the test seam.
 */

import { atom, eventBus, type Atom, type EventBus } from '@semantos/state';

import type {
  MUDPlayer,
  PlayerId,
  RoomEvent,
  RoomId,
  RoomState,
} from '../types';

export interface RoomAtoms {
  roomId: RoomId;
  /** Authoritative room state — turn number, tiles, monsters, items, exits. */
  roomStateAtom: Atom<RoomState>;
  /** Players currently bound to this room, keyed by id. */
  playersAtom: Atom<Map<PlayerId, MUDPlayer>>;
  /** Cell ids that have been linearly consumed (treasure, keys, broken gear, slain monsters). */
  consumedCellsAtom: Atom<Set<string>>;
  /** Append-only DAG history of room state cell ids. */
  dagHistoryAtom: Atom<string[]>;
  /** Last serialized cell bytes (for prevCell chaining). */
  lastCellBytesAtom: Atom<Uint8Array | null>;
  /** Bus of every accepted RoomEvent — facade fans out to listeners. */
  eventsBus: EventBus<RoomEvent>;
}

const registry = new Map<RoomId, RoomAtoms>();

export interface CreateRoomAtomsArgs {
  roomId: RoomId;
  initialState: RoomState;
  initialCellBytes: Uint8Array | null;
}

/**
 * Get (or create) the atom bundle for a room id. Idempotent — repeat
 * calls return the same bundle so subscribers see the same instance.
 */
export function getRoomAtoms(args: CreateRoomAtomsArgs): RoomAtoms {
  const existing = registry.get(args.roomId);
  if (existing) return existing;

  const bundle: RoomAtoms = {
    roomId: args.roomId,
    roomStateAtom: atom<RoomState>(args.initialState),
    playersAtom: atom<Map<PlayerId, MUDPlayer>>(new Map()),
    consumedCellsAtom: atom<Set<string>>(new Set()),
    dagHistoryAtom: atom<string[]>([args.initialState.cellId]),
    lastCellBytesAtom: atom<Uint8Array | null>(args.initialCellBytes),
    eventsBus: eventBus<RoomEvent>(),
  };
  registry.set(args.roomId, bundle);
  return bundle;
}

/** Test helper — wipes the registry between cases. */
export function resetRoomAtoms(): void {
  registry.clear();
}

/** Drop a single room id from the registry (used on shutdown). */
export function disposeRoomAtoms(roomId: RoomId): void {
  registry.delete(roomId);
}

/** Read-only listing of currently registered room ids. */
export function listRoomIds(): RoomId[] {
  return Array.from(registry.keys());
}

```
