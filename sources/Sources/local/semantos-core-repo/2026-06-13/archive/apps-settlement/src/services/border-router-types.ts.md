---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/services/border-router-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.713022+00:00
---

# archive/apps-settlement/src/services/border-router-types.ts

```ts
/**
 * Border Router Types — Shared types and configuration for the H3 settlement layer.
 *
 * The border router collects cells from poker bot multicast traffic, batches them,
 * computes Merkle roots, and anchors to BSV via OP_RETURN + PushDrop writes.
 *
 * Cross-references:
 *   packages/protocol-types/src/constants.ts       — MAGIC_1, Linearity, CELL_SIZE
 *   packages/cell-ops/src/merkleEnvelope.ts        — Merkle tree computation
 *   packages/poker-agent/src/direct-broadcast-engine.ts — BSV broadcast
 *   packages/protocol-types/src/overlay/shard-frame.ts  — BRC-12 frame format
 */

import { EventEmitter } from 'node:events';

// ── Configuration ────────────────────────────────────────────────────

export interface BorderRouterConfig {
  /** IPv6 multicast group address. Default: ff02::semantos:poker */
  multicastGroup: string;
  /** UDP port for multicast listener. Default: 6969 */
  multicastPort: number;
  /** Network interface for multicast binding. Default: eth0 */
  multicastInterface: string;
  /** Batch window size in milliseconds. Default: 30000 (30s) */
  batchIntervalMs: number;
  /** SQLite database path. Default: ./data/provenance.db */
  dbPath: string;
  /** REST API port. Default: 8080 */
  restPort: number;
  /** WebSocket port. Default: 8081 */
  wsPort: number;
  /** ARC broadcast endpoint URL */
  arcUrl: string;
  /** ARC API key (optional — GorillaPool doesn't need one) */
  arcApiKey: string;
  /** Funding transaction hex for anchor pipeline */
  fundingTxHex: string;
  /** Funding transaction output index */
  fundingVout: number;
  /** Number of parallel broadcast streams. Default: 1 */
  streamCount: number;
  /** BSV network. Default: testnet */
  bsvNetwork: 'testnet' | 'mainnet';
  /** Hot wallet private key (WIF format) */
  hotWalletPrivateKey: string;
  /** Dry-run mode: skip actual BSV broadcast. Default: false */
  dryRun: boolean;
  /** Deduplication window in milliseconds. Default: 60000 (60s) */
  dedupWindowMs: number;
  /** Log level. Default: info */
  logLevel: 'debug' | 'info' | 'warn' | 'error';
}

export function loadConfig(): BorderRouterConfig {
  return {
    multicastGroup: process.env.MULTICAST_GROUP ?? 'ff02::semantos:poker',
    multicastPort: parseInt(process.env.MULTICAST_PORT ?? '6969', 10),
    multicastInterface: process.env.MULTICAST_INTERFACE ?? 'eth0',
    batchIntervalMs: parseInt(process.env.ANCHOR_BATCH_INTERVAL_MS ?? '30000', 10),
    dbPath: process.env.SQLITE_DB_PATH ?? './data/provenance.db',
    restPort: parseInt(process.env.REST_PORT ?? '8080', 10),
    wsPort: parseInt(process.env.WS_PORT ?? '8081', 10),
    arcUrl: process.env.ARC_URL ?? 'https://arc.gorillapool.io',
    arcApiKey: process.env.ARC_API_KEY ?? '',
    fundingTxHex: process.env.FUNDING_TX_HEX ?? '',
    fundingVout: parseInt(process.env.FUNDING_VOUT ?? '0', 10),
    streamCount: parseInt(process.env.STREAM_COUNT ?? '1', 10),
    bsvNetwork: (process.env.BSV_NETWORK ?? 'testnet') as 'testnet' | 'mainnet',
    hotWalletPrivateKey: process.env.HOT_WALLET_PRIVKEY ?? '',
    dryRun: process.env.DRY_RUN === 'true',
    dedupWindowMs: parseInt(process.env.CELL_DEDUP_WINDOW_MS ?? '60000', 10),
    logLevel: (process.env.LOG_LEVEL ?? 'info') as BorderRouterConfig['logLevel'],
  };
}

// ── Cell Types ───────────────────────────────────────────────────────

export interface CollectedCell {
  /** Hex string of content hash (dedup key) */
  cellId: string;
  /** Raw cell bytes (1024-byte cell) */
  cellBytes: Uint8Array;
  /** Semantic path (e.g. game/poker/tableId/hand-N/state) */
  semanticPath: string;
  /** Content hash as Buffer (32 bytes, SHA256 of cellBytes) */
  contentHash: Buffer;
  /** Source IP address of the UDP datagram */
  sourceAddr: string;
  /** Epoch ms when cell was received */
  receivedAt: number;
  /** Linearity type from the cell header */
  linearity: number;
}

// ── Batch Types ──────────────────────────────────────────────────────

export interface CellBatch {
  /** UUID for this batch */
  batchId: string;
  /** Cells accumulated in this batch window */
  cells: CollectedCell[];
  /** Epoch ms when this batch window opened */
  openedAt: number;
  /** Epoch ms when this batch window closed */
  closedAt: number;
}

// ── Anchor Types ─────────────────────────────────────────────────────

export interface MerkleAnchor {
  /** UUID of the batch this anchor covers */
  batchId: string;
  /** 32-byte Merkle root of cell content hashes */
  merkleRoot: Buffer;
  /** Number of leaves in the Merkle tree */
  leafCount: number;
  /** BSV transaction ID (null if not yet anchored) */
  txid: string | null;
  /** Epoch ms when anchor was submitted (null if pending) */
  anchoredAt: number | null;
  /** Anchor status */
  status: 'pending' | 'submitted' | 'confirmed' | 'failed';
  /** Error message if failed */
  error?: string;
}

// ── Event Types ──────────────────────────────────────────────────────

export interface BorderRouterEvents {
  'cell:received': [cell: CollectedCell];
  'cell:duplicate': [cellId: string];
  'cell:invalid': [reason: string, sourceAddr: string];
  'batch:closed': [batch: CellBatch];
  'batch:empty': [];
  'merkle:computed': [anchor: MerkleAnchor];
  'anchor:submitted': [anchor: MerkleAnchor];
  'anchor:confirmed': [anchor: MerkleAnchor];
  'anchor:failed': [anchor: MerkleAnchor, error: Error];
  'stats:update': [stats: LiveStats];
}

export interface LiveStats {
  cellsPerSecond: number;
  totalCellsCollected: number;
  totalCellsAnchored: number;
  totalBatches: number;
  totalAnchors: number;
  currentBatchSize: number;
  currentBatchAgeMs: number;
  uniquePlayers: number;
  uptimeMs: number;
}

// ── Typed Event Emitter ──────────────────────────────────────────────

export class TypedBorderRouterEmitter extends EventEmitter {
  override emit<K extends keyof BorderRouterEvents>(
    event: K,
    ...args: BorderRouterEvents[K]
  ): boolean {
    return super.emit(event, ...args);
  }

  override on<K extends keyof BorderRouterEvents>(
    event: K,
    listener: (...args: BorderRouterEvents[K]) => void,
  ): this {
    return super.on(event, listener as (...args: unknown[]) => void);
  }

  override once<K extends keyof BorderRouterEvents>(
    event: K,
    listener: (...args: BorderRouterEvents[K]) => void,
  ): this {
    return super.once(event, listener as (...args: unknown[]) => void);
  }
}

```
