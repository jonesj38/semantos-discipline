---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/__tests__/relations.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.819565+00:00
---

# core/scg-relations/src/__tests__/relations.test.ts

```ts
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import { makeTestDb } from './setup.js';
import {
  RELATION_OBJECT_KIND,
  createRelation,
  foldRelationGraph,
  isRelationRow,
  listRelationsFrom,
  listRelationsTo,
} from '../index.js';

describe('createRelation', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('R1 round-trip: post + reply + REPLIES_TO relation', async () => {
    const post = await createObject(db, {
      id: 'post-1',
      objectKind: 'scg.cell',
      payload: { body: 'original post' },
      createdByCertId: 'cert-a',
    });
    const reply = await createObject(db, {
      id: 'reply-1',
      objectKind: 'scg.cell',
      payload: { body: 'a reply' },
      createdByCertId: 'cert-b',
    });

    const rel = await createRelation(db, {
      kind: 'REPLIES_TO',
      sourceId: reply.id,
      targetId: post.id,
      createdByCertId: 'cert-b',
    });

    expect(rel.objectKind).toBe(RELATION_OBJECT_KIND);
    expect(isRelationRow(rel)).toBe(true);
    expect(rel.payload.kind).toBe('REPLIES_TO');
    expect(rel.payload.sourceId).toBe(reply.id);
    expect(rel.payload.targetId).toBe(post.id);
    expect(rel.parentId).toBeNull();
    expect(rel.currentVersion).toBe(0);
  });

  test('R2 capabilityCheck thunk runs before insert; refusal blocks creation', async () => {
    const post = await createObject(db, {
      objectKind: 'scg.cell',
      payload: {},
    });
    let calls = 0;
    await expect(
      createRelation(db, {
        kind: 'SUPPORTS',
        sourceId: post.id,
        targetId: post.id,
        capabilityCheck: async () => {
          calls += 1;
          throw new Error('RELATION_MINT denied');
        },
      }),
    ).rejects.toThrow('RELATION_MINT denied');
    expect(calls).toBe(1);
    const fromPost = await listRelationsFrom(db, post.id);
    expect(fromPost).toHaveLength(0);
  });

  test('R3 attestation + extra fields survive round-trip', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const rel = await createRelation(db, {
      kind: 'CITES',
      sourceId: a.id,
      targetId: b.id,
      attestation: 'sig-deadbeef',
      extra: { weight: 0.7 },
    });
    expect(rel.payload.attestation).toBe('sig-deadbeef');
    expect(rel.payload.extra).toEqual({ weight: 0.7 });
  });
});

describe('listRelationsFrom / listRelationsTo', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('L4 listRelationsFrom returns outgoing edges only', async () => {
    const post = await createObject(db, { id: 'p1', objectKind: 'scg.cell', payload: {} });
    const r1 = await createObject(db, { id: 'r1', objectKind: 'scg.cell', payload: {} });
    const r2 = await createObject(db, { id: 'r2', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: r1.id, targetId: post.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: r2.id, targetId: post.id });
    await createRelation(db, { kind: 'SUPPORTS', sourceId: r1.id, targetId: post.id });

    const fromR1 = await listRelationsFrom(db, r1.id);
    expect(fromR1).toHaveLength(2);
    expect(fromR1.every((r) => r.payload.sourceId === r1.id)).toBe(true);

    const fromR1Replies = await listRelationsFrom(db, r1.id, { kind: 'REPLIES_TO' });
    expect(fromR1Replies).toHaveLength(1);
    expect(fromR1Replies[0]?.payload.kind).toBe('REPLIES_TO');
  });

  test('L5 listRelationsTo returns incoming edges only', async () => {
    const post = await createObject(db, { id: 'tp', objectKind: 'scg.cell', payload: {} });
    const r1 = await createObject(db, { id: 'tr1', objectKind: 'scg.cell', payload: {} });
    const r2 = await createObject(db, { id: 'tr2', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: r1.id, targetId: post.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: r2.id, targetId: post.id });

    const toPost = await listRelationsTo(db, post.id);
    expect(toPost).toHaveLength(2);
    expect(toPost.every((r) => r.payload.targetId === post.id)).toBe(true);
  });
});

describe('foldRelationGraph', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('F1 outgoing walk collects nodes + edges from root', async () => {
    const a = await createObject(db, { id: 'fa', objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { id: 'fb', objectKind: 'scg.cell', payload: {} });
    const c = await createObject(db, { id: 'fc', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'CITES', sourceId: a.id, targetId: b.id });
    await createRelation(db, { kind: 'CITES', sourceId: b.id, targetId: c.id });

    const graph = await foldRelationGraph(db, a.id, { depth: 3 });
    expect(graph.nodes.size).toBe(3);
    expect(graph.edges.length).toBe(2);
    expect(graph.nodes.has(a.id)).toBe(true);
    expect(graph.nodes.has(c.id)).toBe(true);
  });

  test('F2 depth cap stops the walk', async () => {
    const a = await createObject(db, { id: 'da', objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { id: 'db', objectKind: 'scg.cell', payload: {} });
    const c = await createObject(db, { id: 'dc', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'CITES', sourceId: a.id, targetId: b.id });
    await createRelation(db, { kind: 'CITES', sourceId: b.id, targetId: c.id });

    const graph = await foldRelationGraph(db, a.id, { depth: 1 });
    expect(graph.nodes.has(a.id)).toBe(true);
    expect(graph.nodes.has(b.id)).toBe(true);
    expect(graph.nodes.has(c.id)).toBe(false);
    expect(graph.edges.length).toBe(1);
  });

  test('F3 cycle does not loop forever', async () => {
    const a = await createObject(db, { id: 'ca', objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { id: 'cb', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'CITES', sourceId: a.id, targetId: b.id });
    await createRelation(db, { kind: 'CITES', sourceId: b.id, targetId: a.id });

    const graph = await foldRelationGraph(db, a.id, { depth: 5, direction: 'both' });
    expect(graph.nodes.size).toBe(2);
  });

  test('F4 kinds filter restricts traversal', async () => {
    const a = await createObject(db, { id: 'ka', objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { id: 'kb', objectKind: 'scg.cell', payload: {} });
    const c = await createObject(db, { id: 'kc', objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'CITES', sourceId: a.id, targetId: b.id });
    await createRelation(db, { kind: 'DISPUTES', sourceId: a.id, targetId: c.id });

    const graph = await foldRelationGraph(db, a.id, { kinds: ['CITES'] });
    expect(graph.nodes.has(b.id)).toBe(true);
    expect(graph.nodes.has(c.id)).toBe(false);
    expect(graph.edges.every((e) => e.kind === 'CITES')).toBe(true);
  });
});

```
