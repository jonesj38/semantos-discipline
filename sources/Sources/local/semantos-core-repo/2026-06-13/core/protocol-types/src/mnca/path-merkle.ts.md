---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/path-merkle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.900060+00:00
---

# core/protocol-types/src/mnca/path-merkle.ts

```ts
/**
 * Routing path-merkle overload — D-OCT-path-merkle-unify (step 4 of 5).
 *
 * Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5 / §7 step 4.
 *
 * When `FLAG_PATH_MERKLE_OVERLOAD` (bit 4 of ROUTING_FLAGS) is set, the inline
 * typed-segments array is replaced by a 32-byte PATH-MERKLE ROOT at the start
 * of the payload region (cell offset 256), plus a per-hop proof for the CURRENT
 * hop's 48-byte segment tuple.
 *
 * ## Leaf definition (routing vs data — the unification)
 *
 * The data side (D-OCT-merkle-hierarchy, step 3) uses `sha256(full 1024-byte
 * child cell)` as the leaf.  The routing side uses `sha256(48-byte segment
 * tuple)` as the leaf.  The hash math is **identical** — only the leaf size
 * differs.  Both share the same `verifyInclusion(leafBytes, proof, root)`
 * primitive exported from `core/cell-ops/src/packer/cell-merkle.ts`.
 *
 * ## Wire layout for FLAG_PATH_MERKLE_OVERLOAD (at payload offset, i.e. cell offset 256)
 *
 *   off  size  field
 *    0   32    path_merkle_root   — 32-byte root over all N 48-byte segment tuples
 *   32    4    total_hops         — u32 LE: total number of segments N (for
 *                                  segments_left validation; mirrors the N in
 *                                  the inline [N ‖ starts] header)
 *   36    4    leaf_index         — u32 LE: index of the CURRENT hop's tuple in
 *                                  the merkle tree (0-based)
 *   40    1    sibling_count      — u8: number of sibling proof steps
 *   41    (sibling_count × 33)   — proof siblings, each:
 *                                    32 bytes: sibling hash
 *                                     1 byte:  position (0x00 = left, 0x01 = right)
 *
 * Total minimum size: 41 bytes (zero siblings for a single-hop route).
 * Maximum: 41 + 16 × 33 = 569 bytes (16 sibling levels for ≤ 65536 hops).
 *
 * ## CRC relationship
 *
 * The routing CRC covers bytes 160..216 (the routing region header).
 * The FLAG_PATH_MERKLE_OVERLOAD flag at offset 164 IS inside the CRC window
 * (protected).  The path-merkle root + proof at offset 256+ are OUTSIDE the
 * CRC window — same as inline segment tuples are not covered by the routing CRC.
 *
 * ## flow_label as fragment-correlation key
 *
 * `flow_label` (routing header offset 176, u64) ties fragments of a deep route
 * together.  All cells of a single overloaded route share the same `flow_label`.
 * Relays and reassemblers use it to gather fragments without a central index
 * (design doc §5, O-4 answered: reuse offset 176 as-is).
 *
 * ## Segment tuple definition
 *
 * A segment tuple is 48 bytes: `[16-byte BCA ‖ 32-byte type-hash]`.
 * The BCA is the 16-byte IPv6-shaped identifier of the hop node.
 * The type-hash is the 32-byte SHA-256 type-hash the cell must carry on arrival.
 *
 * ## Shared verifier (the unification)
 *
 * `verifyInclusion(segmentTuple48B, proof, pathMerkleRoot)` from
 * `core/cell-ops/src/packer/cell-merkle.ts` is called with the 48-byte tuple
 * as the leaf.  This is byte-identical to how the data side calls
 * `verifyCellInclusion(cell1024B, proof, domainPayloadRoot)` — only the leaf
 * size changes.  One verifier, two use sites.
 */

import {
  cellMerkleSha256 as sha256,
  verifyInclusion,
  type CellMerkleProof,
  type CellMerkleSibling,
} from '@semantos/cell-ops/packer';

// ── Segment tuple constants ────────────────────────────────────────────────────

export const SEGMENT_BCA_SIZE = 16 as const;
export const SEGMENT_TYPE_HASH_SIZE = 32 as const;
/** Size of a single segment tuple: 16B BCA + 32B type-hash. */
export const SEGMENT_TUPLE_SIZE = SEGMENT_BCA_SIZE + SEGMENT_TYPE_HASH_SIZE; // 48

// ── Path-merkle payload layout constants ──────────────────────────────────────

/** Offset within the PAYLOAD region (i.e. +256 for cell-absolute) of the path-merkle root. */
export const PATH_MERKLE_ROOT_OFFSET = 0 as const;
export const PATH_MERKLE_ROOT_SIZE = 32 as const;

/** Offset (within payload) of the u32 LE total_hops field. */
export const PATH_MERKLE_TOTAL_HOPS_OFFSET = 32 as const;

/** Offset (within payload) of the u32 LE leaf_index field for the current hop's proof. */
export const PATH_MERKLE_LEAF_INDEX_OFFSET = 36 as const;

/** Offset (within payload) of the u8 sibling_count field. */
export const PATH_MERKLE_SIBLING_COUNT_OFFSET = 40 as const;

/** Offset (within payload) of the first sibling entry. */
export const PATH_MERKLE_SIBLINGS_OFFSET = 41 as const;

/** Size of one sibling entry: 32-byte hash + 1-byte position. */
export const PATH_MERKLE_SIBLING_ENTRY_SIZE = 33 as const;

/** Maximum proof siblings (ceil(log2(65536)) = 16 levels). */
export const PATH_MERKLE_MAX_SIBLINGS = 16 as const;

/** Minimum payload bytes required for a path-merkle overload payload (zero siblings). */
export const PATH_MERKLE_PAYLOAD_MIN_SIZE = PATH_MERKLE_SIBLINGS_OFFSET; // 41

/** Maximum payload bytes for a path-merkle proof (16 sibling levels). */
export const PATH_MERKLE_PAYLOAD_MAX_SIZE =
  PATH_MERKLE_SIBLINGS_OFFSET + PATH_MERKLE_MAX_SIBLINGS * PATH_MERKLE_SIBLING_ENTRY_SIZE; // 569

// ── Types ─────────────────────────────────────────────────────────────────────

/** A single segment tuple: the building block for the path-merkle tree. */
export interface SegmentTuple {
  /** 16-byte BCA of the hop. */
  bca: Uint8Array;
  /** 32-byte type-hash the cell must carry on arrival at this hop. */
  typeHash: Uint8Array;
}

/**
 * The path-merkle overload payload: the 32-byte root + per-hop proof,
 * in the decoded (structured) form.
 */
export interface PathMerklePayload {
  /** 32-byte merkle root over all segment tuples. */
  pathMerkleRoot: Uint8Array;
  /** Total number of hops (N). */
  totalHops: number;
  /** Leaf index of the current hop's tuple in the merkle tree. */
  leafIndex: number;
  /** Merkle proof siblings for the current hop's tuple. */
  siblings: CellMerkleSibling[];
}

// ── Segment tuple helpers ─────────────────────────────────────────────────────

/**
 * Encode a segment tuple into 48 bytes: `[16B BCA ‖ 32B type-hash]`.
 */
export function encodeSegmentTuple(seg: SegmentTuple): Uint8Array {
  if (seg.bca.length !== SEGMENT_BCA_SIZE) {
    throw new Error(`encodeSegmentTuple: bca must be ${SEGMENT_BCA_SIZE} bytes`);
  }
  if (seg.typeHash.length !== SEGMENT_TYPE_HASH_SIZE) {
    throw new Error(`encodeSegmentTuple: typeHash must be ${SEGMENT_TYPE_HASH_SIZE} bytes`);
  }
  const out = new Uint8Array(SEGMENT_TUPLE_SIZE);
  out.set(seg.bca, 0);
  out.set(seg.typeHash, SEGMENT_BCA_SIZE);
  return out;
}

/**
 * Decode a 48-byte segment tuple into a `SegmentTuple`.
 */
export function decodeSegmentTuple(bytes: Uint8Array): SegmentTuple {
  if (bytes.length < SEGMENT_TUPLE_SIZE) {
    throw new Error(`decodeSegmentTuple: need ${SEGMENT_TUPLE_SIZE} bytes, got ${bytes.length}`);
  }
  return {
    bca: bytes.slice(0, SEGMENT_BCA_SIZE),
    typeHash: bytes.slice(SEGMENT_BCA_SIZE, SEGMENT_TUPLE_SIZE),
  };
}

// ── Merkle tree over segment tuples ───────────────────────────────────────────

/**
 * Compute a merkle root over segment tuples.
 *
 * The leaf hash for each segment tuple is `sha256(48-byte tuple)` — the same
 * single-SHA-256 scheme used by the data side for 1024-byte cells.
 *
 * @param segments - Array of segment tuples (one per hop).
 * @returns 32-byte merkle root.
 */
export function computePathMerkleRoot(segments: SegmentTuple[]): Uint8Array {
  if (segments.length === 0) {
    throw new Error('computePathMerkleRoot: no segments');
  }

  const leafHashes = segments.map(seg => sha256(encodeSegmentTuple(seg)));
  return computeRootFromHashes(leafHashes);
}

/** Internal: binary merkle root from an array of 32-byte hashes. */
function computeRootFromHashes(hashes: Uint8Array[]): Uint8Array {
  if (hashes.length === 1) return new Uint8Array(hashes[0]!);

  let level = hashes.map(h => new Uint8Array(h));

  while (level.length > 1) {
    // Odd padding: duplicate last.
    if (level.length % 2 !== 0) {
      level.push(new Uint8Array(level[level.length - 1]!));
    }
    const next: Uint8Array[] = [];
    for (let i = 0; i < level.length; i += 2) {
      const combined = new Uint8Array(64);
      combined.set(level[i]!, 0);
      combined.set(level[i + 1]!, 32);
      next.push(sha256(combined));
    }
    level = next;
  }

  return level[0]!;
}

/**
 * Generate an inclusion proof for segment at `hopIndex` within the hop list.
 *
 * @param segments - All segments for the route.
 * @param hopIndex - Which hop's proof to generate (0-based).
 * @returns CellMerkleProof (same type as the data side — shared proof structure).
 */
export function generateSegmentInclusionProof(
  segments: SegmentTuple[],
  hopIndex: number,
): CellMerkleProof {
  if (segments.length === 0) {
    throw new Error('generateSegmentInclusionProof: no segments');
  }
  if (hopIndex < 0 || hopIndex >= segments.length) {
    throw new Error(`generateSegmentInclusionProof: hopIndex ${hopIndex} out of range [0, ${segments.length})`);
  }

  const leafHashes = segments.map(seg => sha256(encodeSegmentTuple(seg)));
  return generateProofFromHashes(leafHashes, hopIndex);
}

/** Internal: generate a merkle proof from pre-computed leaf hashes. */
function generateProofFromHashes(leafHashes: Uint8Array[], leafIndex: number): CellMerkleProof {
  const siblings: CellMerkleSibling[] = [];
  let level = leafHashes.map(h => new Uint8Array(h));
  let currentIndex = leafIndex;

  while (level.length > 1) {
    if (level.length % 2 !== 0) {
      level.push(new Uint8Array(level[level.length - 1]!));
    }
    const next: Uint8Array[] = [];
    for (let i = 0; i < level.length; i += 2) {
      if (i === currentIndex || i + 1 === currentIndex) {
        if (currentIndex % 2 === 0) {
          siblings.push({ hash: new Uint8Array(level[i + 1]!), position: 'right' });
        } else {
          siblings.push({ hash: new Uint8Array(level[i]!), position: 'left' });
        }
      }
      const combined = new Uint8Array(64);
      combined.set(level[i]!, 0);
      combined.set(level[i + 1]!, 32);
      next.push(sha256(combined));
    }
    currentIndex = Math.floor(currentIndex / 2);
    level = next;
  }

  return { leafIndex, siblings };
}

// ── Verify segment inclusion ───────────────────────────────────────────────────

/**
 * Verify that a segment tuple is included under the path-merkle root.
 *
 * This is the ROUTING half of the UNIFIED inclusion-proof verifier.
 * Delegates to `verifyInclusion(leafBytes, proof, root)` from
 * `@semantos/cell-ops` — the SAME function used by the data side.
 *
 * The unification (design doc §1 thesis):
 *   - Data side:    `verifyCellInclusion(cell1024B, proof, domainPayloadRoot)`
 *                    → calls verifyInclusion(cell1024B, ...)
 *   - Routing side: `verifySegmentInclusion(seg48B, proof, pathMerkleRoot)`
 *                    → calls verifyInclusion(seg48B, ...)
 * Both share one verifier; only the leaf size differs.
 *
 * @param seg - The segment tuple to verify (48 bytes = 16B BCA + 32B type-hash).
 * @param proof - Merkle proof (shared CellMerkleProof type).
 * @param root - 32-byte path-merkle root from the payload.
 * @returns true iff the segment is provably in the tree under `root`.
 */
export function verifySegmentInclusion(
  seg: SegmentTuple,
  proof: CellMerkleProof,
  root: Uint8Array,
): boolean {
  // The 48-byte segment tuple is the leaf. The shared verifyInclusion
  // hashes it as sha256(48B) — identical math to sha256(1024B) for cells.
  return verifyInclusion(encodeSegmentTuple(seg), proof, root);
}

// ── Payload wire encode / decode ───────────────────────────────────────────────

/**
 * Encode the path-merkle payload into a byte buffer.
 *
 * Wire layout (at payload offset 0 within the 768-byte payload region):
 *   0..31   path_merkle_root (32 bytes)
 *   32..35  total_hops (u32 LE)
 *   36..39  leaf_index (u32 LE)
 *   40      sibling_count (u8)
 *   41..    sibling_count × 33-byte entries: [32 hash ‖ 1 position (0=left, 1=right)]
 *
 * @param payload - Decoded path-merkle payload.
 * @returns Byte buffer (minimum 41 bytes, maximum 569 bytes).
 */
export function encodePathMerklePayload(payload: PathMerklePayload): Uint8Array {
  if (payload.pathMerkleRoot.length !== PATH_MERKLE_ROOT_SIZE) {
    throw new Error(`encodePathMerklePayload: root must be ${PATH_MERKLE_ROOT_SIZE} bytes`);
  }
  if (payload.siblings.length > PATH_MERKLE_MAX_SIBLINGS) {
    throw new Error(
      `encodePathMerklePayload: too many siblings ${payload.siblings.length} (max ${PATH_MERKLE_MAX_SIBLINGS})`,
    );
  }

  const size =
    PATH_MERKLE_SIBLINGS_OFFSET + payload.siblings.length * PATH_MERKLE_SIBLING_ENTRY_SIZE;
  const buf = new Uint8Array(size);
  const dv = new DataView(buf.buffer);

  // 0..31: root
  buf.set(payload.pathMerkleRoot, PATH_MERKLE_ROOT_OFFSET);

  // 32..35: total_hops u32 LE
  dv.setUint32(PATH_MERKLE_TOTAL_HOPS_OFFSET, payload.totalHops >>> 0, true);

  // 36..39: leaf_index u32 LE
  dv.setUint32(PATH_MERKLE_LEAF_INDEX_OFFSET, payload.leafIndex >>> 0, true);

  // 40: sibling_count
  buf[PATH_MERKLE_SIBLING_COUNT_OFFSET] = payload.siblings.length & 0xff;

  // 41..: siblings
  let off = PATH_MERKLE_SIBLINGS_OFFSET;
  for (const sib of payload.siblings) {
    if (sib.hash.length !== 32) {
      throw new Error('encodePathMerklePayload: sibling hash must be 32 bytes');
    }
    buf.set(sib.hash, off);
    buf[off + 32] = sib.position === 'left' ? 0x00 : 0x01;
    off += PATH_MERKLE_SIBLING_ENTRY_SIZE;
  }

  return buf;
}

/**
 * Decode path-merkle payload bytes (at payload offset 0 within the cell payload region).
 *
 * @param payloadBuf - The 768-byte payload region buffer (or at least the first
 *                    `41 + sibling_count * 33` bytes).
 * @returns Decoded `PathMerklePayload`.
 */
export function decodePathMerklePayload(payloadBuf: Uint8Array): PathMerklePayload {
  if (payloadBuf.length < PATH_MERKLE_PAYLOAD_MIN_SIZE) {
    throw new Error(
      `decodePathMerklePayload: buffer too small (${payloadBuf.length}, need ${PATH_MERKLE_PAYLOAD_MIN_SIZE})`,
    );
  }

  const dv = new DataView(payloadBuf.buffer, payloadBuf.byteOffset, payloadBuf.byteLength);

  const pathMerkleRoot = payloadBuf.slice(PATH_MERKLE_ROOT_OFFSET, PATH_MERKLE_ROOT_SIZE);
  const totalHops = dv.getUint32(PATH_MERKLE_TOTAL_HOPS_OFFSET, true);
  const leafIndex = dv.getUint32(PATH_MERKLE_LEAF_INDEX_OFFSET, true);
  const siblingCount = payloadBuf[PATH_MERKLE_SIBLING_COUNT_OFFSET]!;

  if (siblingCount > PATH_MERKLE_MAX_SIBLINGS) {
    throw new Error(
      `decodePathMerklePayload: sibling_count ${siblingCount} exceeds max ${PATH_MERKLE_MAX_SIBLINGS}`,
    );
  }

  const required = PATH_MERKLE_SIBLINGS_OFFSET + siblingCount * PATH_MERKLE_SIBLING_ENTRY_SIZE;
  if (payloadBuf.length < required) {
    throw new Error(
      `decodePathMerklePayload: buffer too small for ${siblingCount} siblings (need ${required}, got ${payloadBuf.length})`,
    );
  }

  const siblings: CellMerkleSibling[] = [];
  let off = PATH_MERKLE_SIBLINGS_OFFSET;
  for (let i = 0; i < siblingCount; i++) {
    const hash = payloadBuf.slice(off, off + 32);
    const posByte = payloadBuf[off + 32]!;
    const position: 'left' | 'right' = posByte === 0x00 ? 'left' : 'right';
    siblings.push({ hash, position });
    off += PATH_MERKLE_SIBLING_ENTRY_SIZE;
  }

  return { pathMerkleRoot, totalHops, leafIndex, siblings };
}

// ── Full route builder: encode all hops' proofs for a deep route ───────────────

/**
 * Build the per-hop path-merkle payload for each hop in a deep route.
 *
 * The originator calls this to prepare one `PathMerklePayload` per hop.
 * Each cell on the route carries its own payload (with its `leafIndex` and
 * the proof specific to that hop's segment position in the tree).
 *
 * @param segments - All segment tuples for the route (one per hop, in order).
 * @returns Array of `PathMerklePayload`, one per hop (same length as segments).
 */
export function buildPathMerklePayloads(segments: SegmentTuple[]): PathMerklePayload[] {
  if (segments.length === 0) {
    throw new Error('buildPathMerklePayloads: no segments');
  }

  const root = computePathMerkleRoot(segments);
  const totalHops = segments.length;

  return segments.map((_, hopIndex) => {
    const proof = generateSegmentInclusionProof(segments, hopIndex);
    return {
      pathMerkleRoot: root,
      totalHops,
      leafIndex: hopIndex,
      siblings: proof.siblings,
    };
  });
}

/**
 * Write the path-merkle payload (encoded) into the beginning of the 768-byte
 * cell payload region.
 *
 * @param cellBuf - Mutable 1024-byte cell buffer.
 * @param payload - The decoded path-merkle payload to write.
 * @param headerSize - Cell header size (256). Provided as a parameter so callers
 *                     don't need to import constants; defaults to 256.
 */
export function writePathMerklePayload(
  cellBuf: Uint8Array,
  payload: PathMerklePayload,
  headerSize = 256,
): void {
  const encoded = encodePathMerklePayload(payload);
  if (cellBuf.length < headerSize + encoded.length) {
    throw new Error(
      `writePathMerklePayload: cell buffer too small (${cellBuf.length}) for payload (${encoded.length})`,
    );
  }
  cellBuf.set(encoded, headerSize);
}

/**
 * Read the path-merkle payload from the beginning of the 768-byte cell payload region.
 *
 * @param cellBuf - The 1024-byte cell buffer.
 * @param headerSize - Cell header size (256). Defaults to 256.
 */
export function readPathMerklePayload(
  cellBuf: Uint8Array,
  headerSize = 256,
): PathMerklePayload {
  const payloadView = cellBuf.subarray(headerSize);
  return decodePathMerklePayload(payloadView);
}

```
