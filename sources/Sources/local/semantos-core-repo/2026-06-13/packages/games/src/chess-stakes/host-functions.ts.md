---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.414927+00:00
---

# packages/games/src/chess-stakes/host-functions.ts

```ts
/**
 * Doubling Cube Host Functions — zero-arity predicates for cube policies.
 *
 * Each predicate reads from a frozen evaluation context set before
 * policy evaluation, exactly like the chess move predicates.
 *
 * Context shape:
 *   cubeState: "centered" | "held" | "offered"
 *   cubeHolder: "white" | "black" | null
 *   cubeValue: 1 | 2 | 4 | 8 | 16 | 32 | 64
 *   activeColor: "white" | "black"         — whose turn it is
 *   respondingColor: "white" | "black"     — opponent of offerer (set when offered)
 *   gameStatus: "playing" | "check" | "checkmate" | "stalemate" | "draw"
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';
import type { CubeValue } from './types';
import { CUBE_VALUES } from './types';

const MAX_CUBE_VALUE: CubeValue = 64;

/** Register all doubling cube predicates with the host function registry. */
export function registerCubeHostFunctions(registry: HostFunctionRegistry): void {

  // ── Game state predicates ───────────────────────────────────

  /** Game is still in progress (not over). */
  registry.register('game-in-progress?', (ctx) => {
    const status = ctx.gameStatus as string;
    return (status === 'playing' || status === 'check') ? 1 : 0;
  });

  // ── Cube state predicates ───────────────────────────────────

  /** Cube is in the 'centered' state (start of game, no holder). */
  registry.register('cube-centered?', (ctx) =>
    (ctx.cubeState === 'centered') ? 1 : 0);

  /** A double is currently offered (awaiting take/drop). */
  registry.register('cube-offered?', (ctx) =>
    (ctx.cubeState === 'offered') ? 1 : 0);

  /** Cube value is below the maximum (64). Can still double. */
  registry.register('cube-below-max?', (ctx) =>
    ((ctx.cubeValue as number) < MAX_CUBE_VALUE) ? 1 : 0);

  // ── Ownership predicates ────────────────────────────────────

  /**
   * Active player is the cube holder.
   * True when:
   *   - cubeState is 'held' AND cubeHolder === activeColor
   * (When centered, this returns false — use cube-centered? instead.)
   */
  registry.register('is-cube-holder?', (ctx) =>
    (ctx.cubeState === 'held' && ctx.cubeHolder === ctx.activeColor) ? 1 : 0);

  /**
   * Current player is the one who must respond to an offer.
   * True when cubeState is 'offered' and the current player is
   * the respondingColor (the opponent of whoever offered).
   */
  registry.register('is-response-player?', (ctx) =>
    (ctx.cubeState === 'offered' && ctx.activeColor === ctx.respondingColor) ? 1 : 0);
}

```
