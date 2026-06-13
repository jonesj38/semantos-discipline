---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/ai-participant.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.539704+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/ai-participant.test.ts

```ts
/**
 * D-OJ-conv-ai-participant — AI participant outbound state tests.
 *
 * Tests:
 *   AP1  — recordIntakeTurn default (ai) role → outbound turn has outboundState: 'proposed'
 *   AP2  — recordIntakeTurn with outboundParticipantRole:'operator' → outboundState: 'drafted'
 *   AP3  — approveOutboundTurn proposed → stateSink 'approved', then 'sent'; returns { state: 'sent' }
 *   AP4  — approveOutboundTurn proposed + surfaceSend failure → stateSink 'approved', then 'failed'; returns { state: 'failed' }
 *   AP5  — approveOutboundTurn with non-proposed state → throws ApprovalError
 *   AP6  — approveOutboundTurn with 'drafted' state → throws ApprovalError
 *   AP7  — makeOutboundStateSink integration: UPDATE reflected when turn read back (pglite)
 *   AP8  — makeOddjobzSinks now includes outboundStateSink in its return shape
 *   AP9  — AI turn with agent cert id set → actorCertId is not sentinel; outboundState: 'proposed'
 *   AP10 — operator turn → outboundState: 'drafted'; inbound turn → no outboundState
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
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInMemoryLogger } from '@semantos/intent';
import {
  createObject,
  getObject,
  type Database,
} from '@semantos/semantic-objects';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
  AI_CERT_PENDING_SENTINEL,
  type OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';
import {
  makeOddjobzSinks,
  makeOutboundStateSink,
  makeSemObjectSink,
} from '../db.js';
import {
  approveOutboundTurn,
  ApprovalError,
  type ApprovalDeps,
} from '../outbound-approval.js';

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
  const sqlText = readFileSync(MIGRATION_PATH, 'utf-8');
  for (const stmt of splitSql(sqlText)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  return { db, async close() { await pg.close(); } };
}

function splitSql(sqlText: string): string[] {
  const out: string[] = [];
  const lines = sqlText.split('\n');
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
// Test deps factory (mirrors conversation-turn-patch.test.ts)
// ────────────────────────────────────────────────────────────

let _idCounter = 0;

function makeDeps(
  sinks: Partial<{
    semObjectSink: (turn: OddjobzConversationTurnPayload) => Promise<void> | void;
  }> = {},
  opts: { tmpDir?: string } = {},
) {
  const tmpDir = opts.tmpDir ?? mkdtempSync(join(tmpdir(), 'oj-ai-test-'));
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
  objectId: 'conv-ai-test',
  hatId: 'hat-op',
  message: 'Need a fence quote',
  reply: 'Sure — what length?',
  action: { type: 'gather_info' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\nOddjobz intake prompt',
  surface: 'widget' as const,
};

// Helper: capture all turns emitted by recordIntakeTurn.
async function captureTurns(
  args: typeof baseArgs & Record<string, unknown>,
): Promise<OddjobzConversationTurnPayload[]> {
  const captured: OddjobzConversationTurnPayload[] = [];
  const deps = makeDeps({
    semObjectSink: async (turn) => { captured.push(turn); },
  });
  await recordIntakeTurn(args, deps);
  return captured;
}

// ────────────────────────────────────────────────────────────
// AP1 — AI role (default) → outboundState: 'proposed'
// ────────────────────────────────────────────────────────────

describe('AP1 — AI turn (default role) → outboundState proposed', () => {
  test('recordIntakeTurn default outboundParticipantRole → outbound turn has outboundState: proposed', async () => {
    const turns = await captureTurns(baseArgs);
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('proposed');
  });
});

// ────────────────────────────────────────────────────────────
// AP2 — Operator role → outboundState: 'drafted'
// ────────────────────────────────────────────────────────────

describe('AP2 — Operator turn → outboundState drafted', () => {
  test('recordIntakeTurn with outboundParticipantRole:operator → outbound turn has outboundState: drafted', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      outboundParticipantRole: 'operator' as const,
      operatorCertId: 'cert_op_test',
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('drafted');
  });
});

// ────────────────────────────────────────────────────────────
// AP3 — approveOutboundTurn: proposed → approved → sent
// ────────────────────────────────────────────────────────────

describe('AP3 — approveOutboundTurn happy path', () => {
  test('proposed turn → stateSink called with approved then sent, returns { state: sent }', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink = async (turnId: string, newState: string) => {
      sinkCalls.push([turnId, newState]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) => ({
      state: 'delivered' as const,
      surfaceMessageId: 'msg-abc123',
    });

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-ap3',
      conversationId: 'conv-ap3',
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'Sure — what length?',
      outboundState: 'proposed',
      correlationId: 'corr-ap3',
      timestamp: 1_700_000_000_000,
    };

    const deps: ApprovalDeps = { stateSink, surfaceSend };
    const result = await approveOutboundTurn(
      { operatorCertId: 'cert_op_ap3', turn },
      deps,
    );

    expect(sinkCalls).toEqual([
      ['turn-out-ap3', 'approved'],
      ['turn-out-ap3', 'sent'],
    ]);
    expect(result).toEqual({ state: 'sent', surfaceMessageId: 'msg-abc123' });
  });
});

// ────────────────────────────────────────────────────────────
// AP4 — approveOutboundTurn: proposed + surfaceSend failure
// ────────────────────────────────────────────────────────────

describe('AP4 — approveOutboundTurn surface send failure', () => {
  test('proposed turn + surfaceSend returns failed → stateSink approved then failed, returns { state: failed }', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink = async (turnId: string, newState: string) => {
      sinkCalls.push([turnId, newState]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) => ({
      state: 'failed' as const,
      error: 'Twilio 429 rate limited',
    });

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-ap4',
      conversationId: 'conv-ap4',
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'Sure — what length?',
      outboundState: 'proposed',
      correlationId: 'corr-ap4',
      timestamp: 1_700_000_000_000,
    };

    const deps: ApprovalDeps = { stateSink, surfaceSend };
    const result = await approveOutboundTurn(
      { operatorCertId: 'cert_op_ap4', turn },
      deps,
    );

    expect(sinkCalls).toEqual([
      ['turn-out-ap4', 'approved'],
      ['turn-out-ap4', 'failed'],
    ]);
    expect(result).toEqual({ state: 'failed', error: 'Twilio 429 rate limited' });
  });

  test('surfaceSend throws → stateSink approved then failed, returns { state: failed }', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink = async (turnId: string, newState: string) => {
      sinkCalls.push([turnId, newState]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload): Promise<{ state: 'delivered' | 'failed'; surfaceMessageId?: string; error?: string }> => {
      throw new Error('network timeout');
    };

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-ap4b',
      conversationId: 'conv-ap4b',
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'Sure — what length?',
      outboundState: 'proposed',
      correlationId: 'corr-ap4b',
      timestamp: 1_700_000_000_000,
    };

    const deps: ApprovalDeps = { stateSink, surfaceSend };
    const result = await approveOutboundTurn(
      { operatorCertId: 'cert_op_ap4b', turn },
      deps,
    );

    expect(sinkCalls).toEqual([
      ['turn-out-ap4b', 'approved'],
      ['turn-out-ap4b', 'failed'],
    ]);
    expect(result.state).toBe('failed');
    expect((result as { state: 'failed'; error?: string }).error).toContain('network timeout');
  });
});

// ────────────────────────────────────────────────────────────
// AP5 — approveOutboundTurn: non-proposed state → ApprovalError
// ────────────────────────────────────────────────────────────

describe('AP5 — approveOutboundTurn rejects non-proposed states', () => {
  const nonProposedStates = ['approved', 'sent', 'delivered', 'failed', 'rejected', undefined] as const;

  for (const state of nonProposedStates) {
    test(`outboundState '${state}' → throws ApprovalError`, async () => {
      const stateSink = async () => {};
      const surfaceSend = async () => ({ state: 'delivered' as const });

      const turn: OddjobzConversationTurnPayload = {
        turnId: 'turn-out-ap5',
        conversationId: 'conv-ap5',
        participantRole: 'ai',
        surface: 'widget',
        direction: 'outbound',
        bodyText: 'body',
        outboundState: state as any,
        correlationId: 'corr-ap5',
        timestamp: 1_700_000_000_000,
      };

      const deps: ApprovalDeps = { stateSink, surfaceSend };
      await expect(
        approveOutboundTurn({ operatorCertId: 'cert_op', turn }, deps),
      ).rejects.toBeInstanceOf(ApprovalError);
    });
  }
});

// ────────────────────────────────────────────────────────────
// AP6 — approveOutboundTurn: drafted state → ApprovalError
// ────────────────────────────────────────────────────────────

describe('AP6 — approveOutboundTurn rejects drafted state', () => {
  test('outboundState drafted → throws ApprovalError', async () => {
    const stateSink = async () => {};
    const surfaceSend = async () => ({ state: 'delivered' as const });

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-ap6',
      conversationId: 'conv-ap6',
      participantRole: 'operator',
      actorCertId: 'cert_op_ap6',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'operator reply',
      outboundState: 'drafted',
      correlationId: 'corr-ap6',
      timestamp: 1_700_000_000_000,
    };

    const deps: ApprovalDeps = { stateSink, surfaceSend };
    await expect(
      approveOutboundTurn({ operatorCertId: 'cert_op_ap6', turn }, deps),
    ).rejects.toBeInstanceOf(ApprovalError);
  });
});

// ────────────────────────────────────────────────────────────
// AP7 — makeOutboundStateSink integration (pglite)
// ────────────────────────────────────────────────────────────

describe('AP7 — makeOutboundStateSink UPDATE reflected on read-back', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('UPDATE patches outboundState on the sem_objects payload row', async () => {
    // Insert a turn row with outboundState: 'proposed'
    const semSink = makeSemObjectSink(db);
    const initialTurn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-ap7',
      conversationId: 'conv-ap7',
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'Sure — what length?',
      outboundState: 'proposed',
      correlationId: 'corr-ap7',
      timestamp: 1_700_000_000_000,
    };
    await semSink(initialTurn);

    // Verify initial state
    const before = await getObject<OddjobzConversationTurnPayload>(db, 'turn-out-ap7');
    expect(before?.payload.outboundState).toBe('proposed');

    // Apply state transition via the sink
    const stateSink = makeOutboundStateSink(db);
    await stateSink('turn-out-ap7', 'approved');

    // Read back and verify
    const after = await getObject<OddjobzConversationTurnPayload>(db, 'turn-out-ap7');
    expect(after?.payload.outboundState).toBe('approved');

    // Apply sent transition
    await stateSink('turn-out-ap7', 'sent');
    const final = await getObject<OddjobzConversationTurnPayload>(db, 'turn-out-ap7');
    expect(final?.payload.outboundState).toBe('sent');
  });
});

// ────────────────────────────────────────────────────────────
// AP8 — makeOddjobzSinks includes outboundStateSink
// ────────────────────────────────────────────────────────────

describe('AP8 — makeOddjobzSinks returns outboundStateSink', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('makeOddjobzSinks includes outboundStateSink in its return shape', () => {
    const sinks = makeOddjobzSinks(db);
    expect(typeof sinks.outboundStateSink).toBe('function');
    // Verify all existing sinks are still present (non-regression)
    expect(typeof sinks.semObjectSink).toBe('function');
    expect(typeof sinks.relationSink).toBe('function');
    expect(typeof sinks.replyRelationSink).toBe('function');
    expect(typeof sinks.nlRelationSink).toBe('function');
  });
});

// ────────────────────────────────────────────────────────────
// AP9 — AI turn with real agent cert id → not sentinel; proposed
// ────────────────────────────────────────────────────────────

describe('AP9 — AI turn with provisioned agent cert id', () => {
  test('agentCertId set → actorCertId is the real cert (not sentinel); outboundState proposed', async () => {
    const REAL_AGENT_CERT = 'cert_ai_provisioned_001';
    const turns = await captureTurns({
      ...baseArgs,
      agentCertId: REAL_AGENT_CERT,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.actorCertId).toBe(REAL_AGENT_CERT);
    expect(outbound?.actorCertId).not.toBe(AI_CERT_PENDING_SENTINEL);
    expect(outbound?.outboundState).toBe('proposed');
  });
});

// ────────────────────────────────────────────────────────────
// AP10 — operator → drafted; inbound → no outboundState
// ────────────────────────────────────────────────────────────

describe('AP10 — operator outbound drafted; inbound has no outboundState', () => {
  test('operator outbound turn has outboundState drafted', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      outboundParticipantRole: 'operator' as const,
      operatorCertId: 'cert_op_ap10',
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound?.outboundState).toBe('drafted');
  });

  test('inbound turn has NO outboundState field', async () => {
    const turns = await captureTurns(baseArgs);
    const inbound = turns.find((t) => t.direction === 'inbound');
    expect(inbound).toBeDefined();
    // outboundState must be absent on inbound turns
    expect(inbound?.outboundState).toBeUndefined();
    expect('outboundState' in inbound!).toBe(false);
  });
});

```
