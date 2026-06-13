---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/hat-sessions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.082459+00:00
---

# apps/loom-svelte/src/lib/hat-sessions.ts

```ts
// D-O5.followup-8 — Multi-hat session store for the loom-svelte helm.
//
// Until this PR the helm SPA carried exactly one bearer token in
// `localStorage["helm.bearer"]` (D-O5.followup-2 dual-cookie path).
// An operator wearing multiple hats — e.g. a tradie hat + PM hat per
// the D-O11 federation work — had to log out / re-pair / open a
// second browser to switch contexts.  This module replaces the
// single-bearer model with a typed multi-hat session list:
//
//   • Each `HatSession` records a hat's bearer token + cert id +
//     operator-friendly name + the brain origin it was paired
//     against + first-paired-at + last-used-at timestamps.
//   • Sessions persist as a single JSON object under
//     `localStorage["helm.hat-sessions.v1"]` (versioned key so a
//     future schema rev can migrate cleanly).
//   • Exactly one session is "active" at a time — `activeId` indexes
//     into the list.  `getActiveSession` is the read seam ReplClient
//     uses on every call so a hat switch takes effect immediately on
//     the next REPL call without rebinding the client.
//   • Each session optionally carries an operator-picked
//     `colorHex` — the App.svelte top-nav strip tints to that color
//     so the operator always knows which hat they're acting under.
//
// Backward compat — `helm.bearer` migration: on first load, if the
// legacy single-bearer entry exists, we promote it as a session
// (hatId / hatName stub'd to "default" / "Default" because the
// pre-followup-8 SPA never knew which hat the bearer represented;
// the operator can rename via the HatSwitcher dropdown, or the next
// `/api/v1/info` round-trip will populate the real values via the
// new `hat` block — D-O5.followup-8 brain side).
//
// Typing intentionally stays close to the wire shape so the
// HatSwitcher dropdown can render every field without further
// transformation.

import { writable, type Readable } from "svelte/store";

/// Storage key for the multi-hat session list.  Versioned so a
/// schema rev can migrate cleanly via a `helm.hat-sessions.v2` cutover.
export const HAT_SESSIONS_STORAGE_KEY = "helm.hat-sessions.v1";

/// Legacy single-bearer key from D-O5.followup-2.  Read once on first
/// load, promoted into a default `HatSession`, then deleted from
/// localStorage so subsequent loads don't re-import.
export const LEGACY_BEARER_STORAGE_KEY = "helm.bearer";

/// One paired hat, identified by its bearer token + cert id.  The
/// fields below mirror the `hat` block in `/api/v1/info` (brain side
/// also extended in D-O5.followup-8) so the helm can populate them
/// via a one-shot `/api/v1/info` call after pairing.
export interface HatSession {
  /// Client-generated UUIDv4 — stable across renames so React/Svelte
  /// keys don't churn when the operator edits `hatName`.
  id: string;
  /// Hat id from the cert (cert.context_tag namespace).  Stub'd to
  /// "default" for the legacy-bearer migration path; real value
  /// arrives from `/api/v1/info.hat.id` post-migration.
  hatId: string;
  /// Operator-friendly display name shown in the HatSwitcher
  /// dropdown.  Defaults to the cert label or "Default" for legacy.
  hatName: string;
  /// 32-hex cert id this bearer was minted under.  Empty until the
  /// `/api/v1/info` round-trip resolves.
  certId: string;
  /// 64-hex bearer token used for the `Authorization: Bearer ...`
  /// header.  Required.
  bearer: string;
  /// Brain origin this bearer was issued by — used by ReplClient as
  /// `baseUrl`.  Same-origin deploys leave this empty (the SPA's
  /// `window.location.host` is implied).
  brainBaseUrl: string;
  /// Per-hat tint shown in the App.svelte top-nav strip.  Operator
  /// can pick any hex; defaults to the theme primary color resolved
  /// at first add.  Optional — empty string means "use theme primary".
  colorHex: string;
  /// Unix-ms the hat was first paired with this helm.
  loggedInAt: number;
  /// Unix-ms the hat last issued a REPL call.  Bumped by ReplClient on
  /// every `send`.  Used by the dropdown to sort least-recently-used
  /// to the bottom + by `removeSession` to pick the new active hat.
  lastUsedAt: number;
}

/// Persisted store shape.  `activeId` is null in the "no hat paired"
/// state (the SPA renders the auth-challenge stub).
export interface HatSessionStore {
  sessions: HatSession[];
  activeId: string | null;
}

/// Empty store — the value the SPA boots with on a fresh browser
/// (no localStorage entry, no legacy bearer).
export const EMPTY_STORE: HatSessionStore = { sessions: [], activeId: null };

// ─────────────────────────────────────────────────────────────────────
// Internal — Svelte writable mirroring the persisted state
// ─────────────────────────────────────────────────────────────────────

const internal = writable<HatSessionStore>({ ...EMPTY_STORE });

/// Public read-only handle.  Components subscribe via `$hatSessions`
/// to get reactive updates when sessions are added / removed / the
/// active id changes.  Mutators below all `internal.set(...)` to
/// keep the store coherent.
export const hatSessions: Readable<HatSessionStore> = {
  subscribe: internal.subscribe,
};

// ─────────────────────────────────────────────────────────────────────
// Persistence helpers
// ─────────────────────────────────────────────────────────────────────

/// Read the store from localStorage.  Performs the one-time migration
/// from `helm.bearer` (D-O5.followup-2 single-bearer key) the first
/// time it sees no `helm.hat-sessions.v1` entry but a populated
/// legacy entry.
export function loadSessions(): HatSessionStore {
  if (typeof localStorage === "undefined") return { ...EMPTY_STORE };

  const raw = localStorage.getItem(HAT_SESSIONS_STORAGE_KEY);
  if (raw !== null) {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (isValidStore(parsed)) {
        internal.set(parsed);
        return parsed;
      }
    } catch {
      // Corrupted JSON — fall through to migration / empty.
    }
  }

  // Migration: legacy `helm.bearer` → single default HatSession.
  const legacyBearer = localStorage.getItem(LEGACY_BEARER_STORAGE_KEY);
  if (legacyBearer !== null && legacyBearer.length === 64) {
    const now = Date.now();
    const session: HatSession = {
      id: generateId(),
      hatId: "default",
      hatName: "Default",
      certId: "",
      bearer: legacyBearer,
      brainBaseUrl: "",
      colorHex: "",
      loggedInAt: now,
      lastUsedAt: now,
    };
    const store: HatSessionStore = {
      sessions: [session],
      activeId: session.id,
    };
    saveSessions(store);
    // Wipe the legacy key so subsequent loads don't re-import (idempotent
    // — we own the new storage shape now).
    localStorage.removeItem(LEGACY_BEARER_STORAGE_KEY);
    return store;
  }

  internal.set({ ...EMPTY_STORE });
  return { ...EMPTY_STORE };
}

/// Persist the store to localStorage + push it to the Svelte writable.
/// Always go through this seam (don't mutate `internal` directly) so
/// the on-disk and in-memory views stay in sync.
export function saveSessions(state: HatSessionStore): void {
  if (typeof localStorage !== "undefined") {
    localStorage.setItem(HAT_SESSIONS_STORAGE_KEY, JSON.stringify(state));
  }
  internal.set(state);
}

/// Add a new session.  If no session is currently active, the new
/// one becomes active.  Idempotent on `id` — adding a session with
/// an id already in the list replaces it (covers the "operator
/// re-pairs the same hat" path).
export function addSession(session: HatSession): void {
  const state = loadCurrent();
  const filtered = state.sessions.filter((s) => s.id !== session.id);
  const next: HatSessionStore = {
    sessions: [...filtered, session],
    activeId: state.activeId ?? session.id,
  };
  saveSessions(next);
}

/// Remove a session by id.  If the removed session was active,
/// `activeId` re-points to the most-recently-used remaining session
/// (or null if none remain).
export function removeSession(id: string): void {
  const state = loadCurrent();
  const remaining = state.sessions.filter((s) => s.id !== id);
  let nextActive: string | null = state.activeId;
  if (state.activeId === id) {
    if (remaining.length === 0) {
      nextActive = null;
    } else {
      // Sort by lastUsedAt desc + pick the head.
      const sorted = [...remaining].sort((a, b) => b.lastUsedAt - a.lastUsedAt);
      nextActive = sorted[0].id;
    }
  }
  saveSessions({ sessions: remaining, activeId: nextActive });
}

/// Mark the named session as active.  No-op if the id isn't in the
/// list (defensive — the dropdown could race a remove).
export function setActive(id: string): void {
  const state = loadCurrent();
  const exists = state.sessions.some((s) => s.id === id);
  if (!exists) return;
  saveSessions({ ...state, activeId: id });
}

/// Read the currently active session, or null if none is active.
/// ReplClient calls this on every `send` so a hat switch takes
/// effect immediately on the next REPL call — no client rebind needed.
export function getActiveSession(): HatSession | null {
  const state = loadCurrent();
  if (state.activeId === null) return null;
  return state.sessions.find((s) => s.id === state.activeId) ?? null;
}

/// Bump the named session's `lastUsedAt` to `Date.now()`.  Called by
/// ReplClient at the top of every `send`; the dropdown uses the
/// timestamp to sort + the remove-active fallback uses it to pick
/// the new active hat.
export function bumpLastUsed(id: string): void {
  const state = loadCurrent();
  const idx = state.sessions.findIndex((s) => s.id === id);
  if (idx < 0) return;
  const updated = { ...state.sessions[idx], lastUsedAt: Date.now() };
  const sessions = [...state.sessions];
  sessions[idx] = updated;
  saveSessions({ ...state, sessions });
}

/// Update fields on an existing session in-place (e.g. populate
/// `hatName` / `hatId` / `certId` from a successful `/api/v1/info`
/// round-trip).  No-op if the id isn't in the list.
export function updateSession(id: string, patch: Partial<HatSession>): void {
  const state = loadCurrent();
  const idx = state.sessions.findIndex((s) => s.id === id);
  if (idx < 0) return;
  const merged = { ...state.sessions[idx], ...patch, id: state.sessions[idx].id };
  const sessions = [...state.sessions];
  sessions[idx] = merged;
  saveSessions({ ...state, sessions });
}

/// Generate a UUIDv4 client-side.  Uses `crypto.randomUUID` when
/// available; otherwise falls back to a Math.random-backed shape.
/// Tests inject a deterministic id via `addSession({ id: ... })`.
export function generateId(): string {
  if (
    typeof crypto !== "undefined" &&
    typeof (crypto as { randomUUID?: () => string }).randomUUID === "function"
  ) {
    return (crypto as { randomUUID: () => string }).randomUUID();
  }
  // RFC4122-shaped fallback.
  const hex = (n: number) =>
    Math.floor(Math.random() * Math.pow(16, n))
      .toString(16)
      .padStart(n, "0");
  return `${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}`;
}

// ─────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────

/// Read the latest persisted state.  Prefers localStorage so cross-tab
/// updates are observed (the dropdown writes; another tab's
/// ReplClient reads).  When localStorage is unavailable (SSR / Node
/// tests pre-stub) we fall back to the in-memory writable.
function loadCurrent(): HatSessionStore {
  if (typeof localStorage === "undefined") {
    let snapshot: HatSessionStore = { ...EMPTY_STORE };
    internal.subscribe((s) => {
      snapshot = s;
    })();
    return snapshot;
  }
  const raw = localStorage.getItem(HAT_SESSIONS_STORAGE_KEY);
  if (raw === null) return { ...EMPTY_STORE };
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (isValidStore(parsed)) return parsed;
  } catch {
    // fallthrough
  }
  return { ...EMPTY_STORE };
}

function isValidStore(v: unknown): v is HatSessionStore {
  if (!v || typeof v !== "object") return false;
  const o = v as { sessions?: unknown; activeId?: unknown };
  if (!Array.isArray(o.sessions)) return false;
  if (o.activeId !== null && typeof o.activeId !== "string") return false;
  for (const s of o.sessions) {
    if (!s || typeof s !== "object") return false;
    const r = s as Record<string, unknown>;
    if (typeof r.id !== "string") return false;
    if (typeof r.bearer !== "string") return false;
    if (typeof r.hatName !== "string") return false;
  }
  return true;
}

/// Test-only — reset the store to empty, clearing localStorage.  Used
/// by tests/hat-sessions.test.ts between cases.
export function _resetSessionsForTests(): void {
  if (typeof localStorage !== "undefined") {
    localStorage.removeItem(HAT_SESSIONS_STORAGE_KEY);
    localStorage.removeItem(LEGACY_BEARER_STORAGE_KEY);
  }
  internal.set({ ...EMPTY_STORE });
}

```
