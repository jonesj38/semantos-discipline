---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/oauth.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.147254+00:00
---

# runtime/legacy-ingest/src/__tests__/oauth.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import {
  OAuthOrchestrator,
  OAuthError,
  ProviderRegistry,
  type ClientConfig,
  type FetchLike,
} from '../oauth';
import { LegacyGrantStore, type GrantPersistence } from '../grant-store';
import { PendingStateStore, type PendingPersistence } from '../pending-state-store';
import type { LegacyProvider, ListPageResult, RawItem, AccessToken } from '../types';
import { setAuditSink, type AuditEntry } from '../audit';

class MemoryPersistence implements GrantPersistence {
  private store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

const stubProvider: LegacyProvider = {
  id: 'gmail',
  displayName: 'Gmail',
  oauthScopes: ['https://www.googleapis.com/auth/gmail.readonly'],
  oauthAuthorizeUrl: 'https://accounts.example.com/o/oauth2/auth',
  oauthTokenUrl: 'https://oauth2.example.com/token',
  oauthRevokeUrl: 'https://oauth2.example.com/revoke',
  async listPage(): Promise<ListPageResult> { return { items: [], nextCursor: null }; },
  async fetchFull(_t: AccessToken, item: RawItem) { return item; },
  fingerprint(item: RawItem) { return item.providerItemId; },
};

const stubConfig: ClientConfig = {
  clientId: 'test-client',
  clientSecret: 'test-secret',
  redirectUri: 'https://oddjobtodd.info/auth/callback',
  pkce: true,
};

function makeFetch(routes: Record<string, () => Response | Promise<Response>>): FetchLike {
  return async (url) => {
    const u = typeof url === 'string' ? url : url.toString();
    const handler = routes[u];
    if (!handler) throw new Error(`fetch: no stub for ${u}`);
    return handler();
  };
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

describe('OAuthOrchestrator', () => {
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let auditEntries: AuditEntry[];

  beforeEach(async () => {
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    const kek = await makeKek();
    store = new LegacyGrantStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => kek,
    });
    auditEntries = [];
    setAuditSink((e) => { auditEntries.push(e); });
  });

  test('prepareGrant returns an authorize URL with state nonce + PKCE challenge', async () => {
    const orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
    });
    const prepared = await orch.prepareGrant('gmail');
    const u = new URL(prepared.authorizeUrl);
    expect(u.origin + u.pathname).toBe(stubProvider.oauthAuthorizeUrl);
    expect(u.searchParams.get('client_id')).toBe('test-client');
    expect(u.searchParams.get('redirect_uri')).toBe(stubConfig.redirectUri);
    expect(u.searchParams.get('state')).toBe(prepared.stateNonce);
    expect(u.searchParams.get('code_challenge_method')).toBe('S256');
    expect(u.searchParams.get('code_challenge')).toBeTruthy();
    expect(orch.pendingCount()).toBe(1);
  });

  test('prepareGrant fails on unknown provider', async () => {
    const orch = new OAuthOrchestrator({ registry, store, configProvider: () => stubConfig });
    await expect(orch.prepareGrant('nope')).rejects.toThrow(OAuthError);
  });

  test('handleCallback exchanges code, persists grant, clears pending', async () => {
    const orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/token': () => new Response(JSON.stringify({
          access_token: 'access-123',
          refresh_token: 'refresh-456',
          expires_in: 3600,
          scope: stubProvider.oauthScopes.join(' '),
        }), { status: 200, headers: { 'content-type': 'application/json' } }),
      }),
    });
    const prepared = await orch.prepareGrant('gmail');
    const grant = await orch.handleCallback({ state: prepared.stateNonce, code: 'auth-code' });
    expect(grant.providerId).toBe('gmail');
    expect(grant.token.accessToken).toBe('access-123');
    expect(grant.token.refreshToken).toBe('refresh-456');
    expect(orch.pendingCount()).toBe(0);
    const stored = await store.get('gmail', grant.grantId);
    expect(stored?.token.accessToken).toBe('access-123');
  });

  test('handleCallback rejects unknown state nonce', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({}),
    });
    await expect(orch.handleCallback({ state: 'bogus', code: 'x' })).rejects.toThrow(/bad_state|state nonce/);
  });

  test('handleCallback rejects expired state nonce', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({}),
      pendingTtlMs: 0, // any pending state expires instantly
    });
    const prepared = await orch.prepareGrant('gmail');
    await new Promise(resolve => setTimeout(resolve, 5));
    await expect(orch.handleCallback({ state: prepared.stateNonce, code: 'x' })).rejects.toThrow(/expired|bad_state/);
  });

  test('refresh exchanges refresh_token and persists new access token', async () => {
    const orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/token': () => new Response(JSON.stringify({
          access_token: 'access-NEW',
          expires_in: 3600,
        }), { status: 200, headers: { 'content-type': 'application/json' } }),
      }),
    });
    const grant = {
      grantId: 'g-1',
      providerId: 'gmail',
      createdAt: new Date(0).toISOString(),
      lastRefreshedAt: null,
      accountLabel: null,
      hatId: null,
      token: {
        accessToken: 'access-OLD',
        refreshToken: 'refresh-keep',
        expiresAt: Date.now() + 60_000,
        scopes: '',
        providerExtras: {},
      },
    };
    await store.put(grant);
    const refreshed = await orch.refresh(grant);
    expect(refreshed.token.accessToken).toBe('access-NEW');
    expect(refreshed.token.refreshToken).toBe('refresh-keep'); // preserved when provider omits
    expect(refreshed.lastRefreshedAt).not.toBeNull();
  });

  test('disconnect best-effort revokes at provider then deletes locally', async () => {
    let revoked = false;
    const orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/revoke': () => {
          revoked = true;
          return new Response('', { status: 200 });
        },
      }),
    });
    const grant = {
      grantId: 'g-1', providerId: 'gmail',
      createdAt: '0', lastRefreshedAt: null, accountLabel: null, hatId: null,
      token: {
        accessToken: 'a', refreshToken: 'r',
        expiresAt: Date.now() + 60_000, scopes: '', providerExtras: {},
      },
    };
    await store.put(grant);
    await orch.disconnect(grant);
    expect(revoked).toBe(true);
    expect(await store.get('gmail', 'g-1')).toBeNull();
  });

  test('disconnect deletes local grant even when remote revoke fails', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/revoke': () => { throw new Error('network'); },
      }),
    });
    const grant = {
      grantId: 'g-1', providerId: 'gmail',
      createdAt: '0', lastRefreshedAt: null, accountLabel: null, hatId: null,
      token: { accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 60_000, scopes: '', providerExtras: {} },
    };
    await store.put(grant);
    await orch.disconnect(grant);
    expect(await store.get('gmail', 'g-1')).toBeNull();
  });

  test('audit log records prepare / grant / refresh / revoke', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/token': () => new Response(JSON.stringify({
          access_token: 'a', refresh_token: 'r', expires_in: 3600, scope: '',
        }), { status: 200 }),
        'https://oauth2.example.com/revoke': () => new Response('', { status: 200 }),
      }),
    });
    const prepared = await orch.prepareGrant('gmail');
    const grant = await orch.handleCallback({ state: prepared.stateNonce, code: 'c' });
    await orch.refresh(grant);
    await orch.disconnect(grant);
    const ops = auditEntries.map(e => e.op);
    expect(ops).toContain('oauth.prepare');
    expect(ops).toContain('oauth.grant');
    expect(ops).toContain('oauth.refresh');
    expect(ops).toContain('oauth.revoke.remote');
  });
});

