---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/node-index.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.716396+00:00
---

# archive/apps-settlement/src/store/__tests__/node-index.test.ts

```ts
/**
 * Per-concern unit tests for `NodeStore`.
 *
 * Spins up an in-memory SQLite DB, applies the schema, and exercises
 * upsert / get / update / mark / list. No facade involved — the test
 * uses the per-concern store directly to prove it's standalone-usable.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';

function freshNodeStore(): { db: Database; store: NodeStore } {
  const db = new Database(':memory:');
  applyPaskianSchema(db);
  return { db, store: new NodeStore(db) };
}

describe('NodeStore', () => {
  test('upsertNode is idempotent on cellId', () => {
    const { db, store } = freshNodeStore();
    store.upsertNode({ cellId: 'a', typePath: 'paskian.story.thread' });
    store.upsertNode({ cellId: 'a', typePath: 'paskian.story.thread' });
    expect(store.allNodes()).toHaveLength(1);
    db.close();
  });

  test('getNode returns null for unknown cell', () => {
    const { db, store } = freshNodeStore();
    expect(store.getNode('missing')).toBeNull();
    db.close();
  });

  test('updateNodeState accumulates deltaH and bumps interactionCount', () => {
    const { db, store } = freshNodeStore();
    store.upsertNode({ cellId: 'a', typePath: 't' });
    store.updateNodeState('a', 0.5);
    store.updateNodeState('a', 0.25);
    const n = store.getNode('a')!;
    expect(n.hState).toBeCloseTo(0.75);
    expect(n.interactionCount).toBe(2);
    db.close();
  });

  test('markStable flips the boolean both ways', () => {
    const { db, store } = freshNodeStore();
    store.upsertNode({ cellId: 'a', typePath: 't' });
    expect(store.getNode('a')!.isStable).toBe(false);
    store.markStable('a', true);
    expect(store.getNode('a')!.isStable).toBe(true);
    store.markStable('a', false);
    expect(store.getNode('a')!.isStable).toBe(false);
    db.close();
  });

  test('markPruned excludes the node from activeNodes', () => {
    const { db, store } = freshNodeStore();
    store.upsertNode({ cellId: 'live', typePath: 't' });
    store.upsertNode({ cellId: 'dead', typePath: 't' });
    store.markPruned('dead');

    const active = store.activeNodes().map((n) => n.cellId).sort();
    expect(active).toEqual(['live']);
    expect(store.allNodes()).toHaveLength(2);
    db.close();
  });
});

```
