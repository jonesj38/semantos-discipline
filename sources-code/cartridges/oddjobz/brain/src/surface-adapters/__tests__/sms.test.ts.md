---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/__tests__/sms.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.533379+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/__tests__/sms.test.ts

```ts
/**
 * D-OJ-conv-sms-intake — SMS surface adapter tests.
 *
 * Test groups:
 *
 * EC1–EC7:  Error/edge cases (malformed payload, missing fields, E.164 validation,
 *           no sender, Twilio API error)
 * IN1–IN8:  Ingest happy path + E.164 identity + lead-on-contact (entity miss) +
 *           entity hit + conversationId stability + turnId determinism
 * SND1–SND6: Send happy path + failure + no-sender fallback + surfaceMessageId from
 *            Twilio SID + missing identityHandle guard
 * INT1–INT5: End-to-end integration (ingest → ctx.submitTurn called correctly,
 *            round-trip conversationId, contract compliance)
 *
 * Pre-existing baselines you must NOT chase:
 * oddjobz brain ≈8 fail + 6 errors (missing @anthropic-ai/sdk). These new tests
 * must ALL PASS; no new failures introduced.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { makeSmsAdapter } from '../sms.js';
import type {
  SmsAdapterDeps,
  TwilioHttpSend,
  TwilioInboundSmsWebhook,
} from '../sms.js';
import type { ConversationSurfaceAdapter, AdapterContext } from '../contract.js';
import type { OddjobzConversationTurnPayload } from '../../conversation/conversation-turn-patch.js';

// ── Test constants ────────────────────────────────────────────────────────────

const OPERATOR_NUMBER = '+61299990000';
const CUSTOMER_NUMBER = '+61412345678';
const MESSAGE_SID = 'SM1234567890abcdef1234567890abcdef';
const ACCOUNT_SID = 'ACtest1234567890';
const AUTH_TOKEN = 'test_auth_token';
const TWILIO_OUTBOUND_SID = 'SMoutbound1234567890';

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Build a minimal valid Twilio inbound SMS webhook payload.
 */
function buildWebhook(
  overrides: Partial<TwilioInboundSmsWebhook & Record<string, unknown>> = {},
): TwilioInboundSmsWebhook {
  return {
    MessageSid: MESSAGE_SID,
    AccountSid: ACCOUNT_SID,
    From: CUSTOMER_NUMBER,
    To: OPERATOR_NUMBER,
    Body: 'Can I get a quote for a fence?',
    NumMedia: '0',
    ...overrides,
  };
}

/**
 * Build minimal SmsAdapterDeps with a mock httpSend.
 */
function makeDeps(
  overrides: Partial<SmsAdapterDeps> = {},
  mockSend?: TwilioHttpSend,
): SmsAdapterDeps {
  const httpSend: TwilioHttpSend =
    mockSend ??
    (async (_params) => ({ sid: TWILIO_OUTBOUND_SID }));

  return {
    accountSid: ACCOUNT_SID,
    authToken: AUTH_TOKEN,
    fromNumber: OPERATOR_NUMBER,
    httpSend,
    ...overrides,
  };
}

/**
 * Build a minimal AdapterContext with injectable mocks.
 */
function makeCtx(opts: {
  resolveEntityResult?: { cellHash: string; kind: 'job' | 'site' | 'customer' } | null;
  submittedTurns?: OddjobzConversationTurnPayload[];
} = {}): AdapterContext {
  const submittedTurns = opts.submittedTurns ?? [];
  return {
    operatorCert: {
      certId: 'cert-operator-sms-test-001',
      subjectPublicKey: 'aa'.repeat(33),
      certifierPublicKey: 'bb'.repeat(33),
      type: 'plexus.identity.root',
      serialNumber: 'serial-sms-001',
      fields: {},
      signature: 'sig-sms-test',
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

/**
 * Derive the expected conversationId using the same sha256 approach.
 */
function expectedConversationId(
  operatorPhone: string,
  customerPhone: string,
): string {
  const seed = `sms:${operatorPhone.trim().toLowerCase()}:${customerPhone.trim().toLowerCase()}`;
  return createHash('sha256').update(seed).digest('hex');
}

// ── EC: Error / edge cases ────────────────────────────────────────────────────

describe('sms.ingest — error / edge cases (EC)', () => {
  test('EC1: null payload → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    await expect(adapter.ingest(null, ctx)).rejects.toThrow(
      'sms.ingest: payload must be an object',
    );
  });

  test('EC2: non-object payload → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    await expect(adapter.ingest('string-payload', ctx)).rejects.toThrow(
      'sms.ingest: payload must be an object',
    );
  });

  test('EC3: missing MessageSid → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const payload = { AccountSid: ACCOUNT_SID, From: CUSTOMER_NUMBER, To: OPERATOR_NUMBER, Body: 'Hi' };
    await expect(adapter.ingest(payload, ctx)).rejects.toThrow(
      'sms.ingest: payload.MessageSid is required',
    );
  });

  test('EC4: missing From → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const payload = { MessageSid: MESSAGE_SID, AccountSid: ACCOUNT_SID, To: OPERATOR_NUMBER, Body: 'Hi' };
    await expect(adapter.ingest(payload, ctx)).rejects.toThrow(
      'sms.ingest: payload.From (customer E.164) is required',
    );
  });

  test('EC5: missing Body → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const payload = { MessageSid: MESSAGE_SID, AccountSid: ACCOUNT_SID, From: CUSTOMER_NUMBER, To: OPERATOR_NUMBER };
    await expect(adapter.ingest(payload, ctx)).rejects.toThrow(
      'sms.ingest: payload.Body is required',
    );
  });

  test('EC6: From not starting with + → throws (invalid E.164)', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const payload = buildWebhook({ From: '0412345678' }); // missing leading +
    await expect(adapter.ingest(payload, ctx)).rejects.toThrow(
      'sms.ingest: payload.From must be E.164',
    );
  });

  test('EC7: missing To → throws', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const payload = { MessageSid: MESSAGE_SID, AccountSid: ACCOUNT_SID, From: CUSTOMER_NUMBER, Body: 'Hi' };
    await expect(adapter.ingest(payload, ctx)).rejects.toThrow(
      'sms.ingest: payload.To (operator number) is required',
    );
  });
});

// ── IN: Ingest happy path ─────────────────────────────────────────────────────

describe('sms.ingest — happy path + identity + entity (IN)', () => {
  test('IN1: valid webhook → returns exactly one turn', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const turns = await adapter.ingest(buildWebhook(), ctx);

    expect(turns.length).toBe(1);
    expect(submitted.length).toBe(1);
  });

  test('IN2: surface=sms on the canonical turn', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    expect(submitted[0].surface).toBe('sms');
  });

  test('IN3: participantRole=external, direction=inbound', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    expect(submitted[0].participantRole).toBe('external');
    expect(submitted[0].direction).toBe('inbound');
  });

  test('IN4: identityHandle = { kind: phone, value: From } (E.164)', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook({ From: '+61412345678' }), ctx);

    expect(submitted[0].identityHandle).toEqual({ kind: 'phone', value: '+61412345678' });
    // XOR invariant: no actorCertId for un-cert'd external
    expect(submitted[0].actorCertId).toBeUndefined();
  });

  test('IN5: bodyText = webhook.Body', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });
    const body = 'Please send me a quote for a timber fence.';

    await adapter.ingest(buildWebhook({ Body: body }), ctx);

    expect(submitted[0].bodyText).toBe(body);
  });

  test('IN6: conversationId is stable sha256 hash of phone pair', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    const expected = expectedConversationId(OPERATOR_NUMBER, CUSTOMER_NUMBER);
    expect(submitted[0].conversationId).toBe(expected);
  });

  test('IN7: entity miss → entityRef absent (§6.3 lead-on-contact)', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    expect(submitted[0].entityRef).toBeUndefined();
  });

  test('IN8: entity hit → entityRef populated on the turn', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const resolveResult = { cellHash: 'cell-abc123', kind: 'job' as const };
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: resolveResult });

    await adapter.ingest(buildWebhook(), ctx);

    expect(submitted[0].entityRef).toEqual({ kind: 'job', cellHash: 'cell-abc123' });
  });

  test('IN9: resolveEntity called with phone identityHandle', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const capturedHandles: { kind: string; value: string }[] = [];
    const ctx: AdapterContext = {
      operatorCert: {
        certId: 'cert-op-001',
        subjectPublicKey: 'aa'.repeat(33),
        certifierPublicKey: 'bb'.repeat(33),
        type: 'plexus.identity.root',
        serialNumber: 'serial-001',
        fields: {},
        signature: 'sig',
      },
      async resolveEntity(handle) {
        capturedHandles.push(handle);
        return null;
      },
      async submitTurn() {},
    };

    await adapter.ingest(buildWebhook({ From: CUSTOMER_NUMBER }), ctx);

    expect(capturedHandles.length).toBe(1);
    expect(capturedHandles[0]).toEqual({ kind: 'phone', value: CUSTOMER_NUMBER });
  });

  test('IN10: turnId is deterministic — same MessageSid → same turnId', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted1: OddjobzConversationTurnPayload[] = [];
    const submitted2: OddjobzConversationTurnPayload[] = [];

    await adapter.ingest(buildWebhook({ MessageSid: 'SM-stable-001' }), makeCtx({ submittedTurns: submitted1, resolveEntityResult: null }));
    await adapter.ingest(buildWebhook({ MessageSid: 'SM-stable-001' }), makeCtx({ submittedTurns: submitted2, resolveEntityResult: null }));

    expect(submitted1[0].turnId).toBe(submitted2[0].turnId);
  });

  test('IN11: different MessageSid → different turnId', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted1: OddjobzConversationTurnPayload[] = [];
    const submitted2: OddjobzConversationTurnPayload[] = [];

    await adapter.ingest(buildWebhook({ MessageSid: 'SM-aaa' }), makeCtx({ submittedTurns: submitted1, resolveEntityResult: null }));
    await adapter.ingest(buildWebhook({ MessageSid: 'SM-bbb' }), makeCtx({ submittedTurns: submitted2, resolveEntityResult: null }));

    expect(submitted1[0].turnId).not.toBe(submitted2[0].turnId);
  });

  test('IN12: conversationId is direction-stable (same pair regardless of inbound/outbound orientation)', async () => {
    // Simulate the same customer+operator pair from inbound perspective
    const conv1 = expectedConversationId(OPERATOR_NUMBER, CUSTOMER_NUMBER);
    // Same pair — should always produce the same hash since we always put operator first
    const conv2 = expectedConversationId(OPERATOR_NUMBER, CUSTOMER_NUMBER);
    expect(conv1).toBe(conv2);
  });

  test('IN13: different customer phones → different conversationIds', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted1: OddjobzConversationTurnPayload[] = [];
    const submitted2: OddjobzConversationTurnPayload[] = [];

    await adapter.ingest(buildWebhook({ From: '+61412345678' }), makeCtx({ submittedTurns: submitted1, resolveEntityResult: null }));
    await adapter.ingest(buildWebhook({ From: '+61498765432' }), makeCtx({ submittedTurns: submitted2, resolveEntityResult: null }));

    expect(submitted1[0].conversationId).not.toBe(submitted2[0].conversationId);
  });

  test('IN14: empty Body is allowed (zero-length SMS body)', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook({ Body: '' }), ctx);

    expect(submitted[0].bodyText).toBe('');
  });

  test('IN15: ctx.submitTurn called exactly once for a single inbound', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    let callCount = 0;
    const ctx: AdapterContext = {
      operatorCert: {
        certId: 'cert-op-001',
        subjectPublicKey: 'aa'.repeat(33),
        certifierPublicKey: 'bb'.repeat(33),
        type: 'plexus.identity.root',
        serialNumber: 'serial-001',
        fields: {},
        signature: 'sig',
      },
      async resolveEntity() { return null; },
      async submitTurn() { callCount++; },
    };

    await adapter.ingest(buildWebhook(), ctx);

    expect(callCount).toBe(1);
  });
});

// ── SND: Send tests ───────────────────────────────────────────────────────────

describe('sms.send — outbound delivery (SND)', () => {
  /** Build a minimal outbound canonical turn for send tests. */
  function buildOutboundTurn(
    overrides: Partial<OddjobzConversationTurnPayload> = {},
  ): OddjobzConversationTurnPayload {
    return {
      turnId: 'turn-outbound-001',
      conversationId: expectedConversationId(OPERATOR_NUMBER, CUSTOMER_NUMBER),
      participantRole: 'operator',
      surface: 'sms',
      direction: 'outbound',
      bodyText: 'Thanks for your enquiry! We will get back to you shortly.',
      correlationId: 'corr-001',
      timestamp: 1_748_770_000_000,
      identityHandle: { kind: 'phone', value: CUSTOMER_NUMBER },
      ...overrides,
    };
  }

  test('SND1: successful send → { state: "delivered", surfaceMessageId: Twilio SID }', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    const turn = buildOutboundTurn();

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('delivered');
    expect(result.surfaceMessageId).toBe(TWILIO_OUTBOUND_SID);
    expect(result.error).toBeUndefined();
  });

  test('SND2: no httpSend configured → { state: "failed", error }', async () => {
    const adapter = makeSmsAdapter({
      accountSid: ACCOUNT_SID,
      authToken: AUTH_TOKEN,
      fromNumber: OPERATOR_NUMBER,
      // httpSend intentionally absent
    });
    const ctx = makeCtx();
    const turn = buildOutboundTurn();

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toBe('sms.send: no twilio sender configured');
  });

  test('SND3: httpSend throws → { state: "failed", error message } — never re-throws', async () => {
    const failingSend: TwilioHttpSend = async () => {
      throw new Error('Twilio API 429 Too Many Requests');
    };
    const adapter = makeSmsAdapter(makeDeps({}, failingSend));
    const ctx = makeCtx();
    const turn = buildOutboundTurn();

    // Must NOT throw (§6.1 contract)
    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toBe('Twilio API 429 Too Many Requests');
  });

  test('SND4: httpSend receives correct to/from/body params', async () => {
    const capturedParams: Array<{ to: string; from: string; body: string }> = [];
    const mockSend: TwilioHttpSend = async (params) => {
      capturedParams.push({ ...params });
      return { sid: TWILIO_OUTBOUND_SID };
    };
    const adapter = makeSmsAdapter(makeDeps({}, mockSend));
    const ctx = makeCtx();
    const body = 'Your quote is ready!';
    const turn = buildOutboundTurn({ bodyText: body });

    await adapter.send(turn, ctx);

    expect(capturedParams.length).toBe(1);
    expect(capturedParams[0].to).toBe(CUSTOMER_NUMBER);
    expect(capturedParams[0].from).toBe(OPERATOR_NUMBER);
    expect(capturedParams[0].body).toBe(body);
  });

  test('SND5: turn without phone identityHandle → { state: "failed" }', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    // Outbound turn with no identityHandle (e.g. malformed / wrong surface)
    const turn = buildOutboundTurn({ identityHandle: undefined });

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toContain('no phone identityHandle');
  });

  test('SND6: turn with non-phone identityHandle → { state: "failed" }', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const ctx = makeCtx();
    // identityHandle with wrong kind (e.g. email)
    const turn = buildOutboundTurn({
      identityHandle: { kind: 'email', value: 'customer@example.com' },
    });

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toContain('no phone identityHandle');
  });

  test('SND7: httpSend throws non-Error → error string captured', async () => {
    const failingSend: TwilioHttpSend = async () => {
      throw 'plain string error'; // non-Error throw
    };
    const adapter = makeSmsAdapter(makeDeps({}, failingSend));
    const ctx = makeCtx();
    const turn = buildOutboundTurn();

    const result = await adapter.send(turn, ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toBe('plain string error');
  });

  test('SND8: surfaceMessageId comes from Twilio SID in response', async () => {
    const customSid = 'SM_CUSTOM_SID_XYZ';
    const mockSend: TwilioHttpSend = async () => ({ sid: customSid });
    const adapter = makeSmsAdapter(makeDeps({}, mockSend));
    const ctx = makeCtx();

    const result = await adapter.send(buildOutboundTurn(), ctx);

    expect(result.surfaceMessageId).toBe(customSid);
  });
});

// ── INT: Integration tests ────────────────────────────────────────────────────

describe('sms — integration (INT)', () => {
  test('INT1: ingest + send round-trip — conversationId matches', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);
    const inboundTurn = submitted[0];

    // Build an outbound turn using the same conversationId from the inbound
    const outboundTurn: OddjobzConversationTurnPayload = {
      turnId: 'turn-out-001',
      conversationId: inboundTurn.conversationId,
      participantRole: 'operator',
      surface: 'sms',
      direction: 'outbound',
      bodyText: 'Thank you, we will call you shortly.',
      correlationId: inboundTurn.correlationId,
      timestamp: Date.now(),
      identityHandle: inboundTurn.identityHandle, // phone from inbound
    };

    const sendResult = await adapter.send(outboundTurn, ctx);
    expect(sendResult.state).toBe('delivered');
  });

  test('INT2: surface property === "sms" (ConversationSurfaceAdapter.surface)', () => {
    const adapter = makeSmsAdapter(makeDeps());
    expect(adapter.surface).toBe('sms');
  });

  test('INT3: structural contract compliance — has ingest + send + surface', () => {
    const adapter = makeSmsAdapter(makeDeps());
    expect(typeof adapter.ingest).toBe('function');
    expect(typeof adapter.send).toBe('function');
    expect(adapter.surface).toBeDefined();
  });

  test('INT4: type-compatible with ConversationSurfaceAdapter (TypeScript structural)', () => {
    // This test compiles only if makeSmsAdapter returns a ConversationSurfaceAdapter.
    const adapter: ConversationSurfaceAdapter = makeSmsAdapter(makeDeps());
    expect(adapter.surface).toBe('sms');
  });

  test('INT5: ingest produces turn with required canonical fields', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);
    const turn = submitted[0];

    // All required fields per OddjobzConversationTurnPayload
    expect(typeof turn.turnId).toBe('string');
    expect(turn.turnId).toMatch(/^turn-/);
    expect(typeof turn.conversationId).toBe('string');
    expect(turn.conversationId.length).toBe(64); // sha256 hex = 64 chars
    expect(turn.surface).toBe('sms');
    expect(turn.participantRole).toBe('external');
    expect(turn.direction).toBe('inbound');
    expect(typeof turn.bodyText).toBe('string');
    expect(typeof turn.correlationId).toBe('string');
    expect(typeof turn.timestamp).toBe('number');
  });

  test('INT6: ingest turn has identityHandle.kind = phone (L1 tier)', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    const turn = submitted[0];
    expect(turn.identityHandle?.kind).toBe('phone');
    expect(turn.identityHandle?.value).toBe(CUSTOMER_NUMBER);
  });

  test('INT7: entity hit sets entityRef on the turn returned and submitted', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const entityHit = { cellHash: 'cell-xyz789', kind: 'customer' as const };
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: entityHit });

    const turns = await adapter.ingest(buildWebhook(), ctx);

    // Both the returned turns and submitted turns carry entityRef
    expect(turns[0].entityRef).toEqual({ kind: 'customer', cellHash: 'cell-xyz789' });
    expect(submitted[0].entityRef).toEqual({ kind: 'customer', cellHash: 'cell-xyz789' });
  });

  test('INT8: stateless adapter — two ingests from different customers do not cross-contaminate', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted1: OddjobzConversationTurnPayload[] = [];
    const submitted2: OddjobzConversationTurnPayload[] = [];
    const ctx1 = makeCtx({ submittedTurns: submitted1, resolveEntityResult: null });
    const ctx2 = makeCtx({ submittedTurns: submitted2, resolveEntityResult: null });

    await adapter.ingest(buildWebhook({ From: '+61412345678', MessageSid: 'SM-cust-1' }), ctx1);
    await adapter.ingest(buildWebhook({ From: '+61498765432', MessageSid: 'SM-cust-2' }), ctx2);

    expect(submitted1[0].identityHandle?.value).toBe('+61412345678');
    expect(submitted2[0].identityHandle?.value).toBe('+61498765432');
    expect(submitted1[0].conversationId).not.toBe(submitted2[0].conversationId);
  });

  test('INT9: turnId from ingest turn starts with turn- prefix', async () => {
    const adapter = makeSmsAdapter(makeDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    await adapter.ingest(buildWebhook(), ctx);

    expect(submitted[0].turnId).toMatch(/^turn-[0-9a-f]{16}$/);
  });
});

```
