---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.398576+00:00
---

# packages/games/src/chess/policies.ts

```ts
/**
 * Chess move policies — Lisp s-expressions compiled to opcodes.
 *
 * Each policy is a constraint expression that compiles to an opcode sequence
 * via LispCompiler. At runtime, the WASM cell engine evaluates the opcodes,
 * dispatching zero-arity predicates via OP_CALLHOST to the HostFunctionRegistry.
 *
 * All predicates read from a frozen evaluation context set before WASM execution.
 */

import { parseExpression } from '../../../shell/src/lisp/parser';
import { LispCompiler } from '../../../shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../shell/src/lisp/types';

// ── Policy Sources (Lisp S-Expressions) ──────────────────────────

export const PAWN_POLICY = `(and
  (is-pawn?)
  (or
    (and (forward-one?) (square-empty?))
    (and (on-start-rank?) (forward-two?) (square-empty?) (path-clear?))
    (and (diagonal-one-forward?) (has-enemy-piece?))
    (and (diagonal-one-forward?) (en-passant-target?))))`;

export const KNIGHT_POLICY = `(and (is-knight?) (l-shape?) (target-not-friendly?))`;

export const BISHOP_POLICY = `(and (is-bishop?) (diagonal-path?) (path-clear?) (target-not-friendly?))`;

export const ROOK_POLICY = `(and (is-rook?) (orthogonal-path?) (path-clear?) (target-not-friendly?))`;

export const QUEEN_POLICY = `(and
  (is-queen?)
  (or (diagonal-path?) (orthogonal-path?))
  (path-clear?)
  (target-not-friendly?))`;

export const KING_POLICY = `(and
  (is-king?)
  (or
    (and (one-square-any-direction?) (target-not-friendly?))
    (and (not (moved?))
         (kingside-castle-target?)
         (kingside-rook-unmoved?)
         (kingside-path-clear?)
         (not-in-check?)
         (no-check-through-path?))
    (and (not (moved?))
         (queenside-castle-target?)
         (queenside-rook-unmoved?)
         (queenside-path-clear?)
         (not-in-check?)
         (no-check-through-path?))))`;

// ── Compiled Policy Cache ────────────────────────────────────────

export interface CompiledPolicies {
  pawn: ScriptOutput;
  knight: ScriptOutput;
  bishop: ScriptOutput;
  rook: ScriptOutput;
  queen: ScriptOutput;
  king: ScriptOutput;
}

const POLICY_MAP: Record<string, string> = {
  pawn: PAWN_POLICY,
  knight: KNIGHT_POLICY,
  bishop: BISHOP_POLICY,
  rook: ROOK_POLICY,
  queen: QUEEN_POLICY,
  king: KING_POLICY,
};

/** Compile all chess policies once at init. */
export function compileChessPolicies(): CompiledPolicies {
  const compiler = new LispCompiler({ compiledAt: 'chess-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledPolicies;
}

```
