---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/retrieve-context.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.007674+00:00
---

# core/conversation-graph/src/retrieve-context.ts

```ts
/**
 * Semantic context retrieval — RM-070.
 *
 * Substrate-level minimal retrieve. Given a seed cell (or set of seeds),
 * walk the SCG relation graph to gather the surrounding context that an
 * LLM / consumer would need to reason about the seed. This is the
 * substrate's structural retrieval; the embedding-based retrieval (LLM
 * harness, vector indexes) layers on top and is RM-071 (deferred).
 *
 * Two retrieval modes:
 *   - **thread**: walk REPLIES_TO upward (toward the conversation root)
 *     and downward (toward leaves). Returns the linear thread the seed
 *     participates in.
 *   - **citations**: walk CITES + SUPERSEDES + SUPPORTS + DISPUTES
 *     outward in both directions, capping at `depth`. Returns the local
 *     citation / argument neighbourhood.
 *
 * Both modes return a `RetrievedContext` bundle the caller can render
 * directly or pass to an LLM. The bundle is ordered: most-relevant
 * (closest hop) first; ties broken by `createdAt` ascending so threads
 * read chronologically.
 *
 * Why this lives in `conversation-graph` rather than `scg-relations`:
 * retrieval is a consumer-facing abstraction — it builds on top of the
 * relation primitives but adds an ordering/relevance contract that's
 * specific to conversation-graph callers. `scg-relations` ships the
 * graph walk (`foldRelationGraph`); this module wraps it with the
 * retrieval semantics.
 */
import type { Database, ObjectRow } from '@semantos/semantic-objects';
import {
  foldRelationGraph,
  type RelationEdge,
  type RelationKind,
} from '@semantos/scg-relations';

export interface RetrieveContextInput {
  /** The cell(s) to retrieve context around. */
  readonly seedIds: ReadonlyArray<string>;
  /** Retrieval mode — selects which relation kinds get walked. */
  readonly mode: 'thread' | 'citations';
  /** Maximum walk depth (default 3). */
  readonly depth?: number;
  /**
   * Optional extra kinds to include on top of the mode's defaults. Use
   * this when the caller wants e.g. `thread` plus `FORKS`/`MERGES` for
   * a branching conversation view.
   */
  readonly extraKinds?: ReadonlyArray<RelationKind>;
}

export interface RetrievedContextNode {
  readonly id: string;
  /** `sem_objects.objectKind` — `'scg.cell'`, `'conversation.turn'`, etc. */
  readonly objectKind: string;
  /** Distance from the nearest seed, in graph hops. Seeds are 0. */
  readonly hopsFromSeed: number;
  /** The underlying row payload — caller decodes per its domain schema. */
  readonly payload: unknown;
  readonly createdAt: Date;
}

export interface RetrievedContext {
  /** Ordered: ascending hop distance, then ascending createdAt. */
  readonly nodes: ReadonlyArray<RetrievedContextNode>;
  /** Traversed edges, denormalised. */
  readonly edges: ReadonlyArray<RelationEdge>;
  /** Mode the caller asked for; echoed for downstream rendering. */
  readonly mode: 'thread' | 'citations';
}

const THREAD_KINDS: ReadonlyArray<RelationKind> = ['REPLIES_TO'];

const CITATION_KINDS: ReadonlyArray<RelationKind> = [
  'CITES',
  'SUPERSEDES',
  'SUPPORTS',
  'DISPUTES',
];

/**
 * Walk the SCG relation graph around `seedIds` and return the ordered
 * context bundle. The walk is BFS bounded by `depth`; cycles are
 * de-duplicated by `foldRelationGraph`.
 */
export async function retrieveContext(
  db: Database,
  input: RetrieveContextInput,
): Promise<RetrievedContext> {
  if (input.seedIds.length === 0) {
    return { nodes: [], edges: [], mode: input.mode };
  }
  const depth = input.depth ?? 3;
  const baseKinds = input.mode === 'thread' ? THREAD_KINDS : CITATION_KINDS;
  const kinds: RelationKind[] = [
    ...baseKinds,
    ...(input.extraKinds ?? []),
  ];

  // Hop tracking across multiple seeds: each seed contributes its own
  // BFS; the per-node hop count is the min across all seeds. This makes
  // "nearest seed wins" the relevance signal.
  const hopsByNode = new Map<string, number>();
  const allNodes = new Map<string, ObjectRow<unknown>>();
  const seenEdges = new Map<string, RelationEdge>();

  for (const seedId of input.seedIds) {
    const graph = await foldRelationGraph(db, seedId, {
      depth,
      kinds,
      direction: 'both',
    });

    // BFS again over the returned subgraph to compute hop distances
    // from THIS seed; foldRelationGraph itself doesn't surface hop info.
    const localHops = bfsHops(seedId, graph.edges);
    for (const [nodeId, h] of localHops) {
      const prev = hopsByNode.get(nodeId);
      if (prev === undefined || h < prev) hopsByNode.set(nodeId, h);
    }
    for (const [id, node] of graph.nodes) allNodes.set(id, node);
    for (const e of graph.edges) seenEdges.set(e.id, e);
  }

  const nodes: RetrievedContextNode[] = [];
  for (const [id, row] of allNodes) {
    nodes.push({
      id,
      objectKind: row.objectKind,
      hopsFromSeed: hopsByNode.get(id) ?? 0,
      payload: row.payload,
      createdAt: row.createdAt,
    });
  }
  nodes.sort((a, b) => {
    if (a.hopsFromSeed !== b.hopsFromSeed) return a.hopsFromSeed - b.hopsFromSeed;
    return a.createdAt.getTime() - b.createdAt.getTime();
  });

  return {
    nodes,
    edges: Array.from(seenEdges.values()),
    mode: input.mode,
  };
}

/** BFS hop-distance map from `rootId` over the supplied edges. */
function bfsHops(
  rootId: string,
  edges: ReadonlyArray<RelationEdge>,
): Map<string, number> {
  const hops = new Map<string, number>();
  hops.set(rootId, 0);

  const adj = new Map<string, Set<string>>();
  for (const e of edges) {
    if (!adj.has(e.sourceId)) adj.set(e.sourceId, new Set());
    if (!adj.has(e.targetId)) adj.set(e.targetId, new Set());
    adj.get(e.sourceId)!.add(e.targetId);
    adj.get(e.targetId)!.add(e.sourceId);
  }

  let frontier = [rootId];
  let depth = 0;
  while (frontier.length > 0) {
    const next: string[] = [];
    for (const node of frontier) {
      const neighbours = adj.get(node);
      if (!neighbours) continue;
      for (const n of neighbours) {
        if (hops.has(n)) continue;
        hops.set(n, depth + 1);
        next.push(n);
      }
    }
    frontier = next;
    depth += 1;
  }
  return hops;
}

```
