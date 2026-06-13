---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/blob-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.129858+00:00
---

# runtime/legacy-ingest/src/blob-store.ts

```ts
/**
 * Encrypted raw-item blob store — LI2.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI2 deliverable 2.
 *
 * Each fetched RawItem is persisted verbatim under
 * `legacy-ingest/<provider-id>/<provider-item-id>` encrypted under the
 * operator's wallet-derived KEK. We keep raw bytes indefinitely so the
 * extractor (LI3) can re-run with an improved prompt months later
 * without re-fetching from the provider.
 *
 * Envelope reuses the grant-store format: version || reserved || nonce
 * || tag || ciphertext. Plaintext is the JSON-encoded RawItem with
 * the bytes field base64'd (raw Uint8Array doesn't survive JSON).
 */

import type { RawItem } from './types';
import {
  GrantStoreCorrupt,
  GrantStoreLocked,
  type GrantPersistence,
  type KekProvider,
} from './grant-store';
import { audit } from './audit';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 36;

interface SerialisedRawItem {
  providerId: string;
  providerItemId: string;
  fetchedAt: number;
  contentType: string;
  /** base64 string. */
  bytes: string;
  metadata: Record<string, string>;
}

export interface BlobStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  /** Path prefix — defaults to "legacy-ingest". */
  prefix?: string;
  cryptoImpl?: Crypto;
}

export class LegacyBlobStore {
  private readonly persistence: GrantPersistence;
  private readonly kekProvider: KekProvider;
  private readonly prefix: string;
  private readonly cryptoImpl: Crypto;

  constructor(opts: BlobStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix ?? 'legacy-ingest';
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  async put(item: RawItem): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const ser: SerialisedRawItem = {
      providerId: item.providerId,
      providerItemId: item.providerItemId,
      fetchedAt: item.fetchedAt,
      contentType: item.contentType,
      // Buffer.from(...).toString('base64') for the bytes payload.
      // The earlier `btoa(String.fromCharCode(...item.bytes))` blew the
      // call stack on any Gmail message larger than ~64 KB (the
      // engine's variadic-spread arg-count limit) — i.e. essentially
      // every email with attachments. Buffer is chunked internally and
      // has no such limit. Symmetric change in `deserialise` below.
      bytes: Buffer.from(item.bytes).toString('base64'),
      metadata: { ...item.metadata },
    };
    const plaintext = new TextEncoder().encode(JSON.stringify(ser));
    const blob = await this.encrypt(kek, plaintext);
    await this.persistence.write(this.keyFor(item.providerId, item.providerItemId), blob);
  }

  async get(providerId: string, providerItemId: string): Promise<RawItem | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId, providerItemId));
    if (!blob) return null;
    const plaintext = await this.decrypt(kek, blob);
    const ser = JSON.parse(new TextDecoder().decode(plaintext)) as SerialisedRawItem;
    return deserialise(ser);
  }

  async has(providerId: string, providerItemId: string): Promise<boolean> {
    const blob = await this.persistence.read(this.keyFor(providerId, providerItemId));
    return blob !== null;
  }

  async listIds(providerId: string): Promise<string[]> {
    const keys = await this.persistence.list(`${this.prefix}/${providerId}/`);
    return keys.map(k => k.slice(`${this.prefix}/${providerId}/`.length).replace(/\.enc$/, ''));
  }

  async count(providerId: string): Promise<number> {
    const ids = await this.listIds(providerId);
    return ids.length;
  }

  async delete(providerId: string, providerItemId: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, providerItemId));
    await audit('blob.delete', 'ok', { providerId, detail: providerItemId });
  }

  /**
   * Bulk put — used by the ingest worker to persist a page of items.
   * Returns count of new items (pre-existing items are overwritten).
   */
  async putMany(items: RawItem[]): Promise<{ written: number; alreadyPresent: number }> {
    let written = 0;
    let alreadyPresent = 0;
    for (const item of items) {
      const exists = await this.has(item.providerId, item.providerItemId);
      if (exists) alreadyPresent += 1;
      await this.put(item);
      written += 1;
    }
    return { written, alreadyPresent };
  }

  private keyFor(providerId: string, providerItemId: string): string {
    return `${this.prefix}/${providerId}/${providerItemId}.enc`;
  }

  // ── envelope (mirrors grant-store) ──

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

function deserialise(ser: SerialisedRawItem): RawItem {
  // Buffer.from(b64, 'base64') symmetrically replaces the
  // atob+charCodeAt path. atob+map technically tolerates large input,
  // but using Buffer on both sides keeps the codec consistent and
  // avoids any future variadic-spread footguns.
  const bytes = new Uint8Array(Buffer.from(ser.bytes, 'base64'));
  return {
    providerId: ser.providerId,
    providerItemId: ser.providerItemId,
    fetchedAt: ser.fetchedAt,
    contentType: ser.contentType,
    bytes,
    metadata: ser.metadata,
  };
}

```
