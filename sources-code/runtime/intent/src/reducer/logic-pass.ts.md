---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/logic-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.350901+00:00
---

# runtime/intent/src/reducer/logic-pass.ts

```ts
/**
 * I-3 — Trivium pass 2: Logic.
 *
 * Maps taggedFacts + action → taxonomy.how (relational binding).
 *
 * The logic pass determines HOW the action is being performed — the
 * protocol/lifecycle axis. It reads the dominant category from tagged
 * facts and the grammar's declared actions to infer the how coordinate.
 */

import type { PassFn, PassResult } from './types';

const CATEGORY_TO_HOW: Record<string, string> = {
  declaration:     'how.lifecycle.create',
  obligation:      'how.lifecycle.obligation',
  power:           'how.lifecycle.authorise',
  condition:       'how.lifecycle.schedule',
  transfer:        'how.commercial.transfer',
  measurement:     'how.technical.observe',
  setpoint:        'how.technical.configure',
  actuation:       'how.technical.command',
  interlock:       'how.technical.safety',
  alarm:           'how.technical.alert',
  acknowledgement: 'how.technical.acknowledge',
  calibration:     'how.technical.calibrate',
};

export const logicPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state, grammar } = ctx;
  const flags: string[] = [];

  // Dominant category: highest-confidence tagged fact's category
  let dominantCategory = '';
  let dominantConfidence = 0;
  for (const fact of state.taggedFacts) {
    if (fact.confidence > dominantConfidence && grammar.lexicon.categories.includes(fact.category)) {
      dominantCategory = fact.category;
      dominantConfidence = fact.confidence;
    }
  }

  const how = CATEGORY_TO_HOW[dominantCategory] ?? 'how.technical.api.rest';
  const confidence = dominantConfidence > 0 ? Math.min(dominantConfidence * 0.9, 1) : 0.3;

  if (!dominantCategory) flags.push('logic: no category resolved from taggedFacts; defaulting how coordinate');
  if (confidence < 0.5) flags.push(`logic: low confidence taxonomy.how '${how}' (${confidence.toFixed(2)})`);

  return {
    pass: 'logic',
    contribution: {
      taxonomy: {
        what: accumulated.taxonomy?.what ?? '',
        how,
        why: accumulated.taxonomy?.why ?? '',
        where: accumulated.taxonomy?.where,
      },
    },
    confidence,
    flags,
  };
};

```
