---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/grant-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.150931+00:00
---

# runtime/legacy-ingest/src/__tests__/grant-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { LegacyGrantStore, GrantStoreLocked, GrantStoreCorrupt } from '../grant-store';
import type { GrantPersistence } from '../grant-store';
import type { LegacyGrant } from '../types';

class MemoryPersistence implements GrantPersistence {
  private store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) {
    return [...this.store.keys()].filter(k => k.startsWith(prefix));
  }
  raw(): Map<string, Uint8Array> { return this.store; }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

function makeGrant(over: Partial<LegacyGrant> = {}): LegacyGrant {
  return {
    grantId: 'g-1',
    providerId: 'gmail',
    createdAt: new Date(0).toISOString(),
    lastRefreshedAt: null,
    accountLabel: 'todd@example.com',
    hatId: 'hat-1',
    token: {
      accessToken: 'at-secret',
      refreshToken: 'rt-secret',
      expiresAt: Date.now() + 3600_000,
      scopes: 'https://www.googleapis.com/auth/gmail.readonly',
      providerExtras: {},
    },
    ...over,
  };
}

describe('LegacyGrantStore', () => {
  let persistence: MemoryPersistence;
  let kek: CryptoKey;
  let store: LegacyGrantStore;

  beforeEach(async () => {
    persistence = new MemoryPersistence();
    kek = await makeKek();
    store = new LegacyGrantStore({
      persistence,
      kekProvider: async () => kek,
    });
  });

  test('round-trip: put → get returns the same grant', async () => {
    const grant = makeGrant();
    await store.put(grant);
    const got = await store.get('gmail', 'g-1');
    expect(got).not.toBeNull();
    expect(got!.grantId).toBe('g-1');
    expect(got!.token.accessToken).toBe('at-secret');
    expect(got!.token.refreshToken).toBe('rt-secret');
  });

  test('raw on-disk bytes are encrypted (no plaintext access token)', async () => {
    await store.put(makeGrant());
    const blob = [...persistence.raw().values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    expect(text).not.toContain('at-secret');
    expect(text).not.toContain('rt-secret');
  });

  test('delete removes the grant and listByProvider no longer sees it', async () => {
    await store.put(makeGrant());
    expect((await store.listByProvider('gmail')).length).toBe(1);
    await store.delete('gmail', 'g-1');
    expect((await store.listByProvider('gmail')).length).toBe(0);
  });

  test('listByProvider returns multiple grants', async () => {
    await store.put(makeGrant({ grantId: 'g-1' }));
    await store.put(makeGrant({ grantId: 'g-2', accountLabel: 'b@example.com' }));
    const all = await store.listByProvider('gmail');
    expect(all.length).toBe(2);
  });

  test('GrantStoreLocked when KEK provider returns null', async () => {
    const locked = new LegacyGrantStore({
      persistence,
      kekProvider: async () => null,
    });
    await expect(locked.put(makeGrant())).rejects.toThrow(GrantStoreLocked);
    await expect(locked.get('gmail', 'g-1')).rejects.toThrow(GrantStoreLocked);
  });

  test('GrantStoreCorrupt when blob is tampered', async () => {
    await store.put(makeGrant());
    const [key, blob] = [...persistence.raw().entries()][0];
    blob[40] ^= 0xff; // flip a ciphertext bit
    persistence.raw().set(key, blob);
    await expect(store.get('gmail', 'g-1')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('GrantStoreCorrupt when format-version field is wrong', async () => {
    await store.put(makeGrant());
    const [key, blob] = [...persistence.raw().entries()][0];
    new DataView(blob.buffer).setUint32(0, 99, true);
    persistence.raw().set(key, blob);
    await expect(store.get('gmail', 'g-1')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('decrypt with a different KEK fails closed', async () => {
    await store.put(makeGrant());
    const otherKek = await makeKek();
    const otherStore = new LegacyGrantStore({
      persistence,
      kekProvider: async () => otherKek,
    });
    await expect(otherStore.get('gmail', 'g-1')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('get returns null when the grant does not exist', async () => {
    expect(await store.get('gmail', 'no-such-grant')).toBeNull();
  });
});

```
