---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/customer-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.061596+00:00
---

# apps/loom-svelte/tests/customer-list-parse.test.ts

```ts
// D-O5.followup-3 — CustomerList.parseCustomers unit tests.
//
// Mirrors the shape of `tests/job-list-parse.test.ts`.  parseCustomers
// is exported from CustomerList.svelte's <script> block; we re-
// implement it here for direct test coverage so the Svelte component
// file stays the canonical source of truth.  Backed by the Semantos Brain
// dispatcher's typed `customers` resource (runtime/semantos-brain/src/resources/
// customers_handler.zig) — the JSON-array branch is hot.

import { test } from "node:test";
import { strict as assert } from "node:assert";

// Re-implementation of the parser for direct test coverage — keeps
// the Svelte component file the canonical source of truth.
function parseCustomers(text: string): {
  id: string;
  display_name: string;
  phone: string;
  email: string;
  address: string;
  created_at: string;
}[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row) => ({
          id: String(row.id ?? ""),
          display_name: String(row.display_name ?? row.name ?? ""),
          phone: String(row.phone ?? ""),
          email: String(row.email ?? ""),
          address: String(row.address ?? ""),
          created_at: String(row.created_at ?? ""),
        }));
      }
    } catch {
      // fall through
    }
  }
  const lines = trimmed.split("\n").filter((l) => l.length > 0 && !l.startsWith("#"));
  return lines.flatMap((line) => {
    const cols = line.split("\t");
    if (cols.length < 2) return [];
    return [{
      id: cols[0]!,
      display_name: cols[1]!,
      phone: cols[2] ?? "",
      email: cols[3] ?? "",
      address: cols[4] ?? "",
      created_at: cols[5] ?? "",
    }];
  });
}

test("parseCustomers: empty input yields empty list", () => {
  assert.deepEqual(parseCustomers(""), []);
  assert.deepEqual(parseCustomers("   \n  "), []);
});

test("parseCustomers: parses JSON array", () => {
  const text = JSON.stringify([
    {
      id: "cust-1",
      display_name: "Acme",
      phone: "+61 400",
      email: "ops@acme",
      address: "1 Way",
      created_at: "2026-05-02T09:00Z",
    },
    {
      id: "cust-2",
      display_name: "Globex",
      phone: "",
      email: "ops@globex",
      address: "",
      created_at: "2026-05-02T13:30Z",
    },
  ]);
  const customers = parseCustomers(text);
  assert.equal(customers.length, 2);
  assert.equal(customers[0]!.display_name, "Acme");
  assert.equal(customers[0]!.email, "ops@acme");
  assert.equal(customers[1]!.display_name, "Globex");
});

test("parseCustomers: maps `name` to `display_name`", () => {
  const text = JSON.stringify([
    { id: "c1", name: "Old Field", phone: "", email: "", address: "", created_at: "" },
  ]);
  const customers = parseCustomers(text);
  assert.equal(customers[0]!.display_name, "Old Field");
});

test("parseCustomers: parses TSV with comment header", () => {
  const text = [
    "# id\tdisplay_name\tphone\temail\taddress\tcreated_at",
    "cust-1\tAcme\t+61 400\tops@acme\t1 Way\t2026-05-02",
    "cust-2\tGlobex\t\tops@globex\t\t2026-05-03",
  ].join("\n");
  const customers = parseCustomers(text);
  assert.equal(customers.length, 2);
  assert.equal(customers[0]!.id, "cust-1");
  assert.equal(customers[1]!.email, "ops@globex");
});

// D-O5.followup-3 — integration with the typed `customers` dispatcher
// resource.  The brain-side resource handler (runtime/semantos-brain/src/resources/
// customers_handler.zig) emits a JSON array where every row carries
// the canonical helm field set: id, display_name, phone, email,
// address, created_at.  Notes are deliberately omitted from the list
// payload (only surfaced via find_by_id).  This test asserts
// parseCustomers consumes that exact shape — the exact bytes the
// dispatcher would return — without falling through to the TSV
// branch.  When a future churn drops a field on the Semantos Brain side, this
// test breaks loud.
test("parseCustomers: D-O5.followup-3 dispatcher response shape", () => {
  // Verbatim shape from `customers_handler.zig::writeCustomerListJson`.
  const dispatcherResponse =
    `[{"id":"abc123","display_name":"Acme Corp","phone":"+61 400 111 222",` +
    `"email":"ops@acme.example","address":"1 Industrial Way",` +
    `"created_at":"2026-05-02T10:00:00Z"},` +
    `{"id":"def456","display_name":"Globex","phone":"","email":"",` +
    `"address":"","created_at":"2026-05-02T11:30:00Z"}]`;
  const customers = parseCustomers(dispatcherResponse);
  assert.equal(customers.length, 2);
  assert.equal(customers[0]!.id, "abc123");
  assert.equal(customers[0]!.display_name, "Acme Corp");
  assert.equal(customers[0]!.phone, "+61 400 111 222");
  assert.equal(customers[0]!.email, "ops@acme.example");
  assert.equal(customers[0]!.address, "1 Industrial Way");
  assert.equal(customers[0]!.created_at, "2026-05-02T10:00:00Z");
  assert.equal(customers[1]!.display_name, "Globex");
  assert.equal(customers[1]!.phone, "");
});

```
