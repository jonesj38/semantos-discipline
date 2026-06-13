---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/joblist-graph.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.065768+00:00
---

# apps/loom-svelte/tests/joblist-graph.test.ts

```ts
// D-DOG.1.0c Phase 3 E.1 — JobList graph-aware joiner tests.
//
// Pure-function coverage of `lib/joblist-graph.ts`: the row shapes,
// primary-customer picker, due-date formatter, and the v1/v2
// `enrichJobs` joiner.  Run via `node --test --import tsx`; no Svelte
// runtime needed.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  customerMap,
  enrichJobs,
  formatDueDate,
  formatPrimaryCustomer,
  jobV2Map,
  pickPrimaryCustomerRef,
  resolvePrimaryCustomer,
  siteMap,
  type ReplJobRow,
} from "../src/lib/joblist-graph";
import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "../src/lib/oddjobz-query";

// ── Helpers ──────────────────────────────────────────────────────────

function siteRow(overrides: Partial<OddjobzSiteRow>): OddjobzSiteRow {
  return {
    cellId: "a".repeat(64),
    typeHash: "f".repeat(64),
    normalisedAddress: "13 orealla cr surfers paradise",
    keyNumber: null,
    lookupKey: "13 orealla cr surfers paradise|",
    fullAddress: "13 Orealla Cr, Surfers Paradise",
    suburb: "Surfers Paradise",
    postcode: "4217",
    state: "QLD",
    createdAt: 1_700_000_000,
    ...overrides,
  };
}

function customerRow(overrides: Partial<OddjobzCustomerRow>): OddjobzCustomerRow {
  return {
    id: "00000000-0000-0000-0000-000000000001",
    display_name: "Jo-Anne Bisman",
    phone: "0400 111 222",
    email: "jo@example.test",
    address: "",
    notes: "",
    created_at: "2026-05-04T00:00:00Z",
    cellId: "b".repeat(64),
    typeHash: "f".repeat(64),
    role: "tenant",
    normalisedPhone: "+61400111222",
    sourceProvenance: {
      providerId: "gmail",
      providerItemId: "msg-1",
      extractedAt: "2026-05-04T00:00:00Z",
    },
    siteRef: "a".repeat(64),
    ...overrides,
  };
}

function v2JobRow(overrides: Partial<OddjobzJobRow>): OddjobzJobRow {
  return {
    version: 2,
    id: "00000000-0000-0000-0000-00000000abcd",
    customer_name: "Jo-Anne Bisman",
    state: "scheduled",
    scheduled_at: "2026-05-10T09:00:00Z",
    created_at: "2026-05-04T00:00:00Z",
    cellId: "c".repeat(64),
    typeHash: "f".repeat(64),
    workOrderNumber: "07487",
    issuanceDate: "2026-05-01",
    dueDate: "2026-05-24",
    billingParty: { type: "agency", name: "Bricks & Agent" },
    hasPhotos: true,
    photoCount: 4,
    propertyKey: "key #177",
    siteRef: "a".repeat(64),
    customerRefs: [
      { cellId: "b".repeat(64), role: "tenant", primary: true },
      { cellId: "d".repeat(64), role: "agent", primary: false },
    ],
    attachmentRefs: ["e".repeat(64)],
    ...overrides,
  };
}

// ── pickPrimaryCustomerRef ────────────────────────────────────────────

test("pickPrimaryCustomerRef: returns the primary entry", () => {
  const refs = [
    { cellId: "x".repeat(64), role: "agent", primary: false },
    { cellId: "y".repeat(64), role: "tenant", primary: true },
  ];
  const picked = pickPrimaryCustomerRef(refs);
  assert.notEqual(picked, null);
  assert.equal(picked!.cellId, "y".repeat(64));
  assert.equal(picked!.role, "tenant");
});

test("pickPrimaryCustomerRef: null on null input", () => {
  assert.equal(pickPrimaryCustomerRef(null), null);
});

test("pickPrimaryCustomerRef: null when no entry is primary", () => {
  const refs = [
    { cellId: "x".repeat(64), role: "agent", primary: false },
    { cellId: "y".repeat(64), role: "owner", primary: false },
  ];
  assert.equal(pickPrimaryCustomerRef(refs), null);
});

// ── resolvePrimaryCustomer ────────────────────────────────────────────

test("resolvePrimaryCustomer: joins ref to customer row + role", () => {
  const job = v2JobRow({});
  const customers = customerMap([customerRow({})]);
  const pc = resolvePrimaryCustomer(job, customers);
  assert.notEqual(pc, null);
  assert.equal(pc!.displayName, "Jo-Anne Bisman");
  assert.equal(pc!.role, "tenant");
  assert.equal(pc!.phone, "0400 111 222");
  assert.equal(pc!.customerCellId, "b".repeat(64));
  assert.equal(pc!.providerId, "gmail"); // source pill reads this
});

test("resolvePrimaryCustomer: providerId is null when customer has no provenance", () => {
  const job = v2JobRow({});
  const customers = customerMap([customerRow({ sourceProvenance: null })]);
  const pc = resolvePrimaryCustomer(job, customers);
  assert.notEqual(pc, null);
  assert.equal(pc!.providerId, null);
});

test("resolvePrimaryCustomer: null when v2 job is null", () => {
  const customers = customerMap([customerRow({})]);
  assert.equal(resolvePrimaryCustomer(null, customers), null);
});

test("resolvePrimaryCustomer: null on orphaned customerRef", () => {
  const job = v2JobRow({});
  const customers = customerMap([]);
  assert.equal(resolvePrimaryCustomer(job, customers), null);
});

test("resolvePrimaryCustomer: phone is null when v2 carry-over phone is empty", () => {
  const job = v2JobRow({});
  const customers = customerMap([customerRow({ phone: "" })]);
  const pc = resolvePrimaryCustomer(job, customers);
  assert.notEqual(pc, null);
  assert.equal(pc!.phone, null);
});

// ── formatDueDate ────────────────────────────────────────────────────

test("formatDueDate: '—' for null input", () => {
  assert.equal(formatDueDate(null), "—");
});

test("formatDueDate: 'Due today' for today", () => {
  const today = new Date(Date.UTC(2026, 4, 4)); // 2026-05-04
  assert.equal(formatDueDate("2026-05-04", today), "Due today");
});

test("formatDueDate: 'Due tomorrow' for next day", () => {
  const today = new Date(Date.UTC(2026, 4, 4));
  assert.equal(formatDueDate("2026-05-05", today), "Due tomorrow");
});

test("formatDueDate: overdue rendering", () => {
  const today = new Date(Date.UTC(2026, 4, 10));
  assert.equal(formatDueDate("2026-05-09", today), "Overdue 1 day");
  assert.equal(formatDueDate("2026-05-04", today), "Overdue 6 days");
});

test("formatDueDate: same-year future date renders without year", () => {
  const today = new Date(Date.UTC(2026, 2, 1)); // 1 Mar 2026
  assert.equal(formatDueDate("2026-05-24", today), "Due 24 May");
});

test("formatDueDate: cross-year future date includes year", () => {
  const today = new Date(Date.UTC(2026, 11, 1)); // 1 Dec 2026
  assert.equal(formatDueDate("2027-01-15", today), "Due 15 Jan 2027");
});

test("formatDueDate: malformed input falls through to raw string", () => {
  const today = new Date(Date.UTC(2026, 4, 4));
  assert.equal(formatDueDate("not-a-date", today), "not-a-date");
});

// ── formatPrimaryCustomer ────────────────────────────────────────────

test("formatPrimaryCustomer: 'Name (role)' shape", () => {
  const s = formatPrimaryCustomer({
    displayName: "Jo-Anne Bisman",
    role: "tenant",
    phone: null,
    customerCellId: "b".repeat(64),
  });
  assert.equal(s, "Jo-Anne Bisman (tenant)");
});

test("formatPrimaryCustomer: null in → null out (caller falls back)", () => {
  assert.equal(formatPrimaryCustomer(null), null);
});

// ── enrichJobs — v1 / v2 join ─────────────────────────────────────────

test("enrichJobs: v1 row renders without crashing (legacy fallback)", () => {
  const base: ReplJobRow[] = [
    {
      id: "v1-uuid",
      customer_name: "Acme Legacy",
      state: "scheduled",
      scheduled_at: "2026-05-10T09:00:00Z",
    },
  ];
  const out = enrichJobs(base, new Map(), new Map(), new Map());
  assert.equal(out.length, 1);
  const r = out[0]!;
  assert.equal(r.id, "v1-uuid");
  assert.equal(r.hasV2, false);
  assert.equal(r.propertyAddress, null);
  assert.equal(r.propertyKey, null);
  assert.equal(r.primaryCustomer, null);
  assert.equal(r.dueDate, null);
  assert.equal(r.hasPhotos, false);
  assert.equal(r.photoCount, null);
  assert.equal(r.customer_name, "Acme Legacy");
});

test("enrichJobs: v2 row renders all four new fields with correct values", () => {
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "Jo-Anne Bisman",
      state: "scheduled",
      scheduled_at: "2026-05-10T09:00:00Z",
    },
  ];
  const v2 = jobV2Map([v2JobRow({})]);
  const sites = siteMap([siteRow({})]);
  const customers = customerMap([customerRow({})]);
  const out = enrichJobs(base, v2, sites, customers);
  assert.equal(out.length, 1);
  const r = out[0]!;
  assert.equal(r.hasV2, true);
  assert.equal(r.propertyAddress, "13 Orealla Cr, Surfers Paradise");
  assert.equal(r.propertyKey, "key #177");
  assert.equal(r.dueDate, "2026-05-24");
  assert.equal(r.hasPhotos, true);
  assert.equal(r.photoCount, 4);
  assert.notEqual(r.primaryCustomer, null);
  assert.equal(r.primaryCustomer!.displayName, "Jo-Anne Bisman");
  assert.equal(r.primaryCustomer!.role, "tenant");
});

test("enrichJobs: primary customer displays role label e.g. tenant", () => {
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "fallback name",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const v2 = jobV2Map([v2JobRow({})]);
  const sites = siteMap([siteRow({})]);
  const customers = customerMap([customerRow({})]);
  const [r] = enrichJobs(base, v2, sites, customers);
  assert.equal(formatPrimaryCustomer(r!.primaryCustomer), "Jo-Anne Bisman (tenant)");
});

test("enrichJobs: v2 row with hasPhotos:false leaves badge data off", () => {
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "Jo-Anne Bisman",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const v2 = jobV2Map([
    v2JobRow({ hasPhotos: false, photoCount: null }),
  ]);
  const sites = siteMap([siteRow({})]);
  const customers = customerMap([customerRow({})]);
  const [r] = enrichJobs(base, v2, sites, customers);
  assert.equal(r!.hasPhotos, false);
  // Component renders the badge only when hasPhotos === true; the
  // joiner just surfaces the underlying boolean, so the assertion is
  // on the data, not the DOM.
});

test("enrichJobs: row without propertyKey omits the key badge field", () => {
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "Jo-Anne Bisman",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const v2 = jobV2Map([v2JobRow({ propertyKey: null })]);
  const sites = siteMap([siteRow({})]);
  const customers = customerMap([customerRow({})]);
  const [r] = enrichJobs(base, v2, sites, customers);
  assert.equal(r!.propertyKey, null);
});

test("enrichJobs: v2 row with orphaned siteRef renders propertyAddress=null", () => {
  // Job has siteRef but the sites map doesn't know about it.
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "Jo-Anne Bisman",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const v2 = jobV2Map([v2JobRow({ siteRef: "z".repeat(64) })]);
  const sites = siteMap([]); // empty
  const customers = customerMap([customerRow({})]);
  const [r] = enrichJobs(base, v2, sites, customers);
  assert.equal(r!.hasV2, true);
  assert.equal(r!.propertyAddress, null);
});

test("enrichJobs: order of base list is preserved", () => {
  const base: ReplJobRow[] = [
    { id: "a", customer_name: "A", state: "lead", scheduled_at: "" },
    { id: "b", customer_name: "B", state: "lead", scheduled_at: "" },
    { id: "c", customer_name: "C", state: "lead", scheduled_at: "" },
  ];
  const out = enrichJobs(base, new Map(), new Map(), new Map());
  assert.deepEqual(
    out.map((r) => r.id),
    ["a", "b", "c"],
  );
});

// ── D-DOG.1.0c Phase 5 G.2 — legacyUnsigned badge ─────────────────────

test("enrichJobs: v1 row in legacyUnsignedIds set carries the flag", () => {
  const base: ReplJobRow[] = [
    {
      id: "v1-orphan",
      customer_name: "Acme Legacy",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const out = enrichJobs(
    base,
    new Map(),
    new Map(),
    new Map(),
    new Set(["v1-orphan"]),
  );
  assert.equal(out[0]!.legacyUnsigned, true);
  assert.equal(out[0]!.hasV2, false);
});

test("enrichJobs: default empty set leaves legacyUnsigned=false on every row", () => {
  const base: ReplJobRow[] = [
    { id: "x", customer_name: "X", state: "lead", scheduled_at: "" },
  ];
  const out = enrichJobs(base, new Map(), new Map(), new Map());
  assert.equal(out[0]!.legacyUnsigned, false);
});

test("enrichJobs: v2 row id in legacyUnsignedIds is NOT flagged (defensive)", () => {
  // A v2 row that successfully migrated to a graph cell — by Phase 4
  // it's BKDS-signed, so even if the verb's marker file still has a
  // stale entry pointing at the same id, the v2 row should not be
  // painted as unsigned.
  const base: ReplJobRow[] = [
    {
      id: "00000000-0000-0000-0000-00000000abcd",
      customer_name: "Jo-Anne Bisman",
      state: "scheduled",
      scheduled_at: "",
    },
  ];
  const v2 = jobV2Map([v2JobRow({})]);
  const sites = siteMap([siteRow({})]);
  const customers = customerMap([customerRow({})]);
  const out = enrichJobs(
    base,
    v2,
    sites,
    customers,
    new Set(["00000000-0000-0000-0000-00000000abcd"]),
  );
  assert.equal(out[0]!.hasV2, true);
  assert.equal(out[0]!.legacyUnsigned, false);
});

```
