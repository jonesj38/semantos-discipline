---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/world-generator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.837149+00:00
---

# archive/apps-mud/src/world-server/world-generator.ts

```ts
/**
 * World-generator — pure-ish layout builder.
 *
 * Generates an initial dungeon: an array of `RoomState` snapshots and a
 * graph of `RoomExit` edges between them. The generator creates the
 * supporting cell entities (rooms, monsters, items) via the supplied
 * `GameCellEngine`, but it does NOT spin up `RoomActor` instances; that
 * is the room-actor-pool's job.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * Inputs:
 *   - `cellEngine` — produces cells for room/monster/item entities
 *   - `config`     — room count + start-room id (from `WorldConfig`)
 *
 * Outputs (one per room):
 *   - `state` — fully-populated `RoomState`
 *   - `cellBytes` — initial bytes of the room cell (handed straight to
 *     the room-actor for DAG-chaining)
 *
 * Cross-room exits are added as a second pass once all rooms exist.
 *
 * The generator is deliberately stateless — repeated calls with the
 * same engine produce independent worlds.
 */

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import { GameEntityType } from '../../../../packages/game-sdk/src/types';
import {
  generateFloor,
  randomRoomPosition,
} from '../../../../packages/games/src/dungeon/map-gen';
import {
  MONSTER_TYPES,
  ITEM_TEMPLATES,
  FLOOR_MONSTERS,
  posKey,
} from '../../../../packages/games/src/dungeon/types';
import type {
  DungeonItem,
  Monster,
} from '../../../../packages/games/src/dungeon/types';
import type { RoomId, RoomState, WorldConfig } from '../types';

import {
  AFFINE,
  LINEAR,
  RELEVANT,
  WORLD_OWNER,
  getItemPool,
} from './internal-types';

// ── Stock content tables ───────────────────────────────────────

export const ROOM_NAMES: readonly string[] = [
  'Tavern', 'Dark Corridor', 'Armory', 'Library', 'Dungeon Cell',
  'Guard Room', 'Throne Room', 'Crypt', 'Sewer Passage', 'Alchemy Lab',
  'Barracks', 'Treasury', 'Temple', 'Prison', 'Forge',
  'Gallery', 'Kitchen', 'Wine Cellar', 'Tower Base', 'Secret Chamber',
];

export const ROOM_DESCRIPTIONS: readonly string[] = [
  'A warm room with a crackling fireplace.',
  'A damp, narrow passage. Water drips from the ceiling.',
  'Weapons and armor line the walls.',
  'Dusty shelves overflow with ancient tomes.',
  'Iron bars and cold stone. Something scratched the walls.',
  'A sturdy room. A guard post, long abandoned.',
  'Faded tapestries hang from high walls.',
  'Stone coffins rest in alcoves. The air is still.',
  'The smell is overwhelming. Something moves in the dark.',
  'Glass vials and strange apparatus cover the tables.',
  'Rows of bunks. Armor stands in the corner.',
  'Gold glints in the torchlight.',
  'An altar stands at the center. Candles flicker.',
  'The iron door creaks. Chains hang from the walls.',
  'The heat of the furnace warms the room.',
  'Paintings of forgotten lords watch you pass.',
  'Pots and pans. A rat scurries under the table.',
  'Bottles line the racks. Some are very old.',
  'Spiral stairs lead up into darkness.',
  'A hidden room behind a false wall.',
];

// ── Outputs ────────────────────────────────────────────────────

/** Result of generating a single room — used to seed a `RoomActor`. */
export interface GeneratedRoom {
  roomId: RoomId;
  state: RoomState;
  /** Initial cell bytes for the room's structure cell. */
  cellBytes: Uint8Array;
}

/** Choose the room id for index `i` — first room is the start room. */
export function roomIdAt(index: number, startRoomId: RoomId): RoomId {
  return index === 0 ? startRoomId : `room-${index}`;
}

// ── Generator ──────────────────────────────────────────────────

/**
 * Build `config.roomCount` rooms with monsters + items.
 *
 * Returns one `GeneratedRoom` per room in canonical order; exits are
 * NOT yet wired — the caller follows up with `wireRoomExits()`.
 */
export function generateWorldRooms(
  cellEngine: GameCellEngine,
  config: WorldConfig,
): GeneratedRoom[] {
  const rooms: GeneratedRoom[] = [];

  for (let i = 0; i < config.roomCount; i++) {
    const roomId = roomIdAt(i, config.startRoomId);

    const generated = generateFloor(Math.floor(i / 5), 5, 30, 15);
    const tiles = generated.tiles;

    const floorLevel = Math.floor(i / 4);
    const monsterPool = FLOOR_MONSTERS[Math.min(floorLevel, FLOOR_MONSTERS.length - 1)];
    const monsters: Monster[] = [];
    const items: DungeonItem[] = [];
    const occupied = new Set<string>();

    occupied.add(posKey(generated.playerStart));

    // Monsters: 1-3 per room (none in the start room)
    if (i > 0) {
      const monsterCount = 1 + Math.floor(Math.random() * 3);
      for (let m = 0; m < monsterCount; m++) {
        const room = generated.rooms[Math.floor(Math.random() * generated.rooms.length)];
        const pos = randomRoomPosition(room, tiles, occupied);
        if (!pos) continue;
        occupied.add(posKey(pos));

        const typeKey = monsterPool[Math.floor(Math.random() * monsterPool.length)];
        const monsterType = MONSTER_TYPES[typeKey];
        const entity = cellEngine.createEntity({
          entityType: GameEntityType.CHARACTER,
          ownerId: WORLD_OWNER,
          linearity: AFFINE,
          metadata: { domain: 'mud-monster', monsterType: typeKey, roomId },
          state: 'alive',
        });
        monsters.push({ entity, type: monsterType, hp: monsterType.hp, position: pos });
      }
    }

    // Items: 0-2 per room
    const itemCount = Math.floor(Math.random() * 3);
    const itemPool = getItemPool(floorLevel);
    for (let j = 0; j < itemCount; j++) {
      const room = generated.rooms[Math.floor(Math.random() * generated.rooms.length)];
      const pos = randomRoomPosition(room, tiles, occupied);
      if (!pos) continue;
      occupied.add(posKey(pos));

      const templateKey = itemPool[Math.floor(Math.random() * itemPool.length)];
      const template = ITEM_TEMPLATES[templateKey];
      const linearity = (template.category === 'weapon' || template.category === 'armor') ? AFFINE : LINEAR;

      const entity = cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: WORLD_OWNER,
        linearity,
        metadata: { domain: 'mud-item', ...template },
        state: 'on-ground',
      });
      items.push({
        entity,
        name: template.name,
        category: template.category,
        position: pos,
        damage: template.damage,
        defense: template.defense,
        healAmount: template.healAmount,
        durability: template.durability,
        value: template.value,
      });
    }

    // Room structure cell (RELEVANT — non-consumable)
    const roomEntity = cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: WORLD_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'mud-room',
        roomId,
        name: ROOM_NAMES[i % ROOM_NAMES.length],
        monsters: monsters.length,
        items: items.length,
      },
      state: 'active',
    });

    const state: RoomState = {
      cellId: roomEntity.id,
      roomId,
      name: ROOM_NAMES[i % ROOM_NAMES.length],
      description: ROOM_DESCRIPTIONS[i % ROOM_DESCRIPTIONS.length],
      width: tiles[0].length,
      height: tiles.length,
      tiles: tiles.map(row => [...row]),
      occupants: [],
      monsters,
      items,
      exits: [],
      doorLocks: new Map(),
      turnNumber: 0,
      previousCellId: null,
    };

    rooms.push({ roomId, state, cellBytes: roomEntity.cell });
  }

  return rooms;
}

/**
 * Wire east/west and the small set of north/south branches between the
 * generated rooms — pure mutation of the `state.exits` arrays.
 *
 * Layout: a linear corridor with branches every 5 rooms. Identical to
 * the pre-split monolith.
 */
export function wireRoomExits(rooms: GeneratedRoom[]): void {
  for (let i = 0; i < rooms.length; i++) {
    const state = rooms[i].state;

    // east/west neighbours
    if (i < rooms.length - 1) {
      state.exits.push({
        direction: 'e',
        targetRoomId: rooms[i + 1].roomId,
        locked: false,
      });
    }
    if (i > 0) {
      state.exits.push({
        direction: 'w',
        targetRoomId: rooms[i - 1].roomId,
        locked: false,
      });
    }

    // north/south branches every 5 rooms
    if (i + 5 < rooms.length && i % 5 === 0) {
      state.exits.push({
        direction: 's',
        targetRoomId: rooms[i + 5].roomId,
        locked: false,
      });
    }
    if (i - 5 >= 0 && (i - 5) % 5 === 0) {
      state.exits.push({
        direction: 'n',
        targetRoomId: rooms[i - 5].roomId,
        locked: false,
      });
    }
  }
}

```
