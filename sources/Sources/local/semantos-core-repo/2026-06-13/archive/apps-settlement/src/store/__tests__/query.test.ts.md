---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/query.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.718499+00:00
---

# archive/apps-settlement/src/store/__tests__/query.test.ts

```ts
/**
 * Per-concern unit tests for `QuerySurface`.
 *
 * Exercises the cross-table queries (`stableThreads`,
 * `emergingThreads`, `snapshot`, `getReputationScore`) directly so
 * we can fixture exactly the rows each one cares about.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { DeltaLog } from '../delta-log';
import { EdgeStore } from '../edge-index';
import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';
import { QuerySurface } from '../query';

function freshQuerySurface(): {
  db: Database;
  queries: QuerySurface;
  nodes: NodeStore;
  edges: EdgeStore;
  deltas: DeltaLog;
} {
  const db = new Database(':memory:');
  applyPaskianSchema(db);
  return {
    db,
    queries: new QuerySurface(db),
    nodes: new NodeStore(db),
    edges: new EdgeStore(db),
    deltas: new DeltaLog(db),
  };
}

describe('QuerySurface', () => {
  test('stableThreads returns only stable + non-pruned nodes with summed weight', () => {
    const { db, queries, nodes, edges } = freshQuerySurface();
    for (const id of ['stable1', 'unstable', 'pruned', 'src']) {
      nodes.upsertNode({ cellId: id, typePath: 't' });
    }
    const e1 = edges.upsertEdge('src', 'stable1');
    edges.updateEdgeWeight(e1, 1.5);
    edges.updateEdgeWeight(e1, 0.5);

    nodes.markStable('stable1', true);
    nodes.markStable('pruned', true);
    nodes.markPruned('pruned');

    const threads = queries.stableThreads();
    expect(threads).toHaveLength(1);
    expect(threads[0].cellId).toBe('stable1');
    expect(threads[0].totalConstraintStrength).toBeCloseTo(2.0);
    db.close();
  });

  test('emergingThreads returns nodes with positive momentum, excluding stable + pruned', () => {
    const { db, queries, nodes, edges, deltas } = freshQuerySurface();
    for (const id of ['emerging', 'fading', 'stable', 'src']) {
      nodes.upsertNode({ cellId: id, typePath: 't' });
    }
    const e1 = edges.upsertEdge('src', 'emerging');
    const e2 = edges.upsertEdge('src', 'fading');
    const e3 = edges.upsertEdge('src', 'stable');

    deltas.recordDelta(e1, 0.4, 'k');
    deltas.recordDelta(e2, -0.4, 'k');
    deltas.recordDelta(e3, 0.5, 'k');
    nodes.markStable('stable', true);

    const emerging = queries.emergingThreads(60_000).map((n) => n.cellId);
    expect(emerging).toEqual(['emerging']);
    db.close();
  });

  test('snapshot returns every node + every edge', () => {
    const { db, queries, nodes, edges } = freshQuerySurface();
    nodes.upsertNode({ cellId: 'a', typePath: 't' });
    nodes.upsertNode({ cellId: 'b', typePath: 't' });
    edges.upsertEdge('a', 'b');

    const snap = queries.snapshot();
    expect(snap.nodes).toHaveLength(2);
    expect(snap.edges).toHaveLength(1);
    db.close();
  });

  test('getReputationScore returns 0/empty for a provider with no reviews', () => {
    const { db, queries } = freshQuerySurface();
    const score = queries.getReputationScore('nobody');
    expect(score).toEqual({
      score: 0,
      totalReviews: 0,
      histogram: [0, 0, 0, 0, 0],
    });
    db.close();
  });
});

```
