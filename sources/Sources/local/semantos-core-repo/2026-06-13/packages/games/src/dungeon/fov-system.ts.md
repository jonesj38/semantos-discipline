---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/fov-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.403178+00:00
---

# packages/games/src/dungeon/fov-system.ts

```ts
/**
 * FOV system — abstract field-of-view provider behind a port so the
 * dungeon engine can be tested with a deterministic stub instead of
 * the rot.js `PreciseShadowcasting` algorithm.
 *
 * Production wires the rot.js implementation via `bindDefaultFovProvider`
 * (see `default-bindings.ts`). Tests bind their own factory that
 * deterministically reveals tiles for replay.
 *
 * Per-engine factory shape mirrors the `transportPort` pattern from
 * the prompt-20 P2P agent split — distinct dungeons want distinct FOV
 * instances, so the port returns a factory rather than a singleton.
 */

import { port, type Port } from '@semantos/state';

import type { DungeonFloor, Position } from './types';
import { Tile, FOV_RADIUS, posKey } from './types';

/** Tile passability lookup — true if light passes through (x, y). */
export type FovPassableLookup = (x: number, y: number) => boolean;

export interface FovProvider {
  /**
   * Compute visibility from `(originX, originY)` out to `radius` tiles.
   * The callback fires once per tile reached with `visibility > 0`.
   */
  compute(
    originX: number,
    originY: number,
    radius: number,
    cb: (x: number, y: number, r: number, visibility: number) => void,
  ): void;
}

export interface FovProviderArgs {
  /** Floor this FOV instance is computing visibility for. */
  passable: FovPassableLookup;
}

export type FovFactory = (args: FovProviderArgs) => FovProvider;

export const fovPort: Port<FovFactory> = port<FovFactory>('dungeon-fov');

/** Build the passability lookup for a dungeon floor. */
export function passableForFloor(floor: DungeonFloor): FovPassableLookup {
  return (x, y) => {
    if (y < 0 || y >= floor.height || x < 0 || x >= floor.width) return false;
    const tile = floor.tiles[y][x];
    return tile !== Tile.WALL && tile !== Tile.DOOR_CLOSED && tile !== Tile.DOOR_LOCKED;
  };
}

/**
 * Compute the visible + explored tile sets given a player position
 * and a (likely already constructed) `FovProvider`. Pure function:
 * mutates the supplied sets in-place.
 */
export function applyVisibility(
  fov: FovProvider,
  origin: Position,
  visible: Set<string>,
  explored: Set<string>,
  radius = FOV_RADIUS,
): void {
  visible.clear();
  fov.compute(origin.x, origin.y, radius, (x, y, _r, visibility) => {
    if (visibility > 0) {
      const key = `${x},${y}`;
      visible.add(key);
      explored.add(key);
    }
  });
  // Always see the origin tile.
  const here = posKey(origin);
  visible.add(here);
  explored.add(here);
}

/**
 * Resolve the bound factory or fall back to a synchronous stub that
 * reveals the radius square. Useful in tests that don't want rot.js
 * involvement and prefer a deterministic fill.
 */
export function resolveFovFactory(): FovFactory {
  return fovPort.isBound() ? fovPort.get() : stubFovFactory;
}

/** Fallback factory — reveals every passable tile within the radius. */
const stubFovFactory: FovFactory = (args): FovProvider => ({
  compute(originX, originY, radius, cb) {
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        const x = originX + dx;
        const y = originY + dy;
        if (Math.abs(dx) + Math.abs(dy) > radius * 2) continue;
        if (!args.passable(x, y) && !(dx === 0 && dy === 0)) continue;
        cb(x, y, Math.max(Math.abs(dx), Math.abs(dy)), 1);
      }
    }
  },
});

/** Test-only — clear the bound factory between cases. */
export function unbindFovProvider(): void {
  if (fovPort.isBound()) fovPort.unbind();
}

```
