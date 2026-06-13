---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.402332+00:00
---

# packages/games/src/dungeon/policies.ts

```ts
/**
 * Dungeon policies -- Lisp s-expressions compiled to WASM opcodes.
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

// ── Policy Sources (Lisp S-Expressions) ──────────────────────

/** Movement: in-bounds, not a wall/closed door */
export const MOVE_POLICY = `(and (is-move?) (in-bounds?) (not-wall?))`;

/** Attack: adjacent to target, have a weapon, target is a monster */
export const ATTACK_POLICY = `(and (is-attack?) (adjacent-to-target?) (has-weapon?) (target-is-monster?))`;

/** Pickup: at or adjacent to item, inventory not full */
export const PICKUP_POLICY = `(and (is-pickup?) (at-or-adjacent?) (inventory-not-full?))`;

/** Use item: have the item, item is usable */
export const USE_ITEM_POLICY = `(and (is-use?) (has-item?) (item-usable?))`;

/** Open door: adjacent, target is a door, unlocked or have matching key */
export const OPEN_DOOR_POLICY = `(and (is-open?) (adjacent-to-target?) (target-is-door?) (or (door-unlocked?) (has-matching-key?)))`;

// ── Compiled Policy Cache ────────────────────────────────────

export interface CompiledDungeonPolicies {
  move: ScriptOutput;
  attack: ScriptOutput;
  pickup: ScriptOutput;
  useItem: ScriptOutput;
  openDoor: ScriptOutput;
}

const POLICY_MAP: Record<string, string> = {
  move: MOVE_POLICY,
  attack: ATTACK_POLICY,
  pickup: PICKUP_POLICY,
  useItem: USE_ITEM_POLICY,
  openDoor: OPEN_DOOR_POLICY,
};

/** Compile all dungeon policies once at init. */
export function compileDungeonPolicies(): CompiledDungeonPolicies {
  const compiler = new LispCompiler({ compiledAt: 'dungeon-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledDungeonPolicies;
}

```
