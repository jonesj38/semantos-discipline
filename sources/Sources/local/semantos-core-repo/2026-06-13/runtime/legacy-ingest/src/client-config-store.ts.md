---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/client-config-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.134213+00:00
---

# runtime/legacy-ingest/src/client-config-store.ts

```ts
/**
 * Encrypted-at-rest legacy-provider OAuth client config store.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 deliverable 2 —
 * "client secrets stored encrypted-at-rest by the host".
 *
 * Bridges the operator-supplied OAuth client credentials (client id +
 * client secret + redirect URI) into the OAuthOrchestrator's
 * `configProvider`. The host registers each provider once via
 * `legacy register-client <provider> ...`; the configs persist between
 * runs encrypted under the operator's wallet KEK.
 *
 * Stored at `legacy-clients/<provider-id>.enc`. Same envelope as the
 * grant / blob / proposal / receipt / correction stores so every
 * legacy-ingest artefact at rest is protected by one wallet KEK.
 */

import {
  GrantStoreCorrupt,
  GrantStoreLocked,
  type GrantPersistence,
  type KekProvider,
} from './grant-store';
import { audit } from './audit';
import type { ClientConfig } from './oauth';
import type { ProviderId } from './types';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 36;

/** Persistent shape — strict superset of the in-memory ClientConfig. */
export interface StoredClientConfig extends ClientConfig {
  readonly providerId: ProviderId;
  /** ISO timestamp of registration. */
  readonly registeredAt: string;
  /** Hat id under whose authority the config was stored. */
  readonly registeredBy: string | null;
}

export interface ClientConfigStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  prefix?: string;
  cryptoImpl?: Crypto;
}

export class ClientConfigStore {
  private readonly persistence: GrantPersistence;
  private readonly kekProvider: KekProvider;
  private readonly prefix: string;
  private readonly cryptoImpl: Crypto;

  constructor(opts: ClientConfigStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix ?? 'legacy-clients';
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  async put(config: StoredClientConfig): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.encrypt(kek, JSON.stringify(config));
    await this.persistence.write(this.keyFor(config.providerId), blob);
    await audit('client.register', 'ok', {
      providerId: config.providerId,
      hatId: config.registeredBy,
      // Never log clientId/clientSecret — the broker summarises before
      // calling audit() but for this store we control the call site
      // directly. Detail line carries only provider + redirect URI.
      detail: `redirect=${config.redirectUri}`,
    });
  }

  async get(providerId: ProviderId): Promise<StoredClientConfig | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId));
    if (!blob) return null;
    const text = await this.decrypt(kek, blob);
    return JSON.parse(text) as StoredClientConfig;
  }

  async list(): Promise<StoredClientConfig[]> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const keys = await this.persistence.list(`${this.prefix}/`);
    const out: StoredClientConfig[] = [];
    for (const key of keys) {
      const blob = await this.persistence.read(key);
      if (!blob) continue;
      try { out.push(JSON.parse(await this.decrypt(kek, blob))); }
      catch { /* skip corrupt — surfaced via `legacy clients` later */ }
    }
    return out;
  }

  async delete(providerId: ProviderId): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId));
    await audit('client.unregister', 'ok', { providerId });
  }

  /**
   * Synchronous lookup helper — returns just the live ClientConfig
   * fields the orchestrator's `configProvider` needs. Callers wire
   * this through a sync cache backed by the async `list()`.
   */
  toClientConfig(stored: StoredClientConfig): ClientConfig {
    return {
      clientId: stored.clientId,
      clientSecret: stored.clientSecret,
      redirectUri: stored.redirectUri,
      pkce: stored.pkce,
    };
  }

  private keyFor(providerId: ProviderId): string {
    return `${this.prefix}/${providerId}.enc`;
  }

  // ── envelope (mirrors grant + blob + proposal + receipt stores) ──

  private async encrypt(kek: CryptoKey, text: string): Promise<Uint8Array> {
    const plaintext = new TextEncoder().encode(text);
    const nonce = new Uint8Array(NONCE_BYTES);
    this.cryptoImpl.getRandomValues(nonce);
    const aad = this.buildAad(nonce);
    const ctWithTag = new Uint8Array(
      await this.cryptoImpl.subtle.encrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek, plaintext,
      ),
    );
    const ciphertext = ctWithTag.subarray(0, ctWithTag.length - TAG_BYTES);
    const tag = ctWithTag.subarray(ctWithTag.length - TAG_BYTES);
    const out = new Uint8Array(HEADER_BYTES + ciphertext.length);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, FORMAT_VERSION, true);
    dv.setUint32(4, 0, true);
    out.set(nonce, 8);
    out.set(tag, 20);
    out.set(ciphertext, 36);
    return out;
  }

  private async decrypt(kek: CryptoKey, blob: Uint8Array): Promise<string> {
    if (blob.length < HEADER_BYTES) throw new GrantStoreCorrupt('blob shorter than header');
    const dv = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
    if (dv.getUint32(0, true) !== FORMAT_VERSION) {
      throw new GrantStoreCorrupt('unknown format version');
    }
    const nonce = blob.subarray(8, 20);
    const tag = blob.subarray(20, 36);
    const ciphertext = blob.subarray(36);
    const aad = this.buildAad(nonce);
    const ctWithTag = new Uint8Array(ciphertext.length + tag.length);
    ctWithTag.set(ciphertext, 0);
    ctWithTag.set(tag, ciphertext.length);
    try {
      const plaintext = await this.cryptoImpl.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek, ctWithTag,
      );
      return new TextDecoder().decode(plaintext);
    } catch {
      throw new GrantStoreCorrupt('AES-GCM auth failure (tampered or wrong KEK)');
    }
  }

  private buildAad(nonce: Uint8Array): Uint8Array {
    const aad = new Uint8Array(20);
    const dv = new DataView(aad.buffer);
    dv.setUint32(0, FORMAT_VERSION, true);
    dv.setUint32(4, 0, true);
    aad.set(nonce, 8);
    return aad;
  }
}

/**
 * Sync-cached configProvider that the OAuthOrchestrator can call
 * synchronously. Caller refreshes the cache by calling `reload()`
 * after `register-client` / `unregister-client` mutations.
 *
 * The cache holds plaintext credentials in memory while the wallet
 * is unlocked — same posture as decrypted grants in the orchestrator
 * and proposal payloads in the proposal store.
 */
export class CachedClientConfigProvider {
  private readonly store: ClientConfigStore;
  private cache = new Map<ProviderId, ClientConfig>();

  constructor(store: ClientConfigStore) {
    this.store = store;
  }

  async reload(): Promise<void> {
    const all = await this.store.list();
    this.cache = new Map(
      all.map(c => [c.providerId, this.store.toClientConfig(c)] as const),
    );
  }

  /** Synchronous getter — orchestrator's `configProvider` shape. */
  get = (providerId: ProviderId): ClientConfig | null => {
    return this.cache.get(providerId) ?? null;
  };

  /** Drop a cached entry without re-listing. */
  forget(providerId: ProviderId): void {
    this.cache.delete(providerId);
  }

  size(): number {
    return this.cache.size;
  }
}

```
