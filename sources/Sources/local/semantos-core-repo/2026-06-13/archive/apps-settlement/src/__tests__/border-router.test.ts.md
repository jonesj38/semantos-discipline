---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/__tests__/border-router.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.714631+00:00
---

# archive/apps-settlement/src/__tests__/border-router.test.ts

```ts
/**
 * Phase H3 Gate Tests T1–T12 — Border Router Aggregator
 *
 * Validates the complete settlement layer pipeline:
 *   T1:  ProvenanceStore — insert and retrieve cells
 *   T2:  ProvenanceStore — deduplication detection
 *   T3:  ProvenanceStore — batch lifecycle (create → close → query)
 *   T4:  CellCollector — validates and accepts valid cell
 *   T5:  CellCollector — rejects invalid magic bytes
 *   T6:  BatchAggregator — closes batch after timer fires
 *   T7:  BatchAggregator — skips empty batches
 *   T8:  MerkleBatcher — computes correct Merkle root
 *   T9:  MerkleBatcher — individual proofs verify against root
 *   T10: BsvAnchorPipeline — dry-run produces valid anchor record
 *   T11: RestServer — GET /health returns 200
 *   T12: End-to-end — cell → store → batch → Merkle → anchor
 *
 * Cross-references:
 *   docs/prd/hackathon/PHASE-H3-BORDER-ROUTER-AGGREGATOR.md — PRD gate tests
 *   packages/cell-ops/src/merkleEnvelope.ts — Merkle verification
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { createHash } from 'node:crypto';

import { ProvenanceStore } from '../store/provenance-store';
import { CellCollector } from '../services/cell-collector';
import { BatchAggregator } from '../services/batch-aggregator';
import { MerkleBatcher } from '../services/merkle-batcher';
import { BsvAnchorPipeline } from '../services/bsv-anchor-pipeline';
import { RestServer } from '../api/rest-server';
import { BorderRouter } from '../border-router';
import {
  loadConfig,
  type CollectedCell,
  type CellBatch,
  type BorderRouterConfig,
} from '../services/border-router-types';

import {
  computeMerkleRoot,
  verifyMerkleProof,
  generateMerkleProof,
  deserializeMerkleEnvelope,
} from '../../../cell-ops/src/merkleEnvelope';

import {
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
  CELL_SIZE,
  HEADER_SIZE,
  Linearity,
  HeaderOffsets,
} from '../../../protocol-types/src/constants';

// ── Test Helpers ─────────────────────────────────────────────────────

function makeTestConfig(overrides?: Partial<BorderRouterConfig>): BorderRouterConfig {
  return {
    ...loadConfig(),
    dbPath: ':memory:',
    dryRun: true,
    batchIntervalMs: 500, // Fast for testing
    multicastGroup: 'ff02::1',
    multicastPort: 0, // Don't actually bind
    multicastInterface: 'lo0',
    restPort: 0,
    wsPort: 0,
    logLevel: 'error',
    ...overrides,
  };
}

/**
 * Build a valid 1024-byte cell with correct magic bytes and linearity.
 */
function buildValidCell(linearity: number = Linearity.LINEAR): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const dv = new DataView(cell.buffer);

  // Write magic bytes (4 x uint32 LE = 16 bytes)
  dv.setUint32(HeaderOffsets.magic, MAGIC_1, true);
  dv.setUint32(HeaderOffsets.magic + 4, MAGIC_2, true);
  dv.setUint32(HeaderOffsets.magic + 8, MAGIC_3, true);
  dv.setUint32(HeaderOffsets.magic + 12, MAGIC_4, true);

  // Write linearity
  dv.setUint32(HeaderOffsets.linearity, linearity, true);

  // Write version
  dv.setUint32(HeaderOffsets.version, 1, true);

  // Write timestamp
  const now = BigInt(Date.now());
  dv.setBigUint64(HeaderOffsets.timestamp, now, true);

  // Fill payload with random-ish data for uniqueness
  const payload = cell.subarray(HEADER_SIZE);
  for (let i = 0; i < payload.length; i++) {
    payload[i] = Math.floor(Math.random() * 256);
  }

  return cell;
}

function cellContentHash(cellBytes: Uint8Array): Buffer {
  return createHash('sha256').update(cellBytes).digest();
}

function makeCollectedCell(cellBytes?: Uint8Array): CollectedCell {
  const bytes = cellBytes ?? buildValidCell();
  const hash = cellContentHash(bytes);
  return {
    cellId: hash.toString('hex'),
    cellBytes: bytes,
    semanticPath: `test/cell/${hash.toString('hex').slice(0, 8)}`,
    contentHash: hash,
    sourceAddr: '::1',
    receivedAt: Date.now(),
    linearity: Linearity.LINEAR,
  };
}

// ── T1: ProvenanceStore — insert and retrieve ────────────────────────

describe('T1: ProvenanceStore insert and retrieve', () => {
  let store: ProvenanceStore;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
  });

  afterEach(() => {
    store.close();
  });

  test('inserts a cell and retrieves it by cellId', () => {
    const cell = makeCollectedCell();
    store.insertCell(cell);

    const retrieved = store.getCell(cell.cellId);
    expect(retrieved).not.toBeNull();
    expect(retrieved!.cellId).toBe(cell.cellId);
    expect(retrieved!.semanticPath).toBe(cell.semanticPath);
    expect(retrieved!.sourceAddr).toBe(cell.sourceAddr);
    expect(retrieved!.linearity).toBe(cell.linearity);
    expect(retrieved!.contentHash.toString('hex')).toBe(cell.contentHash.toString('hex'));
  });

  test('returns null for non-existent cell', () => {
    const retrieved = store.getCell('nonexistent');
    expect(retrieved).toBeNull();
  });

  test('getRecentCells returns cells in descending order', () => {
    for (let i = 0; i < 5; i++) {
      const cell = makeCollectedCell();
      store.insertCell(cell);
    }
    const cells = store.getRecentCells(10);
    expect(cells.length).toBe(5);
    // Most recent first
    for (let i = 1; i < cells.length; i++) {
      expect(cells[i - 1].receivedAt).toBeGreaterThanOrEqual(cells[i].receivedAt);
    }
  });
});

// ── T2: ProvenanceStore — dedup detection ────────────────────────────

describe('T2: ProvenanceStore deduplication', () => {
  let store: ProvenanceStore;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
  });

  afterEach(() => {
    store.close();
  });

  test('isDuplicate returns false for new content hash', () => {
    expect(store.isDuplicate('abc123')).toBe(false);
  });

  test('isDuplicate returns true after markSeen', () => {
    store.markSeen('abc123');
    expect(store.isDuplicate('abc123')).toBe(true);
  });

  test('pruneDedup removes entries older than window', async () => {
    store.markSeen('old_hash');
    // Wait a tick so first_seen_at is in the past
    await new Promise(r => setTimeout(r, 10));
    const pruned = store.pruneDedup(1); // 1ms window = prune everything older than 1ms
    expect(pruned).toBeGreaterThanOrEqual(1);
    expect(store.isDuplicate('old_hash')).toBe(false);
  });
});

// ── T3: ProvenanceStore — batch lifecycle ────────────────────────────

describe('T3: ProvenanceStore batch lifecycle', () => {
  let store: ProvenanceStore;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
  });

  afterEach(() => {
    store.close();
  });

  test('create, close, and retrieve batch', () => {
    const batchId = 'test-batch-001';
    const openedAt = Date.now();
    const closedAt = openedAt + 30000;

    store.createBatch(batchId, openedAt);
    store.closeBatch(batchId, closedAt, 5);

    const batch = store.getBatch(batchId);
    expect(batch).not.toBeNull();
    expect(batch!.batchId).toBe(batchId);
    expect(batch!.openedAt).toBe(openedAt);
    expect(batch!.closedAt).toBe(closedAt);
  });

  test('cells assigned to batch are retrievable', () => {
    const batchId = 'test-batch-002';
    store.createBatch(batchId, Date.now());

    const cells = [makeCollectedCell(), makeCollectedCell(), makeCollectedCell()];
    for (const cell of cells) {
      store.insertCell(cell, batchId);
    }

    const retrieved = store.getCellsByBatch(batchId);
    expect(retrieved.length).toBe(3);
  });

  test('getRecentBatches returns batches in descending order', () => {
    for (let i = 0; i < 3; i++) {
      store.createBatch(`batch-${i}`, Date.now() + i);
      store.closeBatch(`batch-${i}`, Date.now() + i + 1000, 1);
    }
    const batches = store.getRecentBatches(10);
    expect(batches.length).toBe(3);
  });
});

// ── T4: CellCollector — accepts valid cell ───────────────────────────

describe('T4: CellCollector validates and accepts valid cell', () => {
  let store: ProvenanceStore;
  let collector: CellCollector;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
    collector = new CellCollector(store, makeTestConfig());
  });

  afterEach(() => {
    store.close();
  });

  test('injectCell accepts a valid cell with correct magic and linearity', () => {
    const cellBytes = buildValidCell(Linearity.LINEAR);
    const result = collector.injectCell(cellBytes, '::1');

    expect(result).not.toBeNull();
    expect(result!.cellId).toBeDefined();
    expect(result!.cellBytes.length).toBe(CELL_SIZE);
    expect(result!.linearity).toBe(Linearity.LINEAR);

    const stats = collector.getStats();
    expect(stats.collected).toBe(1);
    expect(stats.invalid).toBe(0);
  });

  test('injectCell accepts cells with AFFINE linearity', () => {
    const cellBytes = buildValidCell(Linearity.AFFINE);
    const result = collector.injectCell(cellBytes, '::1');
    expect(result).not.toBeNull();
    expect(result!.linearity).toBe(Linearity.AFFINE);
  });

  test('injectCell accepts cells with RELEVANT linearity', () => {
    const cellBytes = buildValidCell(Linearity.RELEVANT);
    const result = collector.injectCell(cellBytes, '::1');
    expect(result).not.toBeNull();
    expect(result!.linearity).toBe(Linearity.RELEVANT);
  });

  test('injectCell emits cell:received event', (done) => {
    collector.on('cell:received', (cell) => {
      expect(cell.cellId).toBeDefined();
      done();
    });
    const cellBytes = buildValidCell();
    collector.injectCell(cellBytes, '::1');
  });
});

// ── T5: CellCollector — rejects invalid cells ───────────────────────

describe('T5: CellCollector rejects invalid cells', () => {
  let store: ProvenanceStore;
  let collector: CellCollector;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
    collector = new CellCollector(store, makeTestConfig());
  });

  afterEach(() => {
    store.close();
  });

  test('rejects cell with wrong magic bytes', () => {
    const cellBytes = new Uint8Array(CELL_SIZE);
    const dv = new DataView(cellBytes.buffer);
    dv.setUint32(0, 0xBADF00D, true); // Wrong magic

    const result = collector.injectCell(cellBytes, '::1');
    expect(result).toBeNull();

    const stats = collector.getStats();
    expect(stats.invalid).toBe(1);
  });

  test('rejects cell with invalid linearity', () => {
    const cellBytes = buildValidCell();
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    dv.setUint32(HeaderOffsets.linearity, 99, true); // Invalid linearity

    const result = collector.injectCell(cellBytes, '::1');
    expect(result).toBeNull();

    const stats = collector.getStats();
    expect(stats.invalid).toBe(1);
  });

  test('rejects cell that is too small', () => {
    const cellBytes = new Uint8Array(100); // Too small
    const result = collector.injectCell(cellBytes, '::1');
    expect(result).toBeNull();
  });

  test('deduplicates same cell injected twice', () => {
    const cellBytes = buildValidCell();
    const result1 = collector.injectCell(cellBytes, '::1');
    const result2 = collector.injectCell(cellBytes, '::1');

    expect(result1).not.toBeNull();
    expect(result2).toBeNull(); // Deduplicated

    const stats = collector.getStats();
    expect(stats.collected).toBe(1);
    expect(stats.deduplicated).toBe(1);
  });

  test('static validate rejects bad magic', () => {
    const cellBytes = new Uint8Array(CELL_SIZE);
    const result = CellCollector.validate(cellBytes);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('Invalid magic');
  });

  test('static validate accepts good cell', () => {
    const cellBytes = buildValidCell();
    const result = CellCollector.validate(cellBytes);
    expect(result.valid).toBe(true);
  });
});

// ── T6: BatchAggregator — closes batch after timer ───────────────────

describe('T6: BatchAggregator closes batch after timer', () => {
  let store: ProvenanceStore;
  let aggregator: BatchAggregator;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
    aggregator = new BatchAggregator(store, makeTestConfig({ batchIntervalMs: 200 }));
  });

  afterEach(() => {
    aggregator.stop();
    store.close();
  });

  test('emits batch:closed after batch window elapses', async () => {
    aggregator.start();

    const cell = makeCollectedCell();
    store.insertCell(cell);
    aggregator.addCell(cell);

    const batch = await new Promise<CellBatch>((resolve) => {
      aggregator.on('batch:closed', resolve);
    });

    expect(batch.cells.length).toBe(1);
    expect(batch.batchId).toBeDefined();
    expect(batch.closedAt).toBeGreaterThan(batch.openedAt);
  });

  test('accumulates multiple cells in one batch', async () => {
    aggregator.start();

    for (let i = 0; i < 5; i++) {
      const cell = makeCollectedCell();
      store.insertCell(cell);
      aggregator.addCell(cell);
    }

    const batch = await new Promise<CellBatch>((resolve) => {
      aggregator.on('batch:closed', resolve);
    });

    expect(batch.cells.length).toBe(5);
  });
});

// ── T7: BatchAggregator — skips empty batches ────────────────────────

describe('T7: BatchAggregator skips empty batches', () => {
  test('emits batch:empty instead of batch:closed for empty window', async () => {
    const store = new ProvenanceStore(':memory:');
    const aggregator = new BatchAggregator(store, makeTestConfig({ batchIntervalMs: 100 }));
    aggregator.start();

    const emptyReceived = await new Promise<boolean>((resolve) => {
      aggregator.on('batch:empty', () => resolve(true));
      aggregator.on('batch:closed', () => resolve(false));
    });

    expect(emptyReceived).toBe(true);

    aggregator.stop();
    store.close();
  });
});

// ── T8: MerkleBatcher — computes correct root ───────────────────────

describe('T8: MerkleBatcher computes correct Merkle root', () => {
  let store: ProvenanceStore;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
  });

  afterEach(() => {
    store.close();
  });

  test('computes Merkle root matching cell-ops computeMerkleRoot', () => {
    const batcher = new MerkleBatcher(store);

    const cells = [makeCollectedCell(), makeCollectedCell(), makeCollectedCell()];
    const batchId = 'merkle-test-001';
    store.createBatch(batchId, Date.now());
    for (const cell of cells) {
      store.insertCell(cell, batchId);
    }

    const batch: CellBatch = {
      batchId,
      cells,
      openedAt: Date.now(),
      closedAt: Date.now() + 30000,
    };

    const anchor = batcher.processBatch(batch);

    // Verify root matches direct computation
    const expectedRoot = computeMerkleRoot(cells.map(c => c.contentHash));
    expect(anchor.merkleRoot.toString('hex')).toBe(expectedRoot.toString('hex'));

    // Root should be 64 hex chars (32 bytes)
    expect(anchor.merkleRoot.toString('hex')).toMatch(/^[a-f0-9]{64}$/);
    expect(anchor.leafCount).toBe(3);
    expect(anchor.status).toBe('pending');
  });

  test('static computeRoot matches library function', () => {
    const hashes = [
      createHash('sha256').update('leaf1').digest(),
      createHash('sha256').update('leaf2').digest(),
    ];

    const root = MerkleBatcher.computeRoot(hashes);
    const expected = computeMerkleRoot(hashes);
    expect(root.toString('hex')).toBe(expected.toString('hex'));
  });
});

// ── T9: MerkleBatcher — proofs verify against root ───────────────────

describe('T9: MerkleBatcher proofs verify', () => {
  let store: ProvenanceStore;

  beforeEach(() => {
    store = new ProvenanceStore(':memory:');
  });

  afterEach(() => {
    store.close();
  });

  test('individual proofs stored in DB verify against Merkle root', () => {
    const batcher = new MerkleBatcher(store);
    const cells = [makeCollectedCell(), makeCollectedCell(), makeCollectedCell(), makeCollectedCell()];
    const batchId = 'proof-test-001';

    store.createBatch(batchId, Date.now());
    for (const cell of cells) {
      store.insertCell(cell, batchId);
    }

    const batch: CellBatch = {
      batchId,
      cells,
      openedAt: Date.now(),
      closedAt: Date.now() + 30000,
    };

    const anchor = batcher.processBatch(batch);

    // Verify each stored proof
    const proofs = store.getMerkleProofsByBatch(batchId);
    expect(proofs.length).toBe(4);

    for (const proof of proofs) {
      const envelope = deserializeMerkleEnvelope(Buffer.from(proof.proof_blob));
      // Each proof envelope should have the same root
      expect(envelope.root.toString('hex')).toBe(anchor.merkleRoot.toString('hex'));
    }

    // Also verify using direct proof generation
    const leaves = cells.map(c => c.contentHash);
    for (let i = 0; i < leaves.length; i++) {
      const proof = generateMerkleProof(leaves, i);
      expect(verifyMerkleProof(proof, anchor.merkleRoot)).toBe(true);
    }
  });
});

// ── T10: BsvAnchorPipeline — dry-run anchor ──────────────────────────

describe('T10: BsvAnchorPipeline dry-run', () => {
  let store: ProvenanceStore;
  let pipeline: BsvAnchorPipeline;

  beforeEach(async () => {
    store = new ProvenanceStore(':memory:');
    pipeline = new BsvAnchorPipeline(store, makeTestConfig());
    await pipeline.initialize();
  });

  afterEach(() => {
    store.close();
  });

  test('dry-run produces valid anchor record without BSV broadcast', async () => {
    const merkleRoot = createHash('sha256').update('test-root').digest();
    const batchId = 'dry-run-batch-001';

    // Create batch in store first
    store.createBatch(batchId, Date.now());
    store.closeBatch(batchId, Date.now(), 5);
    store.setBatchMerkleRoot(batchId, merkleRoot);

    const anchor = await pipeline.anchor({
      batchId,
      merkleRoot,
      leafCount: 5,
      txid: null,
      anchoredAt: null,
      status: 'pending',
    });

    expect(anchor.txid).toBeDefined();
    expect(anchor.txid).not.toBeNull();
    expect(anchor.txid!.length).toBe(64); // SHA256 hex
    expect(anchor.status).toBe('submitted');
    expect(anchor.anchoredAt).not.toBeNull();

    // Verify stored in DB
    const storedAnchor = store.getAnchor(batchId);
    expect(storedAnchor).not.toBeNull();
    expect(storedAnchor!.txid).toBe(anchor.txid);
    expect(storedAnchor!.status).toBe('submitted');

    const stats = pipeline.getStats();
    expect(stats.submitted).toBe(1);
    expect(stats.failed).toBe(0);
  });

  test('dry-run emits anchor:submitted event', async () => {
    const merkleRoot = createHash('sha256').update('event-test').digest();
    const batchId = 'event-batch-001';

    store.createBatch(batchId, Date.now());
    store.closeBatch(batchId, Date.now(), 1);
    store.setBatchMerkleRoot(batchId, merkleRoot);

    const eventPromise = new Promise((resolve) => {
      pipeline.on('anchor:submitted', resolve);
    });

    await pipeline.anchor({
      batchId,
      merkleRoot,
      leafCount: 1,
      txid: null,
      anchoredAt: null,
      status: 'pending',
    });

    const emitted = await eventPromise;
    expect(emitted).toBeDefined();
  });
});

// ── T11: RestServer — GET /health ────────────────────────────────────

describe('T11: RestServer health endpoint', () => {
  let store: ProvenanceStore;
  let server: RestServer;
  let port: number;

  beforeEach(async () => {
    store = new ProvenanceStore(':memory:');
    // Use port 0 to get a random available port
    port = 9900 + Math.floor(Math.random() * 100);
    server = new RestServer(port, store);
    await server.start();
  });

  afterEach(async () => {
    await server.stop();
    store.close();
  });

  test('GET /health returns 200 with status ok', async () => {
    const response = await fetch(`http://localhost:${port}/health`);
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.data.status).toBe('ok');
    expect(data.data.uptime_ms).toBeGreaterThanOrEqual(0);
    expect(data.data.version).toBeDefined();
  });

  test('GET /api/stats returns statistics', async () => {
    const response = await fetch(`http://localhost:${port}/api/stats`);
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.data).toHaveProperty('totalCells');
    expect(data.data).toHaveProperty('tps');
    expect(data.data).toHaveProperty('uptime_ms');
  });

  test('GET /api/cells returns empty list initially', async () => {
    const response = await fetch(`http://localhost:${port}/api/cells`);
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.data.cells).toEqual([]);
    expect(data.data.total).toBe(0);
  });

  test('GET /api/cells/:cellId returns 404 for missing cell', async () => {
    const response = await fetch(`http://localhost:${port}/api/cells/nonexistent`);
    expect(response.status).toBe(404);
  });
});

