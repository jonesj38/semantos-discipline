---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/semantic-fs-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.866570+00:00
---

# core/protocol-types/src/semantic-fs/semantic-fs-facade.ts

```ts
/**
 * SemanticFS facade — orchestrates the semantic-fs sub-modules.
 *
 * Public API matches the pre-split class so consumers compile
 * unchanged:
 *
 *   put · get · list · history · verify · reclassify · resolve ·
 *   findByContent · queryByParent · queryByType · queryByOwner ·
 *   semanticSearch
 *
 * Each method delegates to a focused helper. Keep this file under the
 * 220-LOC ceiling the prompt sets — heavy lifting belongs in the
 * helpers, not here.
 */

import type { StorageAdapter } from '../storage';
import type { CellStore } from '../cell-store/cell-store-facade';
import type { CellRef, CellValue } from '../cell-store/types';
import type { EmbeddingProvider, TaxonomyResolver } from '../taxonomy-resolver';
import { listCellKeys, metaRefsFor } from './metadata-scanner';
import { reclassifyCell, type ReclassifyResult } from './cell-reclassifier';
import { resolvePath } from './tombstone-resolver';
import {
  queryByOwner as queryByOwnerHandler,
  queryByParent as queryByParentHandler,
  queryByType as queryByTypeHandler,
} from './semantic-queries';
import {
  searchEmbedded,
  type SemanticSearchHit,
  type SemanticSearchOptions,
} from './semantic-search';
import { parseSemanticPath } from './semantic-path-parser';
import { validateForWrite } from './semantic-path-validator';
import { computeTypeHash } from './type-hasher';
import type { SemanticFsOptions, SemanticPutOptions } from './types';

export class SemanticFS {
  private cellStore: CellStore;
  private adapter: StorageAdapter;
  private taxonomy: TaxonomyResolver;
  private embeddings?: EmbeddingProvider;

  constructor(options: SemanticFsOptions) {
    this.cellStore = options.cellStore;
    this.adapter = options.adapter;
    this.taxonomy = options.taxonomy;
    this.embeddings = options.embeddings;
  }

  /**
   * Write an object at a semantic path. Path format:
   * "objects/<taxonomy-path>/<object-id>". The taxonomy prefix is
   * validated against the assembled taxonomy; the object-id is
   * freeform. typeHash is auto-derived from the dotted taxonomy path.
   */
  async put(
    semanticPath: string,
    data: Uint8Array,
    options?: SemanticPutOptions,
  ): Promise<CellRef> {
    const parsed = validateForWrite(semanticPath, this.taxonomy);
    const typeHash = await computeTypeHash(parsed.taxonomyPath);
    return this.cellStore.put(parsed.storageKey, data, { ...options, typeHash });
  }

  /** Read latest version at a semantic path, auto-resolving tombstones. */
  async get(semanticPath: string): Promise<CellValue | null> {
    const resolved = await this.resolve(semanticPath);
    return this.cellStore.get(resolved);
  }

  /**
   * List objects under a semantic path prefix. Taxonomy-aware: includes
   * vertically injected children. `options.depth` limits to N levels
   * below the prefix (1 = direct children only).
   */
  async list(
    pathPrefix: string,
    options?: { depth?: number },
  ): Promise<CellRef[]> {
    const keys = await listCellKeys(this.adapter, pathPrefix, options);
    return metaRefsFor(this.adapter, keys);
  }

  /** Version history for an object. */
  async history(semanticPath: string): Promise<CellRef[]> {
    const parsed = parseSemanticPath(semanticPath, this.taxonomy);
    return this.cellStore.history(parsed.storageKey);
  }

  /** Verify Merkle chain for an object. */
  async verify(semanticPath: string): Promise<{ valid: boolean; errors: string[] }> {
    const parsed = parseSemanticPath(semanticPath, this.taxonomy);
    return this.cellStore.verify(parsed.storageKey);
  }

  /**
   * Reclassify: move an object to a new taxonomy path. Creates a
   * tombstone at the old path that redirects to the new one, then
   * writes the latest data at the new path with prevStateHash linking
   * back to the tombstone.
   */
  async reclassify(
    oldPath: string,
    newPath: string,
    _options?: { reason?: string },
  ): Promise<ReclassifyResult> {
    return reclassifyCell(this.cellStore, this.taxonomy, oldPath, newPath);
  }

  /** Follow tombstone redirects to the current location. */
  async resolve(semanticPath: string): Promise<string> {
    return resolvePath(this.adapter, semanticPath);
  }

  /** Find objects by content hash across all semantic paths. */
  async findByContent(contentHash: string): Promise<CellRef[]> {
    return this.cellStore.findByContent(contentHash);
  }

  // ── Semantic Queries ─────────────────────────────────────────────

  async queryByParent(parentHash: string): Promise<CellRef[]> {
    return queryByParentHandler(this.adapter, parentHash);
  }

  async queryByType(taxonomyPath: string): Promise<CellRef[]> {
    return queryByTypeHandler(this.adapter, taxonomyPath);
  }

  async queryByOwner(ownerId: Uint8Array): Promise<CellRef[]> {
    return queryByOwnerHandler(this.adapter, ownerId);
  }

  // ── Semantic Search ──────────────────────────────────────────────

  /**
   * Find objects nearest to a natural-language query in embedding
   * space. Returns an empty array when no embedding provider is
   * available (constructor-time `embeddings`, or the bound
   * `embeddingPort`).
   */
  async semanticSearch(
    query: string,
    options?: { limit?: number },
  ): Promise<SemanticSearchHit[]> {
    const searchOpts: SemanticSearchOptions = {
      ...(options?.limit !== undefined ? { limit: options.limit } : {}),
      embeddings: this.embeddings,
    };
    return searchEmbedded(this.adapter, query, searchOpts);
  }
}

```
