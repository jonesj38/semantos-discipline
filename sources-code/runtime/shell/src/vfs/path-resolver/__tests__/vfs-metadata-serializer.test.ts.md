---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/__tests__/vfs-metadata-serializer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.394153+00:00
---

# runtime/shell/src/vfs/path-resolver/__tests__/vfs-metadata-serializer.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { deserializeCellHeader } from '@semantos/protocol-types';
import type { CellHeader } from '@semantos/protocol-types';
import { serializeHeaderBin } from '../vfs-metadata-serializer';

function header(over: Partial<CellHeader> = {}): CellHeader {
  return {
    magic: new Uint8Array(16).fill(0xab),
    linearity: 1,
    version: 2,
    flags: 0xff,
    refCount: 7,
    typeHash: new Uint8Array(32).fill(0x11),
    ownerId: new Uint8Array(16).fill(0x22),
    timestamp: 1700000000000n,
    cellCount: 1,
    totalSize: 256,
    parentHash: new Uint8Array(32).fill(0x33),
    prevStateHash: new Uint8Array(32).fill(0x44),
    domainPayloadRoot: new Uint8Array(32).fill(0x55),
    ...over,
  };
}

describe('serializeHeaderBin', () => {
  test('1. emits a 256-byte buffer', () => {
    const out = serializeHeaderBin(header());
    expect(out.size).toBe(256);
    expect(out.data.length).toBe(256);
  });

  test('2. round-trips through deserializeCellHeader', () => {
    const h = header();
    const out = serializeHeaderBin(h);
    const back = deserializeCellHeader(new Uint8Array(out.data.buffer, out.data.byteOffset, out.data.byteLength));
    expect(back.linearity).toBe(h.linearity);
    expect(back.version).toBe(h.version);
    expect(back.flags).toBe(h.flags);
    expect(back.refCount).toBe(h.refCount);
    expect(back.cellCount).toBe(h.cellCount);
    expect(back.totalSize).toBe(h.totalSize);
    // RM-032b: commerce phase/dimension removed from CellHeader.
    expect(back.domainPayloadRoot).toEqual(h.domainPayloadRoot);
    expect(back.timestamp).toBe(h.timestamp);
  });

  test('3. preserves the typeHash + ownerId bytes', () => {
    const out = serializeHeaderBin(header());
    expect(out.data[30]).toBe(0x11); // typeHash starts at offset 30
    expect(out.data[62]).toBe(0x22); // ownerId starts at offset 62
  });

  test('4. preserves parentHash + prevStateHash bytes', () => {
    const out = serializeHeaderBin(header());
    expect(out.data[96]).toBe(0x33); // parentHash starts at offset 96
    expect(out.data[128]).toBe(0x44); // prevStateHash starts at offset 128
  });
});

```
