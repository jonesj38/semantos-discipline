---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/__tests__/email-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.533724+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/__tests__/email-adapter.test.ts

```ts
/**
 * D-OJ-conv-email-intake — email surface adapter tests.
 *
 * Assertions (per deliverable spec):
 *
 * (a) Single inbound email → one canonical turn:
 *     surface='email', participantRole='external',
 *     identityHandle email, bodyText, timestamp from Date header.
 *
 * (b) Thread → ordered canonical turns with correct direction per sender
 *     + quotedTurnId from In-Reply-To (resolved to prior turn in thread).
 *
 * (c) Attachments → bodyParts with attachment entries.
 *
 * (d) Operator-sent message → direction='outbound', participantRole='operator',
 *     actorCertId from ctx.operatorCert.
 *
 * (e) Determinism — same email → same turnId.
 *
 * (f) Implements ConversationSurfaceAdapter (structural).
 *
 * Pre-existing baselines you must NOT chase:
 * oddjobz brain ≈8 fail + 6 errors (missing @anthropic-ai/sdk, D-O7/MT-7).
 * These new tests must ALL PASS; no new failures introduced.
 */

import {
  describe,
  expect,
  test,
} from 'bun:test';
import { makeEmailAdapter } from '../email.js';
import type { EmailRawPayload, EmailSender, EmailAdapterDeps } from '../email.js';
import type { ConversationSurfaceAdapter, AdapterContext } from '../contract.js';
import type { OddjobzConversationTurnPayload } from '../../conversation/conversation-turn-patch.js';

// ── RFC822 fixture builder ────────────────────────────────────────────────────

/**
 * Build a minimal RFC822-formatted email as a Uint8Array.
 *
 * Supports:
 *  - `from`      — From header (required)
 *  - `to`        — To header (required)
 *  - `subject`   — Subject header
 *  - `date`      — Date header (RFC5322 format)
 *  - `messageId` — Message-ID header
 *  - `inReplyTo` — In-Reply-To header
 *  - `references` — References header
 *  - `body`      — Plain text body
 *  - `contentType` — Content-Type header (defaults to 'text/plain')
 */
function buildRfc822(opts: {
  from: string;
  to: string;
  subject?: string;
  date?: string;
  messageId?: string;
  inReplyTo?: string;
  references?: string;
  body?: string;
  contentType?: string;
}): Uint8Array {
  const headers: string[] = [
    `From: ${opts.from}`,
    `To: ${opts.to}`,
    `Subject: ${opts.subject ?? 'Test'}`,
    `Date: ${opts.date ?? 'Tue, 01 Jan 2026 10:00:00 +1000'}`,
    `Content-Type: ${opts.contentType ?? 'text/plain; charset=utf-8'}`,
  ];

  if (opts.messageId) {
    headers.push(`Message-ID: <${opts.messageId}>`);
  }
  if (opts.inReplyTo) {
    headers.push(`In-Reply-To: <${opts.inReplyTo}>`);
  }
  if (opts.references) {
    headers.push(`References: <${opts.references}>`);
  }

  const email = headers.join('\r\n') + '\r\n\r\n' + (opts.body ?? 'Test body.');
  return new TextEncoder().encode(email);
}

/**
 * Build a multipart/mixed RFC822 email with a plain-text body and a fake PDF
 * attachment.
 */
function buildMultipartRfc822(opts: {
  from: string;
  to: string;
  subject?: string;
  date?: string;
  messageId?: string;
  body?: string;
}): Uint8Array {
  const boundary = 'test-boundary-001';
  const pdfContent = 'FAKE-PDF-CONTENT';
  const pdfBase64 = Buffer.from(pdfContent).toString('base64');

  const headers = [
    `From: ${opts.from}`,
    `To: ${opts.to}`,
    `Subject: ${opts.subject ?? 'Test with attachment'}`,
    `Date: ${opts.date ?? 'Tue, 01 Jan 2026 10:00:00 +1000'}`,
    `Message-ID: <${opts.messageId ?? 'multipart-test-001@example.com'}>`,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    `MIME-Version: 1.0`,
  ].join('\r\n');

  const plainPart = [
    `--${boundary}`,
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 7bit',
    '',
    opts.body ?? 'Please find the work order attached.',
    '',
  ].join('\r\n');

  const pdfPart = [
    `--${boundary}`,
    'Content-Type: application/pdf',
    'Content-Disposition: attachment; filename="work-order.pdf"',
    'Content-Transfer-Encoding: base64',
    '',
    pdfBase64,
    '',
    `--${boundary}--`,
  ].join('\r\n');

  const email = headers + '\r\n\r\n' + plainPart + pdfPart;
  return new TextEncoder().encode(email);
}

// ── Test helpers ──────────────────────────────────────────────────────────────

const OPERATOR_EMAIL = 'operator@oddjobtodd.com.au';
const CUSTOMER_EMAIL = 'jane.smith@example.com';
const OPERATOR_FROM = `Oddjob Todd <${OPERATOR_EMAIL}>`;
const CUSTOMER_FROM = `Jane Smith <${CUSTOMER_EMAIL}>`;

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

/** Build a standard EmailAdapterDeps with the test operator address. */
function makeTestDeps(overrides: Partial<EmailAdapterDeps> = {}): EmailAdapterDeps {
  return {
    operatorEmailAddresses: [OPERATOR_EMAIL],
    generateId: makeIdGen(),
    now: makeNow(),
    ...overrides,
  };
}

let _seq = 0;
function makeIdGen(): () => string {
  let seq = 0;
  return () => `test-id-${++seq}`;
}

function makeNow(ts = 1_748_770_000_000): () => number {
  return () => ts;
}

// ── (a) Single inbound email → one canonical turn ─────────────────────────────

describe('email.ingest — single inbound email (a)', () => {
  test('EA-A1: single inbound email → exactly one turn', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      subject: 'Fence quote request',
      messageId: 'msg-001@example.com',
      body: 'Hi, can I get a quote for a timber fence?',
    });

    const result = await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(result.length).toBe(1);
    expect(submitted.length).toBe(1);
  });

  test('EA-A2: surface=email on the canonical turn', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'msg-002@example.com',
      body: 'Hi, can I get a quote?',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].surface).toBe('email');
  });

  test('EA-A3: inbound from external → participantRole=external', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'msg-003@example.com',
      body: 'I need a fence quote.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].participantRole).toBe('external');
    expect(submitted[0].direction).toBe('inbound');
  });

  test('EA-A4: identityHandle = { kind: email, value: fromAddress }', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'msg-004@example.com',
      body: 'Quote request.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].identityHandle).toEqual({ kind: 'email', value: CUSTOMER_EMAIL });
    // XOR invariant: no actorCertId for un-cert'd external
    expect(submitted[0].actorCertId).toBeUndefined();
  });

  test('EA-A5: bodyText comes from the email plain-text body', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'msg-005@example.com',
      body: 'Can you replace the broken gate latch at 42 Smith St?',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].bodyText).toContain('replace the broken gate latch');
  });

  test('EA-A6: timestamp derived from Date header (unix ms)', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    // Use a specific date string: Thu, 22 May 2026 09:00:00 +1000
    const dateStr = 'Thu, 22 May 2026 09:00:00 +1000';
    const expectedMs = new Date(dateStr).getTime();

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      date: dateStr,
      messageId: 'msg-006@example.com',
      body: 'Quote request.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].timestamp).toBe(expectedMs);
  });
});

// ── (b) Thread → ordered canonical turns + direction + quotedTurnId ───────────

describe('email.ingest — thread (b)', () => {
  test('EA-B1: two-message thread → two turns', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-root@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'Hi, I need a fence quote.',
    });

    const msg2 = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'thread-reply-001@example.com',
      inReplyTo: 'thread-root@example.com',
      references: 'thread-root@example.com',
      date: 'Thu, 22 May 2026 09:30:00 +1000',
      body: 'Sure, I can do that. What size fence?',
    });

    const result = await adapter.ingest(
      { kind: 'thread', messages: [msg1, msg2] },
      ctx,
    );

    expect(result.length).toBe(2);
    expect(submitted.length).toBe(2);
  });

  test('EA-B2: first message from external → inbound', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b2-root@example.com',
      body: 'I need a fence quote.',
    });

    await adapter.ingest({ kind: 'single', bytes: msg1 }, ctx);

    expect(submitted[0].direction).toBe('inbound');
    expect(submitted[0].participantRole).toBe('external');
  });

  test('EA-B3: reply from operator → direction=outbound, participantRole=operator', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b3-root@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'I need a fence quote.',
    });

    const msg2 = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'thread-b3-reply@example.com',
      inReplyTo: 'thread-b3-root@example.com',
      references: 'thread-b3-root@example.com',
      date: 'Thu, 22 May 2026 10:00:00 +1000',
      body: 'Happy to help! What is the fence length?',
    });

    await adapter.ingest(
      { kind: 'thread', messages: [msg1, msg2] },
      ctx,
    );

    const operatorTurn = submitted.find(t => t.direction === 'outbound');
    expect(operatorTurn).toBeDefined();
    expect(operatorTurn!.participantRole).toBe('operator');
    expect(operatorTurn!.direction).toBe('outbound');
  });

  test('EA-B4: all turns in a thread share the same conversationId', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b4-root@example.com',
      body: 'Fence quote please.',
    });

    const msg2 = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'thread-b4-r1@example.com',
      inReplyTo: 'thread-b4-root@example.com',
      references: 'thread-b4-root@example.com',
      body: 'What length fence do you need?',
    });

    const msg3 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b4-r2@example.com',
      inReplyTo: 'thread-b4-r1@example.com',
      references: 'thread-b4-root@example.com thread-b4-r1@example.com',
      body: 'About 20 metres.',
    });

    await adapter.ingest(
      { kind: 'thread', messages: [msg1, msg2, msg3] },
      ctx,
    );

    const ids = submitted.map(t => t.conversationId);
    expect(ids.length).toBe(3);
    // All turns share the root message's conversationId.
    const unique = new Set(ids);
    expect(unique.size).toBe(1);
  });

  test('EA-B5: quotedTurnId from In-Reply-To resolved to prior turn in thread', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b5-root@example.com',
      body: 'Fence quote please.',
    });

    const msg2 = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'thread-b5-reply@example.com',
      inReplyTo: 'thread-b5-root@example.com',
      references: 'thread-b5-root@example.com',
      body: 'Sure, how long?',
    });

    await adapter.ingest(
      { kind: 'thread', messages: [msg1, msg2] },
      ctx,
    );

    const [turn1, turn2] = submitted;
    // The second turn (operator reply) quotes the first turn.
    expect(turn2.quotedTurnId).toBe(turn1.turnId);
  });

  test('EA-B6: first message (no In-Reply-To) has no quotedTurnId', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'thread-b6-standalone@example.com',
      body: 'Quote please.',
    });

    await adapter.ingest({ kind: 'single', bytes: msg1 }, ctx);

    expect(submitted[0].quotedTurnId).toBeUndefined();
  });

  test('EA-B7: three-message thread with In-Reply-To chain → correct quotedTurnId chain', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const msg1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'chain-root@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'Fence quote?',
    });

    const msg2 = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'chain-r1@example.com',
      inReplyTo: 'chain-root@example.com',
      references: 'chain-root@example.com',
      date: 'Thu, 22 May 2026 10:00:00 +1000',
      body: 'Sure! What length?',
    });

    const msg3 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'chain-r2@example.com',
      inReplyTo: 'chain-r1@example.com',
      references: 'chain-root@example.com chain-r1@example.com',
      date: 'Thu, 22 May 2026 10:30:00 +1000',
      body: '20 metres please.',
    });

    await adapter.ingest(
      { kind: 'thread', messages: [msg1, msg2, msg3] },
      ctx,
    );

    const [t1, t2, t3] = submitted;
    // t1 (customer) → no quotedTurnId (no In-Reply-To)
    expect(t1.quotedTurnId).toBeUndefined();
    // t2 (operator reply to msg1) → quotedTurnId = t1.turnId
    expect(t2.quotedTurnId).toBe(t1.turnId);
    // t3 (customer reply to msg2) → quotedTurnId = t2.turnId
    expect(t3.quotedTurnId).toBe(t2.turnId);
  });
});

// ── (c) Attachments → bodyParts ───────────────────────────────────────────────

describe('email.ingest — attachments (c)', () => {
  test('EA-C1: multipart email with PDF attachment → bodyParts contains attachment', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildMultipartRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'attachment-c1@example.com',
      body: 'Please find the work order attached.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    const turn = submitted[0];
    expect(turn.bodyParts).toBeDefined();
    expect(turn.bodyParts!.length).toBeGreaterThan(0);
    const attPart = turn.bodyParts!.find(p => p.kind === 'attachment');
    expect(attPart).toBeDefined();
  });

  test('EA-C2: attachment bodyPart carries attachmentKind=pdf', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildMultipartRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'attachment-c2@example.com',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    const turn = submitted[0];
    const attPart = turn.bodyParts?.find(p => p.kind === 'attachment') as
      | { kind: 'attachment'; payload: Record<string, unknown> }
      | undefined;

    expect(attPart).toBeDefined();
    expect(attPart!.payload.attachmentKind).toBe('pdf');
  });

  test('EA-C3: plain-text email (no attachments) → bodyParts absent', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'no-attachment@example.com',
      body: 'Just a simple text email.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    const turn = submitted[0];
    // No bodyParts when there are no attachments.
    expect(turn.bodyParts).toBeUndefined();
  });

  test('EA-C4: multipart email bodyText comes from text/plain part', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildMultipartRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'multipart-body@example.com',
      body: 'The plain text body from the multipart email.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].bodyText).toContain('The plain text body from the multipart email.');
  });
});

// ── (d) Operator-sent message → outbound ──────────────────────────────────────

describe('email.ingest — operator direction (d)', () => {
  test('EA-D1: email FROM operator → direction=outbound', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'operator-d1@example.com',
      body: 'Thanks for your enquiry! I can quote on Thursday.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].direction).toBe('outbound');
    expect(submitted[0].participantRole).toBe('operator');
  });

  test('EA-D2: operator message → actorCertId from ctx.operatorCert.certId', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'operator-d2@example.com',
      body: 'I can be there Thursday.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    // Operator turn carries the operator cert id.
    expect(submitted[0].actorCertId).toBe('cert-operator-test-001');
    // XOR invariant: no identityHandle for cert-bound operator role.
    expect(submitted[0].identityHandle).toBeUndefined();
  });

  test('EA-D3: operator turn without cert → actorCertId absent (no fabrication)', async () => {
    // Create a context with no operatorCert certId.
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];

    // Build a context with an empty certId to simulate missing cert.
    const ctx: AdapterContext = {
      operatorCert: {
        certId: '',
        subjectPublicKey: 'aa'.repeat(33),
        certifierPublicKey: 'bb'.repeat(33),
        type: 'plexus.identity.root',
        serialNumber: 'serial-nope',
        fields: {},
        signature: 'sig-test',
      },
      async resolveEntity() { return null; },
      async submitTurn(turn) { submitted.push(turn); },
    };

    const bytes = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'operator-d3@example.com',
      body: 'Operator message without a real cert.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    // Empty certId → adapter treats it as absent and leaves actorCertId unset.
    expect(submitted[0].actorCertId).toBeUndefined();
  });
});

// ── (e) Determinism — same email → same turnId ───────────────────────────────

describe('email.ingest — determinism (e)', () => {
  test('EA-E1: same single email ingested twice → same turnId both times', async () => {
    const deps = makeTestDeps({ generateId: makeIdGen(), now: makeNow() });
    const adapter = makeEmailAdapter(deps);
    const ctx1 = makeCtx({ resolveEntityResult: null });
    const ctx2 = makeCtx({ resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'determinism-e1@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'Determinism test email.',
    });

    const result1 = await adapter.ingest({ kind: 'single', bytes }, ctx1);
    const result2 = await adapter.ingest({ kind: 'single', bytes }, ctx2);

    expect(result1[0].turnId).toBe(result2[0].turnId);
  });

  test('EA-E2: same email with different bodies → different turnIds', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx1 = makeCtx({ resolveEntityResult: null });
    const ctx2 = makeCtx({ resolveEntityResult: null });

    const bytes1 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'determinism-e2a@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'Message A.',
    });

    const bytes2 = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'determinism-e2b@example.com',
      date: 'Thu, 22 May 2026 09:00:00 +1000',
      body: 'Message B.',
    });

    const result1 = await adapter.ingest({ kind: 'single', bytes: bytes1 }, ctx1);
    const result2 = await adapter.ingest({ kind: 'single', bytes: bytes2 }, ctx2);

    expect(result1[0].turnId).not.toBe(result2[0].turnId);
  });
});

// ── (f) ConversationSurfaceAdapter contract compliance ────────────────────────

describe('email adapter — ConversationSurfaceAdapter contract (f)', () => {
  test('EA-F1: adapter.surface === email', () => {
    const adapter = makeEmailAdapter();
    expect(adapter.surface).toBe('email');
  });

  test('EA-F2: implements ConversationSurfaceAdapter structurally', () => {
    const adapter = makeEmailAdapter();
    expect(typeof adapter.ingest).toBe('function');
    expect(typeof adapter.send).toBe('function');
    expect(typeof adapter.surface).toBe('string');
  });

  test('EA-F3: type-checks as ConversationSurfaceAdapter (compile-time)', () => {
    const adapter = makeEmailAdapter();
    const _typed: ConversationSurfaceAdapter = adapter;
    expect(Boolean(_typed)).toBe(true);
  });

  test('EA-F4: ingest returns OddjobzConversationTurnPayload[] (structural check)', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx = makeCtx({ resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'structural-f4@example.com',
      body: 'Contract check.',
    });

    const result = await adapter.ingest({ kind: 'single', bytes }, ctx);

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

  test('EA-F5: ingest calls ctx.submitTurn for each produced turn', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submittedTurns: OddjobzConversationTurnPayload[] = [];
    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() { return null; },
      async submitTurn(turn) { submittedTurns.push(turn); },
    };

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'submit-turn-f5@example.com',
      body: 'Submit check.',
    });

    const result = await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submittedTurns.length).toBe(result.length);
    for (const turn of result) {
      expect(submittedTurns.find(t => t.turnId === turn.turnId)).toBeDefined();
    }
  });

  test('EA-F6: send returns { state: delivered | failed }', async () => {
    const adapter = makeEmailAdapter({ emailSender: async () => 'msg-id-001' });
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-f6',
      conversationId: 'conv-send-f6',
      participantRole: 'operator',
      actorCertId: 'cert-operator-test-001',
      surface: 'email',
      direction: 'outbound',
      bodyText: 'Reply body for send test.',
      correlationId: 'corr-f6',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);
    expect(['delivered', 'failed']).toContain(result.state);
  });

  test('EA-F7: send with email sender → delivered + surfaceMessageId', async () => {
    const emailSender: EmailSender = async () => 'smtp-msg-id-001';
    const adapter = makeEmailAdapter({ emailSender });
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-f7',
      conversationId: 'conv-send-f7',
      participantRole: 'operator',
      actorCertId: 'cert-operator-test-001',
      surface: 'email',
      direction: 'outbound',
      bodyText: 'Reply text.',
      correlationId: 'corr-f7',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);
    expect(result.state).toBe('delivered');
    expect(result.surfaceMessageId).toBe('smtp-msg-id-001');
    expect(result.error).toBeUndefined();
  });

  test('EA-F8: send without emailSender configured → failed gracefully', async () => {
    const adapter = makeEmailAdapter({}); // no emailSender
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-f8',
      conversationId: 'conv-send-f8',
      participantRole: 'operator',
      surface: 'email',
      direction: 'outbound',
      bodyText: 'Reply.',
      correlationId: 'corr-f8',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);
    expect(result.state).toBe('failed');
    expect(result.error).toBeDefined();
  });

  test('EA-F9: send when emailSender throws → failed + error message', async () => {
    const emailSender: EmailSender = async () => {
      throw new Error('SMTP connection refused');
    };
    const adapter = makeEmailAdapter({ emailSender });
    const ctx = makeCtx();

    const turn: OddjobzConversationTurnPayload = {
      turnId: 'turn-send-f9',
      conversationId: 'conv-send-f9',
      participantRole: 'operator',
      surface: 'email',
      direction: 'outbound',
      bodyText: 'Reply.',
      correlationId: 'corr-f9',
      timestamp: 1_748_770_000_000,
    };

    const result = await adapter.send(turn, ctx);
    expect(result.state).toBe('failed');
    expect(result.error).toContain('SMTP connection refused');
  });
});

// ── Error cases ───────────────────────────────────────────────────────────────

describe('email.ingest — error cases', () => {
  test('EA-G1: null payload → throws', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx = makeCtx();
    await expect(adapter.ingest(null, ctx)).rejects.toThrow();
  });

  test('EA-G2: unknown payload kind → throws', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx = makeCtx();
    await expect(
      adapter.ingest({ kind: 'sms', bytes: new Uint8Array() }, ctx),
    ).rejects.toThrow();
  });

  test('EA-G3: empty thread messages array → throws', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx = makeCtx();
    await expect(
      adapter.ingest({ kind: 'thread', messages: [] }, ctx),
    ).rejects.toThrow();
  });

  test('EA-G4: non-Uint8Array bytes → throws', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const ctx = makeCtx();
    await expect(
      adapter.ingest({ kind: 'single', bytes: 'not-bytes' }, ctx),
    ).rejects.toThrow();
  });
});

// ── §6.3 entity resolution ────────────────────────────────────────────────────

describe('email.ingest — entity resolution §6.3', () => {
  test('EA-H1: entity hit → entityRef set on inbound turn', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({
      submittedTurns: submitted,
      resolveEntityResult: { cellHash: 'cell-job-hash-001', kind: 'job' },
    });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'entity-h1@example.com',
      body: 'Need a fence quote.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].entityRef).toEqual({ kind: 'job', cellHash: 'cell-job-hash-001' });
  });

  test('EA-H2: entity miss → entityRef absent (§6.3 lead-on-contact; no fabrication)', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const submitted: OddjobzConversationTurnPayload[] = [];
    const ctx = makeCtx({ submittedTurns: submitted, resolveEntityResult: null });

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'entity-h2@example.com',
      body: 'First contact; no entity yet.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(submitted[0].entityRef).toBeUndefined();
  });

  test('EA-H3: entity resolution uses identityHandle kind=email', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    const resolvedHandles: Array<{ kind: string; value: string }> = [];

    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity(handle) {
        resolvedHandles.push(handle);
        return null;
      },
      async submitTurn() {},
    };

    const bytes = buildRfc822({
      from: CUSTOMER_FROM,
      to: OPERATOR_FROM,
      messageId: 'entity-h3@example.com',
      body: 'Entity handle check.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    expect(resolvedHandles.length).toBeGreaterThan(0);
    expect(resolvedHandles[0].kind).toBe('email');
    expect(resolvedHandles[0].value).toBe(CUSTOMER_EMAIL);
  });

  test('EA-H4: outbound operator turn → resolveEntity NOT called', async () => {
    const adapter = makeEmailAdapter(makeTestDeps());
    let resolveCalled = false;

    const ctx: AdapterContext = {
      operatorCert: makeCtx().operatorCert,
      async resolveEntity() {
        resolveCalled = true;
        return null;
      },
      async submitTurn() {},
    };

    const bytes = buildRfc822({
      from: OPERATOR_FROM,
      to: CUSTOMER_FROM,
      messageId: 'entity-h4@example.com',
      body: 'Operator reply — no entity resolution needed.',
    });

    await adapter.ingest({ kind: 'single', bytes }, ctx);

    // Operator turns don't need entity resolution.
    expect(resolveCalled).toBe(false);
  });
});

```
