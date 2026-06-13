---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/confidence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.342753+00:00
---

# runtime/intent/src/confidence.ts

```ts
/**
 * confidence — inferred score for NL/voice-originated Intents.
 *
 * LLMs are bad at calibrated self-confidence (doc Decision #2). We
 * compute a composite 0–1 score from four deterministic signals:
 *
 *   1. Required-field fill rate  — how many required Intent fields the
 *      producer supplied vs. left blank.
 *   2. Constraint validation     — fraction of constraints that pass
 *      the extension's field-shape check.
 *   3. Action-verb presence      — is intent.action in the extension's
 *      known action vocabulary?
 *   4. Taxonomy resolution       — do intent.taxonomy coordinates
 *      resolve to known nodes in the extension's taxonomy?
 *
 * Each signal is in [0,1]; the composite is the unweighted mean.
 * Tune weights later if one signal proves noisier than the others.
 *
 * The score drives trustClass gating (doc Decision #2 thresholds);
 * `processIntent` maps the composite to a candidate trust tier.
 */

import type { Intent } from './types';

export interface ConfidenceContext {
  /** Action verbs this extension understands. */
  actionVocabulary: ReadonlySet<string>;
  /** Whether a constraint's referenced fields resolve in this extension. */
  validateConstraintFields: (intent: Intent) => { valid: number; total: number };
  /** Whether a taxonomy coordinate triple resolves to known nodes. */
  taxonomyResolves: (what: string, how: string, why: string) => boolean;
}

export interface ConfidenceBreakdown {
  requiredFieldFill: number;
  constraintValidation: number;
  actionVerbKnown: number;
  taxonomyResolved: number;
  composite: number;
}

/**
 * Score the producer's output. Deterministic given the same Intent +
 * grammar. Used only for NL / voice; other sources bypass this and
 * set intent.confidence directly.
 */
export function score(intent: Intent, grammar: ConfidenceContext): ConfidenceBreakdown {
  // Signal 1 — required-field fill rate.
  // We treat summary, category, taxonomy, action as the always-required
  // fields. constraints array may be empty (no-op intents are legal).
  const requiredFilled = [
    intent.summary.length > 0,
    Boolean(intent.category),
    Boolean(intent.taxonomy?.what && intent.taxonomy.how && intent.taxonomy.why),
    intent.action.length > 0,
  ].filter(Boolean).length;
  const requiredFieldFill = requiredFilled / 4;

  // Signal 2 — constraint validation.
  const { valid, total } = grammar.validateConstraintFields(intent);
  const constraintValidation = total === 0 ? 1 : valid / total;

  // Signal 3 — action verb known.
  const actionVerbKnown = grammar.actionVocabulary.has(intent.action) ? 1 : 0;

  // Signal 4 — taxonomy resolves.
  const taxonomyResolved = grammar.taxonomyResolves(
    intent.taxonomy.what,
    intent.taxonomy.how,
    intent.taxonomy.why,
  )
    ? 1
    : 0;

  const composite =
    (requiredFieldFill + constraintValidation + actionVerbKnown + taxonomyResolved) / 4;

  return {
    requiredFieldFill,
    constraintValidation,
    actionVerbKnown,
    taxonomyResolved,
    composite,
  };
}

```
