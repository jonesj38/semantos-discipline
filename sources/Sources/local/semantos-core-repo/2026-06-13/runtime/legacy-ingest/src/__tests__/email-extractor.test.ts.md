---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/email-extractor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.146355+00:00
---

# runtime/legacy-ingest/src/__tests__/email-extractor.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { EmailExtractor, parseRfc822, EMAIL_EXTRACTOR_VERSION } from '../extractor/email';
import {
  OJT_SENDER_ALLOWLIST,
  OJT_SELF_FORWARD_ADDRESSES,
} from '../extractor/pre-classifier';
import type { ExtractionOutcome, LLMAdapter } from '../extractor/types';
import type { RawItem } from '../types';

function emailItem(content: string): RawItem {
  return {
    providerId: 'gmail',
    providerItemId: 'msg-1',
    fetchedAt: 1000,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(content),
    metadata: {},
  };
}

/**
 * Tier 1.7 changed `extract()` to return `ExtractionOutcome[]` so the
 * bundle-fan-out path can produce N proposals. The non-bundle path
 * always returns a single-element array. This helper preserves the
 * old single-outcome assertion shape for the majority of tests that
 * exercise the non-bundle path.
 */
async function singleOutcome(
  extractor: EmailExtractor,
  item: RawItem,
  llm: LLMAdapter,
): Promise<ExtractionOutcome> {
  const outcomes = await extractor.extract(item, llm);
  expect(outcomes.length).toBe(1);
  return outcomes[0];
}

const REAL_EMAIL = `From: jane@example.com
To: todd@oddjobtodd.com.au
Subject: Quote for fence repair
Message-ID: <abc123@example.com>
In-Reply-To: <prev@example.com>
References: <root@example.com>

Hi Todd, can you give me a quote for repairing a 6m colorbond fence in
Tewantin? Available next Tuesday.
`;

describe('parseRfc822', () => {
  test('extracts headers + body', () => {
    const p = parseRfc822(new TextEncoder().encode(REAL_EMAIL));
    expect(p.from).toBe('jane@example.com');
    expect(p.subject).toBe('Quote for fence repair');
    expect(p.messageId).toBe('abc123@example.com');
    expect(p.inReplyTo).toBe('prev@example.com');
    expect(p.references).toBe('root@example.com');
    expect(p.body).toContain('Tewantin');
  });

  test('handles missing in-reply-to / references', () => {
    const p = parseRfc822(new TextEncoder().encode('From: a@b\r\nSubject: x\r\n\r\nbody'));
    expect(p.inReplyTo).toBeNull();
    expect(p.references).toBeNull();
  });
});

