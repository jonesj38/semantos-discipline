---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/services/bsv-anchor-pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.714294+00:00
---

# archive/apps-settlement/src/services/bsv-anchor-pipeline.ts

```ts
/**
 * BsvAnchorPipeline — Anchors Merkle roots to BSV via OP_RETURN and PushDrop writes.
 *
 * Wraps DirectBroadcastEngine from poker-agent. Receives MerkleAnchor events
 * from MerkleBatcher, builds OP_RETURN transactions containing the Merkle root
 * with a "SEMANTOS" protocol prefix, broadcasts via ARC, and records the result.
 *
 * Also supports PushDrop cell token writes for richer on-chain provenance.
 *
 * Cross-references:
 *   packages/poker-agent/src/direct-broadcast-engine.ts — DirectBroadcastEngine
 *   packages/protocol-types/src/cell-token.ts           — CellToken PushDrop
 */

import { createHash } from 'node:crypto';

import type { ProvenanceStore } from '../store/provenance-store';
import type { MerkleAnchor, BorderRouterConfig } from './border-router-types';
import { TypedBorderRouterEmitter } from './border-router-types';

// Import via the workspace package boundary so the transitive
// imports in poker-agent's split modules don't trip rootDir.
import type {
  DirectBroadcastConfig,
  BroadcastResult,
} from '@semantos/poker-agent';
import { DirectBroadcastEngine } from '@semantos/poker-agent';

// ── Anchor Payload ───────────────────────────────────────────────────

interface AnchorPayload {
  protocol: 'semantos-provenance-v1';
  batchId: string;
  merkleRoot: string;
  leafCount: number;
  timestamp: number;
}

// ── BsvAnchorPipeline ────────────────────────────────────────────────

export class BsvAnchorPipeline extends TypedBorderRouterEmitter {
  private store: ProvenanceStore;
  private config: BorderRouterConfig;
  private engine: DirectBroadcastEngine | null = null;
  private initialized = false;

  // Stats
  private submitted = 0;
  private confirmed = 0;
  private failed = 0;

  constructor(store: ProvenanceStore, config: BorderRouterConfig) {
    super();
    this.store = store;
    this.config = config;
  }

  /**
   * Initialize the broadcast engine with funding.
   * Must be called before anchoring if not in dry-run mode.
   */
  async initialize(): Promise<void> {
    if (this.config.dryRun) {
      console.log('[BsvAnchorPipeline] Dry-run mode — skipping engine initialization');
      this.initialized = true;
      return;
    }

    const engineConfig: DirectBroadcastConfig = {
      arcUrl: this.config.arcUrl,
      arcApiKey: this.config.arcApiKey || undefined,
      streams: this.config.streamCount,
      fireAndForget: true, // Don't wait for ARC confirmation
      verbose: this.config.logLevel === 'debug',
    };

    this.engine = new DirectBroadcastEngine(engineConfig);

    // If funding tx is provided, ingest it
    if (this.config.fundingTxHex) {
      try {
        await this.engine.ingestFunding(
          this.config.fundingTxHex,
          this.config.fundingVout,
        );
        console.log('[BsvAnchorPipeline] Funding ingested, running pre-split...');
        await this.engine.preSplit();
        console.log('[BsvAnchorPipeline] Pre-split complete');
      } catch (err) {
        console.error('[BsvAnchorPipeline] Funding setup failed:', (err as Error).message);
        // Continue — engine may get funded later
      }
    } else {
      console.log(
        '[BsvAnchorPipeline] No funding tx — engine address:',
        this.engine.getFundingAddress(),
      );
    }

    this.initialized = true;
  }

  /**
   * Anchor a Merkle root to BSV via OP_RETURN.
   */
  async anchor(anchor: MerkleAnchor): Promise<MerkleAnchor> {
    if (!this.initialized) {
      throw new Error('BsvAnchorPipeline not initialized — call initialize() first');
    }

    const payload: AnchorPayload = {
      protocol: 'semantos-provenance-v1',
      batchId: anchor.batchId,
      merkleRoot: anchor.merkleRoot.toString('hex'),
      leafCount: anchor.leafCount,
      timestamp: Date.now(),
    };

    const payloadStr = JSON.stringify(payload);

    if (this.config.dryRun) {
      return this.dryRunAnchor(anchor, payloadStr);
    }

    return this.liveAnchor(anchor, payloadStr);
  }

  getStats() {
    const engineStats = this.engine?.getStats();
    return {
      submitted: this.submitted,
      confirmed: this.confirmed,
      failed: this.failed,
      engineStats,
    };
  }

  getEngineAddress(): string | null {
    return this.engine?.getFundingAddress() ?? null;
  }

  // ── Private ────────────────────────────────────────────────────────

  private async liveAnchor(anchor: MerkleAnchor, payloadStr: string): Promise<MerkleAnchor> {
    try {
      const result: BroadcastResult = await this.engine!.anchorOpReturn(0, payloadStr);

      const updated: MerkleAnchor = {
        ...anchor,
        txid: result.txid,
        anchoredAt: Date.now(),
        status: 'submitted',
      };

      this.store.updateAnchorStatus(anchor.batchId, 'submitted', result.txid);
      this.store.setBatchAnchored(anchor.batchId);

      this.submitted++;
      this.emit('anchor:submitted', updated);

      console.log(
        `[BsvAnchorPipeline] Anchored batch ${anchor.batchId.slice(0, 8)} → txid ${result.txid.slice(0, 16)}... ` +
        `(build: ${result.buildMs}ms, broadcast: ${result.broadcastMs}ms)`,
      );

      return updated;
    } catch (err) {
      const error = err as Error;
      const updated: MerkleAnchor = {
        ...anchor,
        status: 'failed',
        error: error.message,
      };

      this.store.updateAnchorStatus(anchor.batchId, 'failed', undefined, error.message);
      this.store.setBatchFailed(anchor.batchId);

      this.failed++;
      this.emit('anchor:failed', updated, error);

      console.error(
        `[BsvAnchorPipeline] Anchor failed for batch ${anchor.batchId.slice(0, 8)}:`,
        error.message,
      );

      return updated;
    }
  }

  private dryRunAnchor(anchor: MerkleAnchor, payloadStr: string): MerkleAnchor {
    // Generate deterministic fake txid from Merkle root
    const fakeTxid = createHash('sha256')
      .update(anchor.merkleRoot)
      .update(anchor.batchId)
      .digest('hex');

    const updated: MerkleAnchor = {
      ...anchor,
      txid: fakeTxid,
      anchoredAt: Date.now(),
      status: 'submitted',
    };

    this.store.recordAnchor(updated, payloadStr);
    this.store.updateAnchorStatus(anchor.batchId, 'submitted', fakeTxid);
    this.store.setBatchAnchored(anchor.batchId);

    this.submitted++;
    this.emit('anchor:submitted', updated);

    console.log(
      `[BsvAnchorPipeline] DRY-RUN anchored batch ${anchor.batchId.slice(0, 8)} → fake txid ${fakeTxid.slice(0, 16)}...`,
    );

    return updated;
  }
}

```
