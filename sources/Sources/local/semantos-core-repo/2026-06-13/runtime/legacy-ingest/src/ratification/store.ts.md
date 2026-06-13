---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ratification/store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.163655+00:00
---

# runtime/legacy-ingest/src/ratification/store.ts

```ts
/**
 * Receipt + correction-edge store — LI4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI4.
 *
 * Both stores share the encrypted-at-rest envelope used by grant /
 * blob / proposal stores so the same wallet KEK protects every
 * legacy-ingest artefact at rest.
 */

import {
  GrantStoreCorrupt,
  GrantStoreLocked,
  type GrantPersistence,
  type KekProvider,
} from '../grant-store';
import type { CorrectionEdge, RatificationReceipt } from './types';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 36;

interface BaseOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  prefix: string;
  cryptoImpl?: Crypto;
}

abstract class EncryptedJsonStore<T extends { readonly providerId: string }> {
  protected readonly persistence: GrantPersistence;
  protected readonly kekProvider: KekProvider;
  protected readonly prefix: string;
  protected readonly cryptoImpl: Crypto;

  constructor(opts: BaseOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix;
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  protected async putRaw(providerId: string, id: string, value: T): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.encrypt(kek, JSON.stringify(value));
    await this.persistence.write(this.keyFor(providerId, id), blob);
  }

  protected async getRaw(providerId: string, id: string): Promise<T | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId, id));
    if (!blob) return null;
    return JSON.parse(await this.decrypt(kek, blob));
  }

  protected async listRaw(providerId?: string): Promise<T[]> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const prefixes = providerId
      ? [`${this.prefix}/${providerId}/`]
      : await this.providerPrefixes();
    const out: T[] = [];
    for (const prefix of prefixes) {
      const keys = await this.persistence.list(prefix);
      for (const key of keys) {
        const blob = await this.persistence.read(key);
        if (!blob) continue;
        try { out.push(JSON.parse(await this.decrypt(kek, blob))); }
        catch { /* skip corrupt — surfaced via status later */ }
      }
    }
    return out;
  }

  protected async deleteRaw(providerId: string, id: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, id));
  }

  private async providerPrefixes(): Promise<string[]> {
    const keys = await this.persistence.list(`${this.prefix}/`);
    const providers = new Set<string>();
    for (const k of keys) {
      const tail = k.slice(`${this.prefix}/`.length);
      const slash = tail.indexOf('/');
      if (slash > 0) providers.add(tail.slice(0, slash));
    }
    return [...providers].map(p => `${this.prefix}/${p}/`);
  }

  private keyFor(providerId: string, id: string): string {
    return `${this.prefix}/${providerId}/${id}.enc`;
  }

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

export interface ReceiptStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  prefix?: string;
  cryptoImpl?: Crypto;
}

export class ReceiptStore extends EncryptedJsonStore<RatificationReceipt> {
  constructor(opts: ReceiptStoreOpts) {
    super({ ...opts, prefix: opts.prefix ?? 'legacy-receipts' });
  }
  put(r: RatificationReceipt): Promise<void> { return this.putRaw(r.providerId, r.receiptId, r); }
  get(providerId: string, id: string): Promise<RatificationReceipt | null> { return this.getRaw(providerId, id); }
  list(providerId?: string): Promise<RatificationReceipt[]> { return this.listRaw(providerId); }
}

export interface CorrectionEdgeStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  prefix?: string;
  cryptoImpl?: Crypto;
}

export class CorrectionEdgeStore extends EncryptedJsonStore<CorrectionEdge> {
  constructor(opts: CorrectionEdgeStoreOpts) {
    super({ ...opts, prefix: opts.prefix ?? 'legacy-corrections' });
  }
  put(c: CorrectionEdge): Promise<void> { return this.putRaw(c.providerId, c.correctionId, c); }
  get(providerId: string, id: string): Promise<CorrectionEdge | null> { return this.getRaw(providerId, id); }
  list(providerId?: string): Promise<CorrectionEdge[]> { return this.listRaw(providerId); }
  delete(providerId: string, id: string): Promise<void> { return this.deleteRaw(providerId, id); }

  async pin(providerId: string, id: string): Promise<boolean> {
    const c = await this.get(providerId, id);
    if (!c) return false;
    if (c.pinned) return true;
    await this.put({ ...c, pinned: true });
    return true;
  }

  async unpin(providerId: string, id: string): Promise<boolean> {
    const c = await this.get(providerId, id);
    if (!c) return false;
    if (!c.pinned) return true;
    await this.put({ ...c, pinned: false });
    return true;
  }
}

```
