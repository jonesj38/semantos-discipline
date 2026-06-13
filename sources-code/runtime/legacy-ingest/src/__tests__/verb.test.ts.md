---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/verb.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.154096+00:00
---

# runtime/legacy-ingest/src/__tests__/verb.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { makeRouteLegacy, type LegacyVerbContext } from '../verb';
import {
  OAuthOrchestrator,
  ProviderRegistry,
  type ClientConfig,
  type FetchLike,
} from '../oauth';
import { LegacyGrantStore, type GrantPersistence } from '../grant-store';
import { LegacyBlobStore } from '../blob-store';
import { CursorStore } from '../cursor-store';
import { IngestWorker } from '../ingest-worker';
import type { LegacyProvider, ListPageResult, RawItem, AccessToken, Cursor } from '../types';

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
  oauthScopes: ['scope1'],
  oauthAuthorizeUrl: 'https://example.com/auth',
  oauthTokenUrl: 'https://example.com/token',
  oauthRevokeUrl: 'https://example.com/revoke',
  async listPage(): Promise<ListPageResult> { return { items: [], nextCursor: null }; },
  async fetchFull(_t: AccessToken, item: RawItem) { return item; },
  fingerprint(item: RawItem) { return item.providerItemId; },
};

const stubConfig: ClientConfig = {
  clientId: 'cid',
  clientSecret: 'csec',
  redirectUri: 'https://x/cb',
};

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

function tokenFetch(): FetchLike {
  return async (url) => {
    const u = typeof url === 'string' ? url : url.toString();
    if (u === 'https://example.com/token') {
      return new Response(JSON.stringify({
        access_token: 'a', refresh_token: 'r', expires_in: 3600,
      }), { status: 200 });
    }
    if (u === 'https://example.com/revoke') {
      return new Response('', { status: 200 });
    }
    throw new Error('unknown url ' + u);
  };
}

describe('legacy verb', () => {
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let orch: OAuthOrchestrator;
  let openedUrl: string | null;
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;

  beforeEach(async () => {
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    const kek = await makeKek();
    store = new LegacyGrantStore({ persistence: new MemoryPersistence(), kekProvider: async () => kek });
    orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: tokenFetch(),
    });
    openedUrl = null;
    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      openBrowser: (u) => { openedUrl = u; },
    });
  });

  test('connect <unknown> returns error', async () => {
    const r = await routeLegacy({ positional: ['connect', 'nope'] }, null) as { error?: string };
    expect(r.error).toMatch(/unknown provider/);
  });

  test('connect <gmail> returns authorize URL and opens browser', async () => {
    const r = await routeLegacy({ positional: ['connect', 'gmail'] }, null) as { ok: boolean; authorizeUrl: string };
    expect(r.ok).toBe(true);
    expect(r.authorizeUrl).toMatch(/https:\/\/example\.com\/auth\?/);
    expect(openedUrl).toBe(r.authorizeUrl);
  });

  test('status with no grants returns empty grants block per provider', async () => {
    const r = await routeLegacy({ positional: ['status'] }, null) as { providers: Record<string, { grants: unknown[] }> };
    expect(r.providers.gmail.grants).toEqual([]);
  });

  test('status after grant + disconnect cycle reflects state correctly', async () => {
    // Connect, callback to create a grant
    const c = await routeLegacy({ positional: ['connect', 'gmail'] }, null) as { stateNonce: string };
    const grant = await orch.handleCallback({ state: c.stateNonce, code: 'auth' });
    let r = await routeLegacy({ positional: ['status', 'gmail'] }, null) as { providers: Record<string, { grants: Array<{ grantId: string }> }> };
    expect(r.providers.gmail.grants.length).toBe(1);
    expect(r.providers.gmail.grants[0].grantId).toBe(grant.grantId);

    // Disconnect
    const d = await routeLegacy({ positional: ['disconnect', 'gmail'] }, null) as { ok: boolean; disconnected: number };
    expect(d.disconnected).toBe(1);

    // Status now empty
    r = await routeLegacy({ positional: ['status', 'gmail'] }, null) as { providers: Record<string, { grants: unknown[] }> };
    expect(r.providers.gmail.grants).toEqual([]);
  });

  test('providers lists registered providers', async () => {
    const r = await routeLegacy({ positional: ['providers'] }, null) as { providers: any[] };
    expect(r.providers.length).toBe(1);
    expect(r.providers[0].id).toBe('gmail');
  });

  test('help / unknown subcommand returns the verb list', async () => {
    const r = await routeLegacy({ positional: ['help'] }, null) as { verbs: string[] };
    expect(r.verbs.some(v => v.startsWith('legacy connect'))).toBe(true);
    expect(r.verbs.some(v => v.startsWith('legacy disconnect'))).toBe(true);
  });

  test('disconnect on a provider with no grants is a no-op', async () => {
    const r = await routeLegacy({ positional: ['disconnect', 'gmail'] }, null) as { disconnected: number };
    expect(r.disconnected).toBe(0);
  });

  test('resume completes the grant after operator pastes (state, code)', async () => {
    // Operator-side: connect produces a state nonce
    const c = await routeLegacy({ positional: ['connect', 'gmail'] }, null) as { stateNonce: string };
    // Browser-side: callback page would render the (state, code) pair
    // for the operator to paste. Simulate that paste here.
    const r = await routeLegacy(
      { positional: ['resume', c.stateNonce, 'auth-code-from-callback'] },
      null,
    ) as { ok?: boolean; providerId?: string; grantId?: string; tokenExpiresAt?: string };
    expect(r.ok).toBe(true);
    expect(r.providerId).toBe('gmail');
    expect(r.grantId).toBeTruthy();
    expect(r.tokenExpiresAt).toBeTruthy();

    // Verify the grant actually persists.
    const grants = await store.listByProvider('gmail');
    expect(grants.length).toBe(1);
    expect(grants[0].grantId).toBe(r.grantId);
  });

  test('resume rejects an unknown state nonce', async () => {
    const r = await routeLegacy(
      { positional: ['resume', 'never-issued-nonce', 'some-code'] },
      null,
    ) as { error?: string };
    expect(r.error).toMatch(/state nonce/);
  });

  test('resume requires both state and code', async () => {
    const r = await routeLegacy({ positional: ['resume'] }, null) as { error?: string };
    expect(r.error).toMatch(/Usage: legacy resume/);
    const r2 = await routeLegacy({ positional: ['resume', 'just-state'] }, null) as { error?: string };
    expect(r2.error).toMatch(/Usage: legacy resume/);
  });

  test('help lists the resume verb', async () => {
    const r = await routeLegacy({ positional: ['help'] }, null) as { verbs: string[] };
    expect(r.verbs.some(v => v.startsWith('legacy resume'))).toBe(true);
  });

  test('ingest reports error when worker is not configured', async () => {
    const r = await routeLegacy({ positional: ['ingest', 'gmail'] }, null) as { error?: string };
    expect(r.error).toMatch(/worker not configured/);
  });

  test('auto reports error when worker is not configured', async () => {
    const r = await routeLegacy({ positional: ['auto', 'gmail'] }, null) as { error?: string };
    expect(r.error).toMatch(/worker not configured|no grants/);
  });

  test('register-client reports error when client config store is not configured', async () => {
    const r = await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: { 'client-id': 'x', 'redirect-uri': 'https://x' },
    }, null) as { error?: string };
    expect(r.error).toMatch(/client config store not configured/);
  });
});

