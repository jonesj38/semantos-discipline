---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/hop-processing.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.899208+00:00
---

# core/protocol-types/src/mnca/hop-processing.ts

```ts
/**
 * Relay hop-processing — the consume-half of source routing.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §4.2 (each hop
 * processes) + §13.3 (how a hop processes a typed segment) + §11.4
 * (non-target receivers drop silently).
 *
 * `buildRoutedCell` (typed-segments.ts) is the originator's *build* half;
 * this module is the relay's *consume* half. Given a received routed cell
 * and this hop's own 16-byte BCA, it decides — purely — what the hop
 * should do:
 *
 *   - reject (typed reason: not-source-routed / checksum / not-my-hop /
 *     type-mismatch / budget-exhausted), or
 *   - recognise itself as the final destination (process the payload), or
 *   - forward: produce the next-hop cell (routing region advanced,
 *     CRC-32 re-sealed) + which segment's pushdrop UTXO to spend.
 *
 * It does NOT run the cell-engine transform or spend any UTXO — those are
 * the relay runtime's job. This module returns *intent*: the forwarded
 * cell carries the updated routing region but its typeHash is UNCHANGED
 * (the caller runs the transform, which sets typeHash to
 * `expectedOutputTypeHash`, before transmitting). Pure over byte buffers;
 * no transport, no chain.
 *
 * SEGMENTS_LEFT convention (matches buildRoutedCell): for N inline
 * segments, the originator sets SEGMENTS_LEFT = N and NEXT_HOP_BCA =
 * segments[0].bca. A hop arriving with SEGMENTS_LEFT = S is at segment
 * index `N - S` (first hop: S = N → index 0). After forwarding, S
 * decrements; when it reaches 0 the cell's NEXT_HOP_BCA points at
 * FINAL_DEST_BCA and the final destination sees (SEGMENTS_LEFT = 0,
 * NEXT_HOP_BCA = own BCA).
 */

import { HeaderOffsets } from '../constants';
import {
  RoutingMode,
  RoutingFlag,
  readRoutingRegion,
  writeRoutingRegion,
  setRoutingChecksum,
  verifyRoutingChecksum,
  type RoutingRegion,
} from '../cell-routing';
import { decodeTypedSegments, type TypedSegment } from './typed-segments';
import {
  decodePathMerklePayload,
  verifySegmentInclusion,
  type SegmentTuple,
} from './path-merkle';

export type HopRejectReason =
  | 'not-source-routed'
  | 'checksum'
  | 'not-my-hop'
  | 'type-mismatch'
  | 'budget-exhausted';

export type HopResult =
  | {
      ok: true;
      kind: 'forward';
      /** A fresh copy of the cell with routing region advanced + re-checksummed. */
      forwarded: Uint8Array;
      /** Index of the segment whose pushdrop UTXO this hop should spend (§13.3 step 11b). */
      spendSegmentIndex: number;
      /**
       * The type-hash the cell SHOULD carry after this hop's transform,
       * i.e. the next segment's committed type (or undefined when the next
       * stop is the final destination and no inline next-type exists).
       * The relay runtime sets the forwarded cell's typeHash to this.
       */
      expectedOutputTypeHash?: Uint8Array;
    }
  | {
      ok: true;
      kind: 'final-destination';
    }
  | {
      ok: false;
      reason: HopRejectReason;
    };

export interface ProcessHopOptions {
  /**
   * When false, skip the §13.3 type-match check even if PATH_IN_PAYLOAD is
   * set. Useful for transport-layer pre-filtering where the type isn't
   * validated yet. Defaults to true.
   */
  validateType?: boolean;
}

function readCellTypeHash(cell: Uint8Array): Uint8Array {
  return cell.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/**
 * Process a received routed cell at a hop owning `ownBca` (16 bytes).
 * Returns a discriminated result — see `HopResult`. Never throws for an
 * expected rejection; throws only for caller misuse (e.g. wrong-sized
 * ownBca or a too-small buffer).
 */
export function processHop(
  cell: Uint8Array,
  ownBca: Uint8Array,
  opts: ProcessHopOptions = {},
): HopResult {
  if (ownBca.length !== 16) {
    throw new Error(`processHop: ownBca must be 16 bytes (got ${ownBca.length})`);
  }
  const validateType = opts.validateType ?? true;

  const region = readRoutingRegion(cell);

  // (1) Must be source-routed.
  if (region.routingMode !== RoutingMode.SOURCE_ROUTED) {
    return { ok: false, reason: 'not-source-routed' };
  }

  // (2) Routing checksum must be intact (in-flight tamper detection, §4.2 step 3).
  if (!verifyRoutingChecksum(cell)) {
    return { ok: false, reason: 'checksum' };
  }

  // (3) NEXT_HOP_BCA must be us (§4.2 step 4; §11.4 non-targets drop silently).
  if (!bytesEqual(region.nextHopBca, ownBca)) {
    return { ok: false, reason: 'not-my-hop' };
  }

  // (4) Final destination: SEGMENTS_LEFT == 0 and we are NEXT_HOP (= FINAL_DEST).
  if (region.segmentsLeft === 0) {
    return { ok: true, kind: 'final-destination' };
  }

  const hasMerkleOverload = (region.routingFlags & RoutingFlag.PATH_MERKLE_OVERLOAD) !== 0;

  // ── PATH_MERKLE_OVERLOAD branch (D-OCT-path-merkle-unify) ──────────────────
  // When FLAG_PATH_MERKLE_OVERLOAD is set, the payload (cell offset 256) holds
  // a 32-byte path-merkle root + a per-hop proof for the current segment tuple.
  // The shared verifier (verifyInclusion from cell-merkle) handles the leaf-agnostic
  // inclusion check with the 48-byte segment tuple as the leaf.
  //
  // Note: PATH_MERKLE_OVERLOAD and PATH_IN_PAYLOAD are mutually exclusive; if
  // both were somehow set, PATH_MERKLE_OVERLOAD takes priority (checked first).
  if (hasMerkleOverload) {
    // Decode the path-merkle payload from the beginning of the payload region.
    let pmPayload;
    try {
      pmPayload = decodePathMerklePayload(cell.subarray(256));
    } catch {
      return { ok: false, reason: 'type-mismatch' };
    }

    // Reconstruct the current hop's segment tuple: [own_bca ‖ cell_type_hash].
    // The BCA in the tuple IS own_bca (we already verified NEXT_HOP_BCA = own_bca in step 3).
    const cellTypeHash = readCellTypeHash(cell);
    const seg: SegmentTuple = { bca: ownBca, typeHash: cellTypeHash };

    // (5a) Verify the segment tuple is included under the path-merkle root.
    const proof = {
      leafIndex: pmPayload.leafIndex,
      siblings: pmPayload.siblings,
    };
    if (!verifySegmentInclusion(seg, proof, pmPayload.pathMerkleRoot)) {
      return { ok: false, reason: 'type-mismatch' };
    }

    // (5b) Optional: validate that leaf_index is consistent with segments_left.
    // With N total hops and segments_left = N - leaf_index (first hop: leaf_index = 0,
    // segments_left = N), consistency check: leaf_index = totalHops - segmentsLeft.
    const expectedLeafIndex = pmPayload.totalHops - region.segmentsLeft;
    if (pmPayload.leafIndex !== expectedLeafIndex) {
      return { ok: false, reason: 'type-mismatch' };
    }

    // (6) Budget check.
    if (region.hopCountBudget === 0) {
      return { ok: false, reason: 'budget-exhausted' };
    }

    const currentIndex = pmPayload.leafIndex;
    const newSegmentsLeft = region.segmentsLeft - 1;

    // (7) Build forwarded cell.
    const forwarded = cell.slice();

    // Next hop's BCA: with merkle overload the cell doesn't carry the next hop's
    // tuple inline. Point at FINAL_DEST as a best-effort; the relay runtime
    // (which knows the full route from its own state) overrides NEXT_HOP_BCA.
    // When this is the last forwarding hop (newSegmentsLeft == 0), FINAL_DEST is correct.
    const nextHopBca = region.finalDestBca;

    // The next hop's type-hash is NOT in this cell under the overload form.
    // The relay runtime advances the cell's type by running the transform.
    const expectedOutputTypeHash: Uint8Array | undefined = undefined;

    const updated: RoutingRegion = {
      ...region,
      segmentsLeft: newSegmentsLeft,
      hopCountBudget: region.hopCountBudget - 1,
      nextHopBca,
    };
    writeRoutingRegion(forwarded, updated);
    setRoutingChecksum(forwarded);

    // Note: the path-merkle root + proof bytes at payload offset 256+ are NOT
    // covered by the routing CRC (CRC covers only 160..216). The overload payload
    // is unchanged in the forwarded cell — the next relay will carry a different
    // proof (prepared by the originator), but that requires the originator to
    // pre-load the correct proof for each hop into the cell before forwarding.
    // In the multicast-and-filter model, the originator or a trusted re-encoder
    // updates the per-hop proof before re-broadcast.

    return {
      ok: true,
      kind: 'forward',
      forwarded,
      spendSegmentIndex: currentIndex,
      expectedOutputTypeHash,
    };
  }

  // ── PATH_IN_PAYLOAD branch (original inline segments — UNCHANGED) ────────────

  // We're a forwarding hop. Decode inline segments if present.
  let segments: TypedSegment[] | null = null;
  if ((region.routingFlags & RoutingFlag.PATH_IN_PAYLOAD) !== 0) {
    const decoded = decodeTypedSegments(cell.subarray(256));
    segments = decoded.segments;
  }

  const N = segments ? segments.length : region.segmentsLeft;
  const currentIndex = N - region.segmentsLeft; // first hop: S = N → 0

  // (5) Type check (§13.3 step 8b): the cell must carry the type committed
  //     for this hop's segment.
  if (validateType && segments) {
    const seg = segments[currentIndex];
    if (!seg) {
      // SEGMENTS_LEFT inconsistent with the inline segment count.
      return { ok: false, reason: 'type-mismatch' };
    }
    const cellType = readCellTypeHash(cell);
    if (!bytesEqual(cellType, seg.typeHash)) {
      return { ok: false, reason: 'type-mismatch' };
    }
  }

  // (6) Budget / loop detection (§4.2 step 9). Each hop consumes one unit.
  if (region.hopCountBudget === 0) {
    return { ok: false, reason: 'budget-exhausted' };
  }

  // (7) Build the forwarded cell on a copy.
  const forwarded = cell.slice();
  const newSegmentsLeft = region.segmentsLeft - 1;

  // Next hop's BCA: the next inline segment, or FINAL_DEST when this was
  // the last forwarding hop.
  let nextHopBca: Uint8Array;
  let expectedOutputTypeHash: Uint8Array | undefined;
  if (newSegmentsLeft === 0) {
    nextHopBca = region.finalDestBca;
    expectedOutputTypeHash = undefined; // final dest has no inline next-type
  } else if (segments) {
    const nextSeg = segments[currentIndex + 1]!;
    nextHopBca = nextSeg.bca;
    expectedOutputTypeHash = nextSeg.typeHash;
  } else {
    // No inline segments (path-by-merkle or bare): we can't know the next
    // BCA from the cell alone. Point at FINAL_DEST as a best-effort; the
    // relay runtime overrides from its own segment knowledge.
    nextHopBca = region.finalDestBca;
  }

  const updated: RoutingRegion = {
    ...region,
    segmentsLeft: newSegmentsLeft,
    hopCountBudget: region.hopCountBudget - 1,
    nextHopBca,
  };
  writeRoutingRegion(forwarded, updated);
  setRoutingChecksum(forwarded);

  return {
    ok: true,
    kind: 'forward',
    forwarded,
    spendSegmentIndex: currentIndex,
    expectedOutputTypeHash,
  };
}

```
