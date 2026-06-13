---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/door-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.847791+00:00
---

# archive/apps-mud/src/room-actor/__tests__/door-system.test.ts

```ts
/**
 * Door system tests — open + locked-door key consumption + exit-room.
 */

import { describe, expect, test } from 'bun:test';

import { handleExitRoom, handleOpenDoor } from '../door-system';

import { Tile } from '../../../../../packages/games/src/dungeon/types';
import type { DungeonItem } from '../../../../../packages/games/src/dungeon/types';
import type { MUDPlayer, RoomExit, RoomState } from '../../types';

const ROOM_ID = 'r1';

function tilesWithDoor(doorTile: Tile): number[][] {
  const tiles = Array(5).fill(0).map(() => Array(5).fill(Tile.FLOOR));
  tiles[1][2] = doorTile;
  return tiles;
}

function makePlayer(): MUDPlayer {
  return {
    id: 'p',
    entity: { id: 'pe' } as MUDPlayer['entity'],
    name: 'P',
    position: { x: 2, y: 2 },
    hp: 10,
    maxHp: 10,
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
  };
}

function makeState(tiles: number[][], doorLocks = new Map<string, string>()): RoomState {
  return {
    cellId: 'c0',
    roomId: ROOM_ID,
    name: 'Test',
    description: 'Test',
    width: 5,
    height: 5,
    tiles,
    occupants: [],
    monsters: [],
    items: [],
    exits: [],
    doorLocks,
    turnNumber: 0,
    previousCellId: null,
  };
}

function makeKey(keyId: string): DungeonItem {
  return {
    entity: { id: `key-${keyId}` } as DungeonItem['entity'],
    name: `Key ${keyId}`,
    category: 'key',
    position: { x: 0, y: 0 },
    keyId,
  };
}

describe('handleOpenDoor', () => {
  test('opens an unlocked closed door', () => {
    const state = makeState(tilesWithDoor(Tile.DOOR_CLOSED));
    const player = makePlayer();

    const out = handleOpenDoor({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'open', playerId: 'p', direction: 'n' },
    });

    expect(out.success).toBe(true);
    expect(state.tiles[1][2]).toBe(Tile.DOOR_OPEN);
    expect(out.broadcastEvents.some((e) => e.type === 'door-opened')).toBe(true);
  });

  test('locked door without key → reject, no consumption', () => {
    const doorLocks = new Map<string, string>([['2,1', 'gold']]);
    const state = makeState(tilesWithDoor(Tile.DOOR_LOCKED), doorLocks);
    const player = makePlayer();

    const out = handleOpenDoor({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'open', playerId: 'p', direction: 'n' },
    });

    expect(out.success).toBe(false);
    expect(out.consumedCellIds).toEqual([]);
    expect(state.tiles[1][2]).toBe(Tile.DOOR_LOCKED);
  });

  test('locked door with matching key → consume key, open door', () => {
    const doorLocks = new Map<string, string>([['2,1', 'gold']]);
    const state = makeState(tilesWithDoor(Tile.DOOR_LOCKED), doorLocks);
    const player = makePlayer();
    const key = makeKey('gold');
    player.inventory.push(key);

    const out = handleOpenDoor({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'open', playerId: 'p', direction: 'n' },
    });

    expect(out.success).toBe(true);
    expect(state.tiles[1][2]).toBe(Tile.DOOR_OPEN);
    expect(out.consumedCellIds).toContain(key.entity.id);
    expect(player.inventory).toHaveLength(0);
    expect(state.doorLocks.has('2,1')).toBe(false);
  });
});

describe('handleExitRoom', () => {
  test('open exit → emits player-left signal, no commit', () => {
    const exit: RoomExit = { direction: 'n', targetRoomId: 'r2', locked: false };
    const state = makeState(Array(5).fill(0).map(() => Array(5).fill(1)));
    state.exits = [exit];
    const player = makePlayer();

    const out = handleExitRoom({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'exit-room', playerId: 'p', direction: 'n' },
    });

    expect(out.success).toBe(true);
    expect(out.stateChanged).toBe(false);
    expect(out.broadcastEvents.some((e) => e.type === 'player-left')).toBe(true);
  });

  test('locked exit consumes matching key', () => {
    const exit: RoomExit = { direction: 'n', targetRoomId: 'r2', locked: true, keyId: 'silver' };
    const state = makeState(Array(5).fill(0).map(() => Array(5).fill(1)));
    state.exits = [exit];
    const player = makePlayer();
    const key = makeKey('silver');
    player.inventory.push(key);

    const out = handleExitRoom({
      roomId: ROOM_ID,
      state,
      player,
      action: { type: 'exit-room', playerId: 'p', direction: 'n' },
    });

    expect(out.success).toBe(true);
    expect(out.consumedCellIds).toContain(key.entity.id);
    expect(exit.locked).toBe(false);
  });
});

```