describe('legacy verb (client config: register / unregister / list)', () => {
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let store: LegacyGrantStore;
  let registry: ProviderRegistry;
  let orch: OAuthOrchestrator;
  let configStore: import('../client-config-store').ClientConfigStore;
  let configCache: import('../client-config-store').CachedClientConfigProvider;

  beforeEach(async () => {
    const kek = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    const persistence = new MemoryPersistence();
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    const { ClientConfigStore, CachedClientConfigProvider } = await import('../client-config-store');
    configStore = new ClientConfigStore({ persistence, kekProvider: async () => kek });
    configCache = new CachedClientConfigProvider(configStore);
    orch = new OAuthOrchestrator({
      registry, store,
      configProvider: configCache.get,
      fetch: tokenFetch(),
    });
    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      clientConfigStore: configStore,
      clientConfigCache: configCache,
      hatIdProvider: () => 'hat-1',
    });
  });

  test('register-client persists credentials and reloads cache so connect works', async () => {
    const r = await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': '0123-test.apps.googleusercontent.com',
        'client-secret': 'GOCSPX-test-secret',
        'redirect-uri': 'https://oddjobtodd.info/auth/callback',
      },
    }, null) as { ok: boolean; redirectUri: string; hasClientSecret: boolean };
    expect(r.ok).toBe(true);
    expect(r.hasClientSecret).toBe(true);
    expect(r.redirectUri).toBe('https://oddjobtodd.info/auth/callback');

    // connect should now succeed (cache was reloaded).
    const c = await routeLegacy({ positional: ['connect', 'gmail'] }, null) as { ok: boolean; authorizeUrl: string };
    expect(c.ok).toBe(true);
    expect(c.authorizeUrl).toMatch(/client_id=0123-test\.apps\.googleusercontent\.com/);
  });

  test('register-client rejects unknown provider', async () => {
    const r = await routeLegacy({
      positional: ['register-client', 'unknown'],
      flags: { 'client-id': 'x', 'redirect-uri': 'https://x' },
    }, null) as { error?: string };
    expect(r.error).toMatch(/unknown provider/);
  });

  test('register-client requires client-id and redirect-uri', async () => {
    const a = await routeLegacy({ positional: ['register-client', 'gmail'], flags: {} }, null) as { error?: string };
    expect(a.error).toMatch(/client-id/);
    const b = await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: { 'client-id': 'x' },
    }, null) as { error?: string };
    expect(b.error).toMatch(/redirect-uri/);
  });

  test('clients lists registered providers without exposing the secret', async () => {
    await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': '0123456789-abcdefghij.apps.googleusercontent.com',
        'client-secret': 'GOCSPX-DO-NOT-LEAK',
        'redirect-uri': 'https://oddjobtodd.info/auth/callback',
      },
    }, null);
    const r = await routeLegacy({ positional: ['clients'] }, null) as {
      clients: Array<{ providerId: string; clientIdFingerprint: string; hasClientSecret: boolean }>;
    };
    expect(r.clients.length).toBe(1);
    expect(r.clients[0].providerId).toBe('gmail');
    // First 8 + last 4 of the test clientId "0123456789-abcdefghij.apps.googleusercontent.com"
    expect(r.clients[0].clientIdFingerprint).toBe('01234567\u2026.com');
    expect(r.clients[0].hasClientSecret).toBe(true);
    // Defensive: the *full* secret value must never appear anywhere in the response.
    expect(JSON.stringify(r)).not.toContain('GOCSPX-DO-NOT-LEAK');
  });

  test('unregister-client removes the credentials and connect fails again', async () => {
    await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': 'x',
        'client-secret': 's',
        'redirect-uri': 'https://x',
      },
    }, null);
    const u = await routeLegacy({ positional: ['unregister-client', 'gmail'] }, null) as { ok: boolean };
    expect(u.ok).toBe(true);
    // Cache forgot it; connect should now fail with "no client config".
    const c = await routeLegacy({ positional: ['connect', 'gmail'] }, null) as { error?: string };
    expect(c.error).toMatch(/no client config/);
  });

  test('unregister-client on a never-registered provider is a clean no-op', async () => {
    const r = await routeLegacy({ positional: ['unregister-client', 'gmail'] }, null) as { ok: boolean; note?: string };
    expect(r.ok).toBe(true);
    expect(r.note).toMatch(/no client config registered/);
  });

  test('register-client without client-secret marks hasClientSecret=false', async () => {
    const r = await routeLegacy({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': 'x',
        'redirect-uri': 'https://x',
        pkce: true,
      },
    }, null) as { ok: boolean; hasClientSecret: boolean; pkce: boolean };
    expect(r.ok).toBe(true);
    expect(r.hasClientSecret).toBe(false);
    expect(r.pkce).toBe(true);
  });

  test('help lists the new client-config verbs', async () => {
    const r = await routeLegacy({ positional: ['help'] }, null) as { verbs: string[] };
    expect(r.verbs.some(v => v.startsWith('legacy register-client'))).toBe(true);
    expect(r.verbs.some(v => v.startsWith('legacy unregister-client'))).toBe(true);
    expect(r.verbs.some(v => v === 'legacy clients')).toBe(true);
  });
});

