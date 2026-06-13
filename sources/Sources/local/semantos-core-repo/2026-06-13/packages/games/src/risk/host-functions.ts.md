---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.408866+00:00
---

# packages/games/src/risk/host-functions.ts

```ts
/**
 * Risk host functions — registered with HostFunctionRegistry.
 *
 * Each predicate is zero-arity: reads from the frozen evaluation context.
 * Returns 1 (true) or 0 (false).
 *
 * Context shape (frozen before WASM evaluation):
 *   action: 'reinforce' | 'attack' | 'fortify'
 *   player: number
 *   territory: number            // target territory
 *   fromTerritory: number        // source territory (attack/fortify)
 *   armies: number               // armies involved
 *   reinforcementsRemaining: number
 *   owners: number[]             // 42-element: owner of each territory
 *   armyCounts: number[]         // 42-element: armies on each territory
 *   adjacency: (tid: number) => Set<number>
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';
import { areAdjacent, hasPath, getAdjacent } from './map';

// ── Context Accessors ───────────────────────────────────────────

function player(ctx: HostFunctionContext): number { return ctx.player as number; }
function territory(ctx: HostFunctionContext): number { return ctx.territory as number; }
function fromTerritory(ctx: HostFunctionContext): number { return ctx.fromTerritory as number; }
function armies(ctx: HostFunctionContext): number { return ctx.armies as number; }
function owners(ctx: HostFunctionContext): number[] { return ctx.owners as number[]; }
function armyCounts(ctx: HostFunctionContext): number[] { return ctx.armyCounts as number[]; }
function reinforcements(ctx: HostFunctionContext): number { return ctx.reinforcementsRemaining as number; }
function action(ctx: HostFunctionContext): string { return ctx.action as string; }

// ── Registration ────────────────────────────────────────────────

export function registerRiskHostFunctions(registry: HostFunctionRegistry): void {
  // ── Action type predicates ──────────────────────────────────

  registry.register('is-reinforce?', (ctx) =>
    action(ctx) === 'reinforce' ? 1 : 0,
  );

  registry.register('is-attack?', (ctx) =>
    action(ctx) === 'attack' ? 1 : 0,
  );

  registry.register('is-fortify?', (ctx) =>
    action(ctx) === 'fortify' ? 1 : 0,
  );

  // ── Ownership predicates ────────────────────────────────────

  registry.register('owns-territory?', (ctx) =>
    owners(ctx)[territory(ctx)] === player(ctx) ? 1 : 0,
  );

  registry.register('owns-from?', (ctx) =>
    owners(ctx)[fromTerritory(ctx)] === player(ctx) ? 1 : 0,
  );

  registry.register('enemy-territory?', (ctx) =>
    owners(ctx)[territory(ctx)] !== player(ctx) ? 1 : 0,
  );

  // ── Adjacency predicates ────────────────────────────────────

  registry.register('is-adjacent?', (ctx) =>
    areAdjacent(fromTerritory(ctx), territory(ctx)) ? 1 : 0,
  );

  registry.register('has-connected-path?', (ctx) =>
    hasPath(fromTerritory(ctx), territory(ctx), owners(ctx)) ? 1 : 0,
  );

  // ── Army predicates ─────────────────────────────────────────

  registry.register('has-armies-to-attack?', (ctx) =>
    armyCounts(ctx)[fromTerritory(ctx)] >= 2 ? 1 : 0,
  );

  registry.register('armies-positive?', (ctx) =>
    armies(ctx) >= 1 ? 1 : 0,
  );

  registry.register('reinforcements-sufficient?', (ctx) =>
    armies(ctx) <= reinforcements(ctx) ? 1 : 0,
  );

  registry.register('leaves-one-army?', (ctx) =>
    armies(ctx) < armyCounts(ctx)[fromTerritory(ctx)] ? 1 : 0,
  );

  // ── Adjacency to enemy (for strategic queries) ─────────────

  registry.register('from-borders-enemy?', (ctx) => {
    const p = player(ctx);
    const from = fromTerritory(ctx);
    for (const neighbor of getAdjacent(from)) {
      if (owners(ctx)[neighbor] !== p) return 1;
    }
    return 0;
  });

  registry.register('territory-borders-enemy?', (ctx) => {
    const p = player(ctx);
    const t = territory(ctx);
    for (const neighbor of getAdjacent(t)) {
      if (owners(ctx)[neighbor] !== p) return 1;
    }
    return 0;
  });
}

```
