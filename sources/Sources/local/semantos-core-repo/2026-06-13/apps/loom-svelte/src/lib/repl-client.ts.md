---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/repl-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.083021+00:00
---

# apps/loom-svelte/src/lib/repl-client.ts

```ts
// D-O5 — REPL HTTP client for the helm SPA.
//
// Wraps `POST /api/v1/repl` (runtime/semantos-brain/src/repl_http.zig) with a
// strongly-typed surface. The endpoint is bearer-token-gated; the
// helm session-cookie flow (also D-O5) issues that token on
// successful identity-cert challenge sign and stores it in
// `localStorage["helm.bearer"]`.
//
// D-O5.followup-2 — bearer-mint at /auth/callback.  The brain
// auth-callback now sets `Set-Cookie: __semantos_helm_bearer=<hex>;
// SameSite=Lax` alongside the HttpOnly session cookie.  On first
// SPA load `getStoredBearer` reads that cookie, promotes the value
// to `localStorage["helm.bearer"]`, and clears the cookie — so the
// bearer never lives in URL history / Referer headers, and only
// rides on the wire for the single round-trip immediately after the
// auth-callback redirect.  Backward-compat: a `?bearer=` query
// param (the legacy callback path) still works via captureBearerFromUrl.
//
// D-O5.followup-8 — multi-hat helm sessions.  An operator can pair
// with multiple hats simultaneously (tradie hat + PM hat, etc.) and
// switch contexts via the top-nav HatSwitcher.  Each REPL call
// reads the *active* HatSession from `lib/hat-sessions.ts` on every
// `send` so a hat switch takes effect immediately on the next call
// without rebinding the client.  The active session's bearer is
// used in the Authorization header; its `brainBaseUrl` overrides
// the constructor's `baseUrl` when set (per-hat tenants).  401s
// auto-remove the session from the store and surface as
// `ReplUnauthorizedError`.  Backward compat: the constructor's
// `bearer` callback still wins (existing callers that explicitly
// inject a bearer keep working), and `getStoredBearer()` continues
// to return the legacy `helm.bearer` value when no multi-hat store
// exists yet (the migration runs on first hat-sessions read).
//
// Wire shape (request):
//
//     POST /api/v1/repl
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     {"cmd":"<repl-line>"}
//
// Wire shape (response) — see runtime/semantos-brain/src/repl_http.zig:
//
//     200 → {"result": "<captured stdout>", "exit": "continue" | "quit"}
//     401 → {"error": "..."}
//     400 → {"error": "..."}
//     503 → {"error": "REPL backend not enabled in this serve mode"}
//
// IMPORTANT — D-O5c-MVP scope: the helm SPA's view layer wants
// canonical resource queries (find jobs, find customers, etc.) but
// the Semantos Brain REPL today only routes a fixed set of verbs (status, help,
// audit, call, hash, history, clear, device).  There's no `find`
// verb wired through the dispatcher yet.  This client therefore
// returns the raw text result from `repl.handleLine` and the view
// layer parses it on a best-effort basis.  The first time we hit a
// view that needs a structured response we'll add a typed dispatcher
// resource (e.g. `find_jobs`) and surface it through this client as
// a typed method.  Tracked as D-O5.followup-1.
//
// D-O5.followup-7 — operator-visibility surface.  Every `send` call
// pushes a pending entry into the transcript ring buffer
// (lib/repl-transcript-store.ts) and resolves it to ok|err on
// completion.  The Transcript view (views/Transcript.svelte) renders
// the buffer; instrumentation lives entirely in this client so no
// view code needs to change.

import {
  pushPending,
  completeEntry,
  maybeTruncate,
} from "./repl-transcript-store";
import {
  getActiveSession,
  bumpLastUsed,
  removeSession,
} from "./hat-sessions";

export interface ReplOk {
  result: string;
  exit: "continue" | "quit";
}

export interface ReplErr {
  error: string;
}

export type ReplResponse = ReplOk | ReplErr;

export class ReplUnauthorizedError extends Error {
  constructor(reason: string) {
    super(reason);
    this.name = "ReplUnauthorizedError";
  }
}

