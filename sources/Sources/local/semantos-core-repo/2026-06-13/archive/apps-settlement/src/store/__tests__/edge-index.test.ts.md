---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/edge-index.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.718209+00:00
---

# archive/apps-settlement/src/store/__tests__/edge-index.test.ts

```ts
/**
 * Per-concern unit tests for `EdgeStore`.
 *
 * Verifies edge-id derivation, upsert idempotence, and that
 * neighbours / allEdges resolve correctly across both directions.
 * Edges have a foreign-key reference back to nodes, so we have to
 * seed nodes before each test.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { EdgeStore, makeEdgeId } from '../edge-index';
import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';

function freshEdgeStore(): {
  db: Database;
  edges: EdgeStore;
  nodes: NodeStore;
} {
  const db = new Database(':memory:');
  applyPaskianSchema(db);
  return { db, edges: new EdgeStore(db), nodes: new NodeStore(db) };
}

describe('EdgeStore', () => {
  test('makeEdgeId is deterministic and ordered', () => {
    expect(makeEdgeId('a', 'b')).toBe('a-b');
    expect(makeEdgeId('b', 'a')).toBe('b-a');
  });

  test('upsertEdge is idempotent on (from, to) pair', () => {
    const { db, edges, nodes } = freshEdgeStore();
    nodes.upsertNode({ cellId: 'a', typePath: 't' });
    nodes.upsertNode({ cellId: 'b', typePath: 't' });
    const id1 = edges.upsertEdge('a', 'b');
    const id2 = edges.upsertEdge('a', 'b');
    expect(id1).toBe(id2);
    expect(edges.allEdgesGlobal()).toHaveLength(1);
    db.close();
  });

  test('updateEdgeWeight increments constraint_weight + interaction_count', () => {
    const { db, edges, nodes } = freshEdgeStore();
    nodes.upsertNode({ cellId: 'a', typePath: 't' });
    nodes.upsertNode({ cellId: 'b', typePath: 't' });
    const id = edges.upsertEdge('a', 'b');
    edges.updateEdgeWeight(id, 0.4);
    edges.updateEdgeWeight(id, 0.1);

    const e = edges.getEdge(id)!;
    expect(e.constraintWeight).toBeCloseTo(0.5);
    expect(e.interactionCount).toBe(2);
    db.close();
  });

  test('updateEdgeTrend overwrites delta_trend', () => {
    const { db, edges, nodes } = freshEdgeStore();
    nodes.upsertNode({ cellId: 'a', typePath: 't' });
    nodes.upsertNode({ cellId: 'b', typePath: 't' });
    const id = edges.upsertEdge('a', 'b');
    edges.updateEdgeTrend(id, 0.7);
    expect(edges.getEdge(id)!.deltaTrend).toBeCloseTo(0.7);
    edges.updateEdgeTrend(id, -0.3);
    expect(edges.getEdge(id)!.deltaTrend).toBeCloseTo(-0.3);
    db.close();
  });

  test('neighbours returns only outgoing edges', () => {
    const { db, edges, nodes } = freshEdgeStore();
    for (const id of ['a', 'b', 'c']) nodes.upsertNode({ cellId: id, typePath: 't' });
    edges.upsertEdge('a', 'b');
    edges.upsertEdge('a', 'c');
    edges.upsertEdge('c', 'a'); // inbound to a — should be excluded

    const ns = edges.neighbours('a').map((e) => e.toCell).sort();
    expect(ns).toEqual(['b', 'c']);
    db.close();
  });

  test('allEdges returns both directions', () => {
    const { db, edges, nodes } = freshEdgeStore();
    for (const id of ['a', 'b', 'c']) nodes.upsertNode({ cellId: id, typePath: 't' });
    edges.upsertEdge('a', 'b');
    edges.upsertEdge('c', 'a');
    edges.upsertEdge('b', 'c');

    const all = edges.allEdges('a').map((e) => e.edgeId).sort();
    expect(all).toEqual(['a-b', 'c-a']);
    db.close();
  });
});

```
