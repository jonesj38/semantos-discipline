---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/oauth.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.128702+00:00
---

# runtime/legacy-ingest/src/oauth.ts

```ts
/**
 * OAuth grant orchestration — LI1.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 deliverable 2.
 *
 * Three responsibilities:
 *   1. Build the provider's authorize URL with a state nonce + PKCE
 *      challenge (where supported).
 *   2. Verify state nonces on callback and exchange the auth `code`
 *      for an access + refresh token pair.
 *   3. Refresh access tokens before expiry; revoke on disconnect.
 *
 * The HTTP-routing layer that *receives* the callback is out of scope
 * here — per the spec (LI §3 LI1 step 4) it lives under BRAIN's HTTP
 * surface, and per the V1.0 plan §5 it currently lands in the existing
 * Next.js Vercel deployment as a temporary placeholder until BRAIN HTTP
 * ships. This module exposes `handleCallback()` so whichever HTTP
 * server hosts the callback can route into here.
 */

import type {
  AccessToken,
  LegacyGrant,
  LegacyProvider,
  OAuthPendingState,
  ProviderId,
} from './types';
import { audit } from './audit';
import { LegacyGrantStore } from './grant-store';
import type { PendingStateStore } from './pending-state-store';

/**
 * Default OAuth redirect URI — the localhost loopback served by the
 * legacy-ingest widget Bun server (`runtime/legacy-ingest/src/widget/serve.ts`).
 *
 * Google explicitly permits `http://localhost:<port>/<path>` for installed-app
 * OAuth clients (https://developers.google.com/identity/protocols/oauth2/native-app),
 * so this is a portable default operators can register with the provider
 * without deploying a public callback host.
 *
 * Per-provider `ClientConfig.redirectUri` (set via `legacy register-client
 * --redirect-uri ...`) overrides this default; this is the floor used when
 * the per-provider config doesn't supply one explicitly. Operators who
 * keep using the public callback URL (e.g. once a wallet origin ships)
 * register that URL via `--redirect-uri` and the override wins.
 */
export const DEFAULT_REDIRECT_URI = 'http://localhost:3001/auth/callback';

/** PKCE S256 challenge from a verifier. */
async function s256(verifier: string, cryptoImpl: Crypto): Promise<string> {
  const buf = new TextEncoder().encode(verifier);
  const digest = await cryptoImpl.subtle.digest('SHA-256', buf);
  const b64 = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function randomB64Url(bytes: number, cryptoImpl: Crypto): string {
  const buf = new Uint8Array(bytes);
  cryptoImpl.getRandomValues(buf);
  return btoa(String.fromCharCode(...buf))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/** Provider catalog — `register` adds a new one. Test code uses this. */
export class ProviderRegistry {
  private readonly providers = new Map<ProviderId, LegacyProvider>();

  register(provider: LegacyProvider): void {
    if (this.providers.has(provider.id)) {
      throw new Error(`legacy-ingest: provider '${provider.id}' is already registered`);
    }
    this.providers.set(provider.id, provider);
  }

  get(id: ProviderId): LegacyProvider | undefined {
    return this.providers.get(id);
  }

  list(): LegacyProvider[] {
    return [...this.providers.values()];
  }
}

/**
 * Outcome of `prepareGrant()` — the operator's browser navigates to
 * `authorizeUrl`, the provider redirects back to the configured
 * callback, the callback handler calls `handleCallback(state, code)`
 * to complete the grant.
 */
export interface PreparedGrant {
  readonly authorizeUrl: string;
  readonly stateNonce: string;
}

/** Provider OAuth configuration the orchestrator needs at grant time. */
export interface ClientConfig {
  /** Operator-registered OAuth client id for this provider. */
  readonly clientId: string;
  /**
   * Operator-registered OAuth client secret. Some providers (Google
   * Cloud Console, Meta) issue secrets; some (PKCE-only flows) don't.
   * Stored encrypted-at-rest by the host (out of scope here).
   */
  readonly clientSecret?: string;
  /**
   * Absolute callback URL the provider will redirect to. Optional — if
   * the per-provider config doesn't supply one, the orchestrator's
   * `defaultRedirectUri` opt is used (which itself defaults to
   * `DEFAULT_REDIRECT_URI`, the localhost loopback).
   */
  readonly redirectUri?: string;
  /** Whether the provider supports PKCE — defaults to false. */
  readonly pkce?: boolean;
}

/** Token-exchange transport. Tests pass a fake; production uses fetch. */
export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface OAuthOrchestratorOpts {
  registry: ProviderRegistry;
  store: LegacyGrantStore;
  /** Returns the operator's active hat id (for audit + grant attribution). */
  hatIdProvider?: () => string | null;
  /** Provider-keyed client config — operator-supplied via `legacy connect`. */
  configProvider: (id: ProviderId) => ClientConfig | null;
  fetch?: FetchLike;
  cryptoImpl?: Crypto;
  /**
   * Pending state-nonce TTL in ms. Default 10 minutes — the operator's
   * OAuth round-trip on a phone is rarely more than that.
   */
  pendingTtlMs?: number;
  /**
   * Default OAuth callback URI used when a per-provider `ClientConfig`
   * doesn't supply `redirectUri`. Defaults to `DEFAULT_REDIRECT_URI`
   * (the localhost loopback served by `runtime/legacy-ingest/src/widget/serve.ts`).
   * Per-provider configs that DO set `redirectUri` always win — this is
   * the floor.
   */
  defaultRedirectUri?: string;
  /**
   * Optional disk-backed pending-state store. When supplied, pending
   * state-nonces are persisted to disk between `prepareGrant` and
   * `handleCallback`; this is what makes the legacy-cli's one-shot
   * verb invocations work (each `bun apps/legacy-cli/src/cli.ts ...`
   * call is a fresh process — without disk persistence the in-memory
   * Map dies between `legacy connect` and `legacy resume`).
   *
   * Embedded uses (the widget server, in-process tests) leave this
   * unset and continue to use the in-memory Map — no behaviour change
   * for them.
   */
  pendingStore?: PendingStateStore;
}

export class OAuthError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = 'OAuthError';
  }
}

/**
 * State nonce + PKCE verifier persistence. By default the pending
 * grant is held in memory only — fine for embedded uses (the widget
 * server) where `prepareGrant` and `handleCallback` run in the same
 * process.
 *
 * The legacy-cli's one-shot verb model (`bun apps/legacy-cli/src/cli.ts
 * <verb>` is a fresh process per invocation) requires disk-backed
 * persistence — the host wires a `PendingStateStore` via the optional
 * `pendingStore` opt, and pending state survives the process exit
 * between `legacy connect` and `legacy resume`. See
 * `pending-state-store.ts` for the encrypted envelope.
 */
export class OAuthOrchestrator {
  private readonly registry: ProviderRegistry;
  private readonly store: LegacyGrantStore;
  private readonly hatIdProvider: () => string | null;
  private readonly configProvider: (id: ProviderId) => ClientConfig | null;
  private readonly fetchImpl: FetchLike;
  private readonly cryptoImpl: Crypto;
  private readonly pendingTtlMs: number;
  private readonly defaultRedirectUri: string;
  private readonly pending = new Map<string, OAuthPendingState>();
  private readonly pendingStore: PendingStateStore | null;

  constructor(opts: OAuthOrchestratorOpts) {
    this.registry = opts.registry;
    this.store = opts.store;
    this.hatIdProvider = opts.hatIdProvider ?? (() => null);
    this.configProvider = opts.configProvider;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
    this.pendingTtlMs = opts.pendingTtlMs ?? 10 * 60 * 1000;
    this.defaultRedirectUri = opts.defaultRedirectUri ?? DEFAULT_REDIRECT_URI;
    this.pendingStore = opts.pendingStore ?? null;
  }

  /** Resolve the redirect URI for a config — per-provider override > default. */
  private resolveRedirectUri(config: ClientConfig): string {
    return config.redirectUri ?? this.defaultRedirectUri;
  }

  /** Step 1 — build the authorize URL the operator's browser navigates to. */
  async prepareGrant(providerId: ProviderId): Promise<PreparedGrant> {
    const provider = this.registry.get(providerId);
    if (!provider) throw new OAuthError(`unknown provider '${providerId}'`, 'unknown_provider');
    const config = this.configProvider(providerId);
    if (!config) throw new OAuthError(`no client config for '${providerId}'`, 'no_client_config');

    const nonce = randomB64Url(32, this.cryptoImpl);
    const pkceVerifier = config.pkce ? randomB64Url(48, this.cryptoImpl) : null;
    const challenge = pkceVerifier ? await s256(pkceVerifier, this.cryptoImpl) : null;

    const redirectUri = this.resolveRedirectUri(config);
    const params = new URLSearchParams({
      response_type: 'code',
      client_id: config.clientId,
      redirect_uri: redirectUri,
      scope: provider.oauthScopes.join(' '),
      state: nonce,
      access_type: 'offline',
      prompt: 'consent',
    });
    if (challenge) {
      params.set('code_challenge', challenge);
      params.set('code_challenge_method', 'S256');
    }

    const url = `${provider.oauthAuthorizeUrl}?${params.toString()}`;

    const pendingState: OAuthPendingState = {
      nonce,
      providerId,
      hatId: this.hatIdProvider(),
      createdAt: Date.now(),
      pkceVerifier,
      redirectUri,
    };
    if (this.pendingStore) {
      // Disk-backed path (legacy-cli). Sweep first so we don't accumulate
      // expired entries between connect calls — the directory is small,
      // so this is cheap.
      await this.pendingStore.sweepExpired();
      await this.pendingStore.put(pendingState);
    } else {
      this.pending.set(nonce, pendingState);
      this.gcPending();
    }

    await audit('oauth.prepare', 'ok', { providerId, hatId: this.hatIdProvider() });
    return { authorizeUrl: url, stateNonce: nonce };
  }

  /**
   * Step 2 — called by the HTTP callback handler. Verifies the state
   * nonce, exchanges the code, encrypts and persists the grant.
   */
  async handleCallback(opts: { state: string; code: string }): Promise<LegacyGrant> {
    let pending: OAuthPendingState | null;
    if (this.pendingStore) {
      // Disk-backed path: get-then-delete. The store enforces TTL on
      // read (returns null + deletes the file when expired) so we
      // collapse the unknown / expired branches into one bad_state
      // error. Sweep happens here too so a long-lived host doesn't
      // accumulate stale entries between unrelated grants.
      await this.pendingStore.sweepExpired();
      pending = await this.pendingStore.get(opts.state);
      if (!pending) {
        await audit('oauth.callback', 'denied', { detail: 'unknown_or_expired_state' });
        throw new OAuthError('state nonce unknown or expired', 'bad_state');
      }
      await this.pendingStore.delete(opts.state);
    } else {
      pending = this.pending.get(opts.state) ?? null;
      if (!pending) {
        await audit('oauth.callback', 'denied', { detail: 'unknown_or_expired_state' });
        throw new OAuthError('state nonce unknown or expired', 'bad_state');
      }
      if (Date.now() - pending.createdAt > this.pendingTtlMs) {
        this.pending.delete(opts.state);
        await audit('oauth.callback', 'denied', {
          providerId: pending.providerId,
          detail: 'state_expired',
        });
        throw new OAuthError('state nonce expired', 'state_expired');
      }
      this.pending.delete(opts.state);
    }

    const provider = this.registry.get(pending.providerId);
    if (!provider) throw new OAuthError(`unknown provider '${pending.providerId}'`, 'unknown_provider');
    const config = this.configProvider(pending.providerId);
    if (!config) throw new OAuthError('no client config', 'no_client_config');

    const token = await this.exchangeCode(provider, config, opts.code, pending.pkceVerifier);
    const grant: LegacyGrant = {
      grantId: randomB64Url(16, this.cryptoImpl),
      providerId: provider.id,
      createdAt: new Date().toISOString(),
      lastRefreshedAt: null,
      accountLabel: null,
      hatId: pending.hatId,
      token,
    };
    await this.store.put(grant);
    await audit('oauth.grant', 'ok', {
      providerId: provider.id,
      grantId: grant.grantId,
      hatId: grant.hatId,
    });
    return grant;
  }

  /** Refresh a single grant. Returns the updated grant. */
  async refresh(grant: LegacyGrant): Promise<LegacyGrant> {
    const provider = this.registry.get(grant.providerId);
    if (!provider) throw new OAuthError(`unknown provider '${grant.providerId}'`, 'unknown_provider');
    const config = this.configProvider(grant.providerId);
    if (!config) throw new OAuthError('no client config', 'no_client_config');
    if (!grant.token.refreshToken) {
      await audit('oauth.refresh', 'denied', {
        providerId: grant.providerId,
        grantId: grant.grantId,
        detail: 'no_refresh_token',
      });
      throw new OAuthError('grant has no refresh token', 'no_refresh_token');
    }

    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: grant.token.refreshToken,
      client_id: config.clientId,
    });
    if (config.clientSecret) body.set('client_secret', config.clientSecret);

    const res = await this.fetchImpl(provider.oauthTokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    if (!res.ok) {
      await audit('oauth.refresh', 'error', {
        providerId: grant.providerId,
        grantId: grant.grantId,
        detail: `http_${res.status}`,
      });
      throw new OAuthError(`token refresh failed: HTTP ${res.status}`, 'refresh_http_error');
    }
    const json = (await res.json()) as Record<string, unknown>;
    const next = parseTokenResponse(json, grant.token.refreshToken);

    const updated: LegacyGrant = {
      ...grant,
      lastRefreshedAt: new Date().toISOString(),
      token: next,
    };
    await this.store.put(updated);
    await audit('oauth.refresh', 'ok', {
      providerId: grant.providerId,
      grantId: grant.grantId,
    });
    return updated;
  }

  /**
   * Step 3 — disconnect. Best-effort revoke at the provider, then
   * delete the local grant unconditionally. Failure to revoke at
   * provider is logged but does not block local deletion.
   */
  async disconnect(grant: LegacyGrant): Promise<void> {
    const provider = this.registry.get(grant.providerId);
    if (provider?.oauthRevokeUrl) {
      try {
        await this.fetchImpl(provider.oauthRevokeUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ token: grant.token.refreshToken ?? grant.token.accessToken }).toString(),
        });
        await audit('oauth.revoke.remote', 'ok', {
          providerId: grant.providerId,
          grantId: grant.grantId,
        });
      } catch (err) {
        await audit('oauth.revoke.remote', 'error', {
          providerId: grant.providerId,
          grantId: grant.grantId,
          detail: err instanceof Error ? err.message : 'unknown',
        });
      }
    }
    await this.store.delete(grant.providerId, grant.grantId);
  }

  /** Exchange the auth code for tokens. */
  private async exchangeCode(
    provider: LegacyProvider,
    config: ClientConfig,
    code: string,
    pkceVerifier: string | null,
  ): Promise<AccessToken> {
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: config.clientId,
      redirect_uri: this.resolveRedirectUri(config),
    });
    if (config.clientSecret) body.set('client_secret', config.clientSecret);
    if (pkceVerifier) body.set('code_verifier', pkceVerifier);

    const res = await this.fetchImpl(provider.oauthTokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    if (!res.ok) {
      await audit('oauth.exchange', 'error', { providerId: provider.id, detail: `http_${res.status}` });
      throw new OAuthError(`code exchange failed: HTTP ${res.status}`, 'exchange_http_error');
    }
    const json = (await res.json()) as Record<string, unknown>;
    return parseTokenResponse(json, null);
  }

  private gcPending(): void {
    const cutoff = Date.now() - this.pendingTtlMs;
    for (const [k, v] of this.pending) {
      if (v.createdAt < cutoff) this.pending.delete(k);
    }
  }

  /**
   * Test/inspection — count of in-flight in-memory pending grants.
   * When a `pendingStore` is wired, in-flight state lives on disk and
   * this returns 0; the on-disk entry count isn't surfaced here
   * because the disk store is the source of truth and tests for it
   * inspect the store directly.
   */
  pendingCount(): number {
    this.gcPending();
    return this.pending.size;
  }
}

function parseTokenResponse(json: Record<string, unknown>, fallbackRefresh: string | null): AccessToken {
  const access = json.access_token;
  if (typeof access !== 'string') {
    throw new OAuthError('token response missing access_token', 'malformed_response');
  }
  const expiresIn = typeof json.expires_in === 'number' ? json.expires_in : 3600;
  const refresh = typeof json.refresh_token === 'string' ? json.refresh_token : fallbackRefresh;
  const scopes = typeof json.scope === 'string' ? json.scope : '';
  return {
    accessToken: access,
    refreshToken: refresh,
    expiresAt: Date.now() + expiresIn * 1000,
    scopes,
    providerExtras: json,
  };
}

```
