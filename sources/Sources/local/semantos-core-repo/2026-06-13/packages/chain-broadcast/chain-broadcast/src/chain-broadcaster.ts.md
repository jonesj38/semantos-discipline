---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/chain-broadcaster.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.520103+00:00
---

# packages/chain-broadcast/chain-broadcast/src/chain-broadcaster.ts

```ts
/**
 * ChainBroadcaster — facade composing the chain-broadcast services.
 *
 * Orchestrates the four focused services into the six high-level
 * operations a bulk-anchoring consumer actually wants:
 *
 *   - ingestFunding(utxos, streamId?)        → ChainTipManager
 *   - preSplit(funding)                       → CellTxBuilder + MapiBroadcaster
 *   - createCellToken(streamId, cell, …)      → all four
 *   - transitionCellToken(streamId, prev, …)  → all four
 *   - anchorOpReturn(streamId, payload)       → all four
 *   - sweepAll(toAddress)                      → CellTxBuilder + MapiBroadcaster
 *
 * Wiring:
 *   CellTxBuilder      builds + signs   (@bsv/sdk)
 *   MapiBroadcaster    submits to ARC/MAPI (configurable, ARC injectable)
 *   ChainTipManager    UTXO pool dedup + `waitForArcSeen`
 *   BeefStore          optional BRC-62 envelope persistence
 *
 * Each hot-path method:
 *   1. Pick a UTXO from ChainTipManager.
 *   2. Ask CellTxBuilder to build + sign.
 *   3. Hand to MapiBroadcaster for submit.
 *   4. If BeefStore present, merge the tx + its ancestry.
 *   5. Recycle the change output back into ChainTipManager.
 *   6. Append an audit-log row if configured.
 *
 * Extracted from the hackathon `DirectBroadcastEngine` at
 * todriguez/hackathon-submission:src/agent/direct-broadcast-engine.ts@496ee8f
 * — the orchestration-root methods only, split from the mechanical work
 * that now lives in the four focused files.
 */

import {
  PrivateKey,
  type PublicKey,
  type Transaction,
  type ARC,
} from "@bsv/sdk";
import { appendFileSync } from "node:fs";

import { BeefStore, type BeefStoreConfig } from "./beef-store.js";
import {
  CellTxBuilder,
  type BuiltTx,
  type CellTxBuilderConfig,
} from "./cell-tx-builder.js";
import {
  ChainTipManager,
  type ChainTipManagerConfig,
  type FundingUtxo,
} from "./chain-tip-manager.js";
import {
  MapiBroadcaster,
  type MapiBroadcasterConfig,
} from "./mapi-broadcaster.js";

export interface ChainBroadcasterConfig {
  // ── Keys ─────────────────────────────────────────────
  /**
   * Signing key. Provide exactly one of:
   *   - `privateKey` (pre-constructed PrivateKey)
   *   - `privateKeyWif` (base58 WIF)
   *   - `privateKeyHex` (64 hex chars)
   *   - `keySeed` (any string — SHA-256 → 32 bytes → PrivateKey)
   *   - none (generate a random key)
   */
  privateKey?: PrivateKey;
  privateKeyWif?: string;
  privateKeyHex?: string;
  keySeed?: string;

  // ── Builder ──────────────────────────────────────────
  feeRate?: number;
  minFee?: number;
  cellSatoshis?: number;
  splitSatoshis?: number;

  // ── Broadcaster ──────────────────────────────────────
  mode?: MapiBroadcasterConfig["mode"];
  arcUrl?: string;
  arcApiKey?: string;
  mapiUrl?: string;
  fireAndForget?: boolean;
  batchSize?: number;
  batchFlushMs?: number;
  enableWocFallback?: boolean;
  /** Pre-built ARC instance (tests pass a stub). */
  arc?: ARC;
  fetchImpl?: typeof fetch;

  // ── Chain tip ────────────────────────────────────────
  streams?: number;
  chainTipPath?: string;
  chainTipFlushMs?: number;

  // ── BEEF ─────────────────────────────────────────────
  beefStore?: Pick<BeefStoreConfig, "filePath" | "flushIntervalMs" | "chainTracker">;

  // ── Observability ────────────────────────────────────
  verbose?: boolean;
  /** Append-only CSV audit log: txid,type,satoshis,fee,bytes,timestamp */
  auditLogPath?: string;
  log?: (tag: string, msg: string) => void;
}

export interface ChainBroadcastStats {
  totalBroadcast: number;
  avgBuildMs: number;
  avgBroadcastMs: number;
  txPerSec: number;
  errors: readonly string[];
  utxoPoolSizes: number[];
  totalRemainingSats: number;
}

const DEFAULT_STREAMS = 4;

export class ChainBroadcaster {
  public readonly builder: CellTxBuilder;
  public readonly broadcaster: MapiBroadcaster;
  public readonly chainTip: ChainTipManager;
  public readonly beefStore: BeefStore | null;

  private readonly streams: number;
  private readonly auditLogPath?: string;
  private readonly log: (tag: string, msg: string) => void;
  private readonly privateKey: PrivateKey;

  // Per-instance counters for end-to-end stats (build-time).
  private totalBroadcast = 0;
  private totalBuildMs = 0;

  constructor(config: ChainBroadcasterConfig = {}) {
    this.log =
      config.log ??
      ((tag, msg) => {
        if (config.verbose)
          console.log(`\x1b[33m[CHAIN-BROADCAST:${tag}]\x1b[0m ${msg}`);
      });

    this.privateKey = resolvePrivateKey(config);
    this.streams = config.streams ?? DEFAULT_STREAMS;
    this.auditLogPath = config.auditLogPath;

    const builderConfig: CellTxBuilderConfig = {
      privateKey: this.privateKey,
      feeRate: config.feeRate,
      minFee: config.minFee,
      cellSatoshis: config.cellSatoshis,
      splitSatoshis: config.splitSatoshis,
    };
    this.builder = new CellTxBuilder(builderConfig);

    const chainTipConfig: ChainTipManagerConfig = {
      streams: this.streams,
      minFee: config.minFee ?? 135,
      cellSatoshis: config.cellSatoshis ?? 1,
      arcUrl: config.arcUrl,
      arcApiKey: config.arcApiKey,
      chainTipPath: config.chainTipPath,
      chainTipFlushMs: config.chainTipFlushMs,
      verbose: config.verbose,
    };
    this.chainTip = new ChainTipManager(chainTipConfig);

    const broadcasterConfig: MapiBroadcasterConfig = {
      mode: config.mode,
      arcUrl: config.arcUrl,
      arcApiKey: config.arcApiKey,
      mapiUrl: config.mapiUrl,
      fireAndForget: config.fireAndForget,
      batchSize: config.batchSize,
      batchFlushMs: config.batchFlushMs,
      enableWocFallback: config.enableWocFallback,
      verbose: config.verbose,
      arc: config.arc,
      fetchImpl: config.fetchImpl,
    };
    this.broadcaster = new MapiBroadcaster(broadcasterConfig);

    this.beefStore = config.beefStore
      ? new BeefStore({ ...config.beefStore, log: this.log })
      : null;

    if (this.auditLogPath) {
      // Write header row if the file is new.
      try {
        appendFileSync(
          this.auditLogPath,
          "txid,type,satoshis,fee,bytes,timestamp\n",
          { flag: "ax" },
        );
      } catch {
        /* file already exists — fine */
      }
    }
  }

  // ── Key / address accessors ──────────────────────────

  getFundingAddress(): string {
    return this.builder.getFundingAddress();
  }

  getPublicKey(): PublicKey {
    return this.builder.getPublicKey();
  }

  getPubKeyHex(): string {
    return (this.builder.getPublicKey().toDER("hex") as string);
  }

  /** Expose the signing key for advanced callers (WIF export, persistence). */
  exportPrivateKey(): PrivateKey {
    return this.privateKey;
  }

  // ── Funding ingress ──────────────────────────────────

  /**
   * Ingest one or more UTXOs into the chain-tip pools.
   * Use this when you already know which UTXOs to consume (e.g. from a
   * pre-split broadcast handed to you by the border router).
   */
  ingestFunding(utxos: FundingUtxo[] | FundingUtxo, streamId?: number): void {
    const list = Array.isArray(utxos) ? utxos : [utxos];
    this.chainTip.ingestMany(list, streamId);
  }

  /**
   * Fan out a single funding UTXO and partition the resulting splits
   * across streams. After this resolves, pools are populated and
   * downstream cell-token broadcasts can proceed.
   */
  async preSplit(
    funding: FundingUtxo,
    count?: number,
  ): Promise<{ txid: string; splits: number }> {
    const built = await this.builder.buildPreSplit(funding, {
      count,
      streamCount: this.streams,
    });
    await this.broadcaster.broadcastTx(built.tx, "preSplit");
    await this.recordTx(built, "split", funding.satoshis);

    // Wait for ARC to index the parent so children don't orphan.
    await this.chainTip.waitForArcSeen(built.txid).catch(() => false);

    // Partition splits round-robin across streams.
    this.chainTip.ingestMany(built.splits);

    this.log(
      "SPLIT",
      `✓ ${built.txid} (${built.splits.length} splits, fee ${built.fee})`,
    );
    return { txid: built.txid, splits: built.splits.length };
  }

  // ── Hot paths ────────────────────────────────────────

  async createCellToken(
    streamId: number,
    cellBytes: Uint8Array,
    semanticPath: string,
    contentHash: Uint8Array,
  ): Promise<BuiltTx & { broadcastMs: number; buildMs: number }> {
    const funding = this.chainTip.pick(streamId, "create");
    const t0 = Date.now();
    const built = await this.builder.buildCellToken(
      funding,
      cellBytes,
      semanticPath,
      contentHash,
    );
    const buildMs = Date.now() - t0;

    await this.recordTx(built, "celltoken", funding.satoshis);
    const { broadcastMs } = await this.broadcaster.broadcastTx(
      built.tx,
      "CellToken",
    );

    this.recycleChange(streamId, built);
    this.totalBroadcast++;
    this.totalBuildMs += buildMs;
    return { ...built, broadcastMs, buildMs };
  }

  async transitionCellToken(params: {
    streamId: number;
    prevCellTxid: string;
    prevCellVout: number;
    prevCellTx: Transaction;
    newCellBytes: Uint8Array;
    semanticPath: string;
    contentHash: Uint8Array;
    prevStateSequence?: number;
  }): Promise<BuiltTx & { broadcastMs: number; buildMs: number }> {
    const funding = this.chainTip.pick(params.streamId, "transition");
    const t0 = Date.now();
    const built = await this.builder.buildTransition({
      funding,
      prevCellTxid: params.prevCellTxid,
      prevCellVout: params.prevCellVout,
      prevCellTx: params.prevCellTx,
      newCellBytes: params.newCellBytes,
      semanticPath: params.semanticPath,
      contentHash: params.contentHash,
      prevStateSequence: params.prevStateSequence,
    });
    const buildMs = Date.now() - t0;

    const totalIn =
      Number(
        params.prevCellTx.outputs[params.prevCellVout]!.satoshis,
      ) + funding.satoshis;
    await this.recordTx(built, "transition", totalIn);

    const { broadcastMs } = await this.broadcaster.broadcastTx(
      built.tx,
      "Transition",
    );

    this.recycleChange(params.streamId, built);
    this.totalBroadcast++;
    this.totalBuildMs += buildMs;
    return { ...built, broadcastMs, buildMs };
  }

  async anchorOpReturn(
    streamId: number,
    payload: string | Uint8Array,
  ): Promise<BuiltTx & { broadcastMs: number; buildMs: number }> {
    const funding = this.chainTip.pick(streamId, "opreturn");
    const t0 = Date.now();
    const built = await this.builder.buildOpReturn(funding, payload);
    const buildMs = Date.now() - t0;

    await this.recordTx(built, "opreturn", funding.satoshis);
    const { broadcastMs } = await this.broadcaster.broadcastTx(
      built.tx,
      "OP_RETURN",
    );

    this.recycleChange(streamId, built);
    this.totalBroadcast++;
    this.totalBuildMs += buildMs;
    return { ...built, broadcastMs, buildMs };
  }

  async sweepAll(toAddress: string): Promise<{
    totalSats: number;
    txids: string[];
    utxosSwept: number;
  }> {
    const all: FundingUtxo[] = [];
    for (let s = 0; s < this.streams; s++) {
      all.push(...this.chainTip.drain(s));
    }
    if (all.length === 0) {
      this.log("SWEEP", "No UTXOs to sweep");
      return { totalSats: 0, txids: [], utxosSwept: 0 };
    }

    const txids: string[] = [];
    let totalSats = 0;
    const BATCH_SIZE = 200;

    for (let i = 0; i < all.length; i += BATCH_SIZE) {
      const batch = all.slice(i, i + BATCH_SIZE);
      const built = await this.builder.buildSweep(batch, toAddress);
      if (!built) {
        this.log(
          "SWEEP",
          `Batch ${i / BATCH_SIZE}: ${batch.length} UTXOs below dust limit — skipped`,
        );
        continue;
      }
      const inputSats = batch.reduce((s, u) => s + u.satoshis, 0);
      await this.recordTx(built, "sweep", inputSats);
      await this.broadcaster.broadcastTx(built.tx, "SWEEP");

      txids.push(built.txid);
      totalSats += inputSats - built.fee;
      this.log(
        "SWEEP",
        `Batch ${Math.floor(i / BATCH_SIZE) + 1}: ${batch.length} → ${built.txid.slice(0, 16)}...`,
      );
    }

    return { totalSats, txids, utxosSwept: all.length };
  }

  // ── Lifecycle ────────────────────────────────────────

  /**
   * Drain all pending fire-and-forget broadcasts, persist BEEF, and
   * snapshot chain-tip state. Call before shutdown.
   */
  async flush(): Promise<void> {
    await this.broadcaster.flush();
    if (this.beefStore) this.beefStore.shutdown();
    this.chainTip.shutdown();
  }

  /** Aggregate stats across sub-services. */
  getStats(): ChainBroadcastStats {
    const b = this.broadcaster.stats();
    const balances = this.chainTip.balance();
    const avgBuild =
      this.totalBroadcast > 0 ? this.totalBuildMs / this.totalBroadcast : 0;
    const totalMs = this.totalBuildMs + b.totalBroadcastMs;
    const txPerSec =
      totalMs > 0 ? (this.totalBroadcast / totalMs) * 1000 : 0;
    return {
      totalBroadcast: this.totalBroadcast,
      avgBuildMs: Math.round(avgBuild),
      avgBroadcastMs: Math.round(b.avgBroadcastMs),
      txPerSec: parseFloat(txPerSec.toFixed(2)),
      errors: b.errors,
      utxoPoolSizes: balances.map((e) => e.utxoCount),
      totalRemainingSats: balances.reduce((s, e) => s + e.sats, 0),
    };
  }

  // ── Internals ────────────────────────────────────────

  /** Push the change output back into the pool it was drawn from. */
  private recycleChange(streamId: number, built: BuiltTx): void {
    if (!built.change) return;
    this.chainTip.returnUtxo(streamId, {
      txid: built.txid,
      vout: built.change.vout,
      satoshis: built.change.satoshis,
      sourceTx: built.tx,
    });
    if (this.beefStore) this.beefStore.mergeTransaction(built.tx);
  }

  /** Append an audit row (txid,type,sats,fee,bytes,ts) and log the header. */
  private async recordTx(
    built: BuiltTx,
    type: string,
    inputSats: number,
  ): Promise<void> {
    if (!this.auditLogPath) return;
    try {
      appendFileSync(
        this.auditLogPath,
        `${built.txid},${type},${inputSats},${built.fee},${built.estBytes},${Date.now()}\n`,
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.log("AUDIT", `append failed: ${msg}`);
    }
  }
}

// ── Helpers ──────────────────────────────────────────────

function resolvePrivateKey(config: ChainBroadcasterConfig): PrivateKey {
  if (config.privateKey) return config.privateKey;
  if (config.privateKeyWif) return PrivateKey.fromWif(config.privateKeyWif);
  if (config.privateKeyHex)
    return PrivateKey.fromHex(config.privateKeyHex);
  if (config.keySeed) {
    // SHA-256 of the seed → 32 bytes → private key.
    const { Hash } = require("@bsv/sdk") as typeof import("@bsv/sdk");
    const digest = Hash.sha256(
      Array.from(new TextEncoder().encode(config.keySeed)),
    ) as number[];
    const hex = digest
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return PrivateKey.fromHex(hex);
  }
  return PrivateKey.fromRandom();
}

```
