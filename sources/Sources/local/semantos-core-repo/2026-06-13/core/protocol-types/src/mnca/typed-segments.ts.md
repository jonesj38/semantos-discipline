---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/typed-segments.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.900349+00:00
---

# core/protocol-types/src/mnca/typed-segments.ts

```ts
/**
 * Typed-segments payload codec + originator path-builder.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.2 (payload
 * layout) + §4.1 / §13.1 (originator builds the routing).
 *
 * When a cell is source-routed with the path carried inline, the first
 * portion of the 768-byte PAYLOAD region (cell offset 256+) holds the
 * typed segments list:
 *
 *   payload[0..1]            u16 LE  N — number of segments
 *   payload[2..3]            u16 LE  payloadStartsAt — offset (within the
 *                                    payload region) where real cell data
 *                                    begins
 *   payload[4 .. 4+N*48)     N × 48-byte tuples:
 *                                - 16 bytes: BCA of the hop
 *                                - 32 bytes: TYPE_HASH the cell should HAVE
 *                                            on arrival at this hop
 *   payload[payloadStartsAt..]        actual cell payload data
 *
 * Each segment is a *contract* (§13.1): "hop BCA_i accepts a cell of the
 * prior segment's type and emits a cell of TYPE_HASH_i." The originator
 * builds this from the relay advertisements it selected.
 *
 * This module operates on the 768-byte payload region as a standalone
 * buffer; `buildRoutedCell` ties it together with the header's routing
 * region (`cell-routing.ts`) to produce a complete 1024-byte routed cell.
 */

import { PAYLOAD_SIZE, HEADER_SIZE } from '../constants';
import {
  RoutingMode,
  RoutingFlag,
  writeRoutingRegion,
  setRoutingChecksum,
  type RoutingRegion,
} from '../cell-routing';

export const SEGMENT_BCA_SIZE = 16 as const;
export const SEGMENT_TYPE_HASH_SIZE = 32 as const;
export const SEGMENT_TUPLE_SIZE = SEGMENT_BCA_SIZE + SEGMENT_TYPE_HASH_SIZE; // 48
export const TYPED_SEGMENTS_HEADER_SIZE = 4 as const; // u16 N + u16 payloadStartsAt

/** Max segments that fit in the 768-byte payload leaving at least `dataReserve` bytes. */
export function maxSegments(dataReserve = 0): number {
  const usable = PAYLOAD_SIZE - TYPED_SEGMENTS_HEADER_SIZE - dataReserve;
  return Math.max(0, Math.floor(usable / SEGMENT_TUPLE_SIZE));
}

/** A single typed hop: (where, what-shape-on-arrival). */
export interface TypedSegment {
  /** 16-byte BCA of the hop. */
  bca: Uint8Array;
  /** 32-byte type-hash the cell must carry when it reaches this hop. */
  typeHash: Uint8Array;
}

/**
 * Encode typed segments + payload data into a 768-byte payload region.
 * `payloadData` is the real cell payload that rides after the segments;
 * it may be empty. Throws if the segments + data don't fit in 768 bytes.
 */
export function encodeTypedSegments(
  segments: TypedSegment[],
  payloadData: Uint8Array = new Uint8Array(0),
): Uint8Array {
  if (segments.length === 0) {
    throw new Error('encodeTypedSegments: at least one segment required');
  }
  if (segments.length > 0xffff) {
    throw new Error(`encodeTypedSegments: too many segments (${segments.length} > 65535)`);
  }
  for (let i = 0; i < segments.length; i++) {
    if (segments[i]!.bca.length !== SEGMENT_BCA_SIZE) {
      throw new Error(`encodeTypedSegments: segment[${i}].bca must be ${SEGMENT_BCA_SIZE} bytes`);
    }
    if (segments[i]!.typeHash.length !== SEGMENT_TYPE_HASH_SIZE) {
      throw new Error(
        `encodeTypedSegments: segment[${i}].typeHash must be ${SEGMENT_TYPE_HASH_SIZE} bytes`,
      );
    }
  }
  const N = segments.length;
  const segmentsBytes = TYPED_SEGMENTS_HEADER_SIZE + N * SEGMENT_TUPLE_SIZE;
  const payloadStartsAt = segmentsBytes;
  const total = payloadStartsAt + payloadData.length;
  if (total > PAYLOAD_SIZE) {
    throw new Error(
      `encodeTypedSegments: ${N} segments + ${payloadData.length} data bytes = ${total} exceeds payload (${PAYLOAD_SIZE})`,
    );
  }

  const payload = new Uint8Array(PAYLOAD_SIZE);
  const dv = new DataView(payload.buffer);
  dv.setUint16(0, N, true);
  dv.setUint16(2, payloadStartsAt, true);
  let off = TYPED_SEGMENTS_HEADER_SIZE;
  for (const seg of segments) {
    payload.set(seg.bca, off);
    off += SEGMENT_BCA_SIZE;
    payload.set(seg.typeHash, off);
    off += SEGMENT_TYPE_HASH_SIZE;
  }
  payload.set(payloadData, payloadStartsAt);
  return payload;
}

export interface DecodedTypedSegments {
  segments: TypedSegment[];
  payloadStartsAt: number;
  payloadData: Uint8Array;
}

/** Decode a 768-byte payload region back into typed segments + data. */
export function decodeTypedSegments(payload: Uint8Array): DecodedTypedSegments {
  if (payload.length < TYPED_SEGMENTS_HEADER_SIZE) {
    throw new Error(`decodeTypedSegments: payload too short (${payload.length})`);
  }
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const N = dv.getUint16(0, true);
  const payloadStartsAt = dv.getUint16(2, true);
  const segmentsEnd = TYPED_SEGMENTS_HEADER_SIZE + N * SEGMENT_TUPLE_SIZE;
  if (payloadStartsAt < segmentsEnd) {
    throw new Error(
      `decodeTypedSegments: payloadStartsAt (${payloadStartsAt}) overlaps ${N} segments (end ${segmentsEnd})`,
    );
  }
  if (payloadStartsAt > payload.length) {
    throw new Error(
      `decodeTypedSegments: payloadStartsAt (${payloadStartsAt}) exceeds payload (${payload.length})`,
    );
  }
  const segments: TypedSegment[] = [];
  let off = TYPED_SEGMENTS_HEADER_SIZE;
  for (let i = 0; i < N; i++) {
    const bca = payload.slice(off, off + SEGMENT_BCA_SIZE);
    off += SEGMENT_BCA_SIZE;
    const typeHash = payload.slice(off, off + SEGMENT_TYPE_HASH_SIZE);
    off += SEGMENT_TYPE_HASH_SIZE;
    segments.push({ bca, typeHash });
  }
  const payloadData = payload.slice(payloadStartsAt);
  return { segments, payloadStartsAt, payloadData };
}

export interface BuildRoutedCellInput {
  /** A 1024-byte cell; its header typeHash (offset 30) should already be set. */
  cell: Uint8Array;
  /** Ordered typed segments — segment[0] is the first hop. */
  segments: TypedSegment[];
  /** 16-byte BCA of the final destination. */
  finalDestBca: Uint8Array;
  /** Real payload data to ride after the inline segments. */
  payloadData?: Uint8Array;
  /** u64 flow label (ECMP / dashboard correlation). */
  flowLabel?: bigint;
  /** Initial hop-count budget (loop detection). Defaults to `segments.length + 2`. */
  hopCountBudget?: number;
  /** Priority byte (0..255). */
  priority?: number;
  /** Extra routing flags to OR in (USES_PUSHDROP_PAYMENT, PRIORITY, etc.). */
  extraFlags?: number;
}

/**
 * Originator-side builder: take a freshly-minted cell + a chosen path
 * (segments) and produce a complete source-routed cell. Writes the
 * inline typed segments into the payload (offset 256+), the routing
 * region into the header (offset 160..223), sets ROUTING_MODE =
 * SOURCE_ROUTED, the PATH_IN_PAYLOAD flag, NEXT_HOP_BCA = segment[0].bca,
 * SEGMENTS_LEFT = N, and the CRC-32. Mutates `cell` in place and returns
 * it.
 *
 * The HMAC framing signature (which covers the routing fields per §4.1
 * step 7) is added by the transport/framing layer — NOT here.
 */
export function buildRoutedCell(input: BuildRoutedCellInput): Uint8Array {
  const {
    cell,
    segments,
    finalDestBca,
    payloadData = new Uint8Array(0),
    flowLabel = 0n,
    priority = 0,
    extraFlags = 0,
  } = input;

  if (cell.length < HEADER_SIZE + PAYLOAD_SIZE) {
    throw new Error(`buildRoutedCell: cell too small (${cell.length}, need ${HEADER_SIZE + PAYLOAD_SIZE})`);
  }
  if (segments.length === 0) {
    throw new Error('buildRoutedCell: at least one segment required');
  }
  if (finalDestBca.length !== SEGMENT_BCA_SIZE) {
    throw new Error(`buildRoutedCell: finalDestBca must be ${SEGMENT_BCA_SIZE} bytes`);
  }

  // 1. Encode the typed segments + data into the payload region.
  const payload = encodeTypedSegments(segments, payloadData);
  cell.set(payload, HEADER_SIZE);

  // 2. Write the routing region into the header.
  const hopCountBudget = input.hopCountBudget ?? segments.length + 2;
  const region: RoutingRegion = {
    routingMode: RoutingMode.SOURCE_ROUTED,
    priority: priority & 0xff,
    routingVersion: 1,
    routingFlags: (RoutingFlag.PATH_IN_PAYLOAD | extraFlags) >>> 0,
    segmentsLeft: segments.length,
    hopCountBudget,
    flowLabel,
    nextHopBca: segments[0]!.bca,
    finalDestBca,
    routingChecksum: 0,
  };
  writeRoutingRegion(cell, region);

  // 3. Seal the routing region with its CRC-32.
  setRoutingChecksum(cell);
  return cell;
}

```
