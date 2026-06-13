---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/content-indexer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.920498+00:00
---

# core/protocol-types/src/cell-store/__tests__/content-indexer.test.ts

```ts
/**
 * ContentIndexer tests — append + dedupe + lookup behaviour against
 * the in-memory storage facade.
 */

import { describe, expect, test } from 'bun:test';
import { ContentIndexer } from '../content-indexer';
import { StorageAdapterFacade } from '../storage-adapter-facade';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import type { ContentIndexEntry } from '../types';

function makeIndexer(): { indexer: ContentIndexer; storage: StorageAdapterFacade } {
  const storage = new StorageAdapterFacade(new MemoryAdapter());
  return { indexer: new ContentIndexer(storage), storage };
}

const entry = (key: string, version = 1): ContentIndexEntry => ({
  key,
  cellHash: 'cellhash:' + key,
  version,
  timestamp: 1700000000000 + version,
});

describe('ContentIndexer', () => {
  test('1. lookup returns [] when the index is empty', async () => {
    const { indexer } = makeIndexer();
    expect(await indexer.lookup('h1')).toEqual([]);
  });

  test('2. append + lookup round-trips a single entry', async () => {
    const { indexer } = makeIndexer();
    await indexer.append('h1', entry('k1'));
    expect(await indexer.lookup('h1')).toEqual([entry('k1')]);
  });

  test('3. append accumulates entries for the same content hash', async () => {
    const { indexer } = makeIndexer();
    await indexer.append('h1', entry('k1', 1));
    await indexer.append('h1', entry('k2', 1));
    const out = await indexer.lookup('h1');
    expect(out.map((e) => e.key)).toEqual(['k1', 'k2']);
  });

  test('4. append dedupes by (key, version)', async () => {
    const { indexer } = makeIndexer();
    await indexer.append('h1', entry('k1', 5));
    await indexer.append('h1', entry('k1', 5));
    expect(await indexer.lookup('h1')).toHaveLength(1);
  });

  test('5. same key with different version is a separate row', async () => {
    const { indexer } = makeIndexer();
    await indexer.append('h1', entry('k1', 1));
    await indexer.append('h1', entry('k1', 2));
    expect(await indexer.lookup('h1')).toHaveLength(2);
  });

  test('6. different content hashes are isolated', async () => {
    const { indexer } = makeIndexer();
    await indexer.append('h1', entry('k1'));
    await indexer.append('h2', entry('k2'));
    expect(await indexer.lookup('h1')).toHaveLength(1);
    expect(await indexer.lookup('h2')).toHaveLength(1);
  });

  test('7. lookup gracefully recovers from corrupt index bytes', async () => {
    const { indexer, storage } = makeIndexer();
    await storage.write('_index/content/garbage', new TextEncoder().encode('{not-json'));
    expect(await indexer.lookup('garbage')).toEqual([]);
  });

  test('8. append after a corrupt index resets to a clean array', async () => {
    const { indexer, storage } = makeIndexer();
    await storage.write('_index/content/h1', new TextEncoder().encode('not-json'));
    await indexer.append('h1', entry('k1'));
    expect(await indexer.lookup('h1')).toEqual([entry('k1')]);
  });
});

```
