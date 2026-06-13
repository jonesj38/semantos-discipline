---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/swarm-file.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.842140+00:00
---

# core/protocol-types/src/swarm-file.ts

```ts
/**
 * Swarm file ⇄ data-cells + per-cell inclusion proofs.
 *
 * Companion to `swarm-manifest.ts`. These helpers are NOT part of the
 * Zig-shared canonical surface (the brain never chunks files) — they are the
 * TS seeder/leecher side: turn a file into the fixed-size data cells a manifest
 * commits to, generate a merkle inclusion proof for any one cell, and verify a
 * fetched cell against the manifest's root.
 *
 * Verification is proof-based (`verifyCellInclusion`), so a leecher needs only
 * the 32-byte `merkleRoot` from the manifest plus a per-cell proof — never the
 * full leaf-hash vector. This is what keeps the manifest a single tiny cell at
 * any file size.
 *
 * Substrate: pure wire — depends only on @semantos/cell-ops + local cell-store
 * helpers. MUST NOT import from cartridges/ or runtime/.
 */

import {
  cellMerkleSha256 as sha256,
  computeLeafHashes,
  generateCellInclusionProof,
  verifyCellInclusion,
  type CellMerkleProof,
} from '@semantos/cell-ops/packer';
import { CONTINUATION_PAYLOAD_SIZE } from './constants';
import { chunkData, reassembleChunks } from './cell-store/cell-chunker';
import { packContinuationCell, unpackContinuationCell } from './cell-store/cell-packer';
import {
  buildManifest,
  computeInfohash,
  encodeManifestCell,
  type SwarmManifest,
} from './swarm-manifest';

export type { CellMerkleProof };

/** Continuation-header cellType byte stamped on swarm data cells ('S'). */
export const SWARM_DATA_CELL_TYPE = 0x53 as const;

/** Result of turning a file into its data cells. */
export interface DataCellPlan {
  /** The full 1024-byte data (continuation) cells, in order. */
  dataCells: Uint8Array[];
  /** Payload bytes carried per cell. */
  chunkSize: number;
  /** Original file size in bytes. */
  totalSize: number;
}

/**
 * Chunk a file into swarm data cells. Each cell is a continuation cell carrying
 * up to `CONTINUATION_PAYLOAD_SIZE` (1016) payload bytes; the final cell may be
 * shorter.
 */
export function fileToDataCells(fileBytes: Uint8Array): DataCellPlan {
  const plan = chunkData(fileBytes, CONTINUATION_PAYLOAD_SIZE);
  const total = plan.chunks.length;
  const dataCells = plan.chunks.map((chunk, i) =>
    packContinuationCell(SWARM_DATA_CELL_TYPE, i + 1, total, chunk),
  );
  return { dataCells, chunkSize: CONTINUATION_PAYLOAD_SIZE, totalSize: fileBytes.length };
}

/** Reassemble the original file bytes from its data cells (order matters). */
export function dataCellsToFile(dataCells: Uint8Array[], totalSize: number): Uint8Array {
  const chunks = dataCells.map(c => unpackContinuationCell(c).chunk);
  return reassembleChunks(chunks, totalSize);
}

/** Everything a seeder needs after ingesting a file. */
export interface PublishedFile {
  manifest: SwarmManifest;
  /** 32-byte infohash. */
  infohash: Uint8Array;
  /** The encoded 1024-byte swarm.manifest cell. */
  manifestCell: Uint8Array;
  /** The file's data cells. */
  dataCells: Uint8Array[];
  /** Per-cell leaf hashes (sha256 of each 1024-byte cell). */
  leafHashes: Uint8Array[];
}

/**
 * Ingest a file: chunk it, build the manifest (merkle root + content hash),
 * derive the infohash, and encode the manifest cell.
 */
export function publishFile(fileBytes: Uint8Array, semanticPath: string): PublishedFile {
  const contentHash = sha256(fileBytes);
  const { dataCells, chunkSize, totalSize } = fileToDataCells(fileBytes);
  const manifest = buildManifest({ dataCells, semanticPath, contentHash, totalSize, chunkSize });
  return {
    manifest,
    infohash: computeInfohash(manifest),
    manifestCell: encodeManifestCell(manifest),
    dataCells,
    leafHashes: computeLeafHashes(dataCells),
  };
}

/** Generate a merkle inclusion proof for the data cell at `cellIndex`. */
export function generateDataCellProof(dataCells: Uint8Array[], cellIndex: number): CellMerkleProof {
  return generateCellInclusionProof(dataCells, cellIndex);
}

/**
 * Verify a fetched data cell against the manifest's merkle root using a per-cell
 * inclusion proof. Returns false on any mismatch (wrong index, bad bytes, bad
 * proof) — a leecher drops + re-fetches and bans the serving peer.
 */
export function verifyDataCell(
  manifest: SwarmManifest,
  cellIndex: number,
  cellBytes: Uint8Array,
  proof: CellMerkleProof,
): boolean {
  if (proof.leafIndex !== cellIndex) return false;
  if (cellIndex < 0 || cellIndex >= manifest.totalCells) return false;
  return verifyCellInclusion(cellBytes, proof, manifest.merkleRoot);
}

```
