---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/invoice-detail-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.058123+00:00
---

# apps/loom-svelte/tests/invoice-detail-parse.test.ts

```ts
// D-O4.followup-4 — InvoiceDetail.svelte parser tests.
//
// `parseInvoiceTransitionResult` + `actionsForStatus` are exported
// from InvoiceDetail.svelte's `<script lang="ts" module>` block.  We
// re-implement them here to keep the Svelte component the canonical
// source — same posture as quote-detail-parse.test.ts.  Closes the
// brain-side cutover of all 4 oddjobz FSMs.

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

type InvoiceTransitionResult =
  | { kind: "success"; invoice: Invoice }
  | { kind: "already_in_state"; invoice: Invoice }
  | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

type InvoiceAction = { label: string; verb: string };

function invoiceFromBody(row: Record<string, unknown>): Invoice {
  return {
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
  };
}

function parseInvoiceTransitionResult(text: string): InvoiceTransitionResult {
  const trimmed = text.trim();
  if (trimmed.length === 0 || !trimmed.startsWith("{")) {
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      if (parsed.status === "already_in_state" && parsed.invoice) {
        return { kind: "already_in_state", invoice: invoiceFromBody(parsed.invoice) };
      }
      if (typeof parsed.error === "string") {
        return {
          kind: "error",
          error: parsed.error,
          from: String(parsed.from ?? ""),
          to: String(parsed.to ?? ""),
          cap_required: typeof parsed.cap_required === "string"
            ? parsed.cap_required
            : null,
        };
      }
      if (parsed.id && parsed.status) {
        return { kind: "success", invoice: invoiceFromBody(parsed) };
      }
    }
  } catch {
    // fall through
  }
  return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
}

function actionsForStatus(status: string): readonly InvoiceAction[] {
  switch (status) {
    case "draft":
      return [
        { label: "Send", verb: "send invoice" },
        { label: "Cancel", verb: "cancel invoice" },
      ];
    case "sent":
      return [
        { label: "Mark Paid", verb: "mark invoice paid" },
        { label: "Mark Viewed", verb: "mark invoice viewed" },
        { label: "Mark Overdue", verb: "mark invoice overdue" },
        { label: "Cancel", verb: "cancel invoice" },
      ];
    case "viewed":
      return [
        { label: "Mark Paid", verb: "mark invoice paid" },
        { label: "Mark Overdue", verb: "mark invoice overdue" },
        { label: "Cancel", verb: "cancel invoice" },
      ];
    case "partial":
      return [
        { label: "Mark Paid", verb: "mark invoice paid" },
        { label: "Mark Overdue", verb: "mark invoice overdue" },
      ];
    case "overdue":
      return [
        { label: "Mark Paid", verb: "mark invoice paid" },
      ];
    case "paid":
    case "cancelled":
      return [];
    default:
      return [];
  }
}

test("parseInvoiceTransitionResult: success body with bare Invoice shape", () => {
  const text =
    `{"id":"i-1","job_id":"j-1","status":"sent",` +
    `"amount":25000,"amount_paid":0,"external_invoice_id":"","notes":"",` +
    `"sent_at":"2026-05-15T09:00:00Z","viewed_at":"","paid_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-15T09:00:00Z"}`;
  const r = parseInvoiceTransitionResult(text);
  assert.equal(r.kind, "success");
  if (r.kind === "success") {
    assert.equal(r.invoice.status, "sent");
    assert.equal(r.invoice.amount, 25000);
  }
});

test("parseInvoiceTransitionResult: already_in_state body", () => {
  const text =
    `{"status":"already_in_state","invoice":{"id":"i-1","job_id":"j-1",` +
    `"status":"draft","amount":25000,"amount_paid":0,"external_invoice_id":"",` +
    `"notes":"","sent_at":"","viewed_at":"","paid_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}`;
  const r = parseInvoiceTransitionResult(text);
  assert.equal(r.kind, "already_in_state");
  if (r.kind === "already_in_state") {
    assert.equal(r.invoice.status, "draft");
  }
});

test("parseInvoiceTransitionResult: typed not_reachable error body", () => {
  const text =
    `{"error":"not_reachable","from":"draft","to":"paid","cap_required":null}`;
  const r = parseInvoiceTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") {
    assert.equal(r.error, "not_reachable");
    assert.equal(r.from, "draft");
    assert.equal(r.to, "paid");
    assert.equal(r.cap_required, null);
  }
});

test("parseInvoiceTransitionResult: typed wrong_principal error body", () => {
  const text =
    `{"error":"wrong_principal","from":"sent","to":"paid","cap_required":null}`;
  const r = parseInvoiceTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "wrong_principal");
});

test("parseInvoiceTransitionResult: empty / non-JSON returns parse_error", () => {
  let r = parseInvoiceTransitionResult("");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
  r = parseInvoiceTransitionResult("not json");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
});

test("actionsForStatus: draft offers Send + Cancel", () => {
  const a = actionsForStatus("draft");
  assert.equal(a.length, 2);
  assert.equal(a[0]!.label, "Send");
  assert.equal(a[0]!.verb, "send invoice");
  assert.equal(a[1]!.label, "Cancel");
  assert.equal(a[1]!.verb, "cancel invoice");
});

test("actionsForStatus: sent offers Mark Paid / Mark Viewed / Mark Overdue / Cancel", () => {
  const a = actionsForStatus("sent");
  assert.equal(a.length, 4);
  const labels = a.map((x) => x.label);
  assert.deepEqual(labels, ["Mark Paid", "Mark Viewed", "Mark Overdue", "Cancel"]);
});

test("actionsForStatus: terminal states offer no actions", () => {
  assert.equal(actionsForStatus("paid").length, 0);
  assert.equal(actionsForStatus("cancelled").length, 0);
});

```
