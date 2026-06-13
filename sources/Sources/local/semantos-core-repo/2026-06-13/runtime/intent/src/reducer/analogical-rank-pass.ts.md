---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/analogical-rank-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.349523+00:00
---

# runtime/intent/src/reducer/analogical-rank-pass.ts

```ts
/**
 * WI-B4 — Trivium/quadrivium final pass: analogical rank.
 *
 * Runs after astronomy (last pass) when the accumulated Intent is complete.
 * At this point accumulated has:
 *   - category, action        (from rhetoric)
 *   - taxonomy.what/.how      (from grammar / logic)
 *   - constraints             (from arithmetic)
 *   - taxonomy.where          (from geometry)
 *   - producerMeta.candidateTemplates  (from WI-B3 prefilter)
 *
 * The pass re-encodes the complete intent using encodePartialIntent with all
 * available fields (richer than the WI-B3 query) and re-queries the library.
 * Results are written to producerMeta.analogicalMatches.
 *
 * When the library is absent or WI-B3 produced no candidates the pass returns
 * vacuously with confidence=1 and an empty analogicalMatches array.
 *
 * See research/cognition-implementation-plan.md §WI-B4.
 */

import { encodePartialIntent } from '@semantos/hrr';
import type { PassFn, PassResult } from './types';

const TOP_K = 5;

export const analogicalRankPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { grammar } = ctx;
  const lib = ctx.analogicalLibrary ?? null;
  const capabilities = ctx.analogicalCapabilities ?? new Set<number>();

  if (!lib) return vacuous(accumulated);

  const juralCategory = accumulated.category?.category;
  if (!juralCategory) return vacuous(accumulated);

  const candidates: Array<{ templateCellId: string; similarity: number }> =
    ((accumulated.producerMeta as Record<string, unknown> | undefined)?.candidateTemplates as Array<{ templateCellId: string; similarity: number }> | undefined) ?? [];

  if (candidates.length === 0) return vacuous(accumulated);

  const query = encodePartialIntent({
    domainFlag:   grammar.domainFlag,
    juralCategory,
    lexicon:      grammar.lexicon.name,
    action:       accumulated.action,
    objectType:   accumulated.taxonomy?.what,
    trustClass:   grammar.trustClass,
    howTaxonomy:  accumulated.taxonomy?.how,
  });

  const ranked = lib.nearest(query, grammar.domainFlag, juralCategory, TOP_K, capabilities);

  return {
    pass: 'analogical_rank',
    contribution: {
      producerMeta: {
        analogicalMatches: ranked.map(r => ({
          templateCellId: r.cellId,
          similarity: r.similarity,
        })),
      },
    },
    confidence: 1,
    flags: [],
  };
};

function vacuous(accumulated: Parameters<PassFn>[0]): PassResult {
  const existing = (accumulated.producerMeta as Record<string, unknown> | undefined) ?? {};
  return {
    pass: 'analogical_rank',
    contribution: {
      producerMeta: { ...existing, analogicalMatches: [] },
    },
    confidence: 1,
    flags: [],
    skipInComposite: true,
  };
}

```
