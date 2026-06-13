---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/event-bus-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.839444+00:00
---

# archive/apps-mud/src/world-server/event-bus-bridge.ts

```ts
/**
 * EventBusBridge — fan-out from per-room event buses to per-player
 * connection listeners.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * The bridge subscribes a player to the event bus of *their current
 * room*. It is the responsibility of higher layers to call
 * `rebindPlayer()` after a cross-room transfer so the player keeps
 * receiving events from the correct room.
 *
 * Surface mirrors what the legacy `WorldServer.onPlayerEvent` exposed:
 *   - `subscribe(playerId, listener)` — returns an unsubscribe fn.
 *   - `rebindPlayer(playerId)` — re-attaches an existing listener
 *     to whichever room the session store now reports.
 *
 * Internally we keep two maps:
 *   - `listeners: Map<PlayerId, RoomEvent → void>` — the user's callback
 *   - `unsubs:    Map<PlayerId, () => void>`        — current actor's
 *                                                     `onEvent` cleanup
 *
 * Cleanup contract: `unsubscribe` calls the current actor's cleanup AND
 * forgets the listener. If a transfer interleaves with an unsubscribe,
 * the order is safe — `rebindPlayer` is a no-op for unknown players.
 *
 * Note (state-update side-effects): we attach via `RoomActor.onEvent`
 * which already uses subscribe-style callbacks — no `effect()` from
 * `@semantos/state` is involved here. (See spec §"Patterns from waves
 * 1+2" — avoid `effect()` for state-change-driven side-effects.)
 */

import type { PlayerId, RoomEvent } from '../types';

import type { PlayerSessionStore } from './player-session-store';
import type { RoomActorPool } from './room-actor-pool';

export type RoomEventListener = (event: RoomEvent) => void;

export class EventBusBridge {
  private readonly pool: RoomActorPool;
  private readonly sessions: PlayerSessionStore;
  private readonly listeners: Map<PlayerId, RoomEventListener>;
  private readonly unsubs: Map<PlayerId, () => void>;

  constructor(pool: RoomActorPool, sessions: PlayerSessionStore) {
    this.pool = pool;
    this.sessions = sessions;
    this.listeners = new Map();
    this.unsubs = new Map();
  }

  /**
   * Subscribe `playerId` to events from their current room.
   *
   * Returns an unsubscribe function. Calling unsubscribe is idempotent.
   *
   * If the player is not in any room (or the room actor is gone), the
   * listener is recorded but no actor subscription is made — calling
   * `rebindPlayer` later will attach it.
   */
  subscribe(playerId: PlayerId, listener: RoomEventListener): () => void {
    // Replace any prior subscription cleanly.
    this.unsubscribe(playerId);

    this.listeners.set(playerId, listener);
    this.attachToCurrentRoom(playerId);

    return () => this.unsubscribe(playerId);
  }

  /**
   * Re-attach `playerId`'s existing listener to whichever room the
   * session store now reports. No-op if the player has no listener
   * registered.
   *
   * Called by the cross-room-transfer flow.
   */
  rebindPlayer(playerId: PlayerId): void {
    if (!this.listeners.has(playerId)) return;
    const prevUnsub = this.unsubs.get(playerId);
    if (prevUnsub) {
      prevUnsub();
      this.unsubs.delete(playerId);
    }
    this.attachToCurrentRoom(playerId);
  }

  /** Clear every subscription. Called from `WorldServer.shutdown()`. */
  shutdown(): void {
    for (const unsub of this.unsubs.values()) unsub();
    this.unsubs.clear();
    this.listeners.clear();
  }

  // ── private ────────────────────────────────────────────────

  private attachToCurrentRoom(playerId: PlayerId): void {
    const listener = this.listeners.get(playerId);
    if (!listener) return;
    const roomId = this.sessions.getPlayerRoom(playerId);
    if (!roomId) return;
    const actor = this.pool.get(roomId);
    if (!actor) return;
    const unsub = actor.onEvent(listener);
    this.unsubs.set(playerId, unsub);
  }

  private unsubscribe(playerId: PlayerId): void {
    const unsub = this.unsubs.get(playerId);
    if (unsub) unsub();
    this.unsubs.delete(playerId);
    this.listeners.delete(playerId);
  }
}

```
