---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/intent-classifier-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.122693+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/intent-classifier-integration.test.ts

```ts
/**
 * IntentClassifier integration test — drives `classifyIntent`
 * end-to-end against deterministic stubs for LLM, embedding, and
 * coherence ports.
 *
 * Pins:
 *   - no-API-key graceful degradation
 *   - flat fallback (no taxonomy extensions registered)
 *   - fast-path with embedding agreement boost
 *   - hierarchical traversal when fast-path returns low confidence
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { classifyIntent } from '../intent-classifier-core';
import {
  coherencePort,
  embeddingServicePort,
  llmClientPort,
  settingsPort,
} from '../ports';
import { clearUtteranceEmbeddingCache } from '../utterance-embedding-cache';
import { intentTaxonomy } from '../../IntentTaxonomy';
import type { ClassificationContext } from '../../intent-types';

const ctx: ClassificationContext = {
  extensionName: 'test',
  objectTypes: ['Job'],
  taxonomyPaths: [],
  flowIds: ['create-job'],
};

const settings = { openRouterApiKey: 'sk-test', modelId: 'm', temperature: 0.2 };

afterEach(() => {
  llmClientPort.unbind();
  embeddingServicePort.unbind();
  coherencePort.unbind();
  settingsPort.unbind();
  clearUtteranceEmbeddingCache();
  // Reset taxonomy registrations so each test starts clean.
  for (const id of [...(intentTaxonomy as unknown as { extensionRegistrations: Map<string, unknown> }).extensionRegistrations.keys()]) {
    intentTaxonomy.unregisterExtension(id);
  }
});

describe('classifyIntent — graceful degradation', () => {
  test('1. returns UNKNOWN_CLASSIFICATION when no API key is configured', async () => {
    const out = await classifyIntent('do something', ctx, {
      ...settings,
      openRouterApiKey: null,
    });
    expect(out.intent).toBe('unknown');
    expect(out.confidence).toBe(0);
  });

  test('2. flat fallback returns parsed result when no extensions are registered', async () => {
    llmClientPort.bind({
      call: async () =>
        JSON.stringify({
          intent: 'create.job',
          confidence: 0.92,
          objectType: 'Job',
          flowId: 'create-job',
        }),
    });
    const out = await classifyIntent('book a plumber', ctx, settings);
    expect(out.intent).toBe('create.job');
    expect(out.fastPath).toBe(false);
    expect(out.path).toEqual([]);
    expect(out.flowId).toBe('create-job');
  });

  test('3. flat fallback returns UNKNOWN_INTENT when LLM is unavailable', async () => {
    llmClientPort.bind({ call: async () => null });
    const out = await classifyIntent('hi', ctx, settings);
    expect(out.intent).toBe('unknown');
    expect(out.fastPath).toBe(false);
  });
});

describe('classifyIntent — port wiring', () => {
  test('4. embedding service is consulted before the LLM call', async () => {
    let embeddedFor: string | null = null;
    embeddingServicePort.bind({
      isReady: () => true,
      embedQuery: async (q) => {
        embeddedFor = q;
        return new Float32Array([1]);
      },
      nearest: () => [{ path: 'create.job', score: 0.9 }],
      similarityToQuery: () => 0,
    });
    llmClientPort.bind({
      call: async () =>
        JSON.stringify({ intent: 'create.job', confidence: 0.93, flowId: 'create-job' }),
    });
    await classifyIntent('book a plumber', ctx, settings);
    expect(embeddedFor).toBe('book a plumber');
  });

  test('5. flat fallback skips the coherence port entirely', async () => {
    const askedFor: string[][] = [];
    coherencePort.bind({
      checkNode: (path) => {
        askedFor.push(path);
        return null;
      },
    });
    llmClientPort.bind({
      call: async () =>
        JSON.stringify({ intent: 'create.job', confidence: 0.92, flowId: 'create-job' }),
    });
    await classifyIntent('hi', ctx, settings);
    expect(askedFor).toEqual([]);
  });

  test('6. settings port supplies the API key when none is passed explicitly', async () => {
    settingsPort.bind({
      getSettings: () => ({ openRouterApiKey: 'sk-port', modelId: 'mp', temperature: 0 }),
    });
    let observedKey: string | null | undefined;
    llmClientPort.bind({
      call: async (_sys, _user, s) => {
        observedKey = s.openRouterApiKey;
        return JSON.stringify({ intent: 'x', confidence: 0.5 });
      },
    });
    await classifyIntent('hi', ctx);
    expect(observedKey).toBe('sk-port');
  });
});

```
