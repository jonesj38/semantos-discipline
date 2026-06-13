---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.890311+00:00
---

# core/protocol-types/src/cell-store/types.ts

```ts
/**
 * Shared types for the cell-store module.
 *
 * The public surface (`CellRef`, `CellValue`, `PutOptions`) keeps the
 * shape it had in the pre-split `cell-store.ts` so downstream
 * consumers (semantic-fs, poker-state-machine, payment-channel) don't
 * notice the move.
 *
 * Internal types (`CellMeta`, `ContentIndexEntry`, `ChunkManifest`)
 * are exported here so per-module unit tests can construct fixtures
 * without reaching into `cell-store-facade.ts` internals.
 */

import type { CellHeader } from '../cell-header';
import { Linearity } from '../constants';

export interface CellRef {
  /** Storage key where this cell lives. */
  key: string;
  /** SHA-256 of the full 1024-byte cell. */
  cellHash: string;
  /** SHA-256 of the payload bytes (original data, not padded). */
  contentHash: string;
  /** Monotonic version counter (1-indexed). */
  version: number;
  /** Epoch ms when the cell was created. */
  timestamp: number;
  /** Linearity constraint. */
  linearity: Linearity;
}

export interface CellValue extends CellRef {
  header: CellHeader;
  payload: Uint8Array;
}

export interface PutOptions {
  linearity?: Linearity;
  ownerId?: Uint8Array;
  parentHash?: Uint8Array;
  typeHash?: Uint8Array;
  phase?: number;
  dimension?: number;
  flags?: number;
  prevStateHash?: Uint8Array;
}

/** Metadata sidecar persisted alongside each cell. */
export interface CellMeta {
  cellHash: string;
  contentHash: string;
  version: number;
  timestamp: number;
  linearity: number;
  prevCellHash: string | null;
}

/** Reverse-lookup row in `_index/content/{hash}`. */
export interface ContentIndexEntry {
  key: string;
  cellHash: string;
  version: number;
  timestamp: number;
}

/** Manifest payload of Cell 0 when data is chunked across continuation cells. */
export interface ChunkManifest {
  totalSize: number;
  chunkCount: number;
  contentHash: string;
  chunkHashes: string[];
}

```