describe('legacy verb LI2 (ingest + auto + status detail)', () => {
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let orch: OAuthOrchestrator;
  let blobStore: LegacyBlobStore;
  let cursorStore: CursorStore;
  let worker: IngestWorker;
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let stopFns: Map<string, () => void>;
  let provider: LegacyProvider;

  beforeEach(async () => {
    const kek = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    const persistence = new MemoryPersistence();
    registry = new ProviderRegistry();

    let listIdx = 0;
    provider = {
      id: 'gmail', displayName: 'Gmail', oauthScopes: ['s'],
      oauthAuthorizeUrl: 'https://example.com/auth',
      oauthTokenUrl: 'https://example.com/token',
      oauthRevokeUrl: 'https://example.com/revoke',
      async listPage(_t: AccessToken, opts: { cursor: Cursor }): Promise<ListPageResult> {
        listIdx += 1;
        if (listIdx === 1) {
          return {
            items: [{
              providerId: 'gmail', providerItemId: `m${listIdx}`, fetchedAt: Date.now(),
              contentType: 'gmail/preview', bytes: new Uint8Array(0), metadata: {},
            }],
            nextCursor: null,
          };
        }
        return { items: [], nextCursor: null };
      },
      async fetchFull(_t: AccessToken, item: RawItem) {
        return { ...item, contentType: 'email/rfc822', bytes: new TextEncoder().encode('body') };
      },
      fingerprint(item: RawItem) { return `gmail:${item.providerItemId}`; },
    };
    registry.register(provider);

    store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    blobStore = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
    cursorStore = new CursorStore({ persistence });
    orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: tokenFetch(),
    });
    worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async (id) => {
        const grants = await store.listByProvider(id);
        return grants[0] ?? null;
      },
    });
    stopFns = new Map();
    const ctx: LegacyVerbContext = {
      registry, store, orchestrator: orch,
      blobStore, cursorStore, worker,
      continuousHandles: stopFns,
    };
    routeLegacy = makeRouteLegacy(ctx);
  });

  test('ingest fails cleanly when no grant exists', async () => {
    const r = await routeLegacy({ positional: ['ingest', 'gmail'] }, null) as { error?: string };
    expect(r.error).toMatch(/no grant/);
  });

  test('ingest after a grant runs the worker', async () => {
    // Grant
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    // Ingest
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null) as { ok: boolean; itemsPersisted: number; completed: boolean };
    expect(r.ok).toBe(true);
    expect(r.itemsPersisted).toBe(1);
    expect(r.completed).toBe(true);
  });

  test('status includes ingest checkpoint + raw item count after ingest', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    await routeLegacy({ positional: ['ingest', 'gmail'] }, null);
    const r = await routeLegacy({ positional: ['status', 'gmail'] }, null) as {
      providers: { gmail: { grants: Array<{ ingest?: { itemsPersisted: number } }>; rawItemsStored: number } };
    };
    expect(r.providers.gmail.rawItemsStored).toBe(1);
    expect(r.providers.gmail.grants[0].ingest?.itemsPersisted).toBe(1);
  });

  test('auto registers a continuous handle, stop tears it down', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const a = await routeLegacy({ positional: ['auto', 'gmail'], flags: { interval: 60 } }, null) as { ok: boolean; started: string[] };
    expect(a.ok).toBe(true);
    expect(a.started.length).toBe(1);
    expect(stopFns.size).toBe(1);

    const s = await routeLegacy({ positional: ['stop', 'gmail'] }, null) as { stopped: number };
    expect(s.stopped).toBe(1);
    expect(stopFns.size).toBe(0);
  });

  test('ingest with --since parses iso date', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { since: '2024-01-01T00:00:00Z', 'max-pages': 1 },
    }, null) as { ok: boolean };
    expect(r.ok).toBe(true);
  });

  test('ingest --query without provider returns the updated usage string', async () => {
    const r = await routeLegacy({ positional: ['ingest'] }, null) as { error: string };
    expect(r.error).toContain('--query');
  });
});

