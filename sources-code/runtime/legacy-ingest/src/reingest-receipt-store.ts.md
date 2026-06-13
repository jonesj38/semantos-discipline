---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/reingest-receipt-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.128993+00:00
---

# runtime/legacy-ingest/src/reingest-receipt-store.ts

```ts
/**
 * D-RTC.6 follow-up — Reingest receipt store.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.6
 *            "Idempotent: cells with matching source_msg_id are skipped
 *             or upgraded-in-place (operator policy)"
 *
 * Persists one receipt per reingested proposal so re-running `legacy
 * reingest <provider>` skips proposals already minted into cells.
 * Audit-log adjacent: each receipt carries the full graph of
 * cell_ids minted from one proposal (site → customers → job →
 * attachments) so operators (and the chat resolver) can trace from
 * a cell back to its source gmail message.
 *
 * Encryption envelope reuses the same wallet-KEK pattern as
 * `ratification/store.ts`'s ReceiptStore — at-rest secrets stay
 * consistent across every legacy-ingest artefact.
 */

import {
  GrantStoreCorrupt,
  GrantStoreLocked,
  type GrantPersistence,
  type KekProvider,
} from './grant-store';
import type { AttachmentParentSummary } from './attachment-pipeline';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/** One persisted reingest event. */
export interface ReingestReceipt {
  /** Lookup key — the proposal id the receipt was minted for. */
  readonly receiptId: string;
  readonly providerId: string;
  readonly proposalId: string;
  /** Gmail message-id (or other provider item id) the proposal came from. */
  readonly sourceMsgId: string;
  /** Unix ms when this reingest happened. */
  readonly reingestedAt: number;
  /** Site cell id (or null when the proposal had no extractable address). */
  readonly siteCellId: string | null;
  /** 'matched' | 'minted' | 'absent' — how the site resolved. */
  readonly siteDisposition: 'matched' | 'minted' | 'absent';
  /** All customer cell ids minted from this proposal. */
  readonly customerCellIds: readonly string[];
  /**
   * Customer dedupe keys, parallel-indexed with `customerCellIds`
   * (handoff §6.2). The `legacy reingest` verb builds an in-memory
   * customerLookupKey → customerCellId index from these so the same
   * contact (e.g. an agency) collapses onto ONE customer_cell across
   * runs instead of regrowing the canonicalized 152. Optional for
   * back-compat with receipts written before customer-dedupe.
   */
  readonly customerLookupKeys?: readonly string[];
  /** The job cell id this proposal produced. */
  readonly jobCellId: string;
  /**
   * Whether the job_cell was freshly minted by this proposal, or
   * matched to one a prior (duplicate) proposal already minted.
   * Optional for back-compat with receipts written before job-dedupe.
   */
  readonly jobDisposition?: 'matched' | 'minted';
  /**
   * Job dedupe key (wo:… / site:… / unkeyed:…). The `legacy
   * reingest` verb builds an in-memory jobLookupKey → jobCellId
   * index from these so duplicate proposals across runs collapse.
   * Optional for back-compat.
   */
  readonly jobLookupKey?: string;
  /** All attachment cell ids minted. */
  readonly attachmentCellIds: readonly string[];
  /** Aggregated parent summary. */
  readonly parentSummary: AttachmentParentSummary;
  /** Extractor version (`email-rfc822-v0.6` etc.) — for cache-bust on re-extract. */
  readonly extractorVersion: string;
  /**
   * Upgrade-in-place chain: when this receipt replaces an earlier
   * receipt (because the operator ran `legacy reingest
   * --upgrade-existing`), this points at the receipt-id it
   * superseded. Audit trail stays contiguous; readers can walk the
   * chain to see how a job evolved across extractor schema bumps.
   *
   * Null on fresh ingests.
   */
  readonly supersededReceiptId?: string | null;
}

export interface ReingestReceiptStoreOpts {
  readonly persistence: GrantPersistence;
  readonly kekProvider: KekProvider;
  /** Path prefix — defaults to "reingest-receipts". */
  readonly prefix?: string;
  readonly cryptoImpl?: Crypto;
}

/* ──────────────────────────────────────────────────────────────────────
 * Store
 * ────────────────────────────────────────────────────────────────────── */

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 36;

export class ReingestReceiptStore {
  private readonly persistence: GrantPersistence;
  private readonly kekProvider: KekProvider;
  private readonly prefix: string;
  private readonly cryptoImpl: Crypto;

  constructor(opts: ReingestReceiptStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.prefix = opts.prefix ?? 'reingest-receipts';
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
  }

  async put(r: ReingestReceipt): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.encrypt(kek, JSON.stringify(r));
    await this.persistence.write(this.keyFor(r.providerId, r.receiptId), blob);
  }

  async get(providerId: string, receiptId: string): Promise<ReingestReceipt | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const blob = await this.persistence.read(this.keyFor(providerId, receiptId));
    if (!blob) return null;
    return JSON.parse(await this.decrypt(kek, blob));
  }

  /** Check existence without decrypting — the idempotency hot path. */
  async has(providerId: string, receiptId: string): Promise<boolean> {
    const blob = await this.persistence.read(this.keyFor(providerId, receiptId));
    return blob !== null;
  }

  async list(providerId?: string): Promise<ReingestReceipt[]> {
    const kek = await this.kekProvider();
    if (!kek) throw new GrantStoreLocked();
    const prefixes = providerId
      ? [`${this.prefix}/${providerId}/`]
      : await this.providerPrefixes();
    const out: ReingestReceipt[] = [];
    for (const prefix of prefixes) {
      const keys = await this.persistence.list(prefix);
      for (const k of keys) {
        const blob = await this.persistence.read(k);
        if (!blob) continue;
        try {
          out.push(JSON.parse(await this.decrypt(kek, blob)));
        } catch {
          // Skip corrupt — surfaced via status later.
        }
      }
    }
    return out;
  }

  async delete(providerId: string, receiptId: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, receiptId));
  }

  async count(providerId?: string): Promise<number> {
    const prefixes = providerId
      ? [`${this.prefix}/${providerId}/`]
      : await this.providerPrefixes();
    let n = 0;
    for (const p of prefixes) {
      n += (await this.persistence.list(p)).length;
    }
    return n;
  }

  /* ── encryption envelope ─────────────────────────────────────────── */

  private keyFor(providerId: string, receiptId: string): string {
    return `${this.prefix}/${providerId}/${receiptId}.enc`;
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

  private async encrypt(kek: CryptoKey, plaintext: string): Promise<Uint8Array> {
    const nonce = new Uint8Array(NONCE_BYTES);
    this.cryptoImpl.getRandomValues(nonce);
    const aad = this.buildAad(nonce);
    const ptBytes = new TextEncoder().encode(plaintext);
    const ctWithTag = new Uint8Array(
      await this.cryptoImpl.subtle.encrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek,
        ptBytes,
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
      const pt = await this.cryptoImpl.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek,
        ctWithTag,
      );
      return new TextDecoder().decode(pt);
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
