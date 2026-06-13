---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/policy-hook.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.527455+00:00
---

# packages/game-sdk/src/engine/policy-hook.ts

```ts
/**
 * Policy hook — pre-action gate.
 *
 * Downstream engines bind a `PolicyEvaluator` to `policyPort`. The
 * dispatcher consults it before reducing each action; if the
 * evaluator rejects, the action never reaches the reducer.
 *
 * The evaluator is intentionally minimal: input is the action +
 * current state + a freeform context bag; output is `accept` /
 * `reject` with a reason. Concrete implementations may delegate
 * to the WASM policy kernel, a Lisp evaluator, or a static rule
 * table — all transparent to the dispatcher.
 */

import { port, type Port } from '@semantos/state';

export type PolicyDecision =
  | { decision: 'accept' }
  | { decision: 'reject'; reason: string };

export interface PolicyEvaluator<S = unknown, A = unknown> {
  evaluate(args: {
    action: A;
    state: S;
    context?: Record<string, unknown>;
  }): PolicyDecision | Promise<PolicyDecision>;
}

export const policyPort: Port<PolicyEvaluator> = port<PolicyEvaluator>('policy');

/** A trivial evaluator that accepts everything. Useful as a default. */
export const acceptAllPolicy: PolicyEvaluator = {
  evaluate: () => ({ decision: 'accept' }),
};

/** Convenience: read the bound evaluator or fall back to accept-all. */
export function resolvePolicy(): PolicyEvaluator {
  return policyPort.isBound() ? policyPort.get() : acceptAllPolicy;
}

```
