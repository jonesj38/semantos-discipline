---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/blob-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.146970+00:00
---

# runtime/legacy-ingest/src/__tests__/blob-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { LegacyBlobStore } from '../blob-store';
import { GrantStoreCorrupt, GrantStoreLocked, type GrantPersistence } from '../grant-store';
import type { RawItem } from '../types';

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

function makeItem(over: Partial<RawItem> = {}): RawItem {
  return {
    providerId: 'gmail',
    providerItemId: 'msg-1',
    fetchedAt: 1000,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode('Subject: Hello\r\n\r\nbody'),
    metadata: { threadId: 't-1' },
    ...over,
  };
}

describe('LegacyBlobStore', () => {
  let persistence: MemoryPersistence;
  let store: LegacyBlobStore;

  beforeEach(async () => {
    persistence = new MemoryPersistence();
    const kek = await makeKek();
    store = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
  });

  test('round-trip preserves bytes + metadata', async () => {
    const item = makeItem();
    await store.put(item);
    const got = await store.get('gmail', 'msg-1');
    expect(got).not.toBeNull();
    expect(got!.contentType).toBe('email/rfc822');
    expect(new TextDecoder().decode(got!.bytes)).toBe('Subject: Hello\r\n\r\nbody');
    expect(got!.metadata.threadId).toBe('t-1');
  });

  test('on-disk bytes are encrypted (no plaintext leaks)', async () => {
    await store.put(makeItem());
    const blob = [...persistence.store.values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    expect(text).not.toContain('Subject: Hello');
    expect(text).not.toContain('body');
  });

  test('has() returns false for missing items, true for stored', async () => {
    expect(await store.has('gmail', 'no-such')).toBe(false);
    await store.put(makeItem());
    expect(await store.has('gmail', 'msg-1')).toBe(true);
  });

  test('listIds and count return the persisted ids', async () => {
    await store.put(makeItem({ providerItemId: 'a' }));
    await store.put(makeItem({ providerItemId: 'b' }));
    expect(await store.count('gmail')).toBe(2);
    const ids = await store.listIds('gmail');
    expect(ids.sort()).toEqual(['a', 'b']);
  });

  test('GrantStoreLocked when KEK provider returns null', async () => {
    const locked = new LegacyBlobStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => null,
    });
    await expect(locked.put(makeItem())).rejects.toThrow(GrantStoreLocked);
  });

  test('tampered ciphertext fails closed', async () => {
    await store.put(makeItem());
    const [key, blob] = [...persistence.store.entries()][0];
    blob[40] ^= 0xff;
    persistence.store.set(key, blob);
    await expect(store.get('gmail', 'msg-1')).rejects.toThrow(GrantStoreCorrupt);
  });

  test('putMany counts written + alreadyPresent', async () => {
    const a = makeItem({ providerItemId: 'a' });
    const b = makeItem({ providerItemId: 'b' });
    let res = await store.putMany([a, b]);
    expect(res.written).toBe(2);
    expect(res.alreadyPresent).toBe(0);
    res = await store.putMany([a, b]);
    expect(res.written).toBe(2);
    expect(res.alreadyPresent).toBe(2);
  });

  test('large items (>64 KB) round-trip without RangeError', async () => {
    // Regression: pre-fix `btoa(String.fromCharCode(...item.bytes))`
    // blew the call stack on items above the engine's variadic-spread
    // limit (~65,536 chars). A typical Gmail message with attachments
    // easily exceeds this. Use 256 KB of pseudo-random bytes
    // (deterministic so the test is reproducible).
    const size = 256 * 1024;
    const bytes = new Uint8Array(size);
    let seed = 1;
    for (let i = 0; i < size; i++) {
      seed = (seed * 1103515245 + 12345) >>> 0;
      bytes[i] = seed & 0xff;
    }
    const big = makeItem({ providerItemId: 'big', bytes });
    await store.put(big);
    const read = await store.get('gmail', 'big');
    expect(read).not.toBeNull();
    expect(read!.bytes.length).toBe(size);
    // Spot-check a few bytes to confirm exact byte-identity.
    expect(read!.bytes[0]).toBe(bytes[0]);
    expect(read!.bytes[size - 1]).toBe(bytes[size - 1]);
    expect(read!.bytes[size >> 1]).toBe(bytes[size >> 1]);
  });
});

```
