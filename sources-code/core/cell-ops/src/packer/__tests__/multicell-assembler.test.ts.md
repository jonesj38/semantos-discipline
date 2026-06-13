---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/__tests__/multicell-assembler.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.834487+00:00
---

# core/cell-ops/src/packer/__tests__/multicell-assembler.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  packMultiCell,
  unpackMultiCell,
  packEscalated,
  unpackEscalated,
  isEscalated,
  ESCALATION_CELL_COUNT_SENTINEL,
  OCTAVE1_CELL_SIZE,
  OCTAVE2_CELL_SIZE,
  OCTAVE_LEVEL_BASE,
  OCTAVE_LEVEL_KILO,
  OCTAVE_LEVEL_MEGA,
  OCTAVE_LEVEL_GIGA,
  MAX_OCTAVE_LEVEL,
  minimumOctaveForSize,
  OCTAVE0_FLAT_CAPACITY,
} from '../multicell-assembler';
import {
  CELL_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  CONTINUATION_TYPE,
  HEADER_SIZE,
} from '../constants';
import type { ContinuationCell, MultiCellObject } from '../types';

function makeHeader(): Buffer {
  const h = Buffer.alloc(HEADER_SIZE, 0);
  h.writeUInt32LE(123, 90); // payloadSize = 123
  return h;
}

describe('packMultiCell + unpackMultiCell — round-trip', () => {
  test('1. one cell (no continuations) round-trips', () => {
    const obj: MultiCellObject = {
      header: makeHeader(),
      payload: Buffer.from('hello world'.padEnd(123, ' ')),
      continuations: [],
    };
    const packed = packMultiCell(obj);
    expect(packed.cellCount).toBe(1);
    expect(packed.buffer.length).toBe(CELL_SIZE);
    const out = unpackMultiCell(packed.buffer);
    expect(out.payload.toString()).toBe(obj.payload.toString());
  });

  test('2. multi-cell round-trips with N continuations of varied sizes', () => {
    const continuations: ContinuationCell[] = [
      { type: CONTINUATION_TYPE.BUMP, data: Buffer.from('A'.repeat(100)) },
      { type: CONTINUATION_TYPE.ATOMIC_BEEF, data: Buffer.from('B'.repeat(500)) },
      { type: CONTINUATION_TYPE.ENVELOPE, data: Buffer.from('C'.repeat(1016)) },
      { type: CONTINUATION_TYPE.DATA, data: Buffer.alloc(0) },
    ];
    const obj: MultiCellObject = {
      header: makeHeader(),
      payload: Buffer.from('payload'.padEnd(123, ' ')),
      continuations,
    };
    const packed = packMultiCell(obj);
    expect(packed.cellCount).toBe(5);
    expect(packed.buffer.length).toBe(5 * CELL_SIZE);
    const out = unpackMultiCell(packed.buffer);
    expect(out.continuations).toHaveLength(4);
    expect(out.continuations[0].type).toBe(CONTINUATION_TYPE.BUMP);
    expect(out.continuations[0].data.toString()).toBe('A'.repeat(100));
    expect(out.continuations[2].data.length).toBe(1016);
  });

  test('3. payload too large throws', () => {
    expect(() =>
      packMultiCell({
        header: makeHeader(),
        payload: Buffer.alloc(769),
        continuations: [],
      }),
    ).toThrow('Cell 0 payload too large');
  });

  test('4. continuation too large throws', () => {
    expect(() =>
      packMultiCell({
        header: makeHeader(),
        payload: Buffer.alloc(0),
        continuations: [
          { type: CONTINUATION_TYPE.DATA, data: Buffer.alloc(CONTINUATION_PAYLOAD_SIZE + 1) },
        ],
      }),
    ).toThrow('Continuation cell 1 data too large');
  });

  test('5. unpack rejects buffer too small', () => {
    expect(() => unpackMultiCell(Buffer.alloc(100))).toThrow('Buffer too small');
  });

  test('6. unpack rejects non-multiple-of-1024', () => {
    expect(() => unpackMultiCell(Buffer.alloc(CELL_SIZE + 1))).toThrow(
      'is not a multiple of 1024',
    );
  });

  test('7. cellCount field at offset 86 is rewritten on pack', () => {
    const obj: MultiCellObject = {
      header: makeHeader(),
      payload: Buffer.alloc(0),
      continuations: [
        { type: CONTINUATION_TYPE.DATA, data: Buffer.alloc(10) },
        { type: CONTINUATION_TYPE.DATA, data: Buffer.alloc(20) },
      ],
    };
    const packed = packMultiCell(obj);
    expect(packed.buffer.readUInt32LE(86)).toBe(3);
  });

  test('8. property: 100 random multi-cell objects round-trip exactly', () => {
    for (let trial = 0; trial < 100; trial++) {
      const numCont = Math.floor(Math.random() * 5);
      const continuations: ContinuationCell[] = [];
      for (let i = 0; i < numCont; i++) {
        const size = Math.floor(Math.random() * CONTINUATION_PAYLOAD_SIZE);
        continuations.push({
          type: CONTINUATION_TYPE.DATA,
          data: Buffer.alloc(size, i),
        });
      }
      const payloadSize = Math.floor(Math.random() * 768);
      const header = Buffer.alloc(HEADER_SIZE, 0);
      header.writeUInt32LE(payloadSize, 90);
      const payload = Buffer.alloc(payloadSize, 7);
      const obj: MultiCellObject = { header, payload, continuations };
      const packed = packMultiCell(obj);
      const out = unpackMultiCell(packed.buffer);
      expect(out.payload).toEqual(payload);
      expect(out.continuations.length).toBe(continuations.length);
      for (let i = 0; i < continuations.length; i++) {
        expect(out.continuations[i].type).toBe(continuations[i].type);
        expect(out.continuations[i].data).toEqual(continuations[i].data);
      }
    }
  });
});

