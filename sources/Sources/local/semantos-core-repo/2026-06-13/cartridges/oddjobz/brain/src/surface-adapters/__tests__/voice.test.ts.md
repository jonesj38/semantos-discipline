---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/__tests__/voice.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.532969+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/__tests__/voice.test.ts

```ts
/**
 * D-OJ-conv-voice-intake — voice surface adapter tests.
 *
 * Test IDs per deliverable spec:
 *
 * VI1: valid payload → ingest produces one turn with correct
 *      surface / direction / participantRole / bodyText
 * VI2: turn has entityRef populated from payload.entityId + entityKind
 * VI3: turn.timestamp is close to Date.now() (within 5s)
 * VI4: invalid payload (missing transcript) → ingest returns [] without throwing
 * VI5: send() always returns { state: 'failed' } with an error string, does not throw
 * VI6: ctx.submitTurn is called exactly once per valid ingest
 * VI7: recordingId from payload becomes turn.correlationId (capture-time dedup)
 *
 * Additional coverage:
 * VA1: adapter.surface === 'voice'
 * VA2: structural contract compliance (ingest + send + surface)
 * VA3: type-compatible with ConversationSurfaceAdapter
 * VA4: actorCertId from ctx.operatorCert.certId on valid ingest
 * VA5: no identityHandle on operator turn (XOR invariant)
 * VA6: conversationId is stable hash — same entityKind + entityId → same conversationId
 * VA7: different entityId → different conversationId
 * VA8: correlationId falls back to turnId when recordingId absent
 * VA9: payload with all optional fields → ingest succeeds
 * VA10: invalid payload (missing entityId) → returns []
 * VA11: invalid payload (wrong entityKind) → returns []
 * VA12: invalid payload (non-object) → returns []
 * VA13: send() does not throw on random turn input
 * VA14: entityRef.cellHash === payload.entityId (capture-time-bound)
 * VA15: entityRef.kind === payload.entityKind
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { makeVoiceAdapter } from '../voice.js';
import type { VoiceNotePayload } from '../voice.js';
import type { ConversationSurfaceAdapter, AdapterContext } from '../contract.js';
import type { OddjobzConversationTurnPayload } from '../../conversation/conversation-turn-patch.js';

// ── Test constants ────────────────────────────────────────────────────────────

const OPERATOR_CERT_ID = 'cert-operator-voice-test-001';
const ENTITY_ID = 'job-cell-hash-abc123';
const ENTITY_KIND = 'job' as const;
const RECORDING_ID = 'rec-voice-001';
const TRANSCRIPT = 'Fence is rotted at the back corner. Need to replace three posts.';

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Build a minimal valid VoiceNotePayload. */
function buildPayload(
  overrides: Partial<VoiceNotePayload & Record<string, unknown>> = {},
): VoiceNotePayload {
  return {
    transcript: TRANSCRIPT,
    entityId: ENTITY_ID,
    entityKind: ENTITY_KIND,
    capturedAt: new Date().toISOString(),
    recordingId: RECORDING_ID,
    ...overrides,
  };
}

/** Build a minimal AdapterContext with injectable mocks. */
function makeCtx(opts: {
  submittedTurns?: OddjobzConversationTurnPayload[];
  certId?: string;
} = {}): AdapterContext {
  const submittedTurns = opts.submittedTurns ?? [];
  return {
    operatorCert: {
      certId: opts.certId ?? OPERATOR_CERT_ID,
      subjectPublicKey: 'aa'.repeat(33),
      certifierPublicKey: 'bb'.repeat(33),
      type: 'plexus.identity.root',
      serialNumber: 'serial-voice-001',
      fields: {},
      signature: 'sig-voice-test',
    },
    async resolveEntity(_handle) {
      return null;
    },
    async submitTurn(turn) {
      submittedTurns.push(turn);
    },
  };
}

/** Build a minimal outbound canonical turn for send() tests. */
function buildOutboundTurn(
  overrides: Partial<OddjobzConversationTurnPayload> = {},
): OddjobzConversationTurnPayload {
  return {
    turnId: 'turn-voice-out-001',
    conversationId: 'conv-voice-001',
    participantRole: 'operator',
    actorCertId: OPERATOR_CERT_ID,
    surface: 'voice',
    direction: 'inbound',
    bodyText: 'Fence notes.',
    correlationId: 'corr-voice-001',
    timestamp: Date.now(),
    ...overrides,
  };
}

/** Derive the expected conversationId using the same sha256 approach. */
function expectedConversationId(
  entityKind: string,
  entityId: string,
): string {
  return createHash('sha256')
    .update(`voice:${entityKind}:${entityId}`)
    .digest('hex');
}

// ── VI: Core spec tests ───────────────────────────────────────────────────────

describe('voice.ingest — core spec (VI)', () => {
  test('VI1: valid payload → one turn with correct surface / direction / participantRole / bodyText', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    const turns = await adapter.ingest(buildPayload(), ctx);

    expect(turns.length).toBe(1);
    expect(submitted.length).toBe(1);

    const turn = turns[0];
    expect(turn.surface).toBe('voice');
    expect(turn.direction).toBe('inbound');
    expect(turn.participantRole).toBe('operator');
    expect(turn.bodyText).toBe(TRANSCRIPT);
  });

  test('VI2: turn has entityRef populated from payload.entityId + entityKind', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    await adapter.ingest(buildPayload({ entityId: ENTITY_ID, entityKind: 'job' }), ctx);

    const turn = submitted[0];
    expect(turn.entityRef).toBeDefined();
    expect(turn.entityRef!.kind).toBe('job');
    expect(turn.entityRef!.cellHash).toBe(ENTITY_ID);
  });

  test('VI3: turn.timestamp is close to Date.now() (within 5 seconds)', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });
    const before = Date.now();

    await adapter.ingest(buildPayload(), ctx);

    const after = Date.now();
    const turn = submitted[0];
    expect(turn.timestamp).toBeGreaterThanOrEqual(before);
    expect(turn.timestamp).toBeLessThanOrEqual(after + 5000);
  });

  test('VI4: invalid payload (missing transcript) → ingest returns [] without throwing', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    // Omit transcript entirely
    const payload = {
      entityId: ENTITY_ID,
      entityKind: 'job',
      capturedAt: new Date().toISOString(),
    };

    let threw = false;
    let result: OddjobzConversationTurnPayload[] = [];
    try {
      result = await adapter.ingest(payload, ctx);
    } catch {
      threw = true;
    }

    expect(threw).toBe(false);
    expect(result).toEqual([]);
  });

  test('VI5: send() always returns { state: "failed" } with an error string, does not throw', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    let threw = false;
    let result: Awaited<ReturnType<ConversationSurfaceAdapter['send']>> = {
      state: 'delivered',
    };
    try {
      result = await adapter.send(buildOutboundTurn(), ctx);
    } catch {
      threw = true;
    }

    expect(threw).toBe(false);
    expect(result.state).toBe('failed');
    expect(typeof result.error).toBe('string');
    expect(result.error!.length).toBeGreaterThan(0);
  });

  test('VI6: ctx.submitTurn is called exactly once per valid ingest', async () => {
    const adapter = makeVoiceAdapter();
    let callCount = 0;
    const ctx: AdapterContext = {
      operatorCert: {
        certId: OPERATOR_CERT_ID,
        subjectPublicKey: 'aa'.repeat(33),
        certifierPublicKey: 'bb'.repeat(33),
        type: 'plexus.identity.root',
        serialNumber: 'serial-voice-001',
        fields: {},
        signature: 'sig-voice-test',
      },
      async resolveEntity() { return null; },
      async submitTurn() { callCount++; },
    };

    await adapter.ingest(buildPayload(), ctx);

    expect(callCount).toBe(1);
  });

  test('VI7: recordingId from payload becomes turn.correlationId', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });
    const recordingId = 'rec-unique-dedup-id-999';

    await adapter.ingest(buildPayload({ recordingId }), ctx);

    expect(submitted[0].correlationId).toBe(recordingId);
  });
});

// ── VA: Additional adapter coverage ──────────────────────────────────────────

describe('voice adapter — surface property (VA)', () => {
  test('VA1: adapter.surface === "voice"', () => {
    const adapter = makeVoiceAdapter();
    expect(adapter.surface).toBe('voice');
  });

  test('VA2: structural contract compliance — has ingest + send + surface', () => {
    const adapter = makeVoiceAdapter();
    expect(typeof adapter.ingest).toBe('function');
    expect(typeof adapter.send).toBe('function');
    expect(adapter.surface).toBeDefined();
  });

  test('VA3: type-compatible with ConversationSurfaceAdapter (TypeScript structural)', () => {
    const adapter: ConversationSurfaceAdapter = makeVoiceAdapter();
    expect(adapter.surface).toBe('voice');
  });
});

describe('voice.ingest — identity (VA)', () => {
  test('VA4: actorCertId from ctx.operatorCert.certId on valid ingest (L2 cert-bound)', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, certId: OPERATOR_CERT_ID });

    await adapter.ingest(buildPayload(), ctx);

    expect(submitted[0].actorCertId).toBe(OPERATOR_CERT_ID);
  });

  test('VA5: no identityHandle on operator turn (XOR invariant)', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    await adapter.ingest(buildPayload(), ctx);

    // XOR: actorCertId present → identityHandle absent
    expect(submitted[0].identityHandle).toBeUndefined();
  });
});

describe('voice.ingest — conversationId stability (VA)', () => {
  test('VA6: conversationId is stable — same entityKind + entityId → same conversationId', async () => {
    const adapter = makeVoiceAdapter();
    const sub1: OddjobzConversationTurnPayload[] = [];
    const sub2: OddjobzConversationTurnPayload[] = [];

    await adapter.ingest(
      buildPayload({ entityId: 'job-stable-abc', entityKind: 'job', recordingId: 'rec-1' }),
      makeCtx({ submittedTurns: sub1 }),
    );
    await adapter.ingest(
      buildPayload({ entityId: 'job-stable-abc', entityKind: 'job', recordingId: 'rec-2' }),
      makeCtx({ submittedTurns: sub2 }),
    );

    expect(sub1[0].conversationId).toBe(sub2[0].conversationId);
    expect(sub1[0].conversationId).toBe(
      expectedConversationId('job', 'job-stable-abc'),
    );
  });

  test('VA7: different entityId → different conversationId', async () => {
    const adapter = makeVoiceAdapter();
    const sub1: OddjobzConversationTurnPayload[] = [];
    const sub2: OddjobzConversationTurnPayload[] = [];

    await adapter.ingest(
      buildPayload({ entityId: 'job-aaa', entityKind: 'job' }),
      makeCtx({ submittedTurns: sub1 }),
    );
    await adapter.ingest(
      buildPayload({ entityId: 'job-bbb', entityKind: 'job' }),
      makeCtx({ submittedTurns: sub2 }),
    );

    expect(sub1[0].conversationId).not.toBe(sub2[0].conversationId);
  });
});

describe('voice.ingest — correlationId fallback (VA)', () => {
  test('VA8: correlationId falls back to turnId when recordingId absent', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    // No recordingId
    await adapter.ingest(
      buildPayload({ recordingId: undefined }),
      ctx,
    );

    const turn = submitted[0];
    // When no recordingId: correlationId should equal turnId
    expect(turn.correlationId).toBe(turn.turnId);
  });
});

describe('voice.ingest — optional fields (VA)', () => {
  test('VA9: payload with all optional fields → ingest succeeds', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    const turns = await adapter.ingest(
      buildPayload({
        durationSeconds: 42,
        recordingId: 'rec-full-optional',
      }),
      ctx,
    );

    expect(turns.length).toBe(1);
    expect(submitted.length).toBe(1);
  });
});

describe('voice.ingest — validation (VA)', () => {
  test('VA10: invalid payload (missing entityId) → returns []', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    const payload = {
      transcript: TRANSCRIPT,
      entityKind: 'job',
      capturedAt: new Date().toISOString(),
    };

    const result = await adapter.ingest(payload, ctx);
    expect(result).toEqual([]);
  });

  test('VA11: invalid payload (wrong entityKind) → returns []', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    const payload = {
      transcript: TRANSCRIPT,
      entityId: ENTITY_ID,
      entityKind: 'unknown-kind', // invalid
      capturedAt: new Date().toISOString(),
    };

    const result = await adapter.ingest(payload, ctx);
    expect(result).toEqual([]);
  });

  test('VA12: invalid payload (non-object) → returns []', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    const result = await adapter.ingest('not-an-object', ctx);
    expect(result).toEqual([]);
  });
});

describe('voice.send — always fails (VA)', () => {
  test('VA13: send() does not throw on any turn input', async () => {
    const adapter = makeVoiceAdapter();
    const ctx = makeCtx();

    const result = await adapter.send(buildOutboundTurn(), ctx);

    expect(result.state).toBe('failed');
    expect(result.error).toBe('voice surface does not support outbound');
    expect(result.surfaceMessageId).toBeUndefined();
  });
});

describe('voice.ingest — entityRef (VA)', () => {
  test('VA14: entityRef.cellHash === payload.entityId (capture-time-bound)', async () => {
    const adapter = makeVoiceAdapter();
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted });

    const entityId = 'my-specific-job-cell-hash';
    await adapter.ingest(buildPayload({ entityId }), ctx);

    expect(submitted[0].entityRef!.cellHash).toBe(entityId);
  });

  test('VA15: entityRef.kind === payload.entityKind for each kind', async () => {
    const adapter = makeVoiceAdapter();

    for (const entityKind of ['job', 'site', 'customer'] as const) {
      const submitted: OddjobzConversationTurnPayload[] = [];
      const ctx = makeCtx({ submittedTurns: submitted });

      await adapter.ingest(buildPayload({ entityKind }), ctx);

      expect(submitted[0].entityRef!.kind).toBe(entityKind);
    }
  });
});

```
