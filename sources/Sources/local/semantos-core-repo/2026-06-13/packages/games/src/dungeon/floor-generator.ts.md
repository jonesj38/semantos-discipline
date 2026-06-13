---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/floor-generator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.403455+00:00
---

# packages/games/src/dungeon/floor-generator.ts

```ts
/**
 * Floor generator — pure population pass on top of `generateFloor`
 * (`map-gen.ts`). Given a generated tile grid + room list, attaches
 * monsters, items, keys, and locked doors using the legacy semantics
 * from `engine.ts`.
 *
 * The legacy engine inlined this as a static method that captured the
 * `GameCellEngine` instance to allocate cells. The split keeps that
 * dependency injected explicitly so the generator stays testable
 * (use a stub `EntityFactory`) and the engine wiring stays thin.
 *
 * RNG remains `Math.random` for parity with the legacy code path.
 * Replay-style tests that need determinism stub it out per-case.
 */

import { GameEntityType } from '../../../game-sdk/src/types';
import type { GameCellEngine } from '../../../game-sdk/src/engine';

import { generateFloor, randomRoomPosition, type GeneratedFloor } from './map-gen';
import {
  Tile,
  type DungeonFloor,
  type Monster,
  type DungeonItem,
  type Position,
  ITEM_TEMPLATES,
  MONSTER_TYPES,
  FLOOR_MONSTERS,
  posKey,
} from './types';

// ── Linearity Constants ────────────────────────────────────────

const LINEAR = 1;
const AFFINE = 2;

// ── Owner IDs (legacy parity) ──────────────────────────────────

const DUNGEON_OWNER = new Uint8Array(16);
DUNGEON_OWNER[0] = 0x40;

// ── Public surface ─────────────────────────────────────────────

/** Pool selection for items as the player descends. */
export function getFloorItemTemplates(floorIndex: number): string[] {
  const base = ['healthSmall', 'dagger'];
  if (floorIndex >= 1) base.push('shortSword', 'leather', 'goldPile', 'scrollMap');
  if (floorIndex >= 2) base.push('longSword', 'chainMail', 'healthLarge', 'gemstone');
  if (floorIndex >= 3) base.push('battleAxe', 'plateMail');
  if (floorIndex >= 4) base.push('magicStaff', 'crown');
  return base;
}

/**
 * Re-export for callers that wanted the bare tile generation. The
 * legacy engine used `generateFloor()` directly from `map-gen` — we
 * keep that surface plus a higher-level `populateFloor` that does the
 * cell allocation.
 */
export { generateFloor };

export interface PopulateFloorArgs {
  /** The pre-generated tile + room list. */
  generated: GeneratedFloor;
  /** Floor index (0-based). */
  floorIndex: number;
  /** Engine used to allocate monster/item cells. */
  engine: GameCellEngine;
}

/**
 * Populate a generated floor with monsters, items, and locked doors.
 * Pure-with-respect-to-randomness: every random choice goes through
 * `Math.random` (legacy parity). Tests that need determinism stub it.
 */
export function populateFloor(args: PopulateFloorArgs): DungeonFloor {
  const { engine, generated, floorIndex } = args;
  const { tiles, rooms, stairsDown, stairsUp, playerStart } = generated;
  const monsters: Monster[] = [];
  const items: DungeonItem[] = [];
  const doorLocks = new Map<string, string>();
  const occupied = new Set<string>();

  // Reserve player start and stairs.
  occupied.add(posKey(playerStart));
  if (stairsDown) occupied.add(posKey(stairsDown));
  if (stairsUp) occupied.add(posKey(stairsUp));

  const monsterPool = FLOOR_MONSTERS[Math.min(floorIndex, FLOOR_MONSTERS.length - 1)];

  // Place monsters in rooms (skip first room = player start).
  for (let ri = 1; ri < rooms.length; ri++) {
    const room = rooms[ri];
    const monsterCount = 1 + Math.floor(Math.random() * 2);
    for (let m = 0; m < monsterCount; m++) {
      const pos = randomRoomPosition(room, tiles, occupied);
      if (!pos) continue;
      occupied.add(posKey(pos));

      const typeKey = monsterPool[Math.floor(Math.random() * monsterPool.length)];
      const monsterType = MONSTER_TYPES[typeKey];
      const entity = engine.createEntity({
        entityType: GameEntityType.CHARACTER,
        ownerId: DUNGEON_OWNER,
        linearity: AFFINE,
        metadata: { domain: 'dungeon-monster', monsterType: typeKey, floor: floorIndex },
        state: 'alive',
      });

      monsters.push({
        entity,
        type: monsterType,
        hp: monsterType.hp,
        position: pos,
      });
    }
  }

  // Place items in rooms (50% chance per room).
  const floorItemTemplates = getFloorItemTemplates(floorIndex);

  for (let ri = 0; ri < rooms.length; ri++) {
    if (Math.random() > 0.5) continue;
    const room = rooms[ri];
    const pos = randomRoomPosition(room, tiles, occupied);
    if (!pos) continue;
    occupied.add(posKey(pos));

    const templateKey = floorItemTemplates[Math.floor(Math.random() * floorItemTemplates.length)];
    const template = ITEM_TEMPLATES[templateKey];
    const linearity = (template.category === 'weapon' || template.category === 'armor') ? AFFINE : LINEAR;

    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: DUNGEON_OWNER,
      linearity,
      metadata: { domain: 'dungeon-item', ...template },
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

  // Lock one random door per floor and place a key.
  if (rooms.length > 2) {
    const doorPositions: Position[] = [];
    for (let y = 0; y < tiles.length; y++) {
      for (let x = 0; x < tiles[0].length; x++) {
        if (tiles[y][x] === Tile.DOOR_CLOSED) {
          doorPositions.push({ x, y });
        }
      }
    }
    if (doorPositions.length > 0) {
      const lockDoor = doorPositions[Math.floor(Math.random() * doorPositions.length)];
      const keyId = `key-f${floorIndex}`;
      tiles[lockDoor.y][lockDoor.x] = Tile.DOOR_LOCKED;
      doorLocks.set(posKey(lockDoor), keyId);

      const keyRoom = rooms[Math.min(1, rooms.length - 1)];
      const keyPos = randomRoomPosition(keyRoom, tiles, occupied);
      if (keyPos) {
        occupied.add(posKey(keyPos));
        const keyEntity = engine.createEntity({
          entityType: GameEntityType.ITEM,
          ownerId: DUNGEON_OWNER,
          linearity: LINEAR,
          metadata: { domain: 'dungeon-item', name: 'Rusty Key', category: 'key', keyId },
          state: 'on-ground',
        });
        items.push({
          entity: keyEntity,
          name: 'Rusty Key',
          category: 'key',
          position: keyPos,
          keyId,
        });
      }
    }
  }

  return {
    width: tiles[0].length,
    height: tiles.length,
    tiles,
    monsters,
    items,
    doorLocks,
  };
}

```
