---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/theme-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.081341+00:00
---

# apps/loom-svelte/src/lib/theme-store.ts

```ts
// D-O5.followup-6 — per-tenant theme store for the loom-svelte helm.
//
// Reads the resolved theme from `GET /api/v1/info` (the brain
// substitutes canonical defaults inline when `[theme]` is absent in
// the tenant manifest, so callers never need to know defaults — they
// just take what they're given).  Applies the result to the document:
//   • CSS custom properties on `:root` (`--color-primary`,
//     `--color-accent`, `--theme-font-family`) — the migrated stylesheet
//     reads these for top-nav background, primary-button color, link
//     color, etc.
//   • `data-mode` attribute on `<html>` — `light` / `dark` / `auto`
//     (auto follows the OS via `matchMedia('(prefers-color-scheme:
//     dark)')`).
//   • The logo URL is exposed through the store; App.svelte renders it
//     in the nav header when set.
//
// Pure-data design: the store never holds DOM references.
// `applyThemeToDocument` accepts an optional `Document` so tests can
// pass a JSDOM-shaped fake.  `loadTheme` accepts an optional
// `fetchImpl` so tests can drive the network round-trip without
// global-fetch monkey-patching.

import { writable, type Readable } from "svelte/store";

/// Wire shape of the `theme` block returned by `/api/v1/info`.
export interface Theme {
  primaryHex: string;
  accentHex: string;
  /// `null` when no logo is configured.
  logoUrl: string | null;
  fontFamily: "system" | "serif" | "mono" | string;
  mode: "light" | "dark" | "auto";
}

/// Canonical defaults — kept in sync with `tenant_manifest.zig`'s
/// `THEME_DEFAULT_*` constants.  When `/api/v1/info` is reachable the
/// brain substitutes its own defaults inline so we never read these in
/// the happy path; they exist so the store has a sensible initial
/// value before the first `loadTheme()` call resolves and so a network
/// failure doesn't leave the helm rendering blank.
export const DEFAULT_THEME: Theme = {
  primaryHex: "#7fd9ff",
  accentHex: "#ffb24a",
  logoUrl: null,
  fontFamily: "system",
  mode: "dark",
};

const internal = writable<Theme>(DEFAULT_THEME);

/// Public read-only handle.  Components call `$theme` (Svelte's reactive
/// auto-subscribe) to render against the current theme.
export const theme: Readable<Theme> = {
  subscribe: internal.subscribe,
};

/// Resolve a CSS font-family declaration from the theme's `fontFamily`
/// shorthand (or pass through an arbitrary CSS font-stack as-is).
export function fontFamilyCss(t: Pick<Theme, "fontFamily">): string {
  switch (t.fontFamily) {
    case "system":
      return 'ui-sans-serif, -apple-system, system-ui, sans-serif';
    case "serif":
      return 'ui-serif, Georgia, "Times New Roman", serif';
    case "mono":
      return 'ui-monospace, "SF Mono", Menlo, Consolas, monospace';
    default:
      // Operator-supplied free-form font stack — passed through as-is.
      return t.fontFamily;
  }
}

/// Resolve `mode: 'auto'` against the OS preference.  Used by
/// `applyThemeToDocument` to decide which `data-mode` to render.
export function effectiveMode(
  mode: Theme["mode"],
  matchMedia?: (q: string) => { matches: boolean },
): "light" | "dark" {
  if (mode === "light" || mode === "dark") return mode;
  // auto — follow the OS.
  if (typeof matchMedia === "function") {
    const m = matchMedia("(prefers-color-scheme: dark)");
    return m.matches ? "dark" : "light";
  }
  // Headless / no-matchMedia — fall back to dark (loom-svelte's
  // historical default was `color-scheme: dark`).
  return "dark";
}

/// Mutate `document` to reflect the supplied theme.  Sets the
/// `--color-primary` / `--color-accent` / `--theme-font-family` CSS
/// custom properties on `:root`, and the `data-mode` attribute on
/// `<html>`.  Idempotent.
export function applyThemeToDocument(
  t: Theme,
  doc?: Document,
  matchMedia?: (q: string) => { matches: boolean },
): void {
  const d = doc ?? (typeof document !== "undefined" ? document : undefined);
  if (!d) return;
  const root = d.documentElement;
  if (!root) return;
  root.style.setProperty("--color-primary", t.primaryHex);
  root.style.setProperty("--color-accent", t.accentHex);
  root.style.setProperty("--color-linear", t.accentHex);
  root.style.setProperty("--theme-font-family", fontFamilyCss(t));
  const mm =
    matchMedia ??
    (typeof window !== "undefined" && typeof window.matchMedia === "function"
      ? window.matchMedia.bind(window)
      : undefined);
  root.setAttribute("data-mode", effectiveMode(t.mode, mm));
}

/// Parse the `theme` block out of a `/api/v1/info` response payload.
/// Tolerant of missing fields (substitutes canonical defaults) so a
/// future brain that adds new theme properties doesn't break older
/// helms.
export function parseInfoThemeBlock(payload: unknown): Theme {
  const t = (payload as { theme?: Record<string, unknown> } | undefined)?.theme;
  if (!t || typeof t !== "object") return { ...DEFAULT_THEME };
  const primaryHex =
    typeof t.primary_hex === "string" ? t.primary_hex : DEFAULT_THEME.primaryHex;
  const accentHex =
    typeof t.accent_hex === "string" ? t.accent_hex : DEFAULT_THEME.accentHex;
  const logoUrl =
    typeof t.logo_url === "string" && t.logo_url.length > 0 ? t.logo_url : null;
  const fontFamily =
    typeof t.font_family === "string" && t.font_family.length > 0
      ? (t.font_family as Theme["fontFamily"])
      : DEFAULT_THEME.fontFamily;
  const modeRaw = typeof t.mode === "string" ? t.mode : DEFAULT_THEME.mode;
  const mode: Theme["mode"] =
    modeRaw === "light" || modeRaw === "dark" || modeRaw === "auto"
      ? modeRaw
      : DEFAULT_THEME.mode;
  return { primaryHex, accentHex, logoUrl, fontFamily, mode };
}

/// Fetch the theme from the brain's `/api/v1/info` endpoint and apply
/// it.  `brainBaseUrl` is the brain's origin (e.g. `https://acme.example`);
/// `bearer` is the helm session bearer.  Returns the resolved theme
/// after applying it to the document.
///
/// On any failure (network error, 401, malformed body) the store is
/// left at its current value and the error is rethrown — the caller
/// (App.svelte) decides whether to surface it to the operator.
export async function loadTheme(
  brainBaseUrl: string,
  bearer: string,
  opts?: {
    fetchImpl?: typeof fetch;
    doc?: Document;
    matchMedia?: (q: string) => { matches: boolean };
  },
): Promise<Theme> {
  const fetchImpl = opts?.fetchImpl ?? fetch;
  const url = `${brainBaseUrl.replace(/\/$/, "")}/api/v1/info`;
  const resp = await fetchImpl(url, {
    method: "GET",
    headers: { authorization: `Bearer ${bearer}` },
  });
  if (!resp.ok) {
    throw new Error(`/api/v1/info ${resp.status}`);
  }
  const body = await resp.json();
  const t = parseInfoThemeBlock(body);
  internal.set(t);
  applyThemeToDocument(t, opts?.doc, opts?.matchMedia);
  return t;
}

/// Test-only — overwrite the store value directly.  Used by component
/// tests that assert the `$theme` reactive subscription downstream.
export function _setThemeForTest(t: Theme): void {
  internal.set(t);
}

```
