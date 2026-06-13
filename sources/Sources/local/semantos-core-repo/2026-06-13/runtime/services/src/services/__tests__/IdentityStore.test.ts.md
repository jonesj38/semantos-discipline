---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/IdentityStore.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.109164+00:00
---

# runtime/services/src/services/__tests__/IdentityStore.test.ts

```ts
/**
 * IdentityStore — D-A3 cert-readiness tests.
 *
 * Covers the boot-time gate Helm uses to delay authenticated backend
 * calls until Plexus identity has issued (or restored from storage)
 * the active hat's cert: `getCert()`, `getCertId()`, `whenCertReady()`,
 * and the `cert-ready` event.
 *
 * Tests bypass PlexusService entirely by feeding a fake StorageAdapter
 * pre-loaded with a serialized Identity payload. This keeps the unit
 * scope narrow — we are not testing the cert issuance flow itself
 * (that's covered by Plexus tests), only that the IdentityStore
 * surfaces the cert state correctly to its consumers.
 */

import { describe, expect, test } from 'bun:test';
import { IdentityStore } from '../IdentityStore';
import type { StorageAdapter, StorageStat } from '../../../../../core/protocol-types/src/storage';

// ── Fake StorageAdapter ────────────────────────────────────────

class FakeStorage implements StorageAdapter {
  private store = new Map<string, Uint8Array>();

  constructor(seed?: Record<string, string>) {
    if (seed) {
      const enc = new TextEncoder();
      for (const [k, v] of Object.entries(seed)) {
        this.store.set(k, enc.encode(v));
      }
    }
  }

  async read(key: string): Promise<Uint8Array | null> {
    return this.store.get(key) ?? null;
  }
  async write(key: string, data: Uint8Array): Promise<void> {
    this.store.set(key, data);
  }
  async exists(key: string): Promise<boolean> {
    return this.store.has(key);
  }
  async list(prefix: string): Promise<string[]> {
    return Array.from(this.store.keys()).filter(k => k.startsWith(prefix));
  }
  async delete(key: string): Promise<boolean> {
    return this.store.delete(key);
  }
  async stat(_key: string): Promise<StorageStat | null> {
    return null;
  }
}

// ── Identity-payload fixtures ──────────────────────────────────

interface SerializedIdentityFixture {
  withCert: boolean;
}

function fixturePayload(opts: SerializedIdentityFixture): string {
  const hat = {
    id: 'hat-developer',
    name: 'Developer',
    displayName: 'Test (Developer)',
    capabilities: [1, 2, 3],
    derivationPath: 'm/brc52/developer/0',
    certId: opts.withCert ? 'cert-active-hat-abc123' : undefined,
    publicKey: opts.withCert ? 'PEM-PUBKEY' : undefined,
  };
  const identity = {
    id: 'identity-1',
    name: 'Test User',
    certId: opts.withCert ? 'cert-root-xyz' : undefined,
    publicKey: opts.withCert ? 'PEM-ROOT-PUBKEY' : undefined,
    hats: [hat],
    activeHatId: hat.id,
    policies: [],
  };
  return JSON.stringify(identity);
}

const ADAPTER_KEY = 'identity/state.json';

// ── Tests ──────────────────────────────────────────────────────

describe('IdentityStore — D-A3 cert exposure', () => {
  test('getCert() returns null when no identity loaded', () => {
    const store = new IdentityStore();
    expect(store.getCert()).toBeNull();
    expect(store.getCertId()).toBeNull();
  });

  test('getCert() returns null when active hat has no cert', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: false }),
    });
    const store = new IdentityStore(adapter);
    await store.initFromAdapter();
    expect(store.getActiveHat()?.id).toBe('hat-developer');
    expect(store.getCert()).toBeNull();
    expect(store.getCertId()).toBeNull();
  });

  test('getCert() returns the active hat cert snapshot', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: true }),
    });
    const store = new IdentityStore(adapter);
    await store.initFromAdapter();
    const cert = store.getCert();
    expect(cert).toEqual({
      hatId: 'hat-developer',
      certId: 'cert-active-hat-abc123',
      publicKey: 'PEM-PUBKEY',
    });
    expect(store.getCertId()).toBe('cert-active-hat-abc123');
  });
});

describe('IdentityStore — D-A3 boot-readiness gate', () => {
  test('whenCertReady() resolves immediately when cert already present', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: true }),
    });
    const store = new IdentityStore(adapter);
    await store.initFromAdapter();
    const cert = await store.whenCertReady();
    expect(cert.certId).toBe('cert-active-hat-abc123');
  });

  test('whenCertReady() pends until cert arrives via initFromAdapter', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: true }),
    });
    // Construct the store BEFORE the adapter has been read so the
    // initial state has no identity / no cert.
    const store = new IdentityStore(adapter);
    expect(store.getCert()).toBeNull();

    // Race a sentinel against the gate to confirm it's pending.
    const sentinel = Symbol('pending');
    const pending = store.whenCertReady();
    const racedFirst = await Promise.race([
      pending,
      Promise.resolve(sentinel),
    ]);
    expect(racedFirst).toBe(sentinel);

    // Now resolve by triggering the adapter load.
    await store.initFromAdapter();
    const cert = await pending;
    expect(cert.certId).toBe('cert-active-hat-abc123');
  });

  test('cert-ready event fires once when cert transitions present', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: true }),
    });
    const store = new IdentityStore(adapter);
    let fires = 0;
    let lastSnapshot: { certId: string } | null = null;
    store.on('cert-ready', snap => {
      fires += 1;
      lastSnapshot = snap;
    });
    await store.initFromAdapter();
    expect(fires).toBe(1);
    expect(lastSnapshot?.certId).toBe('cert-active-hat-abc123');
  });

  test('cert-ready does not double-fire for the same cert', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: true }),
    });
    const store = new IdentityStore(adapter);
    let fires = 0;
    store.on('cert-ready', () => {
      fires += 1;
    });
    await store.initFromAdapter();
    // Re-load the same payload — must NOT fire again.
    await store.initFromAdapter();
    expect(fires).toBe(1);
  });

  test('whenCertReady() never resolves when adapter has no cert', async () => {
    const adapter = new FakeStorage({
      [ADAPTER_KEY]: fixturePayload({ withCert: false }),
    });
    const store = new IdentityStore(adapter);
    await store.initFromAdapter();
    const sentinel = Symbol('pending');
    const raced = await Promise.race([
      store.whenCertReady(),
      Promise.resolve(sentinel),
    ]);
    expect(raced).toBe(sentinel);
  });
});

```
