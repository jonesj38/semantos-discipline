---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/storage-adapter-facade.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.920783+00:00
---

# core/protocol-types/src/cell-store/__tests__/storage-adapter-facade.test.ts

```ts
/**
 * StorageAdapterFacade tests — exercises every named operation
 * (cell/chunk/meta read+write, archivePrevious, list).
 */

import { describe, expect, test } from 'bun:test';
import { StorageAdapterFacade } from '../storage-adapter-facade';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import type { CellMeta } from '../types';

function makeFacade(): { facade: StorageAdapterFacade; adapter: MemoryAdapter } {
  const adapter = new MemoryAdapter();
  return { facade: new StorageAdapterFacade(adapter), adapter };
}

const exampleMeta: CellMeta = {
  cellHash: 'aa'.repeat(32),
  contentHash: 'bb'.repeat(32),
  version: 1,
  timestamp: 1700000000000,
  linearity: 1,
  prevCellHash: null,
};

describe('StorageAdapterFacade', () => {
  test('1. readCell returns null for missing keys', async () => {
    const { facade } = makeFacade();
    expect(await facade.readCell('nope')).toBeNull();
  });

  test('2. writeCell + readCell round-trips bytes', async () => {
    const { facade } = makeFacade();
    const data = new Uint8Array([1, 2, 3]);
    await facade.writeCell('k', data);
    expect(await facade.readCell('k')).toEqual(data);
  });

  test('3. writeChunk + readChunk are independent of cell ops', async () => {
    const { facade } = makeFacade();
    const data = new Uint8Array([9, 8, 7]);
    await facade.writeChunk('k.chunk.0000', data);
    expect(await facade.readChunk('k.chunk.0000')).toEqual(data);
    expect(await facade.readCell('k.chunk.0000')).toEqual(data); // same key namespace
  });

  test('4. writeMeta + readMeta JSON-roundtrip', async () => {
    const { facade } = makeFacade();
    await facade.writeMeta('k', exampleMeta);
    expect(await facade.readMeta('k')).toEqual(exampleMeta);
  });

  test('5. readMeta returns null on missing key', async () => {
    const { facade } = makeFacade();
    expect(await facade.readMeta('missing')).toBeNull();
  });

  test('6. readMeta returns null on malformed JSON', async () => {
    const { facade, adapter } = makeFacade();
    await adapter.write('bad.meta', new TextEncoder().encode('not-json{'));
    expect(await facade.readMeta('bad')).toBeNull();
  });

  test('7. archivePrevious copies cell + meta under .v{version} keys', async () => {
    const { facade, adapter } = makeFacade();
    await facade.writeCell('k', new Uint8Array([1, 2, 3]));
    await facade.writeMeta('k', exampleMeta);
    await facade.archivePrevious('k', 1);
    expect(await adapter.read('k.v1')).toEqual(new Uint8Array([1, 2, 3]));
    expect(await adapter.read('k.v1.meta')).not.toBeNull();
  });

  test('8. archivePrevious is a no-op when no prior bytes exist', async () => {
    const { facade, adapter } = makeFacade();
    await facade.archivePrevious('ghost', 1);
    expect(await adapter.read('ghost.v1')).toBeNull();
  });

  test('9. list pipes through to the adapter', async () => {
    const { facade } = makeFacade();
    await facade.write('_index/content/abc', new Uint8Array([0]));
    await facade.write('_index/content/def', new Uint8Array([1]));
    const keys = await facade.list('_index/content/');
    expect(keys).toContain('abc');
    expect(keys).toContain('def');
  });
});

```