// ── T12: End-to-end — cell → batch → Merkle → anchor ────────────────

describe('T12: End-to-end pipeline', () => {
  test('cell injected into collector flows through to anchored batch', async () => {
    const config = makeTestConfig({
      batchIntervalMs: 300,
      dbPath: ':memory:',
      dryRun: true,
    });

    const store = new ProvenanceStore(':memory:');
    const collector = new CellCollector(store, config);
    const aggregator = new BatchAggregator(store, config);
    const merkleBatcher = new MerkleBatcher(store);
    const anchorPipeline = new BsvAnchorPipeline(store, config);

    await anchorPipeline.initialize();

    // Wire events (same as BorderRouter)
    collector.on('cell:received', (cell) => {
      aggregator.addCell(cell);
    });

    const anchorPromise = new Promise<void>((resolve) => {
      aggregator.on('batch:closed', async (batch) => {
        const anchor = merkleBatcher.processBatch(batch);
        await anchorPipeline.anchor(anchor);
        resolve();
      });
    });

    aggregator.start();

    // Inject 3 valid cells
    for (let i = 0; i < 3; i++) {
      const cellBytes = buildValidCell();
      collector.injectCell(cellBytes, `player-${i}`);
    }

    // Wait for batch + anchor
    await anchorPromise;

    // Verify store state
    const stats = store.getStats();
    expect(stats.total_cells).toBe(3);
    expect(stats.total_batches).toBeGreaterThanOrEqual(1);
    expect(stats.total_anchored).toBeGreaterThanOrEqual(1);

    // Verify cells are in store
    const cells = store.getRecentCells(10);
    expect(cells.length).toBe(3);

    // Verify batch has Merkle root
    const batches = store.getRecentBatches(10);
    const closedBatch = batches.find(b => b.status === 'anchored');
    expect(closedBatch).toBeDefined();
    expect(closedBatch!.merkle_root).not.toBeNull();
    expect(closedBatch!.cell_count).toBe(3);

    // Verify anchor record
    const anchor = store.getAnchor(closedBatch!.batch_id);
    expect(anchor).not.toBeNull();
    expect(anchor!.txid).toBeDefined();
    expect(anchor!.status).toBe('submitted');

    // Verify Merkle proofs exist
    const proofs = store.getMerkleProofsByBatch(closedBatch!.batch_id);
    expect(proofs.length).toBe(3);

    // Verify each proof against the root
    const merkleRootBuf = Buffer.from(closedBatch!.merkle_root!);
    for (const proof of proofs) {
      const envelope = deserializeMerkleEnvelope(Buffer.from(proof.proof_blob));
      expect(envelope.root.toString('hex')).toBe(merkleRootBuf.toString('hex'));
    }

    aggregator.stop();
    store.close();
  });
});

```
