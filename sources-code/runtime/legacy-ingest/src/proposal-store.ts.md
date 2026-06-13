---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/proposal-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.131302+00:00
---

# runtime/legacy-ingest/src/proposal-store.ts

```ts
/**
 * Proposal store — encrypted-at-rest queue of pending / completed
 * extractor proposals.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI3 + LI4.
 *
 * Stored at `legacy-proposals/<provider-id>/<proposal-id>.enc`.
 * Encryption mirrors the grant + blob stores so all three share the
 * envelope format.
 *
 * The proposal record's `status` mutates as the operator interacts
 * (LI4): pending → ratified | rejected | corrected | superseded.
 */

import type { Proposal, ProposalStatus } from './extractor/types';
import {
  GrantStoreCorrupt,
  GrantStoreLocked,
  type GrantPersistence,
  type KekProvider,
} from './grant-store';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 36;

export interface ProposalStoreOpts {
  persistence: GrantPersistence;
  kekProvider: KekProvider;
  prefix?: string;
  cryptoImpl?: Crypto;
}

export interface ProposalQuery {
  providerId?: string;
  status?: ProposalStatus | ProposalStatus[];
  /** Lower-bound confidence filter. */
  minConfidence?: number;
  /** Upper-bound confidence filter. */
  maxConfidence?: number;
  limit?: number;
}

export class ProposalStore {
  private readonly persistence: GrantPersistence;
  private readonly kekProvider: KekProvider;
  private readonly prefix: string;
  private readonly cryptoImpl: Crypto;

  constructor(opts: ProposalStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix ?? 'legacy-proposals';
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  async put(proposal: Proposal): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.encrypt(kek, JSON.stringify(proposal));
    await this.persistence.write(this.keyFor(proposal.provenance.providerId, proposal.proposalId), blob);
  }

  async get(providerId: string, proposalId: string): Promise<Proposal | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId, proposalId));
    if (!blob) return null;
    const text = await this.decrypt(kek, blob);
    return JSON.parse(text);
  }

  async update(proposal: Proposal): Promise<void> {
    return this.put(proposal);
  }

  async delete(providerId: string, proposalId: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, proposalId));
  }

  async list(query: ProposalQuery = {}): Promise<Proposal[]> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const prefixes = query.providerId
      ? [`${this.prefix}/${query.providerId}/`]
      : await this.providerPrefixes();
    const out: Proposal[] = [];
    for (const prefix of prefixes) {
      const keys = await this.persistence.list(prefix);
      for (const key of keys) {
        const blob = await this.persistence.read(key);
        if (!blob) continue;
        try {
          const text = await this.decrypt(kek, blob);
          const proposal = JSON.parse(text) as Proposal;
          if (!matchesQuery(proposal, query)) continue;
          out.push(proposal);
          if (query.limit && out.length >= query.limit) return out;
        } catch {
          // Skip corrupt entries — surfaced via `legacy status` later.
        }
      }
    }
    return out;
  }

  /** Bulk update status — returns count modified. */
  async updateStatus(
    proposals: Proposal[],
    nextStatus: ProposalStatus,
  ): Promise<number> {
    let n = 0;
    for (const p of proposals) {
      const updated: Proposal = { ...p, status: nextStatus };
      await this.update(updated);
      n += 1;
    }
    return n;
  }

  private async providerPrefixes(): Promise<string[]> {
    // Cheap enumeration: list under our root prefix and pluck the
    // provider segment. The persistence adapter returns full paths.
    const keys = await this.persistence.list(`${this.prefix}/`);
    const providers = new Set<string>();
    for (const k of keys) {
      const tail = k.slice(`${this.prefix}/`.length);
      const slash = tail.indexOf('/');
      if (slash > 0) providers.add(tail.slice(0, slash));
    }
    return [...providers].map(p => `${this.prefix}/${p}/`);
  }

  private keyFor(providerId: string, proposalId: string): string {
    return `${this.prefix}/${providerId}/${proposalId}.enc`;
  }

  // ── envelope (mirrors grant + blob stores) ──

  private async encrypt(kek: CryptoKey, text: string): Promise<Uint8Array> {
    const plaintext = new TextEncoder().encode(text);
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
        kek,
        ctWithTag,
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

function matchesQuery(p: Proposal, q: ProposalQuery): boolean {
  if (q.status) {
    const allowed = Array.isArray(q.status) ? q.status : [q.status];
    if (!allowed.includes(p.status)) return false;
  }
  if (typeof q.minConfidence === 'number' && p.confidence < q.minConfidence) return false;
  if (typeof q.maxConfidence === 'number' && p.confidence > q.maxConfidence) return false;
  return true;
}

```
