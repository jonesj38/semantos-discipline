---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-client.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.062192+00:00
---

# apps/loom-svelte/tests/repl-client.test.ts

```ts
// D-O5 — REPLClient + JobList.parseJobs unit tests.
//
// Run via `node --test --import tsx`.  Uses Node's built-in test runner
// to avoid adding vitest/jest as dependencies for the MVP.  When the
// helm SPA grows enough surface to warrant a richer test framework,
// this file ports over cleanly to vitest's same `describe/test` shape.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { ReplClient, ReplUnauthorizedError } from "../src/lib/repl-client";

// ── ReplClient.send ──

test("ReplClient.send: includes bearer token when present", async () => {
  let captured: { url?: string; init?: RequestInit } = {};
  const fakeFetch: typeof fetch = async (url, init) => {
    captured = { url: url.toString(), init };
    return new Response(
      JSON.stringify({ result: "ok", exit: "continue" }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  const client = new ReplClient({
    bearer: () => "deadbeef".repeat(8),
    fetchImpl: fakeFetch,
  });
  const resp = await client.send("status");
  assert.deepEqual(resp, { result: "ok", exit: "continue" });
  const headers = captured.init?.headers as Record<string, string>;
  assert.equal(headers["authorization"], `Bearer ${"deadbeef".repeat(8)}`);
  assert.equal(headers["content-type"], "application/json");
  assert.equal(captured.init?.method, "POST");
  assert.equal(JSON.parse(captured.init?.body as string).cmd, "status");
});

test("ReplClient.send: throws ReplUnauthorizedError on 401", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"missing bearer token"}', {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  await assert.rejects(client.send("status"), ReplUnauthorizedError);
});

test("ReplClient.send: surfaces error body as ReplErr on non-401", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"REPL backend not enabled in this serve mode"}', {
      status: 503,
      headers: { "content-type": "application/json" },
    });
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  const resp = await client.send("status");
  assert.deepEqual(resp, { error: "REPL backend not enabled in this serve mode" });
});

test("ReplClient.send: omits Authorization header when bearer is null", async () => {
  let captured: { init?: RequestInit } = {};
  const fakeFetch: typeof fetch = async (_url, init) => {
    captured = { init };
    return new Response('{"result":"","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  await client.send("status");
  const headers = captured.init?.headers as Record<string, string>;
  assert.equal(headers["authorization"], undefined);
});

// ── ReplClient.fetchBlob (D-O5m.followup-8 capture+upload) ──

// Polyfill URL.createObjectURL for Node tests (jsdom-free environment).
type GlobalWithUrl = typeof globalThis & {
  URL: typeof URL & {
    createObjectURL?: (b: Blob) => string;
    revokeObjectURL?: (s: string) => void;
  };
};
(globalThis as GlobalWithUrl).URL.createObjectURL ??= (_b: Blob) => "blob:mock-url";
(globalThis as GlobalWithUrl).URL.revokeObjectURL ??= (_: string) => {};

test("ReplClient.fetchBlob: includes bearer + returns object URL on 200", async () => {
  let captured: { url?: string; init?: RequestInit } = {};
  const fakeFetch: typeof fetch = async (url, init) => {
    captured = { url: url.toString(), init };
    return new Response(new Uint8Array([0xff, 0xd8, 0xff]), {
      status: 200,
      headers: { "content-type": "image/jpeg" },
    });
  };
  const client = new ReplClient({
    bearer: () => "abcdef".repeat(8) + "abcd",
    fetchImpl: fakeFetch,
    baseUrl: "https://test",
  });
  const url = await client.fetchBlob("/api/v1/attachments/abc/blob");
  assert.equal(typeof url, "string");
  assert.match(url, /^blob:/);
  const headers = captured.init?.headers as Record<string, string>;
  assert.match(headers["authorization"], /^Bearer /);
  assert.equal(captured.url, "https://test/api/v1/attachments/abc/blob");
});

test("ReplClient.fetchBlob: throws ReplUnauthorizedError on 401", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response("{}", { status: 401 });
  const client = new ReplClient({ bearer: () => null, fetchImpl: fakeFetch });
  await assert.rejects(client.fetchBlob("/api/v1/attachments/abc/blob"), ReplUnauthorizedError);
});

test("ReplClient.fetchBlob: throws on non-2xx, non-401", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response("{}", { status: 404 });
  const client = new ReplClient({ bearer: () => "x".repeat(64), fetchImpl: fakeFetch });
  await assert.rejects(
    client.fetchBlob("/api/v1/attachments/missing/blob"),
    /blob fetch failed: 404/,
  );
});

```
