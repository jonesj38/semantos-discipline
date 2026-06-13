---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/metadata-scanner.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.907178+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/metadata-scanner.test.ts

```ts
/**
 * metadata-scanner tests — verifies the filtering rules and the
 * predicate-driven scan against an in-memory adapter.
 */

import { describe, expect, test } from 'bun:test';
import {
  listCellKeys,
  metaRefsFor,
  readMeta,
  scanMetaFilter,
} from '../metadata-scanner';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import type { CellMeta } from '../types';

const sampleMeta = (cellHash: string): CellMeta => ({
  cellHash,
  contentHash: `cnt-${cellHash}`,
  version: 1,
  timestamp: 1700000000000,
  linearity: 1,
  prevCellHash: null,
});

async function seed(adapter: MemoryAdapter, layout: Record<string, CellMeta | null>): Promise<void> {
  for (const [key, meta] of Object.entries(layout)) {
    await adapter.write(key, new Uint8Array([0])); // placeholder cell bytes
    if (meta) {
      await adapter.write(`${key}.meta`, new TextEncoder().encode(JSON.stringify(meta)));
    }
  }
}

describe('readMeta', () => {
  test('1. returns null on missing meta', async () => {
    const adapter = new MemoryAdapter();
    expect(await readMeta(adapter, 'nope')).toBeNull();
  });

  test('2. returns null on malformed JSON', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('bad.meta', new TextEncoder().encode('{ not json'));
    expect(await readMeta(adapter, 'bad')).toBeNull();
  });

  test('3. parses a valid meta sidecar', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('k.meta', new TextEncoder().encode(JSON.stringify(sampleMeta('abc'))));
    expect(await readMeta(adapter, 'k')).toEqual(sampleMeta('abc'));
  });
});

describe('listCellKeys', () => {
  test('4. excludes .meta / .chunk. / .v* / _index keys', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, {
      'objects/a': sampleMeta('h-a'),
      'objects/b': sampleMeta('h-b'),
      'objects/_index/foo': sampleMeta('h-i'),
      'objects/big.chunk.0000': null,
      'objects/old.v1': null,
    });
    // .meta sidecars are seeded for a/b/_index/foo by the helper; the
    // key list should still drop the .meta extension itself.
    const keys = await listCellKeys(adapter, 'objects/');
    expect(keys.sort()).toEqual(['objects/a', 'objects/b']);
  });

  test('5. depth filter caps result depth', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, {
      'objects/x': sampleMeta('1'),
      'objects/foo/bar': sampleMeta('2'),
      'objects/foo/bar/baz': sampleMeta('3'),
    });
    const shallow = await listCellKeys(adapter, 'objects/', { depth: 1 });
    expect(shallow.sort()).toEqual(['objects/x']);
    const wider = await listCellKeys(adapter, 'objects/', { depth: 2 });
    expect(wider.sort()).toEqual(['objects/foo/bar', 'objects/x']);
  });

  test('6. trims trailing slashes from the prefix', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, { 'objects/a': sampleMeta('h') });
    const keys = await listCellKeys(adapter, 'objects//');
    expect(keys).toEqual(['objects/a']);
  });
});

describe('metaRefsFor', () => {
  test('7. resolves CellRefs for keys with metadata', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, {
      'objects/a': sampleMeta('h-a'),
      'objects/b': sampleMeta('h-b'),
    });
    const refs = await metaRefsFor(adapter, ['objects/a', 'objects/b']);
    expect(refs.map((r) => r.cellHash).sort()).toEqual(['h-a', 'h-b']);
  });

  test('8. silently drops keys whose meta is missing', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, { 'objects/has': sampleMeta('h') });
    const refs = await metaRefsFor(adapter, ['objects/has', 'objects/missing']);
    expect(refs).toHaveLength(1);
    expect(refs[0]?.key).toBe('objects/has');
  });
});

describe('scanMetaFilter', () => {
  test('9. invokes predicate with each (key, meta) pair', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, {
      'objects/a': sampleMeta('h-a'),
      'objects/b': sampleMeta('h-b'),
    });
    const seen: string[] = [];
    await scanMetaFilter(adapter, async (key, meta) => {
      seen.push(`${key}:${meta.cellHash}`);
      return true;
    });
    expect(seen.sort()).toEqual(['objects/a:h-a', 'objects/b:h-b']);
  });

  test('10. returns only entries that the predicate accepts', async () => {
    const adapter = new MemoryAdapter();
    await seed(adapter, {
      'objects/a': sampleMeta('h-a'),
      'objects/b': sampleMeta('h-b'),
    });
    const refs = await scanMetaFilter(adapter, async (_key, meta) => meta.cellHash === 'h-a');
    expect(refs.map((r) => r.key)).toEqual(['objects/a']);
  });

  test('11. empty store yields no results', async () => {
    const adapter = new MemoryAdapter();
    const refs = await scanMetaFilter(adapter, async () => true);
    expect(refs).toEqual([]);
  });
});

```
