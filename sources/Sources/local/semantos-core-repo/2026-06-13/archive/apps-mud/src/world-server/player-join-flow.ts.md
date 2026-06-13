---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/player-join-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.837710+00:00
---

# archive/apps-mud/src/world-server/player-join-flow.ts

```ts
/**
 * Player-join-flow — create a player, mint a session, place them in
 * the start room.
 *
 * Refactor 24 / split of `world-server.ts`. Extracted so the facade
 * doesn't carry a 60-LOC method just for entity creation + binding.
 *
 * Steps:
 *   1. Mint a session id and the matching player id.
 *   2. Create the player CHARACTER cell (RELEVANT, owned by PLAYER_OWNER).
 *   3. Create the starting dagger ITEM cell (AFFINE, owned by PLAYER_OWNER).
 *   4. Pick a free position in the start room.
 *   5. Build the `MUDPlayer` snapshot + the `PlayerSession` record.
 *   6. Bind into the session store, add to the start-room actor, persist
 *      the session cell (fire-and-forget).
 */

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import { GameEntityType } from '../../../../packages/game-sdk/src/types';
import type { CellStore } from '../../../../core/protocol-types/src/cell-store';
import { ITEM_TEMPLATES } from '../../../../packages/games/src/dungeon/types';
import type { DungeonItem } from '../../../../packages/games/src/dungeon/types';
import type { MUDPlayer, PlayerSession, WorldConfig } from '../types';
import { XP_PER_LEVEL } from '../types';

import {
  AFFINE,
  PLAYER_OWNER,
  RELEVANT,
  findFreePosition,
} from './internal-types';
import type { PlayerSessionStore } from './player-session-store';
import type { RoomActorPool } from './room-actor-pool';
import { persistPlayerSession } from './world-persistence';

export interface JoinResult {
  session: PlayerSession;
  player: MUDPlayer;
}

/**
 * Run the full player-join flow. Throws if the configured start room
 * is missing from the pool.
 */
export function joinWorld(
  playerName: string,
  ctx: {
    cellEngine: GameCellEngine;
    cellStore: CellStore;
    pool: RoomActorPool;
    sessions: PlayerSessionStore;
    config: WorldConfig;
  },
): JoinResult {
  const sessionId = ctx.sessions.mintSessionId();
  const playerId = ctx.sessions.playerIdFor(sessionId);

  // Player CHARACTER cell — RELEVANT (non-consumable identity)
  const playerEntity = ctx.cellEngine.createEntity({
    entityType: GameEntityType.CHARACTER,
    ownerId: PLAYER_OWNER,
    linearity: RELEVANT,
    metadata: { domain: 'mud-player', name: playerName },
    state: 'alive',
  });

  // Starting dagger — AFFINE (player-owned weapon)
  const daggerTemplate = ITEM_TEMPLATES.dagger;
  const daggerEntity = ctx.cellEngine.createEntity({
    entityType: GameEntityType.ITEM,
    ownerId: PLAYER_OWNER,
    linearity: AFFINE,
    metadata: { domain: 'mud-item', ...daggerTemplate },
    state: 'equipped',
  });

  const startingWeapon: DungeonItem = {
    entity: daggerEntity,
    name: daggerTemplate.name,
    category: 'weapon',
    position: { x: 0, y: 0 },
    damage: daggerTemplate.damage,
    durability: daggerTemplate.durability,
  };

  const startActor = ctx.pool.get(ctx.config.startRoomId);
  if (!startActor) {
    throw new Error(`Start room ${ctx.config.startRoomId} not registered`);
  }
  const startState = startActor.getState();
  const pos = findFreePosition(startState);

  const player: MUDPlayer = {
    id: playerId,
    entity: playerEntity,
    name: playerName,
    position: pos,
    hp: 30,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: XP_PER_LEVEL,
    gold: 0,
    inventory: [startingWeapon],
    equippedWeapon: startingWeapon,
    equippedArmor: null,
    roomId: ctx.config.startRoomId,
  };

  const session: PlayerSession = {
    sessionId,
    playerId,
    playerName,
    currentRoomId: ctx.config.startRoomId,
    connectedAt: Date.now(),
  };

  ctx.sessions.bind(session);
  startActor.addPlayer(player);
  persistPlayerSession(ctx.cellStore, playerId, session);

  return { session, player };
}

```
