---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/job-detail-parse.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.056237+00:00
---

# apps/loom-svelte/tests/job-detail-parse.test.ts

```ts
// D-O5 followup-1 — JobDetail.svelte parser tests.
//
// `parseJobTransitionResult` + `actionForState` are exported from
// JobDetail.svelte's `<script lang="ts" module>` block so we can
// validate them without instantiating the Svelte component.  We
// re-implement them here to keep the Svelte component the canonical
// source — same posture as job-list-parse.test.ts.

import { test } from "node:test";
import { strict as assert } from "node:assert";

type Job = {
  id: string;
  customer_name: string;
  state: string;
  scheduled_at: string;
  created_at?: string;
};

type JobTransitionResult =
  | { kind: "success"; job: Job }
  | { kind: "already_in_state"; job: Job }
  | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

type StateAction = { label: string; verb: string };

function jobFromBody(row: Record<string, unknown>): Job {
  return {
    id: String(row.id ?? ""),
    customer_name: String(row.customer_name ?? row.customer ?? ""),
    state: String(row.state ?? ""),
    scheduled_at: String(row.scheduled_at ?? ""),
    created_at: row.created_at ? String(row.created_at) : undefined,
  };
}

function parseJobTransitionResult(text: string): JobTransitionResult {
  const trimmed = text.trim();
  if (trimmed.length === 0 || !trimmed.startsWith("{")) {
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      if (parsed.status === "already_in_state" && parsed.job) {
        return { kind: "already_in_state", job: jobFromBody(parsed.job) };
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
      if (parsed.id && parsed.state) {
        return { kind: "success", job: jobFromBody(parsed) };
      }
    }
  } catch {
    // Fall through to parse_error.
  }
  return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
}

function actionForState(state: string): StateAction | null {
  switch (state) {
    case "lead":        return { label: "Quote",     verb: "quote job" };
    case "quoted":      return { label: "Schedule",  verb: "schedule job" };
    case "scheduled":   return { label: "Start",     verb: "start job" };
    case "in_progress": return { label: "Complete",  verb: "complete job" };
    case "completed":   return { label: "Invoice",   verb: "invoice job" };
    case "invoiced":    return { label: "Mark Paid", verb: "mark job paid" };
    case "paid":        return { label: "Close",     verb: "close job" };
    case "closed":      return null;
    default:            return null;
  }
}

test("parseJobTransitionResult: success body (bare Job shape)", () => {
  // Verbatim shape from `jobs_handler.zig::handleTransition` success
  // branch — `writeJobJson` of the updated record.
  const body =
    `{"id":"abc123","customer_name":"Acme","state":"quoted",` +
    `"scheduled_at":"","created_at":"2026-05-02T10:00:00Z"}`;
  const r = parseJobTransitionResult(body);
  assert.equal(r.kind, "success");
  if (r.kind === "success") {
    assert.equal(r.job.id, "abc123");
    assert.equal(r.job.state, "quoted");
  }
});

test("parseJobTransitionResult: already_in_state body", () => {
  const body =
    `{"status":"already_in_state","job":{"id":"abc","customer_name":"Acme",` +
    `"state":"scheduled","scheduled_at":"","created_at":"2026-05-01T00:00:00Z"}}`;
  const r = parseJobTransitionResult(body);
  assert.equal(r.kind, "already_in_state");
  if (r.kind === "already_in_state") {
    assert.equal(r.job.state, "scheduled");
  }
});

test("parseJobTransitionResult: typed wrong_cap error", () => {
  const body =
    `{"error":"wrong_cap","from":"lead","to":"quoted",` +
    `"cap_required":"cap.oddjobz.quote"}`;
  const r = parseJobTransitionResult(body);
  assert.equal(r.kind, "error");
  if (r.kind === "error") {
    assert.equal(r.error, "wrong_cap");
    assert.equal(r.from, "lead");
    assert.equal(r.to, "quoted");
    assert.equal(r.cap_required, "cap.oddjobz.quote");
  }
});

test("parseJobTransitionResult: typed not_reachable with null cap_required", () => {
  const body = `{"error":"not_reachable","from":"lead","to":"invoiced","cap_required":null}`;
  const r = parseJobTransitionResult(body);
  assert.equal(r.kind, "error");
  if (r.kind === "error") {
    assert.equal(r.error, "not_reachable");
    assert.equal(r.cap_required, null);
  }
});

test("parseJobTransitionResult: parse_error on malformed input", () => {
  for (const input of ["", "   ", "not json", "{not valid"]) {
    const r = parseJobTransitionResult(input);
    assert.equal(r.kind, "error");
    if (r.kind === "error") assert.equal(r.error, "parse_error");
  }
});

test("actionForState: maps each FSM state to the canonical REPL verb", () => {
  // Mirrors runtime/semantos-brain/src/repl.zig's verb table verbatim.
  assert.deepEqual(actionForState("lead"),        { label: "Quote",     verb: "quote job" });
  assert.deepEqual(actionForState("quoted"),      { label: "Schedule",  verb: "schedule job" });
  assert.deepEqual(actionForState("scheduled"),   { label: "Start",     verb: "start job" });
  assert.deepEqual(actionForState("in_progress"), { label: "Complete",  verb: "complete job" });
  assert.deepEqual(actionForState("completed"),   { label: "Invoice",   verb: "invoice job" });
  assert.deepEqual(actionForState("invoiced"),    { label: "Mark Paid", verb: "mark job paid" });
  assert.deepEqual(actionForState("paid"),        { label: "Close",     verb: "close job" });
  // closed is terminal — no further actions.
  assert.equal(actionForState("closed"), null);
  // unknown states surface no action rather than throwing.
  assert.equal(actionForState("paused"), null);
});

```
