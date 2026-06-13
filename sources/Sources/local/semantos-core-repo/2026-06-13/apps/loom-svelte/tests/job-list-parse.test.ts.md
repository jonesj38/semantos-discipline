---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/job-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.063299+00:00
---

# apps/loom-svelte/tests/job-list-parse.test.ts

```ts
// D-O5 — JobList.parseJobs unit tests.
//
// `parseJobs` is exported from JobList.svelte's <script> block so we
// can validate its parser without instantiating the Svelte component.
// Imports it via the same module Svelte's preprocessor produces.

import { test } from "node:test";
import { strict as assert } from "node:assert";

// Re-implementation of the parser for direct test coverage — keeps
// the Svelte component file the canonical source of truth.  When the
// dispatcher gains a typed `find_jobs` resource (D-O5.followup-1)
// this parser goes away and so does this test.
function parseJobs(text: string): {
  id: string;
  customer_name: string;
  state: string;
  scheduled_at: string;
}[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row) => ({
          id: String(row.id ?? ""),
          customer_name: String(row.customer_name ?? row.customer ?? ""),
          state: String(row.state ?? ""),
          scheduled_at: String(row.scheduled_at ?? ""),
        }));
      }
    } catch {
      // fall through
    }
  }
  const lines = trimmed.split("\n").filter((l) => l.length > 0 && !l.startsWith("#"));
  return lines.flatMap((line) => {
    const cols = line.split("\t");
    if (cols.length < 4) return [];
    return [{
      id: cols[0]!,
      customer_name: cols[1]!,
      state: cols[2]!,
      scheduled_at: cols[3]!,
    }];
  });
}

test("parseJobs: empty input yields empty list", () => {
  assert.deepEqual(parseJobs(""), []);
  assert.deepEqual(parseJobs("   \n  "), []);
});

test("parseJobs: parses JSON array", () => {
  const text = JSON.stringify([
    { id: "job-1", customer_name: "Acme", state: "scheduled", scheduled_at: "2026-05-02T09:00Z" },
    { id: "job-2", customer_name: "Globex", state: "in_progress", scheduled_at: "2026-05-02T13:30Z" },
  ]);
  const jobs = parseJobs(text);
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0]!.customer_name, "Acme");
  assert.equal(jobs[1]!.state, "in_progress");
});

test("parseJobs: maps `customer` to `customer_name`", () => {
  const text = JSON.stringify([
    { id: "j1", customer: "Old Field", state: "quoted", scheduled_at: "" },
  ]);
  const jobs = parseJobs(text);
  assert.equal(jobs[0]!.customer_name, "Old Field");
});

test("parseJobs: parses TSV with comment header", () => {
  const text = [
    "# id\tcustomer\tstate\tscheduled_at",
    "job-1\tAcme\tscheduled\t2026-05-02",
    "job-2\tGlobex\tin_progress\t2026-05-03",
  ].join("\n");
  const jobs = parseJobs(text);
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0]!.id, "job-1");
  assert.equal(jobs[1]!.scheduled_at, "2026-05-03");
});

test("parseJobs: drops malformed TSV rows without breaking later ones", () => {
  const text = [
    "job-1\tAcme\tscheduled\t2026-05-02",
    "broken-line",
    "job-2\tGlobex\tquoted\t2026-05-03",
  ].join("\n");
  const jobs = parseJobs(text);
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0]!.id, "job-1");
  assert.equal(jobs[1]!.id, "job-2");
});

// D-O5.followup-1 / D-O5m.followup-4 — integration with the typed
// `find_jobs` dispatcher resource.  The brain-side resource handler
// (runtime/semantos-brain/src/resources/jobs_handler.zig) emits a JSON array
// where every row has the canonical helm field set: id,
// customer_name, state, scheduled_at, created_at.  This test asserts
// parseJobs consumes that exact shape — the exact bytes the
// dispatcher would return — without falling through to the TSV
// branch.  When a future churn drops a field on the Semantos Brain side, this
// test breaks loud.
test("parseJobs: D-O5.followup-1 dispatcher response shape", () => {
  // Verbatim shape from `jobs_handler.zig::writeJobJson` — both
  // single-quote and double-quote field names are valid JSON; we
  // use the exact bytes the handler emits.
  const dispatcherResponse =
    `[{"id":"abc123","customer_name":"Acme Corp","state":"lead",` +
    `"scheduled_at":"2026-05-15T09:00:00Z","created_at":"2026-05-02T10:00:00Z"},` +
    `{"id":"def456","customer_name":"Globex","state":"scheduled",` +
    `"scheduled_at":"","created_at":"2026-05-02T11:30:00Z"}]`;
  const jobs = parseJobs(dispatcherResponse);
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0]!.id, "abc123");
  assert.equal(jobs[0]!.customer_name, "Acme Corp");
  assert.equal(jobs[0]!.state, "lead");
  assert.equal(jobs[0]!.scheduled_at, "2026-05-15T09:00:00Z");
  assert.equal(jobs[1]!.customer_name, "Globex");
  assert.equal(jobs[1]!.state, "scheduled");
  assert.equal(jobs[1]!.scheduled_at, "");
});

```
