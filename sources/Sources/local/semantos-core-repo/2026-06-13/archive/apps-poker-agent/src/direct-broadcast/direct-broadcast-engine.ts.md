---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/direct-broadcast-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.783761+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/direct-broadcast-engine.ts

```ts
/**
 * Thin orchestrator over the direct-broadcast modules.
 *
 * Public API matches the legacy `DirectBroadcastEngine` exactly so
 * `game-loop.ts`, the arena CLI, and the payment-channel manager
 * keep compiling against `apps/poker-agent/src/direct-broadcast-
 * engine.ts` (which now re-exports from here).
 *
 * Heavy operations live in the helper modules:
 *   - `local-keypair-manager.ts` → key lifecycle
 *   - `utxo-pool-manager.ts`     → atom-backed pre-split pools
 *   - `funding-acquisition.ts`   → poll/ingest/pre-split flows
 *   - `celltoken-tx-builder.ts`  → create + transition CellToken
 *   - `op-return-builder.ts`     → 0-sat OP_RETURN + buildPokerCell
 *   - `tx-flow.ts`               → pick → build → broadcast → recycle
 *   - `arc-broadcaster.ts`       → ARC port wiring (single new ARC)
 *   - `tx-stats-collector.ts`    → event-bus + atom selector
 */

import type { Transaction } from '@bsv/sdk';

import { bindArcBroadcaster } from './arc-broadcaster';
import {
  createCellTokenTx,
  transitionCellTokenTx,
} from './celltoken-tx-builder';
import {
  buildFanOutTx,
  ingestFundingTx,
  partitionFanOut,
  pollWhatsOnChainFunding,
} from './funding-acquisition';
import {
  initLocalKeypair,
  requireLocalKeypair,
  resetLocalKeyAtoms,
} from './local-keypair-manager';
import {
  buildPokerCell,
  opReturnTx,
} from './op-return-builder';
import {
  attachStatsCollector,
  resetDirectBroadcastStats,
  selectStats,
  type StatsCollectorHandle,
} from './tx-stats-collector';
import { runTxFlow, broadcastWithFallback } from './tx-flow';
import {
  consumeUtxos as poolConsume,
  getPoolSizes,
  initPools,
  resetUtxoPoolAtoms,
  returnUtxos as poolReturn,
} from './utxo-pool-manager';
import {
  DEFAULT_ARC_URL,
  type BroadcastResult,
  type DirectBroadcastConfig,
  type FundingUtxo,
} from './types';

let engineSeq = 0;

export class DirectBroadcastEngine {
  private readonly engineId: string;
  private config: Required<DirectBroadcastConfig>;
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  private statsHandle: StatsCollectorHandle;
  private pendingBroadcasts: Promise<void>[] = [];

  constructor(config?: DirectBroadcastConfig) {
    this.engineId = `direct-broadcast-${++engineSeq}`;
    this.config = {
      arcUrl: config?.arcUrl ?? DEFAULT_ARC_URL,
      arcApiKey: config?.arcApiKey ?? '',
      streams: config?.streams ?? 4,
      cellSatoshis: config?.cellSatoshis ?? 1,
      splitSatoshis: config?.splitSatoshis ?? 500,
      verbose: config?.verbose ?? true,
      fireAndForget: config?.fireAndForget ?? false,
    };
    initLocalKeypair(this.engineId);
    initPools(this.engineId, this.config.streams);
    bindArcBroadcaster({ arcUrl: this.config.arcUrl });
    this.statsHandle = attachStatsCollector(this.engineId);
  }

  // ── Public API ─────────────────────────────────────────────

  getFundingAddress(): string { return requireLocalKeypair(this.engineId).fundingAddress; }
  getPubKeyHex(): string { return requireLocalKeypair(this.engineId).pubKeyHex; }
  getPrivateKeyWIF(): string { return requireLocalKeypair(this.engineId).wif; }
  consumeUtxos(streamId: number, count: number): FundingUtxo[] { return poolConsume(this.engineId, streamId, count); }
  returnUtxos(streamId: number, utxos: FundingUtxo[]): void { poolReturn(this.engineId, streamId, utxos); }

  async waitForFunding(timeoutMs: number = 300_000): Promise<FundingUtxo> {
    return pollWhatsOnChainFunding({
      address: this.getFundingAddress(),
      timeoutMs,
      log: this.bindLog(),
    });
  }

  async ingestFunding(txHex: string, vout: number): Promise<FundingUtxo> {
    const utxo = ingestFundingTx(txHex, vout);
    this.log('FUND', `Ingested: ${utxo.txid}:${utxo.vout} (${utxo.satoshis} sats)`);
    return utxo;
  }

  async preSplit(funding: FundingUtxo, count?: number): Promise<{ txid: string; splits: number }> {
    const pair = requireLocalKeypair(this.engineId);
    const { tx, splits } = await buildFanOutTx({
      engineId: this.engineId,
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      funding,
      streams: this.config.streams,
      splitSatoshis: this.config.splitSatoshis,
      count,
    });
    this.log('SPLIT', `Tx size: ${tx.toHex().length / 2} bytes; ${splits} splits`);
    await broadcastWithFallback(this.txFlowDeps('Split'), tx);
    const txid = tx.id('hex') as string;
    this.log('SPLIT', `✓ Fan-out tx: ${txid} (${splits} outputs)`);
    partitionFanOut(this.engineId, tx, splits, this.config.streams, this.config.splitSatoshis);
    this.log('SPLIT', `Partitioned: ${getPoolSizes(this.engineId).map((p, i) => `stream${i}=${p}`).join(', ')}`);
    return { txid, splits };
  }

  async createCellToken(
    streamId: number,
    cellBytes: Uint8Array,
    semanticPath: string,
    contentHash: Uint8Array,
  ): Promise<BroadcastResult> {
    const pair = requireLocalKeypair(this.engineId);
    return runTxFlow(this.txFlowDeps('CellToken', streamId), (funding) =>
      createCellTokenTx({
        privateKey: pair.privateKey,
        publicKey: pair.publicKey,
        funding,
        cellBytes,
        semanticPath,
        contentHash,
        cellSatoshis: this.config.cellSatoshis,
      }),
    );
  }

  async transitionCellToken(
    streamId: number,
    prevCellTxid: string,
    prevCellVout: number,
    prevCellTx: Transaction,
    newCellBytes: Uint8Array,
    semanticPath: string,
    contentHash: Uint8Array,
    prevStateSequence?: number,
  ): Promise<BroadcastResult> {
    const pair = requireLocalKeypair(this.engineId);
    return runTxFlow(this.txFlowDeps('Transition', streamId), (funding) =>
      transitionCellTokenTx({
        privateKey: pair.privateKey,
        publicKey: pair.publicKey,
        funding,
        prevCellTxid,
        prevCellVout,
        prevCellTx,
        newCellBytes,
        semanticPath,
        contentHash,
        cellSatoshis: this.config.cellSatoshis,
        prevStateSequence,
      }),
    );
  }

  async anchorOpReturn(streamId: number, payload: string): Promise<BroadcastResult> {
    const pair = requireLocalKeypair(this.engineId);
    return runTxFlow(this.txFlowDeps('OP_RETURN', streamId), (funding) =>
      opReturnTx({
        privateKey: pair.privateKey,
        publicKey: pair.publicKey,
        funding,
        payload,
      }),
    );
  }

  async buildPokerCell(
    gameId: string,
    handNumber: number,
    phase: string,
    data: Record<string, unknown>,
    version?: number,
  ) {
    return buildPokerCell(gameId, handNumber, phase, data, version);
  }

  getStats(): {
    totalBroadcast: number;
    avgBuildMs: number;
    avgBroadcastMs: number;
    txPerSec: number;
    errors: string[];
    utxoPoolSizes: number[];
  } {
    const stats = selectStats(this.engineId);
    return { ...stats, utxoPoolSizes: getPoolSizes(this.engineId) };
  }

  async flush(): Promise<{ settled: number; errors: number }> {
    const results = await Promise.allSettled(this.pendingBroadcasts);
    const errors = results.filter((r) => r.status === 'rejected').length;
    const settled = results.length;
    this.pendingBroadcasts = [];
    return { settled, errors };
  }

  static resetAll(): void {
    resetLocalKeyAtoms();
    resetUtxoPoolAtoms();
    resetDirectBroadcastStats();
  }

  // ── Internals ─────────────────────────────────────────────

  private txFlowDeps(label: string, streamId: number = 0) {
    return {
      engineId: this.engineId,
      streamId,
      label,
      fireAndForget: this.config.fireAndForget,
      trackPending: (p: Promise<void>) => this.pendingBroadcasts.push(p),
    };
  }

  private log(label: string, msg: string): void {
    if (this.config.verbose) {
      console.log(`\x1b[33m[DIRECT:${label}]\x1b[0m ${msg}`);
    }
  }

  private bindLog() {
    return (label: string, msg: string) => this.log(label, msg);
  }
}

```
