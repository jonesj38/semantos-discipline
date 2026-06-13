---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/grant-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.131582+00:00
---

# runtime/legacy-ingest/src/grant-store.ts

```ts
/**
 * Encrypted-at-rest legacy-grant token store — LI1.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 deliverable 2.
 *
 * Each grant is one operator's OAuth credentials for one provider.
 * Stored at `~/.semantos/legacy-grants/<provider>/<grant-id>.enc`,
 * encrypted under a KEK derived from the operator's wallet (the
 * factor injected by the host — the legacy-ingest crate does not
 * derive KEKs itself).
 *
 * Envelope format (matches the wallet-browser tier-store envelope at
 * cartridges/wallet-headers/brain/src/host.ts ~line 156):
 *
 *   bytes  0..4    u32 LE   format version (= 1)
 *   bytes  4..8    u32 LE   reserved (was tier — 0 for legacy-grants)
 *   bytes  8..20   12 bytes nonce (random per write)
 *   bytes 20..36   16 bytes AES-GCM tag
 *   bytes 36..     ciphertext (UTF-8 JSON-encoded LegacyGrant)
 *
 * Tag is split out from ciphertext so the on-disk byte order is
 * version || reserved || nonce || tag || ciphertext, which matches
 * the existing wallet envelope reader.
 */

import type { LegacyGrant } from './types';
import { audit } from './audit';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 4 + 4 + NONCE_BYTES + TAG_BYTES; // 36

/**
 * Adapter for the persistence layer. Browser uses OPFS; node/bun
 * uses fs. Host is responsible for choosing the implementation; the
 * grant store is renderer-agnostic.
 */
export interface GrantPersistence {
  read(key: string): Promise<Uint8Array | null>;
  write(key: string, data: Uint8Array): Promise<void>;
  delete(key: string): Promise<void>;
  list(prefix: string): Promise<string[]>;
}

/**
 * KEK provider — host injects an AES-GCM CryptoKey. The legacy-ingest
 * crate never sees the wallet factor; it only sees the derived key.
 *
 * Returning null means the wallet isn't unlocked yet — read/write
 * should fail closed with a typed error.
 */
export type KekProvider = () => Promise<CryptoKey | null>;

export class GrantStoreLocked extends Error {
  constructor() {
    super('legacy-ingest grant store: wallet KEK unavailable (wallet locked?)');
    this.name = 'GrantStoreLocked';
  }
}

export class GrantStoreCorrupt extends Error {
  constructor(message: string) {
    super(`legacy-ingest grant store: ${message}`);
    this.name = 'GrantStoreCorrupt';
  }
}

export interface LegacyGrantStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  /** Path prefix — defaults to "legacy-grants". */
  prefix?: string;
  /** Crypto namespace — defaults to globalThis.crypto. Tests inject a fake. */
  cryptoImpl?: Crypto;
}

export class LegacyGrantStore {
  private readonly persistence: GrantPersistence;
  private readonly kekProvider: KekProvider;
  private readonly prefix: string;
  private readonly cryptoImpl: Crypto;

  constructor(opts: LegacyGrantStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix ?? 'legacy-grants';
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  /** Persist (or replace) a grant. */
  async put(grant: LegacyGrant): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const json = JSON.stringify(grant);
    const plaintext = new TextEncoder().encode(json);
    const blob = await this.encrypt(kek, plaintext);
    await this.persistence.write(this.keyFor(grant.providerId, grant.grantId), blob);
    await audit('grant.put', 'ok', {
      providerId: grant.providerId,
      grantId: grant.grantId,
      hatId: grant.hatId,
    });
  }

  /** Fetch one grant. Returns null when no grant exists for that id. */
  async get(providerId: string, grantId: string): Promise<LegacyGrant | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId, grantId));
    if (!blob) return null;
    const plaintext = await this.decrypt(kek, blob);
    const grant = JSON.parse(new TextDecoder().decode(plaintext)) as LegacyGrant;
    return grant;
  }

  /** List grants for a provider. */
  async listByProvider(providerId: string): Promise<LegacyGrant[]> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const keys = await this.persistence.list(`${this.prefix}/${providerId}/`);
    const out: LegacyGrant[] = [];
    for (const key of keys) {
      const blob = await this.persistence.read(key);
      if (!blob) continue;
      try {
        const plaintext = await this.decrypt(kek, blob);
        out.push(JSON.parse(new TextDecoder().decode(plaintext)));
      } catch {
        // Skip corrupt entries — surface to operator via `legacy status` later.
      }
    }
    return out;
  }

  /** Delete a grant — irreversible. */
  async delete(providerId: string, grantId: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, grantId));
    await audit('grant.delete', 'ok', { providerId, grantId });
  }

  /** Path key for a (provider, grant) tuple. */
  private keyFor(providerId: string, grantId: string): string {
    return `${this.prefix}/${providerId}/${grantId}.enc`;
  }

  // ── envelope ──

  private async encrypt(kek: CryptoKey, plaintext: Uint8Array): Promise<Uint8Array> {
    const nonce = new Uint8Array(NONCE_BYTES);
    this.cryptoImpl.getRandomValues(nonce);
    const aad = this.buildAad(nonce);
    const ctWithTag = new Uint8Array(
      await this.cryptoImpl.subtle.encrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek,
        plaintext,
      ),
    );
    // Split tag (last 16 bytes) from ciphertext.
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

  private async decrypt(kek: CryptoKey, blob: Uint8Array): Promise<Uint8Array> {
    if (blob.length < HEADER_BYTES) {
      throw new GrantStoreCorrupt('blob shorter than header');
    }
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
      return new Uint8Array(
        await this.cryptoImpl.subtle.decrypt(
          { name: 'AES-GCM', iv: nonce, additionalData: aad },
          kek,
          ctWithTag,
        ),
      );
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

```
