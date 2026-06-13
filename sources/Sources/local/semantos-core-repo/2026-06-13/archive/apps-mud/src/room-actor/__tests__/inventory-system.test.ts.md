---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/inventory-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.846345+00:00
---

# archive/apps-mud/src/room-actor/__tests__/inventory-system.test.ts

```ts
/**
 * Inventory system tests — pickup / drop / use / equip.
 *
 * Verifies inventory bounds, equip semantics, potion consumption,
 * and the consumed-cell book-keeping the persister relies on.
 */

import { describe, expect, test } from 'bun:test';

import {
  handleDrop,
  handlePickup,
  handleUseItem,
} from '../inventory-system';

import type { DungeonItem } from '../../../../../packages/games/src/dungeon/types';
import type { MUDPlayer, RoomState } from '../../types';
import { INVENTORY_MAX } from '../../types';

const ROOM_ID = 'r1';

function makeItem(overrides: Partial<DungeonItem> = {}): DungeonItem {
  return {
    entity: { id: `i-${Math.random().toString(36).slice(2)}` } as DungeonItem['entity'],
    name: 'Item',
    category: 'potion',
    position: { x: 0, y: 0 },
    healAmount: 10,
    ...overrides,
  };
}

function makePlayer(overrides: Partial<MUDPlayer> = {}): MUDPlayer {
  return {
    id: 'p',
    entity: { id: 'pe' } as MUDPlayer['entity'],
    name: 'P',
    position: { x: 0, y: 0 },
    hp: 10,
    maxHp: 20,
    attack: 1,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: 50,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
    roomId: ROOM_ID,
    ...overrides,
  };
}

function makeState(items: DungeonItem[] = []): RoomState {
  return {
    cellId: 'c0',
    roomId: ROOM_ID,
    name: 'Test',
    description: 'Test',
    width: 10,
    height: 10,
    tiles: Array(10).fill(0).map(() => Array(10).fill(1)),
    occupants: [],
    monsters: [],
    items,
    exits: [],
    doorLocks: new Map(),
    turnNumber: 0,
    previousCellId: null,
  };
}

describe('handlePickup', () => {
  test('picks up item at player position', () => {
    const item = makeItem({ name: 'Potion' });
    const player = makePlayer();
    const state = makeState([item]);

    const out = handlePickup({ roomId: ROOM_ID, state, player });

    expect(out.success).toBe(true);
    expect(player.inventory).toHaveLength(1);
    expect(state.items).toHaveLength(0);
    expect(out.broadcastEvents.some((e) => e.type === 'item-picked-up')).toBe(true);
  });

  test('rejects when nothing here', () => {
    const player = makePlayer({ position: { x: 5, y: 5 } });
    const state = makeState([makeItem({ position: { x: 0, y: 0 } })]);

    const out = handlePickup({ roomId: ROOM_ID, state, player });

    expect(out.success).toBe(false);
    expect(out.message).toBe('Nothing to pick up here.');
  });

  test('rejects when inventory full', () => {
    const player = makePlayer({
      inventory: Array(INVENTORY_MAX).fill(null).map(() => makeItem()),
    });
    const state = makeState([makeItem()]);

    const out = handlePickup({ roomId: ROOM_ID, state, player });

    expect(out.success).toBe(false);
    expect(out.message).toBe('Inventory is full!');
  });
});

describe('handleUseItem', () => {
  test('potion heals and is consumed', () => {
    const potion = makeItem({ name: 'Potion', category: 'potion', healAmount: 8 });
    const player = makePlayer({ hp: 5, maxHp: 20, inventory: [potion] });

    const out = handleUseItem({ player, action: { type: 'use', playerId: player.id, itemIndex: 0 } });

    expect(player.hp).toBe(13);
    expect(player.inventory).toHaveLength(0);
    expect(out.consumedCellIds).toContain(potion.entity.id);
  });

  test('weapon equip updates equippedWeapon', () => {
    const sword = makeItem({ name: 'Sword', category: 'weapon', damage: 5 });
    const player = makePlayer({ inventory: [sword] });

    const out = handleUseItem({ player, action: { type: 'use', playerId: player.id, itemIndex: 0 } });

    expect(player.equippedWeapon).toBe(sword);
    expect(player.inventory).toHaveLength(1); // not consumed on equip
    expect(out.success).toBe(true);
  });

  test('armor equip updates equippedArmor', () => {
    const armor = makeItem({ name: 'Plate', category: 'armor', defense: 4 });
    const player = makePlayer({ inventory: [armor] });

    handleUseItem({ player, action: { type: 'use', playerId: player.id, itemIndex: 0 } });

    expect(player.equippedArmor).toBe(armor);
  });
});

describe('handleDrop', () => {
  test('moves item from inventory to floor at player position', () => {
    const item = makeItem({ name: 'Potion' });
    const player = makePlayer({ position: { x: 3, y: 4 }, inventory: [item] });
    const state = makeState();

    const out = handleDrop({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'drop', playerId: player.id, itemIndex: 0 },
    });

    expect(out.success).toBe(true);
    expect(player.inventory).toHaveLength(0);
    expect(state.items).toHaveLength(1);
    expect(state.items[0].position).toEqual({ x: 3, y: 4 });
  });

  test('dropping equipped weapon unequips it', () => {
    const sword = makeItem({ name: 'Sword', category: 'weapon', damage: 5 });
    const player = makePlayer({ inventory: [sword], equippedWeapon: sword });
    const state = makeState();

    handleDrop({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'drop', playerId: player.id, itemIndex: 0 },
    });

    expect(player.equippedWeapon).toBeNull();
  });
});

```
