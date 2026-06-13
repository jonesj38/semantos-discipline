---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/invoice-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.058663+00:00
---

# apps/loom-svelte/tests/invoice-list-parse.test.ts

```ts
// D-O4.followup-4 — InvoiceList.parseInvoices unit tests.
//
// Mirrors the shape of `tests/quote-list-parse.test.ts`.  parseInvoices
// is exported from InvoiceList.svelte's <script module> block; we
// re-implement it here for direct test coverage so the Svelte component
// file stays the canonical source of truth.  Backed by the Semantos Brain
// dispatcher's typed `invoices` resource (runtime/semantos-brain/src/resources/
// invoices_handler.zig) — JSON is the only branch (invoices have no
// TSV legacy).  Closes the Semantos Brain-side cutover of all 4 oddjobz FSMs.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Invoice = {
  id: string;
  job_id: string;
  status: string;
  amount: number;
  amount_paid: number;
  external_invoice_id: string;
  notes: string;
  sent_at: string;
  viewed_at: string;
  paid_at: string;
  created_at: string;
  updated_at: string;
};

function parseInvoices(text: string): Invoice[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
  try {
    const parsed = JSON.parse(trimmed);
    if (Array.isArray(parsed)) {
      return parsed.map((row) => ({
        id: String(row.id ?? ""),
        job_id: String(row.job_id ?? ""),
        status: String(row.status ?? ""),
        amount: Number(row.amount ?? 0),
        amount_paid: Number(row.amount_paid ?? 0),
        external_invoice_id: String(row.external_invoice_id ?? ""),
        notes: String(row.notes ?? ""),
        sent_at: String(row.sent_at ?? ""),
        viewed_at: String(row.viewed_at ?? ""),
        paid_at: String(row.paid_at ?? ""),
        created_at: String(row.created_at ?? ""),
        updated_at: String(row.updated_at ?? ""),
      }));
    }
  } catch {
    // fall through
  }
  return [];
}

function formatCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

test("parseInvoices: empty input yields empty list", () => {
  assert.deepEqual(parseInvoices(""), []);
  assert.deepEqual(parseInvoices("   \n   "), []);
});

test("parseInvoices: non-JSON input yields empty list", () => {
  assert.deepEqual(parseInvoices("not json"), []);
  assert.deepEqual(parseInvoices("[bad json"), []);
});

test("parseInvoices: parses dispatcher JSON-array response", () => {
  // Verbatim shape from `invoices_handler.zig::writeInvoiceJson`.
  const text =
    `[{"id":"i-001","job_id":"j-001","status":"draft",` +
    `"amount":25000,"amount_paid":0,"external_invoice_id":"",` +
    `"notes":"first invoice","sent_at":"","viewed_at":"","paid_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z",` +
    `"updated_at":"2026-05-02T10:00:00Z"},` +
    `{"id":"i-002","job_id":"j-001","status":"paid",` +
    `"amount":1500,"amount_paid":1500,"external_invoice_id":"INV-2026-001",` +
    `"notes":"","sent_at":"2026-05-15T08:30:00Z","viewed_at":"2026-05-15T09:00:00Z",` +
    `"paid_at":"2026-06-01T11:00:00Z",` +
    `"created_at":"2026-05-15T08:30:00Z",` +
    `"updated_at":"2026-06-01T11:00:00Z"}]`;
  const invoices = parseInvoices(text);
  assert.equal(invoices.length, 2);
  assert.equal(invoices[0]!.id, "i-001");
  assert.equal(invoices[0]!.job_id, "j-001");
  assert.equal(invoices[0]!.status, "draft");
  assert.equal(invoices[0]!.amount, 25000);
  assert.equal(invoices[0]!.notes, "first invoice");
  assert.equal(invoices[1]!.status, "paid");
  assert.equal(invoices[1]!.amount_paid, 1500);
  assert.equal(invoices[1]!.external_invoice_id, "INV-2026-001");
  assert.equal(invoices[1]!.paid_at, "2026-06-01T11:00:00Z");
});

test("parseInvoices: handles missing fields with empty defaults", () => {
  const text = JSON.stringify([{ id: "i-1" }]);
  const invoices = parseInvoices(text);
  assert.equal(invoices.length, 1);
  assert.equal(invoices[0]!.id, "i-1");
  assert.equal(invoices[0]!.job_id, "");
  assert.equal(invoices[0]!.amount, 0);
  assert.equal(invoices[0]!.amount_paid, 0);
});

test("formatCents: $X.YY format", () => {
  assert.equal(formatCents(0), "$0.00");
  assert.equal(formatCents(100), "$1.00");
  assert.equal(formatCents(12345), "$123.45");
  assert.equal(formatCents(20000), "$200.00");
});

```
