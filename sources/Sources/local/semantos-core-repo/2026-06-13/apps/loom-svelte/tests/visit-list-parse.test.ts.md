---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/visit-list-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.060248+00:00
---

# apps/loom-svelte/tests/visit-list-parse.test.ts

```ts
// D-O4.followup-2 — VisitList.parseVisits unit tests.
//
// Mirrors the shape of `tests/customer-list-parse.test.ts` and
// `tests/job-list-parse.test.ts`.  parseVisits is exported from
// VisitList.svelte's <script module> block; we re-implement it here
// for direct test coverage so the Svelte component file stays the
// canonical source of truth.  Backed by the Semantos Brain dispatcher's typed
// `visits` resource (runtime/semantos-brain/src/resources/visits_handler.zig) —
// JSON is the only branch (visits have no TSV legacy).

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Visit = {
  id: string;
  job_id: string;
  visit_type: string;
  status: string;
  notes: string;
  actual_start: string;
  outcome: string;
  created_at: string;
  updated_at: string;
};

function parseVisits(text: string): Visit[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) return [];
  if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
  try {
    const parsed = JSON.parse(trimmed);
    if (Array.isArray(parsed)) {
      return parsed.map((row) => ({
        id: String(row.id ?? ""),
        job_id: String(row.job_id ?? ""),
        visit_type: String(row.visit_type ?? ""),
        status: String(row.status ?? ""),
        notes: String(row.notes ?? ""),
        actual_start: String(row.actual_start ?? ""),
        outcome: String(row.outcome ?? ""),
        created_at: String(row.created_at ?? ""),
        updated_at: String(row.updated_at ?? ""),
      }));
    }
  } catch {
    // fall through
  }
  return [];
}

test("parseVisits: empty input yields empty list", () => {
  assert.deepEqual(parseVisits(""), []);
  assert.deepEqual(parseVisits("   \n   "), []);
});

test("parseVisits: non-JSON input yields empty list", () => {
  assert.deepEqual(parseVisits("not json"), []);
  assert.deepEqual(parseVisits("[bad json"), []);
});

test("parseVisits: parses dispatcher JSON-array response", () => {
  // Verbatim shape from `visits_handler.zig::writeVisitJson`.
  const text =
    `[{"id":"v-001","job_id":"j-001","visit_type":"scheduled_work",` +
    `"status":"scheduled","notes":"first inspection","actual_start":"",` +
    `"outcome":"","created_at":"2026-05-02T10:00:00Z",` +
    `"updated_at":"2026-05-02T10:00:00Z"},` +
    `{"id":"v-002","job_id":"j-001","visit_type":"return_visit",` +
    `"status":"completed","notes":"","actual_start":"2026-05-15T09:00:00Z",` +
    `"outcome":"completed","created_at":"2026-05-15T08:30:00Z",` +
    `"updated_at":"2026-05-15T11:00:00Z"}]`;
  const visits = parseVisits(text);
  assert.equal(visits.length, 2);
  assert.equal(visits[0]!.id, "v-001");
  assert.equal(visits[0]!.job_id, "j-001");
  assert.equal(visits[0]!.visit_type, "scheduled_work");
  assert.equal(visits[0]!.status, "scheduled");
  assert.equal(visits[0]!.notes, "first inspection");
  assert.equal(visits[1]!.status, "completed");
  assert.equal(visits[1]!.outcome, "completed");
  assert.equal(visits[1]!.actual_start, "2026-05-15T09:00:00Z");
});

test("parseVisits: handles missing fields with empty defaults", () => {
  const text = JSON.stringify([{ id: "v-1" }]);
  const visits = parseVisits(text);
  assert.equal(visits.length, 1);
  assert.equal(visits[0]!.id, "v-1");
  assert.equal(visits[0]!.job_id, "");
  assert.equal(visits[0]!.notes, "");
});

```
