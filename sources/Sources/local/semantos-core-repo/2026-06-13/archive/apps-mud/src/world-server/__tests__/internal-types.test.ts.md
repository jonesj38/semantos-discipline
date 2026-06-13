---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/internal-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.844541+00:00
---

# archive/apps-mud/src/world-server/__tests__/internal-types.test.ts

```ts
/**
 * Tests for `internal-types.ts` — pure helpers (no engine, no actor).
 */

import { describe, test, expect } from 'bun:test';

import { Tile } from '../../../../../packages/games/src/dungeon/types';
import type { RoomState } from '../../types';
import { findFreePosition, getItemPool, RELEVANT, AFFINE, LINEAR, WORLD_OWNER, PLAYER_OWNER } from '../internal-types';

function makeRoomState(width: number, height: number, opts?: {
  monsters?: { x: number; y: number; hp: number }[];
  walls?: { x: number; y: number }[];
}): RoomState {
  const tiles: number[][] = [];
  for (let y = 0; y < height; y++) {
    const row: number[] = [];
    for (let x = 0; x < width; x++) row.push(Tile.FLOOR);
    tiles.push(row);
  }
  for (const w of opts?.walls ?? []) tiles[w.y][w.x] = Tile.WALL;

  const monsters = (opts?.monsters ?? []).map((m, i) => ({
    entity: { id: `m-${i}` } as never,
    type: { name: 'orc', hp: 5, attack: 1, xp: 1, char: 'o' } as never,
    hp: m.hp,
    position: { x: m.x, y: m.y },
  }));

  return {
    cellId: 'room-0',
    roomId: 'room-0',
    name: 'test',
    description: 'test',
    width,
    height,
    tiles,
    occupants: [],
    monsters,
    items: [],
    exits: [],
    doorLocks: new Map(),
    turnNumber: 0,
    previousCellId: null,
  };
}

describe('internal-types — constants', () => {
  test('linearity literals match the canonical Linearity enum order', () => {
    expect(RELEVANT).toBe(3);
    expect(AFFINE).toBe(2);
    expect(LINEAR).toBe(1);
  });

  test('WORLD_OWNER and PLAYER_OWNER are 16-byte tags differing by first byte', () => {
    expect(WORLD_OWNER).toBeInstanceOf(Uint8Array);
    expect(WORLD_OWNER.length).toBe(16);
    expect(PLAYER_OWNER.length).toBe(16);
    expect(WORLD_OWNER[0]).toBe(0x60);
    expect(PLAYER_OWNER[0]).toBe(0x61);
  });

  test('owner buckets are independent — mutating one does not leak', () => {
    // Defensive: callers should never mutate, but the constants are
    // shared bytes so verify they are not shared instances.
    expect(WORLD_OWNER).not.toBe(PLAYER_OWNER);
  });
});

describe('internal-types — findFreePosition', () => {
  test('returns the room centre when fully free', () => {
    const state = makeRoomState(11, 11);
    const pos = findFreePosition(state);
    expect(pos).toEqual({ x: 5, y: 5 });
  });

  test('skips dead monsters (hp ≤ 0)', () => {
    const state = makeRoomState(11, 11, {
      monsters: [{ x: 5, y: 5, hp: 0 }],
    });
    const pos = findFreePosition(state);
    expect(pos).toEqual({ x: 5, y: 5 });
  });

  test('avoids living monsters at the centre', () => {
    const state = makeRoomState(11, 11, {
      monsters: [{ x: 5, y: 5, hp: 3 }],
    });
    const pos = findFreePosition(state);
    // Should not return centre — spirals outward
    expect(pos).not.toEqual({ x: 5, y: 5 });
    // Must be a FLOOR tile and not the monster's position
    expect(state.tiles[pos.y][pos.x]).toBe(Tile.FLOOR);
  });

  test('avoids walls', () => {
    const state = makeRoomState(11, 11, {
      walls: [{ x: 5, y: 5 }],
    });
    const pos = findFreePosition(state);
    expect(pos).not.toEqual({ x: 5, y: 5 });
    expect(state.tiles[pos.y][pos.x]).toBe(Tile.FLOOR);
  });
});

describe('internal-types — getItemPool', () => {
  test('floor 0 returns the base pool (healthSmall + dagger only)', () => {
    expect(getItemPool(0)).toEqual(['healthSmall', 'dagger']);
  });

  test('floor 1 unlocks shortSword/leather/goldPile', () => {
    const pool = getItemPool(1);
    expect(pool).toContain('shortSword');
    expect(pool).toContain('leather');
    expect(pool).toContain('goldPile');
  });

  test('higher floors are supersets of lower floors', () => {
    const f1 = getItemPool(1);
    const f3 = getItemPool(3);
    for (const item of f1) {
      expect(f3).toContain(item);
    }
    expect(f3).toContain('battleAxe');
    expect(f3).toContain('plateMail');
  });
});

```