describe('EmailExtractor', () => {
  function stubLLM(payload: unknown, confidence: number): LLMAdapter {
    return {
      async extract<T>() {
        return { payload: payload as T, confidence, raw: JSON.stringify(payload) };
      },
    };
  }

  test('produces a proposal at sufficient confidence', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Jane wants a quote on a 6m colorbond fence in Tewantin.',
      customer: { name: 'Jane', email: 'jane@example.com' },
      job: { description: '6m colorbond fence', location: 'Tewantin' },
    }, 0.92);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.confidence).toBe(0.92);
    expect(outcome.proposal.status).toBe('pending');
    expect(outcome.proposal.provenance.providerId).toBe('gmail');
    expect(outcome.proposal.provenance.providerItemId).toBe('msg-1');
    expect(outcome.proposal.provenance.extractorVersion).toBe(EMAIL_EXTRACTOR_VERSION);
    expect(outcome.proposal.threadKey).toBe('prev@example.com');
    expect(outcome.proposal.summary).toMatch(/Tewantin/);
  });

  test('drops low-confidence outputs below the accept threshold', async () => {
    // job_type is one of the three job-creating values so we reach the
    // confidence gate (not_a_job / thread_followup short-circuit before
    // that gate).
    const extractor = new EmailExtractor({ acceptThreshold: 0.6 });
    const llm = stubLLM({ job_type: 'quote_request', summary: 'unclear' }, 0.3);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('low-confidence');
  });

  test('pre-filtered items short-circuit before LLM', async () => {
    const extractor = new EmailExtractor();
    let called = 0;
    const llm: LLMAdapter = {
      async extract<T>() {
        called += 1;
        return { payload: {} as T, confidence: 1, raw: '' };
      },
    };
    const newsletter = emailItem('Subject: Weekly Newsletter\r\nList-Unsubscribe: <x>\r\n\r\nbody');
    const outcome = await singleOutcome(extractor, newsletter, llm);
    expect(outcome.kind).toBe('pre-filtered');
    expect(called).toBe(0);
  });

  test('promptHash is deterministic across runs', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({ job_type: 'quote_request', summary: 'a' }, 0.9);
    const a = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    const b = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (a.kind !== 'extracted' || b.kind !== 'extracted') throw new Error('extracted expected');
    expect(a.proposal.provenance.promptHash).toBe(b.proposal.provenance.promptHash);
    // proposalIds should differ per call though
    expect(a.proposal.proposalId).not.toBe(b.proposal.proposalId);
  });

  test('threads point_of_contact from the LLM payload onto the proposal (PM at agency)', async () => {
    // Real-estate-agency case: the email is from a property manager
    // at Robert James Realty; the LLM extracts the named PM at the
    // agency as the point of contact — they're the one Todd will
    // text/call about this job.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'PM at RJR wants a quote on a fence repair at a tenanted property in Tewantin.',
      point_of_contact: 'Matthew Pohlen (Robert James Realty)',
      customer: { name: 'Matthew Pohlen', email: 'matthew@rjr.example' },
      job: { description: 'fence repair', location: 'Tewantin' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.pointOfContact).toBe('Matthew Pohlen (Robert James Realty)');
  });

  test('threads point_of_contact when the contact is a TENANT (day-to-day liaison)', async () => {
    // Tenant case: the agency forwards a tenant's request to Todd.
    // The tenant is the day-to-day liaison for access + scheduling, so
    // the LLM picks the tenant as the point of contact, not the
    // (unnamed) landlord and not the agency that just routed it.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'maintenance_order',
      summary: 'Tenant Sarah Liu wants the back door rehung at 13 Orealla Cr.',
      point_of_contact: 'Sarah Liu (tenant)',
      customer: { name: 'Sarah Liu', email: 'sarah.liu@example.com' },
      job: { description: 'rehang back door', location: '13 Orealla Cr' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBe('Sarah Liu (tenant)');
  });

  test('threads point_of_contact when the contact is a LANDLORD with no agency in the chain', async () => {
    // Direct-landlord case: the landlord emails Todd directly with no
    // agency intermediary. The "(direct)" suffix signals to the
    // operator that there's no agency to route through.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'maintenance_order',
      summary: 'Landlord Sarah Nguyen needs a leaking tap fixed at her rental.',
      point_of_contact: 'Sarah Nguyen (direct)',
      customer: { name: 'Sarah Nguyen', email: 'sarah@example.com' },
      job: { description: 'leaking kitchen tap', location: 'Tewantin' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBe('Sarah Nguyen (direct)');
  });

  test('threads point_of_contact when the contact is a SUB-TRADIE collaborating on someone elses job', async () => {
    // Sub-tradie case: another tradie wants Todd to come in on a job
    // they're running. Todd's reply-to is the sub-tradie, not the
    // end-customer (who Todd doesn't have a relationship with).
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Tradie Dan Murphy wants Todd to handle the carpentry portion of a renovation he is running.',
      point_of_contact: 'Dan Murphy (sub-tradie)',
      customer: { name: 'Dan Murphy', email: 'dan@dansbuilding.example' },
      job: { description: 'carpentry on renovation', location: 'Tewantin' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBe('Dan Murphy (sub-tradie)');
  });

  test('threads point_of_contact for a Bricks + Agent auto-dispatch with named PM', async () => {
    // Bricks routing case: the work order comes in via
    // noreply@bricksandagent.com but a PM is named in the routed
    // order. The combined "Bricks + Agent — <PM>" form keeps both the
    // dispatch source and the human contact visible.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'Bricks + Agent dispatched a work order from PM Lisa Tran.',
      point_of_contact: 'Bricks + Agent — Lisa Tran',
      customer: { name: 'Lisa Tran' },
      job: { description: 'oven not heating', location: 'Tewantin', referenceNumber: 'BA-12345' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBe('Bricks + Agent — Lisa Tran');
  });

  test('point_of_contact is undefined when the LLM omits it (older / poorly-extracted emails)', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'fence repair',
      // no point_of_contact field
    }, 0.9);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBeUndefined();
  });

  test('point_of_contact is trimmed and length-capped to 200 chars', async () => {
    const extractor = new EmailExtractor();
    const padded = '   Bricks + Agent   ';
    const tooLong = 'A'.repeat(500);
    const llm1 = stubLLM({ job_type: 'work_order', summary: 's', point_of_contact: padded }, 0.9);
    const out1 = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm1);
    if (out1.kind !== 'extracted') throw new Error('extracted expected');
    expect(out1.proposal.pointOfContact).toBe('Bricks + Agent');

    const llm2 = stubLLM({ job_type: 'work_order', summary: 's', point_of_contact: tooLong }, 0.9);
    const out2 = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm2);
    if (out2.kind !== 'extracted') throw new Error('extracted expected');
    expect(out2.proposal.pointOfContact?.length).toBe(200);
  });

  test('prompt mentions the point_of_contact extraction instructions', async () => {
    // Snapshot-style assertion: future prompt edits that drop the
    // point-of-contact guidance will fail this — the operator's
    // helm/mobile display name depends on the LLM understanding what
    // to extract, so the prompt's contract is load-bearing.
    const extractor = new EmailExtractor();
    let capturedPrompt: string | null = null;
    const llm: LLMAdapter = {
      async extract<T>(opts: { prompt: string; schema: object }) {
        capturedPrompt = opts.prompt;
        return {
          payload: { job_type: 'quote_request', summary: 's' } as T,
          confidence: 0.9,
          raw: '',
        };
      },
    };
    await extractor.extract(emailItem(REAL_EMAIL), llm);
    expect(capturedPrompt).not.toBeNull();
    const p = capturedPrompt!;
    expect(p).toContain('point_of_contact');
    expect(p).toContain('point of contact');
    expect(p).toContain('Bricks + Agent');
    expect(p).toContain('NOT the billing party');
    expect(p).toContain('NOT the property owner');
    // Broader-scope contract: the prompt must explicitly mention each
    // non-agency role the contact could be — tenant (day-to-day),
    // landlord (direct), sub-tradie. If a prompt edit collapses these
    // back to "agency / agent / business" only, this test fails and
    // the operator stops getting a tenant's name on a tenant-driven
    // job.
    expect(p).toContain('tenant');
    expect(p).toContain('landlord');
    expect(p).toContain('sub-tradie');
    expect(p).toContain('(direct)');
  });

  // ── job_type classification — Phase 1 outcome routing ────────────────
  //
  // Operator data showed ~90% false-positive proposals at 0.95+ confidence
  // because the prior prompt schema (`lead | quote | booking | ...`) let
  // the LLM call any structured email a "lead". The fix is to force a
  // five-way classification first; only the three job-creating values
  // produce a proposal. Each branch is asserted below, including the
  // false-positive categories the operator has actually been hit by.

  test('job_type=not_a_job short-circuits to pre-filtered (no proposal created)', async () => {
    // The Bricks weekly digest, Google Cloud product updates, Facebook
    // business partner requests, Desire Industries advertising receipts,
    // Google Workspace / Ads billing — all of these were producing
    // 0.95+ confidence proposals before this fix. The LLM now routes
    // them to `not_a_job`, which the extractor surfaces as a
    // `pre-filtered` outcome (the runner increments `preFiltered` and
    // proposalStore receives nothing).
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'not_a_job',
      summary: 'Google Cloud product update notification — not a job.',
    }, 0.97);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('pre-filtered');
    if (outcome.kind !== 'pre-filtered') return;
    expect(outcome.reason).toContain('not_a_job');
    expect(outcome.reason).toContain('Google Cloud');
  });

  test('job_type=thread_followup short-circuits to pre-filtered (existing thread, no duplicate proposal)', async () => {
    // Replies on an existing job thread — scheduling access, sending an
    // invoice, confirming completion — are NOT new jobs. The
    // thread-fold pass on subsequent runs already keeps state coherent;
    // we'd just create a duplicate proposal otherwise. Surfaces as a
    // `pre-filtered` outcome with the `thread_followup` marker so audit
    // logs can distinguish the two non-job-creating buckets.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'thread_followup',
      summary: 'Reply confirming Tuesday access for the previously-discussed fence repair.',
    }, 0.94);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('pre-filtered');
    if (outcome.kind !== 'pre-filtered') return;
    expect(outcome.reason).toContain('thread_followup');
    expect(outcome.reason).toContain('existing thread');
  });

  test('job_type=quote_request continues to extraction', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Customer wants a quote for fence repair.',
      point_of_contact: 'Jane Smith',
      customer: { name: 'Jane Smith', email: 'jane@example.com' },
      job: { description: 'fence repair', location: 'Tewantin' },
    }, 0.9);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.pointOfContact).toBe('Jane Smith');
    expect(outcome.proposal.summary).toMatch(/quote/);
  });

  test('job_type=work_order continues to extraction', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'Bricks + Agent dispatched a work order for an oven repair.',
      point_of_contact: 'Bricks + Agent — Lisa Tran',
      customer: { name: 'Lisa Tran' },
      job: { description: 'oven not heating', location: 'Tewantin', referenceNumber: 'BA-12345' },
    }, 0.95);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.referenceNumber).toBe('BA-12345');
    expect(outcome.proposal.pointOfContact).toBe('Bricks + Agent — Lisa Tran');
  });

  test('job_type=maintenance_order continues to extraction', async () => {
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'maintenance_order',
      summary: 'Tenant reports a leaking kitchen tap at 13 Orealla Cr.',
      point_of_contact: 'Sarah Liu (tenant)',
      customer: { name: 'Sarah Liu' },
      job: { description: 'leaking kitchen tap', location: '13 Orealla Cr' },
    }, 0.88);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.pointOfContact).toBe('Sarah Liu (tenant)');
    expect(outcome.proposal.summary).toMatch(/leaking/);
  });

  test('not_a_job pre-filter happens BEFORE the confidence gate', async () => {
    // Even at confidence < acceptThreshold, a `not_a_job` classification
    // takes precedence. Otherwise a low-confidence "this is junk" call
    // would surface as `low-confidence` instead of `pre-filtered`,
    // muddling the run-summary counters.
    const extractor = new EmailExtractor({ acceptThreshold: 0.6 });
    const llm = stubLLM({ job_type: 'not_a_job', summary: 'newsletter' }, 0.2);
    const outcome = await singleOutcome(extractor, emailItem(REAL_EMAIL), llm);
    expect(outcome.kind).toBe('pre-filtered');
  });

  test('prompt encodes the five-way classification with false-positive examples', async () => {
    // Snapshot-style assertion: the operator-supplied list of
    // false-positive categories (Google Cloud, Facebook / Meta, Bricks
    // weekly digest, billing receipts, Desire Industries) must stay in
    // the prompt. A future edit that quietly drops these would
    // re-introduce the ~90%-false-positive regression that motivated
    // this PR — fail loudly here instead.
    const extractor = new EmailExtractor();
    let capturedPrompt: string | null = null;
    const llm: LLMAdapter = {
      async extract<T>(opts: { prompt: string; schema: object }) {
        capturedPrompt = opts.prompt;
        return {
          payload: { job_type: 'quote_request', summary: 's' } as T,
          confidence: 0.9,
          raw: '',
        };
      },
    };
    await extractor.extract(emailItem(REAL_EMAIL), llm);
    expect(capturedPrompt).not.toBeNull();
    const p = capturedPrompt!;
    // Phase 1 — the five enum values must each appear in the prompt
    // body, not just the schema.
    expect(p).toContain('quote_request');
    expect(p).toContain('work_order');
    expect(p).toContain('maintenance_order');
    expect(p).toContain('thread_followup');
    expect(p).toContain('not_a_job');
    // Phase-1 framing: the operator's three-event-type domain rule.
    // Tolerant of line-break placement — the framing sentence wraps
    // mid-phrase in the prompt template.
    const collapsedWhitespace = p.replace(/\s+/g, ' ');
    expect(collapsedWhitespace).toContain('Quote Request');
    expect(collapsedWhitespace).toContain('Work Order');
    expect(collapsedWhitespace).toContain('Maintenance Order');
    // False-positive categories that motivated the PR. If any of these
    // gets dropped, the regression reopens.
    expect(p).toContain('Google');
    expect(p).toContain('Facebook');
    expect(p).toContain('Bricks');
    expect(p).toContain('digest');
    expect(p).toContain('newsletters');
    expect(p).toContain('Billing receipts');
    // The decision rule: prefer false-negatives over false-positives.
    // Tolerant of line-wrap placement.
    expect(collapsedWhitespace).toContain('False positives');
    expect(collapsedWhitespace).toContain('false negatives');
  });
});

