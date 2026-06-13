---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/IntentClassifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.099080+00:00
---

# runtime/services/src/services/IntentClassifier.ts

```ts
/**
 * @deprecated Use `./intent-classifier` (the split) instead. This
 * module is a one-release re-export shim for the new home of the
 * intent classifier under `intent-classifier/`. It will be removed
 * once all consumers have migrated.
 *
 * The split lives in `runtime/services/src/services/intent-classifier/`:
 *   - `ports.ts`                       llmClientPort, embeddingServicePort,
 *                                      coherencePort, settingsPort
 *   - `utterance-embedding-cache.ts`   atom-backed embedding cache
 *   - `confidence-calibrator.ts`       buildEmbeddingHint + calibrate
 *   - `coherence-checker.ts`           pure checkCoherence
 *   - `embedding-ranker.ts`            pure ranking helpers
 *   - `prompt-builders.ts`             every system prompt in one place
 *   - `response-parsers.ts`            pure JSON → typed-result parsers
 *   - `llm-transport.ts`               default OpenRouter client +
 *                                      port-bound dispatcher
 *   - `taxonomy-navigator.ts`          tryFastPath + traverseHierarchy
 *   - `intent-classifier-core.ts`      classifyIntent + buildContextFromConfig
 *
 * Module-level setters (`setSettingsStoreRef`, `setEmbeddingServiceRef`,
 * `setCoherenceRef`) are kept here as compatibility shims that forward
 * to the corresponding port `bind()` calls so existing call sites keep
 * working through the deprecation window.
 */

import { SettingsStore } from './SettingsStore';
import {
  coherencePort,
  embeddingServicePort,
  settingsPort,
  type CoherenceLike,
  type EmbeddingServiceLike,
} from './intent-classifier/ports';

export {
  classifyIntent,
  buildContextFromConfig,
} from './intent-classifier/intent-classifier-core';

export type {
  ClassifierSettings,
  EmbeddingServiceLike,
  CoherenceLike,
} from './intent-classifier/ports';

/** @deprecated bind `settingsPort` instead. */
export function setSettingsStoreRef(store: SettingsStore): void {
  settingsPort.unbind();
  settingsPort.bind({ getSettings: () => store.getSettings() });
}

/** @deprecated bind `embeddingServicePort` instead. */
export function setEmbeddingServiceRef(service: EmbeddingServiceLike): void {
  embeddingServicePort.unbind();
  embeddingServicePort.bind(service);
}

/** @deprecated bind `coherencePort` instead. */
export function setCoherenceRef(coherence: CoherenceLike): void {
  coherencePort.unbind();
  coherencePort.bind(coherence);
}

```
