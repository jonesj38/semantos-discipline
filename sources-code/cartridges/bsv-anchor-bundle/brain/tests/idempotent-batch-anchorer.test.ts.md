---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/tests/idempotent-batch-anchorer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.442842+00:00
---

# cartridges/bsv-anchor-bundle/brain/tests/idempotent-batch-anchorer.test.ts

```ts
/**
 * Tests for the IdempotentBatchAnchorer wrapper — first consumer of
 * L5's per-batchId idempotent anchoring primitive (#815).
 *
 * Reference: docs/canon/cw-lift-matrix.yml L5.
 *
 * Strategy:
 *   Use a mock AnchorAdapter that records every batchAnchor call and
 *   returns synthetic AnchorProof[]s. Drive the wrapper through every
 *   cache-state path (miss / hit / failed-not-cached / multi-window).
 *   This proves the L5 idempotency layer rides on top of the existing
 *   AnchorAdapter contract without modification.
 *
 * Covers:
 *   - Cache miss on first call: inner adapter invoked once, manifest
 *     persisted, proofs returned.
 *   - Cache hit on retry: inner NOT invoked again, same manifest + same
 *     proofs returned.
 *   - Reordered cellRoots produce the same batchId (idempotency is
 *     order-independent on the L5 key).
 *   - Different windows produce different batchIds → two inner calls.
 *   - Inner adapter throwing produces 'failed' manifest (L5 contract);
 *     retry re-invokes inner.
 *   - Empty proof array from inner → 'failed' manifest.
 *   - AnchorProof[] reconstituted from manifest.attestationPayload on
 *     cache hit (no extra adapter calls).
 *   - Manifest's batchId is the L5 deterministic id (computeBatchId
 *     parity).
 */

import { describe, expect, test } from 'bun:test';
import { InMemoryAnchorStore, computeBatchId } from '@semantos/anchor-attestation';
import type { AnchorAdapter, AnchorItem, AnchorProof, AnchorState, AnchorMode } from '@semantos/protocol-types';
import { IdempotentBatchAnchorer } from '../src/idempotent-batch-anchorer';

// ── Mock AnchorAdapter that records calls ────────────────────────

interface RecordedCall {
  items: AnchorItem[];
  callIndex: number;
}

function makeMockAnchorAdapter(opts: {
  /** Optional override: throw on submit. */
  throwOn?: number;
  /** Optional override: return empty proof array on this call index. */
  returnEmptyOn?: number;
} = {}) {
  const calls: RecordedCall[] = [];
  let callCount = 0;
  const adapter: AnchorAdapter = {
    async anchor(stateHash) {
      throw new Error('anchor() not used by IdempotentBatchAnchorer');
    },
    async batchAnchor(items) {
      const callIndex = callCount++;
      calls.push({ items: [...items], callIndex });
      if (opts.throwOn === callIndex) {
        throw new Error(`simulated inner failure on call ${callIndex}`);
      }
      if (opts.returnEmptyOn === callIndex) {
        return [];
      }
      // Synthesise an AnchorProof per item — txid stable across the
      // batch, merkle path distinct per index.
      const txid = `tx${callIndex.toString().padStart(2, '0')}`.padEnd(64, '0');
      return items.map((item, i) => ({
        stateHash: item.stateHash,
        txid,
        vout: 0,
        blockHeight: 800_000 + callIndex,
        blockHash: 'block'.padEnd(64, '0'),
        timestamp: 1_700_000_000_000,
        merkleProof: `path-${i}`,
        interval: 60_000,
      } satisfies AnchorProof));
    },
    async verify() {
      throw new Error('verify() not used by IdempotentBatchAnchorer');
    },
    async getLatestAnchor() { return null; },
    async getAnchorHistory() { return []; },
    getAnchorInterval() { return 60_000; },
    async start() {},
    async stop() {},
    getState(): AnchorState {
      return {
        mode: 'stub' as AnchorMode,
        interval: 60_000,
        pendingStateHashes: [],
        totalAnchored: 0,
      };
    },
  };
  return { adapter, calls };
}

// ── Fixtures ──────────────────────────────────────────────────────

function cellRoot(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (seed * 13 + i * 17) & 0xff;
  return b;
}

function items(stateHashes: string[]): AnchorItem[] {
  return stateHashes.map((stateHash) => ({ stateHash }));
}

function bytesHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

// ── Tests ─────────────────────────────────────────────────────────

describe('IdempotentBatchAnchorer — cache miss + persist', () => {
  test('first call invokes inner.batchAnchor exactly once, persists manifest', async () => {
    const { adapter, calls } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);

    const result = await anchorer.anchorBatchIdempotent({
      cellRoots: [cellRoot(1), cellRoot(2)],
      items: items(['hash-a', 'hash-b']),
    });

    expect(calls.length).toBe(1);
    expect(result.fromCache).toBe(false);
    expect(result.proofs.length).toBe(2);
    expect(result.proofs[0].stateHash).toBe('hash-a');
    expect(result.proofs[1].stateHash).toBe('hash-b');
    expect(result.manifest.status).toBe('broadcast');
    expect(result.manifest.txid).toBeDefined();
    expect(store.size()).toBe(1);
  });

  test('manifest.batchId equals computeBatchId(cellRoots, window) for parity with L5', async () => {
    const { adapter } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);
    const cellRoots = [cellRoot(1), cellRoot(2), cellRoot(3)];

    const result = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['a', 'b', 'c']),
    });
    const expectedBatchId = computeBatchId(cellRoots);
    expect(bytesHex(result.manifest.batchId)).toBe(bytesHex(expectedBatchId));
  });
});

describe('IdempotentBatchAnchorer — cache hit (idempotency)', () => {
  test('second call with same cellRoots returns cached manifest WITHOUT calling inner', async () => {
    const { adapter, calls } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);
    const cellRoots = [cellRoot(1), cellRoot(2)];

    const first = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['a', 'b']),
    });
    const second = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['a', 'b']),
    });

    expect(calls.length).toBe(1); // inner called ONCE
    expect(second.fromCache).toBe(true);
    expect(first.fromCache).toBe(false);
    expect(bytesHex(second.manifest.batchId)).toBe(bytesHex(first.manifest.batchId));
    expect(second.manifest.txid).toEqual(first.manifest.txid);
  });

  test('cache hit returns the SAME AnchorProof[] (reconstituted from payload)', async () => {
    const { adapter } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);
    const cellRoots = [cellRoot(1), cellRoot(2)];

    const first = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['a', 'b']),
    });
    const second = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['a', 'b']),
    });

    expect(second.proofs.length).toBe(first.proofs.length);
    for (let i = 0; i < second.proofs.length; i++) {
      expect(second.proofs[i].stateHash).toBe(first.proofs[i].stateHash);
      expect(second.proofs[i].txid).toBe(first.proofs[i].txid);
      expect(second.proofs[i].blockHeight).toBe(first.proofs[i].blockHeight);
    }
  });

  test('reordered cellRoots → same batchId → cache hit', async () => {
    const { adapter, calls } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);

    await anchorer.anchorBatchIdempotent({
      cellRoots: [cellRoot(1), cellRoot(2), cellRoot(3)],
      items: items(['a', 'b', 'c']),
    });
    const second = await anchorer.anchorBatchIdempotent({
      cellRoots: [cellRoot(3), cellRoot(1), cellRoot(2)], // reordered
      items: items(['c', 'a', 'b']),
    });

    expect(calls.length).toBe(1);
    expect(second.fromCache).toBe(true);
  });
});

describe('IdempotentBatchAnchorer — distinct windows', () => {
  test('same cellRoots with different windows → two inner calls + two manifests', async () => {
    const { adapter, calls } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);
    const cellRoots = [cellRoot(1)];
    const w1 = new TextEncoder().encode('window/2026-06-02T22:00');
    const w2 = new TextEncoder().encode('window/2026-06-02T22:10');

    const a = await anchorer.anchorBatchIdempotent({ cellRoots, items: items(['x']), window: w1 });
    const b = await anchorer.anchorBatchIdempotent({ cellRoots, items: items(['x']), window: w2 });

    expect(calls.length).toBe(2);
    expect(bytesHex(a.manifest.batchId)).not.toBe(bytesHex(b.manifest.batchId));
    expect(store.size()).toBe(2);
  });
});

describe('IdempotentBatchAnchorer — failure paths', () => {
  test('inner adapter throws → manifest stored as failed → next call re-invokes', async () => {
    const { adapter, calls } = makeMockAnchorAdapter({ throwOn: 0 });
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);

    await expect(
      anchorer.anchorBatchIdempotent({
        cellRoots: [cellRoot(1)],
        items: items(['x']),
      }),
    ).rejects.toThrow('failed at submission');

    // Failed manifests are not cached → next call re-submits.
    // The mock's throwOn is for call 0; call 1 succeeds.
    const second = await anchorer.anchorBatchIdempotent({
      cellRoots: [cellRoot(1)],
      items: items(['x']),
    });
    expect(calls.length).toBe(2);
    expect(second.fromCache).toBe(false);
    expect(second.manifest.status).toBe('broadcast');
  });

  test('inner returns empty proof array → failed manifest → throws', async () => {
    const { adapter } = makeMockAnchorAdapter({ returnEmptyOn: 0 });
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);

    await expect(
      anchorer.anchorBatchIdempotent({
        cellRoots: [cellRoot(1)],
        items: items(['x']),
      }),
    ).rejects.toThrow('empty proof array');
  });
});

describe('IdempotentBatchAnchorer — composition with L4', () => {
  test('proofs returned from cache have all fields needed for downstream L4 verifyInclusion', async () => {
    // This is a SHAPE test — the cached proofs must round-trip cleanly
    // through JSON. We don't run verifyInclusion here (that's covered
    // in #835's tests); we just confirm the proof fields are intact
    // so a consumer can feed them to verifyInclusion / verifyAnchor
    // AttestationInclusion (#835).
    const { adapter } = makeMockAnchorAdapter();
    const store = new InMemoryAnchorStore();
    const anchorer = new IdempotentBatchAnchorer(adapter, store);
    const cellRoots = [cellRoot(1)];

    await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['hash-a']),
    });
    const second = await anchorer.anchorBatchIdempotent({
      cellRoots,
      items: items(['hash-a']),
    });

    const proof = second.proofs[0];
    expect(proof.stateHash).toBe('hash-a');
    expect(proof.txid).toBeDefined();
    expect(typeof proof.vout).toBe('number');
    expect(typeof proof.blockHeight).toBe('number');
    expect(proof.merkleProof).toBeDefined();
  });
});

```
