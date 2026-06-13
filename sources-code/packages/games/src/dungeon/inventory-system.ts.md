---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/inventory-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.405123+00:00
---

# packages/games/src/dungeon/inventory-system.ts

```ts
/**
 * Inventory system — pickup, drop, use, equip operations.
 *
 * The legacy engine inlined these in `pickup`, `useItem`, and
 * `attackMonster`. Splitting them here keeps the LINEAR (potion,
 * key, scroll, treasure) vs AFFINE (weapon, armor) handling in one
 * file and lets the action dispatcher stay terse.
 *
 * Each helper mutates the supplied state in-place and returns a
 * structured outcome listing consumed cell ids + narration fragments
 * the caller threads onto the action result.
 */

import type {
  DungeonBoard,
  DungeonFloor,
  DungeonItem,
  DungeonPlayer,
} from './types';
import { Tile, posEq } from './types';

export interface PickupOutcome {
  /** Item was added to inventory. */
  pickedUp: DungeonItem | null;
  /** Cell ids consumed (auto-pickup of treasure). */
  consumedCellIds: string[];
  /** Gold added (from auto-pickup of treasure). */
  goldAdded: number;
  /** Narration fragment. */
  message: string;
}

/**
 * Auto-pickup any treasure on the player's tile. Treasure is LINEAR
 * — it disappears from the floor and the cell is recorded in
 * `consumedCellIds`. Items other than treasure are ignored here;
 * use the explicit `pickupItem` helper for those.
 */
export function autoPickupTreasure(
  board: DungeonBoard,
  player: DungeonPlayer,
): PickupOutcome {
  const floor = board.floors[board.floor];
  const idx = floor.items.findIndex(
    (i) => i.category === 'treasure' && posEq(i.position, player.position),
  );
  if (idx < 0) {
    return {
      pickedUp: null,
      consumedCellIds: [],
      goldAdded: 0,
      message: '',
    };
  }
  const treasure = floor.items[idx];
  const goldAdded = treasure.value ?? 0;
  player.gold += goldAdded;
  floor.items.splice(idx, 1);
  return {
    pickedUp: treasure,
    consumedCellIds: [treasure.entity.id],
    goldAdded,
    message: ` Picked up ${treasure.name} (+${goldAdded}g).`,
  };
}

/**
 * Pick up a specific item at the player's tile. Returns null when
 * nothing matches the index. The caller is expected to have already
 * passed the policy gate for inventory capacity.
 */
export function pickupItem(
  board: DungeonBoard,
  player: DungeonPlayer,
  itemIndex?: number,
): { item: DungeonItem | null; message: string } {
  const floor: DungeonFloor = board.floors[board.floor];
  const itemsHere = floor.items.filter((i) => posEq(i.position, player.position));
  if (itemsHere.length === 0) {
    return { item: null, message: 'Nothing to pick up here.' };
  }

  const item = itemIndex !== undefined ? itemsHere[itemIndex] : itemsHere[0];
  if (!item) return { item: null, message: 'No item at that index.' };

  player.inventory.push(item);
  const idx = floor.items.indexOf(item);
  if (idx >= 0) floor.items.splice(idx, 1);
  return { item, message: `Picked up ${item.name}.` };
}

export interface UseItemOutcome {
  /** Cell ids consumed by LINEAR destruction. */
  consumedCellIds: string[];
  /** Narration. */
  message: string;
  /** When non-null, the floor's `exploredTiles` should be flooded. */
  revealFloor: boolean;
}

/**
 * Apply an item's "use" effect. Potions heal + are consumed (LINEAR);
 * scrolls reveal + are consumed (LINEAR); weapons / armor are
 * equipped (no consumption — AFFINE durability handles wear).
 */
export function useItem(
  board: DungeonBoard,
  player: DungeonPlayer,
  itemIndex: number,
): UseItemOutcome {
  const consumedCellIds: string[] = [];
  let message: string;
  let revealFloor = false;
  const item = player.inventory[itemIndex];
  if (!item) return { consumedCellIds, message: 'No item at that index.', revealFloor };

  switch (item.category) {
    case 'potion': {
      const heal = item.healAmount ?? 10;
      player.hp = Math.min(player.maxHp, player.hp + heal);
      message = `Used ${item.name}. Healed ${heal} HP. (HP: ${player.hp}/${player.maxHp})`;
      consumedCellIds.push(item.entity.id);
      player.inventory.splice(itemIndex, 1);
      break;
    }
    case 'scroll': {
      if (item.name === 'Scroll of Mapping') {
        revealFloor = true;
        message = 'The scroll reveals the entire floor layout!';
      } else {
        message = `Used ${item.name}.`;
      }
      consumedCellIds.push(item.entity.id);
      player.inventory.splice(itemIndex, 1);
      break;
    }
    case 'weapon': {
      player.equippedWeapon = item;
      message = `Equipped ${item.name} (dmg: ${item.damage}).`;
      break;
    }
    case 'armor': {
      player.equippedArmor = item;
      message = `Equipped ${item.name} (def: ${item.defense}).`;
      break;
    }
    default:
      message = `Can't use ${item.name}.`;
  }

  return { consumedCellIds, message, revealFloor };
}

export interface OpenDoorOutcome {
  /** Cell ids consumed by LINEAR destruction (the matching key). */
  consumedCellIds: string[];
  /** Narration. */
  message: string;
}

/**
 * Open a door at `(x, y)` — consumes the matching key for locked doors.
 * Caller is responsible for the policy gate; this helper assumes it
 * passed (so a locked door + matching key both pass through).
 */
export function openDoorAt(
  board: DungeonBoard,
  player: DungeonPlayer,
  x: number,
  y: number,
): OpenDoorOutcome {
  const floor = board.floors[board.floor];
  const tile = floor.tiles[y][x];
  const consumedCellIds: string[] = [];

  if (tile === Tile.DOOR_LOCKED) {
    const keyId = floor.doorLocks.get(`${x},${y}`)!;
    const keyIdx = player.inventory.findIndex(
      (i) => i.category === 'key' && i.keyId === keyId,
    );
    if (keyIdx >= 0) {
      consumedCellIds.push(player.inventory[keyIdx].entity.id);
      player.inventory.splice(keyIdx, 1);
    }
    floor.doorLocks.delete(`${x},${y}`);
  }

  floor.tiles[y][x] = Tile.DOOR_OPEN;
  return { consumedCellIds, message: 'You open the door.' };
}

```
