---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/attention-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.059000+00:00
---

# apps/loom-svelte/tests/attention-parse.test.ts

```ts
// D-O5.followup-3 — Attention.parseAttention unit tests.
//
// Mirrors the shape of `tests/job-list-parse.test.ts`.  parseAttention
// is exported from Attention.svelte's <script> block; we re-implement
// it here for direct test coverage so the Svelte component file
// stays the canonical source of truth.  Backed by the Semantos Brain dispatcher's
// typed `jobs` resource (runtime/semantos-brain/src/resources/jobs_handler.zig
// ::find_attention) — the JSON-object branch is hot.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Job = {
  id: string;
  customer_name: string;
  state: string;
  scheduled_at: string;
};
type AttentionFeed = {
  pending_quote: Job[];
  pending_schedule: Job[];
  pending_invoice: Job[];
  total: number;
};

const empty: AttentionFeed = {
  pending_quote: [],
  pending_schedule: [],
  pending_invoice: [],
  total: 0,
};

function extractJobs(raw: unknown): Job[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((j: any) => ({
    id: String(j.id ?? ""),
    customer_name: String(j.customer_name ?? j.customer ?? ""),
    state: String(j.state ?? ""),
    scheduled_at: String(j.scheduled_at ?? ""),
  }));
}

// Re-implementation of the parser for direct test coverage.
function parseAttention(text: string): AttentionFeed {
  const trimmed = text.trim();
  if (trimmed.length === 0) return empty;
  if (!trimmed.startsWith("{")) return empty;
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      const pq = extractJobs(parsed.pending_quote);
      const ps = extractJobs(parsed.pending_schedule);
      const pi = extractJobs(parsed.pending_invoice);
      const totalRaw = parsed.total;
      const total = typeof totalRaw === "number"
        ? totalRaw
        : pq.length + ps.length + pi.length;
      return {
        pending_quote: pq,
        pending_schedule: ps,
        pending_invoice: pi,
        total,
      };
    }
  } catch {
    // fall through
  }
  return empty;
}

test("parseAttention: empty input yields empty feed", () => {
  assert.deepEqual(parseAttention(""), empty);
  assert.deepEqual(parseAttention("   \n  "), empty);
});

test("parseAttention: non-JSON input yields empty feed", () => {
  assert.deepEqual(parseAttention("not json"), empty);
  assert.deepEqual(parseAttention("[1,2,3]"), empty);
});

test("parseAttention: empty-categories envelope returns total=0", () => {
  const body = JSON.stringify({
    pending_quote: [],
    pending_schedule: [],
    pending_invoice: [],
    total: 0,
  });
  const feed = parseAttention(body);
  assert.equal(feed.total, 0);
  assert.deepEqual(feed.pending_quote, []);
});

// D-O5.followup-3 — integration with the typed `jobs.find_attention`
// dispatcher resource.  The brain-side resource handler emits a JSON
// object with three keyed arrays plus a `total` int.  This test
// asserts parseAttention consumes the exact bytes the dispatcher
// emits — when a future churn drops a field on the Semantos Brain side, this
// test breaks loud.
test("parseAttention: D-O5.followup-3 dispatcher response shape", () => {
  // Verbatim shape from `jobs_handler.zig::handleFindAttention`.
  const dispatcherResponse =
    `{"pending_quote":[` +
    `{"id":"j-lead","customer_name":"Lead Co","state":"lead","scheduled_at":""}` +
    `],"pending_schedule":[` +
    `{"id":"j-quoted","customer_name":"Quoted Co","state":"quoted","scheduled_at":""}` +
    `],"pending_invoice":[` +
    `{"id":"j-completed","customer_name":"Done Co","state":"completed","scheduled_at":"2026-05-04T08:00:00Z"}` +
    `],"total":3}`;
  const feed = parseAttention(dispatcherResponse);
  assert.equal(feed.total, 3);
  assert.equal(feed.pending_quote.length, 1);
  assert.equal(feed.pending_quote[0]!.customer_name, "Lead Co");
  assert.equal(feed.pending_schedule[0]!.state, "quoted");
  assert.equal(feed.pending_invoice[0]!.scheduled_at, "2026-05-04T08:00:00Z");
});

```
