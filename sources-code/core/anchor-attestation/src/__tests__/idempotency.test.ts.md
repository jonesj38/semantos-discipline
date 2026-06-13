---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/__tests__/idempotency.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.940599+00:00
---

# core/anchor-attestation/src/__tests__/idempotency.test.ts

```ts
/**
 * CW Lift L5 — per-batchId idempotent anchoring primitive.
 *
 * Tests both pure helpers (computeBatchId, sortCellRoots) and the
 * idempotent `requestAnchor` wrapper against an `InMemoryAnchorStore`.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L5; docs/prd/CW-LIFT-ROADMAP.md §2.
 */

import { describe, expect, test } from 'bun:test';
import {
  computeBatchId,
  InMemoryAnchorStore,
  requestAnchor,
  sortCellRoots,
  type BatchSubmitResult,
} from '../idempotency.js';

function root(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  // Fill with a seed-derived deterministic pattern.
  for (let i = 0; i < 32; i++) b[i] = (seed * 7 + i * 13) & 0xff;
  return b;
}

function bytesHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

describe('CW Lift L5: idempotency primitives', () => {
  describe('sortCellRoots', () => {
    test('sorts lexicographically and returns copies (not aliases)', () => {
      const a = root(3);
      const b = root(1);
      const c = root(2);
      const sorted = sortCellRoots([a, b, c]);
      expect(sorted.length).toBe(3);
      // Verify each pair is in ascending order
      for (let i = 0; i < sorted.length - 1; i++) {
        expect(bytesHex(sorted[i]) <= bytesHex(sorted[i + 1])).toBe(true);
      }
      // Verify not aliases (mutating sorted shouldn't affect inputs)
      sorted[0][0] = 0xff;
      expect(a[0]).not.toBe(0xff);
      expect(b[0]).not.toBe(0xff);
      expect(c[0]).not.toBe(0xff);
    });

    test('rejects roots not exactly 32 bytes', () => {
      expect(() => sortCellRoots([new Uint8Array(31)])).toThrow();
      expect(() => sortCellRoots([new Uint8Array(33)])).toThrow();
    });
  });

  describe('computeBatchId', () => {
    test('same roots in different order → same batchId', () => {
      const id1 = computeBatchId([root(1), root(2), root(3)]);
      const id2 = computeBatchId([root(3), root(1), root(2)]);
      expect(bytesHex(id1)).toBe(bytesHex(id2));
      expect(id1.byteLength).toBe(32);
    });

    test('different roots → different batchId', () => {
      const id1 = computeBatchId([root(1), root(2)]);
      const id2 = computeBatchId([root(1), root(3)]);
      expect(bytesHex(id1)).not.toBe(bytesHex(id2));
    });

    test('same roots, different window → different batchId', () => {
      const w1 = new TextEncoder().encode('window/2026-06-02T22:00Z');
      const w2 = new TextEncoder().encode('window/2026-06-02T22:10Z');
      const id1 = computeBatchId([root(1), root(2)], w1);
      const id2 = computeBatchId([root(1), root(2)], w2);
      expect(bytesHex(id1)).not.toBe(bytesHex(id2));
    });

    test('empty window === default empty window', () => {
      const id1 = computeBatchId([root(1)]);
      const id2 = computeBatchId([root(1)], new Uint8Array(0));
      expect(bytesHex(id1)).toBe(bytesHex(id2));
    });

    test('rejects empty cellRoots', () => {
      expect(() => computeBatchId([])).toThrow();
    });

    test('domain separator pin — known-answer for a fixed input', () => {
      // Fixes the wire format. If this hash changes, the batchId scheme
      // changed and downstream stored manifests are invalidated. The
      // input here is: cellRoots = [root(1)] where root(seed) fills a
      // 32-byte buffer with (seed*7 + i*13) & 0xff per index, and the
      // window is UTF-8 "w" (one byte). The preimage is:
      //   "semantos.anchor.batch/v1" || varint(1) || "w"
      //   || varint(1) || root(1)
      const id = computeBatchId([root(1)], new TextEncoder().encode('w'));
      expect(bytesHex(id)).toBe(
        'bfbaf7ec20ee2f02ec98abe3f445e50510b94186a1f906c3cad686cf0b0dd09b',
      );
    });
  });

  describe('requestAnchor — idempotent flow', () => {
    test('first call invokes submitter and persists manifest', async () => {
      const store = new InMemoryAnchorStore();
      let calls = 0;
      const submit = async () => {
        calls++;
        return {
          status: 'broadcast' as const,
          txid: new Uint8Array(32).fill(0xAB),
          vout: 0,
        };
      };

      const out = await requestAnchor({
        cellRoots: [root(1), root(2)],
        store,
        submit,
      });

      expect(out.fromCache).toBe(false);
      expect(calls).toBe(1);
      expect(out.manifest.status).toBe('broadcast');
      expect(store.size()).toBe(1);
    });

    test('second call with same roots returns cached manifest, does not re-invoke submitter', async () => {
      const store = new InMemoryAnchorStore();
      let calls = 0;
      const submit = async () => {
        calls++;
        return { status: 'broadcast' as const, txid: new Uint8Array(32).fill(0xCD), vout: 0 };
      };

      const first = await requestAnchor({
        cellRoots: [root(1), root(2)],
        store,
        submit,
      });
      const second = await requestAnchor({
        cellRoots: [root(2), root(1)], // same set, different submission order
        store,
        submit,
      });

      expect(calls).toBe(1);
      expect(second.fromCache).toBe(true);
      expect(bytesHex(second.manifest.batchId)).toBe(bytesHex(first.manifest.batchId));
      expect(second.manifest.txid).toEqual(first.manifest.txid);
      expect(store.size()).toBe(1);
    });

    test("different windows produce different batchIds → two manifests", async () => {
      const store = new InMemoryAnchorStore();
      let calls = 0;
      const submit = async (req: { batchId: Uint8Array }) => {
        calls++;
        return {
          status: 'broadcast' as const,
          txid: req.batchId, // tie txid to batchId so we can inspect
          vout: 0,
        };
      };

      const w1 = new TextEncoder().encode('window/A');
      const w2 = new TextEncoder().encode('window/B');
      const a = await requestAnchor({ cellRoots: [root(1)], window: w1, store, submit });
      const b = await requestAnchor({ cellRoots: [root(1)], window: w2, store, submit });

      expect(calls).toBe(2);
      expect(bytesHex(a.manifest.batchId)).not.toBe(bytesHex(b.manifest.batchId));
      expect(store.size()).toBe(2);
    });

    test('failed submit is NOT cached — next call re-submits', async () => {
      const store = new InMemoryAnchorStore();
      let calls = 0;
      const submit = async (): Promise<BatchSubmitResult> => {
        calls++;
        if (calls === 1) {
          return { status: 'failed', reason: 'broadcast: temporary network error' };
        }
        return { status: 'broadcast', txid: new Uint8Array(32).fill(0xEE), vout: 0 };
      };

      const first = await requestAnchor({ cellRoots: [root(7)], store, submit });
      const second = await requestAnchor({ cellRoots: [root(7)], store, submit });

      expect(first.manifest.status).toBe('failed');
      expect(first.fromCache).toBe(false);
      expect(second.manifest.status).toBe('broadcast');
      expect(second.fromCache).toBe(false);
      expect(calls).toBe(2);
      // Store contains the latest manifest (broadcast), the failed one was overwritten
      expect(store.size()).toBe(1);
      const stored = store.get(second.manifest.batchId);
      expect(stored?.status).toBe('broadcast');
    });

    test('confirmed manifests are cached idempotently', async () => {
      const store = new InMemoryAnchorStore();
      let calls = 0;
      const submit = async (): Promise<BatchSubmitResult> => {
        calls++;
        return {
          status: 'confirmed',
          txid: new Uint8Array(32).fill(0x11),
          vout: 0,
          anchorHeight: 312500n,
        };
      };

      const first = await requestAnchor({ cellRoots: [root(9), root(8)], store, submit });
      const second = await requestAnchor({ cellRoots: [root(8), root(9)], store, submit });

      expect(calls).toBe(1);
      expect(second.fromCache).toBe(true);
      expect(second.manifest.anchorHeight).toBe(312500n);
    });

    test('cellRoots are stored in canonical sorted order regardless of submission order', async () => {
      const store = new InMemoryAnchorStore();
      const submit = async () => ({ status: 'broadcast' as const, txid: new Uint8Array(32), vout: 0 });
      const out = await requestAnchor({
        cellRoots: [root(3), root(1), root(2)],
        store,
        submit,
      });
      const sorted = out.manifest.cellRoots;
      for (let i = 0; i < sorted.length - 1; i++) {
        expect(bytesHex(sorted[i]) <= bytesHex(sorted[i + 1])).toBe(true);
      }
    });
  });

  describe('InMemoryAnchorStore', () => {
    test('listByStatus filters correctly', () => {
      const store = new InMemoryAnchorStore();
      store.put({
        batchId: new Uint8Array(32).fill(0xA1),
        cellRoots: [root(1)],
        window: new Uint8Array(0),
        status: 'pending',
      });
      store.put({
        batchId: new Uint8Array(32).fill(0xA2),
        cellRoots: [root(2)],
        window: new Uint8Array(0),
        status: 'broadcast',
      });
      store.put({
        batchId: new Uint8Array(32).fill(0xA3),
        cellRoots: [root(3)],
        window: new Uint8Array(0),
        status: 'confirmed',
      });
      expect(store.listByStatus('pending').length).toBe(1);
      expect(store.listByStatus('broadcast').length).toBe(1);
      expect(store.listByStatus('confirmed').length).toBe(1);
      expect(store.listByStatus('failed').length).toBe(0);
    });

    test('put with the same batchId replaces the existing manifest', () => {
      const store = new InMemoryAnchorStore();
      const id = new Uint8Array(32).fill(0xBB);
      store.put({
        batchId: id,
        cellRoots: [root(1)],
        window: new Uint8Array(0),
        status: 'pending',
      });
      store.put({
        batchId: id,
        cellRoots: [root(1)],
        window: new Uint8Array(0),
        status: 'confirmed',
        anchorHeight: 999n,
      });
      expect(store.size()).toBe(1);
      expect(store.get(id)?.status).toBe('confirmed');
    });
  });
});

```
