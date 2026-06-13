---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/hat-sessions.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.064427+00:00
---

# apps/loom-svelte/tests/hat-sessions.test.ts

```ts
// D-O5.followup-8 — hat-sessions store unit tests.
//
// Drives the multi-hat localStorage-backed session store directly.
// Mirrors the harness pattern from
// tests/repl-client-bearer-cookie.test.ts: stub `localStorage` on
// globalThis before the module under test is imported, then exercise
// the public API.
//
// Coverage:
//   • addSession + activeId tracking (first add becomes active)
//   • removeSession + activeId reassigns to most-recently-used
//   • Migration from legacy `helm.bearer` localStorage key
//   • bumpLastUsed updates the timestamp
//   • Persistence across "page reload" (load → save → fresh load)
//   • setActive only flips `activeId` for known sessions
//
// Run via `bun test --timeout 10000 tests/hat-sessions.test.ts`.

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
  // Each test installs a fresh fake localStorage so cross-test state
  // doesn't bleed.  We delete the global between tests for hygiene.
  delete (globalThis as Record<string, unknown>).localStorage;
});

// ── addSession + activeId tracking ─────────────────────────────────

test("addSession: first add becomes active automatically", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  const session: import("../src/lib/hat-sessions").HatSession = {
    id: "sess-A",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "abc",
    bearer: "f".repeat(64),
    brainBaseUrl: "",
    colorHex: "#FF0000",
    loggedInAt: 100,
    lastUsedAt: 100,
  };
  mod.addSession(session);
  const active = mod.getActiveSession();
  assert.equal(active?.id, "sess-A");
  assert.equal(active?.hatName, "Tradie");
});

test("addSession: second add does NOT auto-switch the active hat", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
    id: "sess-A",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "",
    bearer: "f".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });
  mod.addSession({
    id: "sess-B",
    hatId: "pm",
    hatName: "PM",
    certId: "",
    bearer: "e".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 200,
    lastUsedAt: 200,
  });
  // First-add wins until the operator explicitly switches.
  assert.equal(mod.getActiveSession()?.id, "sess-A");
});

// ── removeSession ──────────────────────────────────────────────────

test("removeSession: active reassigns to most-recently-used remaining session", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
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
  mod.addSession({
    id: "sess-B",
    hatId: "pm",
    hatName: "PM",
    certId: "",
    bearer: "b".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 200,
    lastUsedAt: 500, // most-recently-used among non-A
  });
  mod.addSession({
    id: "sess-C",
    hatId: "ops",
    hatName: "Ops",
    certId: "",
    bearer: "c".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 300,
    lastUsedAt: 300,
  });
  // sess-A is still active (first add).  Removing sess-A should
  // reassign to sess-B (highest lastUsedAt of the remaining two).
  mod.removeSession("sess-A");
  assert.equal(mod.getActiveSession()?.id, "sess-B");
});

test("removeSession: removing the last session leaves activeId null", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
    id: "sess-only",
    hatId: "x",
    hatName: "X",
    certId: "",
    bearer: "1".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });
  mod.removeSession("sess-only");
  assert.equal(mod.getActiveSession(), null);
});

// ── Legacy bearer migration ────────────────────────────────────────

test("loadSessions: migrates legacy helm.bearer → single Default session", async () => {
  const fakeLS = makeFakeLocalStorage();
  fakeLS.setItem("helm.bearer", "deadbeef".repeat(8)); // 64 hex
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();
  // _resetSessionsForTests just cleared the legacy key; re-set it for the migration test.
  fakeLS.setItem("helm.bearer", "deadbeef".repeat(8));

  const store = mod.loadSessions();
  assert.equal(store.sessions.length, 1);
  assert.equal(store.sessions[0].hatName, "Default");
  assert.equal(store.sessions[0].hatId, "default");
  assert.equal(store.sessions[0].bearer, "deadbeef".repeat(8));
  assert.equal(store.activeId, store.sessions[0].id);
  // Legacy key wiped after migration.
  assert.equal(fakeLS.getItem("helm.bearer"), null);
});

test("loadSessions: ignores malformed legacy bearer (wrong length)", async () => {
  const fakeLS = makeFakeLocalStorage();
  fakeLS.setItem("helm.bearer", "tooshort"); // not 64 hex
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();
  fakeLS.setItem("helm.bearer", "tooshort");

  const store = mod.loadSessions();
  assert.equal(store.sessions.length, 0);
  assert.equal(store.activeId, null);
});

// ── bumpLastUsed ───────────────────────────────────────────────────

test("bumpLastUsed: updates the timestamp on the named session", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
    id: "sess-A",
    hatId: "tradie",
    hatName: "Tradie",
    certId: "",
    bearer: "f".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 100,
    lastUsedAt: 100,
  });
  const before = mod.getActiveSession()?.lastUsedAt ?? 0;
  // Sleep tick — Date.now() should move forward by at least 1ms in
  // any sane runtime; if the test runs fast the assertion below uses
  // `>=` not `>` so a same-ms call still passes the invariant.
  await new Promise((r) => setTimeout(r, 2));
  mod.bumpLastUsed("sess-A");
  const after = mod.getActiveSession()?.lastUsedAt ?? 0;
  assert.ok(after >= before, `expected after (${after}) >= before (${before})`);
  assert.notEqual(after, 100); // moved off the seed value
});

// ── Persistence across "page reload" ───────────────────────────────

test("persistence: saved sessions survive a fresh loadSessions call", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
    id: "sess-persist",
    hatId: "tradie",
    hatName: "Persistent Tradie",
    certId: "abcd",
    bearer: "9".repeat(64),
    brainBaseUrl: "https://acme.example",
    colorHex: "#123456",
    loggedInAt: 100,
    lastUsedAt: 200,
  });

  // Simulate page reload by re-reading from localStorage.
  const reloaded = mod.loadSessions();
  assert.equal(reloaded.sessions.length, 1);
  assert.equal(reloaded.sessions[0].id, "sess-persist");
  assert.equal(reloaded.sessions[0].hatName, "Persistent Tradie");
  assert.equal(reloaded.sessions[0].brainBaseUrl, "https://acme.example");
  assert.equal(reloaded.activeId, "sess-persist");
});

// ── setActive defensiveness ────────────────────────────────────────

test("setActive: ignores unknown ids (defensive — dropdown race)", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  const mod = await import("../src/lib/hat-sessions");
  mod._resetSessionsForTests();

  mod.addSession({
    id: "sess-A",
    hatId: "x",
    hatName: "X",
    certId: "",
    bearer: "1".repeat(64),
    brainBaseUrl: "",
    colorHex: "",
    loggedInAt: 0,
    lastUsedAt: 0,
  });
  mod.setActive("sess-MISSING");
  assert.equal(mod.getActiveSession()?.id, "sess-A");
});

```
