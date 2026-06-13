---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/reingest-extractor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.151513+00:00
---

# runtime/legacy-ingest/src/__tests__/reingest-extractor.test.ts

```ts
/**
 * D-RTC.3 — extraction prompt + field-schema upgrade conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.3.
 *
 * Two responsibilities:
 *   1. The new `services` field flows LLM payload → Proposal cleanly,
 *      with defensive normalisation against prompt-injection /
 *      malformed-LLM input.
 *   2. The canonical `cell-schema.json` (the contract D-RTC.4 cell
 *      encoding will validate against) carries every cell type +
 *      field the PRD §Cell-shape tables require, with the new
 *      contact-role taxonomy.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  EmailExtractor,
  EMAIL_EXTRACTOR_VERSION,
  type EmailExtractionPayload,
} from '../extractor/email';
import type { LLMAdapter } from '../extractor/types';
import type { RawItem } from '../types';

/* ──────────────────────────────────────────────────────────────────────
 * Test helpers
 * ────────────────────────────────────────────────────────────────────── */

function stubLLM(payload: EmailExtractionPayload, confidence = 0.9): LLMAdapter {
  return {
    async extract<T>(): Promise<{ payload: T; confidence: number; raw: string }> {
      return { payload: payload as unknown as T, confidence, raw: '' };
    },
  };
}

function emailItem(body: string): RawItem {
  return {
    providerId: 'gmail',
    providerItemId: 'test-msg-1',
    fetchedAt: 1700000000000,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(body),
    metadata: {},
  };
}

const MINIMAL_EMAIL = [
  'From: pm@cleverproperty.com.au',
  'To: ops@example.com',
  'Subject: New job',
  '',
  'Body',
].join('\r\n');

/* ──────────────────────────────────────────────────────────────────────
 * Extractor version bump
 * ────────────────────────────────────────────────────────────────────── */

describe('D-RTC.3: extractor version bump', () => {
  test('extractor version is v0.6', () => {
    expect(EMAIL_EXTRACTOR_VERSION).toBe('email-rfc822-v0.6');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * services flow + defensive normalisation
 * ────────────────────────────────────────────────────────────────────── */

describe('D-RTC.3: services field flows LLM → Proposal', () => {
  test('clean service tags pass through', async () => {
    const llm = stubLLM({
      job_type: 'maintenance_order',
      summary: 'Leaking tap at 13 Oak Rd.',
      services: ['plumbing', 'leak-investigation'],
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.services).toEqual(['plumbing', 'leak-investigation']);
  });

  test('services are lowercased + whitespace-collapsed + non-alnum stripped', async () => {
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'pergola build',
      services: ['Pergola Build', '  ROOF REPAIR  ', 'tap@home!'],
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('expected extracted');
    expect(outcome.proposal.services).toEqual(['pergola-build', 'roof-repair', 'taphome']);
  });

  test('services are deduped + capped at 8', async () => {
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'multi-service',
      services: [
        'plumbing', 'plumbing', 'PLUMBING',
        'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
      ],
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('expected extracted');
    expect(outcome.proposal.services?.length).toBeLessThanOrEqual(8);
    expect(outcome.proposal.services?.[0]).toBe('plumbing');
  });

  test('missing services field → proposal omits it', async () => {
    const llm = stubLLM({
      job_type: 'maintenance_order',
      summary: 'no service tags',
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('expected extracted');
    expect(outcome.proposal.services).toBeUndefined();
  });

  test('empty / non-array services → proposal omits it', async () => {
    for (const bad of [[], null, undefined, 'plumbing', 42, { tag: 'plumbing' }]) {
      const llm = stubLLM({
        job_type: 'maintenance_order',
        summary: 's',
        services: bad as never,
      });
      const extractor = new EmailExtractor();
      const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
      if (outcome.kind !== 'extracted') throw new Error('expected extracted');
      expect(outcome.proposal.services).toBeUndefined();
    }
  });

  test('non-string array entries are filtered out', async () => {
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'mixed garbage',
      services: ['plumbing', null, 42, undefined, 'roofing', { tag: 'x' }] as never,
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('expected extracted');
    expect(outcome.proposal.services).toEqual(['plumbing', 'roofing']);
  });

  test('tag length is bounded', async () => {
    const huge = 'x'.repeat(500);
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'huge tag',
      services: [huge],
    });
    const extractor = new EmailExtractor();
    const outcome = (await extractor.extract(emailItem(MINIMAL_EMAIL), llm))[0];
    if (outcome.kind !== 'extracted') throw new Error('expected extracted');
    expect(outcome.proposal.services?.[0]?.length).toBeLessThanOrEqual(64);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * cell-schema.json canonical contract
 * ────────────────────────────────────────────────────────────────────── */

describe('D-RTC.3: cell-schema.json canonical contract', () => {
  const SCHEMA_PATH = join(__dirname, '..', 'extractor', 'cell-schema.json');
  const raw = readFileSync(SCHEMA_PATH, 'utf8');
  const schema = JSON.parse(raw) as Record<string, unknown>;
  const defs = schema.definitions as Record<string, Record<string, unknown>>;

  test('schema parses as valid JSON', () => {
    expect(schema).toBeDefined();
    expect(typeof schema.$schema).toBe('string');
    expect(typeof schema.title).toBe('string');
  });

  test('defines every required type', () => {
    for (const t of ['Site', 'Customer', 'Job', 'Attachment', 'Contact', 'ContactRole', 'JobIntent', 'ReingestProposal']) {
      expect(defs[t]).toBeDefined();
    }
  });

  test('ContactRole carries the PRD-broader taxonomy', () => {
    const role = defs.ContactRole as { enum?: string[] };
    expect(role.enum).toEqual([
      'site_owner',
      'tenant',
      'property_manager',
      'agent',
      'contractor',
      'witness',
      'unknown',
    ]);
  });

  test('JobIntent matches the email job_type values', () => {
    const intent = defs.JobIntent as { enum?: string[] };
    expect(intent.enum).toEqual([
      'quote_request',
      'work_order',
      'maintenance_order',
      'thread_followup',
      'not_a_job',
    ]);
  });

  test('Site has lookupKey + normalizedAddress + keyNumber + rawAddress', () => {
    const site = defs.Site as { properties?: Record<string, unknown>; required?: string[] };
    expect(site.properties?.lookupKey).toBeDefined();
    expect(site.properties?.normalizedAddress).toBeDefined();
    expect(site.properties?.keyNumber).toBeDefined();
    expect(site.properties?.rawAddress).toBeDefined();
    expect(site.required).toContain('lookupKey');
    expect(site.required).toContain('normalizedAddress');
  });

  test('Customer carries role + linkedSiteId + notes', () => {
    const customer = defs.Customer as { properties?: Record<string, unknown> };
    expect(customer.properties?.name).toBeDefined();
    expect(customer.properties?.role).toBeDefined();
    expect(customer.properties?.linkedSiteId).toBeDefined();
    expect(customer.properties?.notes).toBeDefined();
  });

  test('Job carries services + intent + summary + displayName + rawPdfBlobSha256', () => {
    const job = defs.Job as { properties?: Record<string, unknown>; required?: string[] };
    expect(job.properties?.services).toBeDefined();
    expect(job.properties?.intent).toBeDefined();
    expect(job.properties?.summary).toBeDefined();
    expect(job.properties?.displayName).toBeDefined();
    expect(job.properties?.rawPdfBlobSha256).toBeDefined();
    expect(job.properties?.hasPictures).toBeDefined();
    expect(job.required).toContain('services');
    expect(job.required).toContain('intent');
  });

  test('Attachment carries extractionStatus enum + mirrors hasPictures', () => {
    const att = defs.Attachment as { properties?: Record<string, Record<string, unknown>> };
    const status = att.properties?.extractionStatus as { enum?: string[] };
    expect(status.enum).toEqual([
      'stored_verbatim',
      'image_extracted',
      'pdf_text_extracted',
      'failed',
    ]);
    expect(att.properties?.hasPictures).toBeDefined();
  });

  test('ReingestProposal composes the four cell types', () => {
    const rp = defs.ReingestProposal as { properties?: Record<string, unknown>; required?: string[] };
    expect(rp.properties?.intent).toBeDefined();
    expect(rp.properties?.site).toBeDefined();
    expect(rp.properties?.customers).toBeDefined();
    expect(rp.properties?.job).toBeDefined();
    expect(rp.properties?.attachments).toBeDefined();
    expect(rp.required).toContain('intent');
    expect(rp.required).toContain('customers');
    expect(rp.required).toContain('attachments');
  });

  test('cell IDs are 64-char hex (matches D-RTC.1b proposedCellId)', () => {
    const site = defs.Site as { properties?: Record<string, Record<string, unknown>> };
    // No id field on Site itself (id is derived from lookupKey); but
    // Customer.linkedSiteId references a site id and must use the hex
    // pattern.
    const customer = defs.Customer as { properties?: Record<string, Record<string, unknown>> };
    const linked = customer.properties?.linkedSiteId as { pattern?: string };
    expect(linked.pattern).toBe('^[0-9a-f]{64}$');
    expect(site).toBeDefined();
  });
});

```
