---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/life/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.407151+00:00
---

# packages/games/src/life/host-functions.ts

```ts
/**
 * Game of Life host functions — registered with HostFunctionRegistry.
 *
 * Each predicate is zero-arity: reads from the frozen evaluation context.
 * Returns 1 (true) or 0 (false).
 *
 * Context shape (frozen before WASM evaluation):
 *   position: number              // flat index on board
 *   isAlive: boolean              // current state of this cell
 *   neighborCount: number         // count of alive neighbors (0-8)
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';

// ── Context Accessors ───────────────────────────────────────────

function isAlive(ctx: HostFunctionContext): boolean { return ctx.isAlive as boolean; }
function neighborCount(ctx: HostFunctionContext): number { return ctx.neighborCount as number; }

// ── Registration ────────────────────────────────────────────────

export function registerLifeHostFunctions(registry: HostFunctionRegistry): void {
  // ── State predicates ────────────────────────────────────────

  registry.register('alive?', (ctx) =>
    isAlive(ctx) ? 1 : 0,
  );

  registry.register('dead?', (ctx) =>
    !isAlive(ctx) ? 1 : 0,
  );

  // ── Neighbor count predicates ───────────────────────────────

  registry.register('neighbors-eq-2?', (ctx) =>
    neighborCount(ctx) === 2 ? 1 : 0,
  );

  registry.register('neighbors-eq-3?', (ctx) =>
    neighborCount(ctx) === 3 ? 1 : 0,
  );

  registry.register('neighbors-2-or-3?', (ctx) => {
    const n = neighborCount(ctx);
    return (n === 2 || n === 3) ? 1 : 0;
  });

  // ── Derived predicates (for clarity in policies) ────────────

  /** Alive cell with 2 or 3 neighbors → survives. */
  registry.register('survives?', (ctx) => {
    if (!isAlive(ctx)) return 0;
    const n = neighborCount(ctx);
    return (n === 2 || n === 3) ? 1 : 0;
  });

  /** Dead cell with exactly 3 neighbors → born. */
  registry.register('born?', (ctx) => {
    if (isAlive(ctx)) return 0;
    return neighborCount(ctx) === 3 ? 1 : 0;
  });
}

```
