---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.906597+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/fixtures.ts

```ts
/**
 * Test fixtures shared across semantic-fs unit tests.
 */

import type {
  EmbeddingProvider,
  TaxonomyNode,
  TaxonomyResolver,
} from '../../taxonomy-resolver';

/**
 * Build a tiny `TaxonomyResolver` from a literal tree. The fixture
 * tree:
 *
 *   create
 *     └─ job
 *           ├─ plumbing
 *           └─ electric
 *   discover
 *     └─ asset
 */
export function makeTaxonomy(): TaxonomyResolver {
  const tree: TaxonomyNode = {
    id: '__root__',
    label: 'root',
    children: [
      {
        id: 'create',
        label: 'create',
        children: [
          {
            id: 'job',
            label: 'job',
            children: [
              { id: 'plumbing', label: 'plumbing' },
              { id: 'electric', label: 'electric' },
            ],
          },
        ],
      },
      {
        id: 'discover',
        label: 'discover',
        children: [{ id: 'asset', label: 'asset' }],
      },
    ],
  };

  function find(node: TaxonomyNode, segs: string[]): TaxonomyNode | null {
    if (segs.length === 0) return node;
    const [head, ...rest] = segs;
    const child = node.children?.find((c) => c.id === head);
    if (!child) return null;
    return find(child, rest);
  }

  return {
    getNodeAt: (path) => find(tree, path),
    getOptionsAt: (path) => find(tree, path)?.children ?? [],
  };
}

/**
 * Deterministic stub `EmbeddingProvider` — returns a vector keyed off
 * the query string and yields fixed nearest paths. Used by both
 * search-via-port and search-via-options tests.
 */
export function makeEmbeddingStub(opts?: {
  ready?: boolean;
  nearest?: Array<{ path: string; score: number }>;
}): EmbeddingProvider {
  const ready = opts?.ready ?? true;
  const nearest = opts?.nearest ?? [
    { path: 'create.job.plumbing', score: 0.95 },
    { path: 'create.job.electric', score: 0.88 },
  ];
  return {
    isReady: () => ready,
    embedQuery: async () => new Float32Array([1, 2, 3]),
    nearest: () => nearest,
  };
}

```
