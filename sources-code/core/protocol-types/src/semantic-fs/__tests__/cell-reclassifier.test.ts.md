---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/cell-reclassifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.905358+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/cell-reclassifier.test.ts

```ts
/**
 * cell-reclassifier integration tests — drives the full
 * tombstone + new-cell-with-prevStateHash sequence end-to-end.
 */

import { describe, expect, test } from 'bun:test';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { CellStore } from '../../cell-store/cell-store-facade';
import { reclassifyCell } from '../cell-reclassifier';
import { resolvePath } from '../tombstone-resolver';
import { computeTypeHash } from '../type-hasher';
import { hexFromBuffer } from '../../cell-store/content-hasher';
import { deserializeCellHeader } from '../../cell-header';
import { FLAGS_TOMBSTONE } from '../types';
import { makeTaxonomy } from './fixtures';

const taxonomy = makeTaxonomy();

async function setup(): Promise<{ adapter: MemoryAdapter; store: CellStore }> {
  const adapter = new MemoryAdapter();
  const store = new CellStore(adapter);
  return { adapter, store };
}

async function seedAtPlumbing(store: CellStore, payload = 'job-data'): Promise<void> {
  await store.put(
    'objects/create/job/plumbing/job-1',
    new TextEncoder().encode(payload),
    { typeHash: await computeTypeHash(['create', 'job', 'plumbing']) },
  );
}

describe('reclassifyCell', () => {
  test('1. throws when the source cell does not exist', async () => {
    const { store } = await setup();
    await expect(
      reclassifyCell(
        store,
        taxonomy,
        'objects/create/job/plumbing/missing',
        'objects/create/job/electric/missing',
      ),
    ).rejects.toThrow(/Cannot reclassify/);
  });

  test('2. writes a tombstone at the old path with FLAGS_TOMBSTONE set', async () => {
    const { adapter, store } = await setup();
    await seedAtPlumbing(store);
    await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    const oldBytes = (await adapter.read('objects/create/job/plumbing/job-1'))!;
    const oldHeader = deserializeCellHeader(oldBytes);
    expect(oldHeader.flags & FLAGS_TOMBSTONE).toBe(FLAGS_TOMBSTONE);
  });

  test('3. tombstone payload encodes the new storage key, NUL-terminated', async () => {
    const { adapter, store } = await setup();
    await seedAtPlumbing(store);
    await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    const bytes = (await adapter.read('objects/create/job/plumbing/job-1'))!;
    // payload starts at HEADER_SIZE; read until the first NUL.
    const HEADER_SIZE = 256;
    let end = HEADER_SIZE;
    while (end < bytes.length && bytes[end] !== 0) end++;
    const redirect = new TextDecoder().decode(bytes.subarray(HEADER_SIZE, end));
    expect(redirect).toBe('objects/create/job/electric/job-1');
  });

  test('4. tombstone followed via resolvePath lands at the new location', async () => {
    const { adapter, store } = await setup();
    await seedAtPlumbing(store);
    await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    expect(
      await resolvePath(adapter, 'objects/create/job/plumbing/job-1'),
    ).toBe('objects/create/job/electric/job-1');
  });

  test('5. new cell at the destination carries the moved payload', async () => {
    const { store } = await setup();
    await seedAtPlumbing(store, 'pumpkin');
    const result = await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    expect(result.tombstone.cellHash).not.toBe(result.newVersion.cellHash);
    const fresh = await store.get('objects/create/job/electric/job-1');
    expect(new TextDecoder().decode(fresh?.payload ?? new Uint8Array())).toBe('pumpkin');
  });

  test('6. new cell prevStateHash hex matches the tombstone cellHash', async () => {
    const { adapter, store } = await setup();
    await seedAtPlumbing(store);
    const result = await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    const newBytes = (await adapter.read('objects/create/job/electric/job-1'))!;
    const newHeader = deserializeCellHeader(newBytes);
    expect(hexFromBuffer(newHeader.prevStateHash)).toBe(result.tombstone.cellHash);
  });

  test('7. new cell typeHash reflects the destination taxonomy', async () => {
    const { adapter, store } = await setup();
    await seedAtPlumbing(store);
    await reclassifyCell(
      store,
      taxonomy,
      'objects/create/job/plumbing/job-1',
      'objects/create/job/electric/job-1',
    );
    const newBytes = (await adapter.read('objects/create/job/electric/job-1'))!;
    const newHeader = deserializeCellHeader(newBytes);
    const expected = await computeTypeHash(['create', 'job', 'electric']);
    expect(hexFromBuffer(newHeader.typeHash)).toBe(hexFromBuffer(expected));
  });

  test('8. invalid destination (no taxonomy) throws', async () => {
    const { store } = await setup();
    await seedAtPlumbing(store);
    await expect(
      reclassifyCell(
        store,
        taxonomy,
        'objects/create/job/plumbing/job-1',
        'objects',
      ),
    ).rejects.toThrow();
  });
});

```
