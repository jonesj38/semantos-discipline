---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/mapi-broadcaster.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.519492+00:00
---

# packages/chain-broadcast/chain-broadcast/src/mapi-broadcaster.ts

```ts
/**
 * MapiBroadcaster — submit signed BSV transactions to a miner.
 *
 * Two modes:
 *   - `arc`  (default) — broadcast via `@bsv/sdk`'s ARC broadcaster.
 *                        Supports fire-and-forget batching to
 *                        `${arcUrl}/v1/txs` (up to `batchSize` txs per
 *                        POST) with WoC fallback on batch failure.
 *   - `mapi`           — direct POST to a miner's MAPI endpoint
 *                        (GorillaPool default). 3-retry 429 handling.
 *
 * ARC instance is INJECTED via config — the hackathon engine hard-coded
 * `new ARC(url, key)` in its constructor, which made it untestable.
 * Pass a real ARC for production, a stub for unit tests.
 *
 * Owns:
 *   - batch queue + flush timer (fire-and-forget mode)
 *   - pending fire-and-forget promises (drained in `flush()`)
 *   - per-instance stats (broadcast count, cumulative ms)
 *   - error log for the current session
 *
 * Extracted from the hackathon `DirectBroadcastEngine` at
 * todriguez/hackathon-submission:src/agent/direct-broadcast-engine.ts@496ee8f
 * (methods `broadcastTx`, `broadcastViaMapi`, `flushBatch`, `wocBroadcast`).
 */

import { ARC, type Transaction } from "@bsv/sdk";

export type BroadcastMode = "arc" | "mapi";

export interface MapiBroadcasterConfig {
  /** "arc" (default) or "mapi" direct miner endpoint. */
  mode?: BroadcastMode;
  /** ARC endpoint. Default: https://arc.gorillapool.io */
  arcUrl?: string;
  /** ARC bearer token. Optional — GorillaPool doesn't require one. */
  arcApiKey?: string;
  /** MAPI POST URL. Default: https://mapi.gorillapool.io/mapi/tx */
  mapiUrl?: string;
  /**
   * Fire-and-forget mode: don't await broadcast confirmation. Accumulates
   * txs in a batch and posts them to `${arcUrl}/v1/txs`. Default: false.
   */
  fireAndForget?: boolean;
  /** Max txs per batch POST. Default: 20. */
  batchSize?: number;
  /** Max wait before flushing a partial batch. Default: 100ms. */
  batchFlushMs?: number;
  /** Log verbosity. */
  verbose?: boolean;
  log?: (tag: string, msg: string) => void;
  /**
   * Pre-built ARC instance. If omitted, one is constructed from
   * `arcUrl` + `arcApiKey`. Tests pass a stub.
   */
  arc?: ARC;
  /**
   * Injectable `fetch` for unit tests. Defaults to the global `fetch`.
   */
  fetchImpl?: typeof fetch;
  /**
   * Enables the dual-broadcast WoC fallback after each batch.
   * When false, batches hit ARC only. Default: true (production parity).
   */
  enableWocFallback?: boolean;
}

export interface BroadcastStats {
  totalBroadcast: number;
  totalBroadcastMs: number;
  avgBroadcastMs: number;
  errors: readonly string[];
  batchQueueLen: number;
}

const DEFAULT_ARC_URL = "https://arc.gorillapool.io";
const DEFAULT_MAPI_URL = "https://mapi.gorillapool.io/mapi/tx";

export class MapiBroadcaster {
  private readonly mode: BroadcastMode;
  private readonly arcUrl: string;
  private readonly arcApiKey?: string;
  private readonly mapiUrl: string;
  private readonly fireAndForget: boolean;
  private readonly batchSize: number;
  private readonly batchFlushMs: number;
  private readonly enableWocFallback: boolean;
  private readonly log: (tag: string, msg: string) => void;
  private readonly fetchImpl: typeof fetch;

  private readonly arc: ARC;
  private readonly batchQueue: Transaction[] = [];
  private batchFlushTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly pendingBroadcasts: Promise<void>[] = [];

  private totalBroadcast = 0;
  private totalBroadcastMs = 0;
  private readonly errorLog: string[] = [];

  constructor(config: MapiBroadcasterConfig = {}) {
    this.mode = config.mode ?? "arc";
    this.arcUrl = config.arcUrl ?? DEFAULT_ARC_URL;
    this.arcApiKey = config.arcApiKey;
    this.mapiUrl = config.mapiUrl ?? DEFAULT_MAPI_URL;
    this.fireAndForget = config.fireAndForget ?? false;
    this.batchSize = config.batchSize ?? 20;
    this.batchFlushMs = config.batchFlushMs ?? 100;
    this.enableWocFallback = config.enableWocFallback ?? true;
    this.fetchImpl = config.fetchImpl ?? fetch;
    this.log =
      config.log ??
      ((tag, msg) => {
        if (config.verbose) console.log(`[MAPI:${tag}] ${msg}`);
      });

    this.arc =
      config.arc ??
      (this.arcApiKey
        ? new ARC(this.arcUrl, this.arcApiKey)
        : new ARC(this.arcUrl));
  }

  // ── Public API ─────────────────────────────────────────────

  /**
   * Broadcast a signed tx. In fire-and-forget mode it queues for the next
   * batch flush and resolves immediately (broadcastMs is then an estimate).
   */
  async broadcastTx(
    tx: Transaction,
    label: string,
  ): Promise<{ broadcastMs: number }> {
    if (this.mode === "mapi") {
      return this.broadcastViaMapi(tx, label);
    }

    if (this.fireAndForget) {
      this.batchQueue.push(tx);
      this.totalBroadcast++;

      if (this.batchQueue.length >= this.batchSize) {
        this.flushBatch();
      } else if (!this.batchFlushTimer) {
        this.batchFlushTimer = setTimeout(
          () => this.flushBatch(),
          this.batchFlushMs,
        );
      }
      return { broadcastMs: 0 };
    }

    const t1 = Date.now();
    const result = await tx.broadcast(this.arc);
    const broadcastMs = Date.now() - t1;

    if (isArcError(result)) {
      const err = `${label} broadcast failed: code=${result.code} desc=${result.description} more=${
        result.more ? JSON.stringify(result.more) : ""
      }`;
      this.errorLog.push(err);
      throw new Error(err);
    }

    this.totalBroadcast++;
    this.totalBroadcastMs += broadcastMs;
    return { broadcastMs };
  }

  /**
   * Drain the batch queue and wait for all fire-and-forget promises to
   * settle. Call at graceful shutdown.
   */
  async flush(): Promise<void> {
    if (this.batchQueue.length > 0) this.flushBatch();
    if (this.batchFlushTimer) {
      clearTimeout(this.batchFlushTimer);
      this.batchFlushTimer = null;
    }
    await Promise.allSettled(this.pendingBroadcasts);
  }

  stats(): BroadcastStats {
    return {
      totalBroadcast: this.totalBroadcast,
      totalBroadcastMs: this.totalBroadcastMs,
      avgBroadcastMs:
        this.totalBroadcast > 0
          ? this.totalBroadcastMs / this.totalBroadcast
          : 0,
      errors: Object.freeze([...this.errorLog]),
      batchQueueLen: this.batchQueue.length,
    };
  }

  /** Clear the in-memory error log (keeps counters). */
  clearErrors(): void {
    this.errorLog.length = 0;
  }

  // ── Internals ──────────────────────────────────────────────

  /**
   * Direct POST to the miner's MAPI. Unlike ARC (announce + hope), MAPI
   * puts txs straight into the mining node's mempool. 3-retry 429
   * handling; non-429 errors fail fast.
   */
  private async broadcastViaMapi(
    tx: Transaction,
    label: string,
  ): Promise<{ broadcastMs: number }> {
    const txHex = tx.toHex();
    const t1 = Date.now();

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const resp = await this.fetchImpl(this.mapiUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ rawtx: txHex }),
        });

        if (resp.status === 429) {
          await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
          continue;
        }

        const raw = await resp.text();
        const broadcastMs = Date.now() - t1;

        try {
          const outer = JSON.parse(raw) as { payload?: string };
          const inner = JSON.parse(outer.payload ?? "{}") as {
            returnResult?: string;
            resultDescription?: string;
          };
          const ok =
            inner.returnResult === "success" ||
            (inner.resultDescription ?? "").includes("already known");
          if (!ok) {
            const err = `${label} MAPI rejected: ${inner.resultDescription ?? "(no description)"}`;
            this.errorLog.push(err);
            throw new Error(err);
          }
        } catch (parseErr: unknown) {
          const msg = parseErr instanceof Error ? parseErr.message : String(parseErr);
          if (msg.includes("MAPI rejected")) throw parseErr;
          if (!resp.ok) {
            const err = `${label} MAPI HTTP ${resp.status}: ${raw.slice(0, 200)}`;
            this.errorLog.push(err);
            throw new Error(err);
          }
        }

        this.totalBroadcast++;
        this.totalBroadcastMs += broadcastMs;
        return { broadcastMs };
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes("MAPI rejected") || msg.includes("MAPI HTTP"))
          throw err;
        if (attempt < 2) {
          await new Promise((r) => setTimeout(r, 200));
          continue;
        }
        const errMsg = `${label} MAPI error: ${msg}`;
        this.errorLog.push(errMsg);
        throw new Error(errMsg);
      }
    }
    throw new Error(`${label} MAPI: 429 after 3 retries`);
  }

  /**
   * Batch-broadcast via ARC's `/v1/txs` bulk endpoint using direct fetch
   * (bypasses @bsv/sdk's httpClient, which silently fails under some
   * runtimes). Per-tx errors reported in `errorLog` but don't throw — the
   * batch is fire-and-forget by construction.
   */
  private flushBatch(): void {
    if (this.batchFlushTimer) {
      clearTimeout(this.batchFlushTimer);
      this.batchFlushTimer = null;
    }
    if (this.batchQueue.length === 0) return;

    const batch = this.batchQueue.splice(0, this.batchSize);
    const batchNum = Math.floor(this.totalBroadcast / this.batchSize);

    const p = (async () => {
      const t0 = Date.now();
      try {
        const rawTxs = batch.map((tx) => {
          try {
            return { rawTx: tx.toHexEF() };
          } catch {
            return { rawTx: tx.toHex() };
          }
        });

        const headers: Record<string, string> = {
          "Content-Type": "application/json",
        };
        if (this.arcApiKey)
          headers["Authorization"] = `Bearer ${this.arcApiKey}`;

        const resp = await this.fetchImpl(`${this.arcUrl}/v1/txs`, {
          method: "POST",
          headers,
          body: JSON.stringify(rawTxs),
        });

        const elapsed = Date.now() - t0;
        this.totalBroadcastMs += elapsed;

        if (!resp.ok) {
          const body = await resp.text().catch(() => "");
          throw new Error(
            `ARC batch HTTP ${resp.status}: ${body.slice(0, 200)}`,
          );
        }

        const results = (await resp.json()) as unknown;
        if (!Array.isArray(results)) {
          throw new Error(
            `ARC batch returned non-array: ${JSON.stringify(results).slice(0, 200)}`,
          );
        }

        let ok = 0;
        let fail = 0;
        for (const r of results as Array<Record<string, unknown>>) {
          const isError =
            r?.status === "error" ||
            r?.txStatus === "REJECTED" ||
            (typeof r?.status === "number" && (r.status as number) >= 400);
          if (isError) {
            fail++;
            this.errorLog.push(
              `Batch tx failed: ${
                (r?.title as string | undefined) ??
                (r?.detail as string | undefined) ??
                (r?.description as string | undefined) ??
                JSON.stringify(r).slice(0, 150)
              }`,
            );
          } else {
            ok++;
          }
        }
        if (batchNum <= 2 || fail > 0) {
          this.log(
            "BATCH",
            `Batch #${batchNum}: ${ok} ok, ${fail} failed in ${elapsed}ms`,
          );
        }

        // Dual-broadcast: one WoC probe per batch (rate-limit-safe).
        if (this.enableWocFallback && batch.length > 0) {
          this.wocBroadcast(batch[0]!.toHex()).catch(() => {});
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        this.errorLog.push(`Batch broadcast error: ${msg}`);
        this.log("BATCH", `Batch #${batchNum} error: ${msg} — falling back to WoC`);
        if (this.enableWocFallback && batch.length > 0) {
          this.wocBroadcast(batch[0]!.toHex()).catch(() => {});
        }
      }
    })();

    this.pendingBroadcasts.push(p);
  }

  /**
   * Raw tx hex → WhatsOnChain's node endpoint as a backup. ARC's
   * `ANNOUNCED_TO_NETWORK` doesn't guarantee propagation; WoC goes
   * direct to nodes.
   */
  async wocBroadcast(txHex: string): Promise<boolean> {
    try {
      const resp = await this.fetchImpl(
        "https://api.whatsonchain.com/v1/bsv/main/tx/raw",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ txhex: txHex }),
        },
      );
      if (!resp.ok) {
        const body = await resp.text();
        if (
          body.includes("already-known") ||
          body.includes("already in the mempool")
        ) {
          this.log("WOC", "Tx already on network — treating as success");
          return true;
        }
        this.log(
          "WOC",
          `Backup broadcast returned ${resp.status}: ${body.slice(0, 200)}`,
        );
        return false;
      }
      return true;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.log("WOC", `Backup broadcast failed: ${msg}`);
      return false;
    }
  }
}

// ── helpers ───────────────────────────────────────────────

function isArcError(
  result: unknown,
): result is { status: "error"; code: string; description: string; more?: unknown } {
  return (
    typeof result === "object" &&
    result !== null &&
    (result as { status?: string }).status === "error"
  );
}

```
