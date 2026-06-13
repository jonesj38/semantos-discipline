---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/multicell-assembler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.829776+00:00
---

# core/cell-ops/src/packer/multicell-assembler.ts

```ts
/**
 * Multi-cell pack/unpack — the on-wire layer between
 * `MultiCellObject` and the contiguous byte buffer the cell engine
 * sees. Pure (no IO).
 *
 * ## Escalation (rung-1, octave-1) — D-OCT-data-octave-bump
 *
 * This module adds `packEscalated` / `unpackEscalated` / `isEscalated`
 * alongside the existing `packMultiCell` / `unpackMultiCell` (rung-0).
 *
 * Wire format for an escalated (rung-1) object:
 *
 *   [Cell 0: 256-byte header] — cell_count field (offset 86) = SENTINEL (0xFFFFFFFF)
 *                               total_size field (offset 90)  = 16 (descriptor size, O-1)
 *   [Cell 0: 768-byte payload region]
 *     bytes 0..15  : 16-byte escalation descriptor (rung=1, octave_level=1, child_count=1,
 *                    total_bytes=len, reserved=0)
 *     bytes 16..767: zero-padded
 *   [bytes 1024..(1024+len)]: raw child data, NOT padded
 *
 * Escalation detection: `isEscalated(buffer)` reads `cell_count` at offset 86.
 * If it equals ESCALATION_CELL_COUNT_SENTINEL (0xFFFFFFFF), the object is escalated.
 * Otherwise it is a normal rung-0 multicell object.
 *
 * O-1 (header total_size): for escalated objects, Cell 0's total_size u32 means
 * "bytes of content in this cell" = 16 (the descriptor).  The descriptor's
 * total_bytes u64 is the authoritative logical payload size.
 *
 * Octave-1 cap: payload ≤ 1,048,576 bytes (1 MiB).  Anything larger should be
 * handled by the caller (octave-2+ is step 5, not implemented here).
 *
 * All rung-0 (inline / small-multicell) bytes are UNCHANGED — backward-compatible.
 *
 * Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §2/§5/§7/§8.
 * Zig mirror: core/cell-engine/src/multicell.zig (keep byte-identical).
 */

import { createHash } from 'crypto';

import {
  CELL_SIZE,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
} from './constants';
import {
  buildContinuationHeader,
  parseContinuationHeader,
} from './continuation-handlers';
import type {
  ContinuationCell,
  MultiCellObject,
  PackedMultiCell,
} from './types';

// ── Escalation constants (mirrors multicell.zig) ─────────────────────────────

/** Sentinel written to Cell 0 `cell_count` (offset 86) for escalated objects. */
export const ESCALATION_CELL_COUNT_SENTINEL = 0xffffffff;

/** Maximum payload size for an octave-0 object (768 B inline + 64 × 1016 B). */
export const MAX_CONTINUATIONS = 64;
export const OCTAVE0_FLAT_CAPACITY = PAYLOAD_SIZE + MAX_CONTINUATIONS * CONTINUATION_PAYLOAD_SIZE;

/** Size of the escalation descriptor in bytes (mirrors escalation_descriptor.zig). */
const ESCALATION_DESCRIPTOR_SIZE = 16;

/** Rung values for the escalation descriptor. */
const RUNG_OCTAVE_ESCALATED = 1;

/**
 * Octave level constants — mirrors octave.zig::Octave and multicell.zig.
 * Cell sizes are ×1024 binary (NOT ×1000).
 * D-OCT-octave-2-plus (step 5/5): mega/giga levels added.
 */
/** Octave 0: 1 KiB cells. */
export const OCTAVE_LEVEL_BASE = 0;
/** Octave 1: 1 MiB cells. */
export const OCTAVE_LEVEL_KILO = 1;
/** Octave 2: 1 GiB cells — D-OCT-octave-2-plus (step 5/5). */
export const OCTAVE_LEVEL_MEGA = 2;
/** Octave 3: 1 TiB cells — D-OCT-octave-2-plus (step 5/5). */
export const OCTAVE_LEVEL_GIGA = 3;
/** Maximum octave level: giga (3). */
export const MAX_OCTAVE_LEVEL = 3;

/** Maximum payload size for an octave-1 child cell (1 MiB). */
export const OCTAVE1_CELL_SIZE = 1024 * 1024; // 1,048,576 bytes
/** Maximum payload size for an octave-2 child cell (1 GiB) — D-OCT-octave-2-plus. */
export const OCTAVE2_CELL_SIZE = 1024 * 1024 * 1024; // 1,073,741,824 bytes
/** Maximum payload size for an octave-3 child cell (1 TiB) — D-OCT-octave-2-plus. */
export const OCTAVE3_CELL_SIZE = 1024 * 1024 * 1024 * 1024; // 1,099,511,627,776 bytes

/**
 * Select the minimum octave level needed to fit `byteLen` bytes in a single cell.
 * Mirrors octave.zig::minimumOctaveForSize.
 *
 * Returns the octave level (0=base, 1=kilo, 2=mega, 3=giga), or null if
 * `byteLen` exceeds the largest octave (1 TiB, MAX_OCTAVE_LEVEL=3).
 *
 * D-OCT-octave-2-plus (step 5/5).
 */
export function minimumOctaveForSize(byteLen: number): number | null {
  // CELL_SIZE = 1024 (octave 0, base)
  if (byteLen <= 1024) return OCTAVE_LEVEL_BASE;
  // 1 MiB (octave 1, kilo)
  if (byteLen <= OCTAVE1_CELL_SIZE) return OCTAVE_LEVEL_KILO;
  // 1 GiB (octave 2, mega)
  if (byteLen <= OCTAVE2_CELL_SIZE) return OCTAVE_LEVEL_MEGA;
  // 1 TiB (octave 3, giga) — NOTE: JS Number cannot exactly represent 1 TiB
  // (it is 2^40 = 1,099,511,627,776 which is within safe integer range 2^53-1).
  if (byteLen <= OCTAVE3_CELL_SIZE) return OCTAVE_LEVEL_GIGA;
  // Beyond MAX_OCTAVE_LEVEL=3
  return null;
}

// ── Rung-0: existing pack/unpack (UNCHANGED, backward-compatible) ─────────────

/**
 * Pack a multi-cell object into a contiguous N×1024 buffer.
 *
 * Layout:
 *   [Cell 0: 256-byte header + 768-byte payload]
 *   [Cell 1: 8-byte continuation header + 1016-byte data]
 *   ...
 *
 * Cell 0's header `cellCount` field at offset 86 is overwritten
 * with the total cell count. The buffer length is the source of
 * truth on receive — not this field — see `unpackMultiCell`.
 */
export function packMultiCell(obj: MultiCellObject): PackedMultiCell {
  const totalCells = 1 + obj.continuations.length;

  if (obj.payload.length > PAYLOAD_SIZE) {
    throw new Error(
      `Cell 0 payload too large: ${obj.payload.length} bytes (max ${PAYLOAD_SIZE}). ` +
        `Use continuation cells for overflow data.`,
    );
  }
  for (let i = 0; i < obj.continuations.length; i++) {
    if (obj.continuations[i].data.length > CONTINUATION_PAYLOAD_SIZE) {
      throw new Error(
        `Continuation cell ${i + 1} data too large: ${obj.continuations[i].data.length} bytes ` +
          `(max ${CONTINUATION_PAYLOAD_SIZE})`,
      );
    }
  }

  const buffer = Buffer.alloc(totalCells * CELL_SIZE, 0);

  // Cell 0: copy header + patch cellCount; copy payload.
  const header = Buffer.from(obj.header);
  header.writeUInt32LE(totalCells, 86);
  header.copy(buffer, 0);
  obj.payload.copy(buffer, HEADER_SIZE);

  // Cells 1..N
  for (let i = 0; i < obj.continuations.length; i++) {
    const cont = obj.continuations[i];
    const cellOffset = (i + 1) * CELL_SIZE;
    const contHeader = buildContinuationHeader({
      cellType: cont.type,
      cellIndex: i + 1,
      totalCells: obj.continuations.length,
      payloadSize: cont.data.length,
      reserved: 0,
    });
    contHeader.copy(buffer, cellOffset);
    cont.data.copy(buffer, cellOffset + CONTINUATION_HEADER_SIZE);
  }

  const contentHash = createHash('sha256').update(buffer).digest();
  return { buffer, cellCount: totalCells, contentHash };
}

/**
 * Unpack an N×1024 buffer back to its structured form (rung-0 only).
 *
 * Buffer length is the source of truth — `cellCount` at byte 86 is
 * advisory (writer-controlled). We trust the bytes that arrived.
 *
 * Use `isEscalated()` first to determine whether to call this or
 * `unpackEscalated()`.
 */
export function unpackMultiCell(buffer: Buffer): MultiCellObject {
  if (buffer.length < CELL_SIZE) {
    throw new Error(`Buffer too small: ${buffer.length} bytes (minimum ${CELL_SIZE})`);
  }
  if (buffer.length % CELL_SIZE !== 0) {
    throw new Error(`Buffer size ${buffer.length} is not a multiple of ${CELL_SIZE}`);
  }
  const totalCells = buffer.length / CELL_SIZE;

  const header = Buffer.from(buffer.subarray(0, HEADER_SIZE));
  const payloadSize = header.readUInt32LE(90);
  const payload = Buffer.from(
    buffer.subarray(HEADER_SIZE, HEADER_SIZE + Math.min(payloadSize, PAYLOAD_SIZE)),
  );

  const continuations: ContinuationCell[] = [];
  for (let i = 1; i < totalCells; i++) {
    const cellOffset = i * CELL_SIZE;
    const cellSlice = buffer.subarray(cellOffset, cellOffset + CELL_SIZE);
    const contHeader = parseContinuationHeader(cellSlice);
    continuations.push({
      type: contHeader.cellType,
      data: Buffer.from(
        cellSlice.subarray(
          CONTINUATION_HEADER_SIZE,
          CONTINUATION_HEADER_SIZE + contHeader.payloadSize,
        ),
      ),
    });
  }

  return { header, payload, continuations };
}

// ── Rung-1: escalation (octave-1) pack/unpack ─────────────────────────────────

/**
 * Result of unpacking an escalated (rung-1) buffer.
 */
export interface EscalatedObject {
  /** Cell 0 header bytes (256 bytes). */
  header: Buffer;
  /** The parsed escalation descriptor fields. */
  descriptor: {
    rung: number;
    octaveLevel: number;
    childCount: number;
    /** Logical blob size in bytes as a BigInt (descriptor's total_bytes u64). */
    totalBytes: bigint;
    reserved: number;
  };
  /** Raw child data slice from the input buffer. */
  childData: Buffer;
}

/**
 * Check whether a packed buffer is an escalated (rung-1) object.
 *
 * Reads Cell 0's `cell_count` field at offset 86 (u32 LE).
 * Returns `true` iff it equals ESCALATION_CELL_COUNT_SENTINEL (0xFFFFFFFF).
 *
 * Call this BEFORE choosing `unpackMultiCell` vs `unpackEscalated`.
 */
export function isEscalated(buffer: Buffer): boolean {
  if (buffer.length < CELL_SIZE) return false;
  return buffer.readUInt32LE(86) === ESCALATION_CELL_COUNT_SENTINEL;
}

/**
 * Write a 16-byte escalation descriptor at `offset` within `buf`.
 *
 * Layout (LE):
 *   off 0  u8:   rung
 *   off 1  u8:   octaveLevel
 *   off 2  u16:  childCount
 *   off 4  u64:  totalBytes (BigInt)
 *   off 12 u32:  reserved (always 0)
 */
function writeEscalationDescriptor(
  buf: Buffer,
  offset: number,
  rung: number,
  octaveLevel: number,
  childCount: number,
  totalBytes: bigint,
): void {
  buf.writeUInt8(rung, offset + 0);
  buf.writeUInt8(octaveLevel, offset + 1);
  buf.writeUInt16LE(childCount, offset + 2);
  buf.writeBigUInt64LE(totalBytes, offset + 4);
  buf.writeUInt32LE(0, offset + 12); // reserved = 0
}

/**
 * Read the 16-byte escalation descriptor from `buf` at `offset`.
 */
function readEscalationDescriptor(buf: Buffer, offset: number) {
  return {
    rung: buf.readUInt8(offset + 0),
    octaveLevel: buf.readUInt8(offset + 1),
    childCount: buf.readUInt16LE(offset + 2),
    totalBytes: buf.readBigUInt64LE(offset + 4),
    reserved: buf.readUInt32LE(offset + 12),
  };
}

/**
 * Pack a large blob into an escalated (rung-1) form.
 *
 * Triggers when the payload exceeds the octave-0 flat capacity
 * (OCTAVE0_FLAT_CAPACITY = ~65 KB).  The caller must supply a
 * well-formed 256-byte `header` buffer (magic, type hash, etc.).
 *
 * D-OCT-octave-2-plus (step 5/5): the octave level is selected automatically
 * via `minimumOctaveForSize` and written into the escalation descriptor:
 *   payload ≤ 1 KiB  → octave_level = 0 (base)
 *   payload ≤ 1 MiB  → octave_level = 1 (kilo)
 *   payload ≤ 1 GiB  → octave_level = 2 (mega)
 *   payload ≤ 1 TiB  → octave_level = 3 (giga)
 *   payload > 1 TiB  → throws (beyond MAX_OCTAVE_LEVEL=3)
 *
 * Wire format:
 *   [0..1023]         Cell 0 (1024 B): header with sentinel + descriptor in payload
 *   [1024..1024+len]  raw child data (exactly len bytes, NOT padded)
 *
 * O-1 header semantics (uniform for ALL rung≥1):
 *   total_size (u32 at header offset 90) = ESCALATION_DESCRIPTOR_SIZE (16).
 *   The descriptor's total_bytes (u64 BigInt) is the authoritative logical size.
 *
 * Returns a `PackedMultiCell`-compatible result where:
 *   - `buffer` is the full output (Cell 0 + child)
 *   - `cellCount` = 1 (only Cell 0 uses the standard 1024-byte slot)
 *   - `contentHash` = SHA-256 of the full buffer
 *
 * CAUTION: do NOT pass a multi-GiB/TiB Buffer in production — callers are
 * responsible for not allocating giant buffers. At octave-2/3 the canonical
 * production form is the merkle hierarchy (no giant allocation). This function
 * sets the descriptor's octave_level correctly regardless.
 */
export function packEscalated(
  header: Buffer,
  payload: Buffer,
): PackedMultiCell {
  // Select octave level (D-OCT-octave-2-plus, step 5/5).
  const octaveLevel = minimumOctaveForSize(payload.length);
  if (octaveLevel === null) {
    throw new Error(
      `Payload too large for any octave: ${payload.length} bytes ` +
        `(max ${OCTAVE3_CELL_SIZE}, beyond MAX_OCTAVE_LEVEL=${MAX_OCTAVE_LEVEL}).`,
    );
  }

  const totalLen = CELL_SIZE + payload.length;
  const buffer = Buffer.alloc(totalLen, 0);

  // ── Cell 0 ──
  // Copy header, patch cell_count (offset 86) to sentinel, total_size (offset 90) to 16.
  // O-1 rule is UNIFORM for ALL rung≥1: total_size = "bytes in THIS cell" = 16.
  const patchedHeader = Buffer.from(header);
  patchedHeader.writeUInt32LE(ESCALATION_CELL_COUNT_SENTINEL, 86);
  patchedHeader.writeUInt32LE(ESCALATION_DESCRIPTOR_SIZE, 90); // O-1: bytes in this cell
  patchedHeader.copy(buffer, 0);

  // Write the escalation descriptor at payload offset 0 (= cell byte 256).
  writeEscalationDescriptor(
    buffer,
    HEADER_SIZE + 0, // descriptor at payload offset 0 = cell byte 256
    RUNG_OCTAVE_ESCALATED,
    octaveLevel,
    1, // child_count = 1
    BigInt(payload.length),
  );

  // ── Child data ──
  payload.copy(buffer, CELL_SIZE);

  const contentHash = createHash('sha256').update(buffer).digest();
  return { buffer, cellCount: 1, contentHash };
}

/**
 * Unpack an escalated (rung-1) buffer.
 *
 * The returned `childData` is a view into the input buffer (zero-copy slice).
 * Check `isEscalated()` before calling this.
 */
export function unpackEscalated(buffer: Buffer): EscalatedObject {
  if (buffer.length < CELL_SIZE) {
    throw new Error(`Buffer too small for escalated object: ${buffer.length} bytes (minimum ${CELL_SIZE})`);
  }

  const header = Buffer.from(buffer.subarray(0, HEADER_SIZE));

  // Read descriptor at payload offset 0 (= cell byte 256).
  const descOffset = HEADER_SIZE; // = 256
  const descriptor = readEscalationDescriptor(buffer, descOffset);

  const childLen = Number(descriptor.totalBytes);
  if (buffer.length < CELL_SIZE + childLen) {
    throw new Error(
      `Buffer too small for escalated child data: ` +
        `have ${buffer.length} bytes, need ${CELL_SIZE + childLen}`,
    );
  }

  const childData = buffer.subarray(CELL_SIZE, CELL_SIZE + childLen);

  return {
    header,
    descriptor,
    childData: Buffer.from(childData),
  };
}

```
