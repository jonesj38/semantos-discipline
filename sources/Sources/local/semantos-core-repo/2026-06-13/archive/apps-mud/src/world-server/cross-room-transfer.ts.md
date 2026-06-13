---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/cross-room-transfer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.839720+00:00
---

# archive/apps-mud/src/world-server/cross-room-transfer.ts

```ts
/**
 * Cross-room-transfer — atomic player exit-from + entry-into flow.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * A transfer is the composition of three steps:
 *   1. Look up the source + target `RoomActor` via the pool.
 *   2. `removePlayer()` from the source actor (returns the player snapshot).
 *   3. Choose a free position in the target, mutate the player's
 *      `position` + `roomId`, then `addPlayer()` on the target actor.
 *   4. Re-bind the `PlayerSessionStore` to the target room.
 *
 * The whole thing is best-effort atomic — if any step short-circuits
 * (room missing, player not present), `transferPlayer` returns `false`
 * and leaves the world in a consistent state (the player remains in
 * their original room).
 *
 * No state is owned by this module; it operates on the pool + session
 * store passed in.
 */

import type { PlayerId, RoomId } from '../types';

import { findFreePosition } from './internal-types';
import type { PlayerSessionStore } from './player-session-store';
import type { RoomActorPool } from './room-actor-pool';

/**
 * Transfer `playerId` from their current room to `targetRoomId`.
 *
 * Returns true on success, false if any pre-condition fails.
 */
export function transferPlayer(
  pool: RoomActorPool,
  sessions: PlayerSessionStore,
  playerId: PlayerId,
  targetRoomId: RoomId,
): boolean {
  const currentRoomId = sessions.getPlayerRoom(playerId);
  if (!currentRoomId) return false;
  if (currentRoomId === targetRoomId) return true; // already there

  const fromActor = pool.get(currentRoomId);
  const toActor = pool.get(targetRoomId);
  if (!fromActor || !toActor) return false;

  const player = fromActor.removePlayer(playerId);
  if (!player) return false;

  // Place player at a free position in the target room.
  const targetState = toActor.getState();
  player.position = findFreePosition(targetState);
  player.roomId = targetRoomId;

  toActor.addPlayer(player);
  sessions.rebind(playerId, targetRoomId);

  return true;
}

```
