---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/path-merkle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.858628+00:00
---

# core/protocol-types/__tests__/path-merkle.test.ts

```ts
/**
 * D-OCT-path-merkle-unify — path-merkle overload tests (TS oracle).
 *
 * Tests the routing path-merkle overload: FLAG_PATH_MERKLE_OVERLOAD causes
 * processHop to verify the current hop's 48-byte segment tuple via a shared
 * merkle inclusion-proof verifier.
 *
 * Covers:
 *   (a) verifySegmentInclusion — the routing half of the unified verifier.
 *   (b) Payload encode/decode round-trip.
 *   (c) Full deep-route walk: build path-merkle root, walk all hops, reach
 *       final destination.
 *   (d) Rejection: tampered segment / wrong root / wrong proof.
 *   (e) Non-mutation of input cell on forward.
 *   (f) Canonical shared vector (oracle↔Zig agreement).
 *   (g) Backward-compat: all original processHop (inline FLAG_PATH_IN_PAYLOAD)
 *       tests are unaffected. Run the existing hop-processing.test.ts for those.
 *
 * The shared verifier unification:
 *   - Data side: verifyCellInclusion(cell1024B, proof, domainPayloadRoot)
 *                → calls verifyInclusion(cell1024B, ...)
 *   - Routing side: verifySegmentInclusion(seg48B, proof, pathMerkleRoot)
 *                   → calls verifyInclusion(seg48B, ...)
 *   Both go through the same verifyInclusion in @semantos/cell-ops.
 */

import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, HEADER_SIZE, HeaderOffsets } from '../src/constants';
import {
  computePathMerkleRoot,
  generateSegmentInclusionProof,
  verifySegmentInclusion,
  encodeSegmentTuple,
  decodeSegmentTuple,
  encodePathMerklePayload,
  decodePathMerklePayload,
  buildPathMerklePayloads,
  writePathMerklePayload,
  readPathMerklePayload,
  SEGMENT_TUPLE_SIZE,
  PATH_MERKLE_ROOT_SIZE,
  PATH_MERKLE_PAYLOAD_MIN_SIZE,
  type SegmentTuple,
  type PathMerklePayload,
} from '../src/mnca/path-merkle';
import { processHop } from '../src/mnca/hop-processing';
import {
  RoutingMode,
  RoutingFlag,
  RoutingRegionOffsets,
  readRoutingRegion,
  writeRoutingRegion,
  setRoutingChecksum,
  verifyRoutingChecksum,
} from '../src/cell-routing';
import { verifyInclusion, cellMerkleSha256 } from '@semantos/cell-ops/packer';

// ── Helpers ────────────────────────────────────────────────────────────────────

function mkBca(seed: number): Uint8Array {
  const b = new Uint8Array(16);
  for (let i = 0; i < 16; i++) b[i] = (i + seed * 31) & 0xff;
  return b;
}

function mkTypeHash(seed: number): Uint8Array {
  const h = new Uint8Array(32);
  for (let i = 0; i < 32; i++) h[i] = (i * 5 + seed) & 0xff;
  return h;
}

function mkSegment(bcaSeed: number, typeSeed: number): SegmentTuple {
  return { bca: mkBca(bcaSeed), typeHash: mkTypeHash(typeSeed) };
}

function setCellType(cell: Uint8Array, h: Uint8Array): void {
  cell.set(h, HeaderOffsets.typeHash);
}

/**
 * Build a routed cell with FLAG_PATH_MERKLE_OVERLOAD set.
 *
 * The originator pre-loads the per-hop proof for hopIndex into the payload.
 * In the multicast-and-filter model, the originator prepares a separate cell
 * variant for each hop (each with the correct proof for that hop's position).
 */
function buildMerkleRoutedCell(
  segments: SegmentTuple[],
  finalDest: Uint8Array,
  hopIndex: number,
): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);

  // The cell carries the type for the current hop's segment.
  setCellType(cell, segments[hopIndex]!.typeHash);

  // Build path-merkle payloads for all hops; select this hop's.
  const allPayloads = buildPathMerklePayloads(segments);
  const hopPayload = allPayloads[hopIndex]!;

  // Write path-merkle payload into the cell payload region (cell offset 256).
  writePathMerklePayload(cell, hopPayload);

  // Write routing region.
  const routingRegion = {
    routingMode: RoutingMode.SOURCE_ROUTED,
    priority: 0,
    routingVersion: 1,
    routingFlags: RoutingFlag.PATH_MERKLE_OVERLOAD,
    segmentsLeft: segments.length - hopIndex,
    hopCountBudget: segments.length + 2,
    flowLabel: 0n,
    nextHopBca: segments[hopIndex]!.bca,
    finalDestBca: finalDest,
    routingChecksum: 0,
  };
  writeRoutingRegion(cell, routingRegion);
  setRoutingChecksum(cell);

  return cell;
}

// ── (a) verifySegmentInclusion — the routing half of the unified verifier ──────

describe('verifySegmentInclusion — routing half of unified verifier', () => {
  test('verifies for the first hop in a 3-hop route', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);
    expect(verifySegmentInclusion(segments[0]!, proof, root)).toBe(true);
  });

  test('verifies for all hops in a 4-hop route', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30), mkSegment(4, 40)];
    const root = computePathMerkleRoot(segments);
    for (let i = 0; i < segments.length; i++) {
      const proof = generateSegmentInclusionProof(segments, i);
      expect(verifySegmentInclusion(segments[i]!, proof, root)).toBe(true);
    }
  });

  test('verifies for all hops in a 5-hop route (odd count, duplication)', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30), mkSegment(4, 40), mkSegment(5, 50)];
    const root = computePathMerkleRoot(segments);
    for (let i = 0; i < segments.length; i++) {
      const proof = generateSegmentInclusionProof(segments, i);
      expect(verifySegmentInclusion(segments[i]!, proof, root)).toBe(true);
    }
  });

  test('proof for hop 0 does NOT verify for hop 1', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);
    expect(verifySegmentInclusion(segments[1]!, proof, root)).toBe(false);
  });

  test('tampered BCA in segment → fails', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);

    const tampered: SegmentTuple = {
      bca: new Uint8Array(segments[0]!.bca).map((b, i) => (i === 3 ? b ^ 0xff : b)),
      typeHash: segments[0]!.typeHash,
    };
    expect(verifySegmentInclusion(tampered, proof, root)).toBe(false);
  });

  test('tampered type-hash in segment → fails', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);

    const tampered: SegmentTuple = {
      bca: segments[0]!.bca,
      typeHash: new Uint8Array(segments[0]!.typeHash).map((b, i) => (i === 5 ? b ^ 0xff : b)),
    };
    expect(verifySegmentInclusion(tampered, proof, root)).toBe(false);
  });

  test('tampered sibling hash → fails', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);

    const tamperedProof = {
      leafIndex: proof.leafIndex,
      siblings: proof.siblings.map(s => ({
        ...s,
        hash: new Uint8Array(s.hash).map((b, i) => (i === 0 ? b ^ 0xff : b)),
      })),
    };
    expect(verifySegmentInclusion(segments[0]!, tamperedProof, root)).toBe(false);
  });

  test('wrong root → fails', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);

    const wrongRoot = new Uint8Array(root);
    wrongRoot[0] ^= 0xff;
    expect(verifySegmentInclusion(segments[0]!, proof, wrongRoot)).toBe(false);
  });

  test('the 48-byte tuple leaf is sha256(tuple) — same single-SHA-256 as data side', () => {
    // Confirm the hash is sha256(48-byte tuple), not double-SHA-256.
    const seg = mkSegment(5, 50);
    const tuple = encodeSegmentTuple(seg);
    expect(tuple.length).toBe(48);
    const leafHash = cellMerkleSha256(tuple);
    expect(leafHash.length).toBe(32);

    // verifyInclusion(tuple, proof, root) = same as verifyInclusion(cell1024B, ...) — same primitive.
    const root = computePathMerkleRoot([seg]);
    const proof = generateSegmentInclusionProof([seg], 0);
    // The shared verifyInclusion from @semantos/cell-ops accepts arbitrary leaf bytes.
    expect(verifyInclusion(tuple, proof, root)).toBe(true);
  });
});

// ── (b) Payload encode/decode round-trip ──────────────────────────────────────

describe('PathMerklePayload encode/decode round-trip', () => {
  test('single hop (zero siblings) round-trips', () => {
    const root = new Uint8Array(32).fill(0xab);
    const payload: PathMerklePayload = {
      pathMerkleRoot: root,
      totalHops: 1,
      leafIndex: 0,
      siblings: [],
    };
    const encoded = encodePathMerklePayload(payload);
    expect(encoded.length).toBe(PATH_MERKLE_PAYLOAD_MIN_SIZE); // 41
    const decoded = decodePathMerklePayload(encoded);
    expect(Array.from(decoded.pathMerkleRoot)).toEqual(Array.from(root));
    expect(decoded.totalHops).toBe(1);
    expect(decoded.leafIndex).toBe(0);
    expect(decoded.siblings.length).toBe(0);
  });

  test('3-hop route — all hop payloads encode/decode correctly', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const payloads = buildPathMerklePayloads(segments);
    expect(payloads.length).toBe(3);

    for (let i = 0; i < 3; i++) {
      const encoded = encodePathMerklePayload(payloads[i]!);
      const decoded = decodePathMerklePayload(encoded);
      expect(Array.from(decoded.pathMerkleRoot)).toEqual(Array.from(payloads[i]!.pathMerkleRoot));
      expect(decoded.totalHops).toBe(3);
      expect(decoded.leafIndex).toBe(i);
      expect(decoded.siblings.length).toBe(payloads[i]!.siblings.length);
      for (let j = 0; j < decoded.siblings.length; j++) {
        expect(Array.from(decoded.siblings[j]!.hash)).toEqual(Array.from(payloads[i]!.siblings[j]!.hash));
        expect(decoded.siblings[j]!.position).toBe(payloads[i]!.siblings[j]!.position);
      }
    }
  });

  test('sibling position bytes: 0x00 = left, 0x01 = right', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const payloads = buildPathMerklePayloads(segments);
    for (const payload of payloads) {
      const encoded = encodePathMerklePayload(payload);
      // Check raw bytes
      let off = 41;
      for (const sib of payload.siblings) {
        const posByte = encoded[off + 32]!;
        expect(posByte).toBe(sib.position === 'left' ? 0x00 : 0x01);
        off += 33;
      }
    }
  });

  test('writePathMerklePayload / readPathMerklePayload round-trip in cell buffer', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const payloads = buildPathMerklePayloads(segments);
    const cell = new Uint8Array(CELL_SIZE);

    writePathMerklePayload(cell, payloads[0]!);
    const read = readPathMerklePayload(cell);

    expect(Array.from(read.pathMerkleRoot)).toEqual(Array.from(payloads[0]!.pathMerkleRoot));
    expect(read.totalHops).toBe(2);
    expect(read.leafIndex).toBe(0);
  });

  test('path-merkle payload starts at cell offset 256 (payload region start)', () => {
    const root = new Uint8Array(32).fill(0xcc);
    const payload: PathMerklePayload = {
      pathMerkleRoot: root,
      totalHops: 2,
      leafIndex: 0,
      siblings: [],
    };
    const cell = new Uint8Array(CELL_SIZE);
    writePathMerklePayload(cell, payload);

    // Root at cell offsets 256..287
    expect(Array.from(cell.slice(256, 288))).toEqual(Array.from(root));
    // total_hops at cell offsets 288..291 (u32 LE: 2)
    expect(cell[288]).toBe(2);
    expect(cell[289]).toBe(0);
    expect(cell[290]).toBe(0);
    expect(cell[291]).toBe(0);
  });
});

// ── (c) Full deep-route walk with merkle overload ─────────────────────────────

describe('processHop with FLAG_PATH_MERKLE_OVERLOAD — full walk', () => {
  test('3-hop merkle route: hop0 → hop1 → hop2 → final destination', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const finalDest = mkBca(99);

    // Each hop gets its own cell with the correct per-hop proof.
    const cell0 = buildMerkleRoutedCell(segments, finalDest, 0);
    const cell1 = buildMerkleRoutedCell(segments, finalDest, 1);
    const cell2 = buildMerkleRoutedCell(segments, finalDest, 2);

    // Hop 0
    let res = processHop(cell0, segments[0]!.bca);
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop0 expected forward');
    expect(res.spendSegmentIndex).toBe(0);
    expect(readRoutingRegion(res.forwarded).segmentsLeft).toBe(2);
    expect(verifyRoutingChecksum(res.forwarded)).toBe(true);

    // Hop 1 — use the pre-loaded cell1 (with hop1's proof already in it).
    // In a real deployment the originator delivers the correct proof per hop;
    // here we simulate by using the pre-built cell1.
    res = processHop(cell1, segments[1]!.bca);
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop1 expected forward');
    expect(res.spendSegmentIndex).toBe(1);
    expect(readRoutingRegion(res.forwarded).segmentsLeft).toBe(1);
    expect(verifyRoutingChecksum(res.forwarded)).toBe(true);

    // Hop 2 (last forwarding hop)
    res = processHop(cell2, segments[2]!.bca);
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop2 expected forward');
    expect(res.spendSegmentIndex).toBe(2);
    const afterHop2 = readRoutingRegion(res.forwarded);
    expect(afterHop2.segmentsLeft).toBe(0);
    // Points at FINAL_DEST (no inline next-hop under merkle overload)
    expect(Array.from(afterHop2.nextHopBca)).toEqual(Array.from(finalDest));
    expect(verifyRoutingChecksum(res.forwarded)).toBe(true);

    // Final destination
    const finalCell = res.forwarded;
    const finalRes = processHop(finalCell, finalDest);
    expect(finalRes.ok).toBe(true);
    if (!finalRes.ok) throw new Error('unreachable');
    expect(finalRes.kind).toBe('final-destination');
  });

  test('single-hop merkle route reaches final destination immediately', () => {
    const segments = [mkSegment(1, 10)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
    expect(res.spendSegmentIndex).toBe(0);

    const afterHop0 = readRoutingRegion(res.forwarded);
    expect(afterHop0.segmentsLeft).toBe(0);
    expect(Array.from(afterHop0.nextHopBca)).toEqual(Array.from(finalDest));

    const finalRes = processHop(res.forwarded, finalDest);
    expect(finalRes.ok).toBe(true);
    if (!finalRes.ok) throw new Error('unreachable');
    expect(finalRes.kind).toBe('final-destination');
  });

  test('budget decrements on each hop', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const finalDest = mkBca(99);
    const cells = [0, 1, 2].map(i => buildMerkleRoutedCell(segments, finalDest, i));

    for (let i = 0; i < 3; i++) {
      const res = processHop(cells[i]!, segments[i]!.bca);
      expect(res.ok).toBe(true);
      if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
      const region = readRoutingRegion(res.forwarded);
      expect(region.hopCountBudget).toBe(segments.length + 2 - 1); // each cell starts fresh
    }
  });
});

// ── (d) Rejections — tampered segment/proof ───────────────────────────────────

describe('processHop with FLAG_PATH_MERKLE_OVERLOAD — rejections', () => {
  test('type-mismatch when the cell carries the wrong type for the current segment', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Set the wrong type on the cell (the proof checks BCA + typeHash together).
    setCellType(cell, mkTypeHash(999)); // wrong type
    // Type is outside CRC window, but we need to re-seal CRC since the routing
    // region hasn't changed. Actually type-hash is at offset 30, outside 160..216.
    // The CRC is still valid after this change. The merkle proof will fail.
    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('type-mismatch');
  });

  test('type-mismatch when sibling hash in proof is tampered', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Tamper the first sibling hash in the proof (at payload offset 256 + 41 + 0).
    // The proof is at cell offset 256 + 41 (first sibling hash starts at 297).
    const sibOff = 256 + 41;
    cell[sibOff] ^= 0xff;

    // CRC covers 160..216 only — doesn't detect payload tampering.
    expect(verifyRoutingChecksum(cell)).toBe(true);

    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('type-mismatch');
  });

  test('type-mismatch when leaf_index is inconsistent with segments_left', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20), mkSegment(3, 30)];
    const finalDest = mkBca(99);
    // Build a cell for hop 0 but claim leaf_index = 2 (inconsistent).
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Overwrite leaf_index in payload (cell offset 256 + 36..39)
    const dv = new DataView(cell.buffer);
    dv.setUint32(256 + 36, 2, true); // claim leaf_index = 2, but segments_left = 3

    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('type-mismatch');
  });

  test('budget-exhausted when HOP_COUNT_BUDGET is 0', () => {
    const segments = [mkSegment(1, 10)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Set budget to 0.
    const dv = new DataView(cell.buffer);
    dv.setUint32(172, 0, true); // OFF_HOP_COUNT_BUDGET
    setRoutingChecksum(cell);

    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('budget-exhausted');
  });

  test('not-my-hop still works under merkle overload', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    const res = processHop(cell, mkBca(777)); // wrong BCA
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('not-my-hop');
  });

  test('checksum rejection still works under merkle overload', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Tamper a byte inside the CRC window.
    cell[RoutingRegionOffsets.nextHopBca] ^= 0xff;
    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
    if (res.ok) throw new Error('unreachable');
    expect(res.reason).toBe('checksum');
  });
});

// ── (e) Non-mutation of input cell ────────────────────────────────────────────

describe('processHop with FLAG_PATH_MERKLE_OVERLOAD — non-mutation', () => {
  test('input cell is not mutated on forward', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    const before = new Uint8Array(cell);
    const res = processHop(cell, segments[0]!.bca);
    expect(Array.from(cell)).toEqual(Array.from(before)); // input unchanged
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
    // Output is different from input
    expect(Array.from(res.forwarded)).not.toEqual(Array.from(before));
  });
});

// ── (f) Canonical shared vector (oracle↔Zig) ──────────────────────────────────
//
// CANONICAL PATH-MERKLE VECTOR:
//
//   segments:
//     hop0: bca = mkBca(1), typeHash = mkTypeHash(10)   →  48-byte tuple
//     hop1: bca = mkBca(2), typeHash = mkTypeHash(20)   →  48-byte tuple
//     hop2: bca = mkBca(3), typeHash = mkTypeHash(30)   →  48-byte tuple
//
//   path_merkle_root: sha256(sha256(tuple0 || tuple1) || sha256(tuple2 || tuple2))
//     (3 leaves, odd → duplicate last)
//
//   hop0 leaf_index = 0, sibling_count = 2:
//     sibling[0] = right  sibling = sha256(tuple1)
//     sibling[1] = right  sibling = sha256(sha256(tuple2 || tuple2))
//
// The Zig mirror test "canonical path-merkle vector" MUST produce the same root.

describe('canonical vector (oracle↔Zig agreement)', () => {
  const seg0 = mkSegment(1, 10);
  const seg1 = mkSegment(2, 20);
  const seg2 = mkSegment(3, 30);
  const segments = [seg0, seg1, seg2];

  test('canonical root matches hand-computed value', () => {
    const t0 = encodeSegmentTuple(seg0);
    const t1 = encodeSegmentTuple(seg1);
    const t2 = encodeSegmentTuple(seg2);

    const leaf0 = cellMerkleSha256(t0);
    const leaf1 = cellMerkleSha256(t1);
    const leaf2 = cellMerkleSha256(t2);

    const ab = new Uint8Array(64);
    ab.set(leaf0, 0); ab.set(leaf1, 32);
    const branch01 = cellMerkleSha256(ab);

    const cd = new Uint8Array(64);
    cd.set(leaf2, 0); cd.set(leaf2, 32); // duplicate last
    const branch22 = cellMerkleSha256(cd);

    const rootInput = new Uint8Array(64);
    rootInput.set(branch01, 0); rootInput.set(branch22, 32);
    const expectedRoot = cellMerkleSha256(rootInput);

    const computedRoot = computePathMerkleRoot(segments);
    expect(Buffer.from(computedRoot).toString('hex')).toBe(
      Buffer.from(expectedRoot).toString('hex'),
    );
    // Print for Zig reference
    console.log('CANONICAL_PATH_MERKLE_ROOT_HEX:', Buffer.from(computedRoot).toString('hex'));
  });

  test('canonical hop0 proof verifies against canonical root', () => {
    const root = computePathMerkleRoot(segments);
    const proof = generateSegmentInclusionProof(segments, 0);
    expect(verifySegmentInclusion(seg0, proof, root)).toBe(true);
    // Sibling count for 3-leaf tree: 2 levels
    expect(proof.siblings.length).toBe(2);
    // First sibling is leaf1 (right sibling)
    expect(proof.siblings[0]!.position).toBe('right');
    // Second sibling is branch22 (right sibling of branch01)
    expect(proof.siblings[1]!.position).toBe('right');
  });

  test('canonical hop0 proof payload encode bytes — Zig must agree', () => {
    const root = computePathMerkleRoot(segments);
    const payloads = buildPathMerklePayloads(segments);
    const hop0 = payloads[0]!;
    const encoded = encodePathMerklePayload(hop0);

    // Bytes 0..31: root
    expect(Array.from(encoded.slice(0, 32))).toEqual(Array.from(root));
    // Bytes 32..35: total_hops = 3 u32 LE
    expect(encoded[32]).toBe(3);
    expect(encoded[33]).toBe(0);
    expect(encoded[34]).toBe(0);
    expect(encoded[35]).toBe(0);
    // Bytes 36..39: leaf_index = 0 u32 LE
    expect(encoded[36]).toBe(0);
    // Byte 40: sibling_count = 2
    expect(encoded[40]).toBe(2);
    // Size = 41 + 2*33 = 107
    expect(encoded.length).toBe(107);

    console.log('CANONICAL_HOP0_PAYLOAD_HEX:', Buffer.from(encoded).toString('hex'));
  });

  test('segment tuple encoding is deterministic (mkBca/mkTypeHash fixed seeds)', () => {
    const t0 = encodeSegmentTuple(seg0);
    expect(t0.length).toBe(48);
    // BCA: seed=1 → b[i] = (i + 31) & 0xff
    for (let i = 0; i < 16; i++) expect(t0[i]).toBe((i + 31) & 0xff);
    // typeHash: seed=10 → h[i] = (i * 5 + 10) & 0xff
    for (let i = 0; i < 32; i++) expect(t0[16 + i]).toBe((i * 5 + 10) & 0xff);
    console.log('CANONICAL_SEG0_TUPLE_HEX:', Buffer.from(t0).toString('hex'));
  });
});

// ── (g) CRC coverage relationship ─────────────────────────────────────────────

describe('CRC coverage — routing CRC does NOT cover path-merkle payload', () => {
  test('tampering path-merkle root (offset 256+) does not invalidate routing CRC', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Tamper the path-merkle root (cell offset 256 — outside CRC window 160..216)
    cell[256] ^= 0xff;
    expect(verifyRoutingChecksum(cell)).toBe(true); // CRC still valid
    // But merkle verification fails
    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(false);
  });

  test('FLAG_PATH_MERKLE_OVERLOAD bit in routing flags IS covered by CRC', () => {
    const segments = [mkSegment(1, 10), mkSegment(2, 20)];
    const finalDest = mkBca(99);
    const cell = buildMerkleRoutedCell(segments, finalDest, 0);

    // Tamper the routing flags byte (offset 164, inside CRC window)
    cell[RoutingRegionOffsets.routingFlags] ^= 0x10; // flip FLAG_PATH_MERKLE_OVERLOAD bit
    // CRC should now be invalid
    expect(verifyRoutingChecksum(cell)).toBe(false);
  });
});

```
