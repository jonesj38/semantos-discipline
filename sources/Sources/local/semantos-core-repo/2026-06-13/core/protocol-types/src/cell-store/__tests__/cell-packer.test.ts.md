---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/__tests__/cell-packer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.919630+00:00
---

# core/protocol-types/src/cell-store/__tests__/cell-packer.test.ts

```ts
/**
 * cell-packer pure-function tests.
 *
 * Covers the byte-level guarantees: round-trip pack/unpack, 1024-byte
 * cell size, header offset, continuation header layout, manifest
 * helpers.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildContinuationHeader,
  findManifestEnd,
  packCell,
  packContinuationCell,
  parseContinuationHeader,
  parseManifest,
  unpackCell,
  unpackContinuationCell,
} from '../cell-packer';
import { CELL_SIZE, CONTINUATION_HEADER_SIZE, HEADER_SIZE, PAYLOAD_SIZE } from '../../constants';
import type { CellHeader } from '../../cell-header';

function header(linearity = 1, totalSize = 16, cellCount = 1): CellHeader {
  return {
    magic: new Uint8Array(16),
    linearity,
    version: 1,
    flags: 0,
    refCount: 1,
    typeHash: new Uint8Array(32),
    ownerId: new Uint8Array(16),
    timestamp: 1700000000000n,
    cellCount,
    totalSize,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
    domainPayloadRoot: new Uint8Array(32),
  };
}

describe('packCell / unpackCell', () => {
  test('1. produces a 1024-byte cell from a fitting payload', () => {
    const cell = packCell(header(1, 4), new Uint8Array([1, 2, 3, 4]));
    expect(cell.length).toBe(CELL_SIZE);
  });

  test('2. payload bytes appear at HEADER_SIZE offset', () => {
    const data = new Uint8Array([7, 8, 9]);
    const cell = packCell(header(1, 3), data);
    expect(cell.slice(HEADER_SIZE, HEADER_SIZE + 3)).toEqual(data);
  });

  test('3. throws when payload exceeds PAYLOAD_SIZE', () => {
    const oversize = new Uint8Array(PAYLOAD_SIZE + 1);
    expect(() => packCell(header(), oversize)).toThrow(/exceeds PAYLOAD_SIZE/);
  });

  test('4. unpackCell round-trips a single cell', () => {
    const data = new Uint8Array([10, 20, 30, 40]);
    const h = header(2, data.length);
    const cell = packCell(h, data);
    const { header: outHeader, payload } = unpackCell(cell);
    expect(outHeader.linearity).toBe(2);
    expect(payload).toEqual(data);
  });

  test('5. unpackCell trims to header.totalSize for single cells', () => {
    const data = new Uint8Array(100).fill(7);
    const cell = packCell(header(1, 50), data); // totalSize=50, payload still 100
    const { payload } = unpackCell(cell);
    expect(payload.length).toBe(50);
  });

  test('6. unpackCell returns full payload region for chunked cells (cellCount > 1)', () => {
    const manifest = new TextEncoder().encode('{"chunkCount":3}');
    const cell = packCell(header(1, 999, 4), manifest);
    const { payload } = unpackCell(cell);
    expect(payload.length).toBe(PAYLOAD_SIZE);
  });

  test('7. unpackCell rejects truncated input', () => {
    const tiny = new Uint8Array(100);
    expect(() => unpackCell(tiny)).toThrow(/expected at least/);
  });
});

describe('continuation headers + cells', () => {
  test('8. buildContinuationHeader / parseContinuationHeader round-trip', () => {
    const buf = buildContinuationHeader(2, 5, 7, 200);
    const fields = parseContinuationHeader(buf);
    expect(fields).toEqual({ cellType: 2, cellIndex: 5, totalCells: 7, payloadSize: 200 });
  });

  test('9. continuation header is exactly CONTINUATION_HEADER_SIZE bytes', () => {
    expect(buildContinuationHeader(1, 1, 1, 1).length).toBe(CONTINUATION_HEADER_SIZE);
  });

  test('10. packContinuationCell + unpackContinuationCell reconstruct chunk bytes', () => {
    const chunk = new Uint8Array([42, 43, 44, 45, 46]);
    const cell = packContinuationCell(2, 3, 9, chunk);
    expect(cell.length).toBe(CELL_SIZE);
    const { header: h, chunk: out } = unpackContinuationCell(cell);
    expect(h.cellIndex).toBe(3);
    expect(h.totalCells).toBe(9);
    expect(h.payloadSize).toBe(5);
    expect(out).toEqual(chunk);
  });

  test('11. byte 7 of the continuation header is reserved/0', () => {
    const buf = buildContinuationHeader(1, 1, 1, 100);
    expect(buf[7]).toBe(0);
  });
});

describe('manifest helpers', () => {
  test('12. findManifestEnd stops at the first NUL after the JSON blob', () => {
    const cell = new Uint8Array(CELL_SIZE);
    const json = new TextEncoder().encode('{"hello":"world"}');
    cell.set(json, HEADER_SIZE);
    expect(findManifestEnd(cell)).toBe(HEADER_SIZE + json.length);
  });

  test('13. parseManifest deserializes JSON inside the payload region', () => {
    const cell = new Uint8Array(CELL_SIZE);
    cell.set(new TextEncoder().encode('{"x":42}'), HEADER_SIZE);
    expect(parseManifest<{ x: number }>(cell)).toEqual({ x: 42 });
  });

  test('14. parseManifest returns null on malformed JSON', () => {
    const cell = new Uint8Array(CELL_SIZE);
    cell.set(new TextEncoder().encode('not-json{'), HEADER_SIZE);
    expect(parseManifest(cell)).toBeNull();
  });
});

```