// ── Escalation (rung-1, octave-1) — D-OCT-data-octave-bump ───────────────────

describe('isEscalated', () => {
  test('9. rung-0 packed buffer is NOT escalated', () => {
    const obj: MultiCellObject = {
      header: makeHeader(),
      payload: Buffer.from('hello'),
      continuations: [],
    };
    const packed = packMultiCell(obj);
    expect(isEscalated(packed.buffer)).toBe(false);
  });

  test('10. buffer smaller than CELL_SIZE returns false', () => {
    expect(isEscalated(Buffer.alloc(100))).toBe(false);
  });

  test('11. escalated buffer is detected as escalated', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.from('some data');
    const packed = packEscalated(header, payload);
    expect(isEscalated(packed.buffer)).toBe(true);
  });

  test('12. sentinel value is 0xFFFFFFFF', () => {
    expect(ESCALATION_CELL_COUNT_SENTINEL).toBe(0xffffffff);
  });
});

describe('packEscalated + unpackEscalated — round-trip', () => {
  test('13. small payload escalates and round-trips', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.from('hello escalated world');
    const packed = packEscalated(header, payload);

    // Output is Cell 0 (1024 B) + raw payload bytes
    expect(packed.buffer.length).toBe(CELL_SIZE + payload.length);
    expect(packed.cellCount).toBe(1);

    const obj = unpackEscalated(packed.buffer);
    expect(Buffer.from(obj.childData)).toEqual(payload);
  });

  test('14. descriptor fields are correct after pack', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(1234, 0xab);
    const packed = packEscalated(header, payload);
    const obj = unpackEscalated(packed.buffer);

    expect(obj.descriptor.rung).toBe(1);
    expect(obj.descriptor.octaveLevel).toBe(1);
    expect(obj.descriptor.childCount).toBe(1);
    expect(obj.descriptor.totalBytes).toBe(BigInt(1234));
    expect(obj.descriptor.reserved).toBe(0);
  });

  test('15. O-1: Cell 0 total_size (offset 90) = 16 (descriptor size)', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(50000, 0x7f);
    const packed = packEscalated(header, payload);
    // total_size at offset 90 must be 16 per O-1 rule
    expect(packed.buffer.readUInt32LE(90)).toBe(16);
  });

  test('16. Cell 0 cell_count (offset 86) = sentinel 0xFFFFFFFF', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(10, 0x01);
    const packed = packEscalated(header, payload);
    expect(packed.buffer.readUInt32LE(86)).toBe(0xffffffff);
  });

  test('17. payload exactly at OCTAVE1_CELL_SIZE succeeds', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(OCTAVE1_CELL_SIZE, 0);
    // Should NOT throw
    expect(() => packEscalated(header, payload)).not.toThrow();
    const packed = packEscalated(header, payload);
    expect(packed.buffer.length).toBe(CELL_SIZE + OCTAVE1_CELL_SIZE);
  });

  test('18. payload exceeding OCTAVE1_CELL_SIZE routes to octave-2 (D-OCT-octave-2-plus)', () => {
    // D-OCT-octave-2-plus: payloads > 1 MiB no longer throw; they escalate to octave-2 (mega).
    // Only payloads > OCTAVE3_CELL_SIZE (1 TiB) are an error.
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(OCTAVE1_CELL_SIZE + 1, 0xbb);
    const packed = packEscalated(header, payload);
    // octave_level at cell byte 257 must be MEGA (2)
    expect(packed.buffer[257]).toBe(OCTAVE_LEVEL_MEGA);
    // O-1: total_size at header offset 90 = 16
    expect(packed.buffer.readUInt32LE(90)).toBe(16);
    // sentinel still set
    expect(packed.buffer.readUInt32LE(86)).toBe(0xffffffff);
    // round-trip
    const obj = unpackEscalated(packed.buffer);
    expect(obj.descriptor.octaveLevel).toBe(OCTAVE_LEVEL_MEGA);
    expect(obj.childData.length).toBe(OCTAVE1_CELL_SIZE + 1);
  });

  test('19. empty payload escalates correctly', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(0);
    const packed = packEscalated(header, payload);
    expect(packed.buffer.length).toBe(CELL_SIZE);
    const obj = unpackEscalated(packed.buffer);
    expect(obj.childData.length).toBe(0);
    expect(obj.descriptor.totalBytes).toBe(BigInt(0));
  });

  test('20. unpackEscalated rejects buffer too small', () => {
    expect(() => unpackEscalated(Buffer.alloc(100))).toThrow('Buffer too small');
  });

  test('21. rung-0 bytes are byte-identical before and after adding escalation code', () => {
    // Regression guard: existing rung-0 paths must be byte-identical
    const obj: MultiCellObject = {
      header: makeHeader(),
      payload: Buffer.from('backward-compat check'),
      continuations: [
        { type: CONTINUATION_TYPE.DATA, data: Buffer.from('continuation data') },
      ],
    };
    const packed = packMultiCell(obj);
    // cell_count at offset 86 must NOT be sentinel
    const cellCount = packed.buffer.readUInt32LE(86);
    expect(cellCount).toBe(2); // 1 primary + 1 continuation
    expect(cellCount).not.toBe(ESCALATION_CELL_COUNT_SENTINEL);
    // isEscalated must return false for rung-0
    expect(isEscalated(packed.buffer)).toBe(false);
  });

  test('22. property: escalated payloads 1..1000 bytes all round-trip', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    for (let len = 1; len <= 1000; len++) {
      const payload = Buffer.alloc(len, len & 0xff);
      const packed = packEscalated(header, payload);
      const obj = unpackEscalated(packed.buffer);
      expect(obj.childData.length).toBe(len);
      expect(obj.childData[0]).toBe(len & 0xff);
    }
  });
});

