---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/theme-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.059660+00:00
---

# apps/loom-svelte/tests/theme-store.test.ts

```ts
// D-O5.followup-6 — theme-store unit tests.
//
// Covers parseInfoThemeBlock + loadTheme + applyThemeToDocument +
// effectiveMode against a mocked fetch + a JSDOM-shaped fake document.
// The Svelte writable subscribe path is exercised through loadTheme.
//
// Run via `bun test tests/theme-store.test.ts --timeout 10000` (or via
// node --test --import tsx — the suite uses node:test).

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  DEFAULT_THEME,
  applyThemeToDocument,
  effectiveMode,
  fontFamilyCss,
  loadTheme,
  parseInfoThemeBlock,
  theme,
  _setThemeForTest,
} from "../src/lib/theme-store";

/// Build a minimal Document-shaped fake sufficient for
/// `applyThemeToDocument` (we only touch documentElement.style + setAttribute).
function makeFakeDocument(): {
  doc: Document;
  styles: Map<string, string>;
  attrs: Map<string, string>;
} {
  const styles = new Map<string, string>();
  const attrs = new Map<string, string>();
  const root = {
    style: {
      setProperty(name: string, value: string) {
        styles.set(name, value);
      },
    },
    setAttribute(name: string, value: string) {
      attrs.set(name, value);
    },
  };
  const doc = { documentElement: root } as unknown as Document;
  return { doc, styles, attrs };
}

// ── parseInfoThemeBlock ────────────────────────────────────────────

test("parseInfoThemeBlock: missing theme block → default theme", () => {
  const t = parseInfoThemeBlock({ shard_proxy_endpoint: null });
  assert.deepEqual(t, DEFAULT_THEME);
});

test("parseInfoThemeBlock: full block round-trips wire shape to camelCase", () => {
  const t = parseInfoThemeBlock({
    theme: {
      primary_hex: "#FF6F61",
      accent_hex: "#2EC4B6",
      logo_url: "/logo.svg",
      font_family: "serif",
      mode: "dark",
    },
  });
  assert.equal(t.primaryHex, "#FF6F61");
  assert.equal(t.accentHex, "#2EC4B6");
  assert.equal(t.logoUrl, "/logo.svg");
  assert.equal(t.fontFamily, "serif");
  assert.equal(t.mode, "dark");
});

test("parseInfoThemeBlock: logo_url null in JSON → store logoUrl=null", () => {
  const t = parseInfoThemeBlock({
    theme: {
      primary_hex: "#000000",
      accent_hex: "#FFFFFF",
      logo_url: null,
      font_family: "system",
      mode: "auto",
    },
  });
  assert.equal(t.logoUrl, null);
});

test("parseInfoThemeBlock: invalid mode → falls back to default 'auto'", () => {
  const t = parseInfoThemeBlock({
    theme: {
      primary_hex: "#000000",
      accent_hex: "#FFFFFF",
      logo_url: null,
      font_family: "system",
      mode: "high-contrast",
    },
  });
  assert.equal(t.mode, "auto");
});

// ── effectiveMode ──────────────────────────────────────────────────

test("effectiveMode: 'light' / 'dark' pass through unchanged", () => {
  assert.equal(effectiveMode("light"), "light");
  assert.equal(effectiveMode("dark"), "dark");
});

test("effectiveMode: 'auto' + matchMedia(dark)=true → 'dark'", () => {
  const mm = (q: string) => ({ matches: q.includes("dark") });
  assert.equal(effectiveMode("auto", mm), "dark");
});

test("effectiveMode: 'auto' + matchMedia(dark)=false → 'light'", () => {
  const mm = (_q: string) => ({ matches: false });
  assert.equal(effectiveMode("auto", mm), "light");
});

// ── fontFamilyCss ──────────────────────────────────────────────────

test("fontFamilyCss: shorthand 'system' → ui-sans-serif stack", () => {
  const css = fontFamilyCss({ fontFamily: "system" });
  assert.match(css, /ui-sans-serif/);
});

test("fontFamilyCss: arbitrary stack passes through unchanged", () => {
  const css = fontFamilyCss({ fontFamily: "Roboto, sans-serif" });
  assert.equal(css, "Roboto, sans-serif");
});

// ── applyThemeToDocument ───────────────────────────────────────────

test("applyThemeToDocument: sets --color-primary / --color-accent CSS vars", () => {
  const { doc, styles } = makeFakeDocument();
  applyThemeToDocument(
    {
      primaryHex: "#FF0000",
      accentHex: "#00FF00",
      logoUrl: null,
      fontFamily: "system",
      mode: "light",
    },
    doc,
    () => ({ matches: false }),
  );
  assert.equal(styles.get("--color-primary"), "#FF0000");
  assert.equal(styles.get("--color-accent"), "#00FF00");
  assert.match(styles.get("--theme-font-family") ?? "", /ui-sans-serif/);
});

test("applyThemeToDocument: sets data-mode based on auto + matchMedia", () => {
  const { doc, attrs } = makeFakeDocument();
  applyThemeToDocument(
    { ...DEFAULT_THEME, mode: "auto" },
    doc,
    (q) => ({ matches: q.includes("dark") }),
  );
  assert.equal(attrs.get("data-mode"), "dark");
});

test("applyThemeToDocument: explicit dark wins over matchMedia", () => {
  const { doc, attrs } = makeFakeDocument();
  applyThemeToDocument(
    { ...DEFAULT_THEME, mode: "light" },
    doc,
    () => ({ matches: true }),
  );
  assert.equal(attrs.get("data-mode"), "light");
});

// ── loadTheme: end-to-end with mocked fetch ────────────────────────

test("loadTheme: fetches /api/v1/info and applies the resolved theme", async () => {
  const calls: Array<{ url: string; bearer: string }> = [];
  const fakeFetch: typeof fetch = async (url, init) => {
    calls.push({
      url: String(url),
      bearer: (init?.headers as Record<string, string>)?.["authorization"] ?? "",
    });
    return new Response(
      JSON.stringify({
        shard_proxy_endpoint: null,
        shard_group_id: "",
        brain_pin_cert_id: "abcd",
        brain_pin_pubkey: "02" + "aa".repeat(32),
        server_version: "brain 0.1.0",
        theme: {
          primary_hex: "#4F46E5",
          accent_hex: "#10B981",
          logo_url: "/logo.svg",
          font_family: "serif",
          mode: "dark",
        },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  const { doc, styles, attrs } = makeFakeDocument();
  const t = await loadTheme("https://acme.example", "deadbeef".repeat(8), {
    fetchImpl: fakeFetch,
    doc,
    matchMedia: () => ({ matches: false }),
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://acme.example/api/v1/info");
  assert.equal(calls[0].bearer, `Bearer ${"deadbeef".repeat(8)}`);
  assert.equal(t.primaryHex, "#4F46E5");
  assert.equal(t.logoUrl, "/logo.svg");
  assert.equal(styles.get("--color-primary"), "#4F46E5");
  assert.equal(attrs.get("data-mode"), "dark");
});

test("loadTheme: brain returned no theme block → default theme applied", async () => {
  const fakeFetch: typeof fetch = async () =>
    new Response(JSON.stringify({ server_version: "brain 0.1.0" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  const { doc, styles } = makeFakeDocument();
  const t = await loadTheme("https://acme.example", "x".repeat(64), {
    fetchImpl: fakeFetch,
    doc,
    matchMedia: () => ({ matches: false }),
  });
  assert.deepEqual(t, DEFAULT_THEME);
  assert.equal(styles.get("--color-primary"), DEFAULT_THEME.primaryHex);
});

test("loadTheme: 401 from brain → throws and leaves store unchanged", async () => {
  // Seed the store with a known good value so we can assert it didn't
  // mutate when the network call fails.
  _setThemeForTest({ ...DEFAULT_THEME, primaryHex: "#SENTINEL" });
  const fakeFetch: typeof fetch = async () =>
    new Response(JSON.stringify({ error: "unauthorised" }), { status: 401 });
  await assert.rejects(
    () =>
      loadTheme("https://acme.example", "bad", {
        fetchImpl: fakeFetch,
      }),
    /401/,
  );
  let observed: { primaryHex: string } = { primaryHex: "" };
  const unsub = theme.subscribe((t) => {
    observed = t;
  });
  unsub();
  assert.equal(observed.primaryHex, "#SENTINEL");
});

test("theme store: subscribe yields the current value synchronously", () => {
  _setThemeForTest({ ...DEFAULT_THEME, accentHex: "#ABCDEF" });
  let observed: { accentHex: string } = { accentHex: "" };
  const unsub = theme.subscribe((t) => {
    observed = t;
  });
  unsub();
  assert.equal(observed.accentHex, "#ABCDEF");
});

```
