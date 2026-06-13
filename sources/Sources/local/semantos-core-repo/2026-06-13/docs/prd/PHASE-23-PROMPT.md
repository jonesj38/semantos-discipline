---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-23-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.691055+00:00
---

# Phase 23 Execution Prompt — Embedding Service & Coherence Analyzer

> Paste this prompt into a fresh session to execute Phase 23.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 13 built the hierarchical intent taxonomy — an ltree-structured type registry where `create.job.carpentry` is both a semantic object type and a classifiable intent. Phase 22 formalized that taxonomy as a poset category in Lean 4, with the refinement relation as morphisms, extension injection as a functor, and a monotonicity definition linking the categorical structure to an embedding metric.

This phase builds the **embedding infrastructure** and the **coherence analyzer** — the TypeScript services that generate vector embeddings for taxonomy nodes, compare the embedding geometry against the tree structure, and report misalignments. The coherence analyzer is the triangulation engine: it checks empirically whether the formal monotonicity property from Phase 22's Lean model holds for real embeddings.

This phase does NOT modify the intent classifier. It does NOT change classification behavior. It builds new services and CLI commands that can be used standalone. Phase 24 will wire these services into the classification pipeline.

The result of this phase: you can run `semantos taxonomy coherence` and get a report telling you exactly where your taxonomy tree disagrees with the LLM's semantic geometry, with severity ratings and governance ballot suggestions for restructuring.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRDs — your requirements and the formal model you're implementing against):
- `docs/prd/PHASE-23-PROMPT.md` — This file
- `docs/prd/PHASE-22-PROMPT.md` — Categorical model spec (what monotonicity means formally)

**Read second** (the Lean proofs from Phase 22 — the formal definitions you are checking empirically):
- `proofs/lean/Semantos/Category.lean` — `TaxPath`, `refines`, `inject`, `EmbeddingMetric`, `monotone` definitions

**Read third** (the taxonomy infrastructure you are building on):
- `packages/loom/src/services/IntentTaxonomy.ts` — Tree assembly, extension injection, path traversal, `getOptionsAt()`, `getNodeAt()`
- `packages/loom/src/services/IntentClassifier.ts` — Current classification pipeline (DO NOT MODIFY — Phase 24 does this)
- `packages/loom/src/services/intent-types.ts` — `IntentClassification`, `ClassificationResult`
- `packages/loom/src/services/FlowRegistry.ts` — Flow resolution

**Read fourth** (the taxonomy configs you will embed):
- `configs/taxonomy/core.json` — 8 root domains with descriptions and examples
- `configs/taxonomy/trades.json` — Trades extension injection
- `configs/taxonomy/generic.json` — Generic extension injection

**Read fifth** (the shell you will extend with CLI commands):
- `packages/shell/src/router.ts` — Command routing
- `packages/shell/src/shell.ts` — Shell entry point
- `packages/shell/src/types.ts` — Command types

**Read sixth** (settings and API configuration):
- `packages/loom/src/services/SettingsStore.ts` — OpenRouter API key, model ID, temperature

**Read seventh** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-23-embedding-service`. Commits as `phase-23/D23.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–22. Plus:

### 1. NOT A VECTOR DATABASE

You are computing embeddings for a **finite, known set of taxonomy nodes** (currently ~30 nodes across all extensions). The entire index fits in memory as a flat array. Do not import Pinecone, ChromaDB, Qdrant, Weaviate, pgvector, FAISS, Annoy, or any vector database. Brute-force cosine similarity over `Float32Array` is correct and fast at this scale.

### 2. NOT A RAG PIPELINE

You are NOT building retrieval-augmented generation. You are NOT building a search engine. You are building a diagnostic tool that compares two independent representations of the same type hierarchy.

### 3. EMBEDDINGS ARE CACHED AND CONTENT-HASH GATED

Embedding API calls are expensive. Every node's embedding is computed ONCE and cached to disk. Re-embedding happens only when a node's content (label + description + examples) changes, detected by SHA-256 content hash. Partial re-embedding is supported — only changed nodes are re-fetched.

### 4. THE TREE IS THE SOURCE OF TRUTH

Embeddings inform the tree; they do not replace it. The coherence analyzer produces diagnostic reports and governance suggestions. It does NOT automatically restructure the tree. Humans restructure via `govern.propose` and `govern.challenge-classification` flows.

### 5. NO COLD-START DEPENDENCY