// D-O5m.followup-5 K1 conflict UI — typed error classes the loom-svelte
// helm raises when the brain returns a recognised typed error JSON
// body.  These mirror the mobile helm's [OutboxFailureKind] vocabulary
// so list/detail views can render a clear inline conflict banner with
// retry/dismiss actions.
//
// Unlike the mobile outbox (which has an offline queue), the desktop
// helm is online-only — REPL calls fail in real time.  These typed
// errors give the views a structured handle to render specific UX
// without falling back to "Failed to load: <stack>".

/// 400 + `{"error":"<validation_kind>", "hint?": "<detail>"}`.
/// Surfaced when the REPL line was syntactically malformed or when
/// per-field validation rejected a transition payload.
export class ReplValidationError extends Error {
  /// Wire kind from the brain's typed body (e.g. "invalid_args",
  /// "payload_invalid_format").
  readonly kind: string;
  /// Optional human-readable detail from the brain's `hint` field.
  readonly hint: string | null;
  constructor(kind: string, hint: string | null = null) {
    super(hint ? `${kind}: ${hint}` : kind);
    this.name = "ReplValidationError";
    this.kind = kind;
    this.hint = hint;
  }
}

/// 200 + transition body whose `error` field is one of the K1-kind
/// strings (not_reachable / wrong_principal / wrong_cap / state_moved_on).
/// The desktop helm catches this and renders the side-by-side
/// conflict banner.
export class ReplStateMovedOnError extends Error {
  /// Wire kind from the brain (e.g. "not_reachable", "state_moved_on").
  readonly kind: string;
  /// The brain's current canonical state for this entity, when the
  /// brain surfaced one in the typed body.
  readonly brainState: string | null;
  /// The state the operator's command was attempting to leave from.
  readonly fromState: string | null;
  /// The state the operator's command was attempting to transition
  /// into.
  readonly toState: string | null;
  constructor(
    kind: string,
    opts: {
      brainState?: string | null;
      fromState?: string | null;
      toState?: string | null;
    } = {},
  ) {
    super(`${kind} (brain state: ${opts.brainState ?? "unknown"})`);
    this.name = "ReplStateMovedOnError";
    this.kind = kind;
    this.brainState = opts.brainState ?? null;
    this.fromState = opts.fromState ?? null;
    this.toState = opts.toState ?? null;
  }
}

/// 200 / 404 + `{"error":"not_found", "id"|"visit_id": "<id>"}`.
/// The entity the operator's command referenced no longer exists on
/// the brain.  Distinct from validation errors so views can render
/// "this got deleted" UX rather than "your input was wrong".
export class ReplFkError extends Error {
  /// Wire kind from the brain (e.g. "not_found", "visit_not_found").
  readonly kind: string;
  /// The id the brain reported as missing (when one was provided).
  readonly id: string | null;
  /// Which entity type was missing — best-effort sniff of the `id`
  /// field name in the typed body (e.g. "visit_id" → "visit").
  readonly entity: string;
  constructor(
    kind: string,
    opts: { id?: string | null; entity?: string } = {},
  ) {
    super(opts.id ? `${kind}: ${opts.id}` : kind);
    this.name = "ReplFkError";
    this.kind = kind;
    this.id = opts.id ?? null;
    this.entity = opts.entity ?? "entity";
  }
}

/// Set of wire-kind strings that, when seen in a 200-shaped REPL
/// transition body's `error` field, indicate a K1 state_moved_on
/// conflict rather than a validation rejection.  Used by the helpers
/// below + by callers that want to inspect a parsed body directly.
export const STATE_MOVED_ON_KINDS = new Set([
  "state_moved_on",
  "not_reachable",
  "wrong_principal",
  "wrong_cap",
]);

/// Set of wire-kind strings that map to ReplFkError.
export const FK_ERROR_KINDS = new Set([
  "not_found",
  "visit_not_found",
  "job_not_found",
]);

