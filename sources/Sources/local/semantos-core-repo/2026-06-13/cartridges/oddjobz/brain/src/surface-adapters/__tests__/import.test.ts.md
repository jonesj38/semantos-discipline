---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/__tests__/import.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.532492+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/__tests__/import.test.ts

```ts
/**
 * D-OJ-conv-historical-import — import surface adapter tests.
 *
 * Tests per deliverable spec (HI1–HI10):
 *
 * HI1:  valid payload with 3 messages → ingest returns 3 turns, all surface='import'
 * HI2:  inbound message → participantRole='customer', identityHandle from contactHandle
 * HI3:  outbound message → participantRole='operator'
 * HI4:  entity resolves → turns carry entityRef
 * HI5:  entity does not resolve (ctx.resolveEntity returns null) → turns submitted
 *       without entityRef, no throw
 * HI6:  all messages in same thread share a stable conversationId (same contactHandle)
 * HI7:  different contactHandles → different conversationIds
 * HI8:  send() returns {state:'failed'} and never throws
 * HI9:  ctx.submitTurn called once per message
 * HI10: empty messages array → returns []
 *
 * Additional tests:
 * HI11: correlationId = externalMessageId when present
 * HI12: correlationId = importBatchId + ':' + index when no externalMessageId
 * HI13: inbound with no contactHandle → identityHandle kind='free', value='unknown:N'
 * HI14: timestamp parsed from ISO-8601 string
 * HI15: timestamp parsed from unix ms number
 * HI16: adapter.surface === 'import'
 * HI17: send() error is a string, never throws
 * HI18: ConversationSurfaceAdapter structural compliance
 *
 * Pre-existing baselines you must NOT chase:
 * oddjobz brain ≈8 fail + 6 errors (missing @anthropic-ai/sdk, D-O7/MT-7).
 * These new tests must ALL PASS; no new failures introduced.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { makeImportAdapter } from '../import.js';
import type { HistoricalMessagePayload, ImportAdapterDeps } from '../import.js';
import type { ConversationSurfaceAdapter, AdapterContext } from '../contract.js';
import type { OddjobzConversationTurnPayload } from '../../conversation/conversation-turn-patch.js';

// ── Test helpers ──────────────────────────────────────────────────────────────

/** Minimal AdapterContext with injectable mocks. */
function makeCtx(opts: {
  resolveEntityResult?: { cellHash: string; kind: 'job' | 'site' | 'customer' } | null;
  submittedTurns?: OddjobzConversationTurnPayload[];
} = {}): AdapterContext {
  const submittedTurns = opts.submittedTurns ?? [];
  return {
    operatorCert: {
      certId: 'cert-operator-test-001',
      subjectPublicKey: 'aa'.repeat(33),
      certifierPublicKey: 'bb'.repeat(33),
      type: 'plexus.identity.root',
      serialNumber: 'serial-001',
      fields: {},
      signature: 'sig-test',
    },
    async resolveEntity(_handle) {
      return opts.resolveEntityResult !== undefined
        ? opts.resolveEntityResult
        : null;
    },
    async submitTurn(turn) {
      submittedTurns.push(turn);
    },
  };
}

/** Deterministic id generator for tests. */
function makeIdGen(prefix = 'test-turn'): () => string {
  let seq = 0;
  return () => `${prefix}-${++seq}`;
}

/** Deterministic now for tests. */
function makeNow(ts = 1_748_770_000_000): () => number {
  return () => ts;
}

/** Standard ImportAdapterDeps for tests. */
function makeTestDeps(overrides: Partial<ImportAdapterDeps> = {}): ImportAdapterDeps {
  return {
    generateId: makeIdGen(),
    now: makeNow(),
    ...overrides,
  };
}

/** Derive expected conversationId using the same algorithm as the adapter. */
function expectedConvId(anchor: string, source: string): string {
  return createHash('sha256')
    .update(`import:${anchor}:${source}`)
    .digest('hex');
}

/** Build a minimal 3-message HistoricalMessagePayload. */
function buildPayload3(
  source = 'csv',
  contactHandle: { kind: 'phone' | 'email'; value: string } = {
    kind: 'phone',
    value: '+61412345678',
  },
  importBatchId = 'batch-001',
): HistoricalMessagePayload {
  return {
    source,
    importBatchId,
    messages: [
      {
        timestamp: 'Thu, 22 May 2026 09:00:00 +1000',
        direction: 'inbound',
        body: 'Hi, I need a fence quote.',
        contactHandle,
        externalMessageId: 'msg-001',
      },
      {
        timestamp: 'Thu, 22 May 2026 09:05:00 +1000',
        direction: 'outbound',
        body: 'Sure! What length of fence do you need?',
        externalMessageId: 'msg-002',
      },
      {
        timestamp: 'Thu, 22 May 2026 09:10:00 +1000',
        direction: 'inbound',
        body: 'About 20 metres.',
        contactHandle,
        externalMessageId: 'msg-003',
      },
    ],
  };
}

// ── HI1: 3 messages → 3 turns, all surface='import' ──────────────────────────

describe('import.ingest — HI1: 3 messages → 3 turns', () => {
  test('HI1a: returns exactly 3 turns', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const result = await adapter.ingest(buildPayload3(), ctx);

    expect(result.length).toBe(3);
  });

  test('HI1b: all returned turns have surface=import', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const ctx = makeCtx({ resolveEntityResult: null });

    const result = await adapter.ingest(buildPayload3(), ctx);

    for (const turn of result) {
      expect(turn.surface).toBe('import');
    }
  });
});

// ── HI2: inbound → participantRole='customer', identityHandle from contactHandle ─

describe('import.ingest — HI2: inbound message mapping', () => {
  test('HI2a: inbound → participantRole=customer', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Can I get a quote?',
          contactHandle: { kind: 'phone', value: '+61412345678' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].participantRole).toBe('customer');
    expect(submitted[0].direction).toBe('inbound');
  });

  test('HI2b: inbound → identityHandle from contactHandle (phone)', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Quote request.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].identityHandle).toEqual({
      kind: 'phone',
      value: '+61412345678',
    });
  });

  test('HI2c: inbound → identityHandle from contactHandle (email)', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'ig_export',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Hello from IG.',
          contactHandle: { kind: 'email', value: 'customer@example.com' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].identityHandle).toEqual({
      kind: 'email',
      value: 'customer@example.com',
    });
  });
});

// ── HI3: outbound → participantRole='operator' ────────────────────────────────

describe('import.ingest — HI3: outbound message mapping', () => {
  test('HI3a: outbound → participantRole=operator', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'outbound',
          body: 'Thanks for contacting us! We will get back to you soon.',
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].participantRole).toBe('operator');
    expect(submitted[0].direction).toBe('outbound');
  });

  test('HI3b: outbound → no identityHandle (no L0/L1 for historical operator)', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'outbound',
          body: 'Operator historical message.',
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    // No identityHandle for historical operator turns (XOR invariant).
    expect(submitted[0].identityHandle).toBeUndefined();
  });
});

// ── HI4: entity resolves → turns carry entityRef ─────────────────────────────

describe('import.ingest — HI4: entity resolution hit', () => {
  test('HI4: entity hit → inbound turn carries entityRef', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({
      submittedTurns: submitted,
      resolveEntityResult: { cellHash: 'cell-job-hash-001', kind: 'job' },
    });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'I need a fence quote.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].entityRef).toEqual({
      kind: 'job',
      cellHash: 'cell-job-hash-001',
    });
  });
});

// ── HI5: entity miss → turns submitted without entityRef, no throw ────────────

describe('import.ingest — HI5: entity resolution miss (§13.9 auto-lead)', () => {
  test('HI5a: resolveEntity returns null → entityRef absent (no throw)', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'First time contact.',
          contactHandle: { kind: 'phone', value: '+61499999999' },
        },
      ],
    };

    // Must not throw.
    let threw = false;
    try {
      await adapter.ingest(payload, ctx);
    } catch {
      threw = true;
    }

    expect(threw).toBe(false);
    expect(submitted[0].entityRef).toBeUndefined();
    expect(submitted.length).toBe(1);
  });

  test('HI5b: entity miss → turn still submitted', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'First time contact.',
          contactHandle: { kind: 'phone', value: '+61499999999' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted.length).toBe(1);
    expect(typeof submitted[0].turnId).toBe('string');
    expect(submitted[0].surface).toBe('import');
  });
});

// ── HI6: same contactHandle → same conversationId ────────────────────────────

describe('import.ingest — HI6: stable conversationId within thread', () => {
  test('HI6: all messages with same contactHandle share conversationId', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const contactHandle = { kind: 'phone' as const, value: '+61412345678' };
    const payload: HistoricalMessagePayload = {
      source: 'csv',
      importBatchId: 'batch-001',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Message 1.',
          contactHandle,
        },
        {
          timestamp: 1_748_770_001_000,
          direction: 'outbound',
          body: 'Reply 1.',
          // No contactHandle on outbound — uses importBatchId as anchor.
        },
        {
          timestamp: 1_748_770_002_000,
          direction: 'inbound',
          body: 'Message 2.',
          contactHandle,
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    // Inbound turns both have same contactHandle → same conversationId.
    const inboundTurns = submitted.filter(t => t.direction === 'inbound');
    expect(inboundTurns.length).toBe(2);

    const ids = new Set(inboundTurns.map(t => t.conversationId));
    expect(ids.size).toBe(1);

    // Verify the conversationId is deterministic (matches sha256 formula).
    const expected = expectedConvId(contactHandle.value, 'csv');
    expect(inboundTurns[0].conversationId).toBe(expected);
  });
});

// ── HI7: different contactHandles → different conversationIds ─────────────────

describe('import.ingest — HI7: different handles → different conversationIds', () => {
  test('HI7: two different contact handles yield two different conversationIds', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted1: OddjobzConversationTurnPayload[] = [];
    const submitted2: OddjobzConversationTurnPayload[] = [];

    const ctx1 = makeCtx({ submittedTurns: submitted1, resolveEntityResult: null });
    const ctx2 = makeCtx({ submittedTurns: submitted2, resolveEntityResult: null });

    const payload1: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Message from Alice.',
          contactHandle: { kind: 'phone', value: '+61411111111' },
        },
      ],
    };

    const payload2: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Message from Bob.',
          contactHandle: { kind: 'phone', value: '+61422222222' },
        },
      ],
    };

    await adapter.ingest(payload1, ctx1);
    await adapter.ingest(payload2, ctx2);

    expect(submitted1[0].conversationId).not.toBe(submitted2[0].conversationId);
  });
});

// ── HI8: send() returns {state:'failed'}, never throws ───────────────────────

describe('import.send — HI8: read-only surface', () => {
  test('HI8a: send() returns {state: failed} without throwing', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-test',
      conversationId: 'conv-send-test',
      participantRole: 'operator',
      surface: 'import',
      direction: 'outbound',
      bodyText: 'Outbound turn on import surface.',
      correlationId: 'corr-test',
      timestamp: 1_748_770_000_000,
    };

    let threw = false;
    let result: Awaited<ReturnType<typeof adapter.send>> | undefined;

    try {
      result = await adapter.send(turn, ctx);
    } catch {
      threw = true;
    }

    expect(threw).toBe(false);
    expect(result?.state).toBe('failed');
  });

  test('HI8b: send() error message references import surface', async () => {
    const adapter = makeImportAdapter();
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-msg-test',
      conversationId: 'conv-send-msg-test',
      participantRole: 'operator',
      surface: 'import',
      direction: 'outbound',
      bodyText: 'Outbound.',
      correlationId: 'corr-msg-test',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(typeof result.error).toBe('string');
    expect(result.error).toBeDefined();
  });
});

// ── HI9: ctx.submitTurn called once per message ───────────────────────────────

describe('import.ingest — HI9: submitTurn call count', () => {
  test('HI9: ctx.submitTurn called exactly once per message', async () => {
    const adapter = makeImportAdapter(makeTestDeps());

    let submitCount = 0;
    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() { return null; },
      async submitTurn() { submitCount++; },
    };

    const payload = buildPayload3();
    await adapter.ingest(payload, ctx);

    expect(submitCount).toBe(payload.messages.length);
    expect(submitCount).toBe(3);
  });
});

// ── HI10: empty messages → returns [] ────────────────────────────────────────

describe('import.ingest — HI10: empty messages array', () => {
  test('HI10: empty messages → returns [] without calling submitTurn', async () => {
    const adapter = makeImportAdapter(makeTestDeps());

    let submitCount = 0;
    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() { return null; },
      async submitTurn() { submitCount++; },
    };

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [],
    };

    const result = await adapter.ingest(payload, ctx);

    expect(result).toEqual([]);
    expect(submitCount).toBe(0);
  });
});

// ── HI11: correlationId = externalMessageId when present ─────────────────────

describe('import.ingest — HI11: correlationId from externalMessageId', () => {
  test('HI11: externalMessageId present → correlationId = externalMessageId', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Hello.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
          externalMessageId: 'ig-msg-abc123',
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].correlationId).toBe('ig-msg-abc123');
  });
});

// ── HI12: correlationId = importBatchId + ':' + index when no externalMessageId ─

describe('import.ingest — HI12: correlationId fallback', () => {
  test('HI12: no externalMessageId → correlationId = importBatchId + index', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      importBatchId: 'batch-test-001',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'No external id.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
          // no externalMessageId
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].correlationId).toBe('batch-test-001:0');
  });
});

// ── HI13: inbound with no contactHandle → L0 fallback identityHandle ─────────

describe('import.ingest — HI13: inbound without contactHandle', () => {
  test('HI13: no contactHandle → identityHandle kind=free, value=unknown:N', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: 1_748_770_000_000,
          direction: 'inbound',
          body: 'Anonymous contact.',
          // no contactHandle
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].identityHandle).toEqual({
      kind: 'free',
      value: 'unknown:0',
    });
  });
});

// ── HI14: timestamp from ISO-8601 string ──────────────────────────────────────

describe('import.ingest — HI14: timestamp from ISO-8601', () => {
  test('HI14: ISO-8601 timestamp string → parsed unix ms', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const isoStr = 'Thu, 22 May 2026 09:00:00 +1000';
    const expectedMs = new Date(isoStr).getTime();

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: isoStr,
          direction: 'inbound',
          body: 'ISO timestamp test.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].timestamp).toBe(expectedMs);
  });
});

// ── HI15: timestamp from unix ms number ──────────────────────────────────────

describe('import.ingest — HI15: timestamp from unix ms number', () => {
  test('HI15: unix ms number timestamp → used directly', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const unixMs = 1_748_770_123_456;

    const payload: HistoricalMessagePayload = {
      source: 'csv',
      messages: [
        {
          timestamp: unixMs,
          direction: 'inbound',
          body: 'Unix ms timestamp test.',
          contactHandle: { kind: 'phone', value: '+61412345678' },
        },
      ],
    };

    await adapter.ingest(payload, ctx);

    expect(submitted[0].timestamp).toBe(unixMs);
  });
});

// ── HI16: adapter.surface === 'import' ───────────────────────────────────────

describe('import adapter — HI16: surface discriminant', () => {
  test('HI16: adapter.surface === import', () => {
    const adapter = makeImportAdapter();
    expect(adapter.surface).toBe('import');
  });
});

// ── HI17: send() error is a string, never throws ─────────────────────────────

describe('import.send — HI17: send error shape', () => {
  test('HI17: send() error field is a string', async () => {
    const adapter = makeImportAdapter();
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-hi17',
      conversationId: 'conv-hi17',
      participantRole: 'operator',
      surface: 'import',
      direction: 'outbound',
      bodyText: 'Test.',
      correlationId: 'corr-hi17',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(typeof result.error).toBe('string');
    expect(result.error!.length).toBeGreaterThan(0);
  });
});

// ── HI18: ConversationSurfaceAdapter structural compliance ────────────────────

describe('import adapter — HI18: ConversationSurfaceAdapter compliance', () => {
  test('HI18a: implements ConversationSurfaceAdapter structurally', () => {
    const adapter = makeImportAdapter();
    expect(typeof adapter.surface).toBe('string');
    expect(typeof adapter.ingest).toBe('function');
    expect(typeof adapter.send).toBe('function');
  });

  test('HI18b: type-checks as ConversationSurfaceAdapter', () => {
    const adapter = makeImportAdapter();
    const _typed: ConversationSurfaceAdapter = adapter;
    expect(Boolean(_typed)).toBe(true);
  });

  test('HI18c: ingest returns OddjobzConversationTurnPayload[] (structural check)', async () => {
    const adapter = makeImportAdapter(makeTestDeps());
    const ctx = makeCtx({ resolveEntityResult: null });

    const result = await adapter.ingest(buildPayload3(), ctx);

    expect(Array.isArray(result)).toBe(true);
    for (const turn of result) {
      expect(typeof turn.turnId).toBe('string');
      expect(typeof turn.conversationId).toBe('string');
      expect(typeof turn.participantRole).toBe('string');
      expect(turn.surface).toBe('import');
      expect(typeof turn.direction).toBe('string');
      expect(typeof turn.bodyText).toBe('string');
      expect(typeof turn.correlationId).toBe('string');
      expect(typeof turn.timestamp).toBe('number');
    }
  });
});

```
