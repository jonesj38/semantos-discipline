---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/repl-client-bearer-cookie.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.066594+00:00
---

# apps/loom-svelte/tests/repl-client-bearer-cookie.test.ts

```ts
// D-O5.followup-2 — bearer-cookie capture in repl-client's
// `getStoredBearer`.
//
// The brain-side `/auth/callback` now mints a bearer alongside the
// session cookie and writes it as a non-HttpOnly
// `__semantos_helm_bearer` cookie (SameSite=Lax).  On first SPA load
// `getStoredBearer` reads the cookie, promotes it into localStorage,
// and clears the cookie — so the bearer rides on the wire for one
// round-trip and never lives in URL history / Referer headers.
//
// These tests stub `localStorage` + `document` to mock the browser
// surfaces in Node's test runner.  Same harness as repl-client.test.ts
// (`node --test --import tsx`).
//
// Coverage:
//   1. cookie path:        first call reads the cookie + promotes
//   2. cookie clear:       the cookie is cleared after read
//   3. cached path:        subsequent calls hit localStorage, no DOM read
//   4. backward-compat:    legacy ?bearer=... still flows via captureBearerFromUrl
//   5. cookie-absent path: no cookie + no localStorage → null

import { test, beforeEach } from "node:test";
import { strict as assert } from "node:assert";

// Helpers — stub `localStorage` + `document.cookie` on globalThis
// before importing the module under test, so module-load-time checks
// (`typeof localStorage`) see the stubs.

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
    getItem: (k: string) => (data.has(k) ? (data.get(k) as string) : null),
    setItem: (k: string, v: string) => {
      data.set(k, v);
    },
    removeItem: (k: string) => {
      data.delete(k);
    },
    clear: () => data.clear(),
  };
}

// `document.cookie` mocked as a settable property — assignments to
// `document.cookie = "name=value; ..."` don't *replace* the jar in a
// real browser (each assignment merges/expires individual cookies).
// For the test, we mimic the relevant sliver: set "name=" + Max-Age=0
// removes the cookie; otherwise it appends.  This is enough to cover
// the cookie-clear path the production code exercises.
interface FakeDocument {
  cookieJar: Map<string, string>;
  // Property accessors set up in `installFakeDocument`.
  cookie: string;
}

function installFakeDocument(initialCookies: Record<string, string> = {}): FakeDocument {
  const jar = new Map<string, string>(Object.entries(initialCookies));
  const fake = { cookieJar: jar } as FakeDocument;
  Object.defineProperty(fake, "cookie", {
    get(): string {
      return Array.from(jar.entries())
        .map(([k, v]) => `${k}=${v}`)
        .join("; ");
    },
    set(line: string) {
      // Parse "<name>=<value>; <attr>=<...>; ..." — only the first
      // pair is the cookie itself.  If Max-Age=0 (or expires-in-past),
      // remove; else upsert.
      const [head, ...rest] = line.split(";").map((s) => s.trim());
      const eq = head.indexOf("=");
      if (eq < 0) return;
      const name = head.slice(0, eq).trim();
      const value = head.slice(eq + 1).trim();
      const isExpired = rest.some((attr) => /^max-age=0$/i.test(attr));
      if (isExpired) {
        jar.delete(name);
      } else {
        jar.set(name, value);
      }
    },
    configurable: true,
  });
  return fake;
}

beforeEach(() => {
  // Reset globals for each test so they don't leak state.  The
  // stubs are installed per-test below where each test needs them.
  delete (globalThis as Record<string, unknown>).localStorage;
  delete (globalThis as Record<string, unknown>).document;
});

test("getStoredBearer: reads cookie on first call + promotes to localStorage", async () => {
  const fakeLS = makeFakeLocalStorage();
  const fakeDoc = installFakeDocument({
    "__semantos_helm_bearer": "deadbeef".repeat(8), // 64-hex
  });
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  (globalThis as Record<string, unknown>).document = fakeDoc;

  // Force a fresh import — the module reads `typeof localStorage` at
  // call time, not load time, so a single import is fine.
  const { getStoredBearer } = await import("../src/lib/repl-client");

  const bearer = getStoredBearer();
  assert.equal(bearer, "deadbeef".repeat(8));
  // Promoted to localStorage.
  assert.equal(fakeLS.getItem("helm.bearer"), "deadbeef".repeat(8));
});

test("getStoredBearer: clears the helm-bearer cookie after promoting", async () => {
  const fakeLS = makeFakeLocalStorage();
  const fakeDoc = installFakeDocument({
    "__semantos_helm_bearer": "feedface".repeat(8),
  });
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  (globalThis as Record<string, unknown>).document = fakeDoc;

  const { getStoredBearer } = await import("../src/lib/repl-client");
  getStoredBearer();
  // After read, the cookie jar no longer contains __semantos_helm_bearer.
  assert.equal(fakeDoc.cookieJar.has("__semantos_helm_bearer"), false);
});

test("getStoredBearer: subsequent calls hit localStorage cache (no cookie re-read)", async () => {
  const fakeLS = makeFakeLocalStorage();
  fakeLS.setItem("helm.bearer", "cafebabe".repeat(8));
  // A different value sits in the cookie jar — we should NOT read it
  // because localStorage already has a cached value.
  const fakeDoc = installFakeDocument({
    "__semantos_helm_bearer": "different".repeat(7) + "deadbeef".slice(0, 8),
  });
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  (globalThis as Record<string, unknown>).document = fakeDoc;

  const { getStoredBearer } = await import("../src/lib/repl-client");
  const bearer = getStoredBearer();
  assert.equal(bearer, "cafebabe".repeat(8));
  // Cookie still present — getStoredBearer didn't touch it because
  // localStorage hit short-circuited the cookie path.
  assert.equal(fakeDoc.cookieJar.has("__semantos_helm_bearer"), true);
});

test("getStoredBearer: returns null when no cookie + no cached value", async () => {
  const fakeLS = makeFakeLocalStorage();
  const fakeDoc = installFakeDocument({}); // empty cookie jar
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  (globalThis as Record<string, unknown>).document = fakeDoc;

  const { getStoredBearer } = await import("../src/lib/repl-client");
  assert.equal(getStoredBearer(), null);
});

test("captureBearerFromUrl: backward-compat — legacy ?bearer=... still seeds localStorage", async () => {
  const fakeLS = makeFakeLocalStorage();
  (globalThis as Record<string, unknown>).localStorage = fakeLS;
  // Stub `window` for captureBearerFromUrl.  Use a minimal URL +
  // history.replaceState shim — captureBearerFromUrl only needs
  // location.href + history.replaceState.
  const replaced: string[] = [];
  const fakeWindow = {
    location: {
      href: "https://helm.example/?bearer=abcd1234".repeat(1) + "abcd5678".repeat(7),
    },
    history: {
      replaceState: (_state: unknown, _title: string, url: string) => {
        replaced.push(url);
      },
    },
  };
  (globalThis as Record<string, unknown>).window = fakeWindow;

  const { captureBearerFromUrl } = await import("../src/lib/auth");
  const bearer = captureBearerFromUrl();
  // The legacy path strips the bearer from the URL and stores it.
  assert.notEqual(bearer, null);
  assert.equal(fakeLS.getItem("helm.bearer"), bearer);
  // The query-string was scrubbed on URL replacement.
  assert.equal(replaced.length, 1);
  assert.equal(replaced[0].includes("bearer="), false);

  delete (globalThis as Record<string, unknown>).window;
});

```
