---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/pending-state-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.148678+00:00
---

# runtime/legacy-ingest/src/__tests__/pending-state-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import {
  PendingStateStore,
  PendingStoreLocked,
  type PendingPersistence,
} from '../pending-state-store';
import type { OAuthPendingState } from '../types';

/**
 * In-memory persistence — mirrors `MemoryPersistence` in
 * grant-store.test.ts but adds mtime tracking, since the pending
 * store enforces TTL on read via `mtimeMs()`.
 *
 * The mtime is set explicitly per-write so tests can drive expiry by
 * either advancing the store's `now` clock or rewriting an entry with
 * a stale mtime.
 */
class MemoryPendingPersistence implements PendingPersistence {
  private store = new Map<string, Uint8Array>();
  private mtimes = new Map<string, number>();
  /** Used by `write` so each entry's mtime tracks the current fake clock. */
  public clock: () => number = () => Date.now();

  async read(k: string) {
    return this.store.get(k) ?? null;
  }
  async write(k: string, v: Uint8Array) {
    this.store.set(k, v);
    this.mtimes.set(k, this.clock());
  }
  async delete(k: string) {
    this.store.delete(k);
    this.mtimes.delete(k);
  }
  async list() {
    return [...this.store.keys()];
  }
  async mtimeMs(k: string) {
    return this.mtimes.has(k) ? (this.mtimes.get(k) as number) : null;
  }
  raw(): Map<string, Uint8Array> {
    return this.store;
  }
  /** Test seam — backdate an entry's mtime to simulate file-on-disk age. */
  setMtime(k: string, ms: number): void {
    this.mtimes.set(k, ms);
  }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey(
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

function makeState(over: Partial<OAuthPendingState> = {}): OAuthPendingState {
  return {
    nonce: 'state-nonce-abc',
    providerId: 'gmail',
    hatId: 'hat-1',
    createdAt: 1_700_000_000_000,
    pkceVerifier: 'verifier-secret-xyz',
    redirectUri: 'http://localhost:3001/auth/callback',
    ...over,
  };
}

describe('PendingStateStore', () => {
  let persistence: MemoryPendingPersistence;
  let kek: CryptoKey;
  let store: PendingStateStore;

  beforeEach(async () => {
    persistence = new MemoryPendingPersistence();
    kek = await makeKek();
    store = new PendingStateStore({
      persistence,
      kekProvider: async () => kek,
    });
  });

  test('round-trip: put → get returns the same state', async () => {
    const state = makeState();
    await store.put(state);
    const got = await store.get('state-nonce-abc');
    expect(got).not.toBeNull();
    expect(got!.nonce).toBe('state-nonce-abc');
    expect(got!.providerId).toBe('gmail');
    expect(got!.pkceVerifier).toBe('verifier-secret-xyz');
    expect(got!.redirectUri).toBe('http://localhost:3001/auth/callback');
    expect(got!.createdAt).toBe(1_700_000_000_000);
    expect(got!.hatId).toBe('hat-1');
  });

  test('round-trip preserves null pkceVerifier (non-PKCE provider)', async () => {
    await store.put(makeState({ pkceVerifier: null, hatId: null }));
    const got = await store.get('state-nonce-abc');
    expect(got!.pkceVerifier).toBeNull();
    expect(got!.hatId).toBeNull();
  });

  test('on-disk bytes do not contain the verifier or nonce in the clear', async () => {
    await store.put(makeState());
    const blob = [...persistence.raw().values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    // Sensitive fields encoded into the JSON must not be on-disk visible.
    expect(text).not.toContain('verifier-secret-xyz');
    expect(text).not.toContain('state-nonce-abc');
    expect(text).not.toContain('localhost:3001');
  });

  test('decrypt with a different KEK returns null (does not throw)', async () => {
    await store.put(makeState());
    const otherKek = await makeKek();
    const otherStore = new PendingStateStore({
      persistence,
      kekProvider: async () => otherKek,
    });
    const got = await otherStore.get('state-nonce-abc');
    expect(got).toBeNull();
  });

  test('TTL expiry: get returns null and deletes the file when mtime > TTL', async () => {
    let now = 1_700_000_000_000;
    persistence.clock = () => now;
    const ttlStore = new PendingStateStore({
      persistence,
      kekProvider: async () => kek,
      pendingTtlMs: 1000,
      now: () => now,
    });
    await ttlStore.put(makeState());
    expect(await ttlStore.get('state-nonce-abc')).not.toBeNull();

    // Advance the clock past the TTL.
    now += 1001;
    const got = await ttlStore.get('state-nonce-abc');
    expect(got).toBeNull();
    // File deleted on TTL miss.
    expect(persistence.raw().has('state-nonce-abc.json')).toBe(false);
  });

  test('delete removes the file', async () => {
    await store.put(makeState());
    expect(persistence.raw().size).toBe(1);
    await store.delete('state-nonce-abc');
    expect(persistence.raw().size).toBe(0);
    expect(await store.get('state-nonce-abc')).toBeNull();
  });

  test('sweepExpired deletes only expired files and returns the count', async () => {
    let now = 1_700_000_000_000;
    persistence.clock = () => now;
    const ttlStore = new PendingStateStore({
      persistence,
      kekProvider: async () => kek,
      pendingTtlMs: 1000,
      now: () => now,
    });
    await ttlStore.put(makeState({ nonce: 'fresh-1' }));
    await ttlStore.put(makeState({ nonce: 'fresh-2' }));
    // Backdate two entries to be older than the TTL.
    persistence.setMtime('fresh-1.json', now - 5000);
    persistence.setMtime('fresh-2.json', now - 5000);
    // Add a not-yet-expired entry.
    await ttlStore.put(makeState({ nonce: 'still-good' }));

    const deleted = await ttlStore.sweepExpired();
    expect(deleted).toBe(2);
    expect(persistence.raw().has('fresh-1.json')).toBe(false);
    expect(persistence.raw().has('fresh-2.json')).toBe(false);
    expect(persistence.raw().has('still-good.json')).toBe(true);
  });

  test('get for unknown nonce returns null (no error)', async () => {
    expect(await store.get('does-not-exist')).toBeNull();
  });

  test('PendingStoreLocked when KEK provider returns null', async () => {
    const locked = new PendingStateStore({
      persistence,
      kekProvider: async () => null,
    });
    await expect(locked.put(makeState())).rejects.toThrow(PendingStoreLocked);
    await expect(locked.get('state-nonce-abc')).rejects.toThrow(PendingStoreLocked);
  });

  test('two stores on the same persistence + KEK can hand off state (cross-process)', async () => {
    // Simulates the legacy-cli scenario: process A puts state, exits;
    // process B comes along (fresh PendingStateStore instance, same
    // root + KEK) and reads the state.
    const a = new PendingStateStore({
      persistence,
      kekProvider: async () => kek,
    });
    await a.put(makeState({ nonce: 'cross-process' }));

    const b = new PendingStateStore({
      persistence,
      kekProvider: async () => kek,
    });
    const got = await b.get('cross-process');
    expect(got).not.toBeNull();
    expect(got!.pkceVerifier).toBe('verifier-secret-xyz');
  });
});

```
