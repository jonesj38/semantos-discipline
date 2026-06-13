---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/semantic-search.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.905066+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/semantic-search.test.ts

```ts
/**
 * semantic-search tests — covers both the embeddingPort path and
 * direct-options path, plus the not-ready / no-vector / no-results
 * graceful degradations.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { embeddingPort, searchEmbedded } from '../semantic-search';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { CellStore } from '../../cell-store/cell-store-facade';
import { makeEmbeddingStub } from './fixtures';

afterEach(() => embeddingPort.unbind());

async function seedTwoObjects(): Promise<MemoryAdapter> {
  const adapter = new MemoryAdapter();
  const store = new CellStore(adapter);
  await store.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('p1'));
  await store.put('objects/create/job/electric/job-2', new TextEncoder().encode('e1'));
  return adapter;
}

describe('searchEmbedded', () => {
  test('1. returns [] when no provider is bound and no override is supplied', async () => {
    const adapter = await seedTwoObjects();
    expect(await searchEmbedded(adapter, 'plumb')).toEqual([]);
  });

  test('2. returns [] when the provider is not ready', async () => {
    const adapter = await seedTwoObjects();
    const out = await searchEmbedded(adapter, 'plumb', {
      embeddings: makeEmbeddingStub({ ready: false }),
    });
    expect(out).toEqual([]);
  });

  test('3. returns [] when embedQuery yields null', async () => {
    const adapter = await seedTwoObjects();
    const provider = makeEmbeddingStub();
    provider.embedQuery = async () => null;
    expect(await searchEmbedded(adapter, 'plumb', { embeddings: provider })).toEqual([]);
  });

  test('4. uses the embeddingPort when bound', async () => {
    const adapter = await seedTwoObjects();
    embeddingPort.bind(makeEmbeddingStub());
    const out = await searchEmbedded(adapter, 'plumb');
    expect(out.length).toBeGreaterThan(0);
    expect(out[0]?.matchedPath).toBe('create.job.plumbing');
  });

  test('5. caller-supplied embeddings option wins over the port', async () => {
    const adapter = await seedTwoObjects();
    embeddingPort.bind(makeEmbeddingStub({ nearest: [{ path: 'create.job.electric', score: 0.9 }] }));
    const out = await searchEmbedded(adapter, 'electric', {
      embeddings: makeEmbeddingStub({ nearest: [{ path: 'create.job.plumbing', score: 0.7 }] }),
    });
    expect(out[0]?.matchedPath).toBe('create.job.plumbing');
  });

  test('6. limits results to the supplied limit', async () => {
    const adapter = await seedTwoObjects();
    const out = await searchEmbedded(adapter, 'job', {
      limit: 1,
      embeddings: makeEmbeddingStub(),
    });
    expect(out).toHaveLength(1);
  });

  test('7. results are sorted by descending score', async () => {
    const adapter = await seedTwoObjects();
    const provider = makeEmbeddingStub({
      nearest: [
        { path: 'create.job.plumbing', score: 0.4 },
        { path: 'create.job.electric', score: 0.9 },
      ],
    });
    const out = await searchEmbedded(adapter, 'job', { embeddings: provider, limit: 5 });
    expect(out.map((h) => h.score)).toEqual([0.9, 0.4]);
    expect(out[0]?.matchedPath).toBe('create.job.electric');
  });

  test('8. yields one hit per object under each matched taxonomy path', async () => {
    const adapter = new MemoryAdapter();
    const store = new CellStore(adapter);
    await store.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('a'));
    await store.put('objects/create/job/plumbing/job-2', new TextEncoder().encode('b'));
    const out = await searchEmbedded(adapter, 'job', {
      embeddings: makeEmbeddingStub({ nearest: [{ path: 'create.job.plumbing', score: 1 }] }),
      limit: 10,
    });
    expect(out).toHaveLength(2);
  });
});

```
