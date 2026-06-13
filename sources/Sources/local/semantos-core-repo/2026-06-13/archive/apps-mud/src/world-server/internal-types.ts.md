---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/internal-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.839169+00:00
---

# archive/apps-mud/src/world-server/internal-types.ts

```ts
/**
 * Internal constants + helpers shared across the `world-server/` modules.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * `RELEVANT`/`AFFINE`/`LINEAR` mirror the linearity tiers from
 * `core/protocol-types/src/constants` but as raw numeric literals so the
 * world-generator can pass them straight to GameCellEngine.createEntity()
 * without an extra import.
 *
 * `WORLD_OWNER` and `PLAYER_OWNER` are the two identity buckets the MUD
 * uses for cell-ownership: world-owned (rooms / monsters / floor items)
 * vs player-owned (player entity + starting inventory).
 */

import { Tile, posKey } from '../../../../packages/games/src/dungeon/types';
import type { Position } from '../../../../packages/games/src/dungeon/types';
import type { RoomState } from '../types';

// ── Linearity literals (mirror Linearity enum) ─────────────────

export const RELEVANT = 3;
export const AFFINE = 2;
export const LINEAR = 1;

// ── Ownership buckets ──────────────────────────────────────────

export const WORLD_OWNER = (() => {
  const a = new Uint8Array(16);
  a[0] = 0x60;
  return a;
})();

export const PLAYER_OWNER = (() => {
  const a = new Uint8Array(16);
  a[0] = 0x61;
  return a;
})();

// ── Spatial helpers ────────────────────────────────────────────

/**
 * Find a free FLOOR position in `state` — a tile not occupied by a live
 * monster. Spirals outward from the room centre.
 *
 * Pure: takes the current `RoomState` snapshot and returns a `Position`.
 * No mutation.
 */
export function findFreePosition(state: RoomState): Position {
  const occupied = new Set<string>();
  for (const m of state.monsters) {
    if (m.hp > 0) occupied.add(posKey(m.position));
  }
  const cy = Math.floor(state.height / 2);
  const cx = Math.floor(state.width / 2);

  for (let r = 0; r < Math.max(state.width, state.height); r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        if (y >= 0 && y < state.height && x >= 0 && x < state.width) {
          if (state.tiles[y][x] === Tile.FLOOR && !occupied.has(`${x},${y}`)) {
            return { x, y };
          }
        }
      }
    }
  }
  return { x: cx, y: cy }; // fallback
}

/**
 * Item-pool tier — wider templates unlock as floor depth increases.
 *
 * Pure helper used by the world-generator when populating each room.
 */
export function getItemPool(floorLevel: number): string[] {
  const base = ['healthSmall', 'dagger'];
  if (floorLevel >= 1) base.push('shortSword', 'leather', 'goldPile');
  if (floorLevel >= 2) base.push('longSword', 'chainMail', 'healthLarge', 'gemstone');
  if (floorLevel >= 3) base.push('battleAxe', 'plateMail');
  return base;
}

```