// ── Tier 1.7 — deep-PDF extraction + bundle fan-out ──────────────────────
//
// Operator brief: when a forwarded bundle of N PDF work-orders comes in,
// fan out one proposal per PDF. Each proposal carries the deep-PDF
// fields (work-order number, dates, primary contact + phone, secondary
// contacts, owner name, billing party per source rules, photo presence,
// and a server-side source_attachment_path). The legacy single-shot
// path (one email → one proposal) is preserved as an array of length 1.

import type { VisionAdapter } from '../extractor/attachment';

/**
 * Build a multipart/mixed RFC822 email with N pretend-PDF attachments.
 * The bytes don't need to be a real PDF — the test's VisionAdapter
 * stub just returns canned OCR text per attachment, so the extractor
 * never decodes the bytes itself.
 */
function buildBundleEmail(opts: {
  from: string;
  subject?: string;
  attachmentCount: number;
}): string {
  const boundary = 'tier17-test-boundary';
  const head = [
    `From: ${opts.from}`,
    `To: todd@oddjobtodd.com.au`,
    `Subject: ${opts.subject ?? 'Bundled work orders'}`,
    `Message-ID: <bundle-${Date.now()}@example.com>`,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    '',
    '',
  ].join('\n');
  const text = [
    `--${boundary}`,
    'Content-Type: text/plain; charset=utf-8',
    '',
    'See attached.',
    '',
  ].join('\n');
  const attachments: string[] = [];
  for (let i = 0; i < opts.attachmentCount; i++) {
    attachments.push([
      `--${boundary}`,
      `Content-Type: application/pdf`,
      `Content-Transfer-Encoding: base64`,
      `Content-Disposition: attachment; filename="wo-${i + 1}.pdf"`,
      '',
      // 16 bytes of zeros — base64 "AAAAAAAAAAAAAAAAAAAAAA==".
      'AAAAAAAAAAAAAAAAAAAAAA==',
      '',
    ].join('\n'));
  }
  return head + text + attachments.join('') + `--${boundary}--\n`;
}

