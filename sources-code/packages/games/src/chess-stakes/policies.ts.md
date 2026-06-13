---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.414374+00:00
---

# packages/games/src/chess-stakes/policies.ts

```ts
/**
 * Doubling Cube Policies — Lisp s-expressions compiled to opcodes.
 *
 * These policies govern when a double can be offered and when a
 * response (take/drop) is valid. They compile to opcode sequences
 * via LispCompiler, just like the chess move policies.
 *
 * All predicates are zero-arity — they read from a frozen evaluation
 * context set before WASM execution.
 */

import { parseExpression } from '../../../shell/src/lisp/parser';
import { LispCompiler } from '../../../shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../shell/src/lisp/types';

// ── Policy Sources (Lisp S-Expressions) ──────────────────────────

/**
 * Can the active player offer a double?
 *
 * Evaluation context:
 *   cube-state: "centered" | "held" | "offered"
 *   cube-holder: "white" | "black" | null
 *   active-color: "white" | "black"
 *   cube-value: 1 | 2 | 4 | ... | 64
 *   game-status: "playing" | "check" | ...
 *
 * Rules:
 *   1. Game must be in progress (playing or check — not over)
 *   2. Cube must not already be offered (no double-double)
 *   3. Cube value must be < 64 (can't exceed max)
 *   4. If cube is centered (start of game), either player can double
 *   5. If cube is held, only the holder can double
 */
export const DOUBLE_OFFER_POLICY = `(and
  (game-in-progress?)
  (not (cube-offered?))
  (cube-below-max?)
  (or
    (cube-centered?)
    (is-cube-holder?)))`;

/**
 * Can the responding player take (accept) the double?
 *
 * Evaluation context:
 *   cube-state: must be "offered"
 *   responding-color: the player who must respond
 *   active-color: who offered the double
 *
 * Rules:
 *   1. A double must be currently offered
 *   2. The responder is NOT the one who offered (they're the opponent)
 */
export const TAKE_POLICY = `(and
  (cube-offered?)
  (is-response-player?))`;

/**
 * Can the responding player drop (decline) the double?
 * Same preconditions as take — the choice between take/drop
 * is the player's decision, not a policy distinction.
 */
export const DROP_POLICY = `(and
  (cube-offered?)
  (is-response-player?))`;

// ── Compiled Policy Cache ────────────────────────────────────────

export interface CompiledCubePolicies {
  doubleOffer: ScriptOutput;
  take: ScriptOutput;
  drop: ScriptOutput;
}

const CUBE_POLICY_MAP: Record<string, string> = {
  doubleOffer: DOUBLE_OFFER_POLICY,
  take: TAKE_POLICY,
  drop: DROP_POLICY,
};

/** Compile all cube policies once at init. */
export function compileCubePolicies(): CompiledCubePolicies {
  const compiler = new LispCompiler({ compiledAt: 'cube-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(CUBE_POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledCubePolicies;
}

```
