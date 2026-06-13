---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/have-bitfield.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.052742+00:00
---

# runtime/session-protocol/src/swarm/have-bitfield.ts

```ts
/**
 * HAVE bitfield — which data cells of a file a peer currently holds.
 *
 * One bit per cell index, MSB-first (bit 7 of byte 0 = cell index 0), matching
 * the BitTorrent convention. `ceil(totalCells / 8)` bytes. A peer broadcasts
 * its bitfield (framed by swarm-wire `MSG_SWARM_HAVE`) on join and whenever its
 * HAVE set grows; the leecher aggregates peers' bitfields and feeds them to
 * rarest-first piece selection.
 *
 * Pure — no I/O, no transport. The wire framing (12-byte header) lives in
 * swarm-wire.ts; this module owns the HAVE *payload* codec and the bit ops.
 */

/** Bytes needed for a bitfield over `totalCells` indices. */
export function bitfieldBytes(totalCells: number): number {
  return Math.ceil(totalCells / 8);
}

/** A zeroed bitfield sized for `totalCells`. */
export function emptyBitfield(totalCells: number): Uint8Array {
  return new Uint8Array(bitfieldBytes(totalCells));
}

/** True iff `index` is within range and its bit is set. */
export function hasCell(bitfield: Uint8Array, index: number): boolean {
  if (index < 0) return false;
  const byte = index >> 3;
  if (byte >= bitfield.length) return false;
  return (bitfield[byte]! & (0x80 >> (index & 7))) !== 0;
}

/** Set the bit for `index` (mutates `bitfield`). */
export function setHave(bitfield: Uint8Array, index: number): void {
  const byte = index >> 3;
  if (index < 0 || byte >= bitfield.length) {
    throw new Error(`setHave: index ${index} out of range for ${bitfield.length * 8}-bit field`);
  }
  bitfield[byte]! |= 0x80 >> (index & 7);
}

/** Clear the bit for `index` (mutates `bitfield`). */
export function clearHave(bitfield: Uint8Array, index: number): void {
  const byte = index >> 3;
  if (index < 0 || byte >= bitfield.length) return;
  bitfield[byte]! &= ~(0x80 >> (index & 7)) & 0xff;
}

/** Build a bitfield from an iterable of held cell indices. */
export function bitfieldFor(haveIndices: Iterable<number>, totalCells: number): Uint8Array {
  const bf = emptyBitfield(totalCells);
  for (const i of haveIndices) {
    if (i >= 0 && i < totalCells) setHave(bf, i);
  }
  return bf;
}

/** Number of held cells (popcount over the valid index range). */
export function haveCount(bitfield: Uint8Array, totalCells: number): number {
  let n = 0;
  for (let i = 0; i < totalCells; i++) if (hasCell(bitfield, i)) n++;
  return n;
}

/** Indices in `[0, totalCells)` whose bit is NOT set. */
export function missingCells(bitfield: Uint8Array, totalCells: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < totalCells; i++) if (!hasCell(bitfield, i)) out.push(i);
  return out;
}

/** True iff every cell in `[0, totalCells)` is held. */
export function isComplete(bitfield: Uint8Array, totalCells: number): boolean {
  for (let i = 0; i < totalCells; i++) if (!hasCell(bitfield, i)) return false;
  return true;
}

/** Bitwise-OR two bitfields into a new buffer (the union of held cells). */
export function mergeBitfields(a: Uint8Array, b: Uint8Array): Uint8Array {
  const len = Math.max(a.length, b.length);
  const out = new Uint8Array(len);
  for (let i = 0; i < len; i++) out[i] = (a[i] ?? 0) | (b[i] ?? 0);
  return out;
}

// ── HAVE payload codec (framed by swarm-wire MSG_SWARM_HAVE) ───────────────────

/** Byte length of an encoded HAVE payload for `totalCells`. */
export function havePayloadSize(totalCells: number): number {
  return 32 /* infohash */ + 4 /* totalCells */ + bitfieldBytes(totalCells);
}

/**
 * Encode a HAVE payload: `infohash(32) | totalCells(u32 LE) | bitfield(⌈n/8⌉)`.
 * The bitfield is copied/truncated to exactly `⌈totalCells/8⌉` bytes.
 */
export function encodeHave(infohash: Uint8Array, totalCells: number, bitfield: Uint8Array): Uint8Array {
  if (infohash.length !== 32) throw new Error('encodeHave: infohash must be 32 bytes');
  const bfLen = bitfieldBytes(totalCells);
  const out = new Uint8Array(36 + bfLen);
  out.set(infohash, 0);
  new DataView(out.buffer).setUint32(32, totalCells >>> 0, true);
  out.set(bitfield.subarray(0, bfLen), 36);
  return out;
}

export interface HavePayload {
  infohash: Uint8Array;
  totalCells: number;
  bitfield: Uint8Array;
}

/** Decode a HAVE payload. Throws on truncation. */
export function decodeHave(payload: Uint8Array): HavePayload {
  if (payload.length < 36) throw new Error(`decodeHave: payload too small (${payload.length})`);
  const totalCells = new DataView(payload.buffer, payload.byteOffset, payload.byteLength).getUint32(32, true);
  const bfLen = bitfieldBytes(totalCells);
  if (payload.length < 36 + bfLen) {
    throw new Error(`decodeHave: payload too small for ${totalCells} cells (need ${36 + bfLen}, got ${payload.length})`);
  }
  return {
    infohash: payload.slice(0, 32),
    totalCells,
    bitfield: payload.slice(36, 36 + bfLen),
  };
}

```
