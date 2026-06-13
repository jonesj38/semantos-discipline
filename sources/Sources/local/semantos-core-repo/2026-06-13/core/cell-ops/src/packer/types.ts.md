---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.830071+00:00
---

# core/cell-ops/src/packer/types.ts

```ts
/**
 * Cell-packing wire types. Pinned to the legacy `cellPacker.ts`
 * exports so consumers (cell engine, runtime services, settlement)
 * keep compiling without edits.
 */

import type { CONTINUATION_TYPE } from './constants';

export type ContinuationType =
  (typeof CONTINUATION_TYPE)[keyof typeof CONTINUATION_TYPE];

/** Continuation cell header — 8 bytes at byte 0 of each continuation cell. */
export interface ContinuationHeader {
  cellType: ContinuationType; // 1 byte
  cellIndex: number; // 2 bytes (1-based)
  totalCells: number; // 2 bytes (excludes Cell 0)
  payloadSize: number; // 2 bytes (max 1016)
  reserved: number; // 1 byte
}

export interface ContinuationCell {
  type: ContinuationType;
  /** Up to CONTINUATION_PAYLOAD_SIZE bytes (1016). */
  data: Buffer;
}

export interface MultiCellObject {
  /** Cell 0: semantic object header (256 bytes). */
  header: Buffer;
  /** Cell 0: semantic payload (up to 768 bytes). */
  payload: Buffer;
  /** Cells 1..N: ordered continuation cells. */
  continuations: ContinuationCell[];
}

export interface PackedMultiCell {
  /** Total packed bytes (N × CELL_SIZE). */
  buffer: Buffer;
  /** How many 1KB cells. */
  cellCount: number;
  /** SHA-256 of the entire packed buffer. */
  contentHash: Buffer;
}

/** BRC-74 BUMP header info, parsed just enough for routing. */
export interface BumpHeader {
  blockHeight: number;
  treeHeight: number;
  /** Byte offset where level data begins (after blockHeight + treeHeight). */
  dataOffset: number;
}

/**
 * An Atomic BEEF payload ready for cell packing.
 *
 * Expected binary layout (per BRC):
 *   [4 bytes: 0x01010101 prefix]
 *   [32 bytes: subject TXID]
 *   [N bytes: standard BEEF structure]
 */
export interface AtomicBeefPayload {
  subjectTxid: Buffer;
  rawBytes: Buffer;
}

```
