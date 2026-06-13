---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/inventory-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.432150+00:00
---

# packages/games/src/dungeon/__tests__/inventory-system.test.ts

```ts
/**
 * Inventory-system tests — `pickupItem`, `useItem`, `openDoorAt`, and
 * `autoPickupTreasure` are pure-mutate-in-place over board + player.
 */

import { describe, expect, test } from 'bun:test';

import {
  autoPickupTreasure,
  openDoorAt,
  pickupItem,
  useItem,
} from '../inventory-system';
import type { GameEntity } from '../../../../game-sdk/src/types';
import {
  Tile,
  XP_PER_LEVEL,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonItem,
  type DungeonPlayer,
} from '../types';

function fakeEntity(id: string): GameEntity {
  return { id, cell: new Uint8Array() } as unknown as GameEntity;
}

function makeFloor(): DungeonFloor {
  const tiles: Tile[][] = Array.from({ length: 5 }, () =>
    new Array(5).fill(Tile.FLOOR),
  );
  return {
    width: 5,
    height: 5,
    tiles,
    monsters: [],
    items: [],
    doorLocks: new Map(),
  };
}

function makePlayer(): DungeonPlayer {
  return {
    entity: fakeEntity('player'),
    position: { x: 1, y: 1 },
    hp: 20,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: XP_PER_LEVEL,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
  };
}

function makeBoard(floor: DungeonFloor, player: DungeonPlayer): DungeonBoard {
  return {
    cellId: 'b0',
    floor: 0,
    floors: [floor],
    player,
    turnNumber: 0,
    previousBoardCellId: null,
    messages: [],
  };
}

function makeTreasure(x: number, y: number, value = 10): DungeonItem {
  return {
    entity: fakeEntity(`treasure-${x}-${y}`),
    name: 'Gold Pile',
    category: 'treasure',
    position: { x, y },
    value,
  };
}

describe('autoPickupTreasure', () => {
  test('picks up treasure on the player tile + records consumption', () => {
    const floor = makeFloor();
    const player = makePlayer();
    const board = makeBoard(floor, player);
    const treasure = makeTreasure(player.position.x, player.position.y, 25);
    floor.items.push(treasure);

    const result = autoPickupTreasure(board, player);
    expect(result.pickedUp).toBe(treasure);
    expect(result.goldAdded).toBe(25);
    expect(player.gold).toBe(25);
    expect(result.consumedCellIds).toContain(treasure.entity.id);
    expect(floor.items).not.toContain(treasure);
  });

  test('returns null when no treasure here', () => {
    const board = makeBoard(makeFloor(), makePlayer());
    const r = autoPickupTreasure(board, board.player);
    expect(r.pickedUp).toBeNull();
    expect(r.goldAdded).toBe(0);
  });
});

describe('pickupItem', () => {
  test('picks up the first item on the floor at player tile', () => {
    const floor = makeFloor();
    const player = makePlayer();
    const board = makeBoard(floor, player);
    const potion: DungeonItem = {
      entity: fakeEntity('potion'),
      name: 'Small Health Potion',
      category: 'potion',
      position: { x: 1, y: 1 },
      healAmount: 10,
    };
    floor.items.push(potion);
    const r = pickupItem(board, player);
    expect(r.item).toBe(potion);
    expect(player.inventory).toContain(potion);
    expect(floor.items).not.toContain(potion);
  });

  test('returns informative message when nothing is here', () => {
    const board = makeBoard(makeFloor(), makePlayer());
    const r = pickupItem(board, board.player);
    expect(r.item).toBeNull();
    expect(r.message).toContain('Nothing');
  });
});

describe('useItem', () => {
  test('potion heals + LINEAR consumes the cell', () => {
    const player = makePlayer();
    const potion: DungeonItem = {
      entity: fakeEntity('potion'),
      name: 'Small Health Potion',
      category: 'potion',
      position: { x: 0, y: 0 },
      healAmount: 8,
    };
    player.inventory.push(potion);
    const board = makeBoard(makeFloor(), player);

    const out = useItem(board, player, 0);
    expect(player.hp).toBe(28);
    expect(out.consumedCellIds).toContain(potion.entity.id);
    expect(player.inventory).not.toContain(potion);
  });

  test('weapon equips without consuming the cell', () => {
    const player = makePlayer();
    const sword: DungeonItem = {
      entity: fakeEntity('sword'),
      name: 'Short Sword',
      category: 'weapon',
      position: { x: 0, y: 0 },
      damage: 4,
      durability: 30,
    };
    player.inventory.push(sword);
    const board = makeBoard(makeFloor(), player);

    const out = useItem(board, player, 0);
    expect(player.equippedWeapon).toBe(sword);
    expect(out.consumedCellIds).toHaveLength(0);
    expect(player.inventory).toContain(sword);
  });

  test('Scroll of Mapping flags revealFloor', () => {
    const player = makePlayer();
    const scroll: DungeonItem = {
      entity: fakeEntity('scroll'),
      name: 'Scroll of Mapping',
      category: 'scroll',
      position: { x: 0, y: 0 },
    };
    player.inventory.push(scroll);
    const board = makeBoard(makeFloor(), player);
    const out = useItem(board, player, 0);
    expect(out.revealFloor).toBe(true);
    expect(out.consumedCellIds).toContain(scroll.entity.id);
  });
});

describe('openDoorAt', () => {
  test('locked door consumes matching key + opens', () => {
    const floor = makeFloor();
    floor.tiles[1][2] = Tile.DOOR_LOCKED;
    floor.doorLocks.set('2,1', 'key-f0');
    const player = makePlayer();
    const key: DungeonItem = {
      entity: fakeEntity('rusty-key'),
      name: 'Rusty Key',
      category: 'key',
      position: { x: 0, y: 0 },
      keyId: 'key-f0',
    };
    player.inventory.push(key);
    const board = makeBoard(floor, player);

    const out = openDoorAt(board, player, 2, 1);
    expect(floor.tiles[1][2]).toBe(Tile.DOOR_OPEN);
    expect(out.consumedCellIds).toContain(key.entity.id);
    expect(player.inventory).not.toContain(key);
    expect(floor.doorLocks.has('2,1')).toBe(false);
  });

  test('unlocked door opens without consuming any cell', () => {
    const floor = makeFloor();
    floor.tiles[1][2] = Tile.DOOR_CLOSED;
    const player = makePlayer();
    const board = makeBoard(floor, player);
    const out = openDoorAt(board, player, 2, 1);
    expect(floor.tiles[1][2]).toBe(Tile.DOOR_OPEN);
    expect(out.consumedCellIds).toHaveLength(0);
  });
});

```
