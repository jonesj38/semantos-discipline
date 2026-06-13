---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/site-pivot.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.064150+00:00
---

# apps/loom-svelte/tests/site-pivot.test.ts

```ts
// D-DOG.1.0c Phase 3 E.2 — site-pivot pure-helper tests.
//
// Pure-function coverage of `lib/site-pivot.ts`: address-header build,
// per-site row joiner, and the hash-route parser/builder.  Run via
// `node --test --import tsx`; no Svelte runtime needed.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  buildSiteAddressHeader,
  buildSiteJobRows,
  parseSiteHashRoute,
  siteHashRoute,
} from "../src/lib/site-pivot";
import { customerMap } from "../src/lib/joblist-graph";
import type {
  OddjobzCustomerRow,
  OddjobzJobCustomerRef,
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
    sourceProvenance: null,
    siteRef: "a".repeat(64),
    ...overrides,
  };
}

function jobRow(overrides: Partial<OddjobzJobRow>): OddjobzJobRow {
  return {
    version: 2,
    id: "11111111-1111-1111-1111-111111111111",
    customer_name: "Jo-Anne Bisman",
    state: "scheduled",
    scheduled_at: "2026-05-10T09:00:00Z",
    created_at: "2026-05-04T00:00:00Z",
    cellId: "c".repeat(64),
    typeHash: "f".repeat(64),
    workOrderNumber: "WO-001",
    issuanceDate: "2026-05-04",
    dueDate: "2026-05-12",
    billingParty: { type: "agent", name: "Acme PM" },
    hasPhotos: false,
    photoCount: 0,
    propertyKey: null,
    siteRef: "a".repeat(64),
    customerRefs: [
      { cellId: "b".repeat(64), role: "tenant", primary: true } satisfies OddjobzJobCustomerRef,
    ],
    attachmentRefs: [],
    ...overrides,
  };
}

// ── buildSiteAddressHeader ───────────────────────────────────────────

test("buildSiteAddressHeader: full QLD locality renders 'suburb, STATE postcode'", () => {
  const h = buildSiteAddressHeader(siteRow({}));
  assert.equal(h.fullAddress, "13 Orealla Cr, Surfers Paradise");
  assert.equal(h.localityLine, "Surfers Paradise, QLD 4217");
  assert.equal(h.keyChip, null);
});

test("buildSiteAddressHeader: missing postcode collapses to 'suburb, STATE'", () => {
  const h = buildSiteAddressHeader(siteRow({ postcode: null }));
  assert.equal(h.localityLine, "Surfers Paradise, QLD");
});

test("buildSiteAddressHeader: missing state collapses to 'suburb postcode'", () => {
  const h = buildSiteAddressHeader(siteRow({ state: null }));
  assert.equal(h.localityLine, "Surfers Paradise, 4217");
});

test("buildSiteAddressHeader: only suburb renders bare", () => {
  const h = buildSiteAddressHeader(
    siteRow({ state: null, postcode: null }),
  );
  assert.equal(h.localityLine, "Surfers Paradise");
});

test("buildSiteAddressHeader: empty locality fields render empty line", () => {
  const h = buildSiteAddressHeader(
    siteRow({ suburb: null, state: null, postcode: null }),
  );
  assert.equal(h.localityLine, "");
});

test("buildSiteAddressHeader: whitespace-only locality fields treated as empty", () => {
  const h = buildSiteAddressHeader(
    siteRow({ suburb: "   ", state: " ", postcode: "" }),
  );
  assert.equal(h.localityLine, "");
});

test("buildSiteAddressHeader: keyNumber renders as 'key #N' chip", () => {
  const h = buildSiteAddressHeader(siteRow({ keyNumber: "177" }));
  assert.equal(h.keyChip, "key #177");
});

test("buildSiteAddressHeader: keyNumber that already has '#' isn't double-prefixed", () => {
  const h = buildSiteAddressHeader(siteRow({ keyNumber: "#42A" }));
  assert.equal(h.keyChip, "key #42A");
});

// ── buildSiteJobRows ─────────────────────────────────────────────────

test("buildSiteJobRows: joins customers map + flags hasV2 from cellId", () => {
  const cust = customerMap([customerRow({})]);
  const rows = buildSiteJobRows([jobRow({})], cust);
  assert.equal(rows.length, 1);
  const r = rows[0]!;
  assert.equal(r.id, "11111111-1111-1111-1111-111111111111");
  assert.equal(r.hasV2, true);
  assert.equal(r.dueDate, "2026-05-12");
  assert.notEqual(r.primaryCustomer, null);
  assert.equal(r.primaryCustomer!.displayName, "Jo-Anne Bisman");
  assert.equal(r.primaryCustomer!.role, "tenant");
});

test("buildSiteJobRows: v1 carry-over (cellId null) keeps hasV2 false", () => {
  const cust = customerMap([]);
  const rows = buildSiteJobRows(
    [
      jobRow({
        cellId: null,
        customerRefs: null,
        dueDate: null,
        siteRef: null,
      }),
    ],
    cust,
  );
  assert.equal(rows[0]!.hasV2, false);
  assert.equal(rows[0]!.primaryCustomer, null);
  assert.equal(rows[0]!.dueDate, null);
});

test("buildSiteJobRows: orphaned customerRef resolves to null primary", () => {
  // Customer map empty — primary ref points at a cellId nobody knows.
  const rows = buildSiteJobRows([jobRow({})], customerMap([]));
  assert.equal(rows[0]!.primaryCustomer, null);
});

test("buildSiteJobRows: surfaces hasPhotos + photoCount", () => {
  const rows = buildSiteJobRows(
    [jobRow({ hasPhotos: true, photoCount: 3 })],
    customerMap([customerRow({})]),
  );
  assert.equal(rows[0]!.hasPhotos, true);
  assert.equal(rows[0]!.photoCount, 3);
});

test("buildSiteJobRows: empty input → empty output", () => {
  assert.deepEqual(buildSiteJobRows([], customerMap([])), []);
});

// ── parseSiteHashRoute ───────────────────────────────────────────────

test("parseSiteHashRoute: matches '#/sites/<64-hex>' and returns lowercased ref", () => {
  const ref = "A".repeat(64);
  const got = parseSiteHashRoute(`#/sites/${ref}`);
  assert.equal(got, "a".repeat(64));
});

