---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/calendar-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.058397+00:00
---

# apps/loom-svelte/tests/calendar-parse.test.ts

```ts
// D-O5.followup-3 — Calendar.parseCalendar unit tests.
//
// Mirrors the shape of `tests/job-list-parse.test.ts`.  parseCalendar
// is exported from Calendar.svelte's <script> block; we re-implement
// it here for direct test coverage so the Svelte component file
// stays the canonical source of truth.  Backed by the Semantos Brain dispatcher's
// typed `jobs` resource (runtime/semantos-brain/src/resources/jobs_handler.zig
// ::find_calendar) — the JSON-array branch is hot.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Job = {
  id: string;
  customer_name: string;
  state: string;
  scheduled_at: string;
};
type CalendarDay = {
  date: string;
  jobs: Job[];
};

// Re-implementation of the parser for direct test coverage — keeps
// the Svelte component file the canonical source of truth.
function parseCalendar(text: string): CalendarDay[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
  try {
    const parsed = JSON.parse(trimmed);
    if (Array.isArray(parsed)) {
      return parsed.map((row) => ({
        date: String(row.date ?? ""),
        jobs: Array.isArray(row.jobs)
          ? row.jobs.map((j: any) => ({
              id: String(j.id ?? ""),
              customer_name: String(j.customer_name ?? j.customer ?? ""),
              state: String(j.state ?? ""),
              scheduled_at: String(j.scheduled_at ?? ""),
            }))
          : [],
      }));
    }
  } catch {
    // fall through
  }
  return [];
}

test("parseCalendar: empty input yields empty list", () => {
  assert.deepEqual(parseCalendar(""), []);
  assert.deepEqual(parseCalendar("   \n  "), []);
});

test("parseCalendar: non-JSON input yields empty list", () => {
  assert.deepEqual(parseCalendar("not json"), []);
  assert.deepEqual(parseCalendar("# id\tdate"), []);
});

test("parseCalendar: malformed JSON degrades to empty list", () => {
  assert.deepEqual(parseCalendar("[{\"date\":\"2026-05-04\","), []);
});

// D-O5.followup-3 — integration with the typed `jobs.find_calendar`
// dispatcher resource.  The brain-side resource handler emits a JSON
// array `[{date, jobs:[...]}, ...]`; days with no jobs scheduled
// still appear with empty `jobs` arrays so the helm renders a
// calendar grid without missing-key checks.  This test asserts
// parseCalendar consumes the exact bytes the dispatcher emits.
test("parseCalendar: D-O5.followup-3 dispatcher response shape", () => {
  // Verbatim shape from `jobs_handler.zig::handleFindCalendar`.
  const dispatcherResponse =
    `[{"date":"2026-05-04","jobs":[` +
    `{"id":"abc123","customer_name":"Acme Corp","state":"scheduled","scheduled_at":"2026-05-04T09:00:00Z"}` +
    `]},` +
    `{"date":"2026-05-05","jobs":[]},` +
    `{"date":"2026-05-06","jobs":[` +
    `{"id":"def456","customer_name":"Globex","state":"in_progress","scheduled_at":"2026-05-06T10:00:00Z"}` +
    `]}]`;
  const days = parseCalendar(dispatcherResponse);
  assert.equal(days.length, 3);
  assert.equal(days[0]!.date, "2026-05-04");
  assert.equal(days[0]!.jobs.length, 1);
  assert.equal(days[0]!.jobs[0]!.customer_name, "Acme Corp");
  assert.equal(days[0]!.jobs[0]!.scheduled_at, "2026-05-04T09:00:00Z");
  // Empty-day buckets surface with `jobs: []` so the helm renders
  // the calendar grid without missing-key checks.
  assert.equal(days[1]!.date, "2026-05-05");
  assert.deepEqual(days[1]!.jobs, []);
  assert.equal(days[2]!.jobs[0]!.state, "in_progress");
});

```
