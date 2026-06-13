---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/pointer-cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.825421+00:00
---

# archive/apps-world-client/src/pointer-cell.ts

```ts
// M4.4 — Pointer cell pack/unpack TypeScript parity (D6.3 deferred work).
//
// Produces byte-identical output to core/cell-engine/src/pointer.zig
// packPointerCell / unpackPointerCell.
//
// Wire format (1024 bytes total):
//   [0..7]    8-byte ContinuationHeader (cellType=0x06, cellIndex u16 LE,
//             totalCells u16 LE, payloadSize=90 u16 LE, reserved=0)
//   [8..97]   90-byte PointerPayload
//   [98..1023] 926 zero bytes (padding)
//
// PointerPayload layout (byte offsets relative to byte 8 of the cell):
//   [0]      octave         u8      target octave level (0-3)
//   [1..2]   slot           u16 LE  slot within that octave (0-1023)
//   [3..6]   offset         u32 LE  byte offset within the cell
//   [7]      _slot_pad      u8      always 0
//   [8..39]  content_hash   [32]u8  SHA-256 of referenced content
//   [40..71] type_hash      [32]u8  type hash (CAS lookup)
//   [72..79] total_size     u64 LE  actual byte size of referenced object
//   [80]     flags          u8      IMMUTABLE|ENCRYPTED|COMPRESSED
//   [81..82] fragment_count u16 LE  sub-cells at target octave (0 = single)
//   [83..89] reserved       [7]u8   future use
//
// Reference: core/cell-engine/src/pointer.zig (Phase 6, D6.1/D6.3)

// ── Constants ─────────────────────────────────────────────────────────────────

export const CELL_SIZE = 1024;
export const CONTINUATION_HEADER_SIZE = 8;

/** First byte of every pointer cell — mirrors POINTER_CELL_TYPE in Zig. */
export const POINTER_CELL_TYPE = 0x06;

/** Byte length of the PointerPayload section — mirrors POINTER_PAYLOAD_SIZE in Zig. */
export const POINTER_PAYLOAD_SIZE = 90;

/** Pointer payload flags — mirrors PointerFlags in Zig. */
export const PointerFlags = {
  IMMUTABLE: 0x01,
  ENCRYPTED: 0x02,
  COMPRESSED: 0x04,
} as const;
export type PointerFlagValue = (typeof PointerFlags)[keyof typeof PointerFlags];

// ── Types ─────────────────────────────────────────────────────────────────────

/**
 * Pointer payload — mirrors PointerPayload struct in pointer.zig.
 *
 * All multi-byte integers use little-endian encoding on the wire, matching
 * the Zig `std.mem.writeInt(..., .little)` calls.
 */
export interface PointerPayload {
  /** Target octave level: 0=base(1KB), 1=kilo(1MB), 2=mega(1GB), 3=giga(1TB) */
  octave: 0 | 1 | 2 | 3;
  /** Slot within that octave (0-1023) */
  slot: number;
  /** Byte offset within the cell */
  offset: number;
  /** SHA-256 of referenced content — must be exactly 32 bytes */
  contentHash: Uint8Array;
  /** Type hash for CAS lookup — must be exactly 32 bytes */
  typeHash: Uint8Array;
  /** Actual byte size of the referenced object */
  totalSize: bigint;
  /** Bit field: IMMUTABLE=0x01, ENCRYPTED=0x02, COMPRESSED=0x04 */
  flags: number;
  /** Number of sub-cells at target octave (0 = single) */
  fragmentCount: number;
  /** Reserved for future use — must be exactly 7 bytes */
  reserved: Uint8Array;
}

// ── Pack ──────────────────────────────────────────────────────────────────────

/**
 * Pack a PointerPayload into a 1024-byte cell buffer.
 *
 * Produces byte-identical output to Zig's packPointerCell.
 *
 * @param payload     The pointer payload to encode.
 * @param cellIndex   1-based position among continuation cells.
 * @param totalCells  Count of continuation cells (excluding Cell 0).
 * @returns A new 1024-byte Uint8Array.
 */
export function packPointerCell(
  payload: PointerPayload,
  cellIndex: number,
  totalCells: number,
): Uint8Array {
  if (payload.contentHash.length !== 32) {
    throw new Error(
      `contentHash must be exactly 32 bytes; got ${payload.contentHash.length}`,
    );
  }
  if (payload.typeHash.length !== 32) {
    throw new Error(
      `typeHash must be exactly 32 bytes; got ${payload.typeHash.length}`,
    );
  }
  if (payload.reserved.length !== 7) {
    throw new Error(
      `reserved must be exactly 7 bytes; got ${payload.reserved.length}`,
    );
  }

  const cell = new Uint8Array(CELL_SIZE); // zeroed by default
  const view = new DataView(cell.buffer);

  // ── 8-byte ContinuationHeader ─────────────────────────────────────────────
  // [0]    cellType        u8
  // [1..2] cellIndex       u16 LE
  // [3..4] totalCells      u16 LE
  // [5..6] payloadSize     u16 LE
  // [7]    reserved        u8
  view.setUint8(0, POINTER_CELL_TYPE);
  view.setUint16(1, cellIndex, true);  // LE
  view.setUint16(3, totalCells, true); // LE
  view.setUint16(5, POINTER_PAYLOAD_SIZE, true); // LE
  view.setUint8(7, 0); // reserved

  // ── 90-byte PointerPayload starting at byte 8 ─────────────────────────────
  const p = CONTINUATION_HEADER_SIZE; // = 8

  view.setUint8(p + 0, payload.octave);
  view.setUint16(p + 1, payload.slot, true);    // LE
  view.setUint32(p + 3, payload.offset, true);  // LE
  view.setUint8(p + 7, 0);                      // slot_pad

  cell.set(payload.contentHash, p + 8);   // [8..39]
  cell.set(payload.typeHash, p + 40);     // [40..71]

  // total_size: u64 LE — split into two u32 writes since DataView.setBigUint64
  // is available but bigint is used directly here for clarity.
  view.setBigUint64(p + 72, payload.totalSize, true); // LE

  view.setUint8(p + 80, payload.flags);
  view.setUint16(p + 81, payload.fragmentCount, true); // LE

  cell.set(payload.reserved, p + 83);    // [83..89]

  // Bytes 98..1023 remain zero (already zeroed by Uint8Array constructor).

  return cell;
}

// ── Unpack ────────────────────────────────────────────────────────────────────

/**
 * Unpack a PointerPayload from a 1024-byte cell buffer.
 *
 * Produces byte-identical parsing to Zig's unpackPointerCell.
 * Throws if the buffer is not a valid pointer cell.
 *
 * @param cell  A 1024-byte buffer.
 * @returns The decoded PointerPayload.
 */
export function unpackPointerCell(cell: Uint8Array): PointerPayload {
  if (cell.length !== CELL_SIZE) {
    throw new Error(
      `pointer cell must be exactly ${CELL_SIZE} bytes; got ${cell.length}`,
    );
  }

  // Verify continuation type — matches Zig: if (cell[0] != POINTER_CELL_TYPE) ...
  if (cell[0] !== POINTER_CELL_TYPE) {
    throw new Error(
      `not a pointer cell: byte[0]=0x${cell[0].toString(16).padStart(2, "0")} expected 0x06`,
    );
  }

  const view = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
  const p = CONTINUATION_HEADER_SIZE; // = 8

  const octave = view.getUint8(p + 0) as 0 | 1 | 2 | 3;
  const slot = view.getUint16(p + 1, true);    // LE
  const offset = view.getUint32(p + 3, true);  // LE
  // skip slot_pad at p+7
  const contentHash = cell.slice(p + 8, p + 40);   // 32 bytes
  const typeHash = cell.slice(p + 40, p + 72);      // 32 bytes
  const totalSize = view.getBigUint64(p + 72, true); // LE
  const flags = view.getUint8(p + 80);
  const fragmentCount = view.getUint16(p + 81, true); // LE
  const reserved = cell.slice(p + 83, p + 90);         // 7 bytes

  return {
    octave,
    slot,
    offset,
    contentHash,
    typeHash,
    totalSize,
    flags,
    fragmentCount,
    reserved,
  };
}

/**
 * Return true if the 1024-byte buffer is a pointer cell (type byte == 0x06).
 * Does not validate the rest of the cell.
 */
export function isPointerCell(cell: Uint8Array): boolean {
  return cell.length === CELL_SIZE && cell[0] === POINTER_CELL_TYPE;
}

```
