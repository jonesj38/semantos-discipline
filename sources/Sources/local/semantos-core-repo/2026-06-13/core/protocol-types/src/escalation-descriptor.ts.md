---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/escalation-descriptor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.840659+00:00
---

# core/protocol-types/src/escalation-descriptor.ts

```ts
/**
 * Escalation-descriptor — unified 16-byte payload-side descriptor for the
 * inline → octave-escalated → merkle-rooted escalation ladder.
 *
 * Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5, §7.
 * This is Step 1 (D-OCT-escalation-descriptor) of a 5-step decomposition:
 *   1. (this) — define the wire shape + accessors (NO behaviour change).
 *   2. D-OCT-data-octave-bump   — wire rung 0→1 for data payloads.
 *   3. D-OCT-merkle-hierarchy   — rung 1→2 for data (domainPayloadRoot commit).
 *   4. D-OCT-path-merkle-unify  — point FLAG_PATH_MERKLE_OVERLOAD here.
 *   5. D-OCT-octave-2-plus      — mega/giga octaves (gated on O-1 landing).
 *
 * ---
 *
 * ## The escalation ladder
 *
 * | Rung | Name                    | When                                       |
 * |------|-------------------------|--------------------------------------------|
 * |  0   | inline                  | blob ≤ the inline region of the cell       |
 * |  1   | octave-escalated        | blob > inline, fits one larger-octave cell |
 * |  2   | merkle-rooted hierarchy | blob spans many cells                      |
 *
 * ---
 *
 * ## Wire layout (little-endian, 16 bytes)
 *
 * ```
 * off  size  field          meaning
 *  0   1     rung           u8: 0=inline, 1=octave-escalated, 2=merkle-rooted-hierarchy
 *  1   1     octave_level   u8: 0..3 (base 1KiB / kilo 1MiB / mega 1GiB / giga 1TiB); 0 when rung=0
 *  2   2     child_count    u16 LE: number of child cells (meaningful when rung ≥ 1)
 *  4   8     total_bytes    u64 LE: logical blob size — THE payload-side source of truth
 * 12   4     reserved       u32 LE: 0 — alignment + future flags
 * ```
 *
 * Total = 16 bytes.
 *
 * ---
 *
 * ## Resolved design decisions (O-1 .. O-4 from the design doc)
 *
 * **O-1 (total_bytes / header total_size):** `total_bytes` (u64) in this
 * descriptor is the source of truth for the whole escalated object's logical
 * size.  The header's `total_size` (u32, offset 90) is reinterpreted as
 * "bytes in THIS cell" for escalated objects.  THIS PR does NOT change header
 * semantics — that is D-OCT-data-octave-bump (step 2).  For octave-0/1 blobs
 * (≤ 1 GiB) the u32 header field is sufficient; the u64 matters for octave 2+.
 *
 * **O-2 (descriptor offset):** For an **unrouted data cell** the descriptor
 * sits at **payload offset 0** (absolute cell offset 256).  For a **routed
 * cell** it sits immediately AFTER the typed-segments `[u16 N ‖ u16
 * payloadStartsAt]` header (i.e., at absolute cell offset 256 + 4 +
 * TYPED_SEGMENTS_HEADER_SIZE when the path-in-payload flag is set).  Use the
 * offset helpers `escalationDescriptorOffsetUnrouted()` and
 * `escalationDescriptorOffsetRouted(payloadStartsAt)`.
 *
 * **O-3 (merkle leaf size):** A merkle LEAF is a full 1024-byte child cell
 * (not the 768 payload bytes).  This is documented here for the future
 * D-OCT-merkle-hierarchy step — no merkle code ships in this PR.
 *
 * **O-4 (fragment-correlation key):** The routing header's `flow_label`
 * (offset 176, u64 LE) is the fragment-correlation key for reassembly — even
 * when `routing_mode == unrouted` (it is zero by default in that case and the
 * producer sets it when emitting an escalated blob).  There is NO duplicate
 * 8-byte key field inside this descriptor; `flow_label` at offset 176 is the
 * single canonical key.
 *
 * ---
 *
 * ## Octave sizes (×1024 binary — NOT ×1000)
 *
 * The ×1000 factor in `octave.zig::costSatsPerCell` is a pricing knob and is
 * independent of byte math.  Cell sizes are strict binary shifts:
 *   octave 0 = 1024 B   (base)
 *   octave 1 = 1 MiB    (kilo)
 *   octave 2 = 1 GiB    (mega)
 *   octave 3 = 1 TiB    (giga)
 * These match `octave.zig::cellSizeForOctave` / `minimumOctaveForSize`.
 *
 * ---
 *
 * ## Oracle ↔ mirror contract
 *
 * This TypeScript file is the ORACLE.  The Zig mirror lives at:
 *   core/cell-engine/src/escalation_descriptor.zig
 * Both sides MUST agree on the CANONICAL_BYTE_VECTOR defined below.
 */

// ── Descriptor size ────────────────────────────────────────────────────────────
/** Total size of the escalation descriptor in bytes. */
export const ESCALATION_DESCRIPTOR_SIZE = 16 as const;

// ── Field offsets within the 16-byte descriptor ────────────────────────────────
/**
 * Field offsets within the 16-byte escalation descriptor.
 * Offsets are relative to the START of the descriptor, not the start of the
 * cell.  Use the offset helpers below to get absolute cell offsets.
 */
export const EscalationDescriptorOffsets = {
  rung: 0,
  rungSize: 1,
  octaveLevel: 1,
  octaveLevelSize: 1,
  childCount: 2,
  childCountSize: 2,
  totalBytes: 4,
  totalBytesSize: 8,
  reserved: 12,
  reservedSize: 4,
} as const;

// ── Cell layout constants (mirrors core/protocol-types/src/constants.ts) ────────
/** Byte offset at which the payload region begins within a cell. */
export const PAYLOAD_OFFSET = 256 as const;

/**
 * Size of the typed-segments header `[u16 N ‖ u16 payloadStartsAt]` that
 * precedes the segment tuples when `FLAG_PATH_IN_PAYLOAD` is set (§13.2 of
 * the brief).
 */
export const TYPED_SEGMENTS_HEADER_SIZE = 4 as const;

// ── Rung enum ─────────────────────────────────────────────────────────────────
/**
 * Escalation rung — which tier of the inline → escalated → merkle ladder the
 * object is on.
 */
export const Rung = {
  /** Blob fits entirely in the cell's own inline payload region. */
  INLINE: 0,
  /**
   * Blob overflows inline but fits in a single larger-octave child cell.
   * `octave_level` indicates which octave class was selected.
   */
  OCTAVE_ESCALATED: 1,
  /**
   * Blob spans multiple cells; a merkle root is committed in the canonical
   * 32-byte slot (header `domainPayloadRoot` for data; the payload-resident
   * slot when `FLAG_PATH_MERKLE_OVERLOAD` is set for paths).
   */
  MERKLE_ROOTED_HIERARCHY: 2,
} as const;
export type Rung = (typeof Rung)[keyof typeof Rung];

// ── Octave level constants ────────────────────────────────────────────────────
/**
 * Octave level values — mirrors `octave.zig::Octave`.
 * Cell sizes are ×1024 binary (NOT ×1000): each level is 1024× the last.
 *   octave 0 = 1024 B (1 KiB)
 *   octave 1 = 1,048,576 B (1 MiB)
 *   octave 2 = 1,073,741,824 B (1 GiB)
 *   octave 3 = 1,099,511,627,776 B (1 TiB)
 */
export const OctaveLevel = {
  BASE: 0, // 1 KiB
  KILO: 1, // 1 MiB
  MEGA: 2, // 1 GiB
  GIGA: 3, // 1 TiB
} as const;
export type OctaveLevel = (typeof OctaveLevel)[keyof typeof OctaveLevel];

// ── Typed view of the descriptor ─────────────────────────────────────────────
/**
 * Parsed representation of the 16-byte escalation descriptor.
 * `totalBytes` is a `bigint` to faithfully represent u64 values that exceed
 * the safe integer range of `number` (> 2^53 - 1), which is needed for
 * octave-2/3 blobs (GiB..TiB scale).
 */
export interface EscalationDescriptor {
  /** Escalation rung: 0=inline, 1=octave-escalated, 2=merkle-rooted-hierarchy. */
  rung: Rung;
  /**
   * Octave level (0..3).  Meaningful when rung ≥ 1.  Should be 0 when
   * rung === 0 (inline).
   */
  octaveLevel: OctaveLevel;
  /**
   * Number of child cells.  Meaningful when rung ≥ 1.
   * For rung=1 this is typically 1 (the single escalated child cell).
   */
  childCount: number;
  /**
   * Logical blob size in bytes — the u64 source of truth for the whole
   * escalated object (resolves O-1).  Represented as `bigint` to handle
   * values beyond 2^53.
   */
  totalBytes: bigint;
  /** Must be 0 on the wire. Reserved for future use. */
  reserved: number;
}

// ── Offset helpers ────────────────────────────────────────────────────────────
/**
 * Absolute byte offset of the escalation descriptor within a cell for an
 * **unrouted data cell** (O-2, option A).
 *
 * The descriptor occupies bytes [256, 272) of the 1024-byte cell.
 */
export function escalationDescriptorOffsetUnrouted(): number {
  return PAYLOAD_OFFSET; // 256
}

/**
 * Absolute byte offset of the escalation descriptor within a cell for a
 * **routed cell** (O-2, option B).
 *
 * The descriptor sits immediately AFTER the typed-segments
 * `[u16 N ‖ u16 payloadStartsAt]` header, so its absolute offset is:
 *   PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE (i.e. 256 + 4 = 260)
 *
 * Note: `payloadStartsAt` from the typed-segments header tells the consumer
 * where *application payload* begins — the escalation descriptor occupies the
 * bytes immediately after the 4-byte typed-segments header and precedes the
 * segment tuples.  Callers that have already read `payloadStartsAt` can use
 * that as a cross-check: the escalation descriptor ends at
 * PAYLOAD_OFFSET + 4 + ESCALATION_DESCRIPTOR_SIZE (= 276).
 *
 * @param _payloadStartsAt - The `payloadStartsAt` field from the
 *   typed-segments header (u16 LE at PAYLOAD_OFFSET + 2).  Not used to
 *   compute the return value (the descriptor always starts at
 *   PAYLOAD_OFFSET + 4) but accepted for documentation clarity and future
 *   validation use.
 */
export function escalationDescriptorOffsetRouted(_payloadStartsAt?: number): number {
  return PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE; // 260
}

// ── Individual field accessors ─────────────────────────────────────────────────
/**
 * Read the `rung` field (u8) from a descriptor buffer.
 * `buf` must be at least `ESCALATION_DESCRIPTOR_SIZE` (16) bytes.
 * `offset` is the absolute byte offset of the descriptor start within `buf`.
 */
export function readRung(buf: Uint8Array, offset: number): Rung {
  return (buf[offset + EscalationDescriptorOffsets.rung] ?? 0) as Rung;
}

/**
 * Write the `rung` field (u8) into a descriptor buffer.
 */
export function writeRung(buf: Uint8Array, offset: number, rung: Rung): void {
  buf[offset + EscalationDescriptorOffsets.rung] = rung & 0xff;
}

/**
 * Read the `octave_level` field (u8) from a descriptor buffer.
 */
export function readOctaveLevel(buf: Uint8Array, offset: number): OctaveLevel {
  return (buf[offset + EscalationDescriptorOffsets.octaveLevel] ?? 0) as OctaveLevel;
}

/**
 * Write the `octave_level` field (u8) into a descriptor buffer.
 */
export function writeOctaveLevel(buf: Uint8Array, offset: number, level: OctaveLevel): void {
  buf[offset + EscalationDescriptorOffsets.octaveLevel] = level & 0xff;
}

/**
 * Read the `child_count` field (u16 LE) from a descriptor buffer.
 */
export function readChildCount(buf: Uint8Array, offset: number): number {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return dv.getUint16(offset + EscalationDescriptorOffsets.childCount, true);
}

/**
 * Write the `child_count` field (u16 LE) into a descriptor buffer.
 */
export function writeChildCount(buf: Uint8Array, offset: number, count: number): void {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  dv.setUint16(offset + EscalationDescriptorOffsets.childCount, count & 0xffff, true);
}

/**
 * Read the `total_bytes` field (u64 LE) from a descriptor buffer.
 * Returns a `bigint` to represent the full u64 range.
 */
export function readTotalBytes(buf: Uint8Array, offset: number): bigint {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return dv.getBigUint64(offset + EscalationDescriptorOffsets.totalBytes, true);
}

/**
 * Write the `total_bytes` field (u64 LE) into a descriptor buffer.
 */
export function writeTotalBytes(buf: Uint8Array, offset: number, bytes: bigint): void {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  dv.setBigUint64(offset + EscalationDescriptorOffsets.totalBytes, bytes, true);
}

// ── Composite read/write ───────────────────────────────────────────────────────
/**
 * Read the full escalation descriptor at `offset` within `buf`.
 * `buf` must have at least `offset + ESCALATION_DESCRIPTOR_SIZE` bytes.
 */
export function readDescriptor(buf: Uint8Array, offset: number): EscalationDescriptor {
  if (buf.length < offset + ESCALATION_DESCRIPTOR_SIZE) {
    throw new Error(
      `Buffer too small for escalation descriptor: ${buf.length} bytes at offset ${offset}, ` +
        `need ${offset + ESCALATION_DESCRIPTOR_SIZE}`,
    );
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return {
    rung: readRung(buf, offset),
    octaveLevel: readOctaveLevel(buf, offset),
    childCount: readChildCount(buf, offset),
    totalBytes: readTotalBytes(buf, offset),
    reserved: dv.getUint32(offset + EscalationDescriptorOffsets.reserved, true),
  };
}

/**
 * Write the full escalation descriptor at `offset` within `buf`.
 * `buf` must have at least `offset + ESCALATION_DESCRIPTOR_SIZE` bytes.
 * `reserved` is forced to 0 regardless of what `desc.reserved` contains.
 */
export function writeDescriptor(
  buf: Uint8Array,
  offset: number,
  desc: Omit<EscalationDescriptor, "reserved">,
): void {
  if (buf.length < offset + ESCALATION_DESCRIPTOR_SIZE) {
    throw new Error(
      `Buffer too small for escalation descriptor: ${buf.length} bytes at offset ${offset}, ` +
        `need ${offset + ESCALATION_DESCRIPTOR_SIZE}`,
    );
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  buf[offset + EscalationDescriptorOffsets.rung] = desc.rung & 0xff;
  buf[offset + EscalationDescriptorOffsets.octaveLevel] = desc.octaveLevel & 0xff;
  dv.setUint16(offset + EscalationDescriptorOffsets.childCount, desc.childCount & 0xffff, true);
  dv.setBigUint64(offset + EscalationDescriptorOffsets.totalBytes, desc.totalBytes, true);
  dv.setUint32(offset + EscalationDescriptorOffsets.reserved, 0, true); // always zero
}

// ── Canonical byte vector (oracle ↔ mirror contract) ──────────────────────────
/**
 * Hand-encoded canonical byte vector for cross-language conformance testing.
 *
 * Encodes the descriptor:
 *   rung          = 1     (OCTAVE_ESCALATED)
 *   octave_level  = 2     (MEGA = 1 GiB cells)
 *   child_count   = 7     (u16 LE → 0x07 0x00)
 *   total_bytes   = 0x00_0000_0A_BC_DE_F0_12_34  (u64 LE)
 *                 = decimal 46,614,352,962,612 bytes (~42 TiB, tests u64 range)
 *   reserved      = 0     (u32 LE → 0x00 0x00 0x00 0x00)
 *
 * Little-endian layout, 16 bytes:
 *
 *   off  byte   field
 *    0   0x01   rung = 1
 *    1   0x02   octave_level = 2
 *    2   0x07   child_count low byte
 *    3   0x00   child_count high byte
 *    4   0x34   total_bytes byte 0  (LSB)
 *    5   0x12   total_bytes byte 1
 *    6   0xF0   total_bytes byte 2
 *    7   0xDE   total_bytes byte 3
 *    8   0xBC   total_bytes byte 4
 *    9   0x0A   total_bytes byte 5
 *   10   0x00   total_bytes byte 6
 *   11   0x00   total_bytes byte 7  (MSB)
 *   12   0x00   reserved byte 0
 *   13   0x00   reserved byte 1
 *   14   0x00   reserved byte 2
 *   15   0x00   reserved byte 3
 *
 * The Zig mirror in `escalation_descriptor.zig` asserts the same vector byte-
 * for-byte in its `test "canonical byte vector"` block.
 */
export const CANONICAL_DESCRIPTOR_BYTES = new Uint8Array([
  0x01, // rung = 1 (OCTAVE_ESCALATED)
  0x02, // octave_level = 2 (MEGA)
  0x07, 0x00, // child_count = 7 (u16 LE)
  0x34, 0x12, 0xf0, 0xde, 0xbc, 0x0a, 0x00, 0x00, // total_bytes = 0x0000_0ABC_DEF0_1234 (u64 LE)
  0x00, 0x00, 0x00, 0x00, // reserved = 0
]);

/**
 * The `total_bytes` value encoded in `CANONICAL_DESCRIPTOR_BYTES` as a bigint,
 * for use in test assertions.
 */
export const CANONICAL_TOTAL_BYTES = BigInt("0x00000ABCDEF01234");

```
