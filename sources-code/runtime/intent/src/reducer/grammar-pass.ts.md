---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/grammar-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.346596+00:00
---

# runtime/intent/src/reducer/grammar-pass.ts

```ts
/**
 * I-2 — Trivium pass 1: Grammar.
 *
 * Maps taggedFacts → taxonomy.what (structural entity identification).
 *
 * The grammar pass selects the most plausible taxonomy.what coordinate
 * by scoring tagged facts against the grammar's declared objectTypes.
 * High-confidence facts matching a known object type name win; ties
 * break by fact confidence descending.
 */

import type { Intent } from '../types';
import type { PassFn, PassResult } from './types';

export const grammarPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state, grammar } = ctx;
  const flags: string[] = [];
  let bestWhat = grammar.defaultTaxonomyWhat;
  let bestScore = 0;

  const objectTypeNames = new Set(grammar.objectTypes.map(o => o.name));

  for (const fact of state.taggedFacts) {
    for (const ot of grammar.objectTypes) {
      const nameMatch =
        fact.fact.toLowerCase().includes(ot.name.split('.').pop() ?? '') ||
        (state.jobType != null && ot.name.includes(state.jobType.toLowerCase()));
      if (nameMatch && fact.confidence > bestScore) {
        bestWhat = ot.name;
        bestScore = fact.confidence;
      }
    }
  }

  if (state.jobType) {
    const directMatch = grammar.objectTypes.find(ot =>
      ot.name.toLowerCase().includes(state.jobType!.toLowerCase()),
    );
    if (directMatch && bestScore < 0.5) {
      bestWhat = directMatch.name;
      bestScore = 0.5;
    }
  }

  const confidence = bestScore > 0 ? Math.min(bestScore, 1) : 0.3;
  if (confidence < 0.6) flags.push(`grammar: low confidence taxonomy.what '${bestWhat}' (${confidence.toFixed(2)})`);

  return {
    pass: 'grammar',
    contribution: {
      taxonomy: {
        ...((accumulated.taxonomy as Partial<Intent['taxonomy']>) ?? {}),
        what: bestWhat,
        how: accumulated.taxonomy?.how ?? '',
        why: accumulated.taxonomy?.why ?? '',
      },
    },
    confidence,
    flags,
  };
};

```
