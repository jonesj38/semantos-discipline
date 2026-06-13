---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/taxonomy-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.839195+00:00
---

# core/protocol-types/src/taxonomy-resolver.ts

```ts
/**
 * TaxonomyResolver — minimal interface for taxonomy path validation.
 *
 * Decouples SemanticFS (protocol-types) from IntentTaxonomy (loom)
 * to avoid a circular package dependency. IntentTaxonomy structurally
 * satisfies this interface — no adapter code needed.
 *
 * Cross-references:
 *   workbench/src/services/IntentTaxonomy.ts  → concrete implementation
 *   proofs/lean/Semantos/Category.lean        → refines relation (prefix ordering)
 *   Phase 25C SemanticFS                      → consumer of this interface
 */

/** A node in the taxonomy tree. */
export interface TaxonomyNode {
  /** Segment id, e.g. "create", "job", "plumbing" */
  id: string;
  /** Human-readable label */
  label: string;
  /** Sub-nodes (absent or empty at leaves) */
  children?: TaxonomyNode[];
}

/**
 * Taxonomy path resolution interface.
 *
 * The `refines` relation from Category.lean (prefix ordering on TaxPath)
 * is implemented here as path segment traversal: getNodeAt(["create", "job"])
 * succeeds iff "create.job" is a valid position in the assembled taxonomy.
 */
export interface TaxonomyResolver {
  /** Walk the tree to a specific node by path segments. Returns null if any segment not found. */
  getNodeAt(path: string[]): TaxonomyNode | null;
  /** Get children at a given path. Empty path returns root domains. */
  getOptionsAt(path: string[]): TaxonomyNode[];
}

/**
 * Embedding provider interface for semantic search.
 *
 * Decouples SemanticFS from EmbeddingService. EmbeddingService structurally
 * satisfies this interface.
 *
 * Cross-references:
 *   workbench/src/services/EmbeddingService.ts → concrete implementation
 */
export interface EmbeddingProvider {
  /** Embed a raw user utterance. Returns null if no API key configured. */
  embedQuery(utterance: string): Promise<Float32Array | null>;
  /** Get the N nearest taxonomy nodes to a query vector. */
  nearest(queryVector: Float32Array, n: number): Array<{ path: string; score: number }>;
  /** Whether the cache is loaded and has at least one entry. */
  isReady(): boolean;
}

```