// ── --query flow: verb → BackfillOpts → provider.listPage ──
//
// These live in their own describe so the listPage stub can capture the
// opts object — the LI2 describe's stub uses a closure-counted `listIdx`
// that shadows the simpler "echo opts" we want here, and ProviderRegistry
// disallows re-registering the same id.

describe('legacy verb (--query flow)', () => {
  let listOptsSeen: { cursor: Cursor; since?: number; query?: string } | null;
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let orch: OAuthOrchestrator;

  beforeEach(async () => {
    listOptsSeen = null;
    const kek = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt'],
    );
    const persistence = new MemoryPersistence();
    const registry = new ProviderRegistry();
    const captureProvider: LegacyProvider = {
      id: 'gmail', displayName: 'Gmail', oauthScopes: ['s'],
      oauthAuthorizeUrl: 'https://example.com/auth',
      oauthTokenUrl: 'https://example.com/token',
      oauthRevokeUrl: 'https://example.com/revoke',
      async listPage(_t, opts) { listOptsSeen = opts; return { items: [], nextCursor: null }; },
      async fetchFull(_t, item) { return item; },
      fingerprint(item) { return `gmail:${item.providerItemId}`; },
    };
    registry.register(captureProvider);

    const store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    const blobStore = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
    const cursorStore = new CursorStore({ persistence });
    orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: tokenFetch(),
    });
    const worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async (id) => {
        const grants = await store.listByProvider(id);
        return grants[0] ?? null;
      },
    });
    const ctx: LegacyVerbContext = {
      registry, store, orchestrator: orch,
      blobStore, cursorStore, worker,
      continuousHandles: new Map(),
    };
    routeLegacy = makeRouteLegacy(ctx);
  });

  test('--query forwards the filter string to provider.listPage', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { query: 'from:bricksandagent.com', 'max-pages': 1 },
    }, null) as { ok: boolean };
    expect(r.ok).toBe(true);
    expect(listOptsSeen).not.toBeNull();
    expect(listOptsSeen!.query).toBe('from:bricksandagent.com');
  });

  test('omitting --query forwards `query: undefined` (back-compat)', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null);
    expect(listOptsSeen).not.toBeNull();
    expect(listOptsSeen!.query).toBeUndefined();
  });

  test('empty-string --query is ignored (treated as no filter)', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { query: '', 'max-pages': 1 },
    }, null);
    expect(listOptsSeen!.query).toBeUndefined();
  });
});

// ── D-DOG.1.0 — chained ingest+extract verb path ──
//
// The verb wraps `IngestWorker.backfill` followed by an optional
// `ExtractionRunner.runForProvider` so a single `legacy ingest` call
// produces both blobs and proposals. These tests exercise:
//   • the runner is invoked when ctx.extractionRunner is wired
//   • `--no-extract` skips the runner with an explicit reason
//   • absent runner returns a "not wired" reason without crashing
//   • runner errors do NOT mask the (already-completed) ingest result

