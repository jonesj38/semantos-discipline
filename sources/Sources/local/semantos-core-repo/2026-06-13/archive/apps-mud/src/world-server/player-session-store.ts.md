---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/player-session-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.837991+00:00
---

# archive/apps-mud/src/world-server/player-session-store.ts

```ts
/**
 * PlayerSessionStore — in-memory map of player sessions and their
 * current-room binding.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * Two indexes are tracked together:
 *   - `sessions: Map<SessionId, PlayerSession>`
 *   - `playerRoomMap: Map<PlayerId, RoomId>` (current room binding)
 *
 * The two are kept consistent via the `bind()` / `rebind()` / `unbind()`
 * surface — never mutate the maps directly.
 *
 * Session-id generation is monotonic (`session-0`, `session-1`, ...) and
 * survives no process restart (the store is rebuilt on every world boot).
 */

import type { PlayerId, PlayerSession, RoomId, SessionId } from '../types';

export class PlayerSessionStore {
  private readonly sessions: Map<SessionId, PlayerSession>;
  private readonly playerRoomMap: Map<PlayerId, RoomId>;
  private nextSessionId = 0;

  constructor() {
    this.sessions = new Map();
    this.playerRoomMap = new Map();
  }

  /** Mint a fresh session id (monotonic). */
  mintSessionId(): SessionId {
    return `session-${this.nextSessionId++}`;
  }

  /** Compose a player id from a session id (matches legacy convention). */
  playerIdFor(sessionId: SessionId): PlayerId {
    return `player-${sessionId}`;
  }

  /**
   * Register a fresh session and bind its player to `roomId`.
   *
   * Throws if `session.sessionId` is already in use — caller mints a new
   * one via `mintSessionId()`.
   */
  bind(session: PlayerSession): void {
    if (this.sessions.has(session.sessionId)) {
      throw new Error(`Session ${session.sessionId} already bound`);
    }
    this.sessions.set(session.sessionId, session);
    this.playerRoomMap.set(session.playerId, session.currentRoomId);
  }

  /**
   * Atomic re-bind: change the player's current-room binding AND the
   * `currentRoomId` field on every session that owns this player. Used
   * by the cross-room-transfer flow to keep both indexes in lockstep.
   *
   * Returns true if the player had an existing binding.
   */
  rebind(playerId: PlayerId, targetRoomId: RoomId): boolean {
    if (!this.playerRoomMap.has(playerId)) return false;
    this.playerRoomMap.set(playerId, targetRoomId);
    for (const session of this.sessions.values()) {
      if (session.playerId === playerId) {
        session.currentRoomId = targetRoomId;
      }
    }
    return true;
  }

  /**
   * Drop every session for `playerId` and clear the player→room
   * binding. No-op if the player is not in the store.
   */
  unbind(playerId: PlayerId): void {
    this.playerRoomMap.delete(playerId);
    for (const [sid, session] of this.sessions) {
      if (session.playerId === playerId) this.sessions.delete(sid);
    }
  }

  // ── Look-ups ───────────────────────────────────────────────

  getSession(sessionId: SessionId): PlayerSession | undefined {
    return this.sessions.get(sessionId);
  }

  getPlayerRoom(playerId: PlayerId): RoomId | undefined {
    return this.playerRoomMap.get(playerId);
  }

  /** All sessions in insertion order. */
  allSessions(): PlayerSession[] {
    return [...this.sessions.values()];
  }

  /** Number of bound players (one entry per active player). */
  playerCount(): number {
    return this.playerRoomMap.size;
  }
}

```
