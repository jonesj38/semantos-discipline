---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/joblist-fetch.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.063845+00:00
---

# apps/loom-svelte/tests/joblist-fetch.test.ts

```ts
// D-DOG.1.0c Phase 3 E.1 — JobList bulk-fetch coordinator tests.
//
// Drives `lib/joblist-fetch.ts::fetchGraphSnapshot` against a stub
// OddjobzQueryClient that counts `cell.query` calls per typeHash.  The N+1
// prevention invariant lives in this layer:
//
//   - `cell.query oddjobz.site.v2` MUST be called exactly once per render
//   - `cell.query oddjobz.customer.v2` MUST be called exactly once per render
//   - per-site `cell.query oddjobz.job.v2` (filter {siteRef}) is bounded by
//     site count, not row count — for 10 v2 jobs at 2 sites we expect 2
//     calls, not 10.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { fetchGraphSnapshot } from "../src/lib/joblist-fetch";
import { customerMap, enrichJobs, jobV2Map, siteMap } from "../src/lib/joblist-graph";
import {
  OddjobzQueryClient,
  type OddjobzCustomerRow,
  type OddjobzJobRow,
  type OddjobzQueryTransport,
  type OddjobzSiteRow,
} from "../src/lib/oddjobz-query";

// ── Stub transport — counts every method call ────────────────────────

class CountingTransport implements OddjobzQueryTransport {
  readonly calls: { method: string; params: Record<string, unknown> }[] = [];
  constructor(
    private readonly responder: (
      method: string,
      params: Record<string, unknown>,
    ) => unknown,
  ) {}
  async request(
    method: string,
    params: Record<string, unknown>,
  ): Promise<unknown> {
    this.calls.push({ method, params });
    return this.responder(method, params);
  }
  countOf(method: string): number {
    return this.calls.filter((c) => c.method === method).length;
  }
  /// Count `cell.query` calls for a given typeHash alias (sites/customers/
  /// jobs all ride the one `cell.query` method, distinguished by typeHash).
  countQuery(typeHash: string): number {
    return this.calls.filter(
      (c) => c.method === "cell.query" && c.params["typeHash"] === typeHash,
    ).length;
  }
  /// Count `cell.get` calls for a given typeHash alias.
  countGet(typeHash: string): number {
    return this.calls.filter(
      (c) => c.method === "cell.get" && c.params["typeHash"] === typeHash,
    ).length;
  }
}

function siteRow(cellId: string, suffix: string): OddjobzSiteRow {
  return {
    cellId,
    typeHash: "f".repeat(64),
    normalisedAddress: `addr ${suffix}`,
    keyNumber: null,
    lookupKey: `addr ${suffix}|`,
    fullAddress: `Address ${suffix}`,
    suburb: null,
    postcode: null,
    state: null,
    createdAt: 1_700_000_000,
  };
}

function customerRow(
  cellId: string,
  name: string,
): OddjobzCustomerRow {
  return {
    id: `00000000-0000-0000-0000-${cellId.slice(0, 12)}`,
    display_name: name,
    phone: "0400000000",
    email: "",
    address: "",
    notes: "",
    created_at: "2026-05-04T00:00:00Z",
    cellId,
    typeHash: "f".repeat(64),
    role: "tenant",
    normalisedPhone: null,
    sourceProvenance: {
      providerId: "gmail",
      providerItemId: "x",
      extractedAt: "2026-05-04T00:00:00Z",
    },
    siteRef: null,
  };
}

function jobRow(
  jobId: string,
  siteRef: string,
  primaryCustomerCellId: string,
): OddjobzJobRow {
  return {
    version: 2,
    id: jobId,
    customer_name: "name",
    state: "scheduled",
    scheduled_at: "",
    created_at: "2026-05-04T00:00:00Z",
    cellId: ("c".repeat(63) + jobId.slice(-1)),
    typeHash: "f".repeat(64),
    workOrderNumber: null,
    issuanceDate: null,
    dueDate: "2026-05-24",
    billingParty: null,
    hasPhotos: false,
    photoCount: null,
    propertyKey: null,
    siteRef,
    customerRefs: [
      { cellId: primaryCustomerCellId, role: "tenant", primary: true },
    ],
    attachmentRefs: [],
  };
}

// ── Tests ────────────────────────────────────────────────────────────

test("fetchGraphSnapshot: list_sites + list_customers each called exactly once", async () => {
  const siteA = "a".repeat(64);
  const siteB = "b".repeat(64);
  const transport = new CountingTransport((method, params) => {
    if (method === "cell.query" && params["typeHash"] === "oddjobz.site.v2") {
      return { sites: [siteRow(siteA, "A"), siteRow(siteB, "B")] };
    }
    if (method === "cell.query" && params["typeHash"] === "oddjobz.customer.v2") {
      return {
        customers: [customerRow("d".repeat(64), "Cust One")],
      };
    }
    if (method === "cell.query" && params["typeHash"] === "oddjobz.job.v2") {
      return { jobs: [] };
    }
    throw new Error(`unexpected method ${method} ${JSON.stringify(params)}`);
  });
  const client = new OddjobzQueryClient(transport);
  await fetchGraphSnapshot(client);
  assert.equal(transport.countQuery("oddjobz.site.v2"), 1);
  assert.equal(transport.countQuery("oddjobz.customer.v2"), 1);
});

test(
  "fetchGraphSnapshot: 10 v2 jobs across 2 sites → 1 list_sites + 1 list_customers + 2 find_jobs_at_site (NOT 10)",
  async () => {
    const siteA = "a".repeat(64);
    const siteB = "b".repeat(64);
    const custA = "d".repeat(64);
    // 10 jobs, 7 at site A and 3 at site B.
    const allJobs: OddjobzJobRow[] = [];
    for (let i = 0; i < 7; i++) {
      allJobs.push(jobRow(`job-A-${i}`, siteA, custA));
    }
    for (let i = 0; i < 3; i++) {
      allJobs.push(jobRow(`job-B-${i}`, siteB, custA));
    }
    const transport = new CountingTransport((method, params) => {
      if (method === "cell.query" && params["typeHash"] === "oddjobz.site.v2") {
        return { sites: [siteRow(siteA, "A"), siteRow(siteB, "B")] };
      }
      if (method === "cell.query" && params["typeHash"] === "oddjobz.customer.v2") {
        return { customers: [customerRow(custA, "Cust A")] };
      }
      if (method === "cell.query" && params["typeHash"] === "oddjobz.job.v2") {
        const ref = (params["filter"] as { siteRef?: string } | undefined)?.siteRef;
        return { jobs: allJobs.filter((j) => j.siteRef === ref) };
      }
      throw new Error(`unexpected method ${method} ${JSON.stringify(params)}`);
    });
    const client = new OddjobzQueryClient(transport);
    const out = await fetchGraphSnapshot(client);

    // The N+1 prevention contract.
    assert.equal(transport.countQuery("oddjobz.site.v2"), 1);
    assert.equal(transport.countQuery("oddjobz.customer.v2"), 1);
    assert.equal(transport.countQuery("oddjobz.job.v2"), 2);
    assert.equal(transport.countGet("oddjobz.customer.v2"), 0); // crucially NOT called per row
    assert.equal(transport.countGet("oddjobz.site.v2"), 0);

    assert.equal(out.snapshot.v2Jobs.length, 10);
    assert.equal(out.snapshot.sites.length, 2);
    assert.equal(out.snapshot.customers.length, 1);
    assert.equal(out.error, null);

    // Sanity: feed into the joiner; all 10 rows render with the
    // primary customer resolved.
    const baseRows = out.snapshot.v2Jobs.map((j) => ({
      id: j.id,
      customer_name: j.customer_name,
      state: j.state,
      scheduled_at: j.scheduled_at,
    }));
    const enriched = enrichJobs(
      baseRows,
      jobV2Map(out.snapshot.v2Jobs),
      siteMap(out.snapshot.sites),
      customerMap(out.snapshot.customers),
    );
    assert.equal(enriched.length, 10);
    for (const r of enriched) {
      assert.equal(r.hasV2, true);
      assert.notEqual(r.primaryCustomer, null);
      assert.equal(r.primaryCustomer!.displayName, "Cust A");
    }
  },
);

test(
  "fetchGraphSnapshot: list_sites failure surfaces error + degrades to empty arrays",
  async () => {
    const transport = new CountingTransport((method, params) => {
      if (
        method === "cell.query" &&
        (params["typeHash"] === "oddjobz.site.v2" ||
          params["typeHash"] === "oddjobz.customer.v2")
      ) {
        throw new Error("oddjobz query error -32603: store_unavailable");
      }
      return {};
    });
    const client = new OddjobzQueryClient(transport);
    const out = await fetchGraphSnapshot(client);
    assert.notEqual(out.error, null);
    assert.match(out.error!, /store_unavailable/);
    assert.equal(out.snapshot.sites.length, 0);
    assert.equal(out.snapshot.customers.length, 0);
    assert.equal(out.snapshot.v2Jobs.length, 0);
  },
);

test(
  "fetchGraphSnapshot: per-site failure absorbed, other sites still return jobs",
  async () => {
    const siteA = "a".repeat(64);
    const siteB = "b".repeat(64);
    const transport = new CountingTransport((method, params) => {
      if (method === "cell.query" && params["typeHash"] === "oddjobz.site.v2") {
        return { sites: [siteRow(siteA, "A"), siteRow(siteB, "B")] };
      }
      if (method === "cell.query" && params["typeHash"] === "oddjobz.customer.v2") {
        return { customers: [] };
      }
      if (method === "cell.query" && params["typeHash"] === "oddjobz.job.v2") {
        const ref = (params["filter"] as { siteRef?: string } | undefined)?.siteRef;
        if (ref === siteA) {
          throw new Error("oddjobz query error -32603: store hiccup");
        }
        return {
          jobs: [jobRow("only-job", siteB, "d".repeat(64))],
        };
      }
      throw new Error(`unexpected method ${method} ${JSON.stringify(params)}`);
    });
    const client = new OddjobzQueryClient(transport);
    const out = await fetchGraphSnapshot(client);
    assert.notEqual(out.error, null);
    assert.equal(out.snapshot.v2Jobs.length, 1);
    assert.equal(out.snapshot.v2Jobs[0]!.id, "only-job");
  },
);

```
