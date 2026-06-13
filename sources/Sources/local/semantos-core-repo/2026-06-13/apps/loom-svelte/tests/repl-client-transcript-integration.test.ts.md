---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-client-transcript-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.055936+00:00
---

# apps/loom-svelte/tests/repl-client-transcript-integration.test.ts

```ts
// D-O5.followup-7 — integration tests asserting ReplClient.send
// pushes transcript entries on the success / 401 / network-error
// paths.  Pure-typescript; uses Node's built-in test runner.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import { ReplClient, ReplUnauthorizedError } from "../src/lib/repl-client";
import {
  __resetTranscriptForTests,
  transcript,
} from "../src/lib/repl-transcript-store";

test("ReplClient.send: 200 path records ok entry with bytes count", async () => {
  __resetTranscriptForTests();
  const fakeFetch: typeof fetch = async () =>
    new Response(
      JSON.stringify({
        result: "job-001\tcust-aa\tlead\t2026-05-02",
        exit: "continue",
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  const client = new ReplClient({
    bearer: () => "a".repeat(64),
    fetchImpl: fakeFetch,
  });
  await client.send("find jobs");
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.cmd, "find jobs");
  assert.equal(entry.result.kind, "ok");
  if (entry.result.kind === "ok") {
    assert.match(entry.result.text, /job-001/);
    assert.equal(entry.result.bytes, "job-001\tcust-aa\tlead\t2026-05-02".length);
    assert.equal(entry.result.truncated, false);
  }
  assert.ok(entry.durationMs >= 0);
});

test("ReplClient.send: 401 path records err entry with statusCode=401", async () => {
  __resetTranscriptForTests();
  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"missing bearer token"}', {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  await assert.rejects(client.send("find jobs"), ReplUnauthorizedError);
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.cmd, "find jobs");
  assert.equal(entry.result.kind, "err");
  if (entry.result.kind === "err") {
    assert.equal(entry.result.statusCode, 401);
  }
});

test("ReplClient.send: network error records err entry without statusCode", async () => {
  __resetTranscriptForTests();
  const fakeFetch: typeof fetch = async () => {
    throw new TypeError("Failed to fetch");
  };
  const client = new ReplClient({ bearer: () => "x".repeat(64), fetchImpl: fakeFetch });
  await assert.rejects(client.send("status"), /Failed to fetch/);
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.cmd, "status");
  assert.equal(entry.result.kind, "err");
  if (entry.result.kind === "err") {
    assert.equal(entry.result.statusCode, undefined);
    assert.match(entry.result.error, /Failed to fetch/);
  }
});

test("ReplClient.send: 503 (typed ReplErr body) records err entry", async () => {
  __resetTranscriptForTests();
  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"REPL backend not enabled in this serve mode"}', {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  const client = new ReplClient({ bearer: () => "y".repeat(64), fetchImpl: fakeFetch });
  const resp = await client.send("status");
  // 503 doesn't throw — it returns a ReplErr body — but the
  // transcript still flags it as err so the operator sees the failure.
  assert.deepEqual(resp, { error: "REPL backend not enabled in this serve mode" });
  const entries = get(transcript);
  assert.equal(entries.length, 1);
  const entry = entries[0]!;
  assert.equal(entry.result.kind, "err");
  if (entry.result.kind === "err") {
    assert.match(entry.result.error, /REPL backend not enabled/);
  }
});

test("ReplClient.send: pending entry exists during in-flight fetch", async () => {
  __resetTranscriptForTests();
  let resolveFetch: (r: Response) => void = () => {};
  const inFlight = new Promise<Response>((res) => {
    resolveFetch = res;
  });
  const fakeFetch: typeof fetch = async () => inFlight;
  const client = new ReplClient({ bearer: () => "z".repeat(64), fetchImpl: fakeFetch });
  const sendPromise = client.send("find jobs");
  // Microtask flush — the pending push is sync, so it should already be in.
  await Promise.resolve();
  let entries = get(transcript);
  assert.equal(entries.length, 1);
  assert.equal(entries[0]!.result.kind, "pending");

  resolveFetch(
    new Response('{"result":"ok","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
  await sendPromise;
  entries = get(transcript);
  assert.equal(entries[0]!.result.kind, "ok");
});

```
