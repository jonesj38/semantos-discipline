---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-fetcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.652793+00:00
---

# cartridges/wallet-headers/brain/src/header-fetcher.ts

```ts
// Phase WH3 — Trustless SPV: multi-source HTTPS header fetcher.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH3) and §11.
//
// Three operating modes:
//
//   1. Bulk sync — `syncFromGenesis()` / `syncToHeight(target)` walks the
//      chain in fixed-size batches, validating each header through the
//      WASM verifier, appending to LocalHeaderStore. Resumes from the
//      current store tip on restart. Reports progress via callback.
//
//   2. Hybrid (lazy) — `fetchSingle(height)` retrieves one header at a time
//      and validates it. Used when a BEEF arrives whose merkle path
//      references a height not yet in the local store; the fetcher pulls
//      just that header (plus the parent chain back to a known anchor).
//      This is the *mobile-first* default — never blocks on 35MB of bulk
//      sync just to verify one BEEF.
//
//   3. Tip pull — `fetchTip()` does a one-shot tip lookup. WH4's
//      WebSocket subscriber prefers push, but falls back to polling tip
//      via this method on disconnect.
//
// Multi-source failover: each operation iterates over the configured source
// list, trying each adapter in order. Failures (network, 4xx/5xx, validator
// rejection) advance to the next source. The wallet emits a structured log
// per failover so operator misbehavior is auditable.

import {
  HEADER_BYTES,
  type HeaderValidator,
  type ValidateContext,
  type ValidateError,
  POW_LIMIT_BITS,
} from './header-validator';
import {
  type HeaderSource,
  type HeaderSourceAdapter,
  type TipInfo,
  makeAdapter,
} from './header-source-adapter';
import { LocalHeaderStore, type HeaderRecord } from './header-store';

/** Default batch size for bulk sync — matches block-headers-service's
 *  comfortable response size (~160KB binary). */
export const DEFAULT_BATCH_SIZE = 2000;

/** Default reorg-protection depth. */
export const DEFAULT_REORG_DEPTH = 6;

export interface FetcherOptions {
  /** Configured source list, in failover order. */
  sources: HeaderSource[];
  /** Batch size for bulk sync (default 2000). */
  batchSize?: number;
  /** Validator instance (Wasm or Js). */
  validator: HeaderValidator;
  /** Local header store. */
  store: LocalHeaderStore;
  /** Optional progress callback (called once per appended header for hybrid,
   *  per batch for bulk). */
  onProgress?: (info: ProgressInfo) => void;
  /** Optional structured log sink for failover/diagnostic events. */
  onEvent?: (ev: FetcherEvent) => void;
  /** Override `pow_limit_bits` for tests/regtest. Default = mainnet powLimit. */
  powLimitBits?: number;
}

export interface ProgressInfo {
  currentHeight: number;
  tipHeight: number;
  bytesDownloaded: number;
}

export type FetcherEvent =
  | { type: 'failover'; from: HeaderSource; to: HeaderSource | null; reason: string }
  | { type: 'validator_reject'; height: number; source: HeaderSource; error: ValidateError }
  | { type: 'batch_appended'; from: number; to: number; source: HeaderSource };

/**
 * Fetch + validate + persist driver. Stateless per-call — wallet code
 * builds one HeaderFetcher per session.
 */
export class HeaderFetcher {
  private readonly adapters: HeaderSourceAdapter[];
  private readonly batchSize: number;
  private readonly validator: HeaderValidator;
  private readonly store: LocalHeaderStore;
  private readonly onProgress?: (info: ProgressInfo) => void;
  private readonly onEvent?: (ev: FetcherEvent) => void;
  private readonly powLimitBits: number;
  private bytesDownloaded = 0;

  constructor(opts: FetcherOptions) {
    if (opts.sources.length === 0) throw new Error('HeaderFetcher: at least one source required');
    this.adapters = opts.sources.map(makeAdapter);
    this.batchSize = opts.batchSize ?? DEFAULT_BATCH_SIZE;
    this.validator = opts.validator;
    this.store = opts.store;
    this.onProgress = opts.onProgress;
    this.onEvent = opts.onEvent;
    this.powLimitBits = opts.powLimitBits ?? POW_LIMIT_BITS;
  }

  /**
   * Fetch + validate + append a single header at the given height. Used by
   * the hybrid lazy-fetch path when a BEEF references an unknown height.
   *
   * If the parent of the requested header is also missing, walks backward
   * (re-fetching as needed) until it reaches a known anchor or hits height
   * 0. This is bounded by reasonable BEEF depth in practice (~6-12 blocks).
   */
  async fetchSingle(height: number): Promise<HeaderRecord> {
    if (height < 0) throw new Error('fetchSingle: negative height');
    const existing = await this.store.getByHeight(height);
    if (existing) return existing;

    // Recurse: ensure parent is present unless we're at height 0.
    let parent: HeaderRecord | null = null;
    if (height > 0) {
      parent = await this.store.getByHeight(height - 1);
      if (!parent) parent = await this.fetchSingle(height - 1);
    }

    const raw = await this.tryAll((a, sig) => a.fetchByHeight(height, sig));
    return await this.validateAndAppend(raw, height, parent);
  }

  /**
   * Bulk sync from `fromHeight` to `toHeight` (inclusive). Resumes from
   * the current store tip if higher than `fromHeight`.
   */
  async syncRange(fromHeight: number, toHeight: number): Promise<void> {
    if (toHeight < fromHeight) return;

    // Resume: bump fromHeight to the height after the current tip.
    const tip = await this.store.tip();
    let cursor = tip ? tip.height + 1 : fromHeight;
    if (cursor < fromHeight) cursor = fromHeight;

    while (cursor <= toHeight) {
      const remain = toHeight - cursor + 1;
      const count = Math.min(this.batchSize, remain);
      const blob = await this.tryAll((a, sig) => a.fetchRange(cursor, count, sig));
      if (blob.length !== count * HEADER_BYTES) {
        throw new Error(
          `syncRange: source returned ${blob.length} bytes, expected ${count * HEADER_BYTES}`,
        );
      }

      // Validate + append in order. Failures abort the batch — caller can
      // retry; the store's tip moves forward only on per-header success.
      let lastSource: HeaderSourceAdapter | undefined;
      for (let i = 0; i < count; i++) {
        const raw = blob.slice(i * HEADER_BYTES, (i + 1) * HEADER_BYTES);
        const h = cursor + i;
        const parentRec = h === 0 ? null : await this.store.getByHeight(h - 1);
        if (h > 0 && !parentRec) {
          throw new Error(`syncRange: missing parent at height ${h - 1}`);
        }
        await this.validateAndAppend(raw, h, parentRec);
        lastSource = this.adapters[0];
      }

      this.onEvent?.({
        type: 'batch_appended',
        from: cursor,
        to: cursor + count - 1,
        source: { kind: lastSource?.kind ?? 'bhs', baseUrl: '' },
      });
      this.onProgress?.({
        currentHeight: cursor + count - 1,
        tipHeight: toHeight,
        bytesDownloaded: this.bytesDownloaded,
      });
      cursor += count;
    }
  }

  /** Convenience: sync from height 0 to the chain tip discovered via tip()
   *  on the configured sources. */
  async syncFromGenesis(): Promise<void> {
    const tip = await this.fetchTip();
    await this.syncRange(0, tip.height);
  }

  /** Fetch just the chain tip (one header). Failover-aware. */
  async fetchTip(): Promise<TipInfo> {
    return await this.tryAll((a, sig) => a.fetchTip(sig));
  }

  /**
   * Fetch a single header at the given height directly from the source
   * (bypassing local cache). Used by WH4's reorg-detection walk to compare
   * the network's canonical hash at a height against what the local store
   * has cached. Does NOT validate, append, or modify the store.
   */
  async fetchCanonicalAt(height: number): Promise<Uint8Array> {
    return await this.tryAll((a, sig) => a.fetchByHeight(height, sig));
  }

  // ──────────────────────────────────────────────────────────────────
  // Internals
  // ──────────────────────────────────────────────────────────────────

  private async tryAll<T>(
    op: (adapter: HeaderSourceAdapter, signal: AbortSignal) => Promise<T>,
  ): Promise<T> {
    let lastErr: unknown = null;
    for (let i = 0; i < this.adapters.length; i++) {
      const a = this.adapters[i];
      const ctrl = new AbortController();
      try {
        const result = await op(a, ctrl.signal);
        // Track byte counts for progress reporting. T may not be bytes, so
        // best-effort: only inspect Uint8Array results.
        if (result instanceof Uint8Array) {
          this.bytesDownloaded += result.length;
        } else if (typeof result === 'object' && result !== null && 'raw' in result) {
          const raw = (result as { raw: unknown }).raw;
          if (raw instanceof Uint8Array) this.bytesDownloaded += raw.length;
        }
        return result;
      } catch (e) {
        lastErr = e;
        const next = this.adapters[i + 1];
        this.onEvent?.({
          type: 'failover',
          from: { kind: a.kind, baseUrl: '' },
          to: next ? { kind: next.kind, baseUrl: '' } : null,
          reason: (e as Error).message,
        });
      }
    }
    throw new Error(`all sources failed: ${(lastErr as Error)?.message ?? 'unknown'}`);
  }

  private async validateAndAppend(
    raw: Uint8Array,
    height: number,
    parent: HeaderRecord | null,
  ): Promise<HeaderRecord> {
    if (raw.length !== HEADER_BYTES) {
      throw new Error(`validateAndAppend: bad length ${raw.length}`);
    }
    if (height === 0) {
      // Genesis: skip parent-linkage / DAA checks; verify PoW only.
      if (!this.validator.satisfiesPoW(raw)) {
        this.onEvent?.({
          type: 'validator_reject',
          height,
          source: { kind: 'bhs', baseUrl: '' },
          error: 'insufficient_pow',
        });
        throw new Error(`validator rejected genesis: insufficient_pow`);
      }
    } else {
      if (!parent) throw new Error(`validateAndAppend: parent missing at height ${height}`);
      const prevTimestamps = await this.collectPrevTimestamps(height - 1, 11);
      const ctx: ValidateContext = {
        parent: parent.header,
        parentHeight: height - 1,
        prevTimestamps,
        powLimitBits: this.powLimitBits,
      };
      const err = this.validator.validate(raw, ctx);
      if (err) {
        this.onEvent?.({
          type: 'validator_reject',
          height,
          source: { kind: 'bhs', baseUrl: '' },
          error: err,
        });
        throw new Error(`validator rejected height ${height}: ${err}`);
      }
    }

    const hash = this.validator.hash(raw);
    const record: HeaderRecord = { header: raw, hash, height };
    const appendErr = await this.store.appendValidated(record);
    if (appendErr) {
      throw new Error(`store rejected height ${height}: ${appendErr}`);
    }
    return record;
  }

  private async collectPrevTimestamps(endHeight: number, n: number): Promise<number[]> {
    // Pull up to `n` timestamps for heights endHeight, endHeight-1, ...
    const out: number[] = [];
    for (let h = endHeight; h >= 0 && out.length < n; h--) {
      const rec = await this.store.getByHeight(h);
      if (!rec) break;
      // Decode timestamp at offset 68 (LE u32).
      const ts =
        rec.header[68] |
        (rec.header[69] << 8) |
        (rec.header[70] << 16) |
        rec.header[71] * 0x01000000;
      out.push(ts);
    }
    return out;
  }
}

```
