---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/EmbeddingService.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.093891+00:00
---

# runtime/services/src/services/EmbeddingService.ts

```ts
/**
 * EmbeddingService — generates and caches vector embeddings for taxonomy nodes.
 *
 * Embeddings are computed via OpenRouter's embedding API (default model:
 * openai/text-embedding-3-small, 1536 dimensions). Results are cached to disk
 * with SHA-256 content-hash gating — only changed nodes are re-embedded.
 *
 * This is NOT a vector database. The entire index (~30 nodes) fits in memory
 * as a flat map of Float32Arrays. Nearest-neighbor is brute-force O(n).
 *
 * Corresponds to EmbeddingMetric in proofs/lean/Semantos/Category.lean.
 */

import { createHash } from 'crypto';
import { cosineSimilarity } from './cosine';
import type { IntentTaxonomyNode } from './IntentTaxonomy';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';

// ── Types ──────────────────────────────────────────────────

interface EmbeddingCacheEntry {
  contentHash: string;
  vector: number[];
}

interface EmbeddingCache {
  modelId: string;
  generatedAt: string;
  dimension: number;
  entries: Record<string, EmbeddingCacheEntry>;
}

interface TaxonomyNodeInfo {
  path: string;        // dotted path, e.g. "create.job"
  segments: string[];  // path segments, e.g. ["create", "job"]
  label: string;
  description: string;
  examples: string[];
}

// ── Constants ──────────────────────────────────────────────

const DEFAULT_EMBEDDING_MODEL = 'openai/text-embedding-3-small';
const OPENROUTER_EMBEDDINGS_URL = 'https://openrouter.ai/api/v1/embeddings';
const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;

// ── Service ────────────────────────────────────────────────

export class EmbeddingService {
  private vectors = new Map<string, Float32Array>();
  private contentHashes = new Map<string, string>();
  private modelId: string = DEFAULT_EMBEDDING_MODEL;
  private dimension = 0;
  private ready = false;

  /** Lazy references — set via setters to avoid circular imports. */
  private _getApiKey: (() => string | null) | null = null;
  private _getNodes: (() => TaxonomyNodeInfo[]) | null = null;
  private _storage: StorageAdapter | null = null;

  private static readonly CACHE_KEY = 'taxonomy/.embeddings-cache.json';

  /** Set the API key provider (SettingsStore or env var). */
  setApiKeyProvider(provider: () => string | null): void {
    this._getApiKey = provider;
  }

  /** Set the taxonomy node provider (walks the assembled tree). */
  setNodeProvider(provider: () => TaxonomyNodeInfo[]): void {
    this._getNodes = provider;
  }

  /** Set the storage adapter for cache persistence. Without one, cache is in-memory only. */
  setStorageAdapter(adapter: StorageAdapter): void {
    this._storage = adapter;
  }

  /**
   * Load cache from disk and generate embeddings for any new or changed nodes.
   * No-ops if no API key configured (isReady() will return false).
   */
  async initialize(): Promise<void> {
    const apiKey = this.getApiKey();
    if (!apiKey) return;

    const nodes = this.getNodes();
    if (nodes.length === 0) return;

    // Load existing cache
    const cache = await this.loadCache();
    if (cache && cache.modelId !== this.modelId) {
      // Model changed — invalidate entire cache
      this.vectors.clear();
      this.contentHashes.clear();
    } else if (cache) {
      // Restore cached vectors
      for (const [path, entry] of Object.entries(cache.entries)) {
        this.vectors.set(path, new Float32Array(entry.vector));
        this.contentHashes.set(path, entry.contentHash);
      }
      this.dimension = cache.dimension;
    }

    // Find nodes that need (re-)embedding
    const toEmbed: { path: string; input: string }[] = [];
    for (const node of nodes) {
      const input = buildEmbeddingInput(node);
      const hash = sha256(input);
      if (this.contentHashes.get(node.path) !== hash) {
        toEmbed.push({ path: node.path, input });
        this.contentHashes.set(node.path, hash);
      }
    }

    // Batch embed changed nodes
    if (toEmbed.length > 0) {
      const vectors = await this.batchEmbed(
        toEmbed.map(e => e.input),
        apiKey,
      );
      if (vectors) {
        for (let i = 0; i < toEmbed.length; i++) {
          if (vectors[i]) {
            this.vectors.set(toEmbed[i].path, vectors[i]);
            if (this.dimension === 0) this.dimension = vectors[i].length;
          }
        }
        await this.saveCache();
      }
    }

    this.ready = this.vectors.size > 0;
  }

  /** Get the cached embedding for a dotted node path. Null if not embedded. */
  getEmbedding(nodePath: string): Float32Array | null {
    return this.vectors.get(nodePath) ?? null;
  }

  /**
   * Cosine similarity between two node paths.
   * Returns NaN if either path has no cached embedding.
   */
  similarity(pathA: string, pathB: string): number {
    const a = this.vectors.get(pathA);
    const b = this.vectors.get(pathB);
    if (!a || !b) return NaN;
    return cosineSimilarity(a, b);
  }

  /**
   * Cosine similarity between a node path and a raw query vector.
   */
  similarityToQuery(nodePath: string, queryVector: Float32Array): number {
    const a = this.vectors.get(nodePath);
    if (!a) return NaN;
    return cosineSimilarity(a, queryVector);
  }

  /**
   * Get the N nearest taxonomy nodes to a query vector.
   * Brute-force scan — O(n) where n = number of embedded nodes.
   */
  nearest(queryVector: Float32Array, n: number): Array<{ path: string; score: number }> {
    const results: Array<{ path: string; score: number }> = [];
    for (const [path, vec] of this.vectors) {
      const score = cosineSimilarity(vec, queryVector);
      results.push({ path, score });
    }
    results.sort((a, b) => b.score - a.score);
    return results.slice(0, n);
  }

  /**
   * Embed a raw text string (e.g. user utterance).
   * Calls the embedding API. Does NOT cache the result.
   * Returns null if no API key configured.
   */
  async embedQuery(utterance: string): Promise<Float32Array | null> {
    const apiKey = this.getApiKey();
    if (!apiKey) return null;

    const vectors = await this.batchEmbed([utterance], apiKey);
    return vectors ? vectors[0] ?? null : null;
  }

  /** Whether the cache is loaded and has at least one entry. */
  isReady(): boolean {
    return this.ready;
  }

  /** Force re-embed all nodes, ignoring content hashes. */
  async regenerate(): Promise<void> {
    const apiKey = this.getApiKey();
    if (!apiKey) return;

    const nodes = this.getNodes();
    if (nodes.length === 0) return;

    const inputs = nodes.map(n => buildEmbeddingInput(n));
    const hashes = inputs.map(i => sha256(i));

    const vectors = await this.batchEmbed(inputs, apiKey);
    if (vectors) {
      this.vectors.clear();
      this.contentHashes.clear();
      for (let i = 0; i < nodes.length; i++) {
        if (vectors[i]) {
          this.vectors.set(nodes[i].path, vectors[i]);
          this.contentHashes.set(nodes[i].path, hashes[i]);
          if (this.dimension === 0) this.dimension = vectors[i].length;
        }
      }
      this.saveCache();
      this.ready = this.vectors.size > 0;
    }
  }

  /** Get cache statistics for diagnostics. */
  getStats(): { totalNodes: number; cachedNodes: number; staleNodes: number; modelId: string | null } {
    const nodes = this._getNodes ? this._getNodes() : [];
    let stale = 0;
    for (const node of nodes) {
      const input = buildEmbeddingInput(node);
      const hash = sha256(input);
      if (this.contentHashes.get(node.path) !== hash) stale++;
    }
    return {
      totalNodes: nodes.length,
      cachedNodes: this.vectors.size,
      staleNodes: stale,
      modelId: this.ready ? this.modelId : null,
    };
  }

  /** Get all embedded node paths. */
  getEmbeddedPaths(): string[] {
    return [...this.vectors.keys()];
  }

  // ── Private ──────────────────────────────────────────

  private getApiKey(): string | null {
    if (this._getApiKey) return this._getApiKey();
    return process.env.OPENROUTER_API_KEY ?? null;
  }

  private getNodes(): TaxonomyNodeInfo[] {
    if (this._getNodes) return this._getNodes();
    return [];
  }

  private async loadCache(): Promise<EmbeddingCache | null> {
    if (!this._storage) return null;
    try {
      const data = await this._storage.read(EmbeddingService.CACHE_KEY);
      if (!data) return null;
      const raw = new TextDecoder().decode(data);
      return JSON.parse(raw) as EmbeddingCache;
    } catch {
      return null;
    }
  }

  private async saveCache(): Promise<void> {
    if (!this._storage) return;
    const cache: EmbeddingCache = {
      modelId: this.modelId,
      generatedAt: new Date().toISOString(),
      dimension: this.dimension,
      entries: {},
    };
    for (const [nodePath, vec] of this.vectors) {
      cache.entries[nodePath] = {
        contentHash: this.contentHashes.get(nodePath) ?? '',
        vector: Array.from(vec),
      };
    }
    try {
      const bytes = new TextEncoder().encode(JSON.stringify(cache, null, 2));
      await this._storage.write(EmbeddingService.CACHE_KEY, bytes);
    } catch {
      // Cache write failed — not fatal
    }
  }

  /**
   * Call the OpenRouter embedding API for a batch of inputs.
   * Returns null on total failure. Individual entries may be missing on partial failure.
   */
  private async batchEmbed(
    inputs: string[],
    apiKey: string,
  ): Promise<Float32Array[] | null> {
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      try {
        const response = await fetch(OPENROUTER_EMBEDDINGS_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model: this.modelId,
            input: inputs,
          }),
        });

        if (response.status === 429) {
          const backoff = INITIAL_BACKOFF_MS * Math.pow(2, attempt);
          await sleep(backoff);
          continue;
        }

        if (!response.ok) {
          console.warn(`Embedding API error: ${response.status} ${response.statusText}`);
          return null;
        }

        const body = await response.json() as {
          data: Array<{ embedding: number[]; index: number }>;
        };

        // Sort by index to match input order
        const sorted = body.data.sort((a, b) => a.index - b.index);
        return sorted.map(d => new Float32Array(d.embedding));
      } catch (err) {
        console.warn(`Embedding API call failed (attempt ${attempt + 1}):`, err);
        if (attempt < MAX_RETRIES - 1) {
          await sleep(INITIAL_BACKOFF_MS * Math.pow(2, attempt));
        }
      }
    }
    return null;
  }
}

// ── Helpers ────────────────────────────────────────────────

/** Build the embedding input string for a taxonomy node. */
function buildEmbeddingInput(node: TaxonomyNodeInfo): string {
  const examples = node.examples.length > 0
    ? `. Examples: ${node.examples.join(', ')}`
    : '';
  return `${node.label}: ${node.description}${examples}`;
}

/** SHA-256 hex digest of a string. */
function sha256(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/** Content hash for change detection — exported for tests. */
export function computeContentHash(label: string, description: string, examples: string[]): string {
  const input = buildEmbeddingInput({ path: '', segments: [], label, description, examples });
  return sha256(input);
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Walk an IntentTaxonomy tree and collect all nodes with their paths.
 * Used by CLI commands that load taxonomy configs directly.
 */
export function collectTaxonomyNodes(
  domains: IntentTaxonomyNode[],
): TaxonomyNodeInfo[] {
  const result: TaxonomyNodeInfo[] = [];

  function walk(nodes: IntentTaxonomyNode[], parentSegments: string[]): void {
    for (const node of nodes) {
      const segments = [...parentSegments, node.id];
      result.push({
        path: segments.join('.'),
        segments,
        label: node.label,
        description: node.description,
        examples: node.examples ?? [],
      });
      if (node.children && node.children.length > 0) {
        walk(node.children, segments);
      }
    }
  }

  walk(domains, []);
  return result;
}

/** Singleton instance. */
export const embeddingService = new EmbeddingService();

```
