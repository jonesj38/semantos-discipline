---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.781960+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/types.ts

```ts
/**
 * Public types + shared constants for the direct-broadcast engine.
 *
 * Pinned identical to the legacy `direct-broadcast-engine.ts`
 * exports so consumers (`game-loop.ts`, `arena/*`) keep compiling
 * after the prompt-18 split.
 */

import type { Transaction } from '@bsv/sdk';

export interface FundingUtxo {
  txid: string;
  vout: number;
  satoshis: number;
  /** The source transaction (needed for signing). */
  sourceTx: Transaction;
}

export interface DirectBroadcastConfig {
  /** ARC endpoint. Default: GorillaPool (no API key). */
  arcUrl?: string;
  /** ARC API key (optional — GorillaPool doesn't need one). */
  arcApiKey?: string;
  /** Number of parallel streams to run. */
  streams?: number;
  /** Satoshis per CellToken output. Default: 1. */
  cellSatoshis?: number;
  /** Satoshis per funding UTXO split. Default: 500. */
  splitSatoshis?: number;
  /** Log verbosity. */
  verbose?: boolean;
  /**
   * Fire-and-forget: don't await ARC broadcast confirmation. The tx
   * is built, signed, and dispatched in the background. The return
   * value uses the locally-computed txid (no round-trip).
   */
  fireAndForget?: boolean;
}

export interface BroadcastResult {
  txid: string;
  /** ms elapsed for broadcast. 0 in fire-and-forget mode. */
  broadcastMs: number;
  /** ms elapsed for tx construction. */
  buildMs: number;
  /** Signed transaction object so callers can chain into the next op. */
  tx: Transaction;
}

export interface StreamStats {
  streamId: number;
  txCount: number;
  totalMs: number;
  avgMs: number;
  txPerSec: number;
}

/**
 * Event emitted whenever a tx is built / broadcast — consumed by
 * `tx-stats-collector.ts` so stats live in an atom rather than
 * mutable engine fields. Both fire-and-forget and synchronous modes
 * emit `'broadcast'` events with their measured timings.
 */
export type BroadcastEvent =
  | {
      type: 'broadcast';
      label: string;
      txid: string;
      buildMs: number;
      broadcastMs: number;
      fireAndForget: boolean;
    }
  | { type: 'broadcast-error'; label: string; message: string }
  | { type: 'utxo-recycled'; streamId: number; satoshis: number }
  | { type: 'utxo-discarded'; streamId: number; satoshis: number };

// ── Shared constants ─────────────────────────────────────────────

// NOTE: @bsv/sdk ARC class appends /v1/tx to this URL, so do NOT
// include /v1 here.
export const DEFAULT_ARC_URL = 'https://arc.gorillapool.io';
export const FEE_RATE = 1; // sats per byte
export const MIN_FEE = 50; // ARC reject floor
export const FIXED_CELL_FEE = 150; // empirical fee for CellToken txs
export const MIN_USEFUL_SATS = 151; // covers fixed fee + 1-sat output

```
