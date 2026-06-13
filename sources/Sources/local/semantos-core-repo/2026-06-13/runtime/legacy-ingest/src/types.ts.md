---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.130153+00:00
---

# runtime/legacy-ingest/src/types.ts

```ts
/**
 * Legacy-ingest core types.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1.
 *
 * The provider-adapter interface is intentionally narrow: every legacy
 * provider (Gmail, Meta, WhatsApp Cloud, Google Calendar, Xero, …) is a
 * thin object that knows how to walk pages, fetch full items, and produce
 * a stable cross-provider fingerprint. Storage, OAuth orchestration,
 * and ratification all live above this layer.
 */

/** Stable identifier for a legacy provider — same string used in TOML config. */
export type ProviderId = string;

/**
 * Opaque pagination cursor. Per-provider semantics:
 *   - Gmail: API `pageToken` string (or null on first page)
 *   - Meta: graph `after` cursor (string)
 *   - WhatsApp Cloud: epoch-ms watermark
 *   - G-Cal: nextPageToken
 *   - Xero: page number
 *
 * Treated as a JSON-serialisable opaque blob by everything above this
 * layer; only the provider knows its shape.
 */
export type Cursor = string | null;

/**
 * One raw legacy item — the verbatim provider payload plus enough
 * identification to re-fetch / dedup / re-extract later.
 */
export interface RawItem {
  /** Matches `LegacyProvider.id`. */
  readonly providerId: ProviderId;
  /** Provider-stable item id. Gmail: message id. Meta: message id. WA: id. */
  readonly providerItemId: string;
  /** Unix ms when fetched. */
  readonly fetchedAt: number;
  /**
   * MIME-style content type per the LI spec:
   *   "email/rfc822" | "meta/message" | "whatsapp/message"
   *   "ical/event"   | "xero/invoice" | "json/<provider>"
   */
  readonly contentType: string;
  /** Raw payload — exactly what the provider returned. Persisted verbatim. */
  readonly bytes: Uint8Array;
  /**
   * Provider-supplied metadata — subject, sender, etc. Strings only;
   * structured fields go through extraction in LI3.
   */
  readonly metadata: Readonly<Record<string, string>>;
}

/**
 * An OAuth access token + refresh material. Decrypted form — never
 * persisted in this shape. The encrypted envelope lives in
 * `~/.semantos/legacy-grants/<provider>/<grant-id>.enc`.
 */
export interface AccessToken {
  readonly accessToken: string;
  /** Optional — some providers (Xero) issue refresh tokens; some don't. */
  readonly refreshToken: string | null;
  /** Unix ms when this access token expires (NOT the refresh token). */
  readonly expiresAt: number;
  /** Space-separated scopes the provider granted. */
  readonly scopes: string;
  /** Raw provider response — preserved for forensic / debug. */
  readonly providerExtras: Readonly<Record<string, unknown>>;
}

/**
 * Persistent grant record for one (operator, provider) tuple. The
 * grant id is generated at OAuth-grant time and stays stable across
 * refreshes — refreshes mutate the embedded AccessToken, not the
 * grant id. Disconnect deletes the grant.
 */
export interface LegacyGrant {
  readonly grantId: string;
  readonly providerId: ProviderId;
  /** ISO timestamp when the grant was created. */
  readonly createdAt: string;
  /** ISO timestamp of the last successful refresh. */
  readonly lastRefreshedAt: string | null;
  /** Operator-facing label, e.g. the Gmail account address. */
  readonly accountLabel: string | null;
  /** Hat id under whose authority the grant was made. */
  readonly hatId: string | null;
  readonly token: AccessToken;
}

/** Result of a paginated list call. */
export interface ListPageResult {
  readonly items: RawItem[];
  readonly nextCursor: Cursor;
}

/**
 * Provider adapter contract. Every legacy provider implements this.
 *
 * The interface deliberately knows nothing about storage, encryption,
 * audit logging, or ratification — those live in the dispatcher above
 * this layer (LI1's grant-store + LI2's ingest worker).
 *
 * Methods receive the access token explicitly; the adapter never reads
 * the grant store. This keeps the adapter unit-testable with a fixture
 * token.
 */
export interface LegacyProvider {
  readonly id: ProviderId;
  readonly displayName: string;
  /** OAuth scopes the adapter needs at grant time. */
  readonly oauthScopes: string[];
  /** Provider's OAuth authorize URL. Used to build the redirect target. */
  readonly oauthAuthorizeUrl: string;
  /** Provider's OAuth token-exchange URL. */
  readonly oauthTokenUrl: string;
  /** Provider's OAuth revoke URL, if it has one. */
  readonly oauthRevokeUrl: string | null;

  /**
   * Walk a page of items, optionally bounded by `cursor`, `since`, and a
   * provider-specific free-form `query` string. For Gmail the `query`
   * is passed through verbatim as the `q` parameter (so the operator can
   * use the full Gmail-search syntax: `from:`, `subject:`, `label:`, …).
   * Providers without a server-side query syntax may ignore the field.
   */
  listPage(
    token: AccessToken,
    opts: { cursor: Cursor; since?: number; query?: string },
  ): Promise<ListPageResult>;

  /**
   * Some providers return preview data in `listPage` and require a
   * follow-up fetch for the full body (Gmail does — `messages.list`
   * returns ids only, `messages.get` returns the rfc822 payload).
   */
  fetchFull(token: AccessToken, item: RawItem): Promise<RawItem>;

  /**
   * Provider-agnostic fingerprint — used by LI5 for cross-provider
   * deduplication. Stable per logical event (e.g. one customer's
   * email address normalised to lower-case + the message timestamp).
   */
  fingerprint(item: RawItem): string;
}

/**
 * State carried in the OAuth `state` URL parameter — the nonce we
 * verify on callback to bind the redirect to the in-flight request.
 * Persisted in-memory in the grant orchestrator until callback arrives.
 */
export interface OAuthPendingState {
  readonly nonce: string;
  readonly providerId: ProviderId;
  readonly hatId: string | null;
  readonly createdAt: number;
  /** PKCE code verifier — present iff the provider requires PKCE. */
  readonly pkceVerifier: string | null;
  readonly redirectUri: string;
}

```
