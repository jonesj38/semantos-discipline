---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/__tests__/varint.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.834792+00:00
---

# core/cell-ops/src/packer/__tests__/varint.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  decodeVarInt,
  encodeVarInt,
  sizeOfVarInt,
} from '../varint';

describe('sizeOfVarInt', () => {
  test('1. < 0xfd → 1 byte', () => {
    expect(sizeOfVarInt(0)).toBe(1);
    expect(sizeOfVarInt(0xfc)).toBe(1);
  });

  test('2. ≤ 0xffff → 3 bytes', () => {
    expect(sizeOfVarInt(0xfd)).toBe(3);
    expect(sizeOfVarInt(0xffff)).toBe(3);
  });

  test('3. ≤ 0xffffffff → 5 bytes', () => {
    expect(sizeOfVarInt(0x10000)).toBe(5);
    expect(sizeOfVarInt(0xffffffff)).toBe(5);
  });

  test('4. above u32 → 9 bytes', () => {
    expect(sizeOfVarInt(0x100000000)).toBe(9);
  });

  test('5. negative throws', () => {
    expect(() => sizeOfVarInt(-1)).toThrow('negative');
  });
});

describe('encodeVarInt + decodeVarInt round-trip', () => {
  test('6. exhaustive round-trip across all four size classes', () => {
    const cases = [0, 1, 0xfc, 0xfd, 0x100, 0xffff, 0x10000, 0xffffffff, 0x100000000, 0x123456789];
    for (const value of cases) {
      const buf = Buffer.alloc(9);
      const written = encodeVarInt(buf, 0, value);
      const decoded = decodeVarInt(buf, 0);
      expect(decoded.value).toBe(value);
      expect(decoded.bytesRead).toBe(written);
      expect(written).toBe(sizeOfVarInt(value));
    }
  });

  test('7. property: 1000 random non-negative integers round-trip exactly', () => {
    for (let i = 0; i < 1000; i++) {
      const value = Math.floor(Math.random() * 0xffffffff);
      const buf = Buffer.alloc(9);
      const written = encodeVarInt(buf, 0, value);
      const { value: out, bytesRead } = decodeVarInt(buf, 0);
      expect(out).toBe(value);
      expect(bytesRead).toBe(written);
    }
  });

  test('8. byte layout: 0xfd marker + LE for u16', () => {
    const buf = Buffer.alloc(9);
    encodeVarInt(buf, 0, 0x1234);
    expect(buf[0]).toBe(0xfd);
    expect(buf[1]).toBe(0x34);
    expect(buf[2]).toBe(0x12);
  });

  test('9. byte layout: 0xfe marker + LE for u32', () => {
    const buf = Buffer.alloc(9);
    encodeVarInt(buf, 0, 0x12345678);
    expect(buf[0]).toBe(0xfe);
    expect(buf[1]).toBe(0x78);
    expect(buf[4]).toBe(0x12);
  });
});

describe('decodeVarInt error cases', () => {
  test('10. throws on out-of-range offset', () => {
    expect(() => decodeVarInt(Buffer.alloc(0), 0)).toThrow('out of range');
  });

  test('11. throws when 0xfd buffer is too short', () => {
    const buf = Buffer.from([0xfd, 0x12]);
    expect(() => decodeVarInt(buf, 0)).toThrow('needs 3 bytes');
  });

  test('12. throws when 0xfe buffer is too short', () => {
    const buf = Buffer.from([0xfe, 0x12, 0x34]);
    expect(() => decodeVarInt(buf, 0)).toThrow('needs 5 bytes');
  });
});

```
