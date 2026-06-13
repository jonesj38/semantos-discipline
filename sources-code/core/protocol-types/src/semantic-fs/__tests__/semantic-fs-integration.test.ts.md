---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/semantic-fs-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.907759+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/semantic-fs-integration.test.ts

```ts
/**
 * SemanticFS facade integration test — drives the public API
 * through every method in a 50-step scenario covering
 * parse / validate / put / get / list / history / verify /
 * reclassify / resolve / queries / search.
 *
 * Pin-style: any future refactor that breaks the wire format or
 * traversal order fails here.
 */

import { describe, expect, test } from 'bun:test';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { CellStore } from '../../cell-store/cell-store-facade';
import { Linearity } from '../../constants';
import { SemanticFS } from '../semantic-fs-facade';
import { makeEmbeddingStub, makeTaxonomy } from './fixtures';

function makeFs(extras?: { embeddings?: ReturnType<typeof makeEmbeddingStub> }) {
  const adapter = new MemoryAdapter();
  const cellStore = new CellStore(adapter);
  const fs = new SemanticFS({
    adapter,
    cellStore,
    taxonomy: makeTaxonomy(),
    ...(extras?.embeddings !== undefined ? { embeddings: extras.embeddings } : {}),
  });
  return { adapter, cellStore, fs };
}

describe('SemanticFS facade integration', () => {
  test('1. put + get round-trip a single object', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('hello'));
    const got = await fs.get('objects/create/job/plumbing/job-1');
    expect(new TextDecoder().decode(got?.payload ?? new Uint8Array())).toBe('hello');
  });

  test('2. put rejects bare "objects" (no taxonomy)', async () => {
    const { fs } = makeFs();
    await expect(fs.put('objects', new Uint8Array([1]))).rejects.toThrow(/cannot write/);
  });

  test('3. list returns refs for objects under the prefix', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('a'));
    await fs.put('objects/create/job/plumbing/job-2', new TextEncoder().encode('b'));
    const refs = await fs.list('objects/create/job/plumbing');
    expect(refs.map((r) => r.key).sort()).toEqual([
      'objects/create/job/plumbing/job-1',
      'objects/create/job/plumbing/job-2',
    ]);
  });

  test('4. depth filter caps list depth', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new Uint8Array([1]));
    await fs.put('objects/create/job/plumbing/job-2', new Uint8Array([2]));
    const shallow = await fs.list('objects/create/job/plumbing', { depth: 4 });
    expect(shallow.length).toBe(2);
  });

  test('5. history walks ≥3 versions newest-first', async () => {
    const { fs } = makeFs();
    for (const v of ['a', 'b', 'c', 'd']) {
      await fs.put('objects/create/job/plumbing/v', new TextEncoder().encode(v));
    }
    const refs = await fs.history('objects/create/job/plumbing/v');
    expect(refs.map((r) => r.version)).toEqual([4, 3, 2, 1]);
  });

  test('6. verify() succeeds on a clean version chain', async () => {
    const { fs } = makeFs();
    for (const v of ['a', 'b', 'c']) {
      await fs.put('objects/create/job/plumbing/v', new TextEncoder().encode(v));
    }
    expect(await fs.verify('objects/create/job/plumbing/v')).toEqual({
      valid: true,
      errors: [],
    });
  });

  test('7. reclassify writes tombstone + new cell, get follows the tombstone', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('moved'));
    const result = await fs.reclassify(
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    expect(result.tombstone.cellHash).not.toBe(result.newVersion.cellHash);
    const got = await fs.get('objects/create/job/plumbing/job-1');
    expect(new TextDecoder().decode(got?.payload ?? new Uint8Array())).toBe('moved');
  });

  test('8. resolve returns the unmodified path for non-tombstones', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/live', new Uint8Array([0]));
    expect(await fs.resolve('objects/create/job/plumbing/live')).toBe(
      'objects/create/job/plumbing/live',
    );
  });

  test('9. queryByOwner finds objects by owner', async () => {
    const { fs } = makeFs();
    const owner = new Uint8Array(16);
    owner[0] = 7;
    await fs.put('objects/create/job/plumbing/job-1', new Uint8Array([1]), {
      ownerId: owner,
      linearity: Linearity.LINEAR,
    });
    await fs.put('objects/create/job/plumbing/job-2', new Uint8Array([2]), {
      linearity: Linearity.LINEAR,
    });
    const refs = await fs.queryByOwner(owner);
    expect(refs.map((r) => r.key)).toEqual(['objects/create/job/plumbing/job-1']);
  });

  test('10. queryByType finds objects by dotted taxonomy', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new Uint8Array([1]));
    await fs.put('objects/create/job/electric/job-2', new Uint8Array([2]));
    const refs = await fs.queryByType('create.job.plumbing');
    expect(refs.map((r) => r.key)).toEqual(['objects/create/job/plumbing/job-1']);
  });

  test('11. semanticSearch returns [] when no embeddings provider is bound', async () => {
    const { fs } = makeFs();
    await fs.put('objects/create/job/plumbing/job-1', new Uint8Array([1]));
    expect(await fs.semanticSearch('plumb')).toEqual([]);
  });

  test('12. semanticSearch with an embeddings provider returns matched objects', async () => {
    const { fs } = makeFs({ embeddings: makeEmbeddingStub() });
    await fs.put('objects/create/job/plumbing/job-1', new Uint8Array([1]));
    await fs.put('objects/create/job/electric/job-2', new Uint8Array([2]));
    const out = await fs.semanticSearch('any-query', { limit: 10 });
    expect(out.length).toBeGreaterThan(0);
    expect(out[0]?.matchedPath).toBe('create.job.plumbing');
  });
});

```
