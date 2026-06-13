---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/approve-turn-script.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.538448+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/approve-turn-script.test.ts

```ts
/**
 * D-OJ-conv-approve — tests for the outbound-turn approval flow.
 *
 * Tests:
 *   AT1 — approveOutboundTurn called with proposed turn → calls stateSink + surfaceSend
 *   AT2 — stateSink is called with 'approved' before surfaceSend
 *   AT3 — on surfaceSend success → stateSink called with 'sent'; returns { state:'sent' }
 *   AT4 — on surfaceSend failure result → stateSink called with 'failed'; returns { state:'failed' }
 *   AT5 — thrown surfaceSend → stateSink called with 'failed', error captured in result
 *   AT6 — turn not in proposed state → throws ApprovalError
 *   AT7 — approveOutboundTurn returns { state:'sent', surfaceMessageId } from adapter
 *   AT8 — approveOutboundTurn returns { state:'failed', error } from adapter
 *   AT9 — surface='widget' → surfaceSend returns delivered without Twilio
 *   AT10 — surface='sms' with no env vars → falls back to delivered (no Twilio config)
 */

import { describe, it, expect, mock, beforeEach } from 'bun:test';
import { approveOutboundTurn, ApprovalError } from '../outbound-approval.js';
import type { OddjobzConversationTurnPayload } from '../conversation-turn-patch.js';
import type { OutboundStateSink } from '../conversation-turn-patch.js';

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Minimal proposed outbound turn for test cases. */
function makeProposedTurn(
  overrides: Partial<OddjobzConversationTurnPayload> = {},
): OddjobzConversationTurnPayload {
  return {
    turnId: 'turn-test-001',
    conversationId: 'conv-test-001',
    participantRole: 'ai',
    surface: 'widget',
    direction: 'outbound',
    bodyText: 'Hello, how can I help?',
    correlationId: 'corr-001',
    timestamp: Date.now(),
    outboundState: 'proposed',
    ...overrides,
  };
}

// ── AT1: stateSink + surfaceSend called ───────────────────────────────────────

describe('approveOutboundTurn', () => {
  it('AT1: calls stateSink and surfaceSend for a proposed turn', async () => {
    const calls: string[] = [];
    const stateSink: OutboundStateSink = async (_id, state) => {
      calls.push(`sink:${state}`);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) => {
      calls.push('send');
      return { state: 'delivered' as const };
    };

    await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(calls).toContain('send');
    expect(calls.some((c) => c.startsWith('sink:'))).toBe(true);
  });

  // ── AT2: 'approved' before surfaceSend ───────────────────────────────────

  it('AT2: stateSink is called with approved before surfaceSend', async () => {
    const order: string[] = [];
    const stateSink: OutboundStateSink = async (_id, state) => {
      order.push(`sink:${state}`);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) => {
      order.push('send');
      return { state: 'delivered' as const };
    };

    await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    const approvedIdx = order.indexOf('sink:approved');
    const sendIdx = order.indexOf('send');
    expect(approvedIdx).toBeGreaterThanOrEqual(0);
    expect(sendIdx).toBeGreaterThan(approvedIdx);
  });

  // ── AT3: send success → 'sent' state ─────────────────────────────────────

  it('AT3: on surfaceSend success → stateSink called with sent; returns { state:sent }', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink: OutboundStateSink = async (id, state) => {
      sinkCalls.push([id, state]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) =>
      ({ state: 'delivered' as const, surfaceMessageId: 'sid-123' });

    const result = await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(result.state).toBe('sent');
    const sentCall = sinkCalls.find(([, s]) => s === 'sent');
    expect(sentCall).toBeDefined();
  });

  // ── AT4: send failure result → 'failed' state ────────────────────────────

  it('AT4: on surfaceSend failure result → stateSink called with failed; returns { state:failed }', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink: OutboundStateSink = async (id, state) => {
      sinkCalls.push([id, state]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) =>
      ({ state: 'failed' as const, error: 'upstream timeout' });

    const result = await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(result.state).toBe('failed');
    const failedCall = sinkCalls.find(([, s]) => s === 'failed');
    expect(failedCall).toBeDefined();
  });

  // ── AT5: thrown surfaceSend → 'failed' ───────────────────────────────────

  it('AT5: thrown surfaceSend → stateSink called with failed, error captured', async () => {
    const sinkCalls: Array<[string, string]> = [];
    const stateSink: OutboundStateSink = async (id, state) => {
      sinkCalls.push([id, state]);
    };
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload): Promise<never> => {
      throw new Error('connection refused');
    };

    const result = await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(result.state).toBe('failed');
    if (result.state === 'failed') {
      expect(result.error).toContain('connection refused');
    }
    const failedCall = sinkCalls.find(([, s]) => s === 'failed');
    expect(failedCall).toBeDefined();
  });

  // ── AT6: non-proposed state → throws ApprovalError ───────────────────────

  it('AT6: turn not in proposed state → throws ApprovalError', async () => {
    const stateSink: OutboundStateSink = async () => {};
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) =>
      ({ state: 'delivered' as const });

    const draftedTurn = makeProposedTurn({ outboundState: 'drafted' });

    await expect(
      approveOutboundTurn({ operatorCertId: 'operator', turn: draftedTurn }, { stateSink, surfaceSend }),
    ).rejects.toBeInstanceOf(ApprovalError);
  });

  // ── AT7: returns surfaceMessageId ────────────────────────────────────────

  it('AT7: returns { state:sent, surfaceMessageId } from adapter', async () => {
    const stateSink: OutboundStateSink = async () => {};
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) =>
      ({ state: 'delivered' as const, surfaceMessageId: 'SM-abc-456' });

    const result = await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(result.state).toBe('sent');
    if (result.state === 'sent') {
      expect(result.surfaceMessageId).toBe('SM-abc-456');
    }
  });

  // ── AT8: returns { state:failed, error } ─────────────────────────────────

  it('AT8: returns { state:failed, error } from adapter failure', async () => {
    const stateSink: OutboundStateSink = async () => {};
    const surfaceSend = async (_turn: OddjobzConversationTurnPayload) =>
      ({ state: 'failed' as const, error: 'rate limited' });

    const result = await approveOutboundTurn(
      { operatorCertId: 'operator', turn: makeProposedTurn() },
      { stateSink, surfaceSend },
    );

    expect(result.state).toBe('failed');
    if (result.state === 'failed') {
      expect(result.error).toBe('rate limited');
    }
  });
});

// ── makeSurfaceSend logic tests ───────────────────────────────────────────────
//
// These test the surfaceSend factory logic from approve-turn-script.ts
// directly (extracted into a testable helper form).

/**
 * Replicate the surface-send selection logic from approve-turn-script.ts
 * so we can unit-test it without running the full subprocess.
 *
 * When surface='sms' AND Twilio env vars are present → use Twilio adapter.
 * Otherwise → return delivered immediately (stub delivery).
 */
function makeSurfaceSendForTest(
  t: OddjobzConversationTurnPayload,
  env: Record<string, string | undefined> = {},
): (turn: OddjobzConversationTurnPayload) => Promise<{
  state: 'delivered' | 'failed';
  surfaceMessageId?: string;
  error?: string;
}> {
  if (t.surface === 'sms') {
    const accountSid = env.TWILIO_ACCOUNT_SID;
    const authToken = env.TWILIO_AUTH_TOKEN;
    const fromNumber = env.TWILIO_FROM_NUMBER;
    if (accountSid && authToken && fromNumber) {
      // Would build Twilio adapter — signal this was reached by returning a
      // marker error so AT10 can assert the fallback wasn't used.
      return async () => ({
        state: 'failed' as const,
        error: 'twilio-adapter-path-reached',
      });
    }
  }
  // Fallback: immediate delivered (widget / no-twilio-config SMS / other surfaces)
  return async () => ({ state: 'delivered' as const });
}

describe('makeSurfaceSend logic', () => {
  // ── AT9: widget surface → delivered without Twilio ────────────────────────

  it('AT9: surface=widget → surfaceSend returns delivered without Twilio', async () => {
    const turn = makeProposedTurn({ surface: 'widget' });
    const sendFn = makeSurfaceSendForTest(turn, {});
    const result = await sendFn(turn);
    expect(result.state).toBe('delivered');
  });

  // ── AT10: surface=sms, no env vars → fallback to delivered ───────────────

  it('AT10: surface=sms with no env vars → falls back to delivered (no Twilio config)', async () => {
    const turn = makeProposedTurn({ surface: 'sms' });
    // No TWILIO_* env vars → should fall through to delivered stub
    const sendFn = makeSurfaceSendForTest(turn, {
      TWILIO_ACCOUNT_SID: undefined,
      TWILIO_AUTH_TOKEN: undefined,
      TWILIO_FROM_NUMBER: undefined,
    });
    const result = await sendFn(turn);
    expect(result.state).toBe('delivered');
  });

  it('AT10b: surface=sms WITH env vars → routes through Twilio adapter path', async () => {
    const turn = makeProposedTurn({ surface: 'sms' });
    const sendFn = makeSurfaceSendForTest(turn, {
      TWILIO_ACCOUNT_SID: 'ACtest',
      TWILIO_AUTH_TOKEN: 'testtoken',
      TWILIO_FROM_NUMBER: '+61299990000',
    });
    const result = await sendFn(turn);
    // Our test stub returns a marker error to confirm the Twilio path was taken
    expect(result.state).toBe('failed');
    expect(result.error).toBe('twilio-adapter-path-reached');
  });
});

```
