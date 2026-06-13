---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.835656+00:00
---

# archive/apps-mud/src/host-functions.ts

```ts
/**
 * MUD host functions -- extends dungeon predicates with multiplayer checks.
 *
 * Each predicate is zero-arity: reads from the frozen evaluation context.
 * Returns 1 (true) or 0 (false).
 *
 * Reuses all dungeon predicates and adds:
 *   target-is-player?     -- attack target is another player (PvP)
 *   pvp-enabled?          -- world allows PvP
 *   not-rate-limited?     -- action cooldown check
 *   room-has-capacity?    -- room not at max occupants
 *   at-exit-tile?         -- player is at a room exit
 *   exit-not-locked?      -- the exit isn't locked
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';
import { registerDungeonHostFunctions } from '../../../packages/games/src/dungeon/host-functions';

export function registerMUDHostFunctions(registry: HostFunctionRegistry): void {
  // Register all base dungeon predicates first
  registerDungeonHostFunctions(registry);

  // ── Multiplayer predicates ─────────────────────────────────

  registry.register('target-is-player?', (ctx) =>
    (ctx.targetIsPlayer as boolean) ? 1 : 0,
  );

  registry.register('pvp-enabled?', (ctx) =>
    (ctx.pvpEnabled as boolean) ? 1 : 0,
  );

  registry.register('not-rate-limited?', (ctx) => {
    const lastActionTime = ctx.lastActionTime as number;
    const now = ctx.now as number;
    const cooldownMs = ctx.cooldownMs as number ?? 250;
    return (now - lastActionTime >= cooldownMs) ? 1 : 0;
  });

  registry.register('room-has-capacity?', (ctx) => {
    const occupantCount = ctx.occupantCount as number;
    const maxOccupants = ctx.maxOccupants as number;
    return (occupantCount < maxOccupants) ? 1 : 0;
  });

  registry.register('at-exit-tile?', (ctx) =>
    (ctx.atExitTile as boolean) ? 1 : 0,
  );

  registry.register('exit-not-locked?', (ctx) =>
    !(ctx.exitLocked as boolean) ? 1 : 0,
  );

  // ── PvE attack (no friendly fire) ─────────────────────────

  registry.register('target-not-player?', (ctx) =>
    !(ctx.targetIsPlayer as boolean) ? 1 : 0,
  );
}

```
