---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.865486+00:00
---

# core/protocol-types/src/semantic-fs/types.ts

```ts
/**
 * Shared types + constants for the semantic-fs module.
 *
 * The public surface (`ParsedSemanticPath`, `SemanticFsOptions`,
 * `SemanticPutOptions`, `InvalidSemanticPathError`, `FLAGS_TOMBSTONE`)
 * keeps the shape it had in the pre-split `semantic-fs.ts` so
 * downstream consumers (runtime/shell, etc.) don't notice the move.
 */

import type { CellStore } from '../cell-store/cell-store-facade';
import type { PutOptions } from '../cell-store/types';
import type { StorageAdapter } from '../storage';
import type { EmbeddingProvider, TaxonomyResolver } from '../taxonomy-resolver';

/** Top-level prefixes valid in semantic paths. */
export const VALID_PREFIXES = new Set([
  'objects',
  'policies',
  'identity',
  'taxonomy',
  'governance',
  'evidence',
]);

/** Tombstone flag bit — marks a cell as a redirect. */
export const FLAGS_TOMBSTONE = 0x0001;

/** Maximum tombstone redirect hops before erroring. */
export const MAX_REDIRECT_HOPS = 10;

export class InvalidSemanticPathError extends Error {
  constructor(path: string, reason: string) {
    super(`Invalid semantic path "${path}": ${reason}`);
    this.name = 'InvalidSemanticPathError';
  }
}

export interface ParsedSemanticPath {
  /** Top-level prefix: "objects", "policies", etc. */
  prefix: string;
  /** Taxonomy path segments, e.g. ["create", "job", "plumbing"] */
  taxonomyPath: string[];
  /** Object ID (freeform), e.g. "job-1774" */
  objectId: string | null;
  /** Sub-resource path after the object ID, e.g. ["evidence", "0001-patch.json"] */
  subResource: string[];
  /** Full storage key for CellStore. */
  storageKey: string;
}

export interface SemanticFsOptions {
  /** The cell store to persist through. */
  cellStore: CellStore;
  /** Raw storage adapter for list/scan operations. */
  adapter: StorageAdapter;
  /** The assembled taxonomy for path validation. */
  taxonomy: TaxonomyResolver;
  /** Embedding provider for semantic search (optional). */
  embeddings?: EmbeddingProvider;
}

export interface SemanticPutOptions extends Omit<PutOptions, 'typeHash'> {
  /** Override the reason for a reclassification. */
  reason?: string;
}

/** Metadata sidecar format (matches CellStore .meta). */
export interface CellMeta {
  cellHash: string;
  contentHash: string;
  version: number;
  timestamp: number;
  linearity: number;
  prevCellHash: string | null;
}

```