/**
 * Matches the operator's May 2026 Clever Property batch shape: one
 * self-sent wrapper email whose attachments are forwarded `.eml`
 * messages, each nested message carrying its own PDF quote request.
 */
function buildNestedEmlBundleEmail(opts: {
  from: string;
  attachmentCount: number;
}): string {
  const outerBoundary = 'tier17-outer-eml-boundary';
  const head = [
    `From: ${opts.from}`,
    `To: todd@oddjobtodd.info`,
    'Subject: Quote Requests',
    `Message-ID: <nested-bundle-${Date.now()}@example.com>`,
    `Content-Type: multipart/mixed; boundary="${outerBoundary}"`,
    '',
    '',
  ].join('\n');
  const text = [
    `--${outerBoundary}`,
    'Content-Type: text/plain; charset=utf-8',
    '',
    'Forwarded Clever quote requests attached.',
    '',
  ].join('\n');
  const attachments: string[] = [];
  for (let i = 0; i < opts.attachmentCount; i++) {
    const innerBoundary = `tier17-inner-eml-boundary-${i}`;
    const nested = [
      'From: Clever Property <cleverproperty@email.propertyme.com>',
      'To: Todd Price <todd.price.aus@gmail.com>',
      `Subject: Quote request - ${i + 1} Test St, Tewantin QLD 4565`,
      `Content-Type: multipart/mixed; boundary="${innerBoundary}"`,
      '',
      `--${innerBoundary}`,
      'Content-Type: text/html; charset=utf-8',
      'Content-Transfer-Encoding: quoted-printable',
      '',
      'Please quote the attached maintenance request.',
      '',
      `--${innerBoundary}`,
      'Content-Type: application/pdf; name="Quote Request.pdf"',
      'Content-Transfer-Encoding: base64',
      'Content-Disposition: attachment; filename="Quote Request.pdf"',
      '',
      'AAAAAAAAAAAAAAAAAAAAAA==',
      '',
      `--${innerBoundary}--`,
      '',
    ].join('\n');
    attachments.push([
      `--${outerBoundary}`,
      `Content-Type: message/rfc822; name="quote-${i + 1}.eml"`,
      `Content-Disposition: attachment; filename="quote-${i + 1}.eml"`,
      '',
      nested,
    ].join('\n'));
  }
  return head + text + attachments.join('') + `--${outerBoundary}--\n`;
}

