---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/taxonomy-navigator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.108144+00:00
---

# runtime/services/src/services/intent-classifier/taxonomy-navigator.ts

```ts
/**
 * Taxonomy navigation — fast-path + level-by-level hierarchy
 * traversal. Pulls the prompt + LLM dance out of the legacy monolith
 * so the entry point can compose them.
 *
 * Behaviour preserved 1:1: same fast-path threshold, same max depth,
 * same baseline confidences, same stop conditions.
 */

import type { ClassificationResult, EmbeddingHint, CoherenceWarning } from '../intent-types';
import { UNKNOWN_CLASSIFICATION } from '../intent-types';
import { intentTaxonomy } from '../IntentTaxonomy';
import { checkCoherence } from './coherence-checker';
import { buildEmbeddingHint, calibrateConfidence } from './confidence-calibrator';
import { rankFastPathByEmbedding } from './embedding-ranker';
import { callBoundLlm } from './llm-transport';
import {
  buildEmbeddingRankedFastPathPrompt,
  buildEmbeddingRankedLevelPrompt,
} from './prompt-builders';
import { parseFastPathResponse, parseLevelResponse } from './response-parsers';
import type { ClassifierSettings } from './ports';
import type { UtteranceEmbeddingResult } from './utterance-embedding-cache';

export const FAST_PATH_CONFIDENCE_THRESHOLD = 0.9;
const HIERARCHY_BASELINE_CONFIDENCE = 0.75;
const MAX_HIERARCHY_DEPTH = 3;

/**
 * Try fast-path classification: a single LLM call with the top-N
 * intents, returning a high-confidence pick or null on miss/timeout.
 */
export async function tryFastPath(
  message: string,
  settings: ClassifierSettings,
  embResult: UtteranceEmbeddingResult | null,
): Promise<ClassificationResult | null> {
  let fastPathIntents = intentTaxonomy.getFastPathIntents(20);
  if (fastPathIntents.length === 0) return null;

  if (embResult) {
    fastPathIntents = rankFastPathByEmbedding(fastPathIntents, embResult);
  }

  const systemPrompt = embResult
    ? buildEmbeddingRankedFastPathPrompt(fastPathIntents, embResult)
    : intentTaxonomy.buildFastPathPrompt(fastPathIntents, message);

  const response = await callBoundLlm(systemPrompt, message, settings);
  if (!response) return null;

  const parsed = parseFastPathResponse(response);
  if (
    !parsed ||
    parsed.intent === 'unknown' ||
    parsed.confidence < FAST_PATH_CONFIDENCE_THRESHOLD
  ) {
    return null;
  }

  const entry = fastPathIntents.find((e) => e.intent === parsed.intent);
  const flowId = parsed.flowId || entry?.flowId;

  let confidence = parsed.confidence;
  let embeddingHint: EmbeddingHint | undefined;
  if (embResult) {
    embeddingHint = buildEmbeddingHint(embResult, parsed.intent);
    confidence = calibrateConfidence(confidence, embeddingHint.confidenceAdjustment);
  }

  const intentPath = entry ? entry.nodeId.split('.') : [parsed.intent];
  const coherenceWarning: CoherenceWarning | undefined = checkCoherence(intentPath) ?? undefined;

  return {
    intent: parsed.intent,
    confidence,
    flowId,
    path: entry ? [entry.nodeId] : [parsed.intent],
    llmCallCount: 1,
    fastPath: true,
    extractedFields: parsed.extractedFields,
    embeddingHint,
    coherenceWarning,
  };
}

/**
 * Walk the taxonomy level by level, calling the LLM at each level.
 * Stops at a leaf or after MAX_HIERARCHY_DEPTH levels.
 */
export async function traverseHierarchy(
  message: string,
  settings: ClassifierSettings,
  embResult: UtteranceEmbeddingResult | null,
): Promise<ClassificationResult> {
  const path: string[] = [];
  let llmCallCount = 0;

  for (let depth = 0; depth < MAX_HIERARCHY_DEPTH; depth++) {
    const options = intentTaxonomy.getOptionsAt(path);
    if (options.length === 0) break;

    const systemPrompt = embResult
      ? buildEmbeddingRankedLevelPrompt(path, options, embResult)
      : intentTaxonomy.buildPrompt(path, message);
    llmCallCount++;

    const response = await callBoundLlm(systemPrompt, message, settings);
    if (!response) break;

    const parsed = parseLevelResponse(response);
    if (!parsed || parsed.selected === 'unknown') break;

    path.push(parsed.selected);

    const node = intentTaxonomy.getNodeAt(path);
    if (!node || !node.children || node.children.length === 0) break;
  }

  if (path.length === 0) {
    return { ...UNKNOWN_CLASSIFICATION, llmCallCount };
  }

  const intentString = path.join('.');
  const flowId = intentTaxonomy.resolveToFlow(path);
  const fastPathMatch = intentTaxonomy.getFastPathMap().get(intentString);

  let confidence = HIERARCHY_BASELINE_CONFIDENCE;
  let embeddingHint: EmbeddingHint | undefined;
  if (embResult) {
    embeddingHint = buildEmbeddingHint(embResult, intentString);
    confidence = calibrateConfidence(confidence, embeddingHint.confidenceAdjustment);
  }

  const coherenceWarning: CoherenceWarning | undefined = checkCoherence(path) ?? undefined;

  return {
    intent: intentString,
    confidence,
    flowId: flowId ?? fastPathMatch?.flowId ?? undefined,
    path,
    llmCallCount,
    fastPath: false,
    embeddingHint,
    coherenceWarning,
  };
}

```
