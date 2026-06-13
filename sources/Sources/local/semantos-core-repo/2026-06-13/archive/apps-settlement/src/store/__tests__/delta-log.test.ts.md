---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/delta-log.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.717899+00:00
---

# archive/apps-settlement/src/store/__tests__/delta-log.test.ts

```ts
/**
 * Per-concern unit tests for `DeltaLog`.
 *
 * Covers append, the per-edge `avgDelta` window query, and the
 * cross-table `inboundTrend` aggregate. Stability detection and
 * pruning both consume from these aggregates so getting them right
 * here matters.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { DeltaLog } from '../delta-log';
import { EdgeStore } from '../edge-index';
import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';

function freshDeltaLog(): {
  db: Database;
  deltas: DeltaLog;
  edges: EdgeStore;
  nodes: NodeStore;
} {
  const db = new Database(':memory:');
  applyPaskianSchema(db);
  return {
    db,
    deltas: new DeltaLog(db),
    edges: new EdgeStore(db),
    nodes: new NodeStore(db),
  };
}

describe('DeltaLog', () => {
  test('avgDelta returns 0 for an edge with no deltas in window', () => {
    const { db, deltas } = freshDeltaLog();
    expect(deltas.avgDelta('nonexistent', 1000)).toBe(0);
    db.close();
  });

  test('avgDelta averages absolute values', () => {
    const { db, deltas, edges, nodes } = freshDeltaLog();
    nodes.upsertNode({ cellId: 'a', typePath: 't' });
    nodes.upsertNode({ cellId: 'b', typePath: 't' });
    const id = edges.upsertEdge('a', 'b');

    deltas.recordDelta(id, 0.4, 'k');
    deltas.recordDelta(id, -0.6, 'k');

    // mean(|0.4|, |0.6|) = 0.5
    expect(deltas.avgDelta(id, 60_000)).toBeCloseTo(0.5);
    db.close();
  });

  test('inboundTrend averages delta_trend across inbound edges only', () => {
    const { db, deltas, edges, nodes } = freshDeltaLog();
    for (const id of ['target', 'src1', 'src2', 'unrelated']) {
      nodes.upsertNode({ cellId: id, typePath: 't' });
    }
    const e1 = edges.upsertEdge('src1', 'target');
    const e2 = edges.upsertEdge('src2', 'target');
    const e3 = edges.upsertEdge('target', 'unrelated'); // outbound — should be ignored
    edges.updateEdgeTrend(e1, 0.4);
    edges.updateEdgeTrend(e2, 0.6);
    edges.updateEdgeTrend(e3, -1.0);

    expect(deltas.inboundTrend('target')).toBeCloseTo(0.5);
    db.close();
  });

  test('inboundTrend returns 0 for a node with no inbound edges', () => {
    const { db, deltas, nodes } = freshDeltaLog();
    nodes.upsertNode({ cellId: 'lonely', typePath: 't' });
    expect(deltas.inboundTrend('lonely')).toBe(0);
    db.close();
  });
});

```
