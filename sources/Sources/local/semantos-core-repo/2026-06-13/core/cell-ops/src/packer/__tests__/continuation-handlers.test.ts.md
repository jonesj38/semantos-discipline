---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/__tests__/continuation-handlers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.835078+00:00
---

# core/cell-ops/src/packer/__tests__/continuation-handlers.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildContinuationHeader,
  parseContinuationHeader,
} from '../continuation-handlers';
import { CONTINUATION_HEADER_SIZE, CONTINUATION_TYPE } from '../constants';

describe('continuation-handlers', () => {
  test('1. round-trip a typical header', () => {
    const h = {
      cellType: CONTINUATION_TYPE.BUMP,
      cellIndex: 1,
      totalCells: 3,
      payloadSize: 312,
      reserved: 0,
    };
    const buf = buildContinuationHeader(h);
    expect(buf.length).toBe(CONTINUATION_HEADER_SIZE);
    expect(parseContinuationHeader(buf)).toEqual(h);
  });

  test('2. byte layout pinned: type at 0, cellIndex at 1 (LE u16)', () => {
    const buf = buildContinuationHeader({
      cellType: CONTINUATION_TYPE.ATOMIC_BEEF,
      cellIndex: 0x1234,
      totalCells: 0,
      payloadSize: 0,
      reserved: 0,
    });
    expect(buf[0]).toBe(CONTINUATION_TYPE.ATOMIC_BEEF);
    expect(buf[1]).toBe(0x34);
    expect(buf[2]).toBe(0x12);
  });

  test('3. parse throws on too-short buffer', () => {
    expect(() => parseContinuationHeader(Buffer.alloc(4))).toThrow('needs 8 bytes');
  });

  test('4. round-trip every known continuation type', () => {
    for (const type of Object.values(CONTINUATION_TYPE)) {
      const h = {
        cellType: type,
        cellIndex: 7,
        totalCells: 12,
        payloadSize: 1000,
        reserved: 0,
      };
      expect(parseContinuationHeader(buildContinuationHeader(h))).toEqual(h);
    }
  });
});

```