// ── Disk-backed pending-state path (legacy-cli scenario) ──
//
// The bug this is regression-protecting against: the legacy-cli
// invokes `bun apps/legacy-cli/src/cli.ts <verb>` as a one-shot
// process per verb, so the in-memory `pending` Map dies between
// `legacy connect` (process A) and `legacy resume` (process B). The
// `pendingStore` opt makes pending state survive across processes —
// these tests simulate that by constructing a second OAuthOrchestrator
// pointed at the same store after the first has done `prepareGrant`.

class MemoryPendingPersistence implements PendingPersistence {
  private store = new Map<string, Uint8Array>();
  private mtimes = new Map<string, number>();
  /** Test seam — drives the mtime stamped on every write. */
  public clock: () => number = () => Date.now();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) {
    this.store.set(k, v);
    this.mtimes.set(k, this.clock());
  }
  async delete(k: string) {
    this.store.delete(k);
    this.mtimes.delete(k);
  }
  async list() { return [...this.store.keys()]; }
  async mtimeMs(k: string) { return this.mtimes.get(k) ?? null; }
}

describe('OAuthOrchestrator with disk-backed pendingStore', () => {
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let pendingPersistence: MemoryPendingPersistence;
  let kek: CryptoKey;

  beforeEach(async () => {
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    kek = await makeKek();
    store = new LegacyGrantStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => kek,
    });
    pendingPersistence = new MemoryPendingPersistence();
    setAuditSink(() => {});
  });

  test('prepareGrant in process A → handleCallback in process B (simulated restart)', async () => {
    // Process A: prepare a grant. The orchestrator is constructed,
    // writes pending state to the shared persistence, exits.
    const orchA = new OAuthOrchestrator({
      registry,
      store,
      configProvider: () => stubConfig,
      pendingStore: new PendingStateStore({
        persistence: pendingPersistence,
        kekProvider: async () => kek,
      }),
    });
    const prepared = await orchA.prepareGrant('gmail');
    // The in-memory Map on orchA was bypassed in favour of the disk store.
    expect(orchA.pendingCount()).toBe(0);

    // Process B: a fresh orchestrator (different instance, same disk
    // state) reads the pending state and completes the exchange.
    const orchB = new OAuthOrchestrator({
      registry,
      store,
      configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/token': () => new Response(JSON.stringify({
          access_token: 'access-from-process-B',
          refresh_token: 'refresh-456',
          expires_in: 3600,
          scope: stubProvider.oauthScopes.join(' '),
        }), { status: 200 }),
      }),
      pendingStore: new PendingStateStore({
        persistence: pendingPersistence,
        kekProvider: async () => kek,
      }),
    });
    const grant = await orchB.handleCallback({ state: prepared.stateNonce, code: 'c' });
    expect(grant.token.accessToken).toBe('access-from-process-B');
    // Pending entry was consumed.
    expect(await pendingPersistence.list()).toEqual([]);
  });

  test('handleCallback rejects unknown nonce against the disk store', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({}),
      pendingStore: new PendingStateStore({
        persistence: pendingPersistence,
        kekProvider: async () => kek,
      }),
    });
    await expect(orch.handleCallback({ state: 'never-prepared', code: 'x' }))
      .rejects.toThrow(/bad_state|state nonce/);
  });

  test('handleCallback rejects expired pending state (disk-backed TTL)', async () => {
    let now = 1_700_000_000_000;
    // Drive both the persistence's mtime stamping AND the store's
    // TTL clock from the same fake `now` — otherwise the persistence
    // stamps real-time mtimes and the store reads fake `now`, which
    // makes time appear to flow backwards.
    pendingPersistence.clock = () => now;
    const pendingStore = new PendingStateStore({
      persistence: pendingPersistence,
      kekProvider: async () => kek,
      pendingTtlMs: 1000,
      now: () => now,
    });
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({}),
      pendingStore,
    });
    const prepared = await orch.prepareGrant('gmail');
    // Advance past the TTL so the next get() returns null + deletes.
    now += 5000;
    await expect(orch.handleCallback({ state: prepared.stateNonce, code: 'x' }))
      .rejects.toThrow(/bad_state|state nonce/);
  });

  test('backward compat: in-memory path still works when no pendingStore is wired', async () => {
    // This is the same scenario as the original `handleCallback exchanges
    // code` test — repeated here under the new describe block to assert
    // that adding the pendingStore opt didn't break the embedded path
    // (widget server, in-process tests).
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig,
      fetch: makeFetch({
        'https://oauth2.example.com/token': () => new Response(JSON.stringify({
          access_token: 'access-in-memory',
          refresh_token: 'r',
          expires_in: 3600,
          scope: '',
        }), { status: 200 }),
      }),
    });
    const prepared = await orch.prepareGrant('gmail');
    expect(orch.pendingCount()).toBe(1);
    const grant = await orch.handleCallback({ state: prepared.stateNonce, code: 'c' });
    expect(grant.token.accessToken).toBe('access-in-memory');
    expect(orch.pendingCount()).toBe(0);
  });
});

```
