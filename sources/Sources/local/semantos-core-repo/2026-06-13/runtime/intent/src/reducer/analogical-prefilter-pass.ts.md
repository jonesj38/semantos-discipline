---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/analogical-prefilter-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.349122+00:00
---

# runtime/intent/src/reducer/analogical-prefilter-pass.ts

```ts
/**
 * WI-B3 — Trivium/quadrivium interstitial pass: analogical pre-filter.
 *
 * Sits between rhetoric and arithmetic in the pass pipeline. At this point
 * the accumulated partial Intent has:
 *   - taxonomy.what   (from grammar pass)
 *   - taxonomy.how    (from logic pass)
 *   - category        (from rhetoric pass)
 *   - action          (from rhetoric pass)
 *
 * The pass encodes those fields as a query HRR via `encodePartialIntent`,
 * queries the HRR library for the top-K most similar stored cells, and writes
 * the results to `producerMeta.candidateTemplates`.
 *
 * When the library is absent or empty the pass returns an empty contribution
 * with confidence=1 (vacuously satisfied — a cold library is not a failure).
 *
 * The pass is injected with the library through `PassContext.analogicalLibrary`
 * so it remains pure and unit-testable without a live library.
 *
 * See research/cognition-implementation-plan.md §WI-B3.
 */

import { encodePartialIntent } from '@semantos/hrr';
import type { PassFn, PassResult } from './types';

const TOP_K = 5;

export const analogicalPrefilterPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { grammar } = ctx;
  const lib = ctx.analogicalLibrary ?? null;
  const capabilities = ctx.analogicalCapabilities ?? new Set<number>();

  // Cold library → vacuous pass (no candidates, full confidence)
  if (!lib) {
    return vacuous();
  }

  const juralCategory = accumulated.category?.category;
  if (!juralCategory) {
    return vacuous();
  }

  const query = encodePartialIntent({
    domainFlag: grammar.domainFlag,
    juralCategory,
    lexicon: grammar.lexicon.name,
    action: accumulated.action,
    objectType: accumulated.taxonomy?.what,
    trustClass: grammar.trustClass,
  });

  const candidates = lib.nearest(query, grammar.domainFlag, juralCategory, TOP_K, capabilities);

  if (candidates.length === 0) {
    return vacuous();
  }

  return {
    pass: 'analogical_prefilter',
    contribution: {
      producerMeta: {
        candidateTemplates: candidates.map(c => ({
          templateCellId: c.cellId,
          similarity: c.similarity,
        })),
      },
    },
    confidence: 1,
    flags: [],
  };
};

function vacuous(): PassResult {
  return {
    pass: 'analogical_prefilter',
    contribution: { producerMeta: { candidateTemplates: [] } },
    confidence: 1,
    flags: [],
    skipInComposite: true,
  };
}

```