If no embedding cache exists, `embeddingService.isReady()` returns false. All consumers of the embedding service must handle this gracefully. The taxonomy, classifier, and entire loom must function identically to Phase 13 behavior when embeddings are unavailable.

### 6. RENDERER AGNOSTICISM IS NOT OPTIONAL

`EmbeddingService.ts` and `TaxonomyCoherence.ts` are plain TypeScript in `src/services/`. They never import from React.

### 7. DO NOT MODIFY THE CLASSIFIER

`IntentClassifier.ts` is not touched in this phase. Phase 24 handles classification enhancement. This phase builds the infrastructure that Phase 24 will consume.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify Phase 22 prerequisites

```bash
# Lean categorical model exists and builds
ls proofs/lean/Semantos/Category.lean
cd proofs/lean && lake build

# Taxonomy infrastructure exists
ls packages/loom/src/services/IntentTaxonomy.ts
ls packages/loom/src/services/IntentClassifier.ts
ls configs/taxonomy/core.json
ls configs/taxonomy/trades.json
ls configs/taxonomy/generic.json

# Shell package exists
ls packages/shell/src/router.ts

# Phase 13 tests pass
bun test packages/__tests__/intent-taxonomy.test.ts

# Phase 22 tests pass
bun test packages/__tests__/phase22-gate.test.ts
```

All must pass. If anything fails, STOP.

### 0.3 Create Phase 23 branch

```bash
git checkout -b phase-23-embedding-service
```

---

## Step 1: Cosine Similarity Module (D23.1)

Create `packages/loom/src/services/cosine.ts`.

A pure, zero-dependency cosine similarity implementation.

**Requirements**:

```typescript
/**
 * Cosine similarity between two Float32Array vectors.
 * Returns 1.0 for identical vectors, 0.0 for orthogonal, -1.0 for antipodal.
 * Returns NaN if either vector has zero magnitude.
 *
 * Corresponds to Lean EmbeddingMetric.dist via: dist = 1 - cosineSimilarity.
 */
export function cosineSimilarity(a: Float32Array, b: Float32Array): number;

/**
 * Cosine distance: 1 - cosineSimilarity.
 * Ranges from 0 (identical) to 2 (antipodal).
 * This is the metric that corresponds to EmbeddingMetric.dist in Category.lean.
 */
export function cosineDistance(a: Float32Array, b: Float32Array): number;
```

- Implementation must be a single tight loop. No allocation. No dependencies.
- Throw `RangeError` if vectors have different lengths.
- Handle zero-magnitude vectors (return `NaN`).

**Commit**: `phase-23/D23.1: cosine similarity and distance — pure TypeScript, zero dependencies`

---

## Step 2: Embedding Service (D23.2)

Create `packages/loom/src/services/EmbeddingService.ts`.

**Requirements**:

- **Embedding source**: OpenRouter API (or direct OpenAI endpoint) with a configurable embedding model. Default: `openai/text-embedding-3-small` (1536 dimensions). Model ID stored in SettingsStore alongside the chat model.

- **Embedding input construction**: For each taxonomy node, build the input string:
  ```
  "{label}: {description}. Examples: {examples[0]}, {examples[1]}, {examples[2]}"
  ```
  This captures both the categorical description and natural language surface forms.

- **Content-hash gating**: Compute SHA-256 of the embedding input string. Compare against cached hash. Only re-embed if the hash differs.

- **Cache format** (`configs/taxonomy/.embeddings-cache.json`):
  ```typescript
  interface EmbeddingCache {
    modelId: string;              // embedding model used
    generatedAt: string;          // ISO timestamp of last generation
    dimension: number;            // vector dimension (e.g. 1536)
    entries: Record<string, {     // keyed by dotted node path (e.g. "create.job")
      contentHash: string;        // SHA-256 hex of embedding input string
      vector: number[];           // the embedding vector
    }>;
  }
  ```
  Cache file is `.gitignore`'d. A regeneration script is provided for CI environments.

