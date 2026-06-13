---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/inventory-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.843600+00:00
---

# archive/apps-mud/src/room-actor/inventory-system.ts

```ts
/**
 * Inventory system — pickup, drop, use, equip.
 *
 * Pure-ish handlers that mutate the supplied player and room state,
 * returning a structured `InventoryOutcome` the facade fans out as
 * RoomEvents and ActionResults. The room's `items` array is mutated
 * in place; consumed cells are reported by id for the persister.
 */

import { posEq, type DungeonItem } from '../../../../packages/games/src/dungeon/types';

import type { MUDPlayer, PlayerAction, RoomEvent, RoomId, RoomState } from '../types';
import { INVENTORY_MAX } from '../types';

export interface InventoryOutcome {
  success: boolean;
  message: string;
  consumedCellIds: string[];
  broadcastEvents: RoomEvent[];
  /** True when the room/player state changed materially (turn bump + commit). */
  stateChanged: boolean;
}

const NOOP: InventoryOutcome = {
  success: false,
  message: '',
  consumedCellIds: [],
  broadcastEvents: [],
  stateChanged: false,
};

export interface PickupArgs {
  roomId: RoomId;
  state: RoomState;
  player: MUDPlayer;
}

export function handlePickup(args: PickupArgs): InventoryOutcome {
  const { roomId, state, player } = args;
  const itemsHere = state.items.filter((i) => posEq(i.position, player.position));
  if (itemsHere.length === 0) {
    return { ...NOOP, message: 'Nothing to pick up here.' };
  }
  if (player.inventory.length >= INVENTORY_MAX) {
    return { ...NOOP, message: 'Inventory is full!' };
  }

  const item = itemsHere[0];
  player.inventory.push(item);
  const floorIdx = state.items.indexOf(item);
  if (floorIdx >= 0) state.items.splice(floorIdx, 1);

  return {
    success: true,
    message: `Picked up ${item.name}.`,
    consumedCellIds: [],
    broadcastEvents: [
      {
        type: 'item-picked-up',
        roomId,
        playerId: player.id,
        message: `${player.name} picks up ${item.name}.`,
      },
    ],
    stateChanged: true,
  };
}

export interface DropArgs {
  roomId: RoomId;
  state: RoomState;
  player: MUDPlayer;
  action: PlayerAction;
}

export function handleDrop(args: DropArgs): InventoryOutcome {
  const { roomId, state, player, action } = args;
  const idx = action.itemIndex ?? 0;
  const item = player.inventory[idx];
  if (!item) {
    return { ...NOOP, message: 'No item at that index.' };
  }

  // Unequip if dropped item is equipped
  if (item === player.equippedWeapon) player.equippedWeapon = null;
  if (item === player.equippedArmor) player.equippedArmor = null;

  player.inventory.splice(idx, 1);
  item.position = { ...player.position };
  state.items.push(item);

  return {
    success: true,
    message: `Dropped ${item.name}.`,
    consumedCellIds: [],
    broadcastEvents: [
      {
        type: 'item-dropped',
        roomId,
        playerId: player.id,
        message: `${player.name} drops ${item.name}.`,
      },
    ],
    stateChanged: true,
  };
}

export interface UseItemArgs {
  player: MUDPlayer;
  action: PlayerAction;
}

export function handleUseItem(args: UseItemArgs): InventoryOutcome {
  const { player, action } = args;
  const idx = action.itemIndex ?? 0;
  const item = player.inventory[idx];
  if (!item) {
    return { ...NOOP, message: 'No item at that index.' };
  }

  switch (item.category) {
    case 'potion':
      return usePotion(player, item, idx);
    case 'weapon':
      player.equippedWeapon = item;
      return {
        success: true,
        message: `Equipped ${item.name} (dmg: ${item.damage}).`,
        consumedCellIds: [],
        broadcastEvents: [],
        stateChanged: true,
      };
    case 'armor':
      player.equippedArmor = item;
      return {
        success: true,
        message: `Equipped ${item.name} (def: ${item.defense}).`,
        consumedCellIds: [],
        broadcastEvents: [],
        stateChanged: true,
      };
    default:
      return {
        success: true,
        message: `Can't use ${item.name}.`,
        consumedCellIds: [],
        broadcastEvents: [],
        stateChanged: true,
      };
  }
}

function usePotion(
  player: MUDPlayer,
  item: DungeonItem,
  idx: number,
): InventoryOutcome {
  const heal = item.healAmount ?? 10;
  player.hp = Math.min(player.maxHp, player.hp + heal);
  const consumed = item.entity.id;
  player.inventory.splice(idx, 1);
  return {
    success: true,
    message: `Used ${item.name}. Healed ${heal} HP. (HP: ${player.hp}/${player.maxHp})`,
    consumedCellIds: [consumed],
    broadcastEvents: [],
    stateChanged: true,
  };
}

```
