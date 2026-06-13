---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/policy-gate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.500613+00:00
---

# packages/cdm/cdm/src/lifecycle/policy-gate.ts

```ts
/**
 * Policy gate — Phase 29.5 kernel policy enforcement for CDM events.
 *
 * Maps each lifecycle event to its applicable ISDA policy, compiles
 * the policy via the runtime Lisp compiler, then evaluates it through
 * the supplied `PolicyRuntime`. A `null` runtime short-circuits to
 * `{ ok: true, results: [] }` so callers without policy enforcement
 * still work.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import type {
  PolicyContext,
  PolicyResult,
  PolicyRuntime,
} from '@semantos/policy-runtime';

import type { CDMEventType } from '../types';
import type { TradeEventPayload } from './trade-events';
import { loadAndCompilePolicy, type PolicyName } from '../policies/compiler';

const EVENT_POLICY_MAP: Partial<Record<CDMEventType, PolicyName>> = {
  'payment': 'payment-condition-precedent',
  'default': 'failure-to-pay-default',
  'close-out-netting': 'close-out-netting',
  'novation': 'transfer-consent',
  'margin-call': 'variation-margin',
};

export interface PolicyGateOk {
  ok: true;
  results: PolicyResult[];
}

export interface PolicyGateRejected {
  ok: false;
  error: string;
  results: PolicyResult[];
}

export type PolicyGateResult = PolicyGateOk | PolicyGateRejected;

/** Run the applicable policy for an event. No runtime → no-op pass. */
export async function runPolicyGate(
  runtime: PolicyRuntime | undefined,
  eventType: CDMEventType,
  payload: TradeEventPayload,
  actorCertId: string,
): Promise<PolicyGateResult> {
  if (!runtime) return { ok: true, results: [] };

  const policyName = EVENT_POLICY_MAP[eventType];
  if (!policyName) return { ok: true, results: [] };

  try {
    const compiled = loadAndCompilePolicy(policyName);
    const ctx: PolicyContext = {
      fields: {
        'counterparty-default-status':
          payload['counterparty-default-status'] ?? 'active',
        'payment-status': payload['payment-status'] ?? 'current',
        'days-past-due': payload['days-past-due'] ?? 0,
        'margin-type': payload['margin-type'] ?? '',
        'margin-amount': payload['margin-amount'] ?? 0,
      },
      actor: {
        certId: actorCertId,
        capabilities: (payload['capabilities'] as number[]) ?? [],
      },
    };

    const result = await runtime.evaluate(compiled.scriptBytes, ctx);
    if (!result.ok) {
      return {
        ok: false,
        error: `Policy '${policyName}' rejected: ${result.rejectionDetail ?? result.rejectionCode}`,
        results: [result],
      };
    }
    return { ok: true, results: [result] };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('ENOENT')) {
      // Policy file missing — non-fatal, treat as pass for environments
      // where policies aren't shipped (preserves prompt-29.5 behaviour).
      return { ok: true, results: [] };
    }
    return { ok: false, error: `Policy evaluation error: ${msg}`, results: [] };
  }
}

```
