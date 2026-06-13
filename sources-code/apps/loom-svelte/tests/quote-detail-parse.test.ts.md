---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/quote-detail-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.067208+00:00
---

# apps/loom-svelte/tests/quote-detail-parse.test.ts

```ts
// D-O4.followup-3 — QuoteDetail.svelte parser tests.
//
// `parseQuoteTransitionResult` + `actionsForStatus` are exported from
// QuoteDetail.svelte's `<script lang="ts" module>` block.  We re-
// implement them here to keep the Svelte component the canonical
// source — same posture as visit-detail-parse.test.ts.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Quote = {
  id: string;
  job_id: string;
  status: string;
  cost_min: number;
  cost_max: number;
  notes: string;
  accepted_at: string;
  rejected_at: string;
  created_at: string;
  updated_at: string;
};

type QuoteTransitionResult =
  | { kind: "success"; quote: Quote }
  | { kind: "already_in_state"; quote: Quote }
  | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

type QuoteAction = { label: string; verb: string };

function quoteFromBody(row: Record<string, unknown>): Quote {
  return {
    id: String(row.id ?? ""),
    job_id: String(row.job_id ?? ""),
    status: String(row.status ?? ""),
    cost_min: Number(row.cost_min ?? 0),
    cost_max: Number(row.cost_max ?? 0),
    notes: String(row.notes ?? ""),
    accepted_at: String(row.accepted_at ?? ""),
    rejected_at: String(row.rejected_at ?? ""),
    created_at: String(row.created_at ?? ""),
    updated_at: String(row.updated_at ?? ""),
  };
}

function parseQuoteTransitionResult(text: string): QuoteTransitionResult {
  const trimmed = text.trim();
  if (trimmed.length === 0 || !trimmed.startsWith("{")) {
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      if (parsed.status === "already_in_state" && parsed.quote) {
        return { kind: "already_in_state", quote: quoteFromBody(parsed.quote) };
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
        return { kind: "success", quote: quoteFromBody(parsed) };
      }
    }
  } catch {
    // fall through
  }
  return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
}

function actionsForStatus(status: string): readonly QuoteAction[] {
  switch (status) {
    case "draft":
      return [
        { label: "Present", verb: "present quote" },
        { label: "Supersede", verb: "supersede quote" },
      ];
    case "presented":
      return [
        { label: "Accept", verb: "accept quote" },
        { label: "Decline", verb: "decline quote" },
        { label: "Expire", verb: "expire quote" },
        { label: "Supersede", verb: "supersede quote" },
      ];
    case "accepted":
    case "rejected":
    case "expired":
    case "superseded":
      return [];
    default:
      return [];
  }
}

test("parseQuoteTransitionResult: success body with bare Quote shape", () => {
  const text =
    `{"id":"q-1","job_id":"j-1","status":"presented",` +
    `"cost_min":5000,"cost_max":20000,"notes":"",` +
    `"accepted_at":"","rejected_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-15T09:00:00Z"}`;
  const r = parseQuoteTransitionResult(text);
  assert.equal(r.kind, "success");
  if (r.kind === "success") {
    assert.equal(r.quote.status, "presented");
    assert.equal(r.quote.cost_min, 5000);
  }
});

test("parseQuoteTransitionResult: already_in_state body", () => {
  const text =
    `{"status":"already_in_state","quote":{"id":"q-1","job_id":"j-1",` +
    `"status":"draft","cost_min":5000,"cost_max":20000,"notes":"",` +
    `"accepted_at":"","rejected_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}`;
  const r = parseQuoteTransitionResult(text);
  assert.equal(r.kind, "already_in_state");
  if (r.kind === "already_in_state") {
    assert.equal(r.quote.status, "draft");
  }
});

test("parseQuoteTransitionResult: typed not_reachable error body", () => {
  const text =
    `{"error":"not_reachable","from":"draft","to":"accepted","cap_required":null}`;
  const r = parseQuoteTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") {
    assert.equal(r.error, "not_reachable");
    assert.equal(r.from, "draft");
    assert.equal(r.to, "accepted");
    assert.equal(r.cap_required, null);
  }
});

test("parseQuoteTransitionResult: typed wrong_principal error body", () => {
  const text =
    `{"error":"wrong_principal","from":"presented","to":"accepted","cap_required":null}`;
  const r = parseQuoteTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "wrong_principal");
});

test("parseQuoteTransitionResult: empty / non-JSON returns parse_error", () => {
  let r = parseQuoteTransitionResult("");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
  r = parseQuoteTransitionResult("not json");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
});

test("actionsForStatus: draft offers Present + Supersede", () => {
  const a = actionsForStatus("draft");
  assert.equal(a.length, 2);
  assert.equal(a[0]!.label, "Present");
  assert.equal(a[0]!.verb, "present quote");
  assert.equal(a[1]!.label, "Supersede");
  assert.equal(a[1]!.verb, "supersede quote");
});

test("actionsForStatus: presented offers Accept / Decline / Expire / Supersede", () => {
  const a = actionsForStatus("presented");
  assert.equal(a.length, 4);
  assert.equal(a[0]!.label, "Accept");
  assert.equal(a[0]!.verb, "accept quote");
  assert.equal(a[1]!.label, "Decline");
  assert.equal(a[1]!.verb, "decline quote");
  assert.equal(a[2]!.label, "Expire");
  assert.equal(a[2]!.verb, "expire quote");
  assert.equal(a[3]!.label, "Supersede");
  assert.equal(a[3]!.verb, "supersede quote");
});

test("actionsForStatus: terminal states have no actions", () => {
  assert.equal(actionsForStatus("accepted").length, 0);
  assert.equal(actionsForStatus("rejected").length, 0);
  assert.equal(actionsForStatus("expired").length, 0);
  assert.equal(actionsForStatus("superseded").length, 0);
  assert.equal(actionsForStatus("unknown").length, 0);
});

```
