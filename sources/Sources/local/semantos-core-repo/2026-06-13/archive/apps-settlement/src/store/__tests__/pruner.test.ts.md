---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/pruner.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.716884+00:00
---

# archive/apps-settlement/src/store/__tests__/pruner.test.ts

```ts
/**
 * Per-concern unit tests for `Pruner`.
 *
 * Covers the pruning-log append and the `pruningCandidates` cross-
 * table query that picks weak nodes by inbound-trend threshold.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { EdgeStore } from '../edge-index';
import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';
import { Pruner } from '../pruner';

function freshPruner(): {
  db: Database;
  pruner: Pruner;
  edges: EdgeStore;
  nodes: NodeStore;
} {
  const db = new Database(':memory:');
  applyPaskianSchema(db);
  return {
    db,
    pruner: new Pruner(db),
    edges: new EdgeStore(db),
    nodes: new NodeStore(db),
  };
}

describe('Pruner', () => {
  test('recordPruning appends to pruning_log', () => {
    const { db, pruner } = freshPruner();
    pruner.recordPruning({
      cellId: 'c',
      typePath: 't',
      reason: 'weak_constraint',
      finalHState: -0.5,
      prunedAt: 100,
      anchorTxid: null,
    });
    const rows = db.prepare('SELECT * FROM pruning_log').all() as unknown[];
    expect(rows).toHaveLength(1);
    db.close();
  });

  test('pruningCandidates returns only nodes with avg(inbound trend) < threshold', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    for (const id of ['weak', 'strong', 'src']) {
      nodes.upsertNode({ cellId: id, typePath: 't' });
    }
    const e1 = edges.upsertEdge('src', 'weak');
    const e2 = edges.upsertEdge('src', 'strong');
    edges.updateEdgeTrend(e1, -0.5);
    edges.updateEdgeTrend(e2, 0.5);

    const candidates = pruner.pruningCandidates(0).map((n) => n.cellId);
    expect(candidates).toEqual(['weak']);
    db.close();
  });

  test('pruningCandidates excludes already-pruned nodes', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    for (const id of ['weak', 'src']) nodes.upsertNode({ cellId: id, typePath: 't' });
    const e = edges.upsertEdge('src', 'weak');
    edges.updateEdgeTrend(e, -0.5);
    nodes.markPruned('weak');

    expect(pruner.pruningCandidates(0)).toHaveLength(0);
    db.close();
  });

  // ── Threshold-boundary scenarios (5) ──────────────────────────────
  // The spec calls for "Pruning unit tests with 5 retention-boundary
  // scenarios". The Paskian pruner threshold is on the average inbound
  // delta-trend per node — these five scenarios cover the relevant
  // boundary cases (just-below, exactly-at, just-above, mixed-average,
  // empty-inbound) since the prune query is `HAVING AVG(trend) <
  // threshold`.

  test('boundary 1: trend just below threshold → included', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    nodes.upsertNode({ cellId: 'tgt', typePath: 't' });
    nodes.upsertNode({ cellId: 'src', typePath: 't' });
    const e = edges.upsertEdge('src', 'tgt');
    edges.updateEdgeTrend(e, -0.000001);
    expect(pruner.pruningCandidates(0).map((n) => n.cellId)).toEqual(['tgt']);
    db.close();
  });

  test('boundary 2: trend exactly at threshold → excluded (strict <)', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    nodes.upsertNode({ cellId: 'tgt', typePath: 't' });
    nodes.upsertNode({ cellId: 'src', typePath: 't' });
    const e = edges.upsertEdge('src', 'tgt');
    edges.updateEdgeTrend(e, 0.0);
    expect(pruner.pruningCandidates(0)).toHaveLength(0);
    db.close();
  });

  test('boundary 3: trend just above threshold → excluded', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    nodes.upsertNode({ cellId: 'tgt', typePath: 't' });
    nodes.upsertNode({ cellId: 'src', typePath: 't' });
    const e = edges.upsertEdge('src', 'tgt');
    edges.updateEdgeTrend(e, 0.000001);
    expect(pruner.pruningCandidates(0)).toHaveLength(0);
    db.close();
  });

  test('boundary 4: mixed inbound trends — average dominates threshold', () => {
    const { db, pruner, edges, nodes } = freshPruner();
    for (const id of ['tgt', 'src1', 'src2']) {
      nodes.upsertNode({ cellId: id, typePath: 't' });
    }
    const e1 = edges.upsertEdge('src1', 'tgt');
    const e2 = edges.upsertEdge('src2', 'tgt');
    // avg(0.4, -0.5) = -0.05  →  pruned with threshold 0
    edges.updateEdgeTrend(e1, 0.4);
    edges.updateEdgeTrend(e2, -0.5);
    expect(pruner.pruningCandidates(0).map((n) => n.cellId)).toEqual(['tgt']);
    // avg(0.4, -0.5) = -0.05  →  not pruned with threshold -0.1
    expect(pruner.pruningCandidates(-0.1)).toHaveLength(0);
    db.close();
  });

  test('boundary 5: node with zero inbound edges is never a candidate', () => {
    const { db, pruner, nodes } = freshPruner();
    nodes.upsertNode({ cellId: 'orphan', typePath: 't' });
    // The HAVING clause aggregates inbound edges; a node with none
    // is filtered out by the JOIN, not the threshold. Use both an
    // inclusive and exclusive threshold to confirm.
    expect(pruner.pruningCandidates(0)).toHaveLength(0);
    expect(pruner.pruningCandidates(Number.POSITIVE_INFINITY)).toHaveLength(0);
    db.close();
  });
});

```
