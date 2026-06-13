---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/go/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.412642+00:00
---

# packages/games/src/go/policies.ts

```ts
/**
 * Go placement policy -- Lisp s-expression compiled to opcodes.
 *
 * The policy is a constraint expression that compiles to an opcode sequence
 * via LispCompiler. At runtime, the WASM cell engine evaluates the opcodes,
 * dispatching zero-arity predicates via OP_CALLHOST to the HostFunctionRegistry.
 *
 * All predicates read from a frozen evaluation context set before WASM execution.
 */

import { parseExpression } from '../../../shell/src/lisp/parser';
import { LispCompiler } from '../../../shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../shell/src/lisp/types';

// -- Policy Source (Lisp S-Expression) ------------------------------------

export const PLACEMENT_POLICY = `(and (intersection-empty?) (not-suicide?) (not-ko-violation?))`;

// -- Compiled Policy Cache ------------------------------------------------

export interface CompiledGoPolicy {
  placement: ScriptOutput;
}

/** Compile the Go placement policy once at init. */
export function compileGoPolicy(): CompiledGoPolicy {
  const compiler = new LispCompiler({ compiledAt: 'go-init' });
  const expr = parseExpression(PLACEMENT_POLICY);
  const placement = compiler.compile(expr);
  return { placement };
}

```
