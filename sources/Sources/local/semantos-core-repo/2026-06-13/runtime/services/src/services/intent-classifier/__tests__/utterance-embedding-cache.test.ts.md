---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/utterance-embedding-cache.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.122297+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/utterance-embedding-cache.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { embeddingServicePort } from '../ports';
import {
  clearUtteranceEmbeddingCache,
  EMBEDDING_TIMEOUT_MS,
  getUtteranceEmbedding,
  utteranceEmbeddingCacheAtom,
} from '../utterance-embedding-cache';
import { get } from '@semantos/state';

afterEach(() => {
  embeddingServicePort.unbind();
  clearUtteranceEmbeddingCache();
});

const stub = (overrides: Partial<{ ready: boolean; vec: Float32Array | null; ranked: Array<{ path: string; score: number }>; delayMs: number; throws: boolean }> = {}) => ({
  isReady: () => overrides.ready ?? true,
  embedQuery: async (_q: string) => {
    if (overrides.throws) throw new Error('embed-fail');
    if (overrides.delayMs) {
      await new Promise((r) => setTimeout(r, overrides.delayMs));
    }
    return overrides.vec === undefined ? new Float32Array([1, 2, 3]) : overrides.vec;
  },
  nearest: () => overrides.ranked ?? [{ path: 'create.job', score: 0.8 }],
  similarityToQuery: () => 0,
});

describe('getUtteranceEmbedding', () => {
  test('1. returns null when no port is bound', async () => {
    expect(await getUtteranceEmbedding('hi')).toBeNull();
  });

  test('2. returns null when service is not ready', async () => {
    embeddingServicePort.bind(stub({ ready: false }));
    expect(await getUtteranceEmbedding('hi')).toBeNull();
  });

  test('3. returns null when embedQuery resolves null', async () => {
    embeddingServicePort.bind(stub({ vec: null }));
    expect(await getUtteranceEmbedding('hi')).toBeNull();
  });

  test('4. returns null when embedQuery throws', async () => {
    embeddingServicePort.bind(stub({ throws: true }));
    expect(await getUtteranceEmbedding('hi')).toBeNull();
  });

  test('5. returns null when embedQuery exceeds the timeout', async () => {
    embeddingServicePort.bind(stub({ delayMs: EMBEDDING_TIMEOUT_MS + 200 }));
    const out = await getUtteranceEmbedding('slow');
    expect(out).toBeNull();
  });

  test('6. returns vector + ranked + latency on success', async () => {
    embeddingServicePort.bind(stub());
    const out = await getUtteranceEmbedding('hi');
    expect(out?.vector.length).toBe(3);
    expect(out?.ranked).toEqual([{ path: 'create.job', score: 0.8 }]);
    expect(out?.latencyMs).toBeGreaterThanOrEqual(0);
  });

  test('7. caches results by utterance', async () => {
    let calls = 0;
    embeddingServicePort.bind({
      isReady: () => true,
      embedQuery: async () => {
        calls++;
        return new Float32Array([calls]);
      },
      nearest: () => [],
      similarityToQuery: () => 0,
    });
    await getUtteranceEmbedding('same');
    await getUtteranceEmbedding('same');
    expect(calls).toBe(1);
    expect(get(utteranceEmbeddingCacheAtom).has('same')).toBe(true);
  });

  test('8. clearUtteranceEmbeddingCache empties the atom', async () => {
    embeddingServicePort.bind(stub());
    await getUtteranceEmbedding('seed');
    expect(get(utteranceEmbeddingCacheAtom).size).toBe(1);
    clearUtteranceEmbeddingCache();
    expect(get(utteranceEmbeddingCacheAtom).size).toBe(0);
  });
});

```
