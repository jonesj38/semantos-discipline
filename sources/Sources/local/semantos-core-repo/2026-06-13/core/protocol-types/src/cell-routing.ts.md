---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-routing.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.848511+00:00
---

# core/protocol-types/src/cell-routing.ts

```ts
/**
 * Cell-routing region — typed accessors over the cell header's reserved
 * bytes. Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §2.1–§2.4.
 *
 * The 256-byte cell header has two unnamed reserved regions left by
 * earlier roadmap cuts:
 *
 *   - bytes 94..95   (2 bytes) — former commerce-phase / commerce-dim
 *   - bytes 160..223 (64 bytes) — former on-chain binding region
 *
 * This module names them as the **routing region** without changing the
 * canonical `CellHeader` interface. Accessors read/write directly on a
 * 256+ byte buffer so the wire format stays bit-identical for cells that
 * don't use routing — routing is opt-in via the `ROUTING_MODE` byte at
 * offset 94 (sentinel 0 = unrouted).
 *
 * Layout (cell-routing v1, ROUTING_VERSION = 1):
 *
 *   Offset   Size  Field
 *   ------   ----  -----
 *   94       1     ROUTING_MODE        u8
 *   95       1     PRIORITY            u8 (DSCP-like traffic class)
 *   160      4     ROUTING_VERSION     u32 LE
 *   164      4     ROUTING_FLAGS       u32 LE (bitfield, see below)
 *   168      4     SEGMENTS_LEFT       u32 LE
 *   172      4     HOP_COUNT_BUDGET    u32 LE
 *   176      8     FLOW_LABEL          u64 LE
 *   184      16    NEXT_HOP_BCA        16 bytes (IPv6-shaped BCA)
 *   200      16    FINAL_DEST_BCA      16 bytes (IPv6-shaped BCA)
 *   216      4     ROUTING_CHECKSUM    u32 LE (CRC-32 over bytes 160..215)
 *   220      4     RESERVED            zero
 *
 * The 64-byte routing region (offset 160..223) ends exactly where the
 * `domainPayloadRoot` field begins (offset 224), so the wire format is
 * unchanged for cells that have a domain payload root.
 */

export const RoutingRegionOffsets = {
  // 2-byte gap at offset 94-95 — fast classification.
  routingMode: 94,
  routingModeSize: 1,
  priority: 95,
  prioritySize: 1,

  // 64-byte region at offset 160-223 — source-routing payload.
  routingVersion: 160,
  routingVersionSize: 4,
  routingFlags: 164,
  routingFlagsSize: 4,
  segmentsLeft: 168,
  segmentsLeftSize: 4,
  hopCountBudget: 172,
  hopCountBudgetSize: 4,
  flowLabel: 176,
  flowLabelSize: 8,
  nextHopBca: 184,
  nextHopBcaSize: 16,
  finalDestBca: 200,
  finalDestBcaSize: 16,
  routingChecksum: 216,
  routingChecksumSize: 4,
  routingReserved: 220,
  routingReservedSize: 4,
} as const;

/** Routing region spans bytes 160..223 (inclusive..exclusive: 160..224). */
export const ROUTING_REGION_START = 160 as const;
export const ROUTING_REGION_END = 224 as const;
export const ROUTING_REGION_SIZE = 64 as const;

/** ROUTING_CHECKSUM covers bytes [160..216). */
export const ROUTING_CHECKSUM_COVERAGE_START = 160 as const;
export const ROUTING_CHECKSUM_COVERAGE_END = 216 as const;

/** Current routing-version value emitted by writers in this module. */
export const ROUTING_VERSION_V1 = 1 as const;

/**
 * ROUTING_MODE — single byte at offset 94. The dispatcher fast-classifies
 * cells using this without parsing the 64-byte region.
 */
export const RoutingMode = {
  UNROUTED: 0,
  SOURCE_ROUTED: 1,
  ANYCAST: 2,
  MULTICAST_PRUNED: 3,
} as const;
export type RoutingMode = (typeof RoutingMode)[keyof typeof RoutingMode];

/**
 * ROUTING_FLAGS bit positions (u32 LE at offset 164).
 *
 * Bits 0..4 are defined; bits 5..31 are reserved for future use and
 * MUST be zero on the wire until a flag is allocated for them.
 */
export const RoutingFlag = {
  /** Bit 0: priority-class cell (originator-marked, distinct from the DSCP byte at 95). */
  PRIORITY: 1 << 0,
  /** Bit 1: hop SHOULD anchor on arrival (mints a BSV pushdrop UTXO). */
  ANCHOR_ON_ARRIVAL: 1 << 1,
  /** Bit 2: cell is part of a merkle-rolled batch (anchored as a root, not individually). */
  BATCHABLE: 1 << 2,
  /** Bit 3: cell uses pre-funded pushdrop UTXOs per hop (§4 of the brief). */
  USES_PUSHDROP_PAYMENT: 1 << 3,
  /** Bit 4: DOMAIN_PAYLOAD_ROOT is overloaded as the path-merkle root (§2.3). */
  PATH_MERKLE_OVERLOAD: 1 << 4,
  /**
   * Bit 5: typed segments are inline in the payload (§13.2 layout —
   * u16 N, u16 payload_starts_at, N×48-byte (BCA, TYPE_HASH) tuples).
   *
   * NOTE (spec wrinkle for Todd): the brief reuses "bit 4" for BOTH the
   * §2.3 path-merkle-overload AND the §13.2 path-in-payload. Those are
   * independent mechanisms (one commits the path as a merkle root in the
   * header; the other carries the segments inline in the payload) and a
   * long path could plausibly use both. So this codec splits them:
   * bit 4 = merkle-overload, bit 5 = path-in-payload. If you'd rather
   * collapse them back to one flag, say so and I'll fold bit 5 out.
   */
  PATH_IN_PAYLOAD: 1 << 5,
} as const;
export type RoutingFlagBit = (typeof RoutingFlag)[keyof typeof RoutingFlag];

/**
 * Typed view of the routing region. All BCAs are 16 raw bytes (IPv6-shaped
 * per §2.4 of the brief). Pass `Uint8Array` everywhere — no parsing of
 * the 64-byte region into structured fields beyond what's already typed.
 */
export interface RoutingRegion {
  routingMode: RoutingMode;
  priority: number; // u8, 0..255
  routingVersion: number; // u32
  routingFlags: number; // u32 bitfield (use RoutingFlag bits)
  segmentsLeft: number; // u32
  hopCountBudget: number; // u32
  flowLabel: bigint; // u64
  nextHopBca: Uint8Array; // 16 bytes
  finalDestBca: Uint8Array; // 16 bytes
  routingChecksum: number; // u32 (CRC-32 over bytes 160..215)
}

/**
 * Read the routing region out of a 256+ byte cell buffer. Does not
 * validate the checksum — call `verifyRoutingChecksum` separately if
 * the cell is in-flight and could have been tampered with.
 */
export function readRoutingRegion(buf: Uint8Array): RoutingRegion {
  if (buf.length < ROUTING_REGION_END) {
    throw new Error(
      `Buffer too small for routing region: ${buf.length} bytes, need ${ROUTING_REGION_END}`,
    );
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return {
    routingMode: buf[RoutingRegionOffsets.routingMode] as RoutingMode,
    priority: buf[RoutingRegionOffsets.priority]!,
    routingVersion: dv.getUint32(RoutingRegionOffsets.routingVersion, true),
    routingFlags: dv.getUint32(RoutingRegionOffsets.routingFlags, true),
    segmentsLeft: dv.getUint32(RoutingRegionOffsets.segmentsLeft, true),
    hopCountBudget: dv.getUint32(RoutingRegionOffsets.hopCountBudget, true),
    flowLabel: dv.getBigUint64(RoutingRegionOffsets.flowLabel, true),
    nextHopBca: buf.slice(
      RoutingRegionOffsets.nextHopBca,
      RoutingRegionOffsets.nextHopBca + RoutingRegionOffsets.nextHopBcaSize,
    ),
    finalDestBca: buf.slice(
      RoutingRegionOffsets.finalDestBca,
      RoutingRegionOffsets.finalDestBca + RoutingRegionOffsets.finalDestBcaSize,
    ),
    routingChecksum: dv.getUint32(RoutingRegionOffsets.routingChecksum, true),
  };
}

/**
 * Write the routing region into a 256+ byte cell buffer in place. Does
 * NOT compute the checksum — caller writes the checksum value or calls
 * `setRoutingChecksum` after writing all other fields.
 *
 * `nextHopBca` and `finalDestBca` MUST be exactly 16 bytes each.
 */
export function writeRoutingRegion(buf: Uint8Array, region: RoutingRegion): void {
  if (buf.length < ROUTING_REGION_END) {
    throw new Error(
      `Buffer too small for routing region: ${buf.length} bytes, need ${ROUTING_REGION_END}`,
    );
  }
  if (region.nextHopBca.length !== 16) {
    throw new Error(`nextHopBca must be 16 bytes, got ${region.nextHopBca.length}`);
  }
  if (region.finalDestBca.length !== 16) {
    throw new Error(`finalDestBca must be 16 bytes, got ${region.finalDestBca.length}`);
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  buf[RoutingRegionOffsets.routingMode] = region.routingMode & 0xff;
  buf[RoutingRegionOffsets.priority] = region.priority & 0xff;
  dv.setUint32(RoutingRegionOffsets.routingVersion, region.routingVersion >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.routingFlags, region.routingFlags >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.segmentsLeft, region.segmentsLeft >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.hopCountBudget, region.hopCountBudget >>> 0, true);
  dv.setBigUint64(RoutingRegionOffsets.flowLabel, region.flowLabel, true);
  buf.set(region.nextHopBca, RoutingRegionOffsets.nextHopBca);
  buf.set(region.finalDestBca, RoutingRegionOffsets.finalDestBca);
  dv.setUint32(RoutingRegionOffsets.routingChecksum, region.routingChecksum >>> 0, true);
  // Reserved bytes stay as-is (zero by construction for freshly-allocated buffers).
}

/**
 * CRC-32 over an arbitrary byte range — the classic IEEE 802.3 polynomial
 * 0xEDB88320 (reflected), the same one used by zlib, PNG, and HDLC.
 *
 * Table-driven; lazily initialised. The routing checksum is a wire-integrity
 * detector, not a security primitive — the originator's HMAC-SHA256 (added
 * by the framing layer) is the authoritative tamper detector. CRC-32 is
 * here so a hop can reject a cell with an in-flight bit-flip in the
 * routing region without having to recompute the full HMAC.
 */
let crc32Table: Uint32Array | null = null;
function crc32TableInit(): Uint32Array {
  if (crc32Table) return crc32Table;
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    t[i] = c >>> 0;
  }
  crc32Table = t;
  return t;
}

export function crc32(bytes: Uint8Array): number {
  const t = crc32TableInit();
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    c = t[(c ^ bytes[i]!) & 0xff]! ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

/**
 * Compute the CRC-32 of bytes [160..216) — the routing-checksum-coverage
 * region. This excludes the checksum field itself (bytes 216..220) and
 * the reserved trailer (bytes 220..224).
 */
export function computeRoutingChecksum(buf: Uint8Array): number {
  return crc32(buf.subarray(ROUTING_CHECKSUM_COVERAGE_START, ROUTING_CHECKSUM_COVERAGE_END));
}

/**
 * Write the CRC-32 of bytes [160..216) into the routing-checksum field
 * (bytes 216..220). Returns the computed checksum value.
 */
export function setRoutingChecksum(buf: Uint8Array): number {
  const c = computeRoutingChecksum(buf);
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  dv.setUint32(RoutingRegionOffsets.routingChecksum, c >>> 0, true);
  return c;
}

/**
 * Verify the CRC-32 in the routing-checksum field matches a recompute
 * over bytes [160..216). Returns `true` when intact, `false` otherwise.
 */
export function verifyRoutingChecksum(buf: Uint8Array): boolean {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const stored = dv.getUint32(RoutingRegionOffsets.routingChecksum, true);
  const computed = computeRoutingChecksum(buf);
  return stored === computed;
}

/** True when the cell is marked as routed (ROUTING_MODE != 0). */
export function isRouted(buf: Uint8Array): boolean {
  return buf[RoutingRegionOffsets.routingMode] !== 0;
}

/** Read just the ROUTING_MODE byte — for fast dispatcher classification. */
export function readRoutingMode(buf: Uint8Array): RoutingMode {
  return (buf[RoutingRegionOffsets.routingMode] ?? 0) as RoutingMode;
}

/** Read just the PRIORITY byte. */
export function readPriority(buf: Uint8Array): number {
  return buf[RoutingRegionOffsets.priority] ?? 0;
}

/** Test a single routing flag bit. */
export function hasRoutingFlag(region: RoutingRegion, flag: RoutingFlagBit): boolean {
  return (region.routingFlags & flag) !== 0;
}

```
