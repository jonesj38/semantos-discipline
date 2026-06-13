---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/fov-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.432444+00:00
---

# packages/games/src/dungeon/__tests__/fov-system.test.ts

```ts
/**
 * FOV-system tests — covers `passableForFloor`, `applyVisibility`,
 * port factory bind/unbind, and the stub-fallback factory.
 */

import { afterEach, describe, expect, test } from 'bun:test';

import {
  applyVisibility,
  fovPort,
  passableForFloor,
  resolveFovFactory,
  unbindFovProvider,
  type FovFactory,
  type FovProvider,
} from '../fov-system';
import { Tile, type DungeonFloor } from '../types';

function makeFloor(): DungeonFloor {
  const tiles: Tile[][] = Array.from({ length: 5 }, () =>
    new Array(5).fill(Tile.FLOOR),
  );
  // Wall pillar at (2,2)
  tiles[2][2] = Tile.WALL;
  return { width: 5, height: 5, tiles, monsters: [], items: [], doorLocks: new Map() };
}

afterEach(() => {
  unbindFovProvider();
});

describe('passableForFloor', () => {
  test('returns false for walls + closed/locked doors', () => {
    const floor = makeFloor();
    floor.tiles[1][1] = Tile.WALL;
    floor.tiles[1][2] = Tile.DOOR_CLOSED;
    floor.tiles[1][3] = Tile.DOOR_LOCKED;
    floor.tiles[1][4] = Tile.FLOOR;
    const passable = passableForFloor(floor);
    expect(passable(1, 1)).toBe(false);
    expect(passable(2, 1)).toBe(false);
    expect(passable(3, 1)).toBe(false);
    expect(passable(4, 1)).toBe(true);
  });

  test('out-of-bounds is not passable', () => {
    const passable = passableForFloor(makeFloor());
    expect(passable(-1, 0)).toBe(false);
    expect(passable(0, -1)).toBe(false);
    expect(passable(99, 99)).toBe(false);
  });
});

describe('fovPort', () => {
  test('bind + resolveFovFactory returns the bound factory', () => {
    let called = false;
    const fakeFactory: FovFactory = (): FovProvider => {
      called = true;
      return { compute: () => {} };
    };
    fovPort.bind(fakeFactory);
    const factory = resolveFovFactory();
    factory({ passable: () => true });
    expect(called).toBe(true);
  });

  test('resolveFovFactory falls back to stub when unbound', () => {
    expect(fovPort.isBound()).toBe(false);
    const factory = resolveFovFactory();
    const visible = new Set<string>();
    const explored = new Set<string>();
    const fov = factory({ passable: () => true });
    applyVisibility(fov, { x: 0, y: 0 }, visible, explored, 1);
    expect(visible.has('0,0')).toBe(true);
    expect(explored.has('0,0')).toBe(true);
  });
});

describe('applyVisibility', () => {
  test('always reveals origin tile + adds to explored', () => {
    const visible = new Set<string>();
    const explored = new Set<string>();
    // empty provider — no callback fires
    const fov: FovProvider = { compute: () => {} };
    applyVisibility(fov, { x: 3, y: 4 }, visible, explored);
    expect(visible.has('3,4')).toBe(true);
    expect(explored.has('3,4')).toBe(true);
  });

  test('clears visible between calls (explored is cumulative)', () => {
    const visible = new Set<string>(['9,9']);
    const explored = new Set<string>(['9,9']);
    const fov: FovProvider = {
      compute: (x, y, _r, cb) => cb(x, y, 0, 1),
    };
    applyVisibility(fov, { x: 1, y: 1 }, visible, explored);
    expect(visible.has('9,9')).toBe(false);
    expect(visible.has('1,1')).toBe(true);
    expect(explored.has('9,9')).toBe(true); // sticky
    expect(explored.has('1,1')).toBe(true);
  });
});

```
