---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/__tests__/operations.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.937552+00:00
---

# core/semantic-objects/src/__tests__/operations.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { makeTestDb } from './setup.js';
import type { Database } from '../types.js';
import {
  createObject,
  getObject,
  appendPatch,
  listPatches,
  foldState,
  addParticipant,
  listParticipants,
  removeParticipant,
  listObjectsByKind,
  StaleStateHashError,
  ObjectNotFoundError,
} from '../index.js';

describe('createObject + getObject', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('O1 creates a new object with generated id', async () => {
    const obj = await createObject<{ x: number }>(db, {
      objectKind: 'schedule',
      payload: { x: 1 },
      createdByCertId: 'cert-a',
    });
    expect(obj.id).toMatch(/^schedule_/);
    expect(obj.currentVersion).toBe(0);
    expect(obj.currentStateHash).toBeNull();
    expect(obj.payload).toEqual({ x: 1 });
  });

  test('O2 getObject returns the object by id', async () => {
    const obj = await createObject(db, { id: 'obj-1', objectKind: 'schedule', payload: {} });
    const fetched = await getObject(db, obj.id);
    expect(fetched?.id).toBe('obj-1');
  });

  test('O3 getObject returns null for unknown id', async () => {
    const result = await getObject(db, 'nope');
    expect(result).toBeNull();
  });
});

describe('appendPatch', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('P1 first patch sets state hash; object version advances to 1', async () => {
    const obj = await createObject(db, { id: 'obj-p1', objectKind: 'schedule', payload: {} });
    const patch = await appendPatch(db, {
      objectId: obj.id,
      kind: 'hold',
      delta: { holdId: 'h1' },
    });
    expect(patch.prevStateHash).toBeNull();
    expect(patch.newStateHash).toMatch(/^[0-9a-f]{64}$/);
    const fresh = await getObject(db, obj.id);
    expect(fresh?.currentVersion).toBe(1);
    expect(fresh?.currentStateHash).toBe(patch.newStateHash);
  });

  test('P2 sequential patches chain: patch2.prev = patch1.new', async () => {
    await createObject(db, { id: 'obj-p2', objectKind: 'schedule', payload: {} });
    const p1 = await appendPatch(db, { objectId: 'obj-p2', kind: 'hold', delta: { h: 1 } });
    const p2 = await appendPatch(db, { objectId: 'obj-p2', kind: 'book', delta: { b: 1 } });
    expect(p2.prevStateHash).toBe(p1.newStateHash);
    expect(p1.newStateHash).not.toBe(p2.newStateHash);
  });

  test('P3 expectedPrevStateHash mismatch throws StaleStateHashError', async () => {
    await createObject(db, { id: 'obj-p3', objectKind: 'schedule', payload: {} });
    await appendPatch(db, { objectId: 'obj-p3', kind: 'hold', delta: {} });
    await expect(
      appendPatch(db, {
        objectId: 'obj-p3',
        kind: 'book',
        delta: {},
        expectedPrevStateHash: 'stale-hash-nope',
      }),
    ).rejects.toBeInstanceOf(StaleStateHashError);
  });

  test('P4 appendPatch on unknown object throws ObjectNotFoundError', async () => {
    await expect(
      appendPatch(db, { objectId: 'ghost', kind: 'hold', delta: {} }),
    ).rejects.toBeInstanceOf(ObjectNotFoundError);
  });

  test('P5 hash is deterministic for same prev + delta + kind + timestamp', async () => {
    await createObject(db, { id: 'obj-p5a', objectKind: 'schedule', payload: {} });
    await createObject(db, { id: 'obj-p5b', objectKind: 'schedule', payload: {} });
    const pa = await appendPatch(db, {
      objectId: 'obj-p5a',
      kind: 'x',
      delta: { a: 1 },
      timestamp: 1000,
    });
    const pb = await appendPatch(db, {
      objectId: 'obj-p5b',
      kind: 'x',
      delta: { a: 1 },
      timestamp: 1000,
    });
    expect(pa.newStateHash).toBe(pb.newStateHash);
  });

  test('P6 facetId + lexicon + capabilities persist', async () => {
    await createObject(db, { id: 'obj-p6', objectKind: 'schedule', payload: {} });
    const p = await appendPatch(db, {
      objectId: 'obj-p6',
      kind: 'hold',
      delta: {},
      facetId: 'hat-tenant',
      facetCapabilities: [1, 2, 4],
      lexicon: 'calendar',
    });
    expect(p.facetId).toBe('hat-tenant');
    expect(p.facetCapabilities).toEqual([1, 2, 4]);
    expect(p.lexicon).toBe('calendar');
  });
});

