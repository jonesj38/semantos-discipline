---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/job-detail-graph.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.062463+00:00
---

# apps/loom-svelte/tests/job-detail-graph.test.ts

```ts
// D-DOG.1.0c Phase 3 E.4 — pure-helper tests for the graph-aware
// job-detail view (lib/job-detail-graph.ts).
//
// Mirrors the posture of joblist-graph.test.ts: no Svelte, no fetch.
// The component (views/JobDetailV2.svelte) orchestrates the IO; this
// suite pins the join + formatting invariants.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  buildJobDetailView,
  formatAttachmentSummary,
  sortAttachments,
} from "../src/lib/job-detail-graph";
import type {
  OddjobzAttachmentRow,
  OddjobzCustomerRow,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "../src/lib/oddjobz-query";

const HEX_A = "a".repeat(64);
const HEX_B = "b".repeat(64);
const HEX_C = "c".repeat(64);
const HEX_D = "d".repeat(64);

function v2Job(overrides: Partial<OddjobzJobRow> = {}): OddjobzJobRow {
  return {
    version: 2,
    id: "job-uuid-1",
    customer_name: "Jo Bisman",
    state: "scheduled",
    scheduled_at: "2026-05-10T09:00:00Z",
    created_at: "2026-04-30T10:00:00Z",
    cellId: HEX_A,
    typeHash: HEX_A,
    workOrderNumber: "WO-12345",
    issuanceDate: "2026-05-01",
    dueDate: "2026-05-12",
    billingParty: { type: "agent", name: "Bisman Realty" },
    hasPhotos: true,
    photoCount: 4,
    propertyKey: "key #177",
    siteRef: HEX_B,
    customerRefs: [
      { cellId: HEX_C, role: "tenant", primary: true },
      { cellId: HEX_D, role: "agent", primary: false },
    ],
    attachmentRefs: [],
    ...overrides,
  };
}

function v1JobRow(): OddjobzJobRow {
  // Mixed-shape v1 carry-over — brain still emits the typed envelope; v2
  // fields are null.
  return {
    version: 1,
    id: "job-uuid-v1",
    customer_name: "Old Carry-Over",
    state: "lead",
    scheduled_at: "",
    created_at: "2026-01-01T00:00:00Z",
    cellId: null,
    typeHash: null,
    workOrderNumber: null,
    issuanceDate: null,
    dueDate: null,
    billingParty: null,
    hasPhotos: null,
    photoCount: null,
    propertyKey: null,
    siteRef: null,
    customerRefs: null,
    attachmentRefs: null,
  };
}

function siteRow(cellId: string, address: string): OddjobzSiteRow {
  return {
    cellId,
    typeHash: cellId,
    normalisedAddress: address.toLowerCase(),
    keyNumber: null,
    lookupKey: `${address.toLowerCase()}|`,
    fullAddress: address,
    suburb: null,
    postcode: null,
    state: null,
    createdAt: 0,
  };
}

function customerRow(cellId: string, name: string): OddjobzCustomerRow {
  return {
    id: `${cellId}-id`,
    display_name: name,
    phone: "",
    email: "",
    address: "",
    notes: "",
    created_at: "",
    cellId,
    typeHash: cellId,
    role: null,
    normalisedPhone: null,
    sourceProvenance: null,
    siteRef: null,
  };
}

// ─── buildJobDetailView ─────────────────────────────────────────────

test("buildJobDetailView: v2 job projects every v2 field", () => {
  const sites = new Map([[HEX_B, siteRow(HEX_B, "13 Orealla Cr")]]);
  const customers = new Map([
    [HEX_C, customerRow(HEX_C, "Jo Bisman")],
    [HEX_D, customerRow(HEX_D, "Bisman Realty")],
  ]);
  const view = buildJobDetailView(v2Job(), sites, customers);
  assert.equal(view.hasV2, true);
  assert.equal(view.cellId, HEX_A);
  assert.equal(view.workOrderNumber, "WO-12345");
  assert.equal(view.issuanceDate, "2026-05-01");
  assert.equal(view.dueDate, "2026-05-12");
  assert.equal(view.propertyKey, "key #177");
  assert.equal(view.siteRef, HEX_B);
  assert.equal(view.siteAddress, "13 Orealla Cr");
  assert.equal(view.billingParty?.name, "Bisman Realty");
  assert.equal(view.billingParty?.type, "agent");
  assert.equal(view.hasPhotos, true);
  assert.equal(view.photoCount, 4);
});

test("buildJobDetailView: customer links sort primary first then wire order", () => {
  // Wire order has tenant primary then agent secondary; reversing the
  // wire shouldn't change the rendered order — primary still leads.
  const job = v2Job({
    customerRefs: [
      { cellId: HEX_D, role: "agent", primary: false },
      { cellId: HEX_C, role: "tenant", primary: true },
    ],
  });
  const customers = new Map([
    [HEX_C, customerRow(HEX_C, "Jo Bisman")],
    [HEX_D, customerRow(HEX_D, "Bisman Realty")],
  ]);
  const view = buildJobDetailView(job, new Map(), customers);
  assert.equal(view.customers.length, 2);
  assert.equal(view.customers[0]!.primary, true);
  assert.equal(view.customers[0]!.cellId, HEX_C);
  assert.equal(view.customers[0]!.displayName, "Jo Bisman");
  assert.equal(view.customers[1]!.primary, false);
  assert.equal(view.customers[1]!.cellId, HEX_D);
  assert.equal(view.customers[1]!.displayName, "Bisman Realty");
});

test("buildJobDetailView: orphaned customerRef renders displayName=null", () => {
  // Customer ref points at a cellId we don't have in the snapshot —
  // render the cellId-only fallback rather than dropping the row.
  const job = v2Job({
    customerRefs: [{ cellId: "z".repeat(64), role: "tenant", primary: true }],
  });
  const view = buildJobDetailView(job, new Map(), new Map());
  assert.equal(view.customers.length, 1);
  assert.equal(view.customers[0]!.displayName, null);
  assert.equal(view.customers[0]!.cellId, "z".repeat(64));
});

test("buildJobDetailView: orphaned siteRef renders siteAddress=null", () => {
  const view = buildJobDetailView(v2Job(), new Map(), new Map());
  assert.equal(view.siteRef, HEX_B);
  assert.equal(view.siteAddress, null);
});

test("buildJobDetailView: v1 carry-over renders empty v2 panels", () => {
  const view = buildJobDetailView(v1JobRow(), new Map(), new Map());
  assert.equal(view.hasV2, false);
  assert.equal(view.cellId, null);
  assert.equal(view.workOrderNumber, null);
  assert.equal(view.dueDate, null);
  assert.equal(view.siteRef, null);
  assert.equal(view.siteAddress, null);
  assert.equal(view.customers.length, 0);
});

test("buildJobDetailView: v2 with no customerRefs renders an empty list, not throw", () => {
  const view = buildJobDetailView(
    v2Job({ customerRefs: [] }),
    new Map(),
    new Map(),
  );
  assert.equal(view.customers.length, 0);
});

// ─── formatAttachmentSummary ────────────────────────────────────────

function attRow(overrides: Partial<OddjobzAttachmentRow> = {}): OddjobzAttachmentRow {
  return {
    id: "att-1",
    visit_id: "",
    kind: "pdf",
    content_hash: "h".repeat(64),
    content_size: 102400,
    mime_type: "application/pdf",
    captured_at: "2026-05-01T10:00:00Z",
    captured_by_cert_id: "00".repeat(16),
    caption: "",
    created_at: "2026-05-01T10:00:01Z",
    cellId: null,
    typeHash: null,
    jobRef: null,
    sourceBlobKey: null,
    pageCount: null,
    photoCount: null,
    hasPhotos: false,
    ...overrides,
  };
}

test("formatAttachmentSummary: full v2 row renders blobKey + mime + pages + photos", () => {
  const s = formatAttachmentSummary(
    attRow({
      sourceBlobKey: "blob/wo-12345.pdf",
      mime_type: "application/pdf",
      pageCount: 5,
      photoCount: 3,
    }),
  );
  assert.equal(
    s,
    "Attachment: blob/wo-12345.pdf (application/pdf, 5 pages, 3 photos)",
  );
});

test("formatAttachmentSummary: singular page / photo grammar", () => {
  const s = formatAttachmentSummary(
    attRow({
      sourceBlobKey: "blob/wo.pdf",
      mime_type: "application/pdf",
      pageCount: 1,
      photoCount: 1,
    }),
  );
  assert.equal(s, "Attachment: blob/wo.pdf (application/pdf, 1 page, 1 photo)");
});

test("formatAttachmentSummary: zero photos still renders (operator wants the count)", () => {
  const s = formatAttachmentSummary(
    attRow({
      sourceBlobKey: "blob/x.pdf",
      mime_type: "application/pdf",
      pageCount: 2,
      photoCount: 0,
    }),
  );
  assert.equal(s, "Attachment: blob/x.pdf (application/pdf, 2 pages, 0 photos)");
});

test("formatAttachmentSummary: v1 row falls back to id + mime only", () => {
  const s = formatAttachmentSummary(
    attRow({
      id: "att-99",
      sourceBlobKey: null,
      mime_type: "image/heic",
      pageCount: null,
      photoCount: null,
    }),
  );
  assert.equal(s, "Attachment: att-99 (image/heic)");
});

test("formatAttachmentSummary: mime-less row still renders something", () => {
  const s = formatAttachmentSummary(
    attRow({
      id: "att-99",
      mime_type: "",
      sourceBlobKey: null,
      pageCount: null,
      photoCount: null,
    }),
  );
  assert.equal(s, "Attachment: att-99");
});

// ─── sortAttachments ────────────────────────────────────────────────

test("sortAttachments: v2 (pageCount-bearing) rows bubble first; v1 in capture order", () => {
  const v1Photo = attRow({
    id: "att-photo-2",
    sourceBlobKey: null,
    pageCount: null,
    photoCount: null,
    captured_at: "2026-05-15T14:32:00Z",
  });
  const v1Photo1 = attRow({
    id: "att-photo-1",
    sourceBlobKey: null,
    pageCount: null,
    photoCount: null,
    captured_at: "2026-05-15T14:30:00Z",
  });
  const v2Pdf = attRow({
    id: "att-pdf",
    sourceBlobKey: "blob/wo.pdf",
    pageCount: 5,
    photoCount: 3,
    captured_at: "2026-05-01T10:00:00Z",
  });
  const out = sortAttachments([v1Photo, v1Photo1, v2Pdf]);
  assert.equal(out.length, 3);
  assert.equal(out[0]!.id, "att-pdf");
  assert.equal(out[1]!.id, "att-photo-1");
  assert.equal(out[2]!.id, "att-photo-2");
});

test("sortAttachments: input is not mutated", () => {
  const a = attRow({ id: "z", captured_at: "2026-05-15T14:00:00Z" });
  const b = attRow({ id: "a", captured_at: "2026-05-14T14:00:00Z" });
  const input = [a, b];
  const out = sortAttachments(input);
  assert.equal(input[0]!.id, "z");
  assert.equal(out[0]!.id, "a");
});

```