describe('canonical oracle↔mirror byte-vector (D-OCT-data-octave-bump)', () => {
  /**
   * CANONICAL VECTOR — must match the Zig test:
   *   "canonical vector: escalated 5-byte payload produces known bytes"
   *   in core/cell-engine/tests/multicell_octave_bump_conformance.zig
   *
   * Input:  header = 256 zero bytes
   *         payload = [0x41, 0x42, 0x43, 0x44, 0x45]  ("ABCDE")
   *
   * Expected wire layout (D-OCT-octave-2-plus: minimumOctaveForSize(5) = base = 0):
   *   buffer[86..89]   = FF FF FF FF       (cell_count sentinel, LE u32)
   *   buffer[90..93]   = 10 00 00 00       (total_size = 16, LE u32)
   *   buffer[256]      = 01                (rung = 1)
   *   buffer[257]      = 00                (octave_level = 0 = base; 5 bytes ≤ 1 KiB)
   *   buffer[258..259] = 01 00             (child_count = 1, LE u16)
   *   buffer[260..267] = 05 00 00 00 00 00 00 00  (total_bytes = 5, LE u64)
   *   buffer[268..271] = 00 00 00 00       (reserved)
   *   buffer[1024..1028] = 41 42 43 44 45  (child data "ABCDE")
   */
  test('23. canonical vector: escalated 5-byte "ABCDE" produces known bytes', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.from([0x41, 0x42, 0x43, 0x44, 0x45]);
    const packed = packEscalated(header, payload);

    // Total size: Cell 0 (1024 B) + 5 child bytes
    expect(packed.buffer.length).toBe(1024 + 5);

    // cell_count sentinel at offset 86
    expect(packed.buffer[86]).toBe(0xff);
    expect(packed.buffer[87]).toBe(0xff);
    expect(packed.buffer[88]).toBe(0xff);
    expect(packed.buffer[89]).toBe(0xff);

    // total_size = 16 at offset 90 (O-1 rule)
    expect(packed.buffer[90]).toBe(0x10);
    expect(packed.buffer[91]).toBe(0x00);
    expect(packed.buffer[92]).toBe(0x00);
    expect(packed.buffer[93]).toBe(0x00);

    // rung = 1 at cell byte 256
    expect(packed.buffer[256]).toBe(0x01);

    // octave_level = 0 (base) at cell byte 257
    // minimumOctaveForSize(5) = base (0); 5 bytes ≤ 1 KiB → octave-0 (base)
    expect(packed.buffer[257]).toBe(0x00);

    // child_count = 1 (LE u16) at bytes 258..259
    expect(packed.buffer[258]).toBe(0x01);
    expect(packed.buffer[259]).toBe(0x00);

    // total_bytes = 5 (LE u64) at bytes 260..267
    expect(packed.buffer[260]).toBe(0x05);
    expect(packed.buffer[261]).toBe(0x00);
    expect(packed.buffer[262]).toBe(0x00);
    expect(packed.buffer[263]).toBe(0x00);
    expect(packed.buffer[264]).toBe(0x00);
    expect(packed.buffer[265]).toBe(0x00);
    expect(packed.buffer[266]).toBe(0x00);
    expect(packed.buffer[267]).toBe(0x00);

    // reserved at bytes 268..271
    expect(packed.buffer[268]).toBe(0x00);
    expect(packed.buffer[269]).toBe(0x00);
    expect(packed.buffer[270]).toBe(0x00);
    expect(packed.buffer[271]).toBe(0x00);

    // Child data "ABCDE" at buffer bytes 1024..1028
    expect(packed.buffer[1024]).toBe(0x41); // 'A'
    expect(packed.buffer[1025]).toBe(0x42); // 'B'
    expect(packed.buffer[1026]).toBe(0x43); // 'C'
    expect(packed.buffer[1027]).toBe(0x44); // 'D'
    expect(packed.buffer[1028]).toBe(0x45); // 'E'

    // All other bytes in Cell 0 (not header, not descriptor, not child) are zero
    // Spot-check payload region bytes 272..1023 are zeroed
    for (let i = 272; i < 1024; i++) {
      if (packed.buffer[i] !== 0) {
        throw new Error(`Non-zero byte at offset ${i}: 0x${packed.buffer[i].toString(16)}`);
      }
    }
  });

  test('24. constants match spec values', () => {
    expect(OCTAVE1_CELL_SIZE).toBe(1_048_576);  // 1 MiB = 1024 * 1024
    expect(OCTAVE0_FLAT_CAPACITY).toBe(768 + 64 * 1016);  // = 65_792
    expect(ESCALATION_CELL_COUNT_SENTINEL).toBe(0xffffffff);
  });
});

