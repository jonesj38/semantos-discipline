---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/memory-helpers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.832424+00:00
---

# core/cell-ops/src/wasm/__tests__/memory-helpers.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import {
  pointerAdd,
  readBytes,
  readBytesView,
  readCString,
  readU32LE,
  readUtf8,
  writeBytes,
  writeU32LE,
  writeUtf8,
} from '../memory-helpers';

function fakeMemory(size = 256): { buffer: ArrayBuffer } {
  return { buffer: new ArrayBuffer(size) };
}

describe('readBytes / writeBytes', () => {
  test('round-trips a byte payload', () => {
    const mem = fakeMemory();
    const payload = new Uint8Array([1, 2, 3, 4, 5]);
    const written = writeBytes(mem, 16, payload);
    expect(written).toBe(5);
    expect(Array.from(readBytes(mem, 16, 5))).toEqual([1, 2, 3, 4, 5]);
  });

  test('readBytes returns a copy (independent of underlying memory)', () => {
    const mem = fakeMemory();
    writeBytes(mem, 0, new Uint8Array([7, 8, 9]));
    const copy = readBytes(mem, 0, 3);
    writeBytes(mem, 0, new Uint8Array([0, 0, 0]));
    expect(Array.from(copy)).toEqual([7, 8, 9]);
  });

  test('readBytes(0) returns empty array', () => {
    const mem = fakeMemory();
    expect(readBytes(mem, 0, 0).length).toBe(0);
  });

  test('readBytes negative length throws', () => {
    const mem = fakeMemory();
    expect(() => readBytes(mem, 0, -1)).toThrow();
  });
});

describe('readBytesView', () => {
  test('view shares storage with memory', () => {
    const mem = fakeMemory();
    writeBytes(mem, 4, new Uint8Array([42, 43]));
    const view = readBytesView(mem, 4, 2);
    expect(view[0]).toBe(42);
    new Uint8Array(mem.buffer, 4, 1)[0] = 99;
    expect(view[0]).toBe(99); // shared storage
  });

  test('negative length throws', () => {
    expect(() => readBytesView(fakeMemory(), 0, -1)).toThrow();
  });
});

describe('readCString / readUtf8 / writeUtf8', () => {
  test('writes UTF-8 string and reads it back via length', () => {
    const mem = fakeMemory();
    const written = writeUtf8(mem, 8, 'hello');
    expect(written).toBe(5);
    expect(readUtf8(mem, 8, 5)).toBe('hello');
  });

  test('readCString stops at NUL byte', () => {
    const mem = fakeMemory();
    writeBytes(mem, 16, new Uint8Array([72, 105, 0, 88, 89]));
    expect(readCString(mem, 16)).toBe('Hi');
  });

  test('readCString respects maxLen cap', () => {
    const mem = fakeMemory(64);
    writeBytes(mem, 16, new Uint8Array([65, 66, 67, 68, 69]));
    expect(readCString(mem, 16, 3)).toBe('ABC');
  });

  test('readCString(ptr=0) returns empty string (NULL convention)', () => {
    expect(readCString(fakeMemory(), 0)).toBe('');
  });

  test('readUtf8(len <= 0) returns empty string', () => {
    expect(readUtf8(fakeMemory(), 8, 0)).toBe('');
  });
});

describe('readU32LE / writeU32LE', () => {
  test('round-trips a 32-bit value', () => {
    const mem = fakeMemory();
    writeU32LE(mem, 12, 0xdeadbeef);
    expect(readU32LE(mem, 12)).toBe(0xdeadbeef);
  });

  test('little-endian byte order', () => {
    const mem = fakeMemory();
    writeU32LE(mem, 0, 0x01020304);
    expect(Array.from(readBytes(mem, 0, 4))).toEqual([0x04, 0x03, 0x02, 0x01]);
  });
});

describe('pointerAdd', () => {
  test('adds integer offsets', () => {
    expect(pointerAdd(100, 4)).toBe(104);
    expect(pointerAdd(0, 0)).toBe(0);
  });

  test('rejects non-integer args', () => {
    expect(() => pointerAdd(1.5, 0)).toThrow();
    expect(() => pointerAdd(0, Number.NaN)).toThrow();
  });
});

```
