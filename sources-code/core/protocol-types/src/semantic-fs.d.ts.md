---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.850923+00:00
---

# core/protocol-types/src/semantic-fs.d.ts

```ts
/**
 * SemanticFS — taxonomy-aware filesystem layer.
 *
 * Maps taxonomy paths to storage paths. Validates writes against the
 * assembled taxonomy (TaxonomyResolver). Presents CellStore as a navigable
 * filesystem where paths ARE semantic positions. Navigating the filesystem
 * IS navigating the semantic space. Querying by path prefix IS querying
 * by category.
 *
 * Cross-references:
 *   proofs/lean/Semantos/Category.lean        → refines relation (prefix ordering)
 *   workbench/src/services/IntentTaxonomy.ts  → getNodeAt(), getOptionsAt()
 *   protocol-types/src/cell-store.ts          → CellStore, CellRef, CellValue, PutOptions
 *   protocol-types/src/taxonomy-resolver.ts   → TaxonomyResolver interface
 *   Phase 25D BsvOverlayAdapter               → same adapter interface, BSV backend
 */
import type { StorageAdapter } from './storage';
import { CellStore, type CellRef, type CellValue, type PutOptions } from './cell-store';
import type { TaxonomyResolver, EmbeddingProvider } from './taxonomy-resolver';
/** Tombstone flag bit — marks a cell as a redirect. */
export declare const FLAGS_TOMBSTONE = 1;
export declare class InvalidSemanticPathError extends Error {
    constructor(path: string, reason: string);
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
export declare class SemanticFS {
    private cellStore;
    private adapter;
    private taxonomy;
    private embeddings?;
    constructor(options: SemanticFsOptions);
    /**
     * Write an object at a semantic path.
     *
     * Path format: "objects/<taxonomy-path>/<object-id>"
     * Example: "objects/create/job/plumbing/job-1774"
     *
     * The taxonomy prefix (create/job/plumbing) is validated against
     * the assembled taxonomy. The object-id is freeform.
     * typeHash is automatically derived as SHA-256 of the dotted taxonomy path.
     *
     * @throws InvalidSemanticPathError if the taxonomy prefix doesn't resolve.
     */
    put(semanticPath: string, data: Uint8Array, options?: SemanticPutOptions): Promise<CellRef>;
    /**
     * Read the latest version at a semantic path.
     * Auto-resolves tombstones to follow redirect chains.
     */
    get(semanticPath: string): Promise<CellValue | null>;
    /**
     * List objects under a semantic path prefix.
     * Taxonomy-aware: includes vertically injected children.
     *
     * @param pathPrefix - e.g. "objects/create/job"
     * @param options.depth - Limit results to N levels below the prefix (1 = direct children only)
     */
    list(pathPrefix: string, options?: {
        depth?: number;
    }): Promise<CellRef[]>;
    /** Version history for an object. */
    history(semanticPath: string): Promise<CellRef[]>;
    /** Verify Merkle chain for an object. */
    verify(semanticPath: string): Promise<{
        valid: boolean;
        errors: string[];
    }>;
    /**
     * Reclassify: move an object to a new taxonomy path.
     *
     * Creates a tombstone cell at the old path with a redirect to the new path,
     * then writes the latest data at the new path with updated typeHash.
     * The version chain links across the move via the tombstone.
     */
    reclassify(oldPath: string, newPath: string, options?: {
        reason?: string;
    }): Promise<{
        tombstone: CellRef;
        newVersion: CellRef;
    }>;
    /**
     * Resolve a tombstone: follow the redirect chain to the current location.
     * Returns the original path if not a tombstone.
     */
    resolve(semanticPath: string): Promise<string>;
    /** Find objects by content hash across all semantic paths. */
    findByContent(contentHash: string): Promise<CellRef[]>;
    /**
     * Find all objects whose parent hash matches.
     * Scans metadata sidecars under objects/.
     */
    queryByParent(parentHash: string): Promise<CellRef[]>;
    /**
     * Find all objects of a given taxonomy type (by dotted taxonomy path).
     * Computes typeHash from the path and scans metadata sidecars.
     */
    queryByType(taxonomyPath: string): Promise<CellRef[]>;
    /**
     * Find all objects owned by a given ownerId.
     * Scans metadata sidecars under objects/.
     */
    queryByOwner(ownerId: Uint8Array): Promise<CellRef[]>;
    /**
     * Semantic search: find objects nearest to a natural language query
     * in embedding space.
     *
     * Uses EmbeddingProvider to embed the query, then finds taxonomy paths
     * closest to the query embedding. Returns objects under those paths,
     * ranked by embedding similarity.
     *
     * Graceful degradation: if EmbeddingProvider is not ready (no cache),
     * returns an empty array.
     */
    semanticSearch(query: string, options?: {
        limit?: number;
    }): Promise<Array<CellRef & {
        score: number;
        matchedPath: string;
    }>>;
    /** Compute typeHash as SHA-256 of dotted taxonomy path. */
    private computeTypeHash;
    /** Read a metadata sidecar. */
    private readMeta;
    /**
     * Scan all object keys and filter by a predicate on their metadata.
     * Returns CellRefs for matching objects.
     */
    private scanMetaFilter;
}
//# sourceMappingURL=semantic-fs.d.ts.map
```
