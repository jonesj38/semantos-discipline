---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/auth.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.081899+00:00
---

# apps/loom-svelte/src/lib/auth.ts

```ts
// D-O5b — Helm SPA identity-cert gate (operator-side).
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE3) +
// runtime/semantos-brain/src/auth_handler.zig.
//
// Flow:
//
//   1. Browser hits `/helm/`. brain's site_server checks the
//      `__semantos_session` cookie and — if absent — emits a 401
//      response with `X-Semantos-*` headers carrying a fresh nonce,
//      a return-to URL, and a `Set-Cookie: __semantos_challenge=...`.
//      The 401 body is the auth-challenge stub HTML.
//
//   2. The helm SPA either (a) loads from a cookie-gated URL and is
//      already authenticated, or (b) loaded from the 401 stub and
//      shows the operator a "scan QR / open wallet" prompt.
//
//   3. Operator signs the challenge with their hat on a wallet origin
//      (mobile Safari from a phone QR scan in production; or
//      `brain repl`-issued bearer token in dev).
//
//   4. Wallet origin POSTs `{pubkey, signature, nonce, return_to}` to
//      `/auth/callback`. brain verifies the signature, mints a
//      session, sets `__semantos_session` cookie, redirects to
//      return_to.
//
//   5. The redirected GET carries the cookie; `requestHasValidSession`
//      passes; brain serves the SPA bundle.
//
// **D-O5b-MVP scope**: the SPA-side code here detects the
// authenticated/unauthenticated state and surfaces the right UI; it
// does NOT carry the wallet-origin sign step (that's a separate
// origin running its own UI).  The SPA reads the bearer token from
// localStorage; in production deployment, the Semantos Brain-side
// /auth/callback now mints a bearer alongside the HttpOnly session
// cookie and writes it as a non-HttpOnly `__semantos_helm_bearer`
// cookie (D-O5.followup-2).  `getStoredBearer` in repl-client.ts
// reads that cookie on first call, promotes it to localStorage, and
// clears the cookie.
//
// Backward-compat (transition window): the legacy `/helm/?bearer=...`
// query-string path is still honoured via `captureBearerFromUrl`
// below — old auth-callback redirects keep working until every
// deploy is on the dual-cookie path.  The mobile-auth roundtrip
// (D-O5e) is unchanged: mobile uses the device-pair flow, not the
// browser /auth/callback redirect.
//
// Closed follow-ups:
//   • D-O5.followup-2: dual-cookie mint at /auth/callback.  Bearer
//     no longer lives in URL history / Referer headers.

import { setStoredBearer, getStoredBearer } from "./repl-client";

export type AuthState =
  | { kind: "authenticated"; bearer: string }
  | { kind: "unauthenticated" }
  | { kind: "pending" };

/// Read the URL for a `?bearer=<hex64>` query param emitted by the
/// auth-callback redirect.  When present, persist + clean the URL.
export function captureBearerFromUrl(): string | null {
  if (typeof window === "undefined") return null;
  const url = new URL(window.location.href);
  const bearer = url.searchParams.get("bearer");
  if (!bearer) return null;
  setStoredBearer(bearer);
  url.searchParams.delete("bearer");
  window.history.replaceState({}, "", url.toString());
  return bearer;
}

/// Snapshot the current auth state by checking localStorage.
export function currentAuthState(): AuthState {
  const bearer = getStoredBearer();
  if (bearer && bearer.length === 64) {
    return { kind: "authenticated", bearer };
  }
  return { kind: "unauthenticated" };
}

/// Clear the persisted bearer (called on 401 from REPL).
export function clearAuth(): void {
  setStoredBearer(null);
}

/// The wallet-origin URL the operator is redirected to to sign the
/// challenge.  In production this is the operator's own wallet
/// (phone or desktop) hosted at a stable origin.  Configurable via
/// `data-helm-wallet-origin` on the SPA's mount element so deploys
/// can switch origins without rebuilding.
export function walletOriginHint(): string {
  if (typeof document === "undefined") return "https://wallet.semantos.app";
  const root = document.getElementById("app");
  return (
    root?.getAttribute("data-helm-wallet-origin") ?? "https://wallet.semantos.app"
  );
}

```