/// Parse a 200-shaped REPL transition body and throw the appropriate
/// typed error when the body carries a typed `error` field.  Returns
/// the body untouched on success.  Used by view layer code that
/// wants to dispatch on typed errors after a `client.send()` call.
export function throwIfTypedConflict(body: ReplResponse): ReplResponse {
  if ("error" in body) {
    const kind = body.error;
    if (STATE_MOVED_ON_KINDS.has(kind)) {
      const obj = body as unknown as Record<string, unknown>;
      throw new ReplStateMovedOnError(kind, {
        brainState: typeof obj.from === "string" ? obj.from : null,
        fromState: typeof obj.from === "string" ? obj.from : null,
        toState: typeof obj.to === "string" ? obj.to : null,
      });
    }
    if (FK_ERROR_KINDS.has(kind)) {
      const obj = body as unknown as Record<string, unknown>;
      const id =
        typeof obj.id === "string"
          ? obj.id
          : typeof obj.visit_id === "string"
            ? (obj.visit_id as string)
            : typeof obj.job_id === "string"
              ? (obj.job_id as string)
              : null;
      const entity =
        kind === "visit_not_found"
          ? "visit"
          : kind === "job_not_found"
            ? "job"
            : "entity";
      throw new ReplFkError(kind, { id, entity });
    }
  }
  return body;
}

export interface ReplClientOptions {
  /// Bearer token previously issued by the helm auth flow. When
  /// omitted, the client reads it from `localStorage["helm.bearer"]`
  /// on every call so a token-rotation handler doesn't need to plumb
  /// the new value through every component.
  bearer?: () => string | null;
  /// HTTP base URL — defaults to "" (same-origin, which is what the
  /// helm SPA wants in production: served from `/helm/` on the same
  /// brain that hosts `/api/v1/repl`).
  baseUrl?: string;
  /// Override `fetch` for tests. Defaults to the global.
  fetchImpl?: typeof fetch;
}

const BEARER_STORAGE_KEY = "helm.bearer";

/// D-O5.followup-2 — name of the non-HttpOnly cookie brain's
/// /auth/callback writes alongside the session cookie.  The value is
/// the 64-hex bearer token.  Read once on first SPA load, promoted to
/// localStorage, then cleared (single-use semantics — the cookie is
/// only on the wire for one request round-trip).
const HELM_BEARER_COOKIE_NAME = "__semantos_helm_bearer";

/// Pull the helm bearer out of `document.cookie`, decode it, return
/// it.  Returns null when the cookie isn't present (e.g. SSR, or the
/// SPA was loaded by a route that didn't go through /auth/callback).
function readHelmBearerCookie(): string | null {
  if (typeof document === "undefined") return null;
  const cookieJar = document.cookie ?? "";
  const match = cookieJar.match(
    new RegExp(`(?:^|; )${HELM_BEARER_COOKIE_NAME}=([^;]+)`),
  );
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    // A malformed % sequence — treat as absent rather than throwing
    // (the SPA's auth state machine handles "no bearer" by surfacing
    // the auth-challenge stub).
    return null;
  }
}

/// Clear the helm bearer cookie from the browser's cookie jar.  Only
/// callable in a browser context.  Used after promoting the cookie's
/// value into localStorage so the bearer no longer rides on every
/// subsequent same-origin request (defense-in-depth: the bearer's
/// long-lived storage is localStorage, scoped to the origin's JS).
function clearHelmBearerCookie(): void {
  if (typeof document === "undefined") return;
  document.cookie = `${HELM_BEARER_COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax`;
}

export function getStoredBearer(): string | null {
  if (typeof localStorage === "undefined") return null;
  // Prefer the localStorage cache — once a bearer has been captured,
  // every subsequent ReplClient call hits this path.
  const cached = localStorage.getItem(BEARER_STORAGE_KEY);
  if (cached !== null) return cached;
  // Cold-start path: the auth-callback redirect just dropped a fresh
  // bearer cookie.  Promote it to localStorage and clear the cookie
  // so the bearer leaves the wire after exactly one request.
  const fromCookie = readHelmBearerCookie();
  if (fromCookie !== null) {
    localStorage.setItem(BEARER_STORAGE_KEY, fromCookie);
    clearHelmBearerCookie();
    return fromCookie;
  }
  return null;
}

