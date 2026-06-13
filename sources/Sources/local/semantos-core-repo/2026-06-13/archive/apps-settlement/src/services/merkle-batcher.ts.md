---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/services/merkle-batcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.714006+00:00
---

# archive/apps-settlement/src/services/merkle-batcher.ts

```ts
/**
 * MerkleBatcher — Computes Merkle roots over closed cell batches.
 *
 * Receives closed batches from BatchAggregator, extracts content hashes
 * as leaves, computes a Merkle root using the existing merkleEnvelope.ts
 * library, generates per-cell proofs, persists them, and emits the result
 * for the anchor pipeline.
 *
 * Cross-references:
 *   packages/cell-ops/src/merkleEnvelope.ts — computeMerkleRoot, generateMerkleProof, serializeMerkleEnvelope
 */

import {
  computeMerkleRoot,
  generateMerkleProof,
  serializeMerkleEnvelope,
  buildMerkleEnvelope,
} from '../../../cell-ops/src/merkleEnvelope';

import type { ProvenanceStore } from '../store/provenance-store';
import type { CellBatch, MerkleAnchor } from './border-router-types';
import { TypedBorderRouterEmitter } from './border-router-types';

// ── MerkleBatcher ────────────────────────────────────────────────────

export class MerkleBatcher extends TypedBorderRouterEmitter {
  private store: ProvenanceStore;

  // Stats
  private totalProcessed = 0;
  private totalLeaves = 0;

  constructor(store: ProvenanceStore) {
    super();
    this.store = store;
  }

  /**
   * Process a closed batch: compute Merkle root, generate proofs, persist.
   */
  processBatch(batch: CellBatch): MerkleAnchor {
    const leaves = batch.cells.map(c => c.contentHash);

    if (leaves.length === 0) {
      throw new Error('Cannot compute Merkle root for empty batch');
    }

    // Compute Merkle root using cell-ops library
    const merkleRoot = computeMerkleRoot(leaves);

    // Update batch in store
    this.store.setBatchMerkleRoot(batch.batchId, merkleRoot);

    // Generate and persist individual proofs for each cell
    for (let i = 0; i < leaves.length; i++) {
      const proof = generateMerkleProof(leaves, i);
      const envelope = buildMerkleEnvelope(leaves, [i]);
      const proofBlob = serializeMerkleEnvelope(envelope);
      this.store.addMerkleProof(batch.cells[i].cellId, batch.batchId, proofBlob, i);
    }

    const anchor: MerkleAnchor = {
      batchId: batch.batchId,
      merkleRoot,
      leafCount: leaves.length,
      txid: null,
      anchoredAt: null,
      status: 'pending',
    };

    // Record pending anchor in store
    this.store.recordAnchor(anchor);

    this.totalProcessed++;
    this.totalLeaves += leaves.length;

    this.emit('merkle:computed', anchor);

    console.log(
      `[MerkleBatcher] Batch ${batch.batchId.slice(0, 8)}: ` +
      `${leaves.length} leaves → root ${merkleRoot.toString('hex').slice(0, 16)}...`,
    );

    return anchor;
  }

  /**
   * Compute Merkle root from content hashes without persisting.
   * Static utility for external callers and tests.
   */
  static computeRoot(contentHashes: Buffer[]): Buffer {
    return computeMerkleRoot(contentHashes);
  }

  getStats() {
    return {
      totalProcessed: this.totalProcessed,
      totalLeaves: this.totalLeaves,
    };
  }
}

```
