---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-tip.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.655199+00:00
---

# cartridges/wallet-headers/brain/src/header-tip.ts

```ts
// Phase WH4 — Trustless SPV: tip-following subscriber + reorg handling.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH4) and §11.5.
//
// Keeps the LocalHeaderStore tip in sync with the live BSV chain. Two
// transports, picked behind an interface so tests can drive either:
//
//   • CentrifugeTipChannel — speaks the centrifuge JSON dialect that both
//     `block-headers-service` and Teranode's centrifuge_impl/websocket.go
//     expose. Receives `{ data: <80-byte-base64-or-hex> }` payloads on a
//     subscribed channel; pushes them through WH1's verifier and appends.
//
//   • SsePollTipChannel — Server-Sent Events (preferred for the eventual
//     BRAIN `headers serve` mode — much simpler than centrifuge) plus a poll
//     fallback. The wallet's reorg-detection / catch-up logic is identical
//     across transports — only the message decode differs.
//
// On a tip-arrival event the subscriber:
//   1. Decodes the new 80-byte raw header.
//   2. If new.prev_hash == local.tip.hash: validate + append. Done.
//   3. Else (reorg or missed blocks): trigger the catch-up handler — pull
//      headers from `local.tip - reorgDepth` to the new tip via the WH3
//      fetcher; if the new chain genuinely diverges from the local chain
//      below the local tip, drop the divergent suffix via
//      `LocalHeaderStore.rollbackFrom` and re-append from the authoritative
//      chain. Surface a `chain_reorg` event upstream.

import { type HeaderValidator, HEADER_BYTES, POW_LIMIT_BITS } from './header-validator';
import { LocalHeaderStore, type HeaderRecord } from './header-store';
import { HeaderFetcher } from './header-fetcher';

export const DEFAULT_REORG_DEPTH = 6;
export const DEFAULT_RECONNECT_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000];

export type TipEvent =
  | { type: 'tip_advanced'; height: number; hash: Uint8Array }
  | { type: 'chain_reorg'; oldTipHeight: number; newTipHeight: number; depth: number }
  | { type: 'transport_disconnect'; reason: string }
  | { type: 'transport_reconnect' }
  | { type: 'transport_error'; reason: string };

export interface TipChannelMessage {
  /** Decoded 80-byte raw header. */
  raw: Uint8Array;
  /** Optional height hint from the server. If absent, the subscriber
   *  computes it as local.tip.height + 1 and validates accordingly. */
  height?: number;
}

/** Transport contract — pushes one TipChannelMessage per new-block event. */
export interface TipChannelTransport {
  /** Open the channel; resolve when the subscription is established. */
  connect(): Promise<void>;
  /** Close the channel; resolve when fully torn down. */
  disconnect(): Promise<void>;
  /** Returns true iff the channel is currently connected. */
  isConnected(): boolean;
  /** Register a handler called with every new-tip event. */
  onMessage(handler: (msg: TipChannelMessage) => void): void;
  /** Register a handler called when the transport breaks. */
  onError(handler: (reason: string) => void): void;
}

export interface TipSubscriberOptions {
  transport: TipChannelTransport;
  store: LocalHeaderStore;
  fetcher: HeaderFetcher;
  validator: HeaderValidator;
  /** Max reorg depth — subscriber rolls back at most this many blocks
   *  before refusing to reconcile. Default 6. */
  reorgDepth?: number;
  /** Optional event sink. */
  onEvent?: (ev: TipEvent) => void;
  /** Override `pow_limit_bits` for tests/regtest. */
  powLimitBits?: number;
}

/**
 * Tip-following subscriber. Construct once per wallet session; call `start()`
 * to connect, `stop()` to tear down. Reorgs are handled transparently — the
 * caller observes them via `onEvent`.
 */
export class TipSubscriber {
  private readonly transport: TipChannelTransport;
  private readonly store: LocalHeaderStore;
  private readonly fetcher: HeaderFetcher;
  private readonly validator: HeaderValidator;
  private readonly reorgDepth: number;
  private readonly onEvent?: (ev: TipEvent) => void;
  private readonly powLimitBits: number;
  private running = false;
  private inflight: Promise<void> = Promise.resolve();

  constructor(opts: TipSubscriberOptions) {
    this.transport = opts.transport;
    this.store = opts.store;
    this.fetcher = opts.fetcher;
    this.validator = opts.validator;
    this.reorgDepth = opts.reorgDepth ?? DEFAULT_REORG_DEPTH;
    this.onEvent = opts.onEvent;
    this.powLimitBits = opts.powLimitBits ?? POW_LIMIT_BITS;
  }

  async start(): Promise<void> {
    if (this.running) return;
    this.running = true;
    this.transport.onMessage((msg) => {
      // Serialize handling: each tip event waits for the prior one so the
      // store's tip never racewrites with itself.
      this.inflight = this.inflight.then(() => this.handleTip(msg)).catch((e) => {
        this.onEvent?.({ type: 'transport_error', reason: (e as Error).message });
      });
    });
    this.transport.onError((reason) => {
      this.onEvent?.({ type: 'transport_disconnect', reason });
    });
    await this.transport.connect();
    this.onEvent?.({ type: 'transport_reconnect' });
  }

  async stop(): Promise<void> {
    if (!this.running) return;
    this.running = false;
    await this.transport.disconnect();
    await this.inflight;
  }

  /** Wait for the in-flight tip-handling chain to finish. Test convenience. */
  async settle(): Promise<void> {
    await this.inflight;
  }

  private async handleTip(msg: TipChannelMessage): Promise<void> {
    if (msg.raw.length !== HEADER_BYTES) {
      this.onEvent?.({
        type: 'transport_error',
        reason: `tip msg: bad length ${msg.raw.length}`,
      });
      return;
    }

    const newHash = this.validator.hash(msg.raw);
    const localTip = await this.store.tip();
    if (!localTip) {
      // No local chain yet — defer to a fetcher sync.  We can't validate a
      // single header without the parent.  Surface as transport_error and
      // let the caller schedule a syncFromGenesis.
      this.onEvent?.({
        type: 'transport_error',
        reason: 'tip arrived but local store is empty — schedule a bulk sync first',
      });
      return;
    }

    const newPrevHash = msg.raw.slice(4, 36);
    if (bytesEqual(newPrevHash, localTip.hash)) {
      // Fast path: direct successor.
      const expectedHeight = localTip.height + 1;
      const prevTimestamps = await this.collectPrevTimestamps(localTip.height, 11);
      const err = this.validator.validate(msg.raw, {
        parent: localTip.header,
        parentHeight: localTip.height,
        prevTimestamps,
        powLimitBits: this.powLimitBits,
      });
      if (err) {
        this.onEvent?.({
          type: 'transport_error',
          reason: `tip rejected: ${err}`,
        });
        return;
      }
      const rec: HeaderRecord = { header: msg.raw, hash: newHash, height: expectedHeight };
      const appendErr = await this.store.appendValidated(rec);
      if (appendErr) {
        this.onEvent?.({
          type: 'transport_error',
          reason: `tip append rejected: ${appendErr}`,
        });
        return;
      }
      this.onEvent?.({ type: 'tip_advanced', height: expectedHeight, hash: newHash });
      return;
    }

    // Reorg path. Strategy:
    //   1. Identify the deepest local height H* such that the local
    //      block-hash at H* matches the new chain's hash at H*.
    //   2. Roll back local from H* + 1.
    //   3. Re-fetch from H* + 1 to the new tip via WH3 fetcher.
    // Bound the search at `reorgDepth` — anything deeper aborts and we
    // surface to the user.

    // We don't know the new tip's height from the message alone reliably;
    // ask the fetcher for it.
    let newTipInfo;
    try {
      newTipInfo = await this.fetcher.fetchTip();
    } catch (e) {
      this.onEvent?.({
        type: 'transport_error',
        reason: `reorg detect: tip fetch failed: ${(e as Error).message}`,
      });
      return;
    }

    const reorgFrom = Math.max(0, localTip.height - this.reorgDepth);
    if (newTipInfo.height < reorgFrom) {
      this.onEvent?.({
        type: 'transport_error',
        reason: `reorg too deep: new tip ${newTipInfo.height} below reorg window ${reorgFrom}`,
      });
      return;
    }

    // Find the deepest matching local height by querying the source for
    // the canonical hash at each candidate height. Use the cache-bypassing
    // `fetchCanonicalAt` — `fetchSingle` would return the locally cached
    // (now-orphaned) header. Depth is bounded by `reorgDepth`.
    let commonAncestorHeight = -1;
    for (let h = localTip.height; h >= reorgFrom; h--) {
      let canonicalHash: Uint8Array;
      try {
        const raw = await this.fetcher.fetchCanonicalAt(h);
        canonicalHash = this.validator.hash(raw);
      } catch (e) {
        this.onEvent?.({
          type: 'transport_error',
          reason: `reorg detect: fetch h=${h} failed: ${(e as Error).message}`,
        });
        return;
      }
      const local = await this.store.getByHeight(h);
      if (local && bytesEqual(local.hash, canonicalHash)) {
        commonAncestorHeight = h;
        break;
      }
    }

    if (commonAncestorHeight === -1) {
      this.onEvent?.({
        type: 'transport_error',
        reason: `reorg too deep: no common ancestor within ${this.reorgDepth} blocks`,
      });
      return;
    }

    const dropFrom = commonAncestorHeight + 1;
    if (dropFrom <= localTip.height) {
      const dropped = await this.store.rollbackFrom(dropFrom);
      this.onEvent?.({
        type: 'chain_reorg',
        oldTipHeight: localTip.height,
        newTipHeight: newTipInfo.height,
        depth: dropped,
      });
    }
    // Re-extend from the new chain.
    if (newTipInfo.height > commonAncestorHeight) {
      try {
        await this.fetcher.syncRange(dropFrom, newTipInfo.height);
      } catch (e) {
        this.onEvent?.({
          type: 'transport_error',
          reason: `reorg rebuild failed: ${(e as Error).message}`,
        });
        return;
      }
    }
    this.onEvent?.({
      type: 'tip_advanced',
      height: newTipInfo.height,
      hash: this.validator.hash(newTipInfo.raw),
    });
  }

  private async collectPrevTimestamps(endHeight: number, n: number): Promise<number[]> {
    const out: number[] = [];
    for (let h = endHeight; h >= 0 && out.length < n; h--) {
      const rec = await this.store.getByHeight(h);
      if (!rec) break;
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

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

// ─────────────────────────────────────────────────────────────────────
// Test transport — used by header-tip.spec.ts and any wallet code that
// needs to drive a tip subscriber without a real network channel.
// ─────────────────────────────────────────────────────────────────────

export class InMemoryTipChannel implements TipChannelTransport {
  private connected = false;
  private msgHandler: ((msg: TipChannelMessage) => void) | null = null;
  private errHandler: ((reason: string) => void) | null = null;

  async connect(): Promise<void> {
    this.connected = true;
  }
  async disconnect(): Promise<void> {
    this.connected = false;
  }
  isConnected(): boolean {
    return this.connected;
  }
  onMessage(h: (msg: TipChannelMessage) => void): void {
    this.msgHandler = h;
  }
  onError(h: (reason: string) => void): void {
    this.errHandler = h;
  }
  /** Test driver: simulate the server pushing a new tip. */
  push(msg: TipChannelMessage): void {
    if (this.connected) this.msgHandler?.(msg);
  }
  /** Test driver: simulate a transport break. */
  pushError(reason: string): void {
    this.errHandler?.(reason);
  }
}

```