export function setStoredBearer(token: string | null): void {
  if (typeof localStorage === "undefined") return;
  if (token === null) localStorage.removeItem(BEARER_STORAGE_KEY);
  else localStorage.setItem(BEARER_STORAGE_KEY, token);
}

/// Wall-clock reading for transcript latency.  Prefers
/// `performance.now()` when available (browser/test runtime) and falls
/// back to `Date.now()` for environments without it.  Returns
/// milliseconds.
function nowMs(): number {
  if (typeof performance !== "undefined" && typeof performance.now === "function") {
    return performance.now();
  }
  return Date.now();
}

export class ReplClient {
  private readonly opts: ReplClientOptions;

  constructor(opts: ReplClientOptions = {}) {
    this.opts = opts;
  }

  /// Send a single REPL line and return the parsed JSON response.
  /// Throws ReplUnauthorizedError on 401 (callers should redirect to
  /// the auth-challenge flow); other non-2xx responses come back as
  /// a ReplErr.
  ///
  /// D-O5.followup-7 — every call pushes a transcript entry; resolved
  /// to `ok` (with the captured result text + bytes + truncation flag)
  /// on success, or `err` (with statusCode when known) on the error
  /// paths.  The transcript view renders the resulting feed.
  async send(cmd: string): Promise<ReplResponse> {
    const transcriptId = pushPending(cmd);
    const startedAt = nowMs();
    try {
      const body = await this._sendInner(cmd);
      const elapsed = nowMs() - startedAt;
      // ReplErr (non-throwing error path — 503, unknown 5xx, etc.)
      // is still recorded as `err` in the transcript so the operator
      // sees backend-unavailable signals alongside HTTP failures.
      if ("error" in body) {
        completeEntry(
          transcriptId,
          { kind: "err", error: body.error },
          elapsed,
        );
      } else {
        const truncated = maybeTruncate(body.result);
        completeEntry(
          transcriptId,
          {
            kind: "ok",
            text: truncated.text,
            bytes: truncated.bytes,
            truncated: truncated.truncated,
          },
          elapsed,
        );
      }
      return body;
    } catch (e: unknown) {
      const elapsed = nowMs() - startedAt;
      const message = e instanceof Error ? e.message : String(e);
      let statusCode: number | undefined;
      if (e instanceof ReplUnauthorizedError) statusCode = 401;
      else if (e instanceof ReplValidationError) statusCode = 400;
      completeEntry(
        transcriptId,
        statusCode === undefined
          ? { kind: "err", error: message }
          : { kind: "err", error: message, statusCode },
        elapsed,
      );
      throw e;
    }
  }

