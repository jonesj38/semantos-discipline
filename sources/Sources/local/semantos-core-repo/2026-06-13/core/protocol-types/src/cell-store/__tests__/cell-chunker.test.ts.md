---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/cell-chunker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.919064+00:00
---

# core/protocol-types/src/cell-store/__tests__/cell-chunker.test.ts

```ts
/**
 * cell-chunker pure-function tests.
 */

import { describe, expect, test } from 'bun:test';
import {
  chunkCountFor,
  chunkData,
  isChunked,
  reassembleChunks,
} from '../cell-chunker';

describe('chunkData', () => {
  test('1. small input yields a single chunk', () => {
    const data = new Uint8Array([1, 2, 3]);
    const plan = chunkData(data, 16);
    expect(plan.chunks).toHaveLength(1);
    expect(plan.chunks[0]).toEqual(data);
    expect(plan.totalSize).toBe(3);
  });

  test('2. multi-chunk split honours chunkSize', () => {
    const data = new Uint8Array(50).map((_, i) => i + 1);
    const plan = chunkData(data, 16);
    expect(plan.chunks).toHaveLength(4);
    expect(plan.chunks[0]?.length).toBe(16);
    expect(plan.chunks[1]?.length).toBe(16);
    expect(plan.chunks[2]?.length).toBe(16);
    expect(plan.chunks[3]?.length).toBe(2);
  });

  test('3. exact multiple of chunkSize → no short tail chunk', () => {
    const data = new Uint8Array(48);
    const plan = chunkData(data, 16);
    expect(plan.chunks.every((c) => c.length === 16)).toBe(true);
  });

  test('4. chunkSize <= 0 throws', () => {
    expect(() => chunkData(new Uint8Array(1), 0)).toThrow();
    expect(() => chunkData(new Uint8Array(1), -1)).toThrow();
  });

  test('5. empty input yields no chunks', () => {
    const plan = chunkData(new Uint8Array(0), 16);
    expect(plan.chunks).toHaveLength(0);
    expect(plan.totalSize).toBe(0);
  });
});

describe('reassembleChunks', () => {
  test('6. round-trips through chunkData', () => {
    const original = new Uint8Array(100).map((_, i) => (i * 7) & 0xff);
    const { chunks } = chunkData(original, 13);
    const out = reassembleChunks(chunks, original.length);
    expect(out).toEqual(original);
  });

  test('7. without explicit totalSize sums chunk lengths', () => {
    const out = reassembleChunks([new Uint8Array([1, 2]), new Uint8Array([3])]);
    expect(out).toEqual(new Uint8Array([1, 2, 3]));
  });

  test('8. truncates chunks that would overflow the requested totalSize', () => {
    const out = reassembleChunks(
      [new Uint8Array([1, 2, 3]), new Uint8Array([4, 5, 6])],
      4,
    );
    expect(out.length).toBe(4);
    expect(out).toEqual(new Uint8Array([1, 2, 3, 4]));
  });
});

describe('helpers', () => {
  test('9. isChunked is true above the threshold', () => {
    expect(isChunked(100, 50)).toBe(true);
    expect(isChunked(50, 50)).toBe(false);
    expect(isChunked(0, 50)).toBe(false);
  });

  test('10. chunkCountFor matches ceil(len/size)', () => {
    expect(chunkCountFor(0, 16)).toBe(0);
    expect(chunkCountFor(15, 16)).toBe(1);
    expect(chunkCountFor(16, 16)).toBe(1);
    expect(chunkCountFor(17, 16)).toBe(2);
    expect(chunkCountFor(100, 16)).toBe(7);
  });
});

```
