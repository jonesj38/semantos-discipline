---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/intent-classifier-core.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.105441+00:00
---

# runtime/services/src/services/intent-classifier/intent-classifier-core.ts

```ts
/**
 * IntentClassifier core entry point — `classifyIntent` orchestrates
 * embedding → fast-path → hierarchy → flat-fallback. Mirrors the
 * pre-split monolith's behaviour exactly; ports replace the
 * module-level setters.
 */

import type {
  ClassificationContext,
  ClassificationResult,
  IntentClassification,
} from '../intent-types';
import { UNKNOWN_CLASSIFICATION, UNKNOWN_INTENT } from '../intent-types';
import { findFlow } from '../FlowRegistry';
import { intentTaxonomy } from '../IntentTaxonomy';
import type { ExtensionConfig } from '../../config/extensionConfig';
import { callBoundLlm } from './llm-transport';
import { getSettings, type ClassifierSettings } from './ports';
import { buildFlatSystemPrompt } from './prompt-builders';
import { parseFlatClassification } from './response-parsers';
import { tryFastPath, traverseHierarchy } from './taxonomy-navigator';
import { getUtteranceEmbedding } from './utterance-embedding-cache';

/**
 * Classify a user message against the active extension config.
 *
 *  1. No API key → UNKNOWN_CLASSIFICATION (graceful degradation).
 *  2. Taxonomy registered → fast-path → hierarchy.
 *  3. No taxonomy → flat fallback.
 */
export async function classifyIntent(
  message: string,
  context: ClassificationContext,
  settings?: ClassifierSettings,
  config?: ExtensionConfig,
): Promise<ClassificationResult> {
  const resolvedSettings = resolveSettings(settings);
  if (!resolvedSettings.openRouterApiKey) {
    return { ...UNKNOWN_CLASSIFICATION };
  }

  const embeddingResult = await getUtteranceEmbedding(message);

  if (intentTaxonomy.hasExtensions()) {
    const fastResult = await tryFastPath(message, resolvedSettings, embeddingResult);
    if (fastResult) {
      if (config && !fastResult.flowId) {
        const flow = findFlow(fastResult.intent, [], config);
        if (flow) fastResult.flowId = flow.id;
      }
      return fastResult;
    }

    const hierarchyResult = await traverseHierarchy(message, resolvedSettings, embeddingResult);
    if (config && !hierarchyResult.flowId) {
      const flow = findFlow(hierarchyResult.intent, [], config);
      if (flow) hierarchyResult.flowId = flow.id;
    }
    return hierarchyResult;
  }

  const flat = await flatClassify(message, context, resolvedSettings);
  return { ...flat, path: [], llmCallCount: 1, fastPath: false };
}

/** Build a ClassificationContext from an extension config (utility). */
export function buildContextFromConfig(
  config: {
    name: string;
    objectTypes: { name: string }[];
    taxonomy?: { dimensions: { nodes: { path: string; children?: { path: string }[] }[] }[] };
    flows?: { id: string }[];
  },
  extras?: { activeHatName?: string; currentObjectType?: string; recentMessages?: string[] },
): ClassificationContext {
  const taxonomyPaths: string[] = [];
  if (config.taxonomy) {
    for (const dim of config.taxonomy.dimensions) {
      for (const node of dim.nodes) {
        taxonomyPaths.push(node.path);
        if (node.children) {
          for (const child of node.children) taxonomyPaths.push(child.path);
        }
      }
    }
  }

  return {
    extensionName: config.name,
    objectTypes: config.objectTypes.map((t) => t.name),
    taxonomyPaths,
    flowIds: (config.flows ?? []).map((f) => f.id),
    ...extras,
  };
}

async function flatClassify(
  message: string,
  context: ClassificationContext,
  settings: ClassifierSettings,
): Promise<IntentClassification> {
  const systemPrompt = buildFlatSystemPrompt(context);
  const response = await callBoundLlm(systemPrompt, message, settings);
  if (!response) {
    return { ...UNKNOWN_INTENT, extractedFields: { error: 'no LLM response' } };
  }
  return parseFlatClassification(response);
}

function resolveSettings(settings?: ClassifierSettings): ClassifierSettings {
  if (settings) return settings;
  return getSettings().getSettings();
}

```
