---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/cell-verifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.920215+00:00
---

# core/protocol-types/src/cell-store/__tests__/cell-verifier.test.ts

```ts
/**
 * cell-verifier tests — exercises the full verifyChain matrix:
 * missing cells, tampered bytes, broken prevStateHash links, chunk
 * mismatches.
 */

import { describe, expect, test } from 'bun:test';
import { CellStore } from '../cell-store-facade';
import { verifyChain } from '../cell-verifier';
import { StorageAdapterFacade } from '../storage-adapter-facade';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { PAYLOAD_SIZE } from '../../constants';

function setup() {
  const adapter = new MemoryAdapter();
  return {
    adapter,
    storage: new StorageAdapterFacade(adapter),
    store: new CellStore(adapter),
  };
}

describe('verifyChain', () => {
  test('1. fresh chain of length 1 is valid', async () => {
    const { storage, store } = setup();
    await store.put('k', new TextEncoder().encode('hi'));
    expect(await verifyChain(storage, 'k')).toEqual({ valid: true, errors: [] });
  });

  test('2. fresh chain of length 3 is valid', async () => {
    const { storage, store } = setup();
    for (let i = 0; i < 3; i++) await store.put('k', new TextEncoder().encode(`v${i}`));
    expect(await verifyChain(storage, 'k')).toEqual({ valid: true, errors: [] });
  });

  test('3. unknown key surfaces a friendly error', async () => {
    const { storage } = setup();
    const result = await verifyChain(storage, 'missing');
    expect(result).toEqual({ valid: false, errors: ['No cell found at key'] });
  });

  test('4. tampered head cell fails with cellHash mismatch', async () => {
    const { storage, store, adapter } = setup();
    await store.put('k', new TextEncoder().encode('a'));
    const cell = (await adapter.read('k'))!;
    cell[100] ^= 0xff;
    await adapter.write('k', cell);
    const result = await verifyChain(storage, 'k');
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('cellHash mismatch'))).toBe(true);
  });

  test('5. missing archived cell bytes is reported', async () => {
    const { storage, store, adapter } = setup();
    await store.put('k', new TextEncoder().encode('v1'));
    await store.put('k', new TextEncoder().encode('v2'));
    // delete the archived v1 cell while leaving its meta sidecar
    (adapter as unknown as { store: Map<string, unknown> }).store.delete('k.v1');
    const result = await verifyChain(storage, 'k');
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('cell bytes missing'))).toBe(true);
  });

  test('6. broken prevStateHash linkage is reported', async () => {
    const { storage, store, adapter } = setup();
    await store.put('k', new TextEncoder().encode('v1'));
    await store.put('k', new TextEncoder().encode('v2'));
    // Mutate v1's meta cellHash so head's prevStateHash no longer matches.
    const v1MetaBytes = (await adapter.read('k.v1.meta'))!;
    const v1Meta = JSON.parse(new TextDecoder().decode(v1MetaBytes));
    v1Meta.cellHash = '00'.repeat(32);
    await adapter.write(
      'k.v1.meta',
      new TextEncoder().encode(JSON.stringify(v1Meta)),
    );
    const result = await verifyChain(storage, 'k');
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('prevStateHash does not match'))).toBe(true);
  });

  test('7. chunked cell with intact chunks verifies clean', async () => {
    const { storage, store } = setup();
    const big = new Uint8Array(PAYLOAD_SIZE * 2 + 50).map((_, i) => (i * 5) & 0xff);
    await store.put('big', big);
    expect(await verifyChain(storage, 'big')).toEqual({ valid: true, errors: [] });
  });

  test('8. chunked cell with a missing chunk is reported', async () => {
    const { storage, store, adapter } = setup();
    const big = new Uint8Array(PAYLOAD_SIZE * 2 + 50).map((_, i) => i & 0xff);
    await store.put('big', big);
    (adapter as unknown as { store: Map<string, unknown> }).store.delete('big.chunk.0001');
    const result = await verifyChain(storage, 'big');
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('chunk 1 missing'))).toBe(true);
  });

  test('9. chunked cell with a corrupted chunk fails on chunk hash', async () => {
    const { storage, store, adapter } = setup();
    const big = new Uint8Array(PAYLOAD_SIZE * 2 + 10).map((_, i) => (i * 3) & 0xff);
    await store.put('big', big);
    const chunk = (await adapter.read('big.chunk.0000'))!;
    chunk[10] ^= 0xff;
    await adapter.write('big.chunk.0000', chunk);
    const result = await verifyChain(storage, 'big');
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('chunk 0 hash mismatch'))).toBe(true);
  });
});

```
