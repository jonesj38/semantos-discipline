---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/client-config-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.153796+00:00
---

# runtime/legacy-ingest/src/__tests__/client-config-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import {
  ClientConfigStore,
  CachedClientConfigProvider,
  type StoredClientConfig,
} from '../client-config-store';
import { GrantStoreCorrupt, GrantStoreLocked, type GrantPersistence } from '../grant-store';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

function makeStored(over: Partial<StoredClientConfig> = {}): StoredClientConfig {
  return {
    providerId: 'gmail',
    clientId: '0123456789-abcdefghij.apps.googleusercontent.com',
    clientSecret: 'GOCSPX-supersecret-do-not-leak',
    redirectUri: 'https://oddjobtodd.info/auth/callback',
    pkce: undefined,
    registeredAt: '2026-04-28T12:00:00Z',
    registeredBy: 'hat-1',
    ...over,
  };
}

describe('ClientConfigStore', () => {
  let persistence: MemoryPersistence;
  let store: ClientConfigStore;

  beforeEach(async () => {
    persistence = new MemoryPersistence();
    const kek = await makeKek();
    store = new ClientConfigStore({ persistence, kekProvider: async () => kek });
  });

  test('round-trip preserves the stored config', async () => {
    await store.put(makeStored());
    const got = await store.get('gmail');
    expect(got?.clientId).toBe('0123456789-abcdefghij.apps.googleusercontent.com');
    expect(got?.clientSecret).toBe('GOCSPX-supersecret-do-not-leak');
    expect(got?.redirectUri).toBe('https://oddjobtodd.info/auth/callback');
  });

  test('on-disk bytes never contain the plaintext clientSecret', async () => {
    await store.put(makeStored());
    const blob = [...persistence.store.values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    expect(text).not.toContain('GOCSPX-supersecret-do-not-leak');
    expect(text).not.toContain('0123456789-abcdefghij');
  });

  test('list returns all stored providers', async () => {
    await store.put(makeStored({ providerId: 'gmail' }));
    await store.put(makeStored({ providerId: 'meta-pages', clientSecret: 'meta-secret' }));
    const list = await store.list();
    expect(list.length).toBe(2);
    expect(list.map(c => c.providerId).sort()).toEqual(['gmail', 'meta-pages']);
  });

  test('delete removes the stored config', async () => {
    await store.put(makeStored());
    expect(await store.get('gmail')).not.toBeNull();
    await store.delete('gmail');
    expect(await store.get('gmail')).toBeNull();
  });

  test('locked store fails closed on put + get', async () => {
    const locked = new ClientConfigStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => null,
    });
    await expect(locked.put(makeStored())).rejects.toThrow(GrantStoreLocked);
    await expect(locked.get('gmail')).rejects.toThrow(GrantStoreLocked);
  });

  test('tampered ciphertext fails closed', async () => {
    await store.put(makeStored());
    const [k, blob] = [...persistence.store.entries()][0];
    blob[40] ^= 0xff;
    persistence.store.set(k, blob);
    await expect(store.get('gmail')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('decrypt with a different KEK fails closed', async () => {
    await store.put(makeStored());
    const otherKek = await makeKek();
    const otherStore = new ClientConfigStore({
      persistence,
      kekProvider: async () => otherKek,
    });
    await expect(otherStore.get('gmail')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('toClientConfig strips audit fields', async () => {
    const stored = makeStored({ pkce: true });
    const live = store.toClientConfig(stored);
    expect(live.clientId).toBe(stored.clientId);
    expect(live.clientSecret).toBe(stored.clientSecret);
    expect(live.redirectUri).toBe(stored.redirectUri);
    expect(live.pkce).toBe(true);
    expect(Object.keys(live).sort()).toEqual(['clientId', 'clientSecret', 'pkce', 'redirectUri']);
  });
});

describe('CachedClientConfigProvider', () => {
  let store: ClientConfigStore;
  let cache: CachedClientConfigProvider;

  beforeEach(async () => {
    const kek = await makeKek();
    store = new ClientConfigStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => kek,
    });
    cache = new CachedClientConfigProvider(store);
  });

  test('reload pulls all configs into the cache', async () => {
    await store.put(makeStored({ providerId: 'gmail' }));
    await store.put(makeStored({ providerId: 'meta-pages' }));
    await cache.reload();
    expect(cache.size()).toBe(2);
    expect(cache.get('gmail')).not.toBeNull();
    expect(cache.get('meta-pages')).not.toBeNull();
    expect(cache.get('xero')).toBeNull();
  });

  test('synchronous get returns ClientConfig without leaking audit fields', async () => {
    await store.put(makeStored());
    await cache.reload();
    const c = cache.get('gmail');
    expect(c).not.toBeNull();
    expect(Object.keys(c!).sort()).toEqual(['clientId', 'clientSecret', 'pkce', 'redirectUri']);
  });

  test('forget drops a single entry without re-listing', async () => {
    await store.put(makeStored({ providerId: 'gmail' }));
    await store.put(makeStored({ providerId: 'meta-pages' }));
    await cache.reload();
    cache.forget('gmail');
    expect(cache.get('gmail')).toBeNull();
    expect(cache.get('meta-pages')).not.toBeNull();
    expect(cache.size()).toBe(1);
  });

  test('cache survives orchestrator-style synchronous calls', async () => {
    await store.put(makeStored());
    await cache.reload();
    // Orchestrator's `configProvider` calls .get synchronously.
    const c = cache.get('gmail');
    expect(c?.clientId).toBe('0123456789-abcdefghij.apps.googleusercontent.com');
    // Re-call should still hit the cache (no async work).
    expect(cache.get('gmail')).toEqual(c);
  });
});

```