describe('legacy verb (D-DOG.1.0 chained extract)', () => {
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let store: LegacyGrantStore;
  let registry: ProviderRegistry;
  let orch: OAuthOrchestrator;
  let blobStore: LegacyBlobStore;
  let cursorStore: CursorStore;
  let worker: IngestWorker;
  let proposalStore: import('../proposal-store').ProposalStore;
  let runCount: { invoked: number; throws: boolean; lastOpts: { force?: boolean } | null };
  let stopFns: Map<string, () => void>;

  // A stub provider that always returns one item per page so the
  // worker has something to persist before the runner sees it.
  const oneItemProvider: LegacyProvider = {
    id: 'gmail',
    displayName: 'Gmail',
    oauthScopes: ['scope1'],
    oauthAuthorizeUrl: 'https://example.com/auth',
    oauthTokenUrl: 'https://example.com/token',
    oauthRevokeUrl: 'https://example.com/revoke',
    async listPage(): Promise<ListPageResult> {
      return { items: [{
        providerId: 'gmail',
        providerItemId: 'm1',
        fetchedAt: 1,
        contentType: 'email/rfc822',
        bytes: new TextEncoder().encode('From: a@b\nSubject: x\n\nbody'),
        metadata: {},
      }], nextCursor: null };
    },
    async fetchFull(_t: AccessToken, item: RawItem) { return item; },
    fingerprint(item: RawItem) { return item.providerItemId; },
  };

  beforeEach(async () => {
    runCount = { invoked: 0, throws: false, lastOpts: null };
    const persistence = new MemoryPersistence();
    const kek = await makeKek();
    registry = new ProviderRegistry();
    registry.register(oneItemProvider);
    store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    blobStore = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
    cursorStore = new CursorStore({ persistence });
    const { ProposalStore } = await import('../proposal-store');
    proposalStore = new ProposalStore({ persistence, kekProvider: async () => kek });
    orch = new OAuthOrchestrator({
      registry, store, configProvider: () => stubConfig, fetch: tokenFetch(),
    });
    worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async (id) => {
        const grants = await store.listByProvider(id);
        return grants[0] ?? null;
      },
    });
    stopFns = new Map();

    // Stub ExtractionRunner — counts invocations + can simulate
    // failure. We only care here that the verb wires it correctly,
    // not that the runner itself works (its own suite covers that).
    const stubRunner = {
      runForProvider: async (_id: string, opts?: { force?: boolean }) => {
        runCount.invoked += 1;
        runCount.lastOpts = opts ?? {};
        if (runCount.throws) throw new Error('extract blew up');
        return {
          providerId: 'gmail',
          itemsExamined: 1,
          extracted: 1,
          preFiltered: 0,
          lowConfidence: 0,
          noExtractor: 0,
          errors: 0,
          threadFolds: 0,
        };
      },
    } as unknown as import('../extractor/runner').ExtractionRunner;

    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      blobStore, cursorStore, worker,
      continuousHandles: stopFns,
      proposalStore,
      extractionRunner: stubRunner,
    });
  });

  test('ingest invokes the extraction runner when wired', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null) as { ok: boolean; itemsPersisted: number; extract: { extracted?: number; skipped?: string } };
    expect(r.ok).toBe(true);
    expect(r.itemsPersisted).toBe(1);
    expect(runCount.invoked).toBe(1);
    expect(r.extract.extracted).toBe(1);
  });

  test('ingest --no-extract skips the runner with an explicit reason', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1, 'no-extract': true },
    }, null) as { ok: boolean; extract: { skipped?: string } };
    expect(r.ok).toBe(true);
    expect(runCount.invoked).toBe(0);
    expect(r.extract.skipped).toMatch(/no-extract/);
  });

  test('ingest with no flags passes force:false to the runner', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null) as { ok: boolean };
    expect(r.ok).toBe(true);
    expect(runCount.invoked).toBe(1);
    expect(runCount.lastOpts?.force).toBe(false);
  });

  test('ingest --reextract passes force:true to the runner', async () => {
    // Operator wants to re-extract over existing blobs (e.g. after a
    // prompt upgrade like PR #361's point_of_contact addition) without
    // re-fetching from Gmail. The runner's default skips items with
    // prior proposals; --reextract forces it to re-walk all of them.
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1, reextract: true },
    }, null) as { ok: boolean };
    expect(r.ok).toBe(true);
    expect(runCount.invoked).toBe(1);
    expect(runCount.lastOpts?.force).toBe(true);
  });

  test('ingest --reextract with --no-extract still skips (no-extract wins)', async () => {
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1, 'no-extract': true, reextract: true },
    }, null) as { ok: boolean; extract: { skipped?: string } };
    expect(r.ok).toBe(true);
    expect(runCount.invoked).toBe(0);
    expect(r.extract.skipped).toMatch(/no-extract/);
  });

  test('ingest reports "no extraction runner wired" when ctx.extractionRunner is absent', async () => {
    // Re-wire ctx without a runner.
    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      blobStore, cursorStore, worker,
      continuousHandles: stopFns,
      proposalStore,
    });
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null) as { ok: boolean; extract: { skipped?: string } };
    expect(r.ok).toBe(true);
    expect(r.extract.skipped).toMatch(/no extraction runner/);
  });

  test('ingest surfaces extract errors without masking the ingest result', async () => {
    runCount.throws = true;
    const prep = await orch.prepareGrant('gmail');
    await orch.handleCallback({ state: prep.stateNonce, code: 'auth' });
    const r = await routeLegacy({
      positional: ['ingest', 'gmail'],
      flags: { 'max-pages': 1 },
    }, null) as { ok: boolean; itemsPersisted: number; extract: { skipped?: string } };
    // Ingest still completed (1 blob persisted); only the extract leg
    // failed. The verb surfaces both so the operator can re-run extract
    // without re-fetching blobs.
    expect(r.ok).toBe(true);
    expect(r.itemsPersisted).toBe(1);
    expect(r.extract.skipped).toMatch(/extract error: extract blew up/);
  });
});

// ── Tier 1.7 — `legacy review` surfaces the deep-PDF fields ──
//
// The new fields ride on the proposalSummary so the operator gets
// primary contact / billing party / WO# / dates / source path at
// first glance, without a `--detail` flag. Older proposals (without
// the fields) keep their existing shape.

