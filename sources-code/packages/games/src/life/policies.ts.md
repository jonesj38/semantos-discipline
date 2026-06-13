---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/life/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.406853+00:00
---

# packages/games/src/life/policies.ts

```ts
/**
 * Game of Life policies — Lisp s-expressions compiled to opcodes.
 *
 * Conway's rules as a single policy: a cell is alive in the next generation
 * if it survives (alive with 2-3 neighbors) OR is born (dead with 3 neighbors).
 *
 * Evaluated via OP_CALLHOST through the Zig WASM cell engine.
 */

import { parseExpression } from '../../../shell/src/lisp/parser';
import { LispCompiler } from '../../../shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../shell/src/lisp/types';

// ── Policy Source (Lisp S-Expression) ───────────────────────────

/**
 * Conway's Game of Life rule:
 *   alive next gen ← (alive AND 2-or-3 neighbors) OR (dead AND exactly 3 neighbors)
 */
export const CONWAY_POLICY = `(or
  (and (alive?) (neighbors-2-or-3?))
  (and (dead?) (neighbors-eq-3?)))`;

// ── Compiled Policy ─────────────────────────────────────────────

export interface CompiledLifePolicy {
  conway: ScriptOutput;
}

/** Compile the Game of Life policy once at init. */
export function compileLifePolicy(): CompiledLifePolicy {
  const compiler = new LispCompiler({ compiledAt: 'life-init' });
  const expr = parseExpression(CONWAY_POLICY);
  return { conway: compiler.compile(expr) };
}

```
