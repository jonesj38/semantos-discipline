---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.404281+00:00
---

# packages/games/src/dungeon/host-functions.ts

```ts
/**
 * Dungeon host functions -- registered with HostFunctionRegistry.
 *
 * Each predicate is zero-arity: reads from the frozen evaluation context.
 * Returns 1 (true) or 0 (false).
 *
 * Context shape (frozen before WASM evaluation):
 *   action: 'move' | 'attack' | 'pickup' | 'use' | 'open'
 *   playerX: number
 *   playerY: number
 *   targetX: number
 *   targetY: number
 *   mapWidth: number
 *   mapHeight: number
 *   targetTile: number          // Tile enum value at target position
 *   hasWeapon: boolean
 *   targetIsMonster: boolean
 *   inventoryCount: number
 *   inventoryMax: number
 *   hasItem: boolean
 *   itemUsable: boolean
 *   doorLocked: boolean
 *   hasMatchingKey: boolean
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';
import { Tile } from './types';

// ── Context Accessors ──────────────────────────────────────────

function action(ctx: HostFunctionContext): string { return ctx.action as string; }
function targetTile(ctx: HostFunctionContext): number { return ctx.targetTile as number; }

// ── Registration ───────────────────────────────────────────────

export function registerDungeonHostFunctions(registry: HostFunctionRegistry): void {
  // ── Action type predicates ─────────────────────────────────

  registry.register('is-move?', (ctx) =>
    action(ctx) === 'move' ? 1 : 0,
  );

  registry.register('is-attack?', (ctx) =>
    action(ctx) === 'attack' ? 1 : 0,
  );

  registry.register('is-pickup?', (ctx) =>
    action(ctx) === 'pickup' ? 1 : 0,
  );

  registry.register('is-use?', (ctx) =>
    action(ctx) === 'use' ? 1 : 0,
  );

  registry.register('is-open?', (ctx) =>
    action(ctx) === 'open' ? 1 : 0,
  );

  // ── Movement predicates ───────────────────────────────────

  registry.register('in-bounds?', (ctx) => {
    const tx = ctx.targetX as number;
    const ty = ctx.targetY as number;
    const w = ctx.mapWidth as number;
    const h = ctx.mapHeight as number;
    return (tx >= 0 && tx < w && ty >= 0 && ty < h) ? 1 : 0;
  });

  registry.register('not-wall?', (ctx) => {
    const tile = targetTile(ctx);
    // Passable: FLOOR, DOOR_OPEN, STAIRS_DOWN, STAIRS_UP
    // Blocked: WALL, DOOR_CLOSED, DOOR_LOCKED
    return (tile !== Tile.WALL && tile !== Tile.DOOR_CLOSED && tile !== Tile.DOOR_LOCKED) ? 1 : 0;
  });

  // ── Combat predicates ─────────────────────────────────────

  registry.register('adjacent-to-target?', (ctx) => {
    const dx = Math.abs((ctx.playerX as number) - (ctx.targetX as number));
    const dy = Math.abs((ctx.playerY as number) - (ctx.targetY as number));
    return (dx + dy === 1) ? 1 : 0;
  });

  registry.register('has-weapon?', (ctx) =>
    (ctx.hasWeapon as boolean) ? 1 : 0,
  );

  registry.register('target-is-monster?', (ctx) =>
    (ctx.targetIsMonster as boolean) ? 1 : 0,
  );

  // ── Pickup predicates ─────────────────────────────────────

  registry.register('at-or-adjacent?', (ctx) => {
    const dx = Math.abs((ctx.playerX as number) - (ctx.targetX as number));
    const dy = Math.abs((ctx.playerY as number) - (ctx.targetY as number));
    return (dx + dy <= 1) ? 1 : 0;
  });

  registry.register('inventory-not-full?', (ctx) =>
    (ctx.inventoryCount as number) < (ctx.inventoryMax as number) ? 1 : 0,
  );

  // ── Use item predicates ───────────────────────────────────

  registry.register('has-item?', (ctx) =>
    (ctx.hasItem as boolean) ? 1 : 0,
  );

  registry.register('item-usable?', (ctx) =>
    (ctx.itemUsable as boolean) ? 1 : 0,
  );

  // ── Door predicates ───────────────────────────────────────

  registry.register('target-is-door?', (ctx) => {
    const tile = targetTile(ctx);
    return (tile === Tile.DOOR_CLOSED || tile === Tile.DOOR_LOCKED) ? 1 : 0;
  });

  registry.register('door-unlocked?', (ctx) =>
    !(ctx.doorLocked as boolean) ? 1 : 0,
  );

  registry.register('has-matching-key?', (ctx) =>
    (ctx.hasMatchingKey as boolean) ? 1 : 0,
  );
}

```
