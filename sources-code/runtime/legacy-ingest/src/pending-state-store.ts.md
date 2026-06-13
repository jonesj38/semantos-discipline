---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/pending-state-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.135712+00:00
---

# runtime/legacy-ingest/src/pending-state-store.ts

```ts
/**
 * Encrypted-at-rest OAuth pending-state store — bug-fix companion to
 * the in-memory `OAuthOrchestrator.pending` Map.
 *
 * ── Why this exists ──
 *
 * The legacy-cli is invoked as one-shot bun verbs (`bun apps/legacy-cli/
 * src/cli.ts <verb>`). Each invocation is a fresh process:
 *
 *   1. `legacy connect gmail`  → process A: prepareGrant() puts a
 *      pending state-nonce into the orchestrator's Map, prints the
 *      authorize URL, then exits → Map is gone.
 *   2. `legacy resume <state>` → process B: a *new* orchestrator with
 *      an *empty* Map; lookup fails with "state nonce unknown or
 *      expired".
 *
 * Persisting the pending state to disk between connect and resume
 * fixes that. The orchestrator opt is optional — embedded uses (the
 * widget server, in-process tests) keep the in-memory Map.
 *
 * ── Envelope ──
 *
 * Mirrors `grant-store.ts`'s envelope shape so the same KEK derivation
 * is used end-to-end (per-byte layout below). The pending state holds
 * the PKCE verifier + provider id + redirect URI — all secrets that
 * deserve encryption at rest.
 *
 *   bytes  0..4    u32 LE   format version (= 1)
 *   bytes  4..8    u32 LE   reserved (was tier — 0 here too)
 *   bytes  8..20   12 bytes nonce (random per write)
 *   bytes 20..36   16 bytes AES-GCM tag
 *   bytes 36..     ciphertext (UTF-8 JSON-encoded OAuthPendingState)
 *
 * AAD is `version || reserved || nonce` (20 bytes), identical to
 * grant-store. Wrong-KEK decrypts return null (not throw) so the
 * orchestrator surfaces the same `bad_state` error on resume.
 *
 * ── TTL ──
 *
 * The orchestrator's existing default `pendingTtlMs` is 10 minutes
 * (oauth.ts:175). TTL is enforced via file mtime — the store deletes
 * any file older than the TTL on `get()` and during `sweepExpired()`.
 * Cleanup is cheap (typically ≤ a few entries) and runs on every
 * `prepareGrant` and `exchangeCode`.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1; this is a
 * disk-backed sibling of the in-memory `pending` Map.
 */

import type { OAuthPendingState } from './types';

const FORMAT_VERSION = 1;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const HEADER_BYTES = 4 + 4 + NONCE_BYTES + TAG_BYTES; // 36

/**
 * Persistence adapter for the pending store. Like `GrantPersistence`
 * but adds `mtimeMs` so the store can enforce TTL on read without
 * having to decrypt to look at `createdAt`.
 *
 * Browser/host wires this to fs (`FsPendingPersistence` in legacy-cli)
 * or to an in-memory adapter for tests.
 */
export interface PendingPersistence {
  read(key: string): Promise<Uint8Array | null>;
  write(key: string, data: Uint8Array): Promise<void>;
  delete(key: string): Promise<void>;
  /** List all entries under the configured prefix. */
  list(): Promise<string[]>;
  /** Returns ms-precision mtime, or null if the entry no longer exists. */
  mtimeMs(key: string): Promise<number | null>;
}

/** KEK provider — same shape as `grant-store.ts`. */
export type KekProvider = () => Promise<CryptoKey | null>;

export class PendingStoreLocked extends Error {
  constructor() {
    super('legacy-ingest pending-state store: wallet KEK unavailable (wallet locked?)');
    this.name = 'PendingStoreLocked';
  }
}

export interface PendingStateStoreOpts {
  persistence: PendingPersistence;
  kekProvider: KekProvider;
  /**
   * TTL for pending state. Default 10 minutes — matches the
   * orchestrator's in-memory default at oauth.ts:175.
   */
  pendingTtlMs?: number;
  /** Crypto namespace — defaults to globalThis.crypto. Tests inject a fake. */
  cryptoImpl?: Crypto;
  /** Clock seam — defaults to Date.now. Tests inject a fake. */
  now?: () => number;
}

/**
 * Encrypted-at-rest pending-state store. Round-trip test cover:
 * `runtime/legacy-ingest/src/__tests__/pending-state-store.test.ts`.
 */
export class PendingStateStore {
  private readonly persistence: PendingPersistence;
  private readonly kekProvider: KekProvider;
  private readonly pendingTtlMs: number;
  private readonly cryptoImpl: Crypto;
  private readonly nowFn: () => number;

  constructor(opts: PendingStateStoreOpts) {
    this.persistence = opts.persistence;
    this.kekProvider = opts.kekProvider;
    this.pendingTtlMs = opts.pendingTtlMs ?? 10 * 60 * 1000;
    this.cryptoImpl = opts.cryptoImpl ?? globalThis.crypto;
    this.nowFn = opts.now ?? (() => Date.now());
  }

  /** Persist (or replace) a pending state keyed by its `nonce`. */
  async put(state: OAuthPendingState): Promise<void> {
    const kek = await this.kekProvider();
    if (!kek) throw new PendingStoreLocked();
    const json = JSON.stringify(state);
    const plaintext = new TextEncoder().encode(json);
    const blob = await this.encrypt(kek, plaintext);
    await this.persistence.write(this.keyFor(state.nonce), blob);
  }

  /**
   * Fetch one pending state. Returns null when:
   *   - the entry doesn't exist
   *   - the entry's mtime is older than the TTL (also deletes the file)
   *   - decryption fails (wrong KEK, tampered, or unreadable)
   *
   * Callers (the orchestrator) treat null as "unknown state" — the
   * same outcome as the in-memory Map.
   */
  async get(nonce: string): Promise<OAuthPendingState | null> {
    const kek = await this.kekProvider();
    if (!kek) throw new PendingStoreLocked();
    const key = this.keyFor(nonce);

    // TTL check up front — avoids decrypting an expired entry.
    const mtime = await this.persistence.mtimeMs(key);
    if (mtime === null) return null;
    if (this.nowFn() - mtime > this.pendingTtlMs) {
      await this.persistence.delete(key);
      return null;
    }

    const blob = await this.persistence.read(key);
    if (!blob) return null;
    try {
      const plaintext = await this.decrypt(kek, blob);
      return JSON.parse(new TextDecoder().decode(plaintext)) as OAuthPendingState;
    } catch {
      // Wrong KEK or tampered — fail closed, surfaces as bad_state.
      return null;
    }
  }

  /** Delete one pending state — irreversible. */
  async delete(nonce: string): Promise<void> {
    await this.persistence.delete(this.keyFor(nonce));
  }

  /**
   * Sweep + delete every pending entry whose mtime is older than the
   * TTL. Returns the count deleted. Cheap to call on every prepare /
   * exchange; the directory typically has ≤ a handful of entries.
   */
  async sweepExpired(): Promise<number> {
    const cutoff = this.nowFn() - this.pendingTtlMs;
    const keys = await this.persistence.list();
    let deleted = 0;
    for (const key of keys) {
      const mtime = await this.persistence.mtimeMs(key);
      if (mtime !== null && mtime < cutoff) {
        await this.persistence.delete(key);
        deleted += 1;
      }
    }
    return deleted;
  }

  /** Path key — single flat directory of `<nonce>.json` files. */
  private keyFor(nonce: string): string {
    // Nonces are b64url (no path-unsafe chars). Append `.json` so
    // ad-hoc inspection is obvious about content type even though
    // bytes are encrypted.
    return `${nonce}.json`;
  }

  // ── envelope (mirrors grant-store.ts) ──

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
    if (blob.length < HEADER_BYTES) {
      throw new Error('blob shorter than header');
    }
    const dv = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
    if (dv.getUint32(0, true) !== FORMAT_VERSION) {
      throw new Error('unknown format version');
    }
    const nonce = blob.subarray(8, 20);
    const tag = blob.subarray(20, 36);
    const ciphertext = blob.subarray(36);
    const aad = this.buildAad(nonce);
    const ctWithTag = new Uint8Array(ciphertext.length + tag.length);
    ctWithTag.set(ciphertext, 0);
    ctWithTag.set(tag, ciphertext.length);
    return new Uint8Array(
      await this.cryptoImpl.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad },
        kek,
        ctWithTag,
      ),
    );
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