test("parseSiteHashRoute: tolerates missing leading slash after the hash", () => {
  const ref = "f".repeat(64);
  assert.equal(parseSiteHashRoute(`#sites/${ref}`), ref);
});

test("parseSiteHashRoute: trims trailing slash", () => {
  const ref = "f".repeat(64);
  assert.equal(parseSiteHashRoute(`#/sites/${ref}/`), ref);
});

test("parseSiteHashRoute: drops query string suffix", () => {
  const ref = "f".repeat(64);
  assert.equal(parseSiteHashRoute(`#/sites/${ref}?bearer=xyz`), ref);
});

test("parseSiteHashRoute: returns null for empty / bare hash", () => {
  assert.equal(parseSiteHashRoute(""), null);
  assert.equal(parseSiteHashRoute("#"), null);
});

test("parseSiteHashRoute: returns null when ref isn't 64 hex chars", () => {
  assert.equal(parseSiteHashRoute("#/sites/short"), null);
  assert.equal(parseSiteHashRoute(`#/sites/${"z".repeat(64)}`), null);
});

test("parseSiteHashRoute: returns null for non-sites route", () => {
  assert.equal(parseSiteHashRoute(`#/customers/${"a".repeat(64)}`), null);
  assert.equal(parseSiteHashRoute("#/jobs"), null);
});

// ── siteHashRoute ────────────────────────────────────────────────────

test("siteHashRoute: round-trips through parseSiteHashRoute", () => {
  const ref = "a".repeat(64);
  const url = siteHashRoute(ref);
  assert.equal(url, `#/sites/${ref}`);
  assert.equal(parseSiteHashRoute(url), ref);
});

```
