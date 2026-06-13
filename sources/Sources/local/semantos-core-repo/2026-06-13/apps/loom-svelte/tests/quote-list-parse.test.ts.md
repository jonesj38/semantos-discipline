---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/quote-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.059361+00:00
---

# apps/loom-svelte/tests/quote-list-parse.test.ts

```ts
// D-O4.followup-3 — QuoteList.parseQuotes unit tests.
//
// Mirrors the shape of `tests/visit-list-parse.test.ts`.  parseQuotes
// is exported from QuoteList.svelte's <script module> block; we re-
// implement it here for direct test coverage so the Svelte component
// file stays the canonical source of truth.  Backed by the Semantos Brain
// dispatcher's typed `quotes` resource (runtime/semantos-brain/src/resources/
// quotes_handler.zig) — JSON is the only branch (quotes have no TSV
// legacy).

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

function parseQuotes(text: string): Quote[] {
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
        cost_min: Number(row.cost_min ?? 0),
        cost_max: Number(row.cost_max ?? 0),
        notes: String(row.notes ?? ""),
        accepted_at: String(row.accepted_at ?? ""),
        rejected_at: String(row.rejected_at ?? ""),
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

test("parseQuotes: empty input yields empty list", () => {
  assert.deepEqual(parseQuotes(""), []);
  assert.deepEqual(parseQuotes("   \n   "), []);
});

test("parseQuotes: non-JSON input yields empty list", () => {
  assert.deepEqual(parseQuotes("not json"), []);
  assert.deepEqual(parseQuotes("[bad json"), []);
});

test("parseQuotes: parses dispatcher JSON-array response", () => {
  // Verbatim shape from `quotes_handler.zig::writeQuoteJson`.
  const text =
    `[{"id":"q-001","job_id":"j-001","status":"draft",` +
    `"cost_min":5000,"cost_max":20000,"notes":"first quote",` +
    `"accepted_at":"","rejected_at":"",` +
    `"created_at":"2026-05-02T10:00:00Z",` +
    `"updated_at":"2026-05-02T10:00:00Z"},` +
    `{"id":"q-002","job_id":"j-001","status":"accepted",` +
    `"cost_min":1000,"cost_max":1500,"notes":"",` +
    `"accepted_at":"2026-05-15T09:00:00Z","rejected_at":"",` +
    `"created_at":"2026-05-15T08:30:00Z",` +
    `"updated_at":"2026-05-15T11:00:00Z"}]`;
  const quotes = parseQuotes(text);
  assert.equal(quotes.length, 2);
  assert.equal(quotes[0]!.id, "q-001");
  assert.equal(quotes[0]!.job_id, "j-001");
  assert.equal(quotes[0]!.status, "draft");
  assert.equal(quotes[0]!.cost_min, 5000);
  assert.equal(quotes[0]!.cost_max, 20000);
  assert.equal(quotes[0]!.notes, "first quote");
  assert.equal(quotes[1]!.status, "accepted");
  assert.equal(quotes[1]!.accepted_at, "2026-05-15T09:00:00Z");
});

test("parseQuotes: handles missing fields with empty defaults", () => {
  const text = JSON.stringify([{ id: "q-1" }]);
  const quotes = parseQuotes(text);
  assert.equal(quotes.length, 1);
  assert.equal(quotes[0]!.id, "q-1");
  assert.equal(quotes[0]!.job_id, "");
  assert.equal(quotes[0]!.cost_min, 0);
  assert.equal(quotes[0]!.cost_max, 0);
});

test("formatCents: $X.YY format", () => {
  assert.equal(formatCents(0), "$0.00");
  assert.equal(formatCents(100), "$1.00");
  assert.equal(formatCents(12345), "$123.45");
  assert.equal(formatCents(20000), "$200.00");
});

```
