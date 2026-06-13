---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.107681+00:00
---

# runtime/services/src/services/intent-classifier/ports.ts

```ts
/**
 * Bindable ports for the IntentClassifier split.
 *
 * Replaces the legacy module-level setters
 * (`setEmbeddingServiceRef`, `setCoherenceRef`, `setSettingsStoreRef`)
 * with `@semantos/state` ports so tests bind deterministic stubs and
 * production code wires the live services at boot.
 *
 * Each `getXxx()` resolver falls back to a sensible "feature-off"
 * default when the port is unbound — preserves the legacy graceful-
 * degradation contract.
 */

import { port, type Port } from '@semantos/state';

import { SettingsStore } from '../SettingsStore';

/** Minimal LLM-call interface — the classifier needs only this method. */
export interface LlmClient {
  /**
   * Call the chat completion endpoint with a system + user message
   * pair. Returns the raw `content` string from the assistant message,
   * or null on any failure (network, parse, etc.). Must never throw.
   */
  call(systemPrompt: string, userMessage: string, settings: ClassifierSettings): Promise<string | null>;
}

/** Settings the classifier needs at call time. */
export interface ClassifierSettings {
  openRouterApiKey: string | null;
  modelId: string;
  temperature: number;
}

export interface SettingsLike {
  getSettings(): ClassifierSettings;
}

export interface EmbeddingServiceLike {
  isReady(): boolean;
  embedQuery(utterance: string): Promise<Float32Array | null>;
  nearest(queryVector: Float32Array, n: number): Array<{ path: string; score: number }>;
  similarityToQuery(nodePath: string, queryVector: Float32Array): number;
}

export interface CoherenceLike {
  checkNode(nodePath: string[]): {
    nodePath: string;
    embeddingNearest: string;
    severity: 'info' | 'warning' | 'critical';
  } | null;
}

export const llmClientPort: Port<LlmClient> = port<LlmClient>('intent-llm-client');
export const embeddingServicePort: Port<EmbeddingServiceLike> = port<EmbeddingServiceLike>(
  'intent-embedding-service',
);
export const coherencePort: Port<CoherenceLike> = port<CoherenceLike>('intent-coherence');
export const settingsPort: Port<SettingsLike> = port<SettingsLike>('intent-settings');

/** Resolve the bound LlmClient, or null if unbound. */
export function getLlmClient(): LlmClient | null {
  return llmClientPort.isBound() ? llmClientPort.get() : null;
}

/** Resolve the embedding service, or null when feature is off. */
export function getEmbeddingService(): EmbeddingServiceLike | null {
  return embeddingServicePort.isBound() ? embeddingServicePort.get() : null;
}

/** Resolve the coherence checker, or null when feature is off. */
export function getCoherence(): CoherenceLike | null {
  return coherencePort.isBound() ? coherencePort.get() : null;
}

/**
 * Resolve a settings provider. Falls back to a fresh `SettingsStore`
 * — same lazy behaviour the pre-split code had — so consumers that
 * never bind the port still get sensible defaults.
 */
let _fallbackSettings: SettingsLike | null = null;
export function getSettings(): SettingsLike {
  if (settingsPort.isBound()) return settingsPort.get();
  if (!_fallbackSettings) _fallbackSettings = new SettingsStore();
  return _fallbackSettings;
}

/** Test-only: reset the fallback singleton so other tests start clean. */
export function __resetIntentClassifierPortsForTests(): void {
  _fallbackSettings = null;
}

```