- **API**:
  ```typescript
  export class EmbeddingService {
    /**
     * Load cache from disk and generate embeddings for any new or changed nodes.
     * Requires the taxonomy to be assembled (intentTaxonomy.hasExtensions()).
     * No-ops if no API key configured (isReady() will return false).
     */
    async initialize(): Promise<void>;

    /** Get the cached embedding for a dotted node path. Null if not embedded. */
    getEmbedding(nodePath: string): Float32Array | null;

    /**
     * Cosine similarity between two node paths.
     * Returns NaN if either path has no cached embedding.
     */
    similarity(pathA: string, pathB: string): number;

    /**
     * Cosine similarity between a node path and a raw query vector.
     * Used by the classifier (Phase 24) to compare user utterance against nodes.
     */
    similarityToQuery(nodePath: string, queryVector: Float32Array): number;

    /**
     * Get the N nearest taxonomy nodes to a query vector.
     * Brute-force scan — O(n) where n = number of embedded nodes.
     */
    nearest(queryVector: Float32Array, n: number): Array<{ path: string; score: number }>;

    /**
     * Embed a raw text string (e.g. user utterance).
     * Calls the embedding API. Does NOT cache the result (utterances are ephemeral).
     * Returns null if no API key configured.
     */
    async embedQuery(utterance: string): Promise<Float32Array | null>;

    /** Whether the cache is loaded and has at least one entry. */
    isReady(): boolean;

    /** Force re-embed all nodes, ignoring content hashes. */
    async regenerate(): Promise<void>;

    /** Get cache statistics for diagnostics. */
    getStats(): { totalNodes: number; cachedNodes: number; staleNodes: number; modelId: string | null };
  }

  export const embeddingService = new EmbeddingService();
  ```

- **API call implementation**:
  - Use `fetch()` to call the OpenRouter embedding endpoint.
  - Batch node embeddings where the API supports it (OpenAI embedding API accepts array input).
  - Rate limit: max 3 concurrent requests, exponential backoff on 429.
  - On API failure: log warning, skip the node, leave cache entry as stale. Never crash.

- **No external dependencies.** No vector DB libraries. No ML libraries. SHA-256 via `crypto.subtle` (browser) or `crypto` (Node/Bun).

**Commit**: `phase-23/D23.2: embedding service with cache, content-hash gating, batch API, and nearest-neighbor`

---

## Step 3: Tree Distance (D23.3)

Create `packages/loom/src/services/tree-distance.ts`.

**Requirements**:

```typescript
/**
 * Compute the tree distance between two nodes in the taxonomy tree.
 * Distance = number of edges on the shortest path.
 *
 * Algorithm: find the lowest common ancestor (LCA), then
 * distance = (depth(a) - depth(lca)) + (depth(b) - depth(lca)).
 *
 * Examples:
 *   treeDistance(["create", "job"], ["create", "quote"]) = 2  (sibling)
 *   treeDistance(["create", "job"], ["create"]) = 1           (parent)
 *   treeDistance(["create", "job"], ["navigate", "objects"]) = 4  (cross-domain)
 *   treeDistance(["create"], ["create"]) = 0                  (identity)
 *
 * Corresponds to the graph distance in the poset category from Category.lean.
 */
export function treeDistance(a: string[], b: string[]): number;

/**
 * Find the lowest common ancestor of two paths.
 * Returns the longest common prefix.
 */
export function lowestCommonAncestor(a: string[], b: string[]): string[];
```

- Pure function. No dependencies on IntentTaxonomy (works on raw path arrays).
- LCA is the longest common prefix of the two path arrays.

**Commit**: `phase-23/D23.3: tree distance and LCA — pure functions on path arrays`

---

## Step 4: Coherence Analyzer (D23.4)

Create `packages/loom/src/services/TaxonomyCoherence.ts`.

This is the triangulation engine.

**Requirements**:

- **Inputs**: The assembled taxonomy tree (from `intentTaxonomy`) and the embedding cache (from `embeddingService`).

- **Analysis**: Compare tree distances against embedding distances for every pair of nodes. Check the monotonicity property from Phase 22's Lean model.

- **Report types**:
  ```typescript
  export interface CoherenceReport {
    timestamp: string;
    totalNodes: number;
    totalPairs: number;

    /** Fraction of parent-child pairs where the child is closer to its parent
        in embedding space than to any other node at the parent's depth.
        Corresponds to `monotone` in Category.lean. */
    monotonicity: number;

    /** Fraction of sibling pairs where embedding distance < cross-branch distance. */
    siblingCohesion: number;

    /** Nodes whose nearest embedding neighbor is NOT their tree-nearest neighbor. */
    misalignments: Misalignment[];

    /** Suggested taxonomy restructuring actions. */
    suggestions: CoherenceSuggestion[];
  }

  export interface Misalignment {
    nodePath: string;
    treeNearest: string;
    embeddingNearest: string;
    treeDistance: number;
    embeddingDistance: number;
    severity: 'info' | 'warning' | 'critical';
  }

  export interface CoherenceSuggestion {
    type: 'move' | 'merge' | 'split' | 'rename';
    nodePath: string;
    suggestedParent?: string;
    reason: string;
    governanceAction?: {
      flowId: string;
      payload: Record<string, unknown>;
    };
  }
  ```

