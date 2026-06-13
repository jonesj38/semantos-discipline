---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/rhetoric-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.351213+00:00
---

# runtime/intent/src/reducer/rhetoric-pass.ts

```ts
/**
 * I-4 — Trivium pass 3: Rhetoric.
 *
 * Maps taggedFacts → TaggedCategory + action (speech act classification).
 *
 * The rhetoric pass selects the action verb from the grammar's action
 * vocabulary and constructs the TaggedCategory. It picks the action
 * whose category matches the dominant tagged fact, preferring the
 * highest-confidence fact.
 */

import type { TaggedCategory } from '@semantos/semantos-sir';
import type { PassAlternative, PassFn, PassResult } from './types';
import { MAX_PASS_ALTERNATIVES } from './types';

export const rhetoricPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state, grammar } = ctx;
  const flags: string[] = [];

  // 1. Find the dominant fact (highest confidence, valid category)
  const rankedFacts = state.taggedFacts
    .filter(f => grammar.lexicon.categories.includes(f.category))
    .slice()
    .sort((a, b) => b.confidence - a.confidence);
  let dominantFact = rankedFacts[0];

  if (!dominantFact) {
    flags.push('rhetoric: no taggedFacts with valid grammar category; falling back to declaration');
    dominantFact = {
      lexicon: grammar.lexicon.name,
      category: grammar.lexicon.categories[0] ?? 'declaration',
      confidence: 0.2,
      fact: state.conversationSummary ?? '',
      source: 'fallback',
    };
  }

  // 2. Find the best matching action for the dominant category
  const matchingActions = grammar.actions.filter(a => a.category === dominantFact.category);
  let bestAction = matchingActions[0];

  if (matchingActions.length > 1) {
    // Score actions by matching keywords in scope/summary
    const text = (state.scopeDescription ?? state.conversationSummary ?? '').toLowerCase();
    bestAction = matchingActions.reduce((best, action) => {
      const keyword = action.name.replace(/_/g, ' ');
      return text.includes(keyword) ? action : best;
    }, matchingActions[0]);
  }

  if (!bestAction) {
    flags.push(`rhetoric: no action matches category '${dominantFact.category}'; using default`);
    bestAction = grammar.actions[0];
  }

  // 3. Build why coordinate from grammar's intent
  const why = resolveWhy(bestAction.category, grammar.extensionId);

  // 4. Construct TaggedCategory — cast required as the lexicon names are runtime strings
  const taggedCategory = {
    lexicon: grammar.lexicon.name,
    category: dominantFact.category,
  } as unknown as TaggedCategory;

  const confidence = dominantFact.confidence > 0 ? Math.min(dominantFact.confidence, 1) : 0.2;
  if (confidence < 0.7) flags.push(`rhetoric: low confidence action '${bestAction.name}' (${confidence.toFixed(2)})`);

  // RM-092 — surface the losing tagged-fact candidates that lost to
  // the winner. The pass picks a category; if multiple tagged facts
  // scored, the losers (strictly below the winner's confidence) are
  // surfaced for trace consumers. Skip the first entry (winner).
  const alternatives: PassAlternative[] = rankedFacts.length > 1
    ? rankedFacts
        .slice(1, 1 + MAX_PASS_ALTERNATIVES)
        .filter((f) => f.confidence < dominantFact.confidence)
        .map((f) => ({
          candidate: { category: f.category, fact: f.fact, source: f.source },
          confidence: f.confidence,
          reason:
            `category '${f.category}' (${f.confidence.toFixed(2)}) lost to ` +
            `'${dominantFact.category}' (${dominantFact.confidence.toFixed(2)})`,
        }))
    : [];

  return {
    pass: 'rhetoric',
    contribution: {
      action: bestAction.name,
      category: taggedCategory,
      summary: state.conversationSummary ?? state.scopeDescription ?? '',
      source: 'nl',
      confidence,
      taxonomy: {
        what: accumulated.taxonomy?.what ?? '',
        how: accumulated.taxonomy?.how ?? '',
        why,
        where: accumulated.taxonomy?.where,
      },
    },
    confidence,
    flags,
    ...(alternatives.length > 0 ? { alternatives } : {}),
  };
};

function resolveWhy(category: string, extensionId: string): string {
  const WHY_MAP: Record<string, string> = {
    declaration:     'why.integration.property-management',
    obligation:      'why.obligation.fulfillment',
    power:           'why.governance.authorise',
    condition:       'why.governance.condition',
    transfer:        'why.commercial.payment',
    measurement:     'why.operational.monitoring',
    setpoint:        'why.operational.control',
    actuation:       'why.operational.command',
    interlock:       'why.safety.interlock',
    alarm:           'why.safety.alert',
    acknowledgement: 'why.operational.acknowledge',
    calibration:     'why.operational.calibrate',
  };
  return WHY_MAP[category] ?? `why.integration.${extensionId}`;
}

```
