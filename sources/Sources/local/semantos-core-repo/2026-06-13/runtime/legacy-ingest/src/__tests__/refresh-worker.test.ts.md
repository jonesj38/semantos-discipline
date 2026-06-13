---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/refresh-worker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.143422+00:00
---

# runtime/legacy-ingest/src/__tests__/refresh-worker.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { RefreshWorker } from '../refresh-worker';
import { OAuthOrchestrator, ProviderRegistry, type ClientConfig, type FetchLike } from '../oauth';
import { LegacyGrantStore, type GrantPersistence } from '../grant-store';
import type { LegacyProvider, LegacyGrant, ListPageResult, RawItem, AccessToken } from '../types';

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
  oauthScopes: ['gmail.readonly'],
  oauthAuthorizeUrl: 'https://example.com/auth',
  oauthTokenUrl: 'https://example.com/token',
  oauthRevokeUrl: null,
  async listPage(): Promise<ListPageResult> { return { items: [], nextCursor: null }; },
  async fetchFull(_t: AccessToken, item: RawItem) { return item; },
  fingerprint(item: RawItem) { return item.providerItemId; },
};

const stubConfig: ClientConfig = {
  clientId: 'cid',
  clientSecret: 'csec',
  redirectUri: 'https://x/callback',
};

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

function tokenResp(accessToken: string): Response {
  return new Response(JSON.stringify({
    access_token: accessToken,
    expires_in: 3600,
  }), { status: 200, headers: { 'content-type': 'application/json' } });
}

function makeGrant(opts: { id: string; expiresInMs: number; refresh: string | null }): LegacyGrant {
  return {
    grantId: opts.id,
    providerId: 'gmail',
    createdAt: new Date(0).toISOString(),
    lastRefreshedAt: null,
    accountLabel: null,
    hatId: null,
    token: {
      accessToken: `${opts.id}-access`,
      refreshToken: opts.refresh,
      expiresAt: Date.now() + opts.expiresInMs,
      scopes: '',
      providerExtras: {},
    },
  };
}

describe('RefreshWorker', () => {
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let fetchCalls: number;
  let fetchImpl: FetchLike;

  beforeEach(async () => {
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    const kek = await makeKek();
    store = new LegacyGrantStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => kek,
    });
    fetchCalls = 0;
    fetchImpl = async () => {
      fetchCalls += 1;
      return tokenResp('rotated-access');
    };
  });

  test('refreshes only grants approaching expiry', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: fetchImpl,
    });
    await store.put(makeGrant({ id: 'soon', expiresInMs: 60_000, refresh: 'r1' }));
    await store.put(makeGrant({ id: 'far',  expiresInMs: 60 * 60 * 1000, refresh: 'r2' }));
    const worker = new RefreshWorker({
      store, orchestrator: orch, providers: ['gmail'],
      leadTimeMs: 5 * 60 * 1000,
    });
    await worker.tick();
    expect(fetchCalls).toBe(1);
    const soon = await store.get('gmail', 'soon');
    expect(soon?.token.accessToken).toBe('rotated-access');
    const far = await store.get('gmail', 'far');
    expect(far?.token.accessToken).toBe('far-access');
  });

  test('skips grants without a refresh token', async () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: fetchImpl,
    });
    await store.put(makeGrant({ id: 'no-rt', expiresInMs: 1000, refresh: null }));
    const worker = new RefreshWorker({ store, orchestrator: orch, providers: ['gmail'] });
    await worker.tick();
    expect(fetchCalls).toBe(0);
  });

  test('refresh failure is non-fatal; onFailure callback fires', async () => {
    const failingFetch: FetchLike = async () => new Response('boom', { status: 500 });
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: failingFetch,
    });
    await store.put(makeGrant({ id: 'g1', expiresInMs: 1000, refresh: 'r1' }));
    let failures = 0;
    const worker = new RefreshWorker({
      store, orchestrator: orch, providers: ['gmail'],
      onFailure: () => { failures += 1; },
    });
    await worker.tick();
    expect(failures).toBe(1);
  });

  test('start/stop are idempotent', () => {
    const orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: fetchImpl,
    });
    const worker = new RefreshWorker({ store, orchestrator: orch, providers: ['gmail'] });
    worker.start();
    worker.start(); // idempotent
    worker.stop();
    worker.stop(); // idempotent
  });
});

```
