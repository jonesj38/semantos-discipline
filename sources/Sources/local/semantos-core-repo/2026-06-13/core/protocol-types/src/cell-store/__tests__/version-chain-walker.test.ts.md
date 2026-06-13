---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/version-chain-walker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.919349+00:00
---

# core/protocol-types/src/cell-store/__tests__/version-chain-walker.test.ts

```ts
/**
 * version-chain-walker tests — walks the .v{N} archive trail produced
 * by StorageAdapterFacade.archivePrevious.
 */

import { describe, expect, test } from 'bun:test';
import { collectVersions, walkVersions } from '../version-chain-walker';
import { StorageAdapterFacade } from '../storage-adapter-facade';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import type { CellMeta } from '../types';

function makeStorage(): StorageAdapterFacade {
  return new StorageAdapterFacade(new MemoryAdapter());
}

function meta(version: number, cellHash: string): CellMeta {
  return {
    cellHash,
    contentHash: `cnt-${version}`,
    version,
    timestamp: 1700000000000 + version,
    linearity: 1,
    prevCellHash: null,
  };
}

async function seedChain(storage: StorageAdapterFacade, key: string, len: number): Promise<void> {
  for (let v = 1; v < len; v++) {
    await storage.writeMeta(`${key}.v${v}`, meta(v, `cellhash:${v}`));
  }
  await storage.writeMeta(key, meta(len, `cellhash:${len}`));
}

describe('walkVersions / collectVersions', () => {
  test('1. yields nothing for a missing key', async () => {
    const storage = makeStorage();
    const out: unknown[] = [];
    for await (const ref of walkVersions(storage, 'missing')) out.push(ref);
    expect(out).toEqual([]);
  });

  test('2. single version → one yield', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 1);
    const refs = await collectVersions(storage, 'k');
    expect(refs).toHaveLength(1);
    expect(refs[0]?.version).toBe(1);
  });

  test('3. chain of length ≥3 walks newest first', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 3);
    const refs = await collectVersions(storage, 'k');
    expect(refs.map((r) => r.version)).toEqual([3, 2, 1]);
  });

  test('4. references the original key for v=head and key.v{N} for archived versions', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 3);
    const refs = await collectVersions(storage, 'k');
    expect(refs[0]?.key).toBe('k');
    expect(refs[1]?.key).toBe('k.v2');
    expect(refs[2]?.key).toBe('k.v1');
  });

  test('5. stops walking at the first missing meta sidecar', async () => {
    const storage = makeStorage();
    // head meta v=3 but no v2 archived → walker stops after head.
    await storage.writeMeta('k', meta(3, 'cellhash:3'));
    const refs = await collectVersions(storage, 'k');
    expect(refs).toHaveLength(1);
  });

  test('6. async generator can be iterated incrementally', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 5);
    const versions: number[] = [];
    for await (const ref of walkVersions(storage, 'k')) {
      versions.push(ref.version);
      if (versions.length === 2) break;
    }
    expect(versions).toEqual([5, 4]);
  });

  test('7. populates contentHash + timestamp + linearity from the meta sidecar', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 1);
    const refs = await collectVersions(storage, 'k');
    expect(refs[0]?.contentHash).toBe('cnt-1');
    expect(refs[0]?.timestamp).toBe(1700000000001);
    expect(refs[0]?.linearity).toBe(1);
  });

  test('8. handles a long chain (≥10) without losing entries', async () => {
    const storage = makeStorage();
    await seedChain(storage, 'k', 10);
    const refs = await collectVersions(storage, 'k');
    expect(refs).toHaveLength(10);
    expect(refs[0]?.version).toBe(10);
    expect(refs[9]?.version).toBe(1);
  });
});

```
