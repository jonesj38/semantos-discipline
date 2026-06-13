---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/reingest-worker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.138882+00:00
---

# runtime/legacy-ingest/src/__tests__/reingest-worker.test.ts

```ts
/**
 * D-RTC.6 — reingest-worker conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.6.
 *
 * Acceptance gate: per-proposal compose pipeline emits the right
 * SEQUENCE of EntityEncodeRequests (site → customers → job →
 * attachments), with idempotent attachment-blob writes, parent
 * has_pictures correctly propagated to the job cell, and the legacy-
 * role enum mapped to the broader PRD taxonomy on the customer cells.
 */

import { describe, test, expect } from 'bun:test';
import { createHash, randomBytes } from 'node:crypto';
import {
  reingestProposal,
  type EncodeDispatcher,
  type ReingestReceipt,
} from '../reingest-worker';
import {
  InMemoryAttachmentBlobStore,
} from '../attachment-pipeline';
import {
  ENTITY_TAGS,
  type EntityEncodeRequest,
} from '../cell-encoder';
import type { SitesView } from '../site-dedupe';
import type { Proposal } from '../extractor/types';
import type { EmailMimePart } from '../extractor/attachment';
import type { SIRProgram } from '@semantos/semantos-sir';

const ZERO_OWNER = '00000000000000000000000000000000';

/** Deterministic dispatcher that mints sequential synthetic cell ids. */
function recordingDispatcher(): EncodeDispatcher & {
  calls: EntityEncodeRequest[];
  byTag: Record<number, EntityEncodeRequest[]>;
} {
  const calls: EntityEncodeRequest[] = [];
  const byTag: Record<number, EntityEncodeRequest[]> = {};
  let counter = 0;
  return {
    calls,
    byTag,
    async dispatch(req) {
      calls.push(req);
      (byTag[req.spec.tag] ??= []).push(req);
      counter += 1;
      // 64-char hex synthetic id; first byte encodes the tag for easy assertion.
      return req.spec.tag.toString(16).padStart(2, '0') + counter.toString(16).padStart(62, '0');
    },
  };
}

function emptySitesView(): SitesView {
  return {
    async findByLookupKey() {
      return null;
    },
  };
}

function viewWithSeed(seed: Record<string, string>): SitesView {
  return {
    async findByLookupKey(k) {
      return seed[k] ?? null;
    },
  };
}

const NOOP_SIR: SIRProgram = {} as unknown as SIRProgram;

function baseProposal(overrides: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: 'prop-1',
    confidence: 0.9,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'msg-1',
      fetchedAt: 1700000000000,
      extractorVersion: 'email-rfc822-v0.6',
      promptHash: 'h',
    },
    extractedAt: 1700000001000,
    program: NOOP_SIR,
    propertyAddress: '10 List Lane, Brisbane QLD 4000',
    propertyKey: null,
    primaryContact: {
      name: 'Jo Smith',
      role: 'tenant',
      phone: '0400000000',
      email: 'jo@gmail.com',
    },
    secondaryContacts: [
      { name: 'Mark Davies', role: 'pm', phone: null, email: 'mark@harcourts.com.au' },
    ],
    services: ['plumbing', 'leak-investigation'],
    summary: 'Leaking tap in unit 4',
    pointOfContact: 'Jo Smith (tenant)',
    workOrderNumber: 'WO-12345',
    issuanceDate: '2026-05-16',
    dueDate: '2026-05-23',
    ...overrides,
  };
}

function makePdf(bytes: Uint8Array): EmailMimePart {
  return { contentType: 'application/pdf', bytes, filename: 'wo.pdf', kind: 'pdf' };
}
function makeImage(bytes: Uint8Array): EmailMimePart {
  return { contentType: 'image/jpeg', bytes, filename: 'photo.jpg', kind: 'image' };
}

/* ──────────────────────────────────────────────────────────────────────
 * Happy path: full graph mint
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: full happy path', () => {
  test('emits site → 2 customers → job, in dispatch order', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });

    expect('skipped' in out).toBe(false);
    const r = out as ReingestReceipt;

    // 4 dispatches: 1 site, 2 customers, 1 job.
    expect(dispatcher.calls).toHaveLength(4);
    expect(dispatcher.calls[0]!.spec.tag).toBe(ENTITY_TAGS.TAG_SITE);
    expect(dispatcher.calls[1]!.spec.tag).toBe(ENTITY_TAGS.TAG_CUSTOMER);
    expect(dispatcher.calls[2]!.spec.tag).toBe(ENTITY_TAGS.TAG_CUSTOMER);
    expect(dispatcher.calls[3]!.spec.tag).toBe(ENTITY_TAGS.TAG_JOB);

    expect(r.siteDisposition).toBe('minted');
    expect(r.siteCellId).not.toBeNull();
    expect(r.customerCellIds).toHaveLength(2);
    expect(r.attachmentCellIds).toHaveLength(0);
  });

  test('legacy role enum maps to PRD-broader taxonomy on customer cells', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const customers = dispatcher.byTag[ENTITY_TAGS.TAG_CUSTOMER]!;
    const primary = JSON.parse(customers[0]!.payloadJson);
    const secondary = JSON.parse(customers[1]!.payloadJson);
    expect(primary.role).toBe('tenant'); // tenant → tenant
    expect(secondary.role).toBe('property_manager'); // pm → property_manager
  });

  test('job cell links to minted site + customers + carries services', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    const jobReq = dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!;
    const jobPayload = JSON.parse(jobReq.payloadJson);
    expect(jobPayload.site_ref).toBe(r.siteCellId);
    expect(jobPayload.customer_refs).toHaveLength(2);
    expect(jobPayload.customer_refs[0].cell_id).toBe(r.customerCellIds[0]);
    expect(jobPayload.customer_refs[0].primary).toBe(true);
    expect(jobPayload.customer_refs[1].primary).toBe(false);
    expect(jobPayload.services).toEqual(['plumbing', 'leak-investigation']);
    expect(jobPayload.intent).toBe('work_order'); // proposal has workOrderNumber
    expect(jobPayload.work_order_number).toBe('WO-12345');
    expect(jobPayload.state).toBe('lead');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Site dedupe match path
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: site dedupe match', () => {
  test('existing site is reused, NOT re-minted', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const existingSite = 'f'.repeat(64);
    const view = viewWithSeed({
      '10 list lane brisbane qld 4000|': existingSite,
    });
    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: view,
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    expect(r.siteDisposition).toBe('matched');
    expect(r.siteCellId).toBe(existingSite);
    // No site dispatch — first call is a customer.
    expect(dispatcher.calls[0]!.spec.tag).toBe(ENTITY_TAGS.TAG_CUSTOMER);
    expect(dispatcher.byTag[ENTITY_TAGS.TAG_SITE]).toBeUndefined();
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * No-address proposal → site absent, job stands alone
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: no extractable address', () => {
  test('site absent when both propertyAddress + pointOfContact missing', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal({
        propertyAddress: null,
        pointOfContact: undefined,
        primaryContact: null,
        secondaryContacts: undefined,
      }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    expect(r.siteDisposition).toBe('absent');
    expect(r.siteCellId).toBeNull();
    // Job still mints — operator can backfill site at ratification.
    const jobs = dispatcher.byTag[ENTITY_TAGS.TAG_JOB]!;
    expect(jobs).toHaveLength(1);
    const payload = JSON.parse(jobs[0]!.payloadJson);
    // slimJobJson omits null/false fields — absence = the documented
    // default (null site_ref). The cell-schema.json "optional"
    // semantics: readers treat a missing site_ref as "no site".
    expect(payload.site_ref ?? null).toBeNull();
  });

  test('PO-box-only address (rejected by normalizer) → site absent', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal({
        propertyAddress: 'PO Box 99, Brisbane QLD 4000',
        pointOfContact: undefined,
      }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    expect(r.siteDisposition).toBe('absent');
    expect(dispatcher.byTag[ENTITY_TAGS.TAG_SITE]).toBeUndefined();
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Attachments + parent has_pictures propagation
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: attachments', () => {
  test('PDF + image: parent job carries has_pictures + raw_pdf_blob_sha256', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfBytes = randomBytes(512);
    const imgBytes = randomBytes(256);
    const pdfSha = createHash('sha256').update(pdfBytes).digest('hex');

    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [makePdf(pdfBytes), makeImage(imgBytes)],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    expect(r.attachmentCellIds).toHaveLength(2);
    expect(r.parentSummary.hasPictures).toBe(true);
    expect(r.parentSummary.pictureCount).toBe(1);
    expect(r.parentSummary.primaryPdfSha256).toBe(pdfSha);

    const jobReq = dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!;
    const job = JSON.parse(jobReq.payloadJson);
    expect(job.has_pictures).toBe(true);
    expect(job.picture_count).toBe(1);
    expect(job.raw_pdf_blob_sha256).toBe(pdfSha);

    // Attachment cells reference the real job id, not the placeholder.
    const atts = dispatcher.byTag[ENTITY_TAGS.TAG_ATTACHMENT]!;
    for (const a of atts) {
      const p = JSON.parse(a.payloadJson);
      expect(p.parent_cell_id).toBe(r.jobCellId);
    }
  });

  test('no attachments: parent.has_pictures false, picture_count null', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const job = JSON.parse(dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!.payloadJson);
    // slimJobJson omits false/null fields to stay under the 768-byte
    // PAYLOAD_BUDGET — absence carries the documented default.
    expect(job.has_pictures ?? false).toBe(false);
    expect(job.picture_count ?? null).toBeNull();
    expect(job.raw_pdf_blob_sha256 ?? null).toBeNull();
  });

  test('attachment blob store: same bytes dedupe across the two pipeline runs', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfBytes = randomBytes(512);
    await reingestProposal({
      proposal: baseProposal(),
      attachments: [makePdf(pdfBytes)],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    // The worker runs the attachment pipeline TWICE (probe for parent
    // summary, then real). Content-addressing means only one blob.
    expect(blobStore.size()).toBe(1);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Skip semantics
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: skips', () => {
  test('proposal with empty summary is skipped', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal({ summary: '' }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    expect('skipped' in out && out.skipped).toBe(true);
    if ('skipped' in out) {
      expect(out.reason).toBe('no summary');
    }
    expect(dispatcher.calls).toHaveLength(0);
  });

  test('proposal with whitespace-only summary is skipped', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal({ summary: '   \n  ' }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    expect('skipped' in out && out.skipped).toBe(true);
    expect(dispatcher.calls).toHaveLength(0);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Intent derivation
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal: intent derivation', () => {
  test('proposal with workOrderNumber → intent=work_order', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    await reingestProposal({
      proposal: baseProposal({ workOrderNumber: 'WO-99' }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const job = JSON.parse(dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!.payloadJson);
    expect(job.intent).toBe('work_order');
  });

  test('proposal without workOrderNumber → intent=maintenance_order', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    await reingestProposal({
      proposal: baseProposal({ workOrderNumber: null }),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const job = JSON.parse(dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!.payloadJson);
    expect(job.intent).toBe('maintenance_order');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Customer dedupe (handoff §6.2) — resolve-or-create by natural key
 * ────────────────────────────────────────────────────────────────────── */

import type { CustomersDedupeView } from '../customer-dedupe';

describe('reingestProposal: customer dedupe (§6.2)', () => {
  test('no customersDedupeView → both contacts mint (legacy behaviour)', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;
    expect(dispatcher.byTag[ENTITY_TAGS.TAG_CUSTOMER]).toHaveLength(2);
    expect(r.customerDispositions).toEqual(['minted', 'minted']);
    expect(r.customerLookupKeys).toEqual(['', '']); // no keys without a view
  });

  test('seeded view reuses the existing agency contact, mints only the tenant', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const existingPm = 'a'.repeat(64);
    // The secondary contact is Mark Davies (pm → property_manager,
    // mark@harcourts.com.au) → person:mark@harcourts.com.au.
    const view: CustomersDedupeView = {
      async findCustomerByLookupKey(k) {
        return k === 'person:mark@harcourts.com.au' ? existingPm : null;
      },
    };
    const out = await reingestProposal({
      proposal: baseProposal(),
      attachments: [],
      sitesView: emptySitesView(),
      customersDedupeView: view,
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    });
    const r = out as ReingestReceipt;

    // Only the tenant gets a customer dispatch — the pm is reused.
    expect(dispatcher.byTag[ENTITY_TAGS.TAG_CUSTOMER]).toHaveLength(1);
    expect(r.customerCellIds).toHaveLength(2);
    expect(r.customerDispositions).toEqual(['minted', 'matched']);
    expect(r.customerCellIds[1]).toBe(existingPm); // reused
    expect(r.customerLookupKeys[1]).toBe('person:mark@harcourts.com.au');
    expect(r.customerLookupKeys[0]).toMatch(/^tenant:jo smith\|/);

    // The job's customer_ref for the pm points at the REUSED cell.
    const jobPayload = JSON.parse(dispatcher.byTag[ENTITY_TAGS.TAG_JOB]![0]!.payloadJson);
    expect(jobPayload.customer_refs[1].cell_id).toBe(existingPm);
  });
});

```
