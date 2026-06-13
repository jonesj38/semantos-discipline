---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/db-sinks.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.541017+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/db-sinks.test.ts

```ts
/**
 * D-OJ-conv-sem-objects-sink-activation — real Database-backed sink tests.
 *
 * Uses the PGlite `makeTestDb` harness (from
 * `core/semantic-objects/src/__tests__/setup.ts`) to inject a real
 * Database into the sink factory and asserts:
 *
 *  (a) A `sem_objects` row of objectKind 'oddjobz.conversation.turn'
 *      lands for each persisted turn, and its `id` equals the turn's
 *      `turnId` (the deterministic id contract on which the relation
 *      sinks depend).
 *
 *  (b) When an `entityRef` is set AND the entity row exists, a
 *      `BELONGS_TO_ENTITY` relation is minted with source=turnId,
 *      target=entityCellHash.
 *
 *  (c) When `quotedTurnId` is set AND the target turn row exists, a
 *      `REPLIES_TO` relation is minted with source=turnId,
 *      target=quotedTurnId.
 *
 *  (d) Idempotency: a second call with the same turnId does not
 *      throw (unique-constraint violation is swallowed silently).
 *
 *  (e) BELONGS_TO_ENTITY is skipped (no throw) when the entity row
 *      does not yet exist (target-must-exist §7.2 best-effort).
 *
 * Test harness mirrors the existing Oddjobz conversation tests —
 * createInMemoryLogger + makeJsonlConversationSink file-free pattern
 * (we stub the write to /dev/null via tmpdir).
 */

import {
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
  beforeAll,
} from 'bun:test';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInMemoryLogger } from '@semantos/intent';
import {
  createObject,
  getObject,
  type Database,
} from '@semantos/semantic-objects';
import {
  listRelationsFrom,
} from '@semantos/scg-relations';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
  type OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';
import {
  makeOddjobzSinks,
  makeSemObjectSink,
  makeRelationSink,
  makeReplyRelationSink,
  ODDJOBZ_TURN_OBJECT_KIND,
} from '../db.js';

// ────────────────────────────────────────────────────────────
// PGlite harness (mirrors core/scg-relations/src/__tests__/setup.ts)
// ────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../../../../../core/semantic-objects/migrations/0000_init.sql',
);

async function makeTestDb(): Promise<{
  db: Database;
  close: () => Promise<void>;
}> {
  const pg = new PGlite();
  await pg.waitReady;
  const db = drizzle(pg) as unknown as Database;
  const sql = readFileSync(MIGRATION_PATH, 'utf-8');
  for (const stmt of splitSql(sql)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  return { db, async close() { await pg.close(); } };
}

function splitSql(sql: string): string[] {
  const out: string[] = [];
  const lines = sql.split('\n');
  let buf: string[] = [];
  let inDoBlock = false;
  for (const line of lines) {
    if (line.trim().startsWith('--')) continue;
    buf.push(line);
    if (/\bDO \$\$/i.test(line)) inDoBlock = true;
    if (inDoBlock && /END \$\$;/.test(line)) {
      inDoBlock = false;
      out.push(buf.join('\n'));
      buf = [];
      continue;
    }
    if (!inDoBlock && line.trimEnd().endsWith(';')) {
      out.push(buf.join('\n'));
      buf = [];
    }
  }
  if (buf.length) out.push(buf.join('\n'));
  return out;
}

// ────────────────────────────────────────────────────────────
// Test deps factory (mirrors existing conversation-turn-patch.test.ts)
// ────────────────────────────────────────────────────────────

let _idCounter = 0;

function makeDeps(
  sinks: Partial<{
    semObjectSink: (turn: OddjobzConversationTurnPayload) => Promise<void> | void;
    relationSink: ReturnType<typeof makeRelationSink>;
    replyRelationSink: ReturnType<typeof makeReplyRelationSink>;
  }> = {},
  opts: { tmpDir?: string } = {},
) {
  const tmpDir = opts.tmpDir ?? mkdtempSync(join(tmpdir(), 'oj-sink-test-'));
  return {
    write: makeJsonlConversationSink(join(tmpDir, 'conversation.jsonl')) as never,
    logger: createInMemoryLogger(),
    generatePatchId: () => `patch-${++_idCounter}`,
    generateCorrelationId: () => `corr-${_idCounter}`,
    now: () => 1_700_000_000_000,
    ...sinks,
  };
}

const baseArgs = {
  objectId: 'conv-sink-test',
  hatId: 'hat-op',
  message: 'Need a colorbond fence quote',
  stateSummary: { jobType: 'fencing' },
  reply: 'Sure — what length?',
  action: { type: 'gather_info' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\nOddjobz intake prompt',
  surface: 'widget' as const,
};

// ────────────────────────────────────────────────────────────
// (a) semObjectSink — row id equals turnId
// ────────────────────────────────────────────────────────────

describe('makeSemObjectSink — row persistence', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('SK1 persists a turn as a sem_objects row with id == turnId', async () => {
    const sink = makeSemObjectSink(db);
    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-in-test-abc',
      conversationId: 'conv-1',
      participantRole: 'external',
      surface: 'widget',
      direction: 'inbound',
      bodyText: 'hello',
      correlationId: 'corr-1',
      timestamp: 1_700_000_000_000,
    };
    await sink(turn);

    const row = await getObject<OddjobzConversationTurnPayload>(db, 'turn-in-test-abc');
    expect(row).not.toBeNull();
    expect(row?.id).toBe('turn-in-test-abc');
    expect(row?.objectKind).toBe(ODDJOBZ_TURN_OBJECT_KIND);
    expect(row?.payload.turnId).toBe('turn-in-test-abc');
    expect(row?.payload.direction).toBe('inbound');
    expect(row?.payload.bodyText).toBe('hello');
  });

  test('SK2 a replayed turn (same turnId) does not throw (idempotency)', async () => {
    const sink = makeSemObjectSink(db);
    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-idempotent-xyz',
      conversationId: 'conv-2',
      participantRole: 'ai',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'reply body',
      correlationId: 'corr-2',
      timestamp: 1_700_000_000_001,
    };
    await sink(turn); // first insert
    await expect(sink(turn)).resolves.toBeUndefined(); // second call — must not throw
  });

  test('SK3 createdByCertId is threaded from actorCertId', async () => {
    const sink = makeSemObjectSink(db);
    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-cert-bind',
      conversationId: 'conv-3',
      participantRole: 'operator',
      actorCertId: 'cert_op_001',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'operator reply',
      correlationId: 'corr-3',
      timestamp: 1_700_000_000_002,
    };
    await sink(turn);
    const row = await getObject<OddjobzConversationTurnPayload>(db, 'turn-cert-bind');
    expect(row?.createdByCertId).toBe('cert_op_001');
  });
});

// ────────────────────────────────────────────────────────────
// (b) relationSink — BELONGS_TO_ENTITY
// ────────────────────────────────────────────────────────────

describe('makeRelationSink — BELONGS_TO_ENTITY', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('BTE1 mints a BELONGS_TO_ENTITY relation when entity row exists', async () => {
    const semSink = makeSemObjectSink(db);
    const relSink = makeRelationSink(db);

    // Create the entity row (simulates the job/site/customer cell in sem_objects)
    const entityCellHash = 'entity-cell-hash-001';
    await createObject(db, {
      id: entityCellHash,
      objectKind: 'oddjobz.job',
      payload: { kind: 'job', ref: 'JOB-42' },
    });

    // Persist the turn
    await semSink({
      turnId: 'turn-bte-001',
      conversationId: 'conv-bte',
      participantRole: 'external',
      surface: 'widget',
      direction: 'inbound',
      bodyText: 'message',
      correlationId: 'corr-bte',
      timestamp: 1_700_000_000_000,
      entityRef: { kind: 'job', cellHash: entityCellHash },
    });

    // Emit the BELONGS_TO_ENTITY relation
    await relSink({
      kind: 'BELONGS_TO_ENTITY',
      turnId: 'turn-bte-001',
      entityCellHash,
      entityKind: 'job',
    });

    // Assert the relation was minted
    const outgoing = await listRelationsFrom(db, 'turn-bte-001');
    expect(outgoing).toHaveLength(1);
    const rel = outgoing[0]!;
    expect(rel.payload.kind).toBe('BELONGS_TO_ENTITY');
    expect(rel.payload.sourceId).toBe('turn-bte-001');
    expect(rel.payload.targetId).toBe(entityCellHash);
  });

  test('BTE2 skips (no throw) when entity row does not yet exist', async () => {
    const relSink = makeRelationSink(db);
    // Entity row intentionally NOT created — target-must-exist fails silently
    await expect(
      relSink({
        kind: 'BELONGS_TO_ENTITY',
        turnId: 'turn-bte-missing',
        entityCellHash: 'entity-does-not-exist',
        entityKind: 'job',
      }),
    ).resolves.toBeUndefined(); // no throw

    // No relation in the DB
    const outgoing = await listRelationsFrom(db, 'turn-bte-missing');
    expect(outgoing).toHaveLength(0);
  });
});

// ────────────────────────────────────────────────────────────
// (c) replyRelationSink — REPLIES_TO
// ────────────────────────────────────────────────────────────

describe('makeReplyRelationSink — REPLIES_TO', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('RT1 mints a REPLIES_TO relation when quotedTurnId is set and both rows exist', async () => {
    const semSink = makeSemObjectSink(db);
    const replySink = makeReplyRelationSink(db);

    // Persist both turns
    await semSink({
      turnId: 'turn-quoted-001',
      conversationId: 'conv-rt',
      participantRole: 'external',
      surface: 'widget',
      direction: 'inbound',
      bodyText: 'original message',
      correlationId: 'corr-rt',
      timestamp: 1_700_000_000_000,
    });
    await semSink({
      turnId: 'turn-reply-001',
      conversationId: 'conv-rt',
      participantRole: 'ai',
      actorCertId: 'cert_ai_001',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'reply body',
      quotedTurnId: 'turn-quoted-001',
      correlationId: 'corr-rt',
      timestamp: 1_700_000_000_001,
    });

    // Emit the REPLIES_TO relation
    await replySink({
      kind: 'REPLIES_TO',
      turnId: 'turn-reply-001',
      quotedTurnId: 'turn-quoted-001',
      authorCertId: 'cert_ai_001',
    });

    // Assert the relation was minted
    const outgoing = await listRelationsFrom(db, 'turn-reply-001');
    expect(outgoing).toHaveLength(1);
    const rel = outgoing[0]!;
    expect(rel.payload.kind).toBe('REPLIES_TO');
    expect(rel.payload.sourceId).toBe('turn-reply-001');
    expect(rel.payload.targetId).toBe('turn-quoted-001');
    expect(rel.createdByCertId).toBe('cert_ai_001');
  });
});

// ────────────────────────────────────────────────────────────
// Integration: recordIntakeTurn with real sinks via makeOddjobzSinks
// ────────────────────────────────────────────────────────────

describe('makeOddjobzSinks — integration via recordIntakeTurn', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('INT1 turn rows land for both inbound and outbound with id == turnId', async () => {
    const { semObjectSink } = makeOddjobzSinks(db);

    const seenTurnIds: string[] = [];
    const capturingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurnIds.push(turn.turnId);
      await semObjectSink(turn);
    };

    const deps = makeDeps({ semObjectSink: capturingSink });
    await recordIntakeTurn(baseArgs, deps);

    expect(seenTurnIds).toHaveLength(2);
    // Assert both rows landed in the DB with the correct objectKind
    for (const turnId of seenTurnIds) {
      const row = await getObject<OddjobzConversationTurnPayload>(db, turnId);
      expect(row).not.toBeNull();
      expect(row?.objectKind).toBe(ODDJOBZ_TURN_OBJECT_KIND);
      expect(row?.id).toBe(turnId);
    }
  });

  test('INT2 BELONGS_TO_ENTITY relation minted when entityRef set and entity row exists', async () => {
    const entityCellHash = 'entity-cell-int2';
    // Pre-create the entity row
    await createObject(db, {
      id: entityCellHash,
      objectKind: 'oddjobz.job',
      payload: { ref: 'INT2-JOB' },
    });

    const sinks = makeOddjobzSinks(db);
    const deps = makeDeps({
      semObjectSink: sinks.semObjectSink,
      relationSink: sinks.relationSink,
    });

    const seenTurnIds: string[] = [];
    const originalSemSink = sinks.semObjectSink;
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurnIds.push(turn.turnId);
      await originalSemSink(turn);
    };

    await recordIntakeTurn(
      {
        ...baseArgs,
        entityRef: { kind: 'job', cellHash: entityCellHash },
      },
      {
        ...deps,
        semObjectSink: trackingSink,
        relationSink: sinks.relationSink,
      },
    );

    // Each of the 2 turns should have a BELONGS_TO_ENTITY relation
    for (const turnId of seenTurnIds) {
      const rels = await listRelationsFrom(db, turnId, { kind: 'BELONGS_TO_ENTITY' });
      expect(rels).toHaveLength(1);
      expect(rels[0]!.payload.targetId).toBe(entityCellHash);
    }
  });

  test('INT3 REPLIES_TO relation minted for the outbound turn (quotedTurnId = inbound turnId)', async () => {
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyRelationSink: sinks.replyRelationSink,
    });
    await recordIntakeTurn(baseArgs, deps);

    // The outbound turn carries quotedTurnId = inbound turnId
    const outbound = seenTurns.find((t) => t.direction === 'outbound');
    expect(outbound?.quotedTurnId).toBeDefined();

    // Assert a REPLIES_TO relation was minted from the outbound turn
    const rels = await listRelationsFrom(db, outbound!.turnId, { kind: 'REPLIES_TO' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.sourceId).toBe(outbound!.turnId);
    expect(rels[0]!.payload.targetId).toBe(outbound!.quotedTurnId);
  });

  test('INT4 inbound turn with explicit inReplyToTurnId gets REPLIES_TO relation', async () => {
    const sinks = makeOddjobzSinks(db);

    // Create a prior-turn row to quote
    const priorTurnId = 'turn-prior-int4';
    await createObject(db, {
      id: priorTurnId,
      objectKind: ODDJOBZ_TURN_OBJECT_KIND,
      payload: { turnId: priorTurnId, direction: 'outbound' },
    });

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyRelationSink: sinks.replyRelationSink,
    });
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: priorTurnId },
      deps,
    );

    // The inbound turn should have quotedTurnId = priorTurnId
    const inbound = seenTurns.find((t) => t.direction === 'inbound');
    expect(inbound?.quotedTurnId).toBe(priorTurnId);

    // REPLIES_TO from inbound → priorTurnId
    const rels = await listRelationsFrom(db, inbound!.turnId, { kind: 'REPLIES_TO' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.targetId).toBe(priorTurnId);
  });

  test('INT5 sink failures are isolated — jsonl path still resolves', async () => {
    // Wire a semObjectSink that always throws
    const failingSink = async (_turn: OddjobzConversationTurnPayload): Promise<void> => {
      throw new Error('intentional sink failure');
    };

    const deps = makeDeps({ semObjectSink: failingSink });
    // recordIntakeTurn must resolve (not throw) — jsonl path is never blocked
    const result = await recordIntakeTurn(baseArgs, deps);
    expect(result.patchId).toBeDefined();
  });
});

```
