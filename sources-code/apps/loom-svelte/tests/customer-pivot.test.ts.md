---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/customer-pivot.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.063570+00:00
---

# apps/loom-svelte/tests/customer-pivot.test.ts

```ts
// D-DOG.1.0c Phase 3 E.3 — customer-pivot helper tests.
//
// Pure projection + path-parser tests for the customer-pivot route.
// The Svelte view itself is exercised manually + via the
// `OddjobzQueryClient.getCustomer` client test below; these cover
// the deterministic shape transforms.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  parseCustomerIdFromPath,
  projectHeader,
  projectJobs,
} from "../src/lib/customer-pivot";
import { OddjobzQueryClient } from "../src/lib/oddjobz-query";
import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
} from "../src/lib/oddjobz-query";

const CELL_A = "a".repeat(64);
const CELL_B = "b".repeat(64);
const CELL_C = "c".repeat(64);

function customer(over: Partial<OddjobzCustomerRow> = {}): OddjobzCustomerRow {
  return {
    id: "uuid-jo-anne",
    display_name: "Jo-Anne Bisman",
    phone: "0411 222 333",
    email: "jo@example.com",
    address: "13 Orealla Cr, Surfers Paradise",
    notes: "",
    created_at: "2026-04-01T00:00:00Z",
    cellId: CELL_A,
    typeHash: "f".repeat(64),
    role: "tenant",
    normalisedPhone: "+61411222333",
    sourceProvenance: null,
    siteRef: null,
    ...over,
  };
}

function job(over: Partial<OddjobzJobRow> = {}): OddjobzJobRow {
  return {
    version: 2,
    id: "job-1",
    customer_name: "Jo-Anne Bisman",
    state: "scheduled",
    scheduled_at: "2026-05-10T09:00:00Z",
    created_at: "2026-04-15T00:00:00Z",
    cellId: "1".repeat(64),
    typeHash: "f".repeat(64),
    workOrderNumber: "WO-1001",
    issuanceDate: "2026-04-15",
    dueDate: "2026-05-12",
    billingParty: null,
    hasPhotos: false,
    photoCount: 0,
    propertyKey: null,
    siteRef: "5".repeat(64),
    customerRefs: [
      { cellId: CELL_A, role: "tenant", primary: true },
    ],
    attachmentRefs: null,
    ...over,
  };
}

// ─── parseCustomerIdFromPath ───────────────────────────────────────────

test("parseCustomerIdFromPath: extracts id from /helm/customers/<id>", () => {
  assert.equal(parseCustomerIdFromPath(`/helm/customers/${CELL_A}`), CELL_A);
});

test("parseCustomerIdFromPath: extracts id from bare /customers/<id>", () => {
  assert.equal(parseCustomerIdFromPath(`/customers/${CELL_A}`), CELL_A);
});

test("parseCustomerIdFromPath: ignores trailing slash + query", () => {
  assert.equal(
    parseCustomerIdFromPath(`/helm/customers/${CELL_A}?refresh=1`),
    CELL_A,
  );
  assert.equal(
    parseCustomerIdFromPath(`/helm/customers/${CELL_A}/`),
    CELL_A,
  );
});

test("parseCustomerIdFromPath: returns null when path doesn't match", () => {
  assert.equal(parseCustomerIdFromPath("/helm/jobs"), null);
  assert.equal(parseCustomerIdFromPath("/customers/"), null);
  assert.equal(parseCustomerIdFromPath(""), null);
});

// ─── projectHeader ─────────────────────────────────────────────────────

test("projectHeader: maps a v2 customer row to the header card", () => {
  const h = projectHeader(customer());
  assert.notEqual(h, null);
  assert.equal(h!.cellId, CELL_A);
  assert.equal(h!.displayName, "Jo-Anne Bisman");
  assert.equal(h!.role, "tenant");
  assert.equal(h!.email, "jo@example.com");
});

test("projectHeader: returns null on null input", () => {
  assert.equal(projectHeader(null), null);
});

test("projectHeader: falls back to v1 id slot when cellId is null", () => {
  const h = projectHeader(customer({ cellId: null, role: null }));
  assert.notEqual(h, null);
  assert.equal(h!.cellId, "v1:uuid-jo-anne");
  assert.equal(h!.role, null);
});

// ─── projectJobs ───────────────────────────────────────────────────────

test("projectJobs: extracts role + primary off the matching customerRef", () => {
  const rows = projectJobs([job()], CELL_A);
  assert.equal(rows.length, 1);
  assert.equal(rows[0]!.role, "tenant");
  assert.equal(rows[0]!.primary, true);
  assert.equal(rows[0]!.workOrderNumber, "WO-1001");
});

test("projectJobs: emits role=null when this customer isn't in the refs", () => {
  // Defensive — brain handler shouldn't return such jobs, but if it
  // did the projection should degrade gracefully rather than throw.
  const rows = projectJobs([
    job({
      customerRefs: [
        { cellId: CELL_B, role: "agent", primary: true },
      ],
    }),
  ], CELL_A);
  assert.equal(rows.length, 1);
  assert.equal(rows[0]!.role, null);
  assert.equal(rows[0]!.primary, false);
});

test("projectJobs: tolerates v2 jobs with null customerRefs", () => {
  const rows = projectJobs([job({ customerRefs: null })], CELL_A);
  assert.equal(rows.length, 1);
  assert.equal(rows[0]!.role, null);
  assert.equal(rows[0]!.primary, false);
});

test("projectJobs: sorts by scheduled_at desc, empty dates last", () => {
  const a = job({ id: "j-a", scheduled_at: "2026-05-01T09:00:00Z" });
  const b = job({ id: "j-b", scheduled_at: "2026-05-10T09:00:00Z" });
  const c = job({ id: "j-c", scheduled_at: "" });
  const rows = projectJobs([a, c, b], CELL_A);
  assert.deepEqual(
    rows.map((r) => r.id),
    ["j-b", "j-a", "j-c"],
  );
});

test("projectJobs: stable id-based tiebreaker for same scheduled_at", () => {
  const a = job({ id: "j-bbb", scheduled_at: "2026-05-10T09:00:00Z" });
  const b = job({ id: "j-aaa", scheduled_at: "2026-05-10T09:00:00Z" });
  const rows = projectJobs([a, b], CELL_A);
  assert.deepEqual(
    rows.map((r) => r.id),
    ["j-aaa", "j-bbb"],
  );
});

test("projectJobs: distinguishes role per-job for the same customer", () => {
  // Same customer, two jobs — tenant on one, agent on the other.
  const j1 = job({
    id: "j-1",
    scheduled_at: "2026-05-01T09:00:00Z",
    customerRefs: [{ cellId: CELL_A, role: "tenant", primary: true }],
  });
  const j2 = job({
    id: "j-2",
    scheduled_at: "2026-05-02T09:00:00Z",
    customerRefs: [
      { cellId: CELL_C, role: "tenant", primary: true },
      { cellId: CELL_A, role: "agent", primary: false },
    ],
  });
  const rows = projectJobs([j1, j2], CELL_A);
  const byId = new Map(rows.map((r) => [r.id, r]));
  assert.equal(byId.get("j-1")!.role, "tenant");
  assert.equal(byId.get("j-1")!.primary, true);
  assert.equal(byId.get("j-2")!.role, "agent");
  assert.equal(byId.get("j-2")!.primary, false);
});

// ─── OddjobzQueryClient.getCustomer ───────────────────────────────────

test("OddjobzQueryClient.getCustomer: passes customerRef as param", async () => {
  let captured: { method: string; params: Record<string, unknown> } | null =
    null;
  const transport = {
    request: async (method: string, params: Record<string, unknown>) => {
      captured = { method, params };
      return { customer: customer() };
    },
  };
  const client = new OddjobzQueryClient(transport);
  const got = await client.getCustomer(CELL_A);
  assert.notEqual(captured, null);
  assert.equal(captured!.method, "cell.get");
  assert.deepEqual(captured!.params, {
    typeHash: "oddjobz.customer.v2",
    cellRef: CELL_A,
  });
  assert.notEqual(got, null);
  assert.equal(got!.cellId, CELL_A);
});

test("OddjobzQueryClient.getCustomer: returns null when brain emits null", async () => {
  const transport = {
    request: async () => ({ customer: null }),
  };
  const client = new OddjobzQueryClient(transport);
  const got = await client.getCustomer(CELL_A);
  assert.equal(got, null);
});

```
