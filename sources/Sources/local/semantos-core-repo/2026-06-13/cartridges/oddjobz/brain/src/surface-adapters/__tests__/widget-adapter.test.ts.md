---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/__tests__/widget-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.532020+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/__tests__/widget-adapter.test.ts

```ts
/**
 * D-OJ-conv-widget-intake — widget surface adapter tests.
 *
 * Assertions (per deliverable spec):
 *
 * (a) `widget.ingest(wsPayload, ctx)` → correct canonical turn(s):
 *     surface='widget', participantRole='external', identityHandle phone
 *     bound, bodyText mapped, direction='inbound'/'outbound'.
 *
 * (b) Entity resolution hit → `entityRef` set on both turns.
 *     Entity resolution miss → `entityRef` absent (§6.3 lead-on-contact —
 *     the adapter does NOT fabricate an entityRef; SD2 handles it out-of-band).
 *
 * (c) `widget.send(outboundTurn, ctx)` → `{ state: 'delivered' }` with
 *     `surfaceMessageId` when WS sender succeeds; `{ state: 'failed', error }`
 *     when it throws; `{ state: 'failed' }` when no sender configured.
 *
 * (d) The adapter implements `ConversationSurfaceAdapter` contract:
 *     - `adapter.surface === 'widget'`
 *     - `ingest` returns `OddjobzConversationTurnPayload[]`
 *     - `send` returns `{ state: 'delivered' | 'failed' }`
 *     - Both methods call the injected `ctx.submitTurn`
 *
 * (e) Identity handling: phone → L1 identityHandle; no phone/email → L0
 *     cookie or no handle.
 *
 * (f) inReplyToTurnId → inbound turn's `quotedTurnId` (quote affordance).
 *
 * Pre-existing baselines (must NOT regress):
 * oddjobz brain ≈8 fail + 6 errors (missing @anthropic-ai/sdk, D-O7/MT-7).
 * These new tests must ALL PASS; no new failures introduced.
 */

import {
  describe,
  expect,
  test,
  beforeEach,
  afterEach,
} from 'bun:test';
import { makeWidgetAdapter } from '../widget.js';
import type { WidgetWsPayload, WidgetWsSender } from '../widget.js';
import type { ConversationSurfaceAdapter, AdapterContext } from '../contract.js';
import type { OddjobzConversationTurnPayload } from '../../conversation/conversation-turn-patch.js';

// ── Test helpers ──────────────────────────────────────────────────────────────

let _idSeq = 0;

/** Deterministic id generator for tests. */
function makeIdGen(): () => string {
  let seq = 0;
  return () => `test-id-${++seq}`;
}

/** Deterministic time for tests. */
function makeNow(ts = 1_700_000_000_000): () => number {
  return () => ts;
}

/** Build a minimal AdapterContext with injectable mocks. */
function makeCtx(opts: {
  resolveEntityResult?: { cellHash: string; kind: 'job' | 'site' | 'customer' } | null;
  submittedTurns?: OddjobzConversationTurnPayload[];
} = {}): AdapterContext {
  const submittedTurns = opts.submittedTurns ?? [];
  return {
    operatorCert: {
      certId: 'cert-id-test-operator',
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

/** Minimal valid WS payload. */
function makePayload(overrides: Partial<WidgetWsPayload> = {}): WidgetWsPayload {
  return {
    message: 'Need a fence quote for my backyard',
    sessionId: 'sess-widget-test-001',
    ...overrides,
  };
}

/** Extract the inbound and outbound turns from a submitted-turns list. */
function splitTurns(turns: OddjobzConversationTurnPayload[]): {
  inbound: OddjobzConversationTurnPayload;
  outbound: OddjobzConversationTurnPayload;
} {
  const inbound = turns.find(t => t.direction === 'inbound');
  const outbound = turns.find(t => t.direction === 'outbound');
  if (!inbound || !outbound) {
    throw new Error(`Expected inbound + outbound turns; got directions: ${turns.map(t => t.direction).join(', ')}`);
  }
  return { inbound, outbound };
}

// ── (a) Basic ingest — canonical turn shape ───────────────────────────────────

describe('widget.ingest — canonical turn shape', () => {
  test('WI-A1: returns two turns (inbound + outbound)', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const payload = makePayload({ phone: '+61412345678', reply: 'Sure!' });
    const result = await adapter.ingest(payload, ctx);

    expect(result.length).toBe(2);
    expect(submitted.length).toBe(2);
  });

  test('WI-A2: inbound turn has surface=widget, direction=inbound, participantRole=external', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678', reply: 'Sure!' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.surface).toBe('widget');
    expect(inbound.direction).toBe('inbound');
    expect(inbound.participantRole).toBe('external');
  });

  test('WI-A3: inbound bodyText equals payload.message', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ message: 'Fix my fence pls', phone: '+61412345678' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.bodyText).toBe('Fix my fence pls');
  });

  test('WI-A4: phone identity bound as identityHandle on inbound turn (L1)', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678', reply: 'Sure!' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.identityHandle).toEqual({ kind: 'phone', value: '+61412345678' });
    // L1 phone → no actorCertId
    expect(inbound.actorCertId).toBeUndefined();
  });

  test('WI-A5: outbound turn has direction=outbound, participantRole=ai', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ reply: 'Happy to help!', phone: '+61412345678' }), ctx);

    const { outbound } = splitTurns(submitted);
    expect(outbound.direction).toBe('outbound');
    expect(outbound.participantRole).toBe('ai');
    expect(outbound.surface).toBe('widget');
  });

  test('WI-A6: outbound bodyText equals payload.reply', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ reply: 'Happy to help with your fence!', phone: '+61412345678' }), ctx);

    const { outbound } = splitTurns(submitted);
    expect(outbound.bodyText).toBe('Happy to help with your fence!');
  });

  test('WI-A7: conversationId is the sessionId', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ sessionId: 'sess-abc-999', phone: '+61412345678' }), ctx);

    const { inbound, outbound } = splitTurns(submitted);
    expect(inbound.conversationId).toBe('sess-abc-999');
    expect(outbound.conversationId).toBe('sess-abc-999');
  });

  test('WI-A8: both turns share the same correlationId and timestamp', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow(999_000) });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { inbound, outbound } = splitTurns(submitted);
    expect(inbound.correlationId).toBe(outbound.correlationId);
    expect(inbound.timestamp).toBe(999_000);
    expect(outbound.timestamp).toBe(999_000);
  });
});

// ── (b) Entity resolution ─────────────────────────────────────────────────────

describe('widget.ingest — entity resolution (§6.3)', () => {
  test('WI-B1: entity hit → entityRef set on both turns', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({
      submittedTurns: submitted,
      resolveEntityResult: { cellHash: 'cell-job-hash-001', kind: 'job' },
    });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { inbound, outbound } = splitTurns(submitted);
    expect(inbound.entityRef).toEqual({ kind: 'job', cellHash: 'cell-job-hash-001' });
    expect(outbound.entityRef).toEqual({ kind: 'job', cellHash: 'cell-job-hash-001' });
  });

  test('WI-B2: entity miss → entityRef absent (§6.3 lead-on-contact; no fabrication)', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { inbound, outbound } = splitTurns(submitted);
    expect(inbound.entityRef).toBeUndefined();
    expect(outbound.entityRef).toBeUndefined();
  });

  test('WI-B3: entity resolution uses phone over email', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const resolvedHandles: Array<{ kind: string; value: string }> = [];

    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity(handle) {
        resolvedHandles.push(handle);
        return null;
      },
      async submitTurn() {},
    };

    await adapter.ingest(makePayload({ phone: '+61412345678', email: 'test@example.com' }), ctx);

    // Should have queried with phone (preferred)
    expect(resolvedHandles.length).toBeGreaterThan(0);
    expect(resolvedHandles[0].kind).toBe('phone');
    expect(resolvedHandles[0].value).toBe('+61412345678');
  });

  test('WI-B4: no phone/email → uses cookie for resolution', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const resolvedHandles: Array<{ kind: string; value: string }> = [];

    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity(handle) {
        resolvedHandles.push(handle);
        return null;
      },
      async submitTurn() {},
    };

    await adapter.ingest(makePayload({ cookie: 'browser-sess-xyz' }), ctx);

    expect(resolvedHandles.length).toBeGreaterThan(0);
    expect(resolvedHandles[0].kind).toBe('cookie');
  });

  test('WI-B5: no phone/email/cookie → resolveEntity not called', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    let resolveCalled = false;

    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() {
        resolveCalled = true;
        return null;
      },
      async submitTurn() {},
    };

    // No phone, email or cookie in the payload
    await adapter.ingest(makePayload(), ctx);

    expect(resolveCalled).toBe(false);
  });
});

// ── (c) widget.send ───────────────────────────────────────────────────────────

describe('widget.send', () => {
  const outboundTurn: OddjobzConversationTurnPayload = {
    turnId: 'turn-out-send-test',
    conversationId: 'sess-send-test-001',
    participantRole: 'ai',
    surface: 'widget',
    direction: 'outbound',
    bodyText: 'Sure, I can help with that fence quote!',
    correlationId: 'corr-send-001',
    timestamp: 1_700_000_000_000,
  };

  test('WI-C1: send with WS sender → delivered + surfaceMessageId', async () => {
    const wsSender: WidgetWsSender = async (_sessionId, _turn) => 'ws-msg-id-001';
    const adapter = makeWidgetAdapter({ wsSender });
    const ctx = makeCtx();

    const result = await adapter.send(outboundTurn, ctx);
    expect(result.state).toBe('delivered');
    expect(result.surfaceMessageId).toBe('ws-msg-id-001');
    expect(result.error).toBeUndefined();
  });

  test('WI-C2: send with WS sender that returns undefined → delivered (no surfaceMessageId)', async () => {
    const wsSender: WidgetWsSender = async () => undefined;
    const adapter = makeWidgetAdapter({ wsSender });
    const ctx = makeCtx();

    const result = await adapter.send(outboundTurn, ctx);
    expect(result.state).toBe('delivered');
    expect(result.surfaceMessageId).toBeUndefined();
  });

  test('WI-C3: send when WS sender throws → failed + error message', async () => {
    const wsSender: WidgetWsSender = async () => {
      throw new Error('WS connection closed');
    };
    const adapter = makeWidgetAdapter({ wsSender });
    const ctx = makeCtx();

    const result = await adapter.send(outboundTurn, ctx);
    expect(result.state).toBe('failed');
    expect(result.error).toContain('WS connection closed');
    // Must not throw
  });

  test('WI-C4: send with no WS sender configured → failed (graceful)', async () => {
    const adapter = makeWidgetAdapter({}); // no wsSender
    const ctx = makeCtx();

    const result = await adapter.send(outboundTurn, ctx);
    expect(result.state).toBe('failed');
    expect(result.error).toBeDefined();
  });

  test('WI-C5: WS sender receives the sessionId (from conversationId) + the turn', async () => {
    const sentSessionIds: string[] = [];
    const sentTurns: OddjobzConversationTurnPayload[] = [];

    const wsSender: WidgetWsSender = async (sessionId, turn) => {
      sentSessionIds.push(sessionId);
      sentTurns.push(turn);
      return 'ws-msg-id-002';
    };

    const adapter = makeWidgetAdapter({ wsSender });
    const ctx = makeCtx();

    await adapter.send(outboundTurn, ctx);

    expect(sentSessionIds).toEqual(['sess-send-test-001']); // conversationId IS the sessionId
    expect(sentTurns[0]).toBe(outboundTurn);
  });
});

// ── (d) Contract compliance ───────────────────────────────────────────────────

describe('widget adapter — ConversationSurfaceAdapter contract', () => {
  test('WI-D1: adapter.surface === widget', () => {
    const adapter = makeWidgetAdapter();
    expect(adapter.surface).toBe('widget');
  });

  test('WI-D2: adapter implements the ConversationSurfaceAdapter interface (structural)', () => {
    const adapter = makeWidgetAdapter();
    // Structural: has ingest + send + surface
    expect(typeof adapter.ingest).toBe('function');
    expect(typeof adapter.send).toBe('function');
    expect(typeof adapter.surface).toBe('string');
  });

  test('WI-D3: ingest returns OddjobzConversationTurnPayload[] (structural check)', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const ctx = makeCtx({ resolveEntityResult: null });

    const result = await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    expect(Array.isArray(result)).toBe(true);
    result.forEach(turn => {
      expect(typeof turn.turnId).toBe('string');
      expect(typeof turn.conversationId).toBe('string');
      expect(typeof turn.participantRole).toBe('string');
      expect(typeof turn.surface).toBe('string');
      expect(typeof turn.direction).toBe('string');
      expect(typeof turn.bodyText).toBe('string');
      expect(typeof turn.correlationId).toBe('string');
      expect(typeof turn.timestamp).toBe('number');
    });
  });

  test('WI-D4: ingest calls ctx.submitTurn for each produced turn', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submittedTurns: OddjobzConversationTurnPayload[] = [];
    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() { return null; },
      async submitTurn(turn) { submittedTurns.push(turn); },
    };

    const result = await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    // Both produced turns must have been submitted via ctx.submitTurn
    expect(submittedTurns.length).toBe(result.length);
    for (const turn of result) {
      expect(submittedTurns.find(t => t.turnId === turn.turnId)).toBeDefined();
    }
  });

  test('WI-D5: send return type is { state, surfaceMessageId?, error? }', async () => {
    const adapter = makeWidgetAdapter({ wsSender: async () => 'id-x' });
    const ctx = makeCtx();
    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-contract-test',
      conversationId: 'sess-contract',
      participantRole: 'ai',
      surface: 'widget',
      direction: 'outbound',
      bodyText: 'A reply',
      correlationId: 'corr-x',
      timestamp: 1_700_000_000_000,
    };

    const result = await adapter.send(turn, ctx);
    expect(['delivered', 'failed'].includes(result.state)).toBe(true);
  });

  test('WI-D6: adapter type-checks as ConversationSurfaceAdapter at compile time', () => {
    // TypeScript type test — assigning to the interface type proves structural compatibility.
    // (At runtime this is just a boolean that is always true.)
    const adapter = makeWidgetAdapter();
    const _typed: ConversationSurfaceAdapter = adapter;
    expect(Boolean(_typed)).toBe(true);
  });
});

// ── (e) Identity handling ─────────────────────────────────────────────────────

describe('widget.ingest — identity handling', () => {
  test('WI-E1: email-only → identityHandle kind=email on inbound turn', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ email: 'customer@example.com' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.identityHandle).toEqual({ kind: 'email', value: 'customer@example.com' });
  });

  test('WI-E2: cookie-only → identityHandle kind=cookie on inbound turn (L0)', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ cookie: 'anon-session-cookie-abc' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.identityHandle).toEqual({ kind: 'cookie', value: 'anon-session-cookie-abc' });
  });

  test('WI-E3: no identity fields → inbound has no identityHandle and no actorCertId', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload(), ctx); // no phone/email/cookie

    const { inbound } = splitTurns(submitted);
    expect(inbound.identityHandle).toBeUndefined();
    expect(inbound.actorCertId).toBeUndefined();
  });

  test('WI-E4: agentCertId wired to outbound actorCertId', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({
      agentCertId: 'cert-agent-001',
      phone: '+61412345678',
    }), ctx);

    const { outbound } = splitTurns(submitted);
    expect(outbound.actorCertId).toBe('cert-agent-001');
  });

  test('WI-E5: outbound without agentCertId → carries AI_CERT_PENDING_SENTINEL', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { outbound } = splitTurns(submitted);
    // ai role without agentCertId → bindParticipantIdentity sets AI_CERT_PENDING_SENTINEL
    expect(outbound.actorCertId).toContain('cert_ai_pending');
  });
});

// ── (f) Quote affordance ──────────────────────────────────────────────────────

describe('widget.ingest — quote affordance (inReplyToTurnId)', () => {
  test('WI-F1: inReplyToTurnId → inbound turn carries quotedTurnId', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({
      phone: '+61412345678',
      inReplyToTurnId: 'turn-in-prior-message',
    }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.quotedTurnId).toBe('turn-in-prior-message');
  });

  test('WI-F2: no inReplyToTurnId → inbound turn has no quotedTurnId', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { inbound } = splitTurns(submitted);
    expect(inbound.quotedTurnId).toBeUndefined();
  });

  test('WI-F3: outbound always quotes the inbound turn from same interaction', async () => {
    const adapter = makeWidgetAdapter({ generateId: makeIdGen(), now: makeNow() });
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(makePayload({ phone: '+61412345678' }), ctx);

    const { inbound, outbound } = splitTurns(submitted);
    // The outbound turn's quotedTurnId is set to the inbound turn's id
    expect(outbound.quotedTurnId).toBe(inbound.turnId);
  });
});

// ── Error cases ───────────────────────────────────────────────────────────────

describe('widget.ingest — error cases', () => {
  test('WI-G1: null payload → throws', async () => {
    const adapter = makeWidgetAdapter();
    const ctx = makeCtx();
    await expect(adapter.ingest(null, ctx)).rejects.toThrow();
  });

  test('WI-G2: empty message → throws', async () => {
    const adapter = makeWidgetAdapter();
    const ctx = makeCtx();
    await expect(adapter.ingest({ sessionId: 'sess-1', message: '' }, ctx)).rejects.toThrow();
  });

  test('WI-G3: missing message key → throws', async () => {
    const adapter = makeWidgetAdapter();
    const ctx = makeCtx();
    await expect(adapter.ingest({ sessionId: 'sess-1' }, ctx)).rejects.toThrow();
  });
});

```
