---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/chain-tip-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.520457+00:00
---

# packages/chain-broadcast/chain-broadcast/src/chain-tip-manager.ts

```ts
/**
 * ChainTipManager — UTXO pool coordinator for bulk on-chain anchoring.
 *
 * Owns:
 *   - `utxoPools: FundingUtxo[][]` — per-stream partitions of available
 *     funding UTXOs. Each parallel stream consumes from its own pool so
 *     two streams never sign two txs spending the same input.
 *   - Chain-tip snapshot persistence — if the runtime restarts without
 *     flushing this state, the next boot would re-ingest the original
 *     funding UTXO and double-spend it, rejecting every downstream tx
 *     with "Missing inputs". A timer persists dirty pools every
 *     `chainTipFlushMs` (default 5000) and `shutdown()` drains
 *     synchronously.
 *   - `waitForArcSeen(txid)` — polls ARC until it has indexed a parent
 *     tx. Critical between a pre-split broadcast and streaming children:
 *     if ARC hasn't ingested the parent, children land in
 *     `SEEN_IN_ORPHAN_MEMPOOL` permanently.
 *
 * Extracted from the hackathon `DirectBroadcastEngine` at
 * todriguez/hackathon-submission:src/agent/direct-broadcast-engine.ts@496ee8f
 * (methods `pickFundingUtxo`, `waitForArcSeen`, private chain-tip state).
 *
 * Separated from cell-tx-builder so consumers can swap the pool policy
 * (e.g. a SettlementBorderRouter coordinating multi-host fleet funding)
 * without touching the tx construction path.
 */

import type { Transaction } from "@bsv/sdk";
import {
  writeFileSync,
  readFileSync,
  existsSync,
  renameSync,
} from "node:fs";

export interface FundingUtxo {
  txid: string;
  vout: number;
  satoshis: number;
  /** Source transaction (needed for signing). */
  sourceTx: Transaction;
}

export interface ChainTipManagerConfig {
  /** Number of parallel streams; one pool per stream. */
  streams: number;
  /** Minimum useful sats = minFee + cellSatoshis; UTXOs below are dust. */
  minFee: number;
  cellSatoshis: number;
  /** ARC endpoint for `waitForArcSeen` polling. */
  arcUrl?: string;
  arcApiKey?: string;
  /**
   * Optional disk snapshot path. When provided a timer persists dirty
   * pools and `shutdown()` drains synchronously.
   */
  chainTipPath?: string;
  /** Flush interval for the chain-tip snapshot. Default 5000. */
  chainTipFlushMs?: number;
  /** Log verbosity. */
  verbose?: boolean;
  log?: (tag: string, msg: string) => void;
}

/** JSON-serialisable snapshot of a single UTXO — sourceTx replaced by hex. */
interface FundingUtxoSnapshot {
  txid: string;
  vout: number;
  satoshis: number;
  sourceTxHex: string;
}

export class ChainTipManager {
  private readonly config: Required<
    Omit<ChainTipManagerConfig, "arcApiKey" | "chainTipPath" | "log">
  > & {
    arcApiKey?: string;
    chainTipPath?: string;
    log: (tag: string, msg: string) => void;
  };

  private readonly utxoPools: FundingUtxo[][];
  private chainTipDirty = false;
  private chainTipTimer: ReturnType<typeof setInterval> | null = null;

  constructor(config: ChainTipManagerConfig) {
    this.config = {
      streams: config.streams,
      minFee: config.minFee,
      cellSatoshis: config.cellSatoshis,
      arcUrl: config.arcUrl ?? "https://arc.gorillapool.io",
      arcApiKey: config.arcApiKey,
      chainTipPath: config.chainTipPath,
      chainTipFlushMs: config.chainTipFlushMs ?? 5000,
      verbose: config.verbose ?? false,
      log:
        config.log ??
        ((tag, msg) => {
          if (config.verbose) console.log(`[CHAIN-TIP:${tag}] ${msg}`);
        }),
    };

    this.utxoPools = Array.from({ length: this.config.streams }, () => []);

    if (this.config.chainTipPath) {
      this.chainTipTimer = setInterval(() => {
        if (this.chainTipDirty) {
          try {
            this.persist();
          } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            this.config.log("PERSIST", `persist failed: ${msg}`);
          }
        }
      }, this.config.chainTipFlushMs);
    }
  }

  // ── Pool operations ────────────────────────────────────────

  /** Ingest a freshly-discovered or -split UTXO into the given stream's pool. */
  ingest(streamId: number, utxo: FundingUtxo): void {
    this.requireStream(streamId);
    this.utxoPools[streamId]!.push(utxo);
    this.chainTipDirty = true;
  }

  /** Ingest many UTXOs; partitions round-robin across streams if streamId omitted. */
  ingestMany(utxos: FundingUtxo[], streamId?: number): void {
    if (streamId !== undefined) {
      this.requireStream(streamId);
      for (const u of utxos) this.utxoPools[streamId]!.push(u);
    } else {
      for (let i = 0; i < utxos.length; i++) {
        this.utxoPools[i % this.config.streams]!.push(utxos[i]!);
      }
    }
    this.chainTipDirty = true;
  }

  /**
   * Pick a funding UTXO with enough sats to cover `minFee + cellSatoshis`.
   * Dust UTXOs that can't cover that floor are silently discarded.
   * Throws if the pool is exhausted.
   */
  pick(streamId: number, op: string): FundingUtxo {
    this.requireStream(streamId);
    const pool = this.utxoPools[streamId]!;
    const minUseful = this.config.minFee + this.config.cellSatoshis;

    while (pool.length > 0) {
      const utxo = pool.shift()!;
      if (utxo.satoshis >= minUseful) {
        this.chainTipDirty = true;
        return utxo;
      }
      // dust — discard silently but still mark dirty so we don't persist it
      this.chainTipDirty = true;
    }
    throw new Error(`Stream ${streamId} has no more funding UTXOs for ${op}`);
  }

  /** Return change back into the pool (cell-tx-builder calls this after build). */
  returnUtxo(streamId: number, utxo: FundingUtxo): void {
    this.requireStream(streamId);
    this.utxoPools[streamId]!.push(utxo);
    this.chainTipDirty = true;
  }

  /** Drain and return a stream's entire pool (e.g. for sweep). */
  drain(streamId: number): FundingUtxo[] {
    this.requireStream(streamId);
    const drained = this.utxoPools[streamId]!;
    this.utxoPools[streamId] = [];
    this.chainTipDirty = true;
    return drained;
  }

  poolSize(streamId: number): number {
    this.requireStream(streamId);
    return this.utxoPools[streamId]!.length;
  }

  totalPoolSize(): number {
    return this.utxoPools.reduce((acc, pool) => acc + pool.length, 0);
  }

  /**
   * Report per-stream balance. Useful for deciding when to request more
   * funding from a border router.
   */
  balance(): Array<{ streamId: number; utxoCount: number; sats: number }> {
    return this.utxoPools.map((pool, streamId) => ({
      streamId,
      utxoCount: pool.length,
      sats: pool.reduce((acc, u) => acc + u.satoshis, 0),
    }));
  }

  // ── ARC tip polling ─────────────────────────────────────────

  /**
   * Poll ARC until it has indexed `txid`. Returns true on success, false
   * on timeout (caller may proceed with downgraded guarantees).
   *
   * This is critical between pre-split (parent) and streaming (children):
   * if ARC hasn't ingested the parent, children land in
   * `SEEN_IN_ORPHAN_MEMPOOL` permanently.
   */
  async waitForArcSeen(txid: string, timeoutMs = 60_000): Promise<boolean> {
    const start = Date.now();
    const headers: Record<string, string> = {};
    if (this.config.arcApiKey)
      headers["Authorization"] = `Bearer ${this.config.arcApiKey}`;

    const goodStatuses = new Set([
      "SEEN_ON_NETWORK",
      "MINED",
      "ACCEPTED_BY_NETWORK",
      "ANNOUNCED_TO_NETWORK",
      "SEEN_IN_ORPHAN_MEMPOOL",
      "STORED",
      "CONFIRMED",
    ]);

    let attempt = 0;
    while (Date.now() - start < timeoutMs) {
      attempt++;
      try {
        const resp = await fetch(`${this.config.arcUrl}/v1/tx/${txid}`, {
          headers,
        });
        if (resp.ok) {
          const body = (await resp.json().catch(() => ({}))) as {
            txStatus?: string;
          };
          const status = body.txStatus ?? "";
          if (goodStatuses.has(status)) {
            this.config.log(
              "ARC-WAIT",
              `✓ ARC sees ${txid.slice(0, 16)}... (${status}) after ${attempt} polls / ${
                Date.now() - start
              }ms`,
            );
            return true;
          }
          this.config.log(
            "ARC-WAIT",
            `ARC status=${status || "(none)"} — polling again`,
          );
        }
      } catch {
        /* transient — retry */
      }
      await new Promise((r) => setTimeout(r, 2000));
    }
    this.config.log(
      "ARC-WAIT",
      `⚠ ARC did not index ${txid.slice(0, 16)}... within ${timeoutMs}ms`,
    );
    return false;
  }

  // ── Persistence ─────────────────────────────────────────────

  persist(): void {
    if (!this.config.chainTipPath) return;
    const snapshot: FundingUtxoSnapshot[][] = this.utxoPools.map((pool) =>
      pool.map((u) => ({
        txid: u.txid,
        vout: u.vout,
        satoshis: u.satoshis,
        sourceTxHex: u.sourceTx.toHex(),
      })),
    );
    const tmp = this.config.chainTipPath + ".tmp";
    writeFileSync(tmp, JSON.stringify(snapshot));
    renameSync(tmp, this.config.chainTipPath);
    this.chainTipDirty = false;
  }

  /**
   * Restore pools from disk. Takes a `Transaction.fromHex` resolver so we
   * don't hard-depend on `@bsv/sdk` in the manager (testability).
   */
  restore(
    txFromHex: (hex: string) => Transaction,
  ): { restored: number } {
    if (!this.config.chainTipPath) return { restored: 0 };
    if (!existsSync(this.config.chainTipPath)) return { restored: 0 };
    try {
      const raw = readFileSync(this.config.chainTipPath, "utf8");
      const snapshot = JSON.parse(raw) as FundingUtxoSnapshot[][];
      if (!Array.isArray(snapshot) || snapshot.length !== this.config.streams) {
        this.config.log(
          "RESTORE",
          "snapshot shape mismatch — ignoring stale state",
        );
        return { restored: 0 };
      }
      let restored = 0;
      for (let s = 0; s < this.config.streams; s++) {
        for (const snap of snapshot[s]!) {
          this.utxoPools[s]!.push({
            txid: snap.txid,
            vout: snap.vout,
            satoshis: snap.satoshis,
            sourceTx: txFromHex(snap.sourceTxHex),
          });
          restored++;
        }
      }
      return { restored };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.config.log("RESTORE", `failed: ${msg}`);
      return { restored: 0 };
    }
  }

  shutdown(): void {
    if (this.chainTipTimer) {
      clearInterval(this.chainTipTimer);
      this.chainTipTimer = null;
    }
    if (this.chainTipDirty && this.config.chainTipPath) {
      try {
        this.persist();
      } catch {
        /* shutdown best-effort */
      }
    }
  }

  // ── Internals ───────────────────────────────────────────────

  private requireStream(streamId: number): void {
    if (streamId < 0 || streamId >= this.config.streams) {
      throw new Error(
        `Invalid streamId ${streamId}; configured streams=${this.config.streams}`,
      );
    }
  }
}

```
