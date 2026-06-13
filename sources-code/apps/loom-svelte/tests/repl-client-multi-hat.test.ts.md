---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-client-multi-hat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.067526+00:00
---

# apps/loom-svelte/tests/repl-client-multi-hat.test.ts

```ts
// D-O5.followup-8 — ReplClient + multi-hat session integration tests.
//
// Asserts that ReplClient (when constructed without an explicit
// `bearer` callback) reads from the active HatSession on every
// `send`, supports a hat-switch mid-flight, surfaces 401 by
// auto-removing the active session from the store, and uses the
// active session's `brainBaseUrl` over the constructor's `baseUrl`.
//
// Run via `bun test --timeout 10000 tests/repl-client-multi-hat.test.ts`.

import { test, beforeEach } from "node:test";
import { strict as assert } from "node:assert";

interface FakeLocalStorage {
  data: Map<string, string>;
  getItem: (k: string) => string | null;
  setItem: (k: string, v: string) => void;
  removeItem: (k: string) => void;
  clear: () => void;
}

function makeFakeLocalStorage(): FakeLocalStorage {
  const data = new Map<string, string>();
  return {
    data,
    getItem: (k) => (data.has(k) ? (data.get(k) as string) : null),
    setItem: (k, v) => {
      data.set(k, v);
    },
    removeItem: (k) => {
      data.delete(k);
    },
    clear: () => data.clear(),
  };
}

beforeEach(() => {
  delete (globalThis as Record<string, unknown>).localStorage;
});

// ── send uses active session's bearer ──────────────────────────────

test("send: rides on the active session's bearer when no explicit bearer is provided", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  sessions.addSession({
    id: "sess-tradie",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "cert1",
    bearer: "a".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });

  let captured: { headers?: Record<string, string> } = {};
  const fakeFetch: typeof fetch = async (_url, init) => {
    captured = { headers: init?.headers as Record<string, string> };
    return new Response('{"result":"ok","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const { ReplClient } = await import("../src/lib/repl-client");
  const client = new ReplClient({ fetchImpl: fakeFetch });
  await client.send("status");

  assert.equal(captured.headers?.["authorization"], `Bearer ${"a".repeat(64)}`);
});

// ── send with no active session throws ReplUnauthorizedError ──────

test("send: throws ReplUnauthorizedError-style 401 when no active session is paired", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  // No session added — getActiveSession returns null; the request
  // omits the Authorization header; the brain rejects with 401.

  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"missing bearer token"}', {
      status: 401,
      headers: { "content-type": "application/json" },
    });

  const { ReplClient, ReplUnauthorizedError } = await import("../src/lib/repl-client");
  const client = new ReplClient({ fetchImpl: fakeFetch });
  await assert.rejects(client.send("status"), ReplUnauthorizedError);
});

// ── 401 response auto-removes the session ─────────────────────────

test("send: 401 response auto-removes the active session from the store", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  sessions.addSession({
    id: "sess-revoked",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "",
    bearer: "b".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });

  const fakeFetch: typeof fetch = async () =>
    new Response('{"error":"bearer revoked"}', { status: 401 });

  const { ReplClient, ReplUnauthorizedError } = await import("../src/lib/repl-client");
  const client = new ReplClient({ fetchImpl: fakeFetch });
  await assert.rejects(client.send("status"), ReplUnauthorizedError);
  // Session no longer in the store.
  assert.equal(sessions.getActiveSession(), null);
});

// ── Hat switch takes effect on the next call ──────────────────────

test("send: hat switch takes effect on the next call (no client rebind)", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  sessions.addSession({
    id: "sess-A",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "",
    bearer: "a".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });
  sessions.addSession({
    id: "sess-B",
    hatId: "pm",
    hatName: "PM",
    certId: "",
    bearer: "b".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 200,
    lastUsedAt: 200,
  });
  // sess-A is active by default (first add).

  const seenAuth: string[] = [];
  const fakeFetch: typeof fetch = async (_url, init) => {
    const headers = init?.headers as Record<string, string>;
    seenAuth.push(headers["authorization"] ?? "");
    return new Response('{"result":"","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const { ReplClient } = await import("../src/lib/repl-client");
  const client = new ReplClient({ fetchImpl: fakeFetch });

  await client.send("first call as Tradie");
  // Switch to PM hat.
  sessions.setActive("sess-B");
  await client.send("second call as PM");

  assert.equal(seenAuth[0], `Bearer ${"a".repeat(64)}`);
  assert.equal(seenAuth[1], `Bearer ${"b".repeat(64)}`);
});

// ── send uses the active session's brainBaseUrl when set ──────────

test("send: per-hat brainBaseUrl overrides the constructor's baseUrl", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  sessions.addSession({
    id: "sess-acme",
    hatId: "tradie",
    hatName: "Tradie @ Acme",
    certId: "",
    bearer: "c".repeat(64),
    brainBaseUrl: "https://acme.example",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });

  let capturedUrl = "";
  const fakeFetch: typeof fetch = async (url) => {
    capturedUrl = url.toString();
    return new Response('{"result":"","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const { ReplClient } = await import("../src/lib/repl-client");
  const client = new ReplClient({ fetchImpl: fakeFetch, baseUrl: "https://wrong-origin.example" });
  await client.send("status");
  assert.equal(capturedUrl, "https://acme.example/api/v1/repl");
});

// ── Backward compat: explicit bearer callback still wins ──────────

test("send: explicit bearer callback still wins over the active session", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;

  const sessions = await import("../src/lib/hat-sessions");
  sessions._resetSessionsForTests();
  sessions.addSession({
    id: "sess-ignored",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "",
    bearer: "f".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });

  let captured: { headers?: Record<string, string> } = {};
  const fakeFetch: typeof fetch = async (_url, init) => {
    captured = { headers: init?.headers as Record<string, string> };
    return new Response('{"result":"","exit":"continue"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const { ReplClient } = await import("../src/lib/repl-client");
  const client = new ReplClient({
    bearer: () => "1".repeat(64),
    fetchImpl: fakeFetch,
  });
  await client.send("status");
  // Explicit bearer wins; session bearer ignored.
  assert.equal(captured.headers?.["authorization"], `Bearer ${"1".repeat(64)}`);
});

```
