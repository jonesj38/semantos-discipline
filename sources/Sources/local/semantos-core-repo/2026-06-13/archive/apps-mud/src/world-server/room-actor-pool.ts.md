---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/room-actor-pool.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.838884+00:00
---

# archive/apps-mud/src/world-server/room-actor-pool.ts

```ts
/**
 * RoomActorPool — registry of `RoomActor` instances keyed by `RoomId`.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * Responsibilities:
 *   - Register and look up actors by room id.
 *   - Start/stop the entire pool (each actor runs its own async loop).
 *   - Iterate actors / room-ids for higher-level supervisors.
 *
 * Non-responsibilities:
 *   - Generating room state (see `world-generator.ts`).
 *   - Player session bookkeeping (see `player-session-store.ts`).
 *   - Cross-room transfers (see `cross-room-transfer.ts`).
 *
 * The pool is a thin wrapper around a `Map<RoomId, RoomActor>` — kept
 * as its own module because the responsibilities listed above will
 * grow (room restart, actor replacement, hot-rebind) and the map needs
 * a single canonical home.
 */

import type { RoomActor } from '../room-actor';
import type { RoomId } from '../types';

export class RoomActorPool {
  private readonly actors: Map<RoomId, RoomActor>;

  constructor() {
    this.actors = new Map();
  }

  /** Register an actor for `roomId`. Replaces any prior actor at that id. */
  register(roomId: RoomId, actor: RoomActor): void {
    this.actors.set(roomId, actor);
  }

  /**
   * Replace the actor at `roomId` (e.g. after a restart). The previous
   * actor is `stop()`-ed first to ensure its async loop exits before
   * the new one takes over. Returns the replaced actor or `undefined`
   * if no actor was registered.
   */
  replace(roomId: RoomId, actor: RoomActor): RoomActor | undefined {
    const prev = this.actors.get(roomId);
    if (prev) prev.stop();
    this.actors.set(roomId, actor);
    return prev;
  }

  /** Remove (and stop) the actor at `roomId`. Returns true if removed. */
  remove(roomId: RoomId): boolean {
    const actor = this.actors.get(roomId);
    if (!actor) return false;
    actor.stop();
    return this.actors.delete(roomId);
  }

  /** Look up the actor for `roomId`. */
  get(roomId: RoomId): RoomActor | undefined {
    return this.actors.get(roomId);
  }

  /** Whether the pool has an actor for `roomId`. */
  has(roomId: RoomId): boolean {
    return this.actors.has(roomId);
  }

  /** All registered room ids in insertion order. */
  ids(): RoomId[] {
    return [...this.actors.keys()];
  }

  /** Iterate over all `[roomId, actor]` entries. */
  entries(): IterableIterator<[RoomId, RoomActor]> {
    return this.actors.entries();
  }

  /** Iterate over actors only. */
  values(): IterableIterator<RoomActor> {
    return this.actors.values();
  }

  /** Number of registered rooms. */
  get size(): number {
    return this.actors.size;
  }

  /**
   * Start every actor's async processing loop. Fire-and-forget — each
   * actor runs independently and returns a promise that the pool does
   * not await.
   */
  startAll(): void {
    for (const actor of this.actors.values()) {
      // fire-and-forget: each RoomActor.start() is its own async loop
      void actor.start();
    }
  }

  /** Stop every actor's async processing loop. */
  stopAll(): void {
    for (const actor of this.actors.values()) {
      actor.stop();
    }
  }
}

```
