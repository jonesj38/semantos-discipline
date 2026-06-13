---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.347422+00:00
---

# runtime/intent/src/reducer/index.ts

```ts
/**
 * I-9 — Pass composer.
 *
 * reduceToIntent orchestrates the seven trivium/quadrivium passes in
 * sequence, threading the accumulated partial Intent through each pass
 * and collecting PassResults. The composite confidence is the geometric
 * mean of per-pass confidences.
 *
 * Pass order is fixed:
 *   grammar → logic → rhetoric → arithmetic → geometry → music → astronomy
 *
 * See docs/textbook/32-trivium-quadrivium-intent-reducer.md
 */

import type { CorrelationId, Intent, IntentId, StageEvent } from '../types';
import type { ReducerInputState, GrammarSpec, PassResult, ReducerOptions, ReducerResult, PassFn } from './types';
import { DEFAULT_THRESHOLDS } from './types';
import { grammarPass } from './grammar-pass';
import { logicPass } from './logic-pass';
import { rhetoricPass } from './rhetoric-pass';
import { relationPass } from './relation-pass';
import { analogicalPrefilterPass } from './analogical-prefilter-pass';
import { arithmeticPass } from './arithmetic-pass';
import { geometryPass } from './geometry-pass';
import { musicPass } from './music-pass';
import { astronomyPass } from './astronomy-pass';
import { analogicalRankPass } from './analogical-rank-pass';

const PASSES: PassFn[] = [
  grammarPass,
  logicPass,
  rhetoricPass,
  relationPass,            // RM-030: SCG typed-relation detection
  analogicalPrefilterPass, // WI-B3: between rhetoric/relation and arithmetic
  arithmeticPass,
  geometryPass,
  musicPass,
  astronomyPass,
  analogicalRankPass,      // WI-B4: after astronomy, complete-intent re-score
];

export async function reduceToIntent(
  state: ReducerInputState,
  grammar: GrammarSpec,
  options?: ReducerOptions,
): Promise<ReducerResult> {
  const thresholds = { ...DEFAULT_THRESHOLDS, ...(options?.thresholds ?? {}) };
  const ctx = {
    state,
    grammar,
    priorRejection: options?.priorRejection,
    maxTrustClass: options?.maxTrustClass,
    analogicalLibrary: options?.analogicalLibrary,
    analogicalCapabilities: options?.analogicalCapabilities,
  };

  let accumulated: Partial<Intent> = {
    constraints: [],
    taxonomy: { what: grammar.defaultTaxonomyWhat, how: '', why: '' },
  };

  const passResults: PassResult[] = [];
  const allFlags: string[] = [];

  // RM-090 — per-pass observability. Bound the logger + correlation tag
  // once outside the loop so the emit hot-path is a single function call.
  const logger = options?.logger;
  const correlationId = options?.correlationId ?? null;
  const intentId = options?.intentId ?? null;

  for (const passFn of PASSES) {
    const startedAt = performance.now();
    const result = await passFn(accumulated, ctx);
    const durationMs = performance.now() - startedAt;
    passResults.push(result);
    allFlags.push(...result.flags);

    // Merge contribution into accumulated — later passes override earlier for the same field
    accumulated = deepMergeIntent(accumulated, result.contribution);

    // Flag if below threshold (informational — reducer does not abort on low confidence)
    const threshold = thresholds[result.pass];
    if (result.confidence < threshold) {
      allFlags.push(`${result.pass}: confidence ${result.confidence.toFixed(2)} below threshold ${threshold}`);
    }

    if (logger && correlationId) {
      const event: StageEvent = {
        ts: new Date().toISOString(),
        correlationId,
        intentId,
        stage: 'reducer_pass_completed',
        durationMs,
        hatId: null,
        source: 'nl',
        data: {
          pass: result.pass,
          confidence: result.confidence,
          flags: result.flags,
          contributionKeys: Object.keys(result.contribution),
          skipInComposite: result.skipInComposite ?? false,
          // RM-092 — only the count goes in the event; full alternatives
          // stay on the PassResult for in-process consumers (cheaper
          // traces, no candidate-payload duplication on disk).
          alternativesCount: result.alternatives?.length ?? 0,
        },
      };
      logger.emit(event);
    }
  }

  const compositeConfidence = geometricMean(
    passResults.filter(r => !r.skipInComposite).map(r => r.confidence),
  );

  const intent = finaliseIntent(accumulated, state, grammar);

  return {
    intent,
    passResults,
    confidence: compositeConfidence,
    flags: allFlags,
  };
}

// Re-export types for consumers
export type { ReducerInputState, GrammarSpec, ReducerOptions, ReducerResult, PassResult } from './types';

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function deepMergeIntent(base: Partial<Intent>, override: Partial<Intent>): Partial<Intent> {
  const merged = { ...base };
  for (const [k, v] of Object.entries(override)) {
    const key = k as keyof Intent;
    if (v === undefined) continue;
    if (key === 'constraints' && Array.isArray(base.constraints) && Array.isArray(v)) {
      // Merge constraints — deduplicate by JSON serialisation
      const combined = [...(base.constraints as unknown[]), ...(v as unknown[])];
      const seen = new Set<string>();
      (merged as Record<string, unknown>)[key] = combined.filter(c => {
        const s = JSON.stringify(c);
        return seen.has(s) ? false : (seen.add(s), true);
      });
    } else if (key === 'taxonomy' && base.taxonomy && v) {
      (merged as Record<string, unknown>)[key] = { ...base.taxonomy, ...(v as object) };
    } else if (key === 'producerMeta' && base.producerMeta && v) {
      (merged as Record<string, unknown>)[key] = { ...base.producerMeta, ...(v as object) };
    } else {
      (merged as Record<string, unknown>)[key] = v;
    }
  }
  return merged;
}

function finaliseIntent(accumulated: Partial<Intent>, state: ReducerInputState, grammar: GrammarSpec): Intent {
  const now = new Date().toISOString();
  const id = crypto.randomUUID() as IntentId;

  return {
    id,
    summary: accumulated.summary || state.conversationSummary || state.scopeDescription || `${grammar.extensionId} intent`,
    category: accumulated.category ?? ({ lexicon: grammar.lexicon.name, category: grammar.lexicon.categories[0] } as unknown as Intent['category']),
    taxonomy: {
      what: accumulated.taxonomy?.what ?? grammar.defaultTaxonomyWhat,
      how:  accumulated.taxonomy?.how  ?? 'how.technical.api.rest',
      why:  accumulated.taxonomy?.why  ?? `why.integration.${grammar.extensionId}`,
      where: accumulated.taxonomy?.where,
    },
    action: accumulated.action ?? grammar.actions[0]?.name ?? 'unknown',
    constraints: accumulated.constraints ?? [],
    confidence: accumulated.confidence ?? 0.5,
    source: 'nl',
    producerMeta: accumulated.producerMeta,
  };
}

function geometricMean(values: number[]): number {
  if (values.length === 0) return 0;
  const product = values.reduce((acc, v) => acc * Math.max(v, 0.001), 1);
  return Math.pow(product, 1 / values.length);
}

```