/**
 * Stub vision adapter — returns the pre-canned OCR text for each
 * call. Per call, pops the next response off the queue. Tests
 * preload the queue with one entry per PDF attachment.
 */
function stubVision(responses: string[]): { vision: VisionAdapter; calls: number } {
  const state = { calls: 0 };
  return {
    calls: 0,
    vision: {
      async describeImage(_b: string, _m: string) {
        const text = responses[state.calls] ?? '';
        state.calls += 1;
        // Surface call count to the caller via shared object identity.
        // (We can't return it from describeImage; tests inspect calls
        // through the closure.)
        Object.assign(this as any, { _calls: state.calls });
        return text;
      },
    } as VisionAdapter & { _calls?: number },
  };
}

const CP_07487_OCR = `
8 Thomas St
Noosaville QLD 4566
www.cleverproperty.com.au
pm@cleverproperty.com.au

Quote Request

Odd Job Todd - Handyman

Job number - 07487
Created: 17/03/2026
Due: 24/03/2026

Property
29 Foedera Cres, Tewantin QLD 4565 (key #177)

For access contact the tenant/s on:
Jo-Anne Bisman
(m) 0450688322 (h) n/a (w) n/a
(e) josiesingh@bigpond.com

Sujit (Sunny) Singh
(m) 0449988150 (h) n/a (w) n/a
(e) sunnymehmi2221@gmail.com

Work order issued on behalf of the owner - Adrian Levy

For queries contact the agent on:
Zoe Welch
(w) 0754730508
(e) zoe.welch@cleverproperty.com.au

Description
Paint Ceiling
`;