- **Monotonicity check**: For each node `a` with parent `b`, find all nodes `c` at the same depth as `b` where `c` is NOT an ancestor of `a`. Check that `embeddingDistance(a, b) ≤ embeddingDistance(a, c)`. The `monotonicity` score is the fraction of nodes where this holds.

- **Sibling cohesion check**: For each pair of siblings under the same parent, check that their mutual embedding distance is less than the average cross-branch distance at that depth. The `siblingCohesion` score is the fraction of sibling pairs where this holds.

- **Severity levels**:
  - `info`: Embedding nearest differs from tree nearest but is within the same domain (same level-1 branch). The embedding sees finer distinctions.
  - `warning`: Embedding nearest is in a different subtree at the same depth but same domain. Possible miscategorization.
  - `critical`: Embedding nearest is in a completely different domain. Almost certainly wrong placement.

- **Suggestion generation**:
  - `critical` → `move` suggestion with `govern.challenge-classification` ballot
  - `warning` where two siblings are closer in embedding space to each other than either is to their parent → `merge` suggestion
  - `warning` where a node's children form two distinct clusters (k-means with k=2 on embeddings, check silhouette score) → `split` suggestion
  - `info` where a node's description has low cosine similarity to its own embedding → `rename` suggestion

- **API**:
  ```typescript
  export class TaxonomyCoherence {
    /**
     * Run full coherence analysis. Requires embeddingService.isReady().
     * Returns null if embeddings are unavailable.
     */
    analyze(): CoherenceReport | null;

    /**
     * Check monotonicity for a single node against all alternatives at parent depth.
     * Useful for incremental validation after taxonomy edits.
     */
    checkNode(nodePath: string[]): Misalignment | null;
  }

  export const taxonomyCoherence = new TaxonomyCoherence();
  ```

**Commit**: `phase-23/D23.4: coherence analyzer with monotonicity, sibling cohesion, misalignment detection, governance suggestions`

---

## Step 5: CLI Commands (D23.5)

Create `packages/shell/src/taxonomy.ts` and register commands in `packages/shell/src/router.ts`.

**Requirements**:

```bash
# Generate or regenerate embeddings for the assembled taxonomy
semantos taxonomy embed [--force]
# --force: ignore content hashes, re-embed everything
# Output: "Embedded 28 nodes (3 new, 2 updated, 23 cached). Model: openai/text-embedding-3-small."

# Run coherence analysis and print report
semantos taxonomy coherence [--format json|table]
# Default: table format with colored severity indicators
# json: machine-readable CoherenceReport

# Show embedding distance and tree distance between two nodes
semantos taxonomy distance <pathA> <pathB>
# Example: semantos taxonomy distance create.job create.quote
# Output: "Tree distance: 2 (siblings). Embedding distance: 0.234. Cosine similarity: 0.766."

# Show nearest N taxonomy nodes to a natural language query
semantos taxonomy nearest "<utterance>" [--n 5]
# Example: semantos taxonomy nearest "I need a plumber" --n 3
# Output: ranked list with scores

# Run full monotonicity validation
semantos taxonomy validate
# Output: per-subtree pass/fail with overall score
# Exit code 0 if monotonicity > 0.80, exit code 1 otherwise
```

- All commands work standalone (no running loom needed). They load taxonomy configs directly.
- Commands that need embeddings print a clear message if no cache exists ("Run `semantos taxonomy embed` first.").
- `taxonomy validate` exit code enables CI integration (fail the build if taxonomy is incoherent).

