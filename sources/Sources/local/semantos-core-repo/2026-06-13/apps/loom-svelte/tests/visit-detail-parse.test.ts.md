---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/visit-detail-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.055651+00:00
---

# apps/loom-svelte/tests/visit-detail-parse.test.ts

```ts
// D-O4.followup-2 — VisitDetail.svelte parser tests.
//
// `parseVisitTransitionResult` + `actionsForStatus` are exported from
// VisitDetail.svelte's `<script lang="ts" module>` block.  We re-
// implement them here to keep the Svelte component the canonical
// source — same posture as job-detail-parse.test.ts.

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

type VisitTransitionResult =
  | { kind: "success"; visit: Visit }
  | { kind: "already_in_state"; visit: Visit }
  | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

type VisitAction = { label: string; verb: string };

function visitFromBody(row: Record<string, unknown>): Visit {
  return {
    id: String(row.id ?? ""),
    job_id: String(row.job_id ?? ""),
    visit_type: String(row.visit_type ?? ""),
    status: String(row.status ?? ""),
    notes: String(row.notes ?? ""),
    actual_start: String(row.actual_start ?? ""),
    outcome: String(row.outcome ?? ""),
    created_at: String(row.created_at ?? ""),
    updated_at: String(row.updated_at ?? ""),
  };
}

function parseVisitTransitionResult(text: string): VisitTransitionResult {
  const trimmed = text.trim();
  if (trimmed.length === 0 || !trimmed.startsWith("{")) {
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      if (parsed.status === "already_in_state" && parsed.visit) {
        return { kind: "already_in_state", visit: visitFromBody(parsed.visit) };
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
        return { kind: "success", visit: visitFromBody(parsed) };
      }
    }
  } catch {
    // fall through
  }
  return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
}

function actionsForStatus(status: string): readonly VisitAction[] {
  switch (status) {
    case "scheduled":
      return [
        { label: "Start", verb: "start visit" },
        { label: "Cancel", verb: "cancel visit" },
      ];
    case "in_progress":
      return [
        { label: "Complete", verb: "complete visit" },
        { label: "Cancel", verb: "cancel visit" },
      ];
    case "completed":
    case "cancelled":
      return [];
    default:
      return [];
  }
}

test("parseVisitTransitionResult: success body with bare Visit shape", () => {
  const text =
    `{"id":"v-1","job_id":"j-1","visit_type":"scheduled_work",` +
    `"status":"in_progress","notes":"",` +
    `"actual_start":"2026-05-15T09:00:00Z","outcome":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-15T09:00:00Z"}`;
  const r = parseVisitTransitionResult(text);
  assert.equal(r.kind, "success");
  if (r.kind === "success") {
    assert.equal(r.visit.status, "in_progress");
    assert.equal(r.visit.actual_start, "2026-05-15T09:00:00Z");
  }
});

test("parseVisitTransitionResult: already_in_state body", () => {
  const text =
    `{"status":"already_in_state","visit":{"id":"v-1","job_id":"j-1",` +
    `"visit_type":"scheduled_work","status":"scheduled","notes":"",` +
    `"actual_start":"","outcome":"",` +
    `"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}`;
  const r = parseVisitTransitionResult(text);
  assert.equal(r.kind, "already_in_state");
  if (r.kind === "already_in_state") {
    assert.equal(r.visit.status, "scheduled");
  }
});

test("parseVisitTransitionResult: typed not_reachable error body", () => {
  const text =
    `{"error":"not_reachable","from":"scheduled","to":"completed","cap_required":null}`;
  const r = parseVisitTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") {
    assert.equal(r.error, "not_reachable");
    assert.equal(r.from, "scheduled");
    assert.equal(r.to, "completed");
    assert.equal(r.cap_required, null);
  }
});

test("parseVisitTransitionResult: typed wrong_principal error body", () => {
  const text =
    `{"error":"wrong_principal","from":"scheduled","to":"in_progress","cap_required":null}`;
  const r = parseVisitTransitionResult(text);
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "wrong_principal");
});

test("parseVisitTransitionResult: empty / non-JSON returns parse_error", () => {
  let r = parseVisitTransitionResult("");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
  r = parseVisitTransitionResult("not json");
  assert.equal(r.kind, "error");
  if (r.kind === "error") assert.equal(r.error, "parse_error");
});

test("actionsForStatus: scheduled offers Start + Cancel", () => {
  const a = actionsForStatus("scheduled");
  assert.equal(a.length, 2);
  assert.equal(a[0]!.label, "Start");
  assert.equal(a[0]!.verb, "start visit");
  assert.equal(a[1]!.label, "Cancel");
  assert.equal(a[1]!.verb, "cancel visit");
});

test("actionsForStatus: in_progress offers Complete + Cancel", () => {
  const a = actionsForStatus("in_progress");
  assert.equal(a.length, 2);
  assert.equal(a[0]!.label, "Complete");
  assert.equal(a[0]!.verb, "complete visit");
  assert.equal(a[1]!.label, "Cancel");
});

test("actionsForStatus: terminal states have no actions", () => {
  assert.equal(actionsForStatus("completed").length, 0);
  assert.equal(actionsForStatus("cancelled").length, 0);
  assert.equal(actionsForStatus("unknown").length, 0);
});

```
