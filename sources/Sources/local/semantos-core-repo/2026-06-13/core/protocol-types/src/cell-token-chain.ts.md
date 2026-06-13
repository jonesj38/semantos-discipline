---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-token-chain.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.850655+00:00
---

# core/protocol-types/src/cell-token-chain.ts

```ts
/**
 * FileTokenChain — multi-cell PushDrop token chains.
 *
 * When a file exceeds PAYLOAD_SIZE (768 bytes), CellStore produces a manifest
 * cell + continuation cells. This module creates a single BSV transaction with
 * one PushDrop output per cell (manifest = output 0, chunks = outputs 1..N-1).
 *
 * Cross-references:
 *   cell-token.ts           → CellToken.createOutputScript / extract
 *   cell-store.ts           → CellStore chunking, continuation header format
 *   constants.ts            → CELL_SIZE, CONTINUATION_HEADER_SIZE, CONTINUATION_PAYLOAD_SIZE
 */

import {
  Transaction,
  PrivateKey,
  PublicKey,
  LockingScript,
  UnlockingScript,
} from '@bsv/sdk';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
} from './constants';
import { CellToken } from './cell-token';

export interface FileTokenChainResult {
  /** The transaction containing all PushDrop outputs. */
  tx: Transaction;
  /** Number of outputs (1 manifest + N chunks). */
  outputCount: number;
}

export interface ExtractedFile {
  /** Reassembled file data. */
  data: Uint8Array;
  /** Semantic path from the manifest token. */
  semanticPath: string;
  /** Content hash from the manifest token. */
  contentHash: Uint8Array;
  /** Owner public key. */
  ownerPubKey: PublicKey;
}

/**
 * Create a single BSV transaction with one PushDrop output per cell.
 *
 * @param cells Array of 1024-byte cells (cell 0 = manifest, rest = continuation)
 * @param semanticPath UTF-8 semantic path for overlay indexing
 * @param contentHash 32-byte SHA-256 of the original file data
 * @param ownerPubKey Owner's public key for P2PK locks
 */
export function createFileTransaction(
  cells: Uint8Array[],
  semanticPath: string,
  contentHash: Uint8Array,
  ownerPubKey: PublicKey,
): FileTokenChainResult {
  if (cells.length === 0) {
    throw new Error('At least one cell required');
  }
  for (let i = 0; i < cells.length; i++) {
    if (cells[i].length !== CELL_SIZE) {
      throw new Error(`Cell ${i} must be ${CELL_SIZE} bytes, got ${cells[i].length}`);
    }
  }

  const tx = new Transaction();

  for (let i = 0; i < cells.length; i++) {
    // Manifest cell gets the real semantic path; chunks get indexed path
    const cellPath = i === 0 ? semanticPath : `${semanticPath}.chunk.${String(i - 1).padStart(4, '0')}`;
    const script = CellToken.createOutputScript(
      cells[i],
      cellPath,
      contentHash,
      ownerPubKey,
    );
    tx.addOutput({ lockingScript: script, satoshis: 1 });
  }

  return { tx, outputCount: cells.length };
}

/**
 * Extract and reassemble file data from a transaction's PushDrop outputs.
 *
 * Parses each output, extracts cell data, and reassembles the original file
 * using CellStore's continuation header format.
 *
 * @param tx Transaction containing PushDrop outputs
 * @returns null if the transaction doesn't contain valid CellToken outputs
 */
export function extractFile(tx: Transaction): ExtractedFile | null {
  if (!tx.outputs || tx.outputs.length === 0) return null;

  // Extract manifest from output 0
  const manifest = CellToken.extract(tx.outputs[0].lockingScript);
  if (!manifest) return null;

  const manifestHeader = manifest.cellBytes.subarray(0, HEADER_SIZE);

  // Read cellCount from header to determine if multi-cell
  const dv = new DataView(
    manifestHeader.buffer,
    manifestHeader.byteOffset,
    manifestHeader.byteLength,
  );
  // cellCount is at HeaderOffsets.cellCount = 86, size 4, LE
  const cellCount = dv.getUint32(86, true);

  if (cellCount <= 1) {
    // Single cell: payload is the data (trimmed to totalSize)
    const totalSize = dv.getUint32(90, true); // HeaderOffsets.payloadTotal = 90
    const payload = manifest.cellBytes.subarray(HEADER_SIZE, HEADER_SIZE + Math.min(totalSize, PAYLOAD_SIZE));
    return {
      data: payload,
      semanticPath: manifest.semanticPath,
      contentHash: manifest.contentHash,
      ownerPubKey: manifest.ownerPubKey,
    };
  }

  // Multi-cell: manifest payload is JSON, chunks are continuation cells
  // Find end of manifest JSON in payload
  let jsonEnd = HEADER_SIZE;
  while (jsonEnd < HEADER_SIZE + PAYLOAD_SIZE && manifest.cellBytes[jsonEnd] !== 0) {
    jsonEnd++;
  }
  const manifestJson = new TextDecoder().decode(
    manifest.cellBytes.subarray(HEADER_SIZE, jsonEnd),
  );

  let manifestData: { totalSize: number; chunkCount: number };
  try {
    manifestData = JSON.parse(manifestJson);
  } catch {
    return null;
  }

  // Extract chunks from remaining outputs
  const chunkCount = manifestData.chunkCount;
  if (tx.outputs.length < 1 + chunkCount) return null;

  const chunks: Uint8Array[] = [];
  for (let i = 0; i < chunkCount; i++) {
    const chunkExtracted = CellToken.extract(tx.outputs[1 + i].lockingScript);
    if (!chunkExtracted) return null;

    const chunkCell = chunkExtracted.cellBytes;
    // Parse continuation header (first 8 bytes of the cell's payload area,
    // but for continuation cells the entire cell starts with the 8-byte header)
    // Actually, continuation cells written by CellStore have the 8-byte
    // continuation header at offset 0 of the 1024-byte cell (no 256-byte header)
    // Wait — CellStore writes continuation cells as full 1024-byte cells with
    // the 8-byte header at offset 0 and payload starting at offset 8.
    // But CellToken packs them with the first 256 bytes as "header" and next 768
    // as "payload". So the continuation header is within the first 256 bytes
    // pushed as field[0]. We need to read it from there.

    // The continuation cell format (from cell-store.ts):
    // byte 0: cellType, bytes 1-2: cellIndex (u16 LE), bytes 3-4: totalCells (u16 LE),
    // bytes 5-6: payloadSize (u16 LE), byte 7: reserved
    // Then payload starts at offset 8 (CONTINUATION_HEADER_SIZE)
    const contDv = new DataView(
      chunkCell.buffer,
      chunkCell.byteOffset,
      chunkCell.byteLength,
    );
    const payloadSize = contDv.getUint16(5, true);

    // Extract the actual chunk data from the continuation cell
    const chunkData = chunkCell.subarray(
      CONTINUATION_HEADER_SIZE,
      CONTINUATION_HEADER_SIZE + payloadSize,
    );
    chunks.push(chunkData);
  }

  // Reassemble
  const data = new Uint8Array(manifestData.totalSize);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.length;
  }

  return {
    data,
    semanticPath: manifest.semanticPath,
    contentHash: manifest.contentHash,
    ownerPubKey: manifest.ownerPubKey,
  };
}

```
