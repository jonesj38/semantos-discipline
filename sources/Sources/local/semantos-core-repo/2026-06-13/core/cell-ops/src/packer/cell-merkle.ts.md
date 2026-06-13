---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/cell-merkle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.830883+00:00
---

# core/cell-ops/src/packer/cell-merkle.ts

```ts
/**
 * Cell Merkle — binary merkle tree over 1024-byte child cells (rung-2 hierarchy).
 *
 * Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §3/§7 step 3.
 * This is D-OCT-merkle-hierarchy (step 3 of 5).
 *
 * ## Hash scheme
 *
 * Cells are content-addressed with single SHA-256 (see `hashBytes` in
 * core/protocol-types/src/content-store.ts — uses `crypto.subtle.digest("SHA-256", ...)`).
 * This merkle tree follows the SAME single-SHA-256 scheme, NOT Bitcoin's double-SHA-256
 * (the double-SHA-256 in headers.zig/merkleEnvelope.ts is for BSV tx-merkle paths,
 * a distinct primitive).
 *
 * Leaf hash  = SHA-256(full 1024-byte child cell)
 * Branch hash = SHA-256(left_hash_32B || right_hash_32B)
 *
 * Odd number of nodes at a level: duplicate the last node (same convention as Bitcoin
 * tx-merkle, but with single-SHA-256).
 *
 * The root is the canonical `domainPayloadRoot` committed into the 1024-byte header
 * at byte offset 224 (HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT = 224).
 *
 * ## Verifier reuse
 *
 * `verifyCellInclusion` is the shared inclusion-proof verifier that step 4
 * (D-OCT-path-merkle-unify) will ALSO use for routing-path merkle proofs.
 * Signature:
 *   verifyCellInclusion(cellBytes: Uint8Array, proof: CellMerkleProof, root: Uint8Array): boolean
 *
 * ## Backward-compat guarantee
 *
 * This module is ADDITIVE. It does not change packMultiCell / unpackMultiCell
 * (rung-0) or packEscalated / unpackEscalated (rung-1). Rung-2 detection uses
 * the descriptor rung field (= 2) AND the domainPayloadRoot field being non-zero.
 *
 * ## Oracle ↔ Zig mirror contract
 *
 * The Zig mirror lives at core/cell-engine/src/cell_merkle.zig.
 * Both sides MUST agree on the CANONICAL_ROOT_HEX and proof byte-vector defined
 * in the tests.
 */

import { createHash } from 'crypto';
import { CELL_SIZE, HEADER_SIZE } from './constants';

// ── Hash scheme ────────────────────────────────────────────────────────────────

/**
 * Single SHA-256 of an arbitrary byte buffer.
 *
 * This is the cell content-addressing scheme (matches `hashBytes` in
 * core/protocol-types/src/content-store.ts).  NOT double-SHA-256.
 */
export function sha256(data: Uint8Array): Uint8Array {
  return new Uint8Array(createHash('sha256').update(data).digest());
}

// ── Header offset ──────────────────────────────────────────────────────────────

/**
 * Byte offset of the 32-byte `domainPayloadRoot` slot within the 1024-byte
 * cell header (matches constants.ts / constants.zig HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT).
 */
export const DOMAIN_PAYLOAD_ROOT_OFFSET = 224;
export const DOMAIN_PAYLOAD_ROOT_SIZE = 32;

// ── Merkle proof types ─────────────────────────────────────────────────────────

/**
 * One sibling node in a merkle path.
 * `position: 'left'`  means the sibling is to the LEFT  of the current hash.
 * `position: 'right'` means the sibling is to the RIGHT of the current hash.
 */
export interface CellMerkleSibling {
  hash: Uint8Array; // 32 bytes
  position: 'left' | 'right';
}

/**
 * Inclusion proof for a single leaf (child cell) within a cell merkle tree.
 *
 * To verify:
 *   1. Compute leaf hash = sha256(cellBytes)  [full 1024-byte cell]
 *   2. Walk the sibling path, combining hashes at each level
 *   3. Compare the computed root to the committed domainPayloadRoot
 *
 * This is the shared verifier signature that step 4 (D-OCT-path-merkle-unify)
 * will also use for routing-path proofs.
 */
export interface CellMerkleProof {
  /** Index of this leaf in the original leaf array (0-based). */
  leafIndex: number;
  /** Sibling hashes from leaf level up to (but not including) the root. */
  siblings: CellMerkleSibling[];
}

// ── Core merkle operations ─────────────────────────────────────────────────────

/**
 * Compute the merkle root over an array of 32-byte leaf hashes.
 *
 * Odd number of leaves at any level: duplicate the last hash (standard convention).
 *
 * @param leafHashes - Array of 32-byte hashes (one per child cell).
 * @returns 32-byte root hash.
 */
export function computeMerkleRootFromHashes(leafHashes: Uint8Array[]): Uint8Array {
  if (leafHashes.length === 0) {
    throw new Error('Cannot compute merkle root from empty leaf set');
  }

  if (leafHashes.length === 1) {
    // Single-leaf tree: root = the leaf hash itself (no sibling to combine with).
    return new Uint8Array(leafHashes[0]!);
  }

  let level = leafHashes.map(h => new Uint8Array(h));

  while (level.length > 1) {
    // Pad if odd
    if (level.length % 2 !== 0) {
      level.push(new Uint8Array(level[level.length - 1]!));
    }

    const nextLevel: Uint8Array[] = [];
    for (let i = 0; i < level.length; i += 2) {
      const combined = new Uint8Array(64);
      combined.set(level[i]!, 0);
      combined.set(level[i + 1]!, 32);
      nextLevel.push(sha256(combined));
    }
    level = nextLevel;
  }

  return level[0]!;
}

/**
 * Compute leaf hashes for a set of child cells.
 * Each leaf hash = sha256(full 1024-byte child cell).
 *
 * O-3 (from design doc): leaf = full 1024-byte child cell, NOT the payload sub-region.
 */
export function computeLeafHashes(childCells: Uint8Array[]): Uint8Array[] {
  return childCells.map(cell => sha256(cell));
}

/**
 * Compute the merkle root over an array of 1024-byte child cells.
 * Convenience wrapper: computeLeafHashes + computeMerkleRootFromHashes.
 */
export function computeCellMerkleRoot(childCells: Uint8Array[]): Uint8Array {
  if (childCells.length === 0) {
    throw new Error('Cannot compute cell merkle root from empty child cell set');
  }
  return computeMerkleRootFromHashes(computeLeafHashes(childCells));
}

/**
 * Generate an inclusion proof from arbitrary leaf-byte arrays.
 *
 * Used by D-OCT-path-merkle-unify for routing segments (48-byte tuples).
 * Each `leafItems[i]` is hashed via sha256 to produce the leaf hash.
 *
 * @param leafItems - Array of arbitrary-length byte arrays (one per leaf).
 * @param leafIndex - Which leaf to generate a proof for (0-based).
 */
export function generateInclusionProof(
  leafItems: Uint8Array[],
  leafIndex: number,
): CellMerkleProof {
  if (leafItems.length === 0) {
    throw new Error('Cannot generate proof from empty leaf set');
  }
  if (leafIndex < 0 || leafIndex >= leafItems.length) {
    throw new Error(
      `Leaf index ${leafIndex} out of range [0, ${leafItems.length})`,
    );
  }

  const leafHashes = leafItems.map(item => sha256(item));
  return generateProofFromHashes(leafHashes, leafIndex);
}

/**
 * Generate an inclusion proof for leaf at `leafIndex` within the array of child cells.
 *
 * Wrapper around `generateInclusionProof` for the conventional 1024-byte cell case.
 *
 * @param childCells - All child cells (each 1024 bytes).
 * @param leafIndex - Which leaf to generate a proof for (0-based).
 */
export function generateCellInclusionProof(
  childCells: Uint8Array[],
  leafIndex: number,
): CellMerkleProof {
  if (childCells.length === 0) {
    throw new Error('Cannot generate proof from empty child cell set');
  }
  if (leafIndex < 0 || leafIndex >= childCells.length) {
    throw new Error(
      `Leaf index ${leafIndex} out of range [0, ${childCells.length})`,
    );
  }

  const leafHashes = computeLeafHashes(childCells);
  return generateProofFromHashes(leafHashes, leafIndex);
}

/**
 * Generate an inclusion proof from pre-computed leaf hashes.
 * Internal helper — use `generateCellInclusionProof` for the public API.
 */
function generateProofFromHashes(
  leafHashes: Uint8Array[],
  leafIndex: number,
): CellMerkleProof {
  const siblings: CellMerkleSibling[] = [];
  let level = leafHashes.map(h => new Uint8Array(h));
  let currentIndex = leafIndex;

  while (level.length > 1) {
    // Pad if odd
    if (level.length % 2 !== 0) {
      level.push(new Uint8Array(level[level.length - 1]!));
    }

    const nextLevel: Uint8Array[] = [];
    for (let i = 0; i < level.length; i += 2) {
      // If the current node is in this pair, record its sibling.
      if (i === currentIndex || i + 1 === currentIndex) {
        if (currentIndex % 2 === 0) {
          // Current node is left → sibling is right.
          siblings.push({ hash: new Uint8Array(level[i + 1]!), position: 'right' });
        } else {
          // Current node is right → sibling is left.
          siblings.push({ hash: new Uint8Array(level[i]!), position: 'left' });
        }
      }

      const combined = new Uint8Array(64);
      combined.set(level[i]!, 0);
      combined.set(level[i + 1]!, 32);
      nextLevel.push(sha256(combined));
    }

    currentIndex = Math.floor(currentIndex / 2);
    level = nextLevel;
  }

  return { leafIndex, siblings };
}

/**
 * Generic leaf-bytes-agnostic inclusion-proof verifier.
 *
 * This is the UNIFIED PRIMITIVE shared by:
 *   - Data side (D-OCT-merkle-hierarchy): leaf = full 1024-byte child cell.
 *   - Routing side (D-OCT-path-merkle-unify): leaf = 48-byte segment tuple
 *     [16B BCA ‖ 32B type-hash].
 *
 * The hash math is identical regardless of leaf size:
 *   leaf_hash = sha256(leafBytes)   // arbitrary length
 *   branch    = sha256(left32 ‖ right32)
 *
 * @param leafBytes - Arbitrary leaf bytes (1024 B for data cells, 48 B for
 *                    routing segments — see note above).
 * @param proof - Inclusion proof (leafIndex + siblings).
 * @param root - The committed 32-byte merkle root.
 * @returns `true` iff the leaf is provably included under `root`.
 */
export function verifyInclusion(
  leafBytes: Uint8Array,
  proof: CellMerkleProof,
  root: Uint8Array,
): boolean {
  if (root.length !== 32) return false;

  let currentHash = sha256(leafBytes);

  for (const sibling of proof.siblings) {
    if (sibling.hash.length !== 32) return false;
    const combined = new Uint8Array(64);
    if (sibling.position === 'right') {
      combined.set(currentHash, 0);
      combined.set(sibling.hash, 32);
    } else {
      combined.set(sibling.hash, 0);
      combined.set(currentHash, 32);
    }
    currentHash = sha256(combined);
  }

  if (currentHash.length !== root.length) return false;
  let diff = 0;
  for (let i = 0; i < 32; i++) diff |= (currentHash[i]! ^ root[i]!);
  return diff === 0;
}

/**
 * Verify that a child cell is included under a committed merkle root.
 *
 * This is the SHARED VERIFIER that step 4 (D-OCT-path-merkle-unify) also
 * uses for routing-path merkle proofs. Delegates to `verifyInclusion` with
 * the full 1024-byte cell bytes as the leaf.
 *
 * For routing-path proofs (48-byte segment tuples), call `verifyInclusion`
 * directly instead of this wrapper.
 *
 * @param cellBytes - Full 1024-byte child cell bytes.
 * @param proof - Inclusion proof (leafIndex + siblings).
 * @param root - The committed 32-byte merkle root (from domainPayloadRoot or
 *               the routing-path merkle slot).
 * @returns `true` iff the cell is provably included under `root`.
 */
export function verifyCellInclusion(
  cellBytes: Uint8Array,
  proof: CellMerkleProof,
  root: Uint8Array,
): boolean {
  // Delegates to the leaf-size-agnostic verifier. 1024-byte leaf is conventional
  // for data cells; routing passes 48-byte segment tuples via verifyInclusion directly.
  return verifyInclusion(cellBytes, proof, root);
}

// ── domainPayloadRoot read/write ───────────────────────────────────────────────

/**
 * Write a 32-byte merkle root into the `domainPayloadRoot` slot of a
 * 1024-byte cell buffer (bytes 224..255 of the header).
 *
 * The cell buffer must be at least 256 bytes (HEADER_SIZE).
 */
export function writeDomainPayloadRoot(cellBuf: Uint8Array, root: Uint8Array): void {
  if (cellBuf.length < HEADER_SIZE) {
    throw new Error(
      `Cell buffer too small: ${cellBuf.length} bytes (minimum ${HEADER_SIZE})`,
    );
  }
  if (root.length !== DOMAIN_PAYLOAD_ROOT_SIZE) {
    throw new Error(
      `Root must be exactly ${DOMAIN_PAYLOAD_ROOT_SIZE} bytes; got ${root.length}`,
    );
  }
  cellBuf.set(root, DOMAIN_PAYLOAD_ROOT_OFFSET);
}

/**
 * Read the 32-byte `domainPayloadRoot` from a cell buffer.
 *
 * Returns a copy (not a view into `cellBuf`).
 */
export function readDomainPayloadRoot(cellBuf: Uint8Array): Uint8Array {
  if (cellBuf.length < HEADER_SIZE) {
    throw new Error(
      `Cell buffer too small: ${cellBuf.length} bytes (minimum ${HEADER_SIZE})`,
    );
  }
  return new Uint8Array(
    cellBuf.buffer,
    cellBuf.byteOffset + DOMAIN_PAYLOAD_ROOT_OFFSET,
    DOMAIN_PAYLOAD_ROOT_SIZE,
  ).slice();
}

// ── Rung-2 pack/unpack ─────────────────────────────────────────────────────────

/** Escalation sentinel value (mirrors multicell-assembler.ts). */
const ESCALATION_CELL_COUNT_SENTINEL = 0xffffffff;

/** Size of the 16-byte escalation descriptor (mirrors escalation_descriptor.ts). */
const ESCALATION_DESCRIPTOR_SIZE = 16;

/** Rung value for merkle-rooted hierarchy. */
const RUNG_MERKLE_ROOTED = 2;

/**
 * Octave level constants for cell_merkle — mirrors multicell-assembler.ts and cell_merkle.zig.
 * D-OCT-octave-2-plus (step 5/5): mega/giga levels added.
 */
export const CELL_MERKLE_OCTAVE_LEVEL_BASE = 0; // 1 KiB cells
export const CELL_MERKLE_OCTAVE_LEVEL_KILO = 1; // 1 MiB cells
export const CELL_MERKLE_OCTAVE_LEVEL_MEGA = 2; // 1 GiB cells
export const CELL_MERKLE_OCTAVE_LEVEL_GIGA = 3; // 1 TiB cells
export const CELL_MERKLE_MAX_OCTAVE_LEVEL = 3;

/** @deprecated Use CELL_MERKLE_OCTAVE_LEVEL_BASE. Kept for backward-compat. */
const OCTAVE_LEVEL_BASE = CELL_MERKLE_OCTAVE_LEVEL_BASE;

/**
 * Result of `packMerkleHierarchy`.
 */
export interface MerkleHierarchyPacked {
  /**
   * The "anchor" Cell 0 (exactly 1024 bytes).
   *
   * Contains:
   *   - The original header bytes (caller-supplied 256 bytes) with:
   *     - `cell_count` (offset 86)  patched to ESCALATION_CELL_COUNT_SENTINEL
   *     - `total_size` (offset 90)  patched to ESCALATION_DESCRIPTOR_SIZE (16)
   *     - `domainPayloadRoot` (offset 224) set to the 32-byte merkle root
   *   - Payload bytes 0..15: 16-byte escalation descriptor
   *     (rung=2, octave_level=OCTAVE_LEVEL_BASE, child_count=N, total_bytes=totalBytes)
   *   - Payload bytes 16..767: zeroed
   */
  anchorCell: Uint8Array;

  /** 32-byte merkle root committed into domainPayloadRoot. */
  merkleRoot: Uint8Array;

  /** Number of child cells. */
  childCount: number;
}

/**
 * Result of `unpackMerkleHierarchy`.
 */
export interface MerkleHierarchyDescriptor {
  /** The 32-byte merkle root from the domainPayloadRoot header slot. */
  merkleRoot: Uint8Array;
  /** Number of child cells (from the escalation descriptor). */
  childCount: number;
  /** Total logical blob size (from the escalation descriptor, u64 as bigint). */
  totalBytes: bigint;
  /** Octave level of the child cells. */
  octaveLevel: number;
}

/**
 * Pack a rung-2 (merkle-rooted hierarchy) anchor cell.
 *
 * Given:
 *   - A 256-byte header (will be patched for cell_count, total_size, domainPayloadRoot).
 *   - An array of 1024-byte child cells.
 *   - The total logical blob size (u64 as bigint — authoritative for O-1).
 *   - The octave level of the child cells (0=base, 1=kilo, 2=mega, 3=giga).
 *     Use `CELL_MERKLE_OCTAVE_LEVEL_BASE` for ordinary 1 KiB child cells.
 *     Use `CELL_MERKLE_OCTAVE_LEVEL_MEGA` / `CELL_MERKLE_OCTAVE_LEVEL_GIGA` when
 *     the hierarchy's child cells are 1 GiB / 1 TiB cells.
 *     (D-OCT-octave-2-plus, step 5/5.)
 *
 * Builds the binary merkle tree over the child cells (leaf = full 1024-byte cell,
 * using single-SHA-256), commits the root into domainPayloadRoot, and writes the
 * escalation descriptor (rung=2) at payload offset 0.
 *
 * O-1 header semantics (uniform for ALL rung≥1):
 *   total_size (u32 at header offset 90) = ESCALATION_DESCRIPTOR_SIZE (16).
 *   The descriptor's totalBytes (u64 BigInt) is the authoritative logical blob size.
 *
 * The child cells themselves are NOT concatenated here — the caller stores/transmits
 * them separately.  Only the 1024-byte anchor Cell 0 is returned.
 *
 * Rung-0/1 bytes are completely unaffected.
 *
 * @param header     - 256 bytes; will be copied and patched (original not mutated).
 * @param childCells - Array of 1024-byte child cell buffers.
 * @param totalBytes - Logical blob size as BigInt (u64, for the descriptor — resolves O-1).
 * @param octaveLevel - Octave class of child cells (0..3). Defaults to 0 (base).
 */
export function packMerkleHierarchy(
  header: Uint8Array,
  childCells: Uint8Array[],
  totalBytes: bigint,
  octaveLevel: number = CELL_MERKLE_OCTAVE_LEVEL_BASE,
): MerkleHierarchyPacked {
  if (header.length < HEADER_SIZE) {
    throw new Error(
      `Header too small: ${header.length} bytes (need ${HEADER_SIZE})`,
    );
  }
  if (childCells.length === 0) {
    throw new Error('Cannot build merkle hierarchy from empty child cell set');
  }
  if (childCells.length > 0xffff) {
    throw new Error(
      `Too many child cells: ${childCells.length} (max 65535 for u16 child_count)`,
    );
  }
  if (octaveLevel < 0 || octaveLevel > CELL_MERKLE_MAX_OCTAVE_LEVEL) {
    throw new Error(
      `Invalid octave level: ${octaveLevel} (must be 0..${CELL_MERKLE_MAX_OCTAVE_LEVEL})`,
    );
  }

  // Build merkle root over child cells.
  const merkleRoot = computeCellMerkleRoot(childCells);

  // Build anchor Cell 0 (1024 bytes, zeroed).
  const anchorCell = new Uint8Array(CELL_SIZE);

  // Copy header bytes (first 256 bytes).
  anchorCell.set(header.subarray(0, HEADER_SIZE), 0);

  // Patch cell_count (offset 86, u32 LE) = sentinel.
  const view = new DataView(anchorCell.buffer, anchorCell.byteOffset, anchorCell.byteLength);
  view.setUint32(86, ESCALATION_CELL_COUNT_SENTINEL, true);

  // Patch total_size (offset 90, u32 LE) = ESCALATION_DESCRIPTOR_SIZE (O-1, uniform for all rung≥1).
  // The authoritative logical blob size is in the descriptor's totalBytes (u64 BigInt).
  view.setUint32(90, ESCALATION_DESCRIPTOR_SIZE, true);

  // Write domainPayloadRoot (offset 224, 32 bytes).
  anchorCell.set(merkleRoot, DOMAIN_PAYLOAD_ROOT_OFFSET);

  // Write escalation descriptor at payload offset 0 (cell byte 256).
  const descOffset = HEADER_SIZE; // 256
  anchorCell[descOffset + 0] = RUNG_MERKLE_ROOTED;              // rung = 2
  anchorCell[descOffset + 1] = octaveLevel & 0xff;              // octave_level (0..3)
  view.setUint16(descOffset + 2, childCells.length & 0xffff, true); // child_count u16 LE
  view.setBigUint64(descOffset + 4, totalBytes, true);              // total_bytes u64 LE
  view.setUint32(descOffset + 12, 0, true);                         // reserved = 0

  return {
    anchorCell,
    merkleRoot,
    childCount: childCells.length,
  };
}

/**
 * Unpack (read) the rung-2 hierarchy descriptor from an anchor Cell 0.
 *
 * Reads:
 *   - The domainPayloadRoot from header offset 224.
 *   - The escalation descriptor from payload offset 0 (cell byte 256).
 *
 * Does NOT validate the child cells themselves — use `verifyCellInclusion`
 * to verify individual children.
 *
 * @param anchorCell - The 1024-byte anchor cell buffer.
 * @throws If the buffer is too small, or if the descriptor rung is not 2.
 */
export function unpackMerkleHierarchy(anchorCell: Uint8Array): MerkleHierarchyDescriptor {
  if (anchorCell.length < CELL_SIZE) {
    throw new Error(
      `Anchor cell buffer too small: ${anchorCell.length} bytes (need ${CELL_SIZE})`,
    );
  }

  const view = new DataView(anchorCell.buffer, anchorCell.byteOffset, anchorCell.byteLength);

  // Read domainPayloadRoot.
  const merkleRoot = new Uint8Array(
    anchorCell.buffer,
    anchorCell.byteOffset + DOMAIN_PAYLOAD_ROOT_OFFSET,
    DOMAIN_PAYLOAD_ROOT_SIZE,
  ).slice();

  // Read escalation descriptor at cell byte 256.
  const descOffset = HEADER_SIZE; // 256
  const rung = anchorCell[descOffset + 0]!;
  if (rung !== RUNG_MERKLE_ROOTED) {
    throw new Error(
      `Expected rung 2 (merkle-rooted hierarchy); got rung ${rung}`,
    );
  }

  const octaveLevel = anchorCell[descOffset + 1]!;
  const childCount = view.getUint16(descOffset + 2, true);
  const totalBytes = view.getBigUint64(descOffset + 4, true);

  return { merkleRoot, childCount, totalBytes, octaveLevel };
}

/**
 * Check whether an anchor cell is a rung-2 (merkle-rooted hierarchy) object.
 *
 * Checks that:
 *   1. cell_count (offset 86) == ESCALATION_CELL_COUNT_SENTINEL
 *   2. descriptor rung (payload byte 0 = cell byte 256) == 2
 *
 * This is distinct from `isEscalated` (which only checks the sentinel and
 * covers rung-1 too).
 */
export function isMerkleHierarchy(buf: Uint8Array): boolean {
  if (buf.length < CELL_SIZE) return false;
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const sentinel = view.getUint32(86, true);
  if (sentinel !== ESCALATION_CELL_COUNT_SENTINEL) return false;
  return buf[HEADER_SIZE + 0] === RUNG_MERKLE_ROOTED;
}

```
