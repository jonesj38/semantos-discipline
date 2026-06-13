---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/arithmetic-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.348277+00:00
---

# runtime/intent/src/reducer/arithmetic-pass.ts

```ts
/**
 * I-5 — Quadrivium pass 1: Arithmetic.
 *
 * Maps numeric fields → SIRConstraint { kind: 'value' }[].
 *
 * Handles cost estimates (AUD cents) and any other numeric quantities
 * present in the ReducerInputState.
 */

import type { SIRConstraint } from '@semantos/semantos-sir';
import type { PassFn, PassResult } from './types';

export const arithmeticPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state } = ctx;
  const constraints: SIRConstraint[] = [...(accumulated.constraints ?? [])];
  const flags: string[] = [];
  let signals = 0;

  if (state.estimatedCostMin != null) {
    constraints.push({
      kind: 'value',
      field: 'estimatedCostMin',
      op: '>=',
      value: state.estimatedCostMin,
    });
    signals++;
  }

  if (state.estimatedCostMax != null) {
    constraints.push({
      kind: 'value',
      field: 'estimatedCostMax',
      op: '<=',
      value: state.estimatedCostMax,
    });
    signals++;
  }

  // Also scan taggedFacts for numeric quantities not captured in structured fields
  for (const fact of state.taggedFacts) {
    // Dollar amounts (cost/invoice)
    const amountMatch = fact.fact.match(/\$\s*([\d,]+(?:\.\d+)?)/);
    if (amountMatch && state.estimatedCostMin == null) {
      const cents = Math.round(parseFloat(amountMatch[1].replace(/,/g, '')) * 100);
      constraints.push({ kind: 'value', field: 'amount', op: '=', value: cents });
      signals++;
      continue;
    }

    // Numeric setpoint / measurement values (temperature °C, pressure bar, level m, etc.)
    const setpointMatch = fact.fact.match(/to\s+([\d.]+)\s*(?:°[CF]|bar|m\b|%|rpm|kPa|psi)/i);
    if (setpointMatch) {
      const val = parseFloat(setpointMatch[1]);
      constraints.push({ kind: 'value', field: 'setpoint', op: '=', value: val });
      signals++;
      continue;
    }

    // Interlock threshold values (above/below N <unit>)
    const interlockThreshold = fact.fact.match(/(?:above|below|exceeds?|threshold)\s+([\d.]+)/i);
    if (interlockThreshold && fact.category === 'interlock') {
      const val = parseFloat(interlockThreshold[1]);
      constraints.push({ kind: 'value', field: 'interlockThreshold', op: '>=', value: val });
      signals++;
    }

    // Interlock constraint — when category is 'interlock', emit a named interlock constraint
    if (fact.category === 'interlock') {
      const idMatch = fact.fact.match(/([A-Z]{2,}-\d+)/);
      const policyId = idMatch ? idMatch[1] : `interlock-${signals}`;
      constraints.push({ kind: 'interlock', policyId, policyName: fact.fact.slice(0, 60) });
      signals++;
    }
  }

  const confidence = signals > 0 ? 0.85 : 1.0; // 1.0 when no numerics — pass is vacuously satisfied
  return {
    pass: 'arithmetic',
    contribution: { constraints },
    confidence,
    flags,
  };
};

```
