---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-spv.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.661446+00:00
---

# cartridges/wallet-headers/brain/src/header-spv.ts

```ts
// Phase WH5 — Trustless SPV: browser-side LocalHeaderChainTracker + SPV
// mode policy.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH5).
//
// The wallet's BEEF validation path needs trusted merkle roots. Pre-WH the
// wallet would have to fetch them from an indexer (or run gullible mode).
// WH5 closes that gap: every merkle root the wallet trusts comes from a
// header that already passed `headers.zig` PoW validation locally.
//
// Three modes mirror the spec / Zig `local_chain_tracker.zig`:
//
//   • 'strict'  — headers must already be in the local store. Missing →
//                 reject. Default for users who've opted in to bulk sync.
//
//   • 'hybrid'  — headers may be missing locally; tracker lazy-fetches via
//                 the WH3 fetcher and caches before answering. The mobile-
//                 friendly default — never blocks a BEEF behind a 35MB
//                 initial sync, only behind a single-header fetch (~1KB).
//
//   • 'gullible' — DEBUG ONLY. Always returns true. v0.4 escape hatch; gated
//                  in production by a console flag.
//
// This module exposes a single `LocalChainTracker` class and the
// `getTrustedRootForHeight()` helper that BEEF-validation call sites use to
// resolve a height → merkle_root mapping. Wiring into `internalizeAction`
// happens in the WA-phase that introduces that surface.

import { LocalHeaderStore } from './header-store';
import { HeaderFetcher } from './header-fetcher';

export type SpvMode = 'strict' | 'hybrid' | 'gullible';

/** Default for new wallets: hybrid lazy-fetch. Once the user opts in to
 *  bulk sync the wallet should switch to 'strict' to gate any future
 *  BEEF on already-verified headers. */
export const DEFAULT_SPV_MODE: SpvMode = 'hybrid';

export class LocalChainTrackerError extends Error {
  constructor(
    readonly kind: 'header_missing' | 'fetch_failed' | 'merkle_root_mismatch',
    msg: string,
  ) {
    super(msg);
  }
}

export interface LocalChainTrackerOptions {
  store: LocalHeaderStore;
  /** Optional — required for hybrid mode lazy-fetch. */
  fetcher?: HeaderFetcher;
  mode?: SpvMode;
}

/**
 * Resolves "merkle root at height H" against the local PoW-verified header
 * store, with optional lazy-fetch in hybrid mode.
 *
 * Surface mirrors the bsvz `chain_tracker` contract — `isValidRootForHeight`
 * is the canonical query. Everything else is convenience.
 */
export class LocalChainTracker {
  private readonly store: LocalHeaderStore;
  private readonly fetcher: HeaderFetcher | null;
  readonly mode: SpvMode;

  constructor(opts: LocalChainTrackerOptions) {
    this.store = opts.store;
    this.fetcher = opts.fetcher ?? null;
    this.mode = opts.mode ?? DEFAULT_SPV_MODE;
    if (this.mode === 'hybrid' && !this.fetcher) {
      // Hybrid mode without a fetcher degenerates to strict — surface this
      // as a configuration warning. We allow construction so callers in
      // edge cases (replay-only, offline) can proceed.
    }
  }

  /**
   * Look up the merkle_root for the block at `height`. Returns null if the
   * header isn't available under the configured mode.
   *
   *   strict   — null only if the lookup hits a real persistence failure.
   *              Missing-locally throws `LocalChainTrackerError('header_missing')`.
   *   hybrid   — lazy-fetches if missing; returns null only if fetch fails.
   *   gullible — DEBUG: never queried; the BEEF caller should use the
   *              gullible bypass directly.
   */
  async getMerkleRootAt(height: number): Promise<Uint8Array | null> {
    if (this.mode === 'gullible') {
      // The caller should not be querying us in gullible mode — gullible
      // means "skip merkle root validation entirely". Returning null here
      // makes any subsequent equality check fail; we'd rather throw.
      throw new LocalChainTrackerError(
        'header_missing',
        'gullible mode: caller must skip the chain-tracker path',
      );
    }
    let rec = await this.store.getByHeight(height);
    if (!rec && this.mode === 'hybrid' && this.fetcher) {
      try {
        rec = await this.fetcher.fetchSingle(height);
      } catch (e) {
        throw new LocalChainTrackerError(
          'fetch_failed',
          `lazy fetch h=${height}: ${(e as Error).message}`,
        );
      }
    }
    if (!rec) {
      if (this.mode === 'strict') {
        throw new LocalChainTrackerError(
          'header_missing',
          `strict mode: no local header at height ${height}`,
        );
      }
      return null;
    }
    // merkle_root is bytes 36..68 of the 80-byte header (internal byte order).
    return rec.header.slice(36, 68);
  }

  /**
   * bsvz-style query: "is `root` the canonical merkle root at `height`?"
   *
   *   strict   — throws `header_missing` if the height isn't local.
   *   hybrid   — lazy-fetches first, then compares.
   *   gullible — always true (matches bsvz.spv.GullibleChainTracker).
   */
  async isValidRootForHeight(root: Uint8Array, height: number): Promise<boolean> {
    if (this.mode === 'gullible') return true;
    const local = await this.getMerkleRootAt(height);
    if (!local) return false; // hybrid + fetch returned null
    return bytesEqual(local, root);
  }
}

/**
 * Convenience helper for BEEF callers that already know the heights their
 * BEEF references — produces an array of trusted-root bytes ready to pass
 * to the kernel's `kernel_verify_beef_spv(beef, txid, roots)`.
 *
 * In strict mode any missing height throws; the caller should treat that as
 * a hard reject (the wallet does not have the chain context to verify this
 * BEEF and refuses to risk it).
 *
 * In hybrid mode missing headers trigger lazy fetches via the WH3 fetcher.
 */
export async function buildTrustedRoots(
  tracker: LocalChainTracker,
  heights: number[],
): Promise<Uint8Array> {
  const out = new Uint8Array(heights.length * 32);
  for (let i = 0; i < heights.length; i++) {
    const root = await tracker.getMerkleRootAt(heights[i]);
    if (!root) {
      throw new LocalChainTrackerError(
        'header_missing',
        `buildTrustedRoots: height ${heights[i]} unavailable`,
      );
    }
    out.set(root, i * 32);
  }
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
