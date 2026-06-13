---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.408309+00:00
---

# packages/games/src/risk/policies.ts

```ts
/**
 * Risk policies — Lisp s-expressions compiled to opcodes.
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

// ── Policy Sources (Lisp S-Expressions) ─────────────────────────

/**
 * Reinforce policy: player must own the territory, have positive armies,
 * and have sufficient reinforcements remaining.
 */
export const REINFORCE_POLICY = `(and
  (is-reinforce?)
  (owns-territory?)
  (armies-positive?)
  (reinforcements-sufficient?))`;

/**
 * Attack policy: player must own the source, target must be enemy,
 * territories must be adjacent, and source must have 2+ armies.
 */
export const ATTACK_POLICY = `(and
  (is-attack?)
  (owns-from?)
  (enemy-territory?)
  (is-adjacent?)
  (has-armies-to-attack?))`;

/**
 * Fortify policy: player must own both territories, they must be
 * connected by a path of friendly territories, and moving armies
 * must leave at least 1 behind.
 */
export const FORTIFY_POLICY = `(and
  (is-fortify?)
  (owns-from?)
  (owns-territory?)
  (has-connected-path?)
  (armies-positive?)
  (leaves-one-army?))`;

// ── Compiled Policy Cache ───────────────────────────────────────

export interface CompiledRiskPolicies {
  reinforce: ScriptOutput;
  attack: ScriptOutput;
  fortify: ScriptOutput;
}

const POLICY_MAP: Record<string, string> = {
  reinforce: REINFORCE_POLICY,
  attack: ATTACK_POLICY,
  fortify: FORTIFY_POLICY,
};

/** Compile all Risk policies once at init. */
export function compileRiskPolicies(): CompiledRiskPolicies {
  const compiler = new LispCompiler({ compiledAt: 'risk-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledRiskPolicies;
}

```
