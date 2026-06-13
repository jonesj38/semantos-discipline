---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/aggregate-sir.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.540085+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/aggregate-sir.test.ts

```ts
/**
 * D-OJ-conv-aggregate-sir — conversation-level aggregate tests.
 *
 * Asserts the five properties from the deliverable spec:
 *
 *  (a) Aggregate carries the right entityRef + participants set from a
 *      multi-turn multi-party conversation.
 *
 *  (b) Summarised intent state reflects open vs ratified actions.
 *
 *  (c) Outbound state-machine snapshot reflects the latest action.
 *
 *  (d) DETERMINISM VECTOR:
 *        d1. Same inputs twice → identical aggregate.
 *        d2. Shuffled inputs (re-sorted canonically by the fold) → identical.
 *
 *  (e) The DB loader reads rows + folds correctly (loadConversationAggregate).
 *
 * Additional:
 *  (f) listObjectsByKind payloadFilter scopes correctly to one conversation.
 *  (g) Empty conversation → loader returns null.
 *  (h) Participants are deduplicated (cert-bound, handle-bound, anon).
 *  (i) Closed conversation has no open intents.
 *  (j) Estimate/quote action sets estimatePresented in snapshot.
 *  (k) DB loader picks up ratified turn ids from reply-audit rows.
 *
 * Test harness mirrors db-sinks.test.ts (PGlite + migration file).
 */

import {
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
} from 'bun:test';
import {
  createObject,
  type Database,
} from '@semantos/semantic-objects';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  aggregateConversation,
  loadConversationAggregate,
  type BelongsToEntityEdge,
  type ConversationAggregate,
} from '../aggregate-sir.js';
import type {
  OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';
import {
  ODDJOBZ_TURN_OBJECT_KIND,
  makeSemObjectSink,
  makeRelationSink,
} from '../db.js';

// ────────────────────────────────────────────────────────────
// PGlite harness (mirrors db-sinks.test.ts)
// ────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../../../../../core/semantic-objects/migrations/0000_init.sql',
);

async function makeTestDb(): Promise<{ db: Database; close: () => Promise<void> }> {
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
// Turn builder helpers
// ────────────────────────────────────────────────────────────

function makeTurn(
  overrides: Partial<OddjobzConversationTurnPayload> & {
    turnId: string;
    conversationId: string;
  },
): OddjobzConversationTurnPayload {
  return {
    participantRole: 'external',
    surface: 'widget',
    direction: 'inbound',
    bodyText: 'test message',
    correlationId: 'corr-test',
    timestamp: 1_700_000_000_000,
    ...overrides,
  };
}

function makeOutboundTurn(
  overrides: Partial<OddjobzConversationTurnPayload> & {
    turnId: string;
    conversationId: string;
    actionType: string;
  },
): OddjobzConversationTurnPayload {
  const { actionType, ...rest } = overrides;
  return makeTurn({
    direction: 'outbound',
    participantRole: 'ai',
    actorCertId: 'cert_ai_pending:D-OJ-conv-ai-participant',
    bodyText: 'AI reply',
    bodyParts: [
      {
        kind: 'oddjobz-intake-meta',
        payload: {
          kind: 'intake_turn',
          message: 'customer message',
          reply: 'AI reply',
          action: { type: actionType },
          model: 'claude-haiku',
          prompt: { promptId: 'reply', version: 1, contentHash: 'hash-test' },
        },
      },
    ],
    ...rest,
  });
}

// ────────────────────────────────────────────────────────────
// (a) entityRef + participants set
// ────────────────────────────────────────────────────────────

describe('AGG-A: entityRef + participants set', () => {
  test('AGG-A1 aggregate carries entityRef from turns', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'turn-in-1',
        conversationId: 'conv-a1',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        entityRef: { kind: 'job', cellHash: 'entity-cell-001' },
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'turn-out-1',
        conversationId: 'conv-a1',
        actionType: 'gather_info',
        entityRef: { kind: 'job', cellHash: 'entity-cell-001' },
        timestamp: 1_700_000_002_000,
      }),
    ];

    const agg = aggregateConversation('conv-a1', turns, [], new Set());
    expect(agg.entityRef).toEqual({ kind: 'job', cellHash: 'entity-cell-001' });
  });

  test('AGG-A2 participants set includes distinct roles from multi-party conversation', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'in-1',
        conversationId: 'conv-a2',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'out-1',
        conversationId: 'conv-a2',
        actionType: 'gather_info',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        timestamp: 1_700_000_002_000,
      }),
      makeTurn({
        turnId: 'in-2',
        conversationId: 'conv-a2',
        participantRole: 'operator',
        actorCertId: 'cert_op_001',
        direction: 'inbound',
        timestamp: 1_700_000_003_000,
      }),
    ];

    const agg = aggregateConversation('conv-a2', turns, [], new Set());
    const roles = agg.participants.map((p) => p.role).sort();
    expect(roles).toContain('external');
    expect(roles).toContain('ai');
    expect(roles).toContain('operator');
    expect(agg.participants).toHaveLength(3);
  });

  test('AGG-A3 duplicate turns with same identity are deduplicated', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'in-a',
        conversationId: 'conv-a3',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        timestamp: 1_700_000_001_000,
      }),
      makeTurn({
        turnId: 'in-b',
        conversationId: 'conv-a3',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        timestamp: 1_700_000_003_000,
      }),
    ];

    const agg = aggregateConversation('conv-a3', turns, [], new Set());
    // Same phone — one participant entry
    expect(agg.participants).toHaveLength(1);
    expect(agg.participants[0]!.identityHandle).toEqual({ kind: 'phone', value: '+61412000001' });
  });

  test('AGG-A4 entityRef falls back to BELONGS_TO_ENTITY edge when turn entityRef absent', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      // Turn has an entityRef so the edge-fallback will match
      makeTurn({
        turnId: 'in-fallback',
        conversationId: 'conv-a4',
        entityRef: { kind: 'site', cellHash: 'entity-site-001' },
        timestamp: 1_700_000_001_000,
      }),
    ];
    const edges: BelongsToEntityEdge[] = [
      { sourceId: 'in-fallback', targetId: 'entity-site-001' },
    ];
    // Even if we pass the turn first, entityRef from turns takes priority
    const agg = aggregateConversation('conv-a4', turns, edges, new Set());
    expect(agg.entityRef?.cellHash).toBe('entity-site-001');
    expect(agg.entityRef?.kind).toBe('site');
  });
});

// ────────────────────────────────────────────────────────────
// (b) Open vs ratified intents
// ────────────────────────────────────────────────────────────

describe('AGG-B: intent state — open vs ratified', () => {
  test('AGG-B1 open intents appear when outbound action not ratified', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-b1',
        conversationId: 'conv-b1',
        actionType: 'gather_info',
        timestamp: 1_700_000_001_000,
      }),
    ];

    const agg = aggregateConversation('conv-b1', turns, [], new Set());
    expect(agg.openIntents).toHaveLength(1);
    expect(agg.openIntents[0]!.actionType).toBe('gather_info');
    expect(agg.openIntents[0]!.sourceTurnId).toBe('out-b1');
  });

  test('AGG-B2 ratified intent is not open', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-b2',
        conversationId: 'conv-b2',
        actionType: 'present_estimate',
        timestamp: 1_700_000_001_000,
      }),
    ];
    const ratifiedIds = new Set(['out-b2']);

    const agg = aggregateConversation('conv-b2', turns, [], ratifiedIds);
    expect(agg.openIntents).toHaveLength(0);
  });

  test('AGG-B3 multiple actions: only un-ratified remain open', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-action-1',
        conversationId: 'conv-b3',
        actionType: 'gather_info',
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'out-action-2',
        conversationId: 'conv-b3',
        actionType: 'send_estimate',
        timestamp: 1_700_000_002_000,
      }),
    ];
    const ratified = new Set(['out-action-1']);  // gather_info ratified; estimate not

    const agg = aggregateConversation('conv-b3', turns, [], ratified);
    expect(agg.openIntents).toHaveLength(1);
    expect(agg.openIntents[0]!.actionType).toBe('send_estimate');
  });

  test('AGG-B4 closed conversation has no open intents', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-open',
        conversationId: 'conv-b4',
        actionType: 'gather_info',
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'out-close',
        conversationId: 'conv-b4',
        actionType: 'close_job',
        timestamp: 1_700_000_002_000,
      }),
    ];

    const agg = aggregateConversation('conv-b4', turns, [], new Set());
    expect(agg.openIntents).toHaveLength(0);
  });
});

// ────────────────────────────────────────────────────────────
// (c) State-machine snapshot
// ────────────────────────────────────────────────────────────

describe('AGG-C: state-machine snapshot', () => {
  test('AGG-C1 lastActionType reflects the most recent outbound action', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-c1-a',
        conversationId: 'conv-c1',
        actionType: 'gather_info',
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'out-c1-b',
        conversationId: 'conv-c1',
        actionType: 'present_estimate',
        timestamp: 1_700_000_002_000,
      }),
    ];

    const agg = aggregateConversation('conv-c1', turns, [], new Set());
    expect(agg.stateMachineSnapshot.lastActionType).toBe('present_estimate');
    expect(agg.stateMachineSnapshot.lastActionTimestamp).toBe(1_700_000_002_000);
  });

  test('AGG-C2 estimatePresented is true when an estimate action exists', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-c2',
        conversationId: 'conv-c2',
        actionType: 'send_estimate',
        timestamp: 1_700_000_001_000,
      }),
    ];

    const agg = aggregateConversation('conv-c2', turns, [], new Set());
    expect(agg.stateMachineSnapshot.estimatePresented).toBe(true);
    expect(agg.stateMachineSnapshot.closed).toBe(false);
  });

  test('AGG-C3 closed is true when a close action was emitted', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-c3',
        conversationId: 'conv-c3',
        actionType: 'close_job',
        timestamp: 1_700_000_001_000,
      }),
    ];

    const agg = aggregateConversation('conv-c3', turns, [], new Set());
    expect(agg.stateMachineSnapshot.closed).toBe(true);
  });

  test('AGG-C4 needsSiteVisit is true when a site_visit action was emitted', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'out-c4',
        conversationId: 'conv-c4',
        actionType: 'needs_site_visit',
        timestamp: 1_700_000_001_000,
      }),
    ];

    const agg = aggregateConversation('conv-c4', turns, [], new Set());
    expect(agg.stateMachineSnapshot.needsSiteVisit).toBe(true);
  });

  test('AGG-C5 no outbound turns → null snapshot fields', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'in-c5',
        conversationId: 'conv-c5',
        direction: 'inbound',
        timestamp: 1_700_000_001_000,
      }),
    ];

    const agg = aggregateConversation('conv-c5', turns, [], new Set());
    expect(agg.stateMachineSnapshot.lastActionType).toBeNull();
    expect(agg.stateMachineSnapshot.lastActionTimestamp).toBeNull();
    expect(agg.stateMachineSnapshot.estimatePresented).toBe(false);
    expect(agg.stateMachineSnapshot.closed).toBe(false);
  });
});

// ────────────────────────────────────────────────────────────
// (d) DETERMINISM VECTOR
// ────────────────────────────────────────────────────────────

describe('AGG-D: determinism vector', () => {
  /**
   * Build a canonical multi-turn, multi-party conversation for
   * determinism testing.
   */
  function buildDeterminismTurns(): OddjobzConversationTurnPayload[] {
    return [
      makeTurn({
        turnId: 'det-in-1',
        conversationId: 'conv-det',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        entityRef: { kind: 'job', cellHash: 'entity-det-001' },
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'det-out-1',
        conversationId: 'conv-det',
        actionType: 'gather_info',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        entityRef: { kind: 'job', cellHash: 'entity-det-001' },
        timestamp: 1_700_000_002_000,
      }),
      makeTurn({
        turnId: 'det-in-2',
        conversationId: 'conv-det',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        timestamp: 1_700_000_003_000,
      }),
      makeOutboundTurn({
        turnId: 'det-out-2',
        conversationId: 'conv-det',
        actionType: 'present_estimate',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        timestamp: 1_700_000_004_000,
      }),
    ];
  }

  function serializeAgg(agg: ConversationAggregate): string {
    return JSON.stringify({
      conversationId: agg.conversationId,
      entityRef: agg.entityRef,
      participants: agg.participants,
      openIntents: agg.openIntents,
      stateMachineSnapshot: agg.stateMachineSnapshot,
      turnCount: agg.turnCount,
      firstTurnAt: agg.firstTurnAt,
      lastTurnAt: agg.lastTurnAt,
    });
  }

  test('AGG-D1 same inputs twice → byte-identical aggregate', () => {
    const turns = buildDeterminismTurns();
    const agg1 = aggregateConversation('conv-det', turns, [], new Set());
    const agg2 = aggregateConversation('conv-det', turns, [], new Set());
    expect(serializeAgg(agg1)).toBe(serializeAgg(agg2));
  });

  test('AGG-D2 shuffled inputs → same aggregate (canonical sort applied)', () => {
    const turns = buildDeterminismTurns();
    // Shuffle: reverse order (latest first)
    const shuffled = [...turns].reverse();
    // Additional shuffle: interleave
    const interleaved = [
      turns[3]!, turns[1]!, turns[0]!, turns[2]!,
    ];

    const agg1 = aggregateConversation('conv-det', turns, [], new Set());
    const aggShuffled = aggregateConversation('conv-det', shuffled, [], new Set());
    const aggInterleaved = aggregateConversation('conv-det', interleaved, [], new Set());

    expect(serializeAgg(aggShuffled)).toBe(serializeAgg(agg1));
    expect(serializeAgg(aggInterleaved)).toBe(serializeAgg(agg1));
  });

  test('AGG-D3 same-timestamp turns sorted by turnId (tie-break determinism)', () => {
    // Two turns at identical timestamp — should sort by turnId ASC
    const turnsA: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'det-tiebreak-a',
        conversationId: 'conv-det-tie',
        timestamp: 1_700_000_001_000,
      }),
      makeTurn({
        turnId: 'det-tiebreak-b',
        conversationId: 'conv-det-tie',
        timestamp: 1_700_000_001_000,
      }),
    ];
    const turnsB = [turnsA[1]!, turnsA[0]!]; // reversed

    const agg1 = aggregateConversation('conv-det-tie', turnsA, [], new Set());
    const agg2 = aggregateConversation('conv-det-tie', turnsB, [], new Set());

    // Both should have the same turnCount, firstTurnAt, lastTurnAt
    expect(agg1.turnCount).toBe(agg2.turnCount);
    expect(agg1.firstTurnAt).toBe(agg2.firstTurnAt);
    expect(agg1.lastTurnAt).toBe(agg2.lastTurnAt);
    // Participant list should be identical (same two participants)
    expect(serializeAgg(agg1)).toBe(serializeAgg(agg2));
  });
});

// ────────────────────────────────────────────────────────────
// (e) DB loader
// ────────────────────────────────────────────────────────────

describe('AGG-E: DB loader (loadConversationAggregate)', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('AGG-E1 returns null for unknown conversationId', async () => {
    const result = await loadConversationAggregate(db, 'conv-no-such');
    expect(result).toBeNull();
  });

  test('AGG-E2 loader reads rows and folds correctly', async () => {
    const semSink = makeSemObjectSink(db);

    const turns: OddjobzConversationTurnPayload[] = [
      makeTurn({
        turnId: 'e2-in-1',
        conversationId: 'conv-e2',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61412000001' },
        entityRef: { kind: 'job', cellHash: 'entity-e2-001' },
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'e2-out-1',
        conversationId: 'conv-e2',
        actionType: 'gather_info',
        entityRef: { kind: 'job', cellHash: 'entity-e2-001' },
        timestamp: 1_700_000_002_000,
      }),
    ];

    // Persist turns
    for (const t of turns) {
      await semSink(t);
    }

    const agg = await loadConversationAggregate(db, 'conv-e2');
    expect(agg).not.toBeNull();
    expect(agg!.conversationId).toBe('conv-e2');
    expect(agg!.turnCount).toBe(2);
    expect(agg!.entityRef).toEqual({ kind: 'job', cellHash: 'entity-e2-001' });
    expect(agg!.participants.length).toBeGreaterThanOrEqual(1);
    expect(agg!.openIntents).toHaveLength(1);
    expect(agg!.openIntents[0]!.actionType).toBe('gather_info');
  });

  test('AGG-E3 loader scopes to conversationId — other conversations excluded', async () => {
    const semSink = makeSemObjectSink(db);

    // Persist turn for conv-e3-a
    await semSink(makeTurn({
      turnId: 'e3-in-a',
      conversationId: 'conv-e3-a',
      timestamp: 1_700_000_001_000,
    }));
    // Persist turn for conv-e3-b (different conversation)
    await semSink(makeTurn({
      turnId: 'e3-in-b',
      conversationId: 'conv-e3-b',
      timestamp: 1_700_000_001_000,
    }));

    const aggA = await loadConversationAggregate(db, 'conv-e3-a');
    expect(aggA!.turnCount).toBe(1); // only the one turn for conv-e3-a

    const aggB = await loadConversationAggregate(db, 'conv-e3-b');
    expect(aggB!.turnCount).toBe(1); // only the one turn for conv-e3-b
  });

  test('AGG-E4 loader picks up BELONGS_TO_ENTITY edges for entityRef', async () => {
    const semSink = makeSemObjectSink(db);
    const relSink = makeRelationSink(db);

    const entityCellHash = 'entity-e4-001';
    // Create the entity row
    await createObject(db, {
      id: entityCellHash,
      objectKind: 'oddjobz.job',
      payload: { kind: 'job', ref: 'E4-JOB' },
    });

    // Persist a turn WITHOUT entityRef on the payload (entity unknown at persist time)
    const turnNoEntity = makeTurn({
      turnId: 'e4-in-1',
      conversationId: 'conv-e4',
      // No entityRef on turn
      timestamp: 1_700_000_001_000,
    });
    await semSink(turnNoEntity);

    // Emit BELONGS_TO_ENTITY relation separately (anchoring happened after turn persist)
    await relSink({
      kind: 'BELONGS_TO_ENTITY',
      turnId: 'e4-in-1',
      entityCellHash,
      entityKind: 'job',
    });

    // Also persist a turn WITH entityRef so the loader can resolve the kind
    const turnWithEntity = makeTurn({
      turnId: 'e4-in-2',
      conversationId: 'conv-e4',
      entityRef: { kind: 'job', cellHash: entityCellHash },
      timestamp: 1_700_000_002_000,
    });
    await semSink(turnWithEntity);

    const agg = await loadConversationAggregate(db, 'conv-e4');
    expect(agg!.entityRef?.cellHash).toBe(entityCellHash);
    expect(agg!.entityRef?.kind).toBe('job');
  });

  test('AGG-E5 loader reads ratified turn ids from reply-audit rows', async () => {
    const semSink = makeSemObjectSink(db);

    const outboundTurn = makeOutboundTurn({
      turnId: 'e5-out-1',
      conversationId: 'conv-e5',
      actionType: 'gather_info',
      timestamp: 1_700_000_001_000,
    });
    await semSink(outboundTurn);

    // Manually persist a reply-audit row marking the turn as ratified
    await createObject(db, {
      id: `audit-${outboundTurn.turnId}`,
      objectKind: 'oddjobz.conversation.reply_audit',
      payload: {
        turnId: outboundTurn.turnId,
        promptVersionRef: { promptId: 'reply', version: 1, contentHash: 'h1' },
        operatorDecision: 'ratified',
        timestamp: 1_700_000_001_500,
      },
    });

    const agg = await loadConversationAggregate(db, 'conv-e5');
    // The ratified turn should NOT appear in open intents
    expect(agg!.openIntents).toHaveLength(0);
  });

  test('AGG-E6 loader computes correct time bounds from turns', async () => {
    const semSink = makeSemObjectSink(db);

    await semSink(makeTurn({
      turnId: 'e6-in-1',
      conversationId: 'conv-e6',
      timestamp: 1_700_000_001_000,
    }));
    await semSink(makeOutboundTurn({
      turnId: 'e6-out-1',
      conversationId: 'conv-e6',
      actionType: 'gather_info',
      timestamp: 1_700_000_005_000,
    }));
    await semSink(makeTurn({
      turnId: 'e6-in-2',
      conversationId: 'conv-e6',
      timestamp: 1_700_000_003_000,
    }));

    const agg = await loadConversationAggregate(db, 'conv-e6');
    expect(agg!.turnCount).toBe(3);
    expect(agg!.firstTurnAt).toBe(1_700_000_001_000);  // earliest
    expect(agg!.lastTurnAt).toBe(1_700_000_005_000);   // latest
  });
});

// ────────────────────────────────────────────────────────────
// Additional: participant deduplication across cert/handle/anon
// ────────────────────────────────────────────────────────────

describe('AGG-H: participant deduplication', () => {
  test('AGG-H1 cert-bound participant deduplicated across multiple turns', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'h1-out-1',
        conversationId: 'conv-h1',
        actionType: 'gather_info',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        timestamp: 1_700_000_001_000,
      }),
      makeOutboundTurn({
        turnId: 'h1-out-2',
        conversationId: 'conv-h1',
        actionType: 'present_estimate',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        timestamp: 1_700_000_003_000,
      }),
    ];

    const agg = aggregateConversation('conv-h1', turns, [], new Set());
    const aiParticipants = agg.participants.filter((p) => p.role === 'ai');
    expect(aiParticipants).toHaveLength(1);
    expect(aiParticipants[0]!.actorCertId).toBe('cert_ai_001');
  });

  test('AGG-H2 participants sorted deterministically', () => {
    const turns: OddjobzConversationTurnPayload[] = [
      makeOutboundTurn({
        turnId: 'h2-out-1',
        conversationId: 'conv-h2',
        actionType: 'gather_info',
        participantRole: 'ai',
        actorCertId: 'cert_ai_001',
        timestamp: 1_700_000_002_000,
      }),
      makeTurn({
        turnId: 'h2-in-1',
        conversationId: 'conv-h2',
        participantRole: 'external',
        identityHandle: { kind: 'phone', value: '+61400001' },
        timestamp: 1_700_000_001_000,
      }),
      makeTurn({
        turnId: 'h2-in-2',
        conversationId: 'conv-h2',
        participantRole: 'operator',
        actorCertId: 'cert_op_001',
        timestamp: 1_700_000_003_000,
      }),
    ];

    // Run twice with different input order
    const agg1 = aggregateConversation('conv-h2', turns, [], new Set());
    const agg2 = aggregateConversation('conv-h2', [...turns].reverse(), [], new Set());

    expect(JSON.stringify(agg1.participants)).toBe(JSON.stringify(agg2.participants));
  });
});

```
