---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/rejection-relay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.350312+00:00
---

# runtime/intent/src/reducer/rejection-relay.ts

```ts
/**
 * I-10 — Rejection relay.
 *
 * Maps SIR rejection codes to the pass that produced the failing field.
 * When processIntent returns a rejection, the relay marks the responsible
 * pass for re-execution on the next attempt with the rejection in context.
 *
 * Rejection → pass mapping:
 *   INVALID_TAXONOMY_PATH      → grammar, logic
 *   UNKNOWN_ACTION             → rhetoric
 *   CONSTRAINT_FIELD_MISSING   → arithmetic, geometry, music
 *   DOMAIN_FLAG_MISMATCH       → astronomy
 *   TRUST_CLASS_EXCEEDED       → astronomy
 *   PROOF_REQUIREMENT_UNMET    → astronomy
 */

import type { IntentRejection } from '../types';
import type { Pass } from './types';

const REJECTION_CODE_TO_PASSES: Record<string, Pass[]> = {
  INVALID_TAXONOMY_PATH:    ['grammar', 'logic'],
  TAXONOMY_WHAT_UNKNOWN:    ['grammar'],
  TAXONOMY_HOW_UNKNOWN:     ['logic'],
  TAXONOMY_WHY_UNKNOWN:     ['logic', 'rhetoric'],
  UNKNOWN_ACTION:           ['rhetoric'],
  CATEGORY_MISMATCH:        ['rhetoric'],
  CONSTRAINT_FIELD_MISSING: ['arithmetic', 'geometry', 'music'],
  VALUE_CONSTRAINT_INVALID: ['arithmetic'],
  TEMPORAL_INVALID:         ['music'],
  DOMAIN_FLAG_MISMATCH:     ['astronomy'],
  TRUST_CLASS_EXCEEDED:     ['astronomy'],
  PROOF_REQUIREMENT_UNMET:  ['astronomy'],
  CAPABILITY_MISSING:       ['astronomy'],
};

export interface RejectionRelay {
  /** Passes the relay considers responsible for the rejection. */
  failedPasses: Pass[];
  /** Human-readable summary for the pass context. */
  summary: string;
}

export function buildRejectionRelay(rejection: IntentRejection): RejectionRelay {
  const failedPasses = REJECTION_CODE_TO_PASSES[rejection.code] ?? [];
  return {
    failedPasses,
    summary: `[${rejection.stage}/${rejection.code}] ${rejection.message}`,
  };
}

```