describe('listPatches + foldState', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  type Delta = { op: 'inc' | 'dec'; n: number };

  test('F1 returns patches in chronological order', async () => {
    await createObject(db, { id: 'obj-f1', objectKind: 'counter', payload: {} });
    await appendPatch<Delta>(db, { objectId: 'obj-f1', kind: 'change', delta: { op: 'inc', n: 1 } });
    await appendPatch<Delta>(db, { objectId: 'obj-f1', kind: 'change', delta: { op: 'inc', n: 2 } });
    await appendPatch<Delta>(db, { objectId: 'obj-f1', kind: 'change', delta: { op: 'dec', n: 1 } });
    const patches = await listPatches<Delta>(db, { objectId: 'obj-f1' });
    expect(patches.length).toBe(3);
    expect(patches.map((p) => p.delta.op)).toEqual(['inc', 'inc', 'dec']);
  });

  test('F2 foldState reduces patches via provided reducer', async () => {
    await createObject(db, { id: 'obj-f2', objectKind: 'counter', payload: {} });
    await appendPatch<Delta>(db, { objectId: 'obj-f2', kind: 'change', delta: { op: 'inc', n: 5 } });
    await appendPatch<Delta>(db, { objectId: 'obj-f2', kind: 'change', delta: { op: 'dec', n: 2 } });
    await appendPatch<Delta>(db, { objectId: 'obj-f2', kind: 'change', delta: { op: 'inc', n: 10 } });
    const patches = await listPatches<Delta>(db, { objectId: 'obj-f2' });
    const total = foldState<number, Delta>({
      patches,
      initial: 0,
      reducer: (s, p) => s + (p.delta.op === 'inc' ? p.delta.n : -p.delta.n),
    });
    expect(total).toBe(13);
  });
});

describe('listObjectsByKind', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('LOK1 returns objects of the given kind', async () => {
    await createObject(db, { id: 'obj-lok-a', objectKind: 'test.kind-a', payload: { v: 1 } });
    await createObject(db, { id: 'obj-lok-b', objectKind: 'test.kind-a', payload: { v: 2 } });
    await createObject(db, { id: 'obj-lok-c', objectKind: 'test.kind-b', payload: { v: 3 } });

    const results = await listObjectsByKind(db, { objectKind: 'test.kind-a' });
    expect(results).toHaveLength(2);
    const ids = results.map((r) => r.id).sort();
    expect(ids).toEqual(['obj-lok-a', 'obj-lok-b']);
  });

  test('LOK2 returns empty array for unknown kind', async () => {
    const results = await listObjectsByKind(db, { objectKind: 'does.not.exist' });
    expect(results).toHaveLength(0);
  });

  test('LOK3 payloadFilter scopes to matching rows', async () => {
    await createObject(db, {
      id: 'obj-lok-p1',
      objectKind: 'test.filterable',
      payload: { conversationId: 'conv-x', v: 1 },
    });
    await createObject(db, {
      id: 'obj-lok-p2',
      objectKind: 'test.filterable',
      payload: { conversationId: 'conv-y', v: 2 },
    });
    await createObject(db, {
      id: 'obj-lok-p3',
      objectKind: 'test.filterable',
      payload: { conversationId: 'conv-x', v: 3 },
    });

    const results = await listObjectsByKind(db, {
      objectKind: 'test.filterable',
      payloadFilters: [{ field: 'conversationId', value: 'conv-x' }],
    });
    expect(results).toHaveLength(2);
    const ids = results.map((r) => r.id).sort();
    expect(ids).toEqual(['obj-lok-p1', 'obj-lok-p3']);
  });

  test('LOK4 limit restricts the number of results', async () => {
    for (let i = 0; i < 5; i++) {
      await createObject(db, {
        id: `obj-lok-lim-${i}`,
        objectKind: 'test.limited',
        payload: { i },
      });
    }
    const results = await listObjectsByKind(db, { objectKind: 'test.limited', limit: 3 });
    expect(results).toHaveLength(3);
  });
});

describe('participants', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('Pa1 add + list', async () => {
    await createObject(db, { id: 'obj-pa', objectKind: 'schedule', payload: {} });
    await addParticipant(db, {
      objectId: 'obj-pa',
      identityRef: 'cert-alice',
      participantRole: 'admin',
      displayName: 'Alice',
    });
    await addParticipant(db, {
      objectId: 'obj-pa',
      identityRef: 'cert-bob',
      participantRole: 'writer',
    });
    const participants = await listParticipants(db, 'obj-pa');
    expect(participants.length).toBe(2);
    const roles = participants.map((p) => p.participantRole).sort();
    expect(roles).toEqual(['admin', 'writer']);
  });

  test('Pa2 remove soft-deletes (leftAt set) and excludes from default list', async () => {
    await createObject(db, { id: 'obj-pb', objectKind: 'schedule', payload: {} });
    const p = await addParticipant(db, {
      objectId: 'obj-pb',
      identityRef: 'cert-alice',
      participantRole: 'admin',
    });
    await removeParticipant(db, p.id);
    const active = await listParticipants(db, 'obj-pb');
    expect(active.length).toBe(0);
    const all = await listParticipants(db, 'obj-pb', { includeLeft: true });
    expect(all.length).toBe(1);
    expect(all[0].leftAt).not.toBeNull();
  });
});

```
