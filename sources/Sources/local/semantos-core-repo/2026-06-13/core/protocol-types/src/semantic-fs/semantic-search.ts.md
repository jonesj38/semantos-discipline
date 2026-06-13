---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/semantic-search.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.866300+00:00
---

# core/protocol-types/src/semantic-fs/semantic-search.ts

```ts
/**
 * Embedding-based semantic search.
 *
 * Defines `embeddingPort` so app boot can bind the live
 * EmbeddingService — but each `searchEmbedded` call also accepts a
 * direct EmbeddingProvider override (the SemanticFS facade still
 * threads `options.embeddings` through). This dual binding keeps the
 * existing instance-style construction working while opening a
 * port-based path for renderer-agnostic consumers.
 */

import { port, type Port } from '@semantos/state';

import type { StorageAdapter } from '../storage';
import type { EmbeddingProvider } from '../taxonomy-resolver';
import type { CellRef } from '../cell-store/types';
import { listCellKeys, metaRefsFor } from './metadata-scanner';

export const embeddingPort: Port<EmbeddingProvider> = port<EmbeddingProvider>('embedding');

export interface SemanticSearchHit extends CellRef {
  score: number;
  matchedPath: string;
}

export interface SemanticSearchOptions {
  /** Maximum results returned. Defaults to 5. */
  limit?: number;
  /**
   * Override the embedding provider. When omitted the embedding port
   * is consulted; when neither is bound search is a no-op.
   */
  embeddings?: EmbeddingProvider | undefined;
}

function resolveProvider(opts: SemanticSearchOptions = {}): EmbeddingProvider | null {
  if (opts.embeddings) return opts.embeddings;
  if (embeddingPort.isBound()) return embeddingPort.get();
  return null;
}

/**
 * Find objects nearest to a natural-language query in embedding
 * space. Returns up to `limit` hits, sorted by descending score.
 */
export async function searchEmbedded(
  adapter: StorageAdapter,
  query: string,
  options: SemanticSearchOptions = {},
): Promise<SemanticSearchHit[]> {
  const provider = resolveProvider(options);
  if (!provider?.isReady()) return [];

  const queryVector = await provider.embedQuery(query);
  if (!queryVector) return [];

  const limit = options.limit ?? 5;
  const nearest = provider.nearest(queryVector, limit);

  const results: SemanticSearchHit[] = [];
  for (const { path, score } of nearest) {
    const slashPath = 'objects/' + path.replace(/\./g, '/');
    const keys = await listCellKeys(adapter, slashPath);
    const refs = await metaRefsFor(adapter, keys);
    for (const ref of refs) results.push({ ...ref, score, matchedPath: path });
  }

  results.sort((a, b) => b.score - a.score);
  return results.slice(0, limit);
}

```
