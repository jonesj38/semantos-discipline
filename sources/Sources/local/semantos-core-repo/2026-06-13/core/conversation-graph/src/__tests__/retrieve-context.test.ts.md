---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/__tests__/retrieve-context.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.009901+00:00
---

# core/conversation-graph/src/__tests__/retrieve-context.test.ts

```ts
/**
 * RM-070 — substrate semantic retrieval (structural).
 *
 * `retrieveContext` walks the SCG relation graph around a seed and
 * returns an ordered context bundle. Tests pin:
 *   - `thread` mode walks REPLIES_TO in both directions
 *   - `citations` mode walks CITES + SUPERSEDES + SUPPORTS + DISPUTES
 *   - nodes are ordered by ascending hops, then createdAt
 *   - depth cap is honoured
 *   - multi-seed walks union the bundles with min-hop relevance
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import { createRelation } from '@semantos/scg-relations';
import { makeTestDb } from './setup.js';
import { retrieveContext } from '../retrieve-context.js';

describe('retrieveContext (RM-070)', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('R1 thread mode returns the seed + connected REPLIES_TO chain', async () => {
    const root = await createObject(db, { objectKind: 'scg.cell', payload: { body: 'root' } });
    const a = await createObject(db, { objectKind: 'scg.cell', payload: { body: 'a' } });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: { body: 'b' } });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: a.id, targetId: root.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: b.id, targetId: a.id });

    const ctx = await retrieveContext(db, { seedIds: [root.id], mode: 'thread' });
    const ids = ctx.nodes.map((n) => n.id);
    expect(ids).toContain(root.id);
    expect(ids).toContain(a.id);
    expect(ids).toContain(b.id);
    // The seed is first (hops=0); reply chain is next.
    expect(ctx.nodes[0]!.id).toBe(root.id);
    expect(ctx.nodes[0]!.hopsFromSeed).toBe(0);
  });

  test('R2 thread mode ignores non-thread relations (CITES, SUPPORTS)', async () => {
    const root = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const cited = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'CITES', sourceId: root.id, targetId: cited.id });

    const ctx = await retrieveContext(db, { seedIds: [root.id], mode: 'thread' });
    expect(ctx.nodes.map((n) => n.id)).toEqual([root.id]);
    expect(ctx.edges).toEqual([]);
  });

  test('R3 citations mode walks CITES + SUPERSEDES + SUPPORTS + DISPUTES', async () => {
    const seed = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const cited = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const superseded = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const supporting = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const disputing = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const unrelated = await createObject(db, { objectKind: 'scg.cell', payload: {} });

    await createRelation(db, { kind: 'CITES', sourceId: seed.id, targetId: cited.id });
    await createRelation(db, { kind: 'SUPERSEDES', sourceId: seed.id, targetId: superseded.id });
    await createRelation(db, { kind: 'SUPPORTS', sourceId: supporting.id, targetId: seed.id });
    await createRelation(db, { kind: 'DISPUTES', sourceId: disputing.id, targetId: seed.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: unrelated.id, targetId: seed.id });

    const ctx = await retrieveContext(db, { seedIds: [seed.id], mode: 'citations' });
    const ids = ctx.nodes.map((n) => n.id);
    expect(ids).toContain(cited.id);
    expect(ids).toContain(superseded.id);
    expect(ids).toContain(supporting.id);
    expect(ids).toContain(disputing.id);
    expect(ids).not.toContain(unrelated.id);
  });

  test('R4 depth cap is honoured', async () => {
    const seed = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const c = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: a.id, targetId: seed.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: b.id, targetId: a.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: c.id, targetId: b.id });

    const ctx = await retrieveContext(db, { seedIds: [seed.id], mode: 'thread', depth: 1 });
    const ids = ctx.nodes.map((n) => n.id);
    expect(ids).toContain(seed.id);
    expect(ids).toContain(a.id);
    expect(ids).not.toContain(c.id);
  });

  test('R5 nodes are ordered by ascending hops, then createdAt', async () => {
    const seed = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const hop1Old = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await new Promise((r) => setTimeout(r, 5));
    const hop1New = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const hop2 = await createObject(db, { objectKind: 'scg.cell', payload: {} });

    await createRelation(db, { kind: 'REPLIES_TO', sourceId: hop1Old.id, targetId: seed.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: hop1New.id, targetId: seed.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: hop2.id, targetId: hop1Old.id });

    const ctx = await retrieveContext(db, { seedIds: [seed.id], mode: 'thread' });
    const positions = ctx.nodes.map((n) => ({ id: n.id, hop: n.hopsFromSeed }));

    expect(positions[0]!.id).toBe(seed.id);
    expect(positions[0]!.hop).toBe(0);
    // hop=1 cells precede hop=2
    const hop1Indices = positions
      .map((p, i) => ({ p, i }))
      .filter(({ p }) => p.hop === 1)
      .map(({ i }) => i);
    const hop2Index = positions.findIndex((p) => p.hop === 2);
    expect(Math.max(...hop1Indices)).toBeLessThan(hop2Index);
  });

  test('R6 multi-seed walks union the bundles; nearest-seed hops win', async () => {
    const seedA = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const seedB = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const mid = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: mid.id, targetId: seedA.id });
    await createRelation(db, { kind: 'REPLIES_TO', sourceId: mid.id, targetId: seedB.id });

    const ctx = await retrieveContext(db, {
      seedIds: [seedA.id, seedB.id],
      mode: 'thread',
    });
    const midNode = ctx.nodes.find((n) => n.id === mid.id);
    expect(midNode).toBeDefined();
    expect(midNode!.hopsFromSeed).toBe(1);
  });

  test('R7 empty seed set returns empty bundle without DB hits', async () => {
    const ctx = await retrieveContext(db, { seedIds: [], mode: 'thread' });
    expect(ctx.nodes).toEqual([]);
    expect(ctx.edges).toEqual([]);
    expect(ctx.mode).toBe('thread');
  });

  test('R8 extraKinds expand the walk on top of mode defaults', async () => {
    const seed = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const branch = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, { kind: 'FORKS', sourceId: branch.id, targetId: seed.id });

    const withoutFork = await retrieveContext(db, { seedIds: [seed.id], mode: 'thread' });
    expect(withoutFork.nodes.map((n) => n.id)).not.toContain(branch.id);

    const withFork = await retrieveContext(db, {
      seedIds: [seed.id],
      mode: 'thread',
      extraKinds: ['FORKS'],
    });
    expect(withFork.nodes.map((n) => n.id)).toContain(branch.id);
  });
});

```
