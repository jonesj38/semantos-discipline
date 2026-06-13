---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/__tests__/beef-codec.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.802615+00:00
---

# archive/apps-poker-agent/src/shared/__tests__/beef-codec.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { fromArray, isBeefArray, isHexBeef, toArray } from '../beef-codec';

describe('toArray / fromArray', () => {
  test('1. number[] passes through unchanged', () => {
    const arr = [0, 1, 254, 255];
    expect(toArray(arr)).toBe(arr);
  });

  test('2. hex string round-trips through toArray + fromArray', () => {
    const hex = 'deadbeef';
    expect(fromArray(toArray(hex))).toBe(hex);
  });

  test('3. lowercase hex matches uppercase hex bytes', () => {
    const lo = toArray('cafebabe');
    const hi = toArray('CAFEBABE');
    expect(lo).toEqual(hi);
  });

  test('4. fromArray emits lowercase hex', () => {
    expect(fromArray([0xab, 0xcd, 0xef])).toBe('abcdef');
  });

  test('5. matches the inline pattern legacy code uses', () => {
    // Pattern from poker-state-machine.ts.
    const inline = (x: string | number[]) =>
      Array.isArray(x) ? x : Array.from(Buffer.from(x as string, 'hex'));
    for (const sample of ['', '00', 'deadbeef', '0102030405']) {
      expect(toArray(sample)).toEqual(inline(sample));
    }
    for (const sample of [[], [0], [255, 254, 253]]) {
      expect(toArray(sample)).toEqual(inline(sample));
    }
  });
});

describe('type guards', () => {
  test('6. isBeefArray accepts arrays', () => {
    expect(isBeefArray([])).toBe(true);
    expect(isBeefArray([1, 2, 3])).toBe(true);
    expect(isBeefArray('abc')).toBe(false);
    expect(isBeefArray(null)).toBe(false);
  });

  test('7. isHexBeef accepts hex strings only', () => {
    expect(isHexBeef('')).toBe(true);
    expect(isHexBeef('abcdef')).toBe(true);
    expect(isHexBeef('0123456789abcdef')).toBe(true);
    expect(isHexBeef('XYZ')).toBe(false);
    expect(isHexBeef('0x12')).toBe(false);
    expect(isHexBeef([])).toBe(false);
  });
});

```
