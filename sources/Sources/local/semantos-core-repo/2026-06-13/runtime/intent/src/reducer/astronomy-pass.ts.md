---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/astronomy-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.350611+00:00
---

# runtime/intent/src/reducer/astronomy-pass.ts

```ts
/**
 * I-8 — Quadrivium pass 4: Astronomy.
 *
 * Maps domain flag + confidence → GovernanceContext (as a domain constraint).
 *
 * "Astronomy" in the quadrivium was the study of number in motion through
 * space — the governance pass anchors the intent in its domain (the
 * governance binding that controls which nodes can execute it) and
 * applies the trust-class ceiling from the grammar and hat context.
 */

import type { SIRConstraint } from '@semantos/semantos-sir';
import type { PassFn, PassResult } from './types';

export const astronomyPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { grammar, maxTrustClass } = ctx;
  const constraints: SIRConstraint[] = [...(accumulated.constraints ?? [])];
  const flags: string[] = [];

  // 1. Domain constraint — binds the intent to the grammar's domain
  constraints.push({ kind: 'domain', flag: grammar.domainFlag });

  // 2. Trust-class ceiling enforcement
  const grammarTrustClass = grammar.trustClass ?? 'cosmetic';
  const effectiveTrustClass = maxTrustClass
    ? lowerOf(grammarTrustClass, maxTrustClass)
    : grammarTrustClass;

  if (grammar.trustClass === 'authoritative' && grammar.proofRequirement !== 'formal') {
    flags.push(
      `astronomy: grammar declares trustClass='authoritative' but proofRequirement='${grammar.proofRequirement ?? 'none'}' (should be 'formal')`,
    );
  }

  if (maxTrustClass && effectiveTrustClass !== grammarTrustClass) {
    flags.push(
      `astronomy: grammar trustClass '${grammarTrustClass}' capped to '${effectiveTrustClass}' by hat context`,
    );
  }

  return {
    pass: 'astronomy',
    contribution: {
      constraints,
      // GovernanceContext is not a direct field on Intent — it flows through
      // the domain constraint and is resolved by processIntent. We encode it
      // in producerMeta so downstream can inspect without polluting Intent.
      producerMeta: {
        governanceContext: {
          trustClass: effectiveTrustClass,
          proofRequirement: grammar.proofRequirement ?? 'none',
          domainFlag: grammar.domainFlag,
          extensionId: grammar.extensionId,
        },
      },
    },
    confidence: 0.9, // astronomy is deterministic given the grammar + hat context
    flags,
  };
};

const TRUST_ORDER = ['cosmetic', 'interpretive', 'authoritative'] as const;
type TrustClass = (typeof TRUST_ORDER)[number];

function lowerOf(a: TrustClass, b: TrustClass): TrustClass {
  const ai = TRUST_ORDER.indexOf(a);
  const bi = TRUST_ORDER.indexOf(b);
  return TRUST_ORDER[Math.min(ai, bi)] ?? 'cosmetic';
}

```
