---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/cell-encoder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.140196+00:00
---

# runtime/legacy-ingest/src/__tests__/cell-encoder.test.ts

```ts
/**
 * D-RTC.4 — cell-encoder conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.4.
 *
 * Acceptance gate: every produced EntityEncodeRequest carries the
 * correct SPEC + linearity per substrate_entity.zig. Linearity table
 * mirrors `runtime/semantos-brain/src/substrate_entity.zig::
 * linearityFor` byte-for-byte (any drift causes drift_detector events
 * brain-side once the dispatcher path lands).
 */

import { describe, test, expect } from 'bun:test';
import {
  ENTITY_TAGS,
  SPEC_SITE,
  SPEC_CUSTOMER,
  SPEC_JOB,
  SPEC_ATTACHMENT,
  linearityFor,
  mapLegacyRole,
  encodeSite,
  encodeCustomer,
  encodeJob,
  encodeAttachment,
  type EntityTag,
  type LinearityClass,
} from '../cell-encoder';

const ZERO_OWNER = '00000000000000000000000000000000';

/* ──────────────────────────────────────────────────────────────────────
 * SPEC mirrors match substrate_entity.zig
 * ────────────────────────────────────────────────────────────────────── */

describe('SPECs mirror substrate_entity.zig', () => {
  test('TAG values match the Zig constants', () => {
    expect(ENTITY_TAGS.TAG_CUSTOMER).toBe(0x01);
    expect(ENTITY_TAGS.TAG_VISIT).toBe(0x02);
    expect(ENTITY_TAGS.TAG_QUOTE).toBe(0x03);
    expect(ENTITY_TAGS.TAG_INVOICE).toBe(0x04);
    expect(ENTITY_TAGS.TAG_ATTACHMENT).toBe(0x05);
    expect(ENTITY_TAGS.TAG_JOB).toBe(0x06);
    expect(ENTITY_TAGS.TAG_SITE).toBe(0x07);
    expect(ENTITY_TAGS.TAG_LEAD).toBe(0x08);
  });

  test('SPEC_SITE matches substrate_entity.zig SPEC_SITE', () => {
    expect(SPEC_SITE.tag).toBe(ENTITY_TAGS.TAG_SITE);
    expect(SPEC_SITE.typePath).toBe('oddjobz.site');
    expect(SPEC_SITE.howSlug).toBe('locate');
    expect(SPEC_SITE.instPath).toBe('inst.location.work-site.v2');
    expect(SPEC_SITE.domainFlag).toBe(0x0001010E);
  });

  test('SPEC_CUSTOMER matches substrate_entity.zig SPEC_CUSTOMER', () => {
    expect(SPEC_CUSTOMER.tag).toBe(ENTITY_TAGS.TAG_CUSTOMER);
    expect(SPEC_CUSTOMER.typePath).toBe('oddjobz.customer');
    expect(SPEC_CUSTOMER.howSlug).toBe('identify');
    expect(SPEC_CUSTOMER.instPath).toBe('inst.identity.customer-record.v2');
    expect(SPEC_CUSTOMER.domainFlag).toBe(0x00010108);
  });

  test('SPEC_JOB matches substrate_entity.zig SPEC_JOB', () => {
    expect(SPEC_JOB.tag).toBe(ENTITY_TAGS.TAG_JOB);
    expect(SPEC_JOB.typePath).toBe('oddjobz.job');
    expect(SPEC_JOB.howSlug).toBe('worktrack');
    expect(SPEC_JOB.instPath).toBe('inst.work.job-record.v2');
    expect(SPEC_JOB.domainFlag).toBe(0x00010107);
  });

  test('SPEC_ATTACHMENT matches substrate_entity.zig SPEC_ATTACHMENT', () => {
    expect(SPEC_ATTACHMENT.tag).toBe(ENTITY_TAGS.TAG_ATTACHMENT);
    expect(SPEC_ATTACHMENT.typePath).toBe('oddjobz.attachment');
    expect(SPEC_ATTACHMENT.howSlug).toBe('capture');
    expect(SPEC_ATTACHMENT.instPath).toBe('inst.evidence.site-artifact.v2');
    expect(SPEC_ATTACHMENT.domainFlag).toBe(0x0001010D);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * linearityFor — mirrors substrate_entity.zig switch byte-for-byte
 * ────────────────────────────────────────────────────────────────────── */

describe('linearityFor mirrors substrate_entity.zig::linearityFor', () => {
  // Every row below should be re-checked against substrate_entity.zig
  // lines 196-228 if either changes. drift_detector.zig will catch
  // any production drift, but tests catch it earlier.
  const cases: Array<[EntityTag, string, LinearityClass]> = [
    // TAG_LEAD
    [ENTITY_TAGS.TAG_LEAD, 'pending', 'affine'],
    [ENTITY_TAGS.TAG_LEAD, 'ratified', 'relevant'],
    [ENTITY_TAGS.TAG_LEAD, 'rejected', 'relevant'],
    // TAG_JOB
    [ENTITY_TAGS.TAG_JOB, 'lead', 'affine'],
    [ENTITY_TAGS.TAG_JOB, 'quoted', 'linear'],
    [ENTITY_TAGS.TAG_JOB, 'scheduled', 'linear'],
    [ENTITY_TAGS.TAG_JOB, 'in_progress', 'linear'],
    [ENTITY_TAGS.TAG_JOB, 'invoiced', 'linear'],
    [ENTITY_TAGS.TAG_JOB, 'paid', 'linear'],
    [ENTITY_TAGS.TAG_JOB, 'completed', 'relevant'],
    [ENTITY_TAGS.TAG_JOB, 'closed', 'relevant'],
    // TAG_QUOTE
    [ENTITY_TAGS.TAG_QUOTE, 'open', 'linear'],
    [ENTITY_TAGS.TAG_QUOTE, 'accepted', 'relevant'],
    [ENTITY_TAGS.TAG_QUOTE, 'declined', 'relevant'],
    [ENTITY_TAGS.TAG_QUOTE, 'expired', 'relevant'],
    // TAG_INVOICE
    [ENTITY_TAGS.TAG_INVOICE, 'issued', 'linear'],
    [ENTITY_TAGS.TAG_INVOICE, 'partial', 'linear'],
    [ENTITY_TAGS.TAG_INVOICE, 'paid', 'relevant'],
    [ENTITY_TAGS.TAG_INVOICE, 'void', 'relevant'],
    // TAG_VISIT
    [ENTITY_TAGS.TAG_VISIT, 'scheduled', 'linear'],
    [ENTITY_TAGS.TAG_VISIT, 'completed', 'relevant'],
    [ENTITY_TAGS.TAG_VISIT, 'no_show', 'relevant'],
    // TAG_CUSTOMER, TAG_SITE
    [ENTITY_TAGS.TAG_CUSTOMER, 'active', 'affine'],
    [ENTITY_TAGS.TAG_CUSTOMER, 'archived', 'relevant'],
    [ENTITY_TAGS.TAG_SITE, 'active', 'affine'],
    [ENTITY_TAGS.TAG_SITE, 'archived', 'relevant'],
    // TAG_ATTACHMENT — always relevant (immutable)
    [ENTITY_TAGS.TAG_ATTACHMENT, 'captured', 'relevant'],
    [ENTITY_TAGS.TAG_ATTACHMENT, '', 'relevant'],
  ];

  for (const [tag, state, expected] of cases) {
    test(`tag=0x${tag.toString(16).padStart(2, '0')} state="${state}" → ${expected}`, () => {
      expect(linearityFor(tag, state)).toBe(expected);
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * Per-cell-type encoders
 * ────────────────────────────────────────────────────────────────────── */

describe('encodeSite', () => {
  test('produces SPEC_SITE + linearity affine for active', () => {
    const req = encodeSite(
      {
        lookup_key: '10 list lane brisbane qld 4000|',
        normalized_address: '10 list lane brisbane qld 4000',
        key_number: null,
        raw_address: '10 List Lane, Brisbane QLD 4000',
        state: 'active',
      },
      ZERO_OWNER,
    );
    expect(req.spec).toBe(SPEC_SITE);
    expect(req.linearity).toBe('affine');
    expect(req.ownerIdHex).toBe(ZERO_OWNER);
    const parsed = JSON.parse(req.payloadJson);
    expect(parsed.lookup_key).toBe('10 list lane brisbane qld 4000|');
    expect(parsed.normalized_address).toBe('10 list lane brisbane qld 4000');
  });

  test('archived site → linearity relevant', () => {
    const req = encodeSite(
      {
        lookup_key: 'x|',
        normalized_address: 'x',
        key_number: null,
        raw_address: 'x',
        state: 'archived',
      },
      ZERO_OWNER,
    );
    expect(req.linearity).toBe('relevant');
  });
});

describe('encodeCustomer', () => {
  test('produces SPEC_CUSTOMER + carries broader role enum', () => {
    const req = encodeCustomer(
      {
        name: 'Anna Smith',
        email: 'anna@cleverproperty.com.au',
        phone: null,
        role: 'property_manager',
        linked_site_id: 'a'.repeat(64),
        notes: null,
        state: 'active',
      },
      ZERO_OWNER,
    );
    expect(req.spec).toBe(SPEC_CUSTOMER);
    expect(req.linearity).toBe('affine');
    const parsed = JSON.parse(req.payloadJson);
    expect(parsed.role).toBe('property_manager');
    expect(parsed.linked_site_id).toHaveLength(64);
  });
});

describe('encodeJob', () => {
  test('produces SPEC_JOB + linearity linear for in-progress', () => {
    const req = encodeJob(
      {
        site_ref: 'a'.repeat(64),
        customer_refs: [{ cell_id: 'b'.repeat(64), role: 'tenant', primary: true }],
        work_order_number: 'WO-12345',
        services: ['plumbing', 'leak-investigation'],
        issuance_date: '2026-05-16',
        due_date: '2026-05-23',
        intent: 'maintenance_order',
        summary: 'Leaking tap at unit 4.',
        display_name: 'Jo-Anne Bisman (tenant)',
        raw_pdf_blob_sha256: 'c'.repeat(64),
        has_pictures: true,
        picture_count: 2,
        state: 'scheduled',
      },
      ZERO_OWNER,
    );
    expect(req.spec).toBe(SPEC_JOB);
    expect(req.linearity).toBe('linear');
    const parsed = JSON.parse(req.payloadJson);
    expect(parsed.services).toEqual(['plumbing', 'leak-investigation']);
    expect(parsed.customer_refs[0].role).toBe('tenant');
  });

  test('completed job → linearity relevant', () => {
    const req = encodeJob(
      {
        site_ref: null,
        customer_refs: [],
        work_order_number: null,
        services: [],
        issuance_date: null,
        due_date: null,
        intent: 'work_order',
        summary: 's',
        display_name: 'd',
        raw_pdf_blob_sha256: null,
        has_pictures: false,
        picture_count: null,
        state: 'completed',
      },
      ZERO_OWNER,
    );
    expect(req.linearity).toBe('relevant');
  });

  test('lead-state job → linearity affine', () => {
    const req = encodeJob(
      {
        site_ref: null,
        customer_refs: [],
        work_order_number: null,
        services: [],
        issuance_date: null,
        due_date: null,
        intent: 'quote_request',
        summary: 's',
        display_name: 'd',
        raw_pdf_blob_sha256: null,
        has_pictures: false,
        picture_count: null,
        state: 'lead',
      },
      ZERO_OWNER,
    );
    expect(req.linearity).toBe('affine');
  });
});

describe('encodeAttachment', () => {
  test('produces SPEC_ATTACHMENT + always linearity relevant', () => {
    const req = encodeAttachment(
      {
        mime_type: 'application/pdf',
        filename: 'work-order.pdf',
        blob_sha256: 'a'.repeat(64),
        parent_cell_id: 'b'.repeat(64),
        extraction_status: 'stored_verbatim',
        has_pictures: false,
        state: 'captured',
      },
      ZERO_OWNER,
    );
    expect(req.spec).toBe(SPEC_ATTACHMENT);
    expect(req.linearity).toBe('relevant');
    const parsed = JSON.parse(req.payloadJson);
    expect(parsed.mime_type).toBe('application/pdf');
    expect(parsed.extraction_status).toBe('stored_verbatim');
  });

  test('failed-extraction attachment still emits cell with has_pictures', () => {
    const req = encodeAttachment(
      {
        mime_type: 'image/jpeg',
        filename: 'photo.jpg',
        blob_sha256: 'c'.repeat(64),
        parent_cell_id: 'd'.repeat(64),
        extraction_status: 'failed',
        has_pictures: true,
        state: 'captured',
      },
      ZERO_OWNER,
    );
    const parsed = JSON.parse(req.payloadJson);
    expect(parsed.extraction_status).toBe('failed');
    expect(parsed.has_pictures).toBe(true);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Legacy-role bridge
 * ────────────────────────────────────────────────────────────────────── */

describe('mapLegacyRole', () => {
  test('tenant → tenant', () => {
    expect(mapLegacyRole('tenant')).toBe('tenant');
  });
  test('agent → agent', () => {
    expect(mapLegacyRole('agent')).toBe('agent');
  });
  test('owner → site_owner (PRD broadening)', () => {
    expect(mapLegacyRole('owner')).toBe('site_owner');
  });
  test('pm → property_manager (PRD broadening)', () => {
    expect(mapLegacyRole('pm')).toBe('property_manager');
  });
  test('other → unknown (PRD broadening)', () => {
    expect(mapLegacyRole('other')).toBe('unknown');
  });
});

```
