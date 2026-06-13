---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/__tests__/auto-emit.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.008710+00:00
---

# core/conversation-graph/src/__tests__/auto-emit.test.ts

```ts
/**
 * RM-031 acceptance — "a turn quoting a previous turn auto-emits a
 * `scg.relation` of kind `REPLIES_TO`".
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import { listRelationsFrom, RELATION_OBJECT_KIND } from '@semantos/scg-relations';
import { makeTestDb } from './setup.js';
import { autoEmitReplyRelation, makeReplyRelationEmitter } from '../auto-emit.js';
import type { Turn } from '../types.js';

describe('autoEmitReplyRelation (RM-031)', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('CG1 turn that quotes a prior turn emits a REPLIES_TO relation', async () => {
    const conv = await createObject(db, {
      objectKind: 'conversation',
      payload: {},
    });
    const original = await createObject(db, {
      id: 'turn-1',
      objectKind: 'conversation.turn',
      payload: { body: 'original message' },
    });
    const reply = await createObject(db, {
      id: 'turn-2',
      objectKind: 'conversation.turn',
      payload: { body: 'reply quoting the original' },
    });

    const turn: Turn = {
      conversationId: conv.id,
      turnId: reply.id,
      quotedTurnId: original.id,
      authorCertId: 'cert-author',
    };
    const rel = await autoEmitReplyRelation(db, turn);

    expect(rel).not.toBeNull();
    if (!rel) return;
    expect(rel.objectKind).toBe(RELATION_OBJECT_KIND);
    expect(rel.payload.kind).toBe('REPLIES_TO');
    expect(rel.payload.sourceId).toBe(reply.id);
    expect(rel.payload.targetId).toBe(original.id);
    expect(rel.createdByCertId).toBe('cert-author');

    // The substrate-graph view: list outgoing relations from the reply.
    const outgoing = await listRelationsFrom(db, reply.id);
    expect(outgoing).toHaveLength(1);
    expect(outgoing[0]?.payload.kind).toBe('REPLIES_TO');
  });

  test('CG2 turn with no quotedTurnId is a no-op (returns null)', async () => {
    const conv = await createObject(db, { objectKind: 'conversation', payload: {} });
    const t = await createObject(db, {
      id: 'turn-3',
      objectKind: 'conversation.turn',
      payload: {},
    });

    const turn: Turn = {
      conversationId: conv.id,
      turnId: t.id,
      // no quotedTurnId
    };
    const rel = await autoEmitReplyRelation(db, turn);
    expect(rel).toBeNull();

    const outgoing = await listRelationsFrom(db, t.id);
    expect(outgoing).toHaveLength(0);
  });

  test('CG3 capability check thunk is forwarded to createRelation', async () => {
    const conv = await createObject(db, { objectKind: 'conversation', payload: {} });
    const a = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const b = await createObject(db, { objectKind: 'conversation.turn', payload: {} });

    let checked = 0;
    await expect(
      autoEmitReplyRelation(
        db,
        { conversationId: conv.id, turnId: b.id, quotedTurnId: a.id },
        {
          capabilityCheck: async () => {
            checked += 1;
            throw new Error('capability denied');
          },
        },
      ),
    ).rejects.toThrow('capability denied');
    expect(checked).toBe(1);

    // The denied capability prevented the relation from being created.
    const outgoing = await listRelationsFrom(db, b.id);
    expect(outgoing).toHaveLength(0);
  });
});

describe('makeReplyRelationEmitter (D-SCG-oddjobz-consumer-cutover)', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('CUT1 emits REPLIES_TO from a brain-side reply request when quotedTurnId set', async () => {
    const conv = await createObject(db, { objectKind: 'conversation', payload: {} });
    const original = await createObject(db, {
      objectKind: 'conversation.turn',
      payload: { body: 'the message' },
    });
    const reply = await createObject(db, {
      objectKind: 'conversation.turn',
      payload: { body: 'the reply' },
    });

    const emit = makeReplyRelationEmitter(db);
    const rel = await emit({
      conversationId: conv.id,
      turnId: reply.id,
      quotedTurnId: original.id,
      authorCertId: 'cert_ai_xyz',
    });

    expect(rel).not.toBeNull();
    if (!rel) return;
    expect(rel.objectKind).toBe(RELATION_OBJECT_KIND);
    expect(rel.payload.kind).toBe('REPLIES_TO');
    expect(rel.payload.sourceId).toBe(reply.id); // source = the quoting turn
    expect(rel.payload.targetId).toBe(original.id); // target = the quoted turn
    expect(rel.createdByCertId).toBe('cert_ai_xyz');

    const outgoing = await listRelationsFrom(db, reply.id);
    expect(outgoing).toHaveLength(1);
    expect(outgoing[0]?.payload.kind).toBe('REPLIES_TO');
  });

  test('CUT2 a request with no quotedTurnId is a no-op (returns null)', async () => {
    const t = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const emit = makeReplyRelationEmitter(db);
    const rel = await emit({ turnId: t.id }); // no quotedTurnId
    expect(rel).toBeNull();
    expect(await listRelationsFrom(db, t.id)).toHaveLength(0);
  });

  test('CUT3 an un-cert’d turn omits createdByCertId', async () => {
    const a = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const b = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const emit = makeReplyRelationEmitter(db);
    const rel = await emit({ turnId: b.id, quotedTurnId: a.id });
    expect(rel).not.toBeNull();
    // The persisted row carries no author binding (null, not a fabricated cert).
    expect(rel?.createdByCertId ?? null).toBeNull();
  });

  test('CUT4 capability check is forwarded; a denied check emits no relation', async () => {
    const a = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const b = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    let checked = 0;
    const emit = makeReplyRelationEmitter(db, {
      capabilityCheck: async () => {
        checked += 1;
        throw new Error('capability denied');
      },
    });
    await expect(emit({ turnId: b.id, quotedTurnId: a.id })).rejects.toThrow(
      'capability denied',
    );
    expect(checked).toBe(1);
    expect(await listRelationsFrom(db, b.id)).toHaveLength(0);
  });
});

```
