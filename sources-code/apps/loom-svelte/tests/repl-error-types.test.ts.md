---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-error-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.059947+00:00
---

# apps/loom-svelte/tests/repl-error-types.test.ts

```ts
// D-O5m.followup-5 K1 conflict UI — typed REPL error class tests.
//
// Asserts the typed error classes (ReplValidationError /
// ReplStateMovedOnError / ReplFkError) parse the relevant brain
// response shapes correctly + that ReplClient.send promotes the
// brain's 400 typed body to a ReplValidationError + that the
// throwIfTypedConflict helper dispatches typed errors on
// 200-shape transition bodies.
//
// Run via `bun test tests/repl-error-types.test.ts`.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  FK_ERROR_KINDS,
  ReplClient,
  ReplFkError,
  ReplStateMovedOnError,
  ReplValidationError,
  STATE_MOVED_ON_KINDS,
  throwIfTypedConflict,
} from "../src/lib/repl-client";

test("ReplValidationError carries kind + hint + composed message", () => {
  const e = new ReplValidationError("invalid_args", "missing visit_id");
  assert.equal(e.name, "ReplValidationError");
  assert.equal(e.kind, "invalid_args");
  assert.equal(e.hint, "missing visit_id");
  // Message interpolates the hint when present.
  assert.match(e.message, /missing visit_id/);
});

test("ReplValidationError without hint falls back to bare kind", () => {
  const e = new ReplValidationError("invalid_args");
  assert.equal(e.hint, null);
  assert.equal(e.message, "invalid_args");
});

test("ReplStateMovedOnError captures brain state + from/to", () => {
  const e = new ReplStateMovedOnError("not_reachable", {
    brainState: "completed",
    fromState: "in_progress",
    toState: "quoted",
  });
  assert.equal(e.name, "ReplStateMovedOnError");
  assert.equal(e.kind, "not_reachable");
  assert.equal(e.brainState, "completed");
  assert.equal(e.fromState, "in_progress");
  assert.equal(e.toState, "quoted");
  assert.match(e.message, /completed/);
});

test("ReplFkError captures id + entity", () => {
  const e = new ReplFkError("visit_not_found", {
    id: "visit-123",
    entity: "visit",
  });
  assert.equal(e.name, "ReplFkError");
  assert.equal(e.kind, "visit_not_found");
  assert.equal(e.id, "visit-123");
  assert.equal(e.entity, "visit");
  assert.match(e.message, /visit-123/);
});

test("STATE_MOVED_ON_KINDS covers FSM rejection wires", () => {
  for (const kind of [
    "state_moved_on",
    "not_reachable",
    "wrong_principal",
    "wrong_cap",
  ]) {
    assert.ok(STATE_MOVED_ON_KINDS.has(kind), `${kind} should be a state-moved-on kind`);
  }
  assert.ok(!STATE_MOVED_ON_KINDS.has("invalid_args"));
});

test("FK_ERROR_KINDS covers the brain's not_found wires", () => {
  for (const kind of ["not_found", "visit_not_found", "job_not_found"]) {
    assert.ok(FK_ERROR_KINDS.has(kind), `${kind} should be an FK error kind`);
  }
  assert.ok(!FK_ERROR_KINDS.has("hash_mismatch"));
});

test("throwIfTypedConflict throws ReplStateMovedOnError on FSM-rejection bodies", () => {
  const body = {
    error: "not_reachable",
    from: "in_progress",
    to: "quoted",
  } as const;
  assert.throws(
    () => throwIfTypedConflict(body),
    (err: unknown) => {
      assert.ok(err instanceof ReplStateMovedOnError);
      assert.equal((err as ReplStateMovedOnError).kind, "not_reachable");
      assert.equal((err as ReplStateMovedOnError).brainState, "in_progress");
      assert.equal((err as ReplStateMovedOnError).toState, "quoted");
      return true;
    },
  );
});

test("throwIfTypedConflict throws ReplFkError on visit_not_found bodies", () => {
  const body = {
    error: "visit_not_found",
    visit_id: "visit-abc",
  } as const;
  assert.throws(
    () => throwIfTypedConflict(body),
    (err: unknown) => {
      assert.ok(err instanceof ReplFkError);
      assert.equal((err as ReplFkError).kind, "visit_not_found");
      assert.equal((err as ReplFkError).id, "visit-abc");
      assert.equal((err as ReplFkError).entity, "visit");
      return true;
    },
  );
});

test("throwIfTypedConflict passes through success bodies untouched", () => {
  const body = { result: "ok", exit: "continue" } as const;
  const passed = throwIfTypedConflict(body);
  assert.deepEqual(passed, body);
});

test("ReplClient.send promotes 400 typed body to ReplValidationError", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response(
      JSON.stringify({ error: "invalid_args", hint: "id missing" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  await assert.rejects(
    client.send("status"),
    (err: unknown) => {
      assert.ok(err instanceof ReplValidationError);
      assert.equal((err as ReplValidationError).kind, "invalid_args");
      assert.equal((err as ReplValidationError).hint, "id missing");
      return true;
    },
  );
});

test("ReplClient.send returns ReplErr for 503 (still untyped)", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"backend_unavailable"}', {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  const resp = await client.send("status");
  assert.deepEqual(resp, { error: "backend_unavailable" });
});

```