  /// Inner send: the original wire-level logic without transcript
  /// instrumentation.  Kept private so callers always go through
  /// `send` (which records the entry).
  ///
  /// D-O5.followup-8 — active hat session resolution.  When the
  /// constructor's `bearer` callback is *not* set, this method reads
  /// the active session from `lib/hat-sessions.ts` on every call: the
  /// session's `bearer` rides on the wire, its `brainBaseUrl`
  /// overrides `opts.baseUrl` when set, and its `lastUsedAt` is bumped
  /// so the HatSwitcher dropdown can sort least-recently-used to the
  /// bottom.  On 401 the active session is auto-removed (the operator
  /// must re-pair the hat) — the App.svelte error surface renders the
  /// "Hat session expired — re-pair" inline error.
  private async _sendInner(cmd: string): Promise<ReplResponse> {
    const session = this.opts.bearer ? null : getActiveSession();
    const bearer = this.opts.bearer ? this.opts.bearer() : session?.bearer ?? null;
    // Per-hat brain origin (multi-tenant): when the active session
    // carries a `brainBaseUrl`, it wins over the constructor's
    // `baseUrl`.  Falls back to "" (same-origin) for legacy callers.
    const baseUrl =
      session?.brainBaseUrl && session.brainBaseUrl.length > 0
        ? session.brainBaseUrl
        : this.opts.baseUrl ?? "";
    const fetchImpl = this.opts.fetchImpl ?? globalThis.fetch.bind(globalThis);
    const headers: Record<string, string> = {
      "content-type": "application/json",
    };
    if (bearer) headers["authorization"] = `Bearer ${bearer}`;

    if (session !== null) {
      // Bump lastUsedAt before the fetch — the dropdown's "this hat
      // last issued a call at <time>" reading should reflect the
      // attempt regardless of how the call resolves.
      bumpLastUsed(session.id);
    }

    const resp = await fetchImpl(`${baseUrl}/api/v1/repl`, {
      method: "POST",
      headers,
      body: JSON.stringify({ cmd }),
      credentials: "include", // session cookie scoped to /helm carries through
    });
    if (resp.status === 401) {
      // D-O5.followup-8 — auto-remove the active session on 401.  The
      // bearer for this hat has been rejected (expired / revoked /
      // brain restarted with a fresh data dir); leaving it in the store
      // would trap the operator in an infinite "REPL bearer token
      // rejected" loop.  Removing here lets the HatSwitcher render
      // the "re-pair another hat" CTA on the next render.
      if (session !== null) removeSession(session.id);
      throw new ReplUnauthorizedError("REPL bearer token rejected");
    }
    const body = (await resp.json()) as ReplResponse;
    // D-O5m.followup-5 — promote the brain's 400-typed error bodies to
    // the typed [ReplValidationError] surface.  This keeps the public
    // contract intact (the body is still returned for 200 responses)
    // while letting view code use a single try/catch over typed
    // errors.  ReplErr is still returned for non-recognised non-2xx
    // cases (e.g. 503 backend unavailable) so the existing
    // unauthenticated/error-banner UI keeps working.
    if (resp.status === 400 && "error" in body) {
      const obj = body as unknown as Record<string, unknown>;
      const hint = typeof obj.hint === "string" ? (obj.hint as string) : null;
      throw new ReplValidationError(body.error, hint);
    }
    return body;
  }

  /// D-O5m.followup-8 capture+upload — bearer-gated GET that fetches a
  /// binary blob and returns an object URL the caller can plug into an
  /// `<img>` src.  Used by VisitDetail.svelte's photo thumbnails — the
  /// raw `<img src>` attribute can't carry custom Authorization
  /// headers cross-origin, so we prefetch via fetch + createObjectURL.
  ///
  /// The caller MUST `URL.revokeObjectURL` the returned URL when the
  /// image element is removed from the DOM (Svelte's onunmount /
  /// derived cleanup discharge that responsibility).
  async fetchBlob(path: string): Promise<string> {
    // D-O5.followup-8 — same active-session resolution as `_sendInner`.
    // Blob fetches don't push a transcript entry (they're lazy
    // image-load paths, not operator-issued REPL calls), but they DO
    // need to ride on the active hat's bearer + brainBaseUrl.
    const session = this.opts.bearer ? null : getActiveSession();
    const bearer = this.opts.bearer ? this.opts.bearer() : session?.bearer ?? null;
    const baseUrl =
      session?.brainBaseUrl && session.brainBaseUrl.length > 0
        ? session.brainBaseUrl
        : this.opts.baseUrl ?? "";
    const fetchImpl = this.opts.fetchImpl ?? globalThis.fetch.bind(globalThis);
    const headers: Record<string, string> = {};
    if (bearer) headers["authorization"] = `Bearer ${bearer}`;

    const resp = await fetchImpl(`${baseUrl}${path}`, {
      method: "GET",
      headers,
      credentials: "include",
    });
    if (resp.status === 401) {
      if (session !== null) removeSession(session.id);
      throw new ReplUnauthorizedError("blob bearer token rejected");
    }
    if (!resp.ok) {
      throw new Error(`blob fetch failed: ${resp.status} ${resp.statusText}`);
    }
    const blob = await resp.blob();
    return URL.createObjectURL(blob);
  }

  private bearer(): string | null {
    if (this.opts.bearer) return this.opts.bearer();
    return getStoredBearer();
  }
}

```