describe('D-OCT-octave-2-plus — octave-2/3 escalation (TS oracle)', () => {
  /**
   * These tests mirror core/cell-engine/tests/multicell_octave_bump_conformance.zig
   * new tests added in D-OCT-octave-2-plus (step 5).
   *
   * No giant allocations: synthetic bigint/number size constants, small real payloads.
   */

  test('oct2+: minimumOctaveForSize boundary values', () => {
    // base: 0 bytes and 1024 bytes
    expect(minimumOctaveForSize(0)).toBe(OCTAVE_LEVEL_BASE);
    expect(minimumOctaveForSize(1024)).toBe(OCTAVE_LEVEL_BASE);
    // kilo: 1025 bytes through 1 MiB
    expect(minimumOctaveForSize(1025)).toBe(OCTAVE_LEVEL_KILO);
    expect(minimumOctaveForSize(OCTAVE1_CELL_SIZE)).toBe(OCTAVE_LEVEL_KILO);
    // mega: 1 MiB + 1 through 1 GiB
    expect(minimumOctaveForSize(OCTAVE1_CELL_SIZE + 1)).toBe(OCTAVE_LEVEL_MEGA);
    expect(minimumOctaveForSize(OCTAVE2_CELL_SIZE)).toBe(OCTAVE_LEVEL_MEGA);
    // giga: 1 GiB + 1 through 1 TiB
    const OCTAVE3_CELL_SIZE = 1024 * 1024 * 1024 * 1024;
    expect(minimumOctaveForSize(OCTAVE2_CELL_SIZE + 1)).toBe(OCTAVE_LEVEL_GIGA);
    expect(minimumOctaveForSize(OCTAVE3_CELL_SIZE)).toBe(OCTAVE_LEVEL_GIGA);
    // null: above 1 TiB
    expect(minimumOctaveForSize(OCTAVE3_CELL_SIZE + 1)).toBeNull();
  });

  test('oct2+: octave constants are correct (KILO=1, MEGA=2, GIGA=3, MAX=3)', () => {
    expect(OCTAVE_LEVEL_BASE).toBe(0);
    expect(OCTAVE_LEVEL_KILO).toBe(1);
    expect(OCTAVE_LEVEL_MEGA).toBe(2);
    expect(OCTAVE_LEVEL_GIGA).toBe(3);
    expect(MAX_OCTAVE_LEVEL).toBe(3);
  });

  test('oct2+: 2048-byte payload escalates to octave-1 (kilo)', () => {
    // 2048 > 1024, so minimumOctaveForSize(2048) = kilo (1)
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(2048, 0xab);
    const packed = packEscalated(header, payload);
    expect(packed.buffer[257]).toBe(OCTAVE_LEVEL_KILO);
    // O-1: total_size = 16
    expect(packed.buffer.readUInt32LE(90)).toBe(16);
    const obj = unpackEscalated(packed.buffer);
    expect(obj.descriptor.octaveLevel).toBe(OCTAVE_LEVEL_KILO);
    expect(Number(obj.descriptor.totalBytes)).toBe(2048);
  });

  test('oct2+: 512-byte payload escalates to octave-0 (base)', () => {
    // 512 ≤ 1024, so minimumOctaveForSize(512) = base (0)
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(512, 0x55);
    const packed = packEscalated(header, payload);
    expect(packed.buffer[257]).toBe(OCTAVE_LEVEL_BASE);
    // O-1: total_size = 16
    expect(packed.buffer.readUInt32LE(90)).toBe(16);
    const obj = unpackEscalated(packed.buffer);
    expect(obj.descriptor.octaveLevel).toBe(OCTAVE_LEVEL_BASE);
    expect(Number(obj.descriptor.totalBytes)).toBe(512);
  });

  test('oct2+: payload just above 1 MiB routes to octave-2 (mega) — synthetic size', () => {
    // 1 MiB + 1 byte: just above kilo boundary → mega (2)
    expect(minimumOctaveForSize(OCTAVE1_CELL_SIZE + 1)).toBe(OCTAVE_LEVEL_MEGA);
    // exactly at 1 GiB boundary → still mega (2)
    expect(minimumOctaveForSize(OCTAVE2_CELL_SIZE)).toBe(OCTAVE_LEVEL_MEGA);
    // 2 GiB is above the 1 GiB mega ceiling → giga (3)
    const TWO_GIB = 2 * 1024 * 1024 * 1024;
    expect(minimumOctaveForSize(TWO_GIB)).toBe(OCTAVE_LEVEL_GIGA);
  });

  test('oct2+: payload > 1 TiB returns null from minimumOctaveForSize (ceiling exceeded)', () => {
    const ONE_TIB = 1024 * 1024 * 1024 * 1024;
    const OVER_TIB = ONE_TIB + 1;
    expect(minimumOctaveForSize(OVER_TIB)).toBeNull();
  });

  test('oct2+: OCTAVE2_CELL_SIZE constant matches spec (1 GiB)', () => {
    expect(OCTAVE2_CELL_SIZE).toBe(1024 * 1024 * 1024);
  });

  test('oct2+: O-1 total_size=16 for all rung≥1 (spot-check multiple sizes)', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const sizes = [1, 100, 512, 1024, 2048, OCTAVE1_CELL_SIZE];
    for (const sz of sizes) {
      const payload = Buffer.alloc(sz, 0x7f);
      const packed = packEscalated(header, payload);
      // O-1 rule: header offset 90 must be 16 (ESCALATION_DESCRIPTOR_SIZE) for ALL rung≥1
      const totalSize = packed.buffer.readUInt32LE(90);
      if (totalSize !== 16) {
        throw new Error(`O-1 violation for payload size ${sz}: total_size=${totalSize}, expected 16`);
      }
    }
  });
});

```
