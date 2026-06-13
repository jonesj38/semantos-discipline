---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.104874+00:00
---

# runtime/services/src/services/intent-classifier/index.ts

```ts
/**
 * IntentClassifier barrel — public surface for the split.
 */

export { classifyIntent, buildContextFromConfig } from './intent-classifier-core';
export {
  llmClientPort,
  embeddingServicePort,
  coherencePort,
  settingsPort,
  getLlmClient,
  getEmbeddingService,
  getCoherence,
  getSettings,
  __resetIntentClassifierPortsForTests,
  type ClassifierSettings,
  type LlmClient,
  type SettingsLike,
  type EmbeddingServiceLike,
  type CoherenceLike,
} from './ports';
export {
  defaultOpenRouterClient,
  bindDefaultOpenRouterClient,
  callBoundLlm,
} from './llm-transport';
export {
  tryFastPath,
  traverseHierarchy,
  FAST_PATH_CONFIDENCE_THRESHOLD,
} from './taxonomy-navigator';
export {
  buildEmbeddingHint,
  calibrateConfidence,
  EMBEDDING_AGREE_BOOST,
  EMBEDDING_DISAGREE_PENALTY,
} from './confidence-calibrator';
export { checkCoherence } from './coherence-checker';
export {
  rankFastPathByEmbedding,
  scoreOptionsForLevel,
  buildScoreMap,
} from './embedding-ranker';
export {
  buildFlatSystemPrompt,
  buildEmbeddingRankedFastPathPrompt,
  buildEmbeddingRankedLevelPrompt,
} from './prompt-builders';
export {
  parseFastPathResponse,
  parseLevelResponse,
  parseFlatClassification,
  type FastPathParsed,
} from './response-parsers';
export {
  utteranceEmbeddingCacheAtom,
  getUtteranceEmbedding,
  clearUtteranceEmbeddingCache,
  EMBEDDING_TIMEOUT_MS,
  EMBEDDING_RANKED_OPTIONS,
  type UtteranceEmbeddingResult,
} from './utterance-embedding-cache';

```