describe('legacy verb (Tier 1.7 review surfaces deep-PDF fields)', () => {
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let proposalStore: import('../proposal-store').ProposalStore;
  let registry: ProviderRegistry;
  let store: LegacyGrantStore;
  let orch: OAuthOrchestrator;

  beforeEach(async () => {
    const persistence = new MemoryPersistence();
    const kek = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt'],
    );
    registry = new ProviderRegistry();
    registry.register(stubProvider);
    store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    const { ProposalStore } = await import('../proposal-store');
    proposalStore = new ProposalStore({ persistence, kekProvider: async () => kek });
    orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: tokenFetch(),
    });
    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      proposalStore,
    });
  });

  test('review surfaces primaryContact, billingParty, workOrderNumber, dueDate, sourceAttachmentPath', async () => {
    const proposal = {
      proposalId: 'p1',
      confidence: 0.92,
      status: 'pending' as const,
      provenance: {
        providerId: 'gmail',
        providerItemId: 'msg-1',
        fetchedAt: 1000,
        extractorVersion: 'email-rfc822-v0.5',
        promptHash: 'h1',
      },
      extractedAt: 2000,
      program: {} as any,
      pointOfContact: 'Jo-Anne Bisman (tenant)',
      summary: 'Paint ceiling at 29 Foedera Cres.',
      workOrderNumber: '07487',
      issuanceDate: '2026-03-17',
      dueDate: '2026-03-24',
      propertyAddress: '29 Foedera Cres, Tewantin QLD 4565',
      propertyKey: 'key #177',
      primaryContact: {
        name: 'Jo-Anne Bisman',
        role: 'tenant' as const,
        phone: '0450688322',
        email: 'josiesingh@bigpond.com',
      },
      secondaryContacts: [
        { name: 'Zoe Welch', role: 'agent' as const, phone: '0754730508', email: null },
      ],
      ownerName: 'Adrian Levy',
      billingParty: { type: 'agency' as const, name: 'Clever Property' },
      hasPhotos: true,
      photoCount: 2,
      sourceAttachmentPath: 'legacy-ingest/gmail/msg-1#attachment-0',
    };
    await proposalStore.put(proposal);

    const r = await routeLegacy({ positional: ['review'] }, null) as {
      pending: number;
      proposals: Array<Record<string, unknown>>;
    };
    expect(r.pending).toBe(1);
    const summary = r.proposals[0];
    expect(summary.workOrderNumber).toBe('07487');
    expect(summary.dueDate).toBe('2026-03-24');
    expect(summary.issuanceDate).toBe('2026-03-17');
    expect(summary.propertyKey).toBe('key #177');
    expect(summary.propertyAddress).toBe('29 Foedera Cres, Tewantin QLD 4565');
    expect(summary.ownerName).toBe('Adrian Levy');
    expect(summary.billingParty).toEqual({
      type: 'agency',
      name: 'Clever Property',
    });
    expect(summary.primaryContact).toMatchObject({
      name: 'Jo-Anne Bisman',
      role: 'tenant',
      phone: '0450688322',
    });
    expect(summary.hasPhotos).toBe(true);
    expect(summary.photoCount).toBe(2);
    expect(summary.sourceAttachmentPath).toBe(
      'legacy-ingest/gmail/msg-1#attachment-0',
    );
    // Display alias preserved.
    expect(summary.pointOfContact).toBe('Jo-Anne Bisman (tenant)');
  });

  test('review keeps the old shape for v0.4 proposals (new fields omitted, not null)', async () => {
    // Older proposal without any of the new fields. The review verb
    // omits them entirely so the JSON shape stays clean for older
    // queues (a downstream JSON consumer that hasn't been updated
    // sees no spurious nulls).
    const proposal = {
      proposalId: 'p2',
      confidence: 0.88,
      status: 'pending' as const,
      provenance: {
        providerId: 'gmail',
        providerItemId: 'msg-2',
        fetchedAt: 1000,
        extractorVersion: 'email-rfc822-v0.4',
        promptHash: 'h0',
      },
      extractedAt: 2000,
      program: {} as any,
      pointOfContact: 'Old Sender',
      summary: 'older proposal',
    };
    await proposalStore.put(proposal);
    const r = await routeLegacy({ positional: ['review'] }, null) as {
      proposals: Array<Record<string, unknown>>;
    };
    const summary = r.proposals[0];
    expect('workOrderNumber' in summary).toBe(false);
    expect('billingParty' in summary).toBe(false);
    expect('primaryContact' in summary).toBe(false);
    expect(summary.pointOfContact).toBe('Old Sender');
  });
});

// ── D-DOG.1.0c Phase 5 G.1 — `legacy migrate-to-graph` ──────────────
//
// Walks `<brainDataDir>/oddjobz/jobs.jsonl` for v1 (flat-shape) rows,
// matches each to its source proposal via the receipt store, and
// re-ratifies through the (stub-orchestrator-driven) graph-walk path.
// Un-matchable rows go into the `legacy-unsigned.jsonl` sidecar marker.

