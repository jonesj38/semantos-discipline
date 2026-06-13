---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/reply-audit.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.541805+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/reply-audit.test.ts

```ts
/**
 * D-OJ-conv-reply-audit-log — reply-audit sink tests.
 *
 * Uses the PGlite `makeTestDb` harness (mirrors db-sinks.test.ts) to
 * exercise the reply-audit sink factory and its integration via
 * `recordIntakeTurn`.
 *
 * Assertions (per deliverable spec):
 *
 *  (a) An outbound reply landing `recordIntakeTurn` produces a
 *      `sem_objects` row of kind `oddjobz.conversation.reply_audit`.
 *
 *  (b) The row carries the `promptVersionRef` pin (promptId + version +
 *      contentHash) matching `promptVersionRef('reply')` — the exact
 *      prompt schema that generated the reply.
 *
 *  (c) Optional fields (confidence, operatorDecision, cellChain)
 *      absent when not supplied — row still persists cleanly.
 *
 *  (d) The audit row's `turnId` references the outbound turn's
 *      sem_objects.id (the reference, not an expansion of the turn).
 *
 *  (e) Audit-sink failure is isolated — the reply still resolves and
 *      the turn rows still land (best-effort isolation).
 *
 *  Plus:
 *  (f) Idempotency: a second call with the same outbound turnId does not
 *      throw (unique-constraint violation is swallowed silently).
 *  (g) Optional fields present when supplied (confidence + decision +
 *      cellChain all round-trip correctly).
 *  (h) The `objectKind` discriminator is exactly
 *      `oddjobz.conversation.reply_audit`.
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
  getObject,
  type Database,
} from '@semantos/semantic-objects';
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
  makeSemObjectSink,
  ODDJOBZ_TURN_OBJECT_KIND,
} from '../db.js';
import {
  makeReplyAuditSink,
  ODDJOBZ_REPLY_AUDIT_OBJECT_KIND,
  type OddjobzReplyAuditPayload,
} from '../reply-audit.js';
import {
  promptVersionRef,
  PROMPT_IDS,
} from '../prompt-store.js';

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
// Test deps factory (mirrors db-sinks.test.ts)
// ────────────────────────────────────────────────────────────

let _idCounter = 0;

function makeDeps(
  sinks: Partial<{
    semObjectSink: (turn: OddjobzConversationTurnPayload) => Promise<void> | void;
    replyAuditSink: ReturnType<typeof makeReplyAuditSink>;
  }> = {},
  opts: { tmpDir?: string } = {},
) {
  const tmpDir = opts.tmpDir ?? mkdtempSync(join(tmpdir(), 'oj-audit-test-'));
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
  objectId: 'audit-test-session',
  hatId: 'hat-op',
  message: 'Need a colorbond fence quote',
  stateSummary: { jobType: 'fencing' },
  reply: 'Sure — what length of fence do you need?',
  action: { type: 'gather_info' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\nOddjobz intake prompt',
  surface: 'widget' as const,
};

// ────────────────────────────────────────────────────────────
// (a) + (b) + (d) + (h) — core audit row
// ────────────────────────────────────────────────────────────

describe('makeReplyAuditSink — core audit row', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('RA1 direct sink: persists an audit row of the correct objectKind', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    const payload: OddjobzReplyAuditPayload = {
      turnId: 'turn-out-ra1',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_000,
    };
    await sink(payload);

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra1');
    expect(row).not.toBeNull();
    // (h) objectKind discriminator
    expect(row?.objectKind).toBe(ODDJOBZ_REPLY_AUDIT_OBJECT_KIND);
    expect(row?.objectKind).toBe('oddjobz.conversation.reply_audit');
  });

  test('RA2 row id is `audit-<turnId>` (greppable, no collision with turn)', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    await sink({
      turnId: 'turn-out-ra2',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_001,
    });

    // The audit row's id is prefixed — no collision with the turn row
    const auditRow = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra2');
    expect(auditRow?.id).toBe('audit-turn-out-ra2');

    // Bare turnId is not present (the turn row hasn't been created here —
    // confirm there's no accidental id aliasing)
    const bareRow = await getObject<unknown>(db, 'turn-out-ra2');
    expect(bareRow).toBeNull();
  });

  test('RA3 payload carries promptVersionRef matching promptVersionRef("reply")', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    await sink({
      turnId: 'turn-out-ra3',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_002,
    });

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra3');
    expect(row?.payload.promptVersionRef.promptId).toBe(PROMPT_IDS.reply);
    expect(row?.payload.promptVersionRef.version).toBe(ref.version);
    expect(row?.payload.promptVersionRef.contentHash).toBe(ref.contentHash);
    // Sanity: content hash is a 64-char hex
    expect(ref.contentHash).toMatch(/^[0-9a-f]{64}$/);
  });

  test('RA4 (d) turnId in payload references the outbound turn id', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    await sink({
      turnId: 'turn-out-ra4',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_003,
    });

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra4');
    // (d) the reference, not an expansion
    expect(row?.payload.turnId).toBe('turn-out-ra4');
  });
});

// ────────────────────────────────────────────────────────────
// (c) optional fields absent
// ────────────────────────────────────────────────────────────

describe('makeReplyAuditSink — optional fields absent', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('RA5 (c) row persists cleanly when confidence/decision/cellChain absent', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    // Only required fields — no optional fields
    await sink({
      turnId: 'turn-out-ra5',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_004,
    });

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra5');
    expect(row).not.toBeNull();
    // Optional fields should be absent (undefined / missing)
    expect(row?.payload.confidence).toBeUndefined();
    expect(row?.payload.operatorDecision).toBeUndefined();
    expect(row?.payload.cellChain).toBeUndefined();
  });
});

// ────────────────────────────────────────────────────────────
// (g) optional fields present when supplied
// ────────────────────────────────────────────────────────────

describe('makeReplyAuditSink — optional fields round-trip', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('RA6 (g) confidence, operatorDecision, cellChain round-trip correctly', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    await sink({
      turnId: 'turn-out-ra6',
      promptVersionRef: ref,
      confidence: 0.87,
      operatorDecision: 'ratified',
      cellChain: 'abc123def456',
      timestamp: 1_700_000_000_005,
    });

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra6');
    expect(row?.payload.confidence).toBe(0.87);
    expect(row?.payload.operatorDecision).toBe('ratified');
    expect(row?.payload.cellChain).toBe('abc123def456');
  });

  test('RA7 operatorDecision "rejected" persists correctly', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    await sink({
      turnId: 'turn-out-ra7',
      promptVersionRef: ref,
      operatorDecision: 'rejected',
      timestamp: 1_700_000_000_006,
    });

    const row = await getObject<OddjobzReplyAuditPayload>(db, 'audit-turn-out-ra7');
    expect(row?.payload.operatorDecision).toBe('rejected');
  });
});

// ────────────────────────────────────────────────────────────
// (f) idempotency
// ────────────────────────────────────────────────────────────

describe('makeReplyAuditSink — idempotency', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('RA8 (f) a replayed audit (same turnId) does not throw', async () => {
    const sink = makeReplyAuditSink(db);
    const ref = promptVersionRef(PROMPT_IDS.reply);
    const payload: OddjobzReplyAuditPayload = {
      turnId: 'turn-out-ra8',
      promptVersionRef: ref,
      timestamp: 1_700_000_000_007,
    };
    await sink(payload); // first insert
    // Second call: unique-constraint must be swallowed silently
    await expect(sink(payload)).resolves.toBeUndefined();
  });
});

// ────────────────────────────────────────────────────────────
// Integration: recordIntakeTurn + replyAuditSink
// ────────────────────────────────────────────────────────────

describe('recordIntakeTurn + replyAuditSink — integration', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('INT-RA1 (a) outbound reply lands a reply_audit sem_objects row', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);

    // Track the outbound turn id
    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: auditSink,
    });
    await recordIntakeTurn(baseArgs, deps);

    // Find the outbound turn
    const outbound = seenTurns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();

    // (a) audit row exists
    const auditRow = await getObject<OddjobzReplyAuditPayload>(
      db,
      `audit-${outbound!.turnId}`,
    );
    expect(auditRow).not.toBeNull();
    expect(auditRow?.objectKind).toBe(ODDJOBZ_REPLY_AUDIT_OBJECT_KIND);
  });

  test('INT-RA2 (b) audit row carries promptVersionRef matching promptVersionRef("reply")', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: auditSink,
    });
    await recordIntakeTurn(baseArgs, deps);

    const outbound = seenTurns.find((t) => t.direction === 'outbound')!;
    const auditRow = await getObject<OddjobzReplyAuditPayload>(
      db,
      `audit-${outbound.turnId}`,
    );
    const expectedRef = promptVersionRef(PROMPT_IDS.reply);
    expect(auditRow?.payload.promptVersionRef.promptId).toBe(PROMPT_IDS.reply);
    expect(auditRow?.payload.promptVersionRef.promptId).toBe(
      'oddjobz.prompt.reply',
    );
    expect(auditRow?.payload.promptVersionRef.version).toBe(expectedRef.version);
    expect(auditRow?.payload.promptVersionRef.contentHash).toBe(
      expectedRef.contentHash,
    );
  });

  test('INT-RA3 (d) audit turnId references the outbound turn sem_objects.id', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: auditSink,
    });
    await recordIntakeTurn(baseArgs, deps);

    const outbound = seenTurns.find((t) => t.direction === 'outbound')!;
    const auditRow = await getObject<OddjobzReplyAuditPayload>(
      db,
      `audit-${outbound.turnId}`,
    );
    // (d) references the turn, not the turn body
    expect(auditRow?.payload.turnId).toBe(outbound.turnId);
    // The outbound turn row itself exists under the bare turnId
    const turnRow = await getObject<OddjobzConversationTurnPayload>(
      db,
      outbound.turnId,
    );
    expect(turnRow?.objectKind).toBe(ODDJOBZ_TURN_OBJECT_KIND);
  });

  test('INT-RA4 (c) optional fields absent when not supplied', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: auditSink,
    });
    // baseArgs has no replyConfidence / replyOperatorDecision / replyCellChain
    await recordIntakeTurn(baseArgs, deps);

    const outbound = seenTurns.find((t) => t.direction === 'outbound')!;
    const auditRow = await getObject<OddjobzReplyAuditPayload>(
      db,
      `audit-${outbound.turnId}`,
    );
    expect(auditRow?.payload.confidence).toBeUndefined();
    expect(auditRow?.payload.operatorDecision).toBeUndefined();
    expect(auditRow?.payload.cellChain).toBeUndefined();
  });

  test('INT-RA5 optional fields present when supplied (confidence + decision + chain)', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: auditSink,
    });
    await recordIntakeTurn(
      {
        ...baseArgs,
        replyConfidence: 0.92,
        replyOperatorDecision: 'ratified',
        replyCellChain: 'cell-hash-xyz',
      },
      deps,
    );

    const outbound = seenTurns.find((t) => t.direction === 'outbound')!;
    const auditRow = await getObject<OddjobzReplyAuditPayload>(
      db,
      `audit-${outbound.turnId}`,
    );
    expect(auditRow?.payload.confidence).toBe(0.92);
    expect(auditRow?.payload.operatorDecision).toBe('ratified');
    expect(auditRow?.payload.cellChain).toBe('cell-hash-xyz');
  });

  test('INT-RA6 (e) audit-sink failure is isolated — reply still resolves and turn rows still land', async () => {
    const semSink = makeSemObjectSink(db);

    // Audit sink that always throws
    const failingAuditSink = async (_payload: OddjobzReplyAuditPayload): Promise<void> => {
      throw new Error('intentional audit-sink failure');
    };

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSink,
      replyAuditSink: failingAuditSink,
    });

    // recordIntakeTurn must resolve (not throw) — audit failure is isolated
    const result = await recordIntakeTurn(baseArgs, deps);
    expect(result.patchId).toBeDefined();

    // Both turn rows still landed despite audit failure
    for (const turn of seenTurns) {
      const row = await getObject<OddjobzConversationTurnPayload>(db, turn.turnId);
      expect(row).not.toBeNull();
      expect(row?.objectKind).toBe(ODDJOBZ_TURN_OBJECT_KIND);
    }
  });

  test('INT-RA7 audit fires ONLY for the outbound turn (not the inbound)', async () => {
    const semSink = makeSemObjectSink(db);
    const auditSink = makeReplyAuditSink(db);
    const seenAuditIds: string[] = [];

    // Wrap the audit sink to track calls
    const trackingAuditSink = async (payload: OddjobzReplyAuditPayload): Promise<void> => {
      seenAuditIds.push(payload.turnId);
      await auditSink(payload);
    };

    const seenTurns: OddjobzConversationTurnPayload[] = [];
    const trackingSemSink = async (turn: OddjobzConversationTurnPayload) => {
      seenTurns.push(turn);
      await semSink(turn);
    };

    const deps = makeDeps({
      semObjectSink: trackingSemSink,
      replyAuditSink: trackingAuditSink,
    });
    await recordIntakeTurn(baseArgs, deps);

    const outbound = seenTurns.find((t) => t.direction === 'outbound')!;
    const inbound = seenTurns.find((t) => t.direction === 'inbound')!;

    // Exactly one audit emit, for the outbound turn
    expect(seenAuditIds).toHaveLength(1);
    expect(seenAuditIds[0]).toBe(outbound.turnId);
    // Not the inbound turn
    expect(seenAuditIds[0]).not.toBe(inbound.turnId);
  });
});

```
