---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/varint.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.830607+00:00
---

# core/cell-ops/src/packer/varint.ts

```ts
/**
 * Bitcoin VarInt encoding — pure functions, zero project imports.
 *
 * Per the prompt-41 spec acceptance criterion: "varint.ts has zero
 * imports from other project files." This file is self-contained
 * so the encoding can be re-used by any consumer without dragging
 * in the rest of the cell-ops surface.
 *
 * Bitcoin VarInt format (Compact Size Unsigned Integer):
 *   value < 0xfd        → 1 byte
 *   value ≤ 0xffff      → 0xfd + 2-byte LE
 *   value ≤ 0xffffffff  → 0xfe + 4-byte LE
 *   value > 0xffffffff  → 0xff + 8-byte LE (capped at MAX_SAFE_INTEGER)
 */

const MAX_U16 = 0xffff;
const MAX_U32 = 0xffffffff;

/** Number of bytes the VarInt encoding of `value` will occupy. */
export function sizeOfVarInt(value: number): number {
  if (value < 0) throw new Error(`VarInt cannot encode negative value: ${value}`);
  if (value < 0xfd) return 1;
  if (value <= MAX_U16) return 3;
  if (value <= MAX_U32) return 5;
  return 9;
}

/**
 * Encode `value` as a Bitcoin VarInt and write it into `buf` at
 * `offset`. Returns the number of bytes written.
 */
export function encodeVarInt(buf: Buffer, offset: number, value: number): number {
  if (value < 0) throw new Error(`VarInt cannot encode negative value: ${value}`);
  if (!Number.isFinite(value)) throw new Error(`VarInt requires finite integer, got ${value}`);

  if (value < 0xfd) {
    buf.writeUInt8(value, offset);
    return 1;
  }
  if (value <= MAX_U16) {
    buf.writeUInt8(0xfd, offset);
    buf.writeUInt16LE(value, offset + 1);
    return 3;
  }
  if (value <= MAX_U32) {
    buf.writeUInt8(0xfe, offset);
    buf.writeUInt32LE(value, offset + 1);
    return 5;
  }
  if (value > Number.MAX_SAFE_INTEGER) {
    throw new Error(`VarInt cannot encode value above MAX_SAFE_INTEGER: ${value}`);
  }
  buf.writeUInt8(0xff, offset);
  const lo = value >>> 0;
  const hi = Math.floor(value / 0x100000000);
  buf.writeUInt32LE(lo, offset + 1);
  buf.writeUInt32LE(hi, offset + 5);
  return 9;
}

export interface DecodedVarInt {
  value: number;
  bytesRead: number;
}

/**
 * Decode a Bitcoin VarInt from `buf` starting at `offset`.
 * Throws if the buffer is too short or the discriminator is invalid.
 */
export function decodeVarInt(buf: Buffer, offset: number): DecodedVarInt {
  if (offset < 0 || offset >= buf.length) {
    throw new Error(`VarInt offset ${offset} out of range (buffer length ${buf.length})`);
  }
  const first = buf.readUInt8(offset);
  if (first < 0xfd) {
    return { value: first, bytesRead: 1 };
  }
  if (first === 0xfd) {
    if (offset + 3 > buf.length) {
      throw new Error(`VarInt 0xfd needs 3 bytes; buffer has ${buf.length - offset}`);
    }
    return { value: buf.readUInt16LE(offset + 1), bytesRead: 3 };
  }
  if (first === 0xfe) {
    if (offset + 5 > buf.length) {
      throw new Error(`VarInt 0xfe needs 5 bytes; buffer has ${buf.length - offset}`);
    }
    return { value: buf.readUInt32LE(offset + 1), bytesRead: 5 };
  }
  if (offset + 9 > buf.length) {
    throw new Error(`VarInt 0xff needs 9 bytes; buffer has ${buf.length - offset}`);
  }
  const lo = buf.readUInt32LE(offset + 1);
  const hi = buf.readUInt32LE(offset + 5);
  const value = hi * 0x100000000 + lo;
  return { value, bytesRead: 9 };
}

```
