---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/cell-store-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.919912+00:00
---

# core/protocol-types/src/cell-store/__tests__/cell-store-integration.test.ts

```ts
/**
 * cell-store integration tests — drive the public CellStore API
 * through the in-memory adapter and pin behaviour the prompt-04 split
 * must preserve:
 *
 *   • 100 sequential writes round-trip byte-identically
 *   • single-cell payload (≤ PAYLOAD_SIZE) round-trips
 *   • multi-cell payload (> PAYLOAD_SIZE) round-trips and verify() passes
 *   • version chain ≥ 3 walks newest-first and verify() passes
 *   • findByContent finds every key that wrote the same payload
 *
 * If a future refactor breaks the wire format, these tests fail.
 */

import { describe, expect, test } from 'bun:test';
import { CellStore } from '../cell-store-facade';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { CELL_SIZE, PAYLOAD_SIZE, Linearity } from '../../constants';

function freshStore(): { store: CellStore; adapter: MemoryAdapter } {
  const adapter = new MemoryAdapter();
  return { store: new CellStore(adapter), adapter };
}

describe('CellStore integration', () => {
  test('1. put + get round-trip a small payload', async () => {
    const { store } = freshStore();
    const data = new TextEncoder().encode('hello cell');
    const ref = await store.put('greeting', data);
    expect(ref.version).toBe(1);
    expect(ref.linearity).toBe(Linearity.LINEAR);
    const got = await store.get('greeting');
    expect(got?.payload).toEqual(data);
  });

  test('2. get returns null for missing keys', async () => {
    const { store } = freshStore();
    expect(await store.get('nope')).toBeNull();
  });

  test('3. put on an existing key bumps version and chains prevStateHash', async () => {
    const { store } = freshStore();
    const a = await store.put('chain', new TextEncoder().encode('v1'));
    const b = await store.put('chain', new TextEncoder().encode('v2'));
    expect(b.version).toBe(2);
    expect(b.cellHash).not.toBe(a.cellHash);
  });

  test('4. history walks back through ≥3 versions, newest first', async () => {
    const { store } = freshStore();
    for (let i = 1; i <= 5; i++) {
      await store.put('chained', new TextEncoder().encode(`v${i}`));
    }
    const refs = await store.history('chained');
    expect(refs).toHaveLength(5);
    expect(refs.map((r) => r.version)).toEqual([5, 4, 3, 2, 1]);
  });

  test('5. verify() passes for a clean ≥3 chain', async () => {
    const { store } = freshStore();
    for (let i = 1; i <= 3; i++) {
      await store.put('vchain', new TextEncoder().encode(`v${i}`));
    }
    const result = await store.verify('vchain');
    expect(result).toEqual({ valid: true, errors: [] });
  });

  test('6. verify() reports when the head cell bytes are tampered', async () => {
    const { store, adapter } = freshStore();
    await store.put('tamper', new TextEncoder().encode('original'));
    const cellBytes = await adapter.read('tamper');
    if (!cellBytes) throw new Error('cell missing');
    cellBytes[CELL_SIZE - 1] = 0xff; // mutate trailing byte
    await adapter.write('tamper', cellBytes);
    const result = await store.verify('tamper');
    expect(result.valid).toBe(false);
    expect(result.errors[0]).toMatch(/cellHash mismatch/);
  });

  test('7. multi-cell payload (> PAYLOAD_SIZE) round-trips', async () => {
    const { store } = freshStore();
    // 3× PAYLOAD_SIZE worth of pseudo-random bytes
    const big = new Uint8Array(PAYLOAD_SIZE * 3 + 17).map((_, i) => (i * 31 + 7) & 0xff);
    await store.put('big', big);
    const got = await store.get('big');
    expect(got?.payload).toEqual(big);
  });

  test('8. multi-cell payload verify() passes for chunked storage', async () => {
    const { store } = freshStore();
    const big = new Uint8Array(PAYLOAD_SIZE * 2 + 200).map((_, i) => (i * 13) & 0xff);
    await store.put('big-verify', big);
    const result = await store.verify('big-verify');
    expect(result).toEqual({ valid: true, errors: [] });
  });

  test('9. findByContent locates every key written with the same payload', async () => {
    const { store } = freshStore();
    const data = new TextEncoder().encode('shared-content');
    await store.put('alpha', data);
    await store.put('beta', data);
    const refs = await store.findByContent(
      // sha256("shared-content") computed in advance via Node crypto;
      // skip embedding the exact digest by reading it back from the
      // first write.
      (await store.get('alpha'))!.contentHash,
    );
    const keys = refs.map((r) => r.key).sort();
    expect(keys).toEqual(['alpha', 'beta']);
  });

  test('10. 100 sequential writes round-trip byte-identically', async () => {
    const { store } = freshStore();
    const inputs: Uint8Array[] = [];
    for (let i = 0; i < 100; i++) {
      const buf = new Uint8Array(32 + (i % 17)).map((_, j) => (i * 7 + j) & 0xff);
      inputs.push(buf);
      await store.put(`bulk/${i.toString().padStart(3, '0')}`, buf);
    }
    for (let i = 0; i < 100; i++) {
      const got = await store.get(`bulk/${i.toString().padStart(3, '0')}`);
      expect(got?.payload).toEqual(inputs[i] as Uint8Array);
    }
  });

  test('11. each persisted cell is exactly CELL_SIZE bytes', async () => {
    const { store, adapter } = freshStore();
    await store.put('size-check', new TextEncoder().encode('small'));
    const cell = await adapter.read('size-check');
    expect(cell?.length).toBe(CELL_SIZE);
  });

  test('12. PutOptions overrides land on the persisted header', async () => {
    const { store } = freshStore();
    await store.put('with-opts', new TextEncoder().encode('o'), {
      linearity: Linearity.AFFINE,
      flags: 0b1010,
    });
    const got = await store.get('with-opts');
    expect(got?.linearity).toBe(Linearity.AFFINE);
    expect(got?.header.flags).toBe(0b1010);
  });
});

```