const CP_07487_LLM_PAYLOAD = {
  job_type: 'quote_request' as const,
  summary: 'Clever Property — paint ceiling at 29 Foedera Cres, Tewantin.',
  work_order_number: '07487',
  issuance_date: '2026-03-17',
  due_date: '2026-03-24',
  property_address: '29 Foedera Cres, Tewantin QLD 4565',
  property_key: 'key #177',
  primary_contact: {
    name: 'Jo-Anne Bisman',
    role: 'tenant' as const,
    phone: '0450688322',
    email: 'josiesingh@bigpond.com',
  },
  secondary_contacts: [
    {
      name: 'Sujit (Sunny) Singh',
      role: 'tenant' as const,
      phone: '0449988150',
      email: 'sunnymehmi2221@gmail.com',
    },
    {
      name: 'Zoe Welch',
      role: 'agent' as const,
      phone: '0754730508',
      email: 'zoe.welch@cleverproperty.com.au',
    },
  ],
  owner_name: 'Adrian Levy',
  // The LLM may emit billing_party but the server's source-domain
  // heuristic is canonical for CP — always agency.
  billing_party: { type: 'agency' as const, name: 'Clever Property' },
  has_photos: false,
  photo_count: 0,
};

describe('EmailExtractor — Tier 1.7 deep PDF extraction', () => {
  function stubLLM(payload: unknown, confidence: number): LLMAdapter {
    return {
      async extract<T>() {
        return { payload: payload as T, confidence, raw: JSON.stringify(payload) };
      },
    };
  }

  // 1. Bundle fan-out: ≥2 PDFs from operator's own address → N outcomes.
  test('bundle fan-out: operator-self-forward with 3 PDFs produces 3 outcomes with distinct source_attachment_path', async () => {
    const { vision } = stubVision([
      CP_07487_OCR,
      CP_07487_OCR.replace('07487', '07628').replace('Foedera Cres', 'Riverside Dr'),
      CP_07487_OCR.replace('07487', '07911').replace('Foedera Cres', 'Beach Rd'),
    ]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM(CP_07487_LLM_PAYLOAD, 0.92);

    const email = buildBundleEmail({
      from: 'todd.price.aus@gmail.com',
      attachmentCount: 3,
    });
    const outcomes = await extractor.extract(emailItem(email), llm);

    expect(outcomes.length).toBe(3);
    const extractedPaths = outcomes
      .filter(o => o.kind === 'extracted')
      .map(o => (o as Extract<ExtractionOutcome, { kind: 'extracted' }>).proposal.sourceAttachmentPath);
    // Distinct paths, one per attachment in the bundle.
    expect(new Set(extractedPaths).size).toBe(extractedPaths.length);
    expect(extractedPaths.length).toBe(3);
    for (let i = 0; i < extractedPaths.length; i++) {
      expect(extractedPaths[i]).toMatch(/#attachment-\d+$/);
    }
  });

  test('bundle fan-out: operator-self-forward with .eml attachments unwraps nested PDFs', async () => {
    const { vision } = stubVision([
      CP_07487_OCR,
      CP_07487_OCR.replace('07487', '07628').replace('Foedera Cres', 'Riverside Dr'),
    ]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM(CP_07487_LLM_PAYLOAD, 0.92);

    const email = buildNestedEmlBundleEmail({
      from: 'todd.price.aus@gmail.com',
      attachmentCount: 2,
    });
    const outcomes = await extractor.extract(emailItem(email), llm);

    expect(outcomes.length).toBe(2);
    const extractedPaths = outcomes
      .filter(o => o.kind === 'extracted')
      .map(o => (o as Extract<ExtractionOutcome, { kind: 'extracted' }>).proposal.sourceAttachmentPath);
    expect(extractedPaths).toEqual([
      'legacy-ingest/gmail/msg-1#attachment-0',
      'legacy-ingest/gmail/msg-1#attachment-1',
    ]);
  });

  // 2. Single-PDF regression — 1 PDF from a NORMAL sender returns
  //    exactly one outcome (the legacy one-email-one-proposal flow).
  test('non-bundle: 1 PDF from a normal sender produces exactly one outcome', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM(CP_07487_LLM_PAYLOAD, 0.92);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcomes = await extractor.extract(emailItem(email), llm);
    expect(outcomes.length).toBe(1);
    expect(outcomes[0].kind).toBe('extracted');
  });

  // 2b. Non-bundle even with many PDFs — sender is not operator
  //     (e.g. a property manager forwarded a couple of orders), so we
  //     stay on the single-shot path (the operator's bundle pattern is
  //     only ever from their own address).
  test('non-bundle: ≥2 PDFs from a non-operator sender stays on the single-shot path', async () => {
    const { vision } = stubVision([CP_07487_OCR, CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM(CP_07487_LLM_PAYLOAD, 0.92);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 2,
    });
    const outcomes = await extractor.extract(emailItem(email), llm);
    expect(outcomes.length).toBe(1);
  });

  // 3. Clever Property full extraction — primary tenant + secondaries
  //    + owner + billing party + WO# + dates + property key + display
  //    alias.
  test('Clever Property: primary tenant, secondaries, owner, billing party, dates, key extracted', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM(CP_07487_LLM_PAYLOAD, 0.92);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    const p = outcome.proposal;
    expect(p.primaryContact?.name).toBe('Jo-Anne Bisman');
    expect(p.primaryContact?.role).toBe('tenant');
    expect(p.primaryContact?.phone).toBe('0450688322');
    expect(p.secondaryContacts?.length).toBe(2);
    expect(p.secondaryContacts?.[0].name).toBe('Sujit (Sunny) Singh');
    expect(p.secondaryContacts?.[0].role).toBe('tenant');
    expect(p.secondaryContacts?.[1].name).toBe('Zoe Welch');
    expect(p.secondaryContacts?.[1].role).toBe('agent');
    expect(p.ownerName).toBe('Adrian Levy');
    expect(p.billingParty).toEqual({ type: 'agency', name: 'Clever Property' });
    expect(p.workOrderNumber).toBe('07487');
    expect(p.issuanceDate).toBe('2026-03-17');
    expect(p.dueDate).toBe('2026-03-24');
    expect(p.propertyKey).toBe('key #177');
    expect(p.propertyAddress).toBe('29 Foedera Cres, Tewantin QLD 4565');
    // Display alias derived server-side from primary_contact.
    expect(p.pointOfContact).toBe('Jo-Anne Bisman (tenant)');
  });

  // 4. RJR variance — owner billing.
  test('RJR variance — owner billing: "on behalf of <owner>" line names a person → bill owner', async () => {
    const { vision } = stubVision([CP_07487_OCR.replace('Adrian Levy', 'John Smith')]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      ...CP_07487_LLM_PAYLOAD,
      owner_name: 'John Smith',
      // The LLM may correctly emit owner billing — server validates.
      billing_party: { type: 'owner', name: 'John Smith' },
    }, 0.91);

    const email = buildBundleEmail({
      from: 'matthew@robertjamesrealty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.billingParty).toEqual({ type: 'owner', name: 'John Smith' });
  });

  // 5. RJR variance — agency billing (when "on behalf of" line names
  //    RJR itself or is absent, fall through to agency billing).
  test('RJR variance — agency billing: no owner_name → bill Robert James Realty', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      ...CP_07487_LLM_PAYLOAD,
      // owner_name absent / null → fall through to agency.
      owner_name: null,
      billing_party: { type: 'agency', name: 'Robert James Realty' },
    }, 0.9);

    const email = buildBundleEmail({
      from: 'lisa@robertjamesrealty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'Robert James Realty',
    });
  });

  // 5b. Defence — Clever Property is ALWAYS agency-billed regardless
  //     of whether the LLM emits owner billing for it. The
  //     source-domain heuristic overrides the LLM's guess.
  test('Clever Property: agency billing wins even if the LLM erroneously emits owner billing', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      ...CP_07487_LLM_PAYLOAD,
      // LLM hallucinates an owner-bill for a CP order — server clobbers.
      billing_party: { type: 'owner', name: 'Adrian Levy' },
    }, 0.93);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'Clever Property',
    });
  });

  // 6. Photos detection.
  test('photos: has_photos true / photo_count 2 propagates onto the proposal', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      ...CP_07487_LLM_PAYLOAD,
      has_photos: true,
      photo_count: 2,
    }, 0.92);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.hasPhotos).toBe(true);
    expect(outcome.proposal.photoCount).toBe(2);
  });

  // 7. source_attachment_path is server-side and immutable from LLM —
  //    defence against prompt injection in PDF content trying to
  //    redirect the path to a malicious blob key.
  test('source_attachment_path is immutable from the LLM (prompt-injection defence)', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      ...CP_07487_LLM_PAYLOAD,
      // Attempt a prompt-injection redirect; the server-side
      // sourceAttachmentPath is deterministic from the RawItem.
      source_attachment_path: 'attacker/path',
    }, 0.92);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.sourceAttachmentPath).toBe('legacy-ingest/gmail/msg-1');
    expect(outcome.proposal.sourceAttachmentPath).not.toContain('attacker');
  });

  // 8. Backward compat — pointOfContact is derived from primaryContact
  //    server-side. The LLM does NOT need to emit point_of_contact for
  //    the display alias to work.
  test('backward compat: pointOfContact is derived from primaryContact server-side', async () => {
    const { vision } = stubVision([CP_07487_OCR]);
    const extractor = new EmailExtractor({ vision });
    const llm = stubLLM({
      // Include only the new primary_contact; do NOT emit
      // legacy point_of_contact.
      job_type: 'quote_request',
      summary: 's',
      primary_contact: {
        name: 'Jo-Anne Bisman',
        role: 'tenant',
        phone: '0450688322',
        email: 'josiesingh@bigpond.com',
      },
    }, 0.9);

    const email = buildBundleEmail({
      from: 'pm@cleverproperty.com.au',
      attachmentCount: 1,
    });
    const outcome = (await extractor.extract(emailItem(email), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('extracted expected');
    expect(outcome.proposal.pointOfContact).toBe('Jo-Anne Bisman (tenant)');
  });

  // 9. The extractor version bumped — re-extract supersedes prior v0.5
  //    proposals. (Defence-in-depth: a future revert that drops the
  //    bump would silently leave the old proposals in place.)
  test('extractor version bumped to v0.6 (D-RTC.3 services elicitation)', () => {
    expect(EMAIL_EXTRACTOR_VERSION).toBe('email-rfc822-v0.6');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * D-RTC.7-followup — sender allowlist threading through EmailExtractor
 * ────────────────────────────────────────────────────────────────────── */

describe('EmailExtractor — sender allowlist', () => {
  function bytes(s: string): RawItem {
    const fromMatch = /^From:\s*(.+)$/im.exec(s);
    return {
      providerId: 'gmail',
      providerItemId: 'm',
      fetchedAt: 1,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode(s),
      metadata: fromMatch ? { from: fromMatch[1]!.trim() } : {},
    };
  }

  const llm: LLMAdapter = {
    async extract<T>() {
      return {
        payload: { job_type: 'quote_request', summary: 'test' } as unknown as T,
        confidence: 0.9,
        raw: '',
      };
    },
  };

  test('without allowlist: random sender extracts normally', async () => {
    const extractor = new EmailExtractor();
    const r = await extractor.extract(
      bytes('From: random@example.com\r\nSubject: Quote please\r\n\r\nHi'),
      llm,
    );
    expect(r[0]!.kind).toBe('extracted');
  });

  test('with OJT allowlist: random sender is pre-filtered', async () => {
    const extractor = new EmailExtractor({
      senderAllowlist: OJT_SENDER_ALLOWLIST,
      selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
    });
    const r = await extractor.extract(
      bytes('From: random@example.com\r\nSubject: Quote please\r\n\r\nHi'),
      llm,
    );
    expect(r[0]!.kind).toBe('pre-filtered');
    if (r[0]!.kind === 'pre-filtered') {
      expect(r[0]!.reason).toMatch(/sender not in allowlist/);
    }
  });

  test('with OJT allowlist: Clever Property passes through', async () => {
    const extractor = new EmailExtractor({
      senderAllowlist: OJT_SENDER_ALLOWLIST,
      selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
    });
    const r = await extractor.extract(
      bytes('From: pm@cleverproperty.com.au\r\nSubject: WO\r\n\r\nbody'),
      llm,
    );
    expect(r[0]!.kind).toBe('extracted');
  });

  test('with OJT allowlist: Robert James Realty passes through', async () => {
    const extractor = new EmailExtractor({
      senderAllowlist: OJT_SENDER_ALLOWLIST,
      selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
    });
    const r = await extractor.extract(
      bytes('From: admin@robertjamesrealty.com.au\r\nSubject: WO\r\n\r\nbody'),
      llm,
    );
    expect(r[0]!.kind).toBe('extracted');
  });

  test('with OJT allowlist: Todd\'s gmail bypasses via selfForward', async () => {
    const extractor = new EmailExtractor({
      senderAllowlist: OJT_SENDER_ALLOWLIST,
      selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,
    });
    const r = await extractor.extract(
      bytes('From: todd.price.aus@gmail.com\r\nSubject: Fwd: bundle\r\n\r\nbody'),
      llm,
    );
    expect(r[0]!.kind).toBe('extracted');
  });
});

```