describe('legacy verb (Phase 5 G.1 migrate-to-graph)', () => {
  let routeLegacy: ReturnType<typeof makeRouteLegacy>;
  let proposalStore: import('../proposal-store').ProposalStore;
  let receiptStore: import('../ratification/store').ReceiptStore;
  let dataDir: string;
  let cleanup: (() => void) | null = null;
  // Stub ratification orchestrator — counts ratify calls + records the
  // proposal ids it saw. A real orchestrator depends on brain + a hat
  // provider; the verb's contract is "call ratify.ratify(provider, id)
  // for each matchable v1 row" so the stub asserts that contract
  // without dragging in the cell-writer.
  let ratifyCalls: Array<{ providerId: string; proposalId: string }>;

  beforeEach(async () => {
    const { mkdtempSync, rmSync } = await import('node:fs');
    const { tmpdir } = await import('node:os');
    const path = await import('node:path');
    dataDir = mkdtempSync(path.join(tmpdir(), 'd10c-phase5-migrate-'));
    cleanup = () => rmSync(dataDir, { recursive: true, force: true });

    const persistence = new MemoryPersistence();
    const kek = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt'],
    );
    const registry = new ProviderRegistry();
    registry.register(stubProvider);
    const store = new LegacyGrantStore({ persistence, kekProvider: async () => kek });
    const { ProposalStore } = await import('../proposal-store');
    const { ReceiptStore } = await import('../ratification/store');
    proposalStore = new ProposalStore({ persistence, kekProvider: async () => kek });
    receiptStore = new ReceiptStore({ persistence, kekProvider: async () => kek });
    const orch = new OAuthOrchestrator({
      registry, store,
      configProvider: () => stubConfig,
      fetch: tokenFetch(),
    });

    ratifyCalls = [];
    const stubRatification = {
      async ratify(providerId: string, proposalId: string) {
        ratifyCalls.push({ providerId, proposalId });
        return {
          receiptId: `r-${proposalId}`,
          proposalId,
          providerId,
          providerItemId: 'item-x',
          issuedAt: new Date().toISOString(),
          signedBy: { hatId: 'h-1', certId: null },
          // The graph-shaped cellId — JSON-stringified per the schema.
          cellId: JSON.stringify({ site: null, customers: [], job: 'graph-job-x', attachments: [] }),
          hadCorrection: false,
        };
      },
    } as unknown as import('../ratification/orchestrator').RatificationOrchestrator;

    routeLegacy = makeRouteLegacy({
      registry, store, orchestrator: orch,
      proposalStore, receiptStore,
      ratification: stubRatification,
      brainDataDir: dataDir,
    });
  });

  afterEach(() => {
    if (cleanup) cleanup();
    cleanup = null;
  });

  test('returns no-op result when jobs.jsonl is missing', async () => {
    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
    };
    expect(r.ok).toBe(true);
    expect(r.scanned).toBe(0);
    expect(r.migrated).toBe(0);
  });

  test('skips v2 rows (rows with siteRef)', async () => {
    const { writeFileSync, mkdirSync, existsSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });
    const v2Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'aabb', state: 'lead', created_at: 'x',
      siteRef: '00'.repeat(32),
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v2Row);

    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      flaggedLegacy: number;
    };
    expect(r.ok).toBe(true);
    expect(r.scanned).toBe(0);
    expect(r.migrated).toBe(0);
    expect(r.flaggedLegacy).toBe(0);
    expect(ratifyCalls.length).toBe(0);
    expect(existsSync(path.join(oddjobzDir, 'legacy-unsigned.jsonl'))).toBe(false);
  });

  test('migrates v1 rows that have a matching proposal in the proposal store', async () => {
    const { writeFileSync, mkdirSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });

    // Seed proposal store + receipt store: one v1 row with id `job-a`,
    // a receipt that stamped that id into cellId, and the source
    // proposal still in the store.
    const proposal = {
      proposalId: 'p-a',
      confidence: 0.9,
      status: 'ratified' as const,
      provenance: {
        providerId: 'gmail',
        providerItemId: 'msg-a',
        fetchedAt: 1,
        extractorVersion: 'v0.5',
        promptHash: 'h',
      },
      extractedAt: 2,
      program: {} as any,
      summary: 'Quote request',
    };
    await proposalStore.put(proposal);
    await receiptStore.put({
      receiptId: 'rec-a',
      proposalId: 'p-a',
      providerId: 'gmail',
      providerItemId: 'msg-a',
      issuedAt: new Date().toISOString(),
      signedBy: { hatId: 'h-1', certId: null },
      cellId: 'job-a',
      hadCorrection: false,
    });

    // v1 row in jobs.jsonl, no siteRef.
    const v1Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'job-a', state: 'lead', created_at: 'x',
      customer_name: 'Test Customer',
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v1Row);

    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      flaggedLegacy: number;
      migratedRows: Array<{ id: string; receiptId: string }>;
    };
    expect(r.ok).toBe(true);
    expect(r.scanned).toBe(1);
    expect(r.migrated).toBe(1);
    expect(r.flaggedLegacy).toBe(0);
    expect(ratifyCalls).toEqual([{ providerId: 'gmail', proposalId: 'p-a' }]);
    expect(r.migratedRows[0]?.id).toBe('job-a');
    expect(r.migratedRows[0]?.receiptId).toBe('r-p-a');
  });

  test('flags v1 rows with no matching receipt as legacy_unsigned', async () => {
    const { writeFileSync, mkdirSync, readFileSync, existsSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });
    const v1Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'orphan-job', state: 'lead', created_at: 'x',
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v1Row);

    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      flaggedLegacy: number;
      flaggedRows: Array<{ id: string; reason: string }>;
    };
    expect(r.scanned).toBe(1);
    expect(r.migrated).toBe(0);
    expect(r.flaggedLegacy).toBe(1);
    expect(r.flaggedRows[0]?.id).toBe('orphan-job');
    expect(ratifyCalls.length).toBe(0);

    const markerPath = path.join(oddjobzDir, 'legacy-unsigned.jsonl');
    expect(existsSync(markerPath)).toBe(true);
    const markerContent = readFileSync(markerPath, 'utf8');
    const lines = markerContent.split('\n').filter(l => l.length > 0);
    expect(lines.length).toBe(1);
    const entry = JSON.parse(lines[0]!);
    expect(entry.v1Id).toBe('orphan-job');
    expect(typeof entry.reason).toBe('string');
    expect(typeof entry.flaggedAt).toBe('string');
  });

  test('flags v1 rows whose receipt points at a missing proposal', async () => {
    const { writeFileSync, mkdirSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });

    // Receipt exists but proposal was pruned.
    await receiptStore.put({
      receiptId: 'rec-b',
      proposalId: 'p-missing',
      providerId: 'gmail',
      providerItemId: 'msg-b',
      issuedAt: new Date().toISOString(),
      signedBy: { hatId: 'h-1', certId: null },
      cellId: 'job-b',
      hadCorrection: false,
    });
    const v1Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'job-b', state: 'lead', created_at: 'x',
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v1Row);

    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      flaggedLegacy: number;
      proposalMissing: number;
    };
    expect(r.scanned).toBe(1);
    expect(r.migrated).toBe(0);
    expect(r.flaggedLegacy).toBe(1);
    expect(r.proposalMissing).toBe(1);
    expect(ratifyCalls.length).toBe(0);
  });

  test('--dry-run reports the migration plan without writing markers or calling ratify', async () => {
    const { writeFileSync, mkdirSync, existsSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });

    await proposalStore.put({
      proposalId: 'p-dry',
      confidence: 0.9,
      status: 'ratified' as const,
      provenance: {
        providerId: 'gmail',
        providerItemId: 'msg-dry',
        fetchedAt: 1,
        extractorVersion: 'v0.5',
        promptHash: 'h',
      },
      extractedAt: 2,
      program: {} as any,
      summary: 'dry run candidate',
    });
    await receiptStore.put({
      receiptId: 'rec-dry',
      proposalId: 'p-dry',
      providerId: 'gmail',
      providerItemId: 'msg-dry',
      issuedAt: new Date().toISOString(),
      signedBy: { hatId: 'h-1', certId: null },
      cellId: 'job-dry',
      hadCorrection: false,
    });
    const v1Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'job-dry', state: 'lead', created_at: 'x',
    }) + '\n';
    const v1Orphan = JSON.stringify({
      ts: 1, kind: 'created', id: 'job-orphan-dry', state: 'lead', created_at: 'x',
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v1Row + v1Orphan);

    const r = await routeLegacy({
      positional: ['migrate-to-graph'],
      flags: { 'dry-run': true },
    }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      flaggedLegacy: number;
      dryRun: boolean;
    };
    expect(r.dryRun).toBe(true);
    expect(r.scanned).toBe(2);
    expect(r.migrated).toBe(1);
    expect(r.flaggedLegacy).toBe(1);
    // Dry run never calls the orchestrator.
    expect(ratifyCalls.length).toBe(0);
    // Dry run never writes the marker file.
    expect(existsSync(path.join(oddjobzDir, 'legacy-unsigned.jsonl'))).toBe(false);
  });

  test('skips proposals already migrated to a graph-shaped receipt', async () => {
    const { writeFileSync, mkdirSync } = await import('node:fs');
    const path = await import('node:path');
    const oddjobzDir = path.join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });

    // Seed: a v1 receipt pointing at job-c, AND a v2 graph-shape
    // receipt for the same proposalId (the migration verb already ran
    // once; we don't want a re-run to migrate the proposal again).
    await proposalStore.put({
      proposalId: 'p-c',
      confidence: 0.9,
      status: 'ratified' as const,
      provenance: {
        providerId: 'gmail',
        providerItemId: 'msg-c',
        fetchedAt: 1,
        extractorVersion: 'v0.5',
        promptHash: 'h',
      },
      extractedAt: 2,
      program: {} as any,
      summary: 'already migrated',
    });
    await receiptStore.put({
      receiptId: 'rec-c-v1',
      proposalId: 'p-c',
      providerId: 'gmail',
      providerItemId: 'msg-c',
      issuedAt: new Date().toISOString(),
      signedBy: { hatId: 'h-1', certId: null },
      cellId: 'job-c',
      hadCorrection: false,
    });
    await receiptStore.put({
      receiptId: 'rec-c-v2',
      proposalId: 'p-c',
      providerId: 'gmail',
      providerItemId: 'msg-c',
      issuedAt: new Date().toISOString(),
      signedBy: { hatId: 'h-1', certId: null },
      cellId: JSON.stringify({ site: null, customers: [], job: 'graph-job-c', attachments: [] }),
      hadCorrection: false,
    });

    const v1Row = JSON.stringify({
      ts: 1, kind: 'created', id: 'job-c', state: 'lead', created_at: 'x',
    }) + '\n';
    writeFileSync(path.join(oddjobzDir, 'jobs.jsonl'), v1Row);

    const r = await routeLegacy({ positional: ['migrate-to-graph'] }, null) as {
      ok: boolean;
      scanned: number;
      migrated: number;
      alreadyMigrated: number;
      flaggedLegacy: number;
    };
    expect(r.scanned).toBe(1);
    expect(r.migrated).toBe(0);
    expect(r.alreadyMigrated).toBe(1);
    expect(r.flaggedLegacy).toBe(0);
    expect(ratifyCalls.length).toBe(0);
  });
});

```
