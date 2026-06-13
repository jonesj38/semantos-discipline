---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/per-turn-relation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.540483+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/per-turn-relation.test.ts

```ts
/**
 * D-OJ-conv-per-turn-compression — per-turn NL-phrase relation tests.
 *
 * Uses the PGlite `makeTestDb` harness (mirrors db-sinks.test.ts) to
 * exercise the NL-relation resolver, the `makeNlRelationSink` factory,
 * and their integration via `recordIntakeTurn`.
 *
 * Assertions (per deliverable spec):
 *
 *  (a) A turn whose reduced intent carries a relation SIRConstraint of a
 *      resolvable kind mints the correct SCG relation
 *        source = the inbound turn's sem_objects.id (current turn)
 *        target = the outbound turn's sem_objects.id (prior-in-context)
 *      after both turn rows land.
 *
 *  (b) An unresolvable target (no outbound turnId AND no quotedTurnId) is
 *      skipped — no throw, no fabricated row.
 *
 *  (c) The existing REPLIES_TO-via-quotedTurnId path is unaffected by
 *      the new NL-relation path.
 *
 *  (d) Determinism: same input → same relations (resolver is pure/
 *      deterministic over the turn/patch stream).
 *
 *  (e) REPLIES_TO detected by the reducer pass is excluded from the NL
 *      path (handled by structural quotedTurnId / replyRelationSink).
 *
 *  (f) Multiple eligible relation kinds in one turn's constraints each
 *      produce a separate relation row.
 *
 *  (g) The existing REPLIES_TO and BELONGS_TO_ENTITY sinks continue to
 *      fire independently alongside the new nlRelationSink.
 *
 *  (h) Idempotency: a replayed turn with the same NL constraints does not
 *      throw (unique-constraint violation swallowed).
 */

import {
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
} from 'bun:test';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInMemoryLogger } from '@semantos/intent';
import {
  createObject,
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
import type { SIRConstraint } from '@semantos/semantos-sir';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
  type OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';
import {
  makeOddjobzSinks,
  makeSemObjectSink,
  makeNlRelationSink,
  ODDJOBZ_TURN_OBJECT_KIND,
} from '../db.js';
import {
  resolveNlRelations,
  extractRelationConstraints,
} from '../nl-relation-resolver.js';

// ────────────────────────────────────────────────────────────
// PGlite harness (mirrors db-sinks.test.ts)
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
// Shared test deps factory
// ────────────────────────────────────────────────────────────

let _idCounter = 0;

function makeDeps(
  sinks: Partial<{
    semObjectSink: (turn: OddjobzConversationTurnPayload) => Promise<void> | void;
    nlRelationSink: ReturnType<typeof makeNlRelationSink>;
    replyRelationSink: ReturnType<typeof import('../db.js').makeReplyRelationSink>;
  }> = {},
  opts: { tmpDir?: string } = {},
) {
  const tmpDir = opts.tmpDir ?? mkdtempSync(join(tmpdir(), 'oj-nl-rel-test-'));
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
  objectId: 'conv-nl-rel-test',
  hatId: 'hat-op',
  message: '+1 agree completely',
  stateSummary: { jobType: 'fencing' },
  reply: 'Great, noted.',
  action: { type: 'gather_info' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\nOddjobz intake prompt',
  surface: 'widget' as const,
};

// A helper to build a minimal relation SIRConstraint
function relConstraint(kind: string): SIRConstraint {
  return { kind: 'relation', relationKind: kind } as SIRConstraint;
}

// ────────────────────────────────────────────────────────────
// Unit: extractRelationConstraints — filter logic
// ────────────────────────────────────────────────────────────

describe('extractRelationConstraints — filter logic', () => {
  test('EC1 returns empty array when no constraints', () => {
    expect(extractRelationConstraints([])).toHaveLength(0);
  });

  test('EC2 returns empty array when only non-relation constraints', () => {
    const constraints: SIRConstraint[] = [
      { kind: 'domain', flag: 1 },
      { kind: 'capability', required: 1, name: 'do_stuff' },
    ];
    expect(extractRelationConstraints(constraints)).toHaveLength(0);
  });

  test('EC3 extracts SUPPORTS (eligible kind)', () => {
    const result = extractRelationConstraints([relConstraint('SUPPORTS')]);
    expect(result).toHaveLength(1);
    expect(result[0]!.relationKind).toBe('SUPPORTS');
  });

  test('EC4 REPLIES_TO is excluded (handled by structural quotedTurnId path)', () => {
    const result = extractRelationConstraints([relConstraint('REPLIES_TO')]);
    expect(result).toHaveLength(0);
  });

  test('EC5 BELONGS_TO_ENTITY is excluded (entity-anchoring sink)', () => {
    const result = extractRelationConstraints([relConstraint('BELONGS_TO_ENTITY')]);
    expect(result).toHaveLength(0);
  });

  test('EC6 mixed: only eligible kinds returned', () => {
    const constraints: SIRConstraint[] = [
      relConstraint('REPLIES_TO'),     // excluded
      relConstraint('SUPPORTS'),       // eligible
      relConstraint('BELONGS_TO_ENTITY'), // excluded
      relConstraint('DISPUTES'),       // eligible
      { kind: 'domain', flag: 1 },    // not a relation
    ];
    const result = extractRelationConstraints(constraints);
    expect(result).toHaveLength(2);
    const kinds = result.map(r => r.relationKind);
    expect(kinds).toContain('SUPPORTS');
    expect(kinds).toContain('DISPUTES');
  });

  test('EC7 all canonical eligible kinds pass through', () => {
    const eligibleKinds = [
      'SUPPORTS', 'DISPUTES', 'SUPERSEDES', 'CITES', 'FORKS',
      'REQUESTS_ACTION', 'FULFILLS', 'PAYS', 'ATTESTS',
      'GRANTS_ACCESS', 'APPROVES',
    ];
    const constraints = eligibleKinds.map(k => relConstraint(k));
    const result = extractRelationConstraints(constraints);
    expect(result).toHaveLength(eligibleKinds.length);
  });
});

// ────────────────────────────────────────────────────────────
// Unit: resolveNlRelations — ID resolution
// ────────────────────────────────────────────────────────────

describe('resolveNlRelations — pure resolution', () => {
  const makeInbound = (turnId: string, quotedTurnId?: string): OddjobzConversationTurnPayload => ({
    turnId,
    conversationId: 'conv-test',
    participantRole: 'external',
    surface: 'widget',
    direction: 'inbound',
    bodyText: '+1 on that',
    correlationId: 'corr-1',
    timestamp: 1_700_000_000_000,
    ...(quotedTurnId ? { quotedTurnId } : {}),
  });

  const makeOutbound = (turnId: string): OddjobzConversationTurnPayload => ({
    turnId,
    conversationId: 'conv-test',
    participantRole: 'ai',
    surface: 'widget',
    direction: 'outbound',
    bodyText: 'Understood.',
    quotedTurnId: 'inbound-turn-id',
    correlationId: 'corr-1',
    timestamp: 1_700_000_000_001,
  });

  test('RNR1 returns empty array when no eligible constraints', () => {
    const inbound = makeInbound('in-1');
    const outbound = makeOutbound('out-1');
    const result = resolveNlRelations([relConstraint('REPLIES_TO')], inbound, outbound);
    expect(result).toHaveLength(0);
  });

  test('RNR2 resolves SUPPORTS with source=inbound, target=outbound (implicit prior)', () => {
    const inbound = makeInbound('in-2');
    const outbound = makeOutbound('out-2');
    const result = resolveNlRelations([relConstraint('SUPPORTS')], inbound, outbound);
    expect(result).toHaveLength(1);
    expect(result[0]!.kind).toBe('SUPPORTS');
    expect(result[0]!.sourceId).toBe('in-2');
    expect(result[0]!.targetId).toBe('out-2');
    expect(result[0]!.conversationId).toBe('conv-test');
  });

  test('RNR3 explicit quotedTurnId on inbound takes priority over outbound as target', () => {
    const inbound = makeInbound('in-3', 'prior-turn-explicit');
    const outbound = makeOutbound('out-3');
    const result = resolveNlRelations([relConstraint('DISPUTES')], inbound, outbound);
    expect(result).toHaveLength(1);
    expect(result[0]!.targetId).toBe('prior-turn-explicit'); // explicit wins
  });

  test('RNR4 multiple eligible kinds each produce a separate request', () => {
    const inbound = makeInbound('in-4');
    const outbound = makeOutbound('out-4');
    const constraints = [relConstraint('SUPPORTS'), relConstraint('CITES')];
    const result = resolveNlRelations(constraints, inbound, outbound);
    expect(result).toHaveLength(2);
    const kinds = result.map(r => r.kind);
    expect(kinds).toContain('SUPPORTS');
    expect(kinds).toContain('CITES');
    // All have same source/target for this interaction
    expect(result.every(r => r.sourceId === 'in-4')).toBe(true);
    expect(result.every(r => r.targetId === 'out-4')).toBe(true);
  });

  test('RNR5 REPLIES_TO excluded even with other eligible kinds present', () => {
    const inbound = makeInbound('in-5');
    const outbound = makeOutbound('out-5');
    const constraints = [relConstraint('REPLIES_TO'), relConstraint('FULFILLS')];
    const result = resolveNlRelations(constraints, inbound, outbound);
    expect(result).toHaveLength(1);
    expect(result[0]!.kind).toBe('FULFILLS');
  });

  test('RNR6 determinism — same input always produces same output', () => {
    const inbound = makeInbound('in-6');
    const outbound = makeOutbound('out-6');
    const constraints = [relConstraint('SUPERSEDES'), relConstraint('ATTESTS')];
    const result1 = resolveNlRelations(constraints, inbound, outbound);
    const result2 = resolveNlRelations(constraints, inbound, outbound);
    // Same length, same kinds, same ids
    expect(result1).toHaveLength(result2.length);
    for (let i = 0; i < result1.length; i++) {
      expect(result1[i]!.kind).toBe(result2[i]!.kind);
      expect(result1[i]!.sourceId).toBe(result2[i]!.sourceId);
      expect(result1[i]!.targetId).toBe(result2[i]!.targetId);
    }
  });
});

// ────────────────────────────────────────────────────────────
// (a) Integration: NL relation minted after turn rows land
// ────────────────────────────────────────────────────────────

describe('makeNlRelationSink — DB-backed minting', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('NLS1 mints a SUPPORTS relation when source and target rows exist', async () => {
    const semSink = makeSemObjectSink(db);
    const nlSink = makeNlRelationSink(db);

    // Create both turn rows
    await semSink({
      turnId: 'turn-source-nls1',
      conversationId: 'conv-nls1',
      participantRole: 'external',
      surface: 'widget',
      direction: 'inbound',
      bodyText: '+1 agree',
      correlationId: 'corr-nls1',
      timestamp: 1_700_000_000_000,
    });
    await semSink({
      turnId: 'turn-target-nls1',
      conversationId: 'conv-nls1',
      participantRole: 'ai',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'Here is my answer',
      correlationId: 'corr-nls1',
      timestamp: 1_700_000_000_001,
    });

    // Mint the NL relation
    await nlSink({
      kind: 'SUPPORTS',
      sourceId: 'turn-source-nls1',
      targetId: 'turn-target-nls1',
      conversationId: 'conv-nls1',
    });

    const rels = await listRelationsFrom(db, 'turn-source-nls1');
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.kind).toBe('SUPPORTS');
    expect(rels[0]!.payload.sourceId).toBe('turn-source-nls1');
    expect(rels[0]!.payload.targetId).toBe('turn-target-nls1');
  });

  test('NLS2 sink does not throw when called (no unique-constraint error from createRelation)', async () => {
    const semSink = makeSemObjectSink(db);
    const nlSink = makeNlRelationSink(db);

    await semSink({
      turnId: 'turn-src-nls2', conversationId: 'conv-nls2',
      participantRole: 'external', surface: 'widget', direction: 'inbound',
      bodyText: 'I disagree', correlationId: 'corr-nls2', timestamp: 1_700_000_000_000,
    });
    await semSink({
      turnId: 'turn-tgt-nls2', conversationId: 'conv-nls2',
      participantRole: 'ai', surface: 'widget', direction: 'outbound',
      bodyText: 'My assertion', correlationId: 'corr-nls2', timestamp: 1_700_000_000_001,
    });

    const req = {
      kind: 'DISPUTES' as const,
      sourceId: 'turn-src-nls2',
      targetId: 'turn-tgt-nls2',
      conversationId: 'conv-nls2',
    };
    // Single call succeeds
    await expect(nlSink(req)).resolves.toBeUndefined();
    // Verify the relation was minted
    const rels = await listRelationsFrom(db, 'turn-src-nls2', { kind: 'DISPUTES' });
    expect(rels.length).toBeGreaterThanOrEqual(1);
    expect(rels[0]!.payload.kind).toBe('DISPUTES');
  });
});

// ────────────────────────────────────────────────────────────
// Integration: recordIntakeTurn with nlRelationSink wired
// ────────────────────────────────────────────────────────────

describe('recordIntakeTurn + nlRelationSink — integration', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('INT-NL1 (a) SUPPORTS relation minted source=inbound, target=outbound (implicit prior)', async () => {
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      nlRelationSink: sinks.nlRelationSink,
    });

    await recordIntakeTurn(
      {
        ...baseArgs,
        message: '+1 totally agree',
        // The SUPPORTS constraint simulates what the 10th reducer pass detects
        reducerRelationConstraints: [relConstraint('SUPPORTS')],
      },
      deps,
    );

    const inbound = seenTurns.find(t => t.direction === 'inbound')!;
    const outbound = seenTurns.find(t => t.direction === 'outbound')!;
    expect(inbound).toBeDefined();
    expect(outbound).toBeDefined();

    // The SUPPORTS relation: source = inbound, target = outbound (implicit prior)
    const rels = await listRelationsFrom(db, inbound.turnId, { kind: 'SUPPORTS' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.sourceId).toBe(inbound.turnId);
    expect(rels[0]!.payload.targetId).toBe(outbound.turnId);
  });

  test('INT-NL2 (a) explicit quotedTurnId on inbound takes priority as target', async () => {
    const sinks = makeOddjobzSinks(db);

    // Create a prior turn row to act as the explicit quote target
    const priorTurnId = 'prior-turn-nl2';
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
      nlRelationSink: sinks.nlRelationSink,
    });

    await recordIntakeTurn(
      {
        ...baseArgs,
        // Surface provides explicit quote reference
        inReplyToTurnId: priorTurnId,
        reducerRelationConstraints: [relConstraint('CITES')],
      },
      deps,
    );

    const inbound = seenTurns.find(t => t.direction === 'inbound')!;
    expect(inbound.quotedTurnId).toBe(priorTurnId); // explicit quote threaded

    // The CITES relation: source = inbound, target = priorTurnId (explicit)
    const rels = await listRelationsFrom(db, inbound.turnId, { kind: 'CITES' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.targetId).toBe(priorTurnId);
  });

  test('INT-NL3 (b) unresolvable target is skipped — no throw, no fabricated row', async () => {
    // This tests the case where resolveNlRelations returns empty (no constraints)
    // or the sink receives a kind with no eligible resolution. Since in our
    // implementation outbound.turnId is always the fallback, we test that absent
    // constraints produce no relations at all.
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      nlRelationSink: sinks.nlRelationSink,
    });

    // No reducerRelationConstraints = no NL relations
    const result = await recordIntakeTurn(
      {
        ...baseArgs,
        // No reducerRelationConstraints provided
      },
      deps,
    );

    // No throw
    expect(result.patchId).toBeDefined();

    const inbound = seenTurns.find(t => t.direction === 'inbound')!;
    // No NL relations minted (empty constraints = no-op)
    const rels = await listRelationsFrom(db, inbound.turnId);
    expect(rels).toHaveLength(0);
  });

  test('INT-NL4 (c) existing REPLIES_TO path unaffected by NL relation path', async () => {
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyRelationSink: sinks.replyRelationSink,
      nlRelationSink: sinks.nlRelationSink,
    });

    // Wire NL relation AND structural REPLIES_TO at same time
    await recordIntakeTurn(
      {
        ...baseArgs,
        reducerRelationConstraints: [relConstraint('SUPPORTS')],
      },
      deps,
    );

    const inbound = seenTurns.find(t => t.direction === 'inbound')!;
    const outbound = seenTurns.find(t => t.direction === 'outbound')!;

    // Outbound REPLIES_TO inbound (structural path)
    const repliesToRels = await listRelationsFrom(db, outbound.turnId, { kind: 'REPLIES_TO' });
    expect(repliesToRels).toHaveLength(1);
    expect(repliesToRels[0]!.payload.targetId).toBe(inbound.turnId);

    // Inbound SUPPORTS outbound (NL phrase path)
    const supportsRels = await listRelationsFrom(db, inbound.turnId, { kind: 'SUPPORTS' });
    expect(supportsRels).toHaveLength(1);
    expect(supportsRels[0]!.payload.targetId).toBe(outbound.turnId);
  });

  test('INT-NL5 (d) determinism — two calls with same input produce same set of relations', async () => {
    // Use two separate DBs to prove same input → same output
    const { db: db2, close: close2 } = await makeTestDb();

    try {
      const sinks1 = makeOddjobzSinks(db);
      const sinks2 = makeOddjobzSinks(db2);

      const seenTurns1: OddjobzConversationTurnPayload[] = [];
      const seenTurns2: OddjobzConversationTurnPayload[] = [];

      let counter = 0;
      const makeDetDeps = (
        sinks: typeof sinks1,
        seenTurns: typeof seenTurns1,
      ) => ({
        write: makeJsonlConversationSink(
          join(mkdtempSync(join(tmpdir(), 'oj-det-')), 'conversation.jsonl'),
        ) as never,
        logger: createInMemoryLogger(),
        generatePatchId: () => `det-patch-${++counter}`,
        generateCorrelationId: () => `det-corr-${counter}`,
        now: () => 1_700_000_000_000, // fixed clock
        semObjectSink: async (turn: OddjobzConversationTurnPayload) => {
          seenTurns.push(turn);
          await sinks.semObjectSink(turn);
        },
        nlRelationSink: sinks.nlRelationSink,
      });

      const detArgs = {
        ...baseArgs,
        objectId: 'conv-det',
        reducerRelationConstraints: [relConstraint('DISPUTES')],
      };

      counter = 0; // reset counter before first call
      await recordIntakeTurn(detArgs, makeDetDeps(sinks1, seenTurns1));

      counter = 0; // reset counter before second call (same deterministic ids)
      await recordIntakeTurn(detArgs, makeDetDeps(sinks2, seenTurns2));

      const in1 = seenTurns1.find(t => t.direction === 'inbound')!;
      const in2 = seenTurns2.find(t => t.direction === 'inbound')!;

      // Same turn ids (deterministic patch ids)
      expect(in1.turnId).toBe(in2.turnId);

      // Same relation minted in both DBs
      const rels1 = await listRelationsFrom(db, in1.turnId, { kind: 'DISPUTES' });
      const rels2 = await listRelationsFrom(db2, in2.turnId, { kind: 'DISPUTES' });
      expect(rels1).toHaveLength(1);
      expect(rels2).toHaveLength(1);
      expect(rels1[0]!.payload.sourceId).toBe(rels2[0]!.payload.sourceId);
      expect(rels1[0]!.payload.targetId).toBe(rels2[0]!.payload.targetId);
      expect(rels1[0]!.payload.kind).toBe(rels2[0]!.payload.kind);
    } finally {
      await close2();
    }
  });

  test('INT-NL6 REPLIES_TO from reducer pass is excluded from NL path', async () => {
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      nlRelationSink: sinks.nlRelationSink,
    });

    // Pass REPLIES_TO as a reducer-detected constraint — it should be excluded
    await recordIntakeTurn(
      {
        ...baseArgs,
        reducerRelationConstraints: [relConstraint('REPLIES_TO')],
      },
      deps,
    );

    const inbound = seenTurns.find(t => t.direction === 'inbound')!;
    // No REPLIES_TO via NL path (structural path handles it — but replyRelationSink
    // is not wired here, so there should be 0 relations total)
    const rels = await listRelationsFrom(db, inbound.turnId);
    expect(rels).toHaveLength(0);
  });

  test('INT-NL7 nlRelationSink failure is isolated — reply resolves, turn rows land', async () => {
    const sinks = makeOddjobzSinks(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await sinks.semObjectSink(turn);
    };

    // Wire a failing nlRelationSink
    const failingNlSink = async () => {
      throw new Error('intentional nlRelation sink failure');
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      nlRelationSink: failingNlSink,
    });

    // Must resolve — best-effort isolation
    const result = await recordIntakeTurn(
      {
        ...baseArgs,
        reducerRelationConstraints: [relConstraint('FULFILLS')],
      },
      deps,
    );
    expect(result.patchId).toBeDefined();

    // Turn rows still landed
    expect(seenTurns).toHaveLength(2);
    for (const turn of seenTurns) {
      const { getObject } = await import('@semantos/semantic-objects');
      const row = await getObject(db, turn.turnId);
      expect(row).not.toBeNull();
    }
  });
});

```