**Commit**: `phase-23/D23.5: taxonomy CLI — embed, coherence, distance, nearest, validate`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase23-gate.test.ts`.

### Cosine Math Tests (T1–T4)

```typescript
describe("Phase 23 — Cosine Similarity", () => {
  // T1: cosineSimilarity of identical vectors = 1.0
  // T2: cosineSimilarity of orthogonal vectors = 0.0
  // T3: cosineSimilarity is commutative: sim(a,b) = sim(b,a)
  // T4: cosineDistance = 1 - cosineSimilarity
});
```

### Tree Distance Tests (T5–T8)

```typescript
describe("Phase 23 — Tree Distance", () => {
  // T5: sibling distance = 2 (["create","job"] ↔ ["create","quote"])
  // T6: parent distance = 1 (["create","job"] ↔ ["create"])
  // T7: cross-domain distance = depth(a) + depth(b) (["create","job"] ↔ ["navigate","objects"] = 4)
  // T8: self distance = 0
});
```

### Embedding Service Tests (T9–T14)

```typescript
describe("Phase 23 — Embedding Service", () => {
  // T9: isReady() returns false before initialize()
  // T10: content hash changes when description changes
  // T11: content hash stable when description unchanged
  // T12: cache round-trip: write cache → read cache → vectors match (Float32 precision)
  // T13: nearest() returns results sorted by descending similarity
  // T14: getStats() reflects correct counts
});
```

### Coherence Analyzer Tests (T15–T20)

```typescript
describe("Phase 23 — Coherence Analyzer", () => {
  // T15: monotonicity = 1.0 for mock embeddings where parent is always nearest
  // T16: monotonicity < 1.0 for deliberately misaligned mock embeddings
  // T17: critical misalignment detected when node's embedding nearest is in different domain
  // T18: warning misalignment when nearest is same domain different subtree
  // T19: governance suggestion includes flowId "challenge-classification" for critical
  // T20: analyze() returns null when embeddings unavailable
});
```

### Anti-Lock Tests (T21–T24)

```typescript
describe("Phase 23 — Anti-Lock", () => {
  // T21: no React imports in EmbeddingService, TaxonomyCoherence, cosine, tree-distance
  // T22: no vector DB dependencies in package.json (pinecone, chromadb, qdrant, etc.)
  // T23: IntentClassifier.ts is UNMODIFIED from Phase 13 (git diff shows no changes)
  // T24: IntentTaxonomy.ts is UNMODIFIED from Phase 13
});
```

**Commit**: `phase-23/T1-T24: gate tests — cosine, tree distance, embedding service, coherence, anti-lock`

---

## Step 7: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Adversarial review of every new file
2. Check that EmbeddingService handles API rate limits gracefully (backoff, partial cache)
3. Check that coherence analyzer handles degenerate cases (single node, no children, empty extension, node with no examples)
4. Check that SHA-256 hashing is consistent between Node/Bun `crypto` and browser `crypto.subtle`
5. Check that `Float32Array` serialization/deserialization in cache preserves precision (JSON `number[]` round-trips correctly)
6. Check that cache format is forward-compatible (new nodes added without re-embedding existing nodes)
7. Check that CLI commands exit cleanly on Ctrl-C and don't leave partial cache files
8. Verify that `embeddingService.isReady() === false` path is tested in every consumer
9. Check that monotonicity validation produces actionable output for governance flows
10. Write errata doc as `docs/prd/PHASE-23-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/loom/src/services/cosine.ts` exists with `cosineSimilarity` and `cosineDistance`
- [ ] `packages/loom/src/services/EmbeddingService.ts` exists with cache, batch API, nearest-neighbor
- [ ] `packages/loom/src/services/tree-distance.ts` exists with `treeDistance` and `lowestCommonAncestor`
- [ ] `packages/loom/src/services/TaxonomyCoherence.ts` exists with `analyze()` and `checkNode()`
- [ ] `packages/shell/src/taxonomy.ts` exists with 5 CLI commands registered in router
- [ ] `configs/taxonomy/.embeddings-cache.json` schema documented (file itself is `.gitignore`'d)
- [ ] `IntentClassifier.ts` is UNMODIFIED
- [ ] `IntentTaxonomy.ts` is UNMODIFIED
- [ ] All commands work without a running loom
- [ ] `taxonomy validate` returns exit code 0/1 for CI
- [ ] Tests T1–T24 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in new services
- [ ] No vector DB dependencies in package.json
- [ ] Errata sprint complete with `docs/prd/PHASE-23-ERRATA.md`
- [ ] All commits follow `phase-23/D23.N:` naming convention
- [ ] Branch is `phase-23-embedding-service`

---

## What NOT to Do

1. Do NOT import a vector database
2. Do NOT build a RAG pipeline
3. Do NOT modify `IntentClassifier.ts` or `IntentTaxonomy.ts`
4. Do NOT make embeddings a hard dependency for any existing feature
5. Do NOT store embedding vectors on-chain or in cells
6. Do NOT import from React in service files
7. Do NOT use `any` casts to avoid typing the embedding API response
8. Do NOT cache user utterance embeddings (they are ephemeral)
9. Do NOT auto-restructure the taxonomy based on coherence results
