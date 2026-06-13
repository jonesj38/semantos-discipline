---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/__tests__/op-packers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.834199+00:00
---

# core/cell-ops/src/packer/__tests__/op-packers.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  createAtomicBeefCells,
  parseAtomicBeefHeader,
} from '../op-packers/pack-beef';
import {
  createBumpCells,
  parseBumpHeader,
} from '../op-packers/pack-bump';
import {
  createDataCell,
  createDataCells,
} from '../op-packers/pack-data';
import {
  ATOMIC_BEEF_PREFIX,
  CONTINUATION_PAYLOAD_SIZE,
  CONTINUATION_TYPE,
} from '../constants';
import { encodeVarInt } from '../varint';

function buildBumpRaw(blockHeight: number, treeHeight: number, dataLen: number): Buffer {
  const buf = Buffer.alloc(9 + 1 + dataLen);
  const written = encodeVarInt(buf, 0, blockHeight);
  buf.writeUInt8(treeHeight, written);
  return buf.subarray(0, written + 1 + dataLen);
}

function buildAtomicBeefRaw(extraBytes: number): Buffer {
  const buf = Buffer.alloc(36 + extraBytes);
  ATOMIC_BEEF_PREFIX.copy(buf, 0);
  buf.fill(0xab, 4, 36);
  buf.fill(0xee, 36);
  return buf;
}

describe('parseBumpHeader', () => {
  test('1. extracts blockHeight + treeHeight', () => {
    const raw = buildBumpRaw(123_456, 22, 0);
    const h = parseBumpHeader(raw);
    expect(h.blockHeight).toBe(123_456);
    expect(h.treeHeight).toBe(22);
  });

  test('2. throws on too-short input', () => {
    expect(() => parseBumpHeader(Buffer.alloc(1))).toThrow('BUMP too short');
  });

  test('3. rejects unreasonable treeHeight', () => {
    const raw = buildBumpRaw(0, 65, 0);
    expect(() => parseBumpHeader(raw)).toThrow('exceeds maximum');
  });
});

describe('createBumpCells', () => {
  test('4. single-cell BUMP under payload size', () => {
    const cells = createBumpCells(buildBumpRaw(1, 5, 100));
    expect(cells).toHaveLength(1);
    expect(cells[0].type).toBe(CONTINUATION_TYPE.BUMP);
  });

  test('5. multi-cell BUMP when over payload size', () => {
    const cells = createBumpCells(buildBumpRaw(1, 5, CONTINUATION_PAYLOAD_SIZE * 2));
    expect(cells.length).toBeGreaterThanOrEqual(2);
    for (const c of cells) expect(c.type).toBe(CONTINUATION_TYPE.BUMP);
  });
});

describe('parseAtomicBeefHeader + createAtomicBeefCells', () => {
  test('6. parses prefix + extracts subject TXID', () => {
    const raw = buildAtomicBeefRaw(100);
    const { subjectTxid } = parseAtomicBeefHeader(raw);
    expect(subjectTxid.length).toBe(32);
    expect(subjectTxid[0]).toBe(0xab);
  });

  test('7. throws on bad prefix', () => {
    const raw = Buffer.alloc(36);
    raw.fill(0x99, 0, 4);
    expect(() => parseAtomicBeefHeader(raw)).toThrow('Invalid Atomic BEEF prefix');
  });

  test('8. createAtomicBeefCells single cell when small', () => {
    const cells = createAtomicBeefCells(buildAtomicBeefRaw(100));
    expect(cells).toHaveLength(1);
    expect(cells[0].type).toBe(CONTINUATION_TYPE.ATOMIC_BEEF);
  });

  test('9. createAtomicBeefCells splits when over payload', () => {
    const cells = createAtomicBeefCells(buildAtomicBeefRaw(CONTINUATION_PAYLOAD_SIZE * 2));
    expect(cells.length).toBeGreaterThanOrEqual(2);
  });
});

describe('createDataCell + createDataCells', () => {
  test('10. createDataCell rejects > payload size', () => {
    expect(() =>
      createDataCell(Buffer.alloc(CONTINUATION_PAYLOAD_SIZE + 1)),
    ).toThrow('too large');
  });

  test('11. createDataCells splits exactly across payload boundary', () => {
    const cells = createDataCells(Buffer.alloc(CONTINUATION_PAYLOAD_SIZE * 3));
    expect(cells).toHaveLength(3);
  });
});

```
