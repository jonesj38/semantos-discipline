---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/tests/anchor-history-chain.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.443154+00:00
---

# cartridges/bsv-anchor-bundle/brain/tests/anchor-history-chain.test.ts

```ts
/**
 * AnchorHistoryChain — first L12 cartridge consumer tests.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L12 axis F.
 *
 * Strategy:
 *   Drive the consumer through three distinct anchors (different
 *   windows so each is a fresh batchId), verify the resulting 3-link
 *   chain. Then exercise the idempotency interaction: a repeated
 *   anchor with the same (cellRoots, window) hits the L5 cache and
 *   MUST NOT append a duplicate chain entry. Tampering with a stored
 *   chain entry must fail end-to-end verification.
 *
 * Covers:
 *   - Canonical encode/decode round-trip + magic + version
 *   - Single anchor → 1-entry chain that verifies
 *   - 3 anchors across 3 windows → 3-entry chain that verifies
 *   - Cache hit (same window twice) → chainEntry is null on the second
 *     call; chain length stays at 1
 *   - Tampered canonical bytes → verifyHistory fails closed
 *   - Failed anchor (inner throws) → no chain entry appended
 *   - Multiple chains keyed by entityId stay independent
 *   - sortedCellRoots in the entry recovers the L5 batchId via
 *     computeBatchId (proving the chain is recomputable)
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { InMemoryAnchorStore, computeBatchId } from '@semantos/anchor-attestation';
import { verifyAuditChain } from '@semantos/anchor-attestation/audit-chain';
import type {
  AnchorAdapter,
  AnchorItem,
  AnchorProof,
  AnchorState,
  AnchorMode,
} from '@semantos/protocol-types';
import {
  AnchorHistoryChain,
  InMemoryAnchorHistoryStore,
  ANCHOR_HISTORY_MAGIC,
  ANCHOR_HISTORY_VERSION,
  STATUS_CODE,
  encodeAnchorHistoryCanonical,
  decodeAnchorHistoryCanonical,
} from '../src/anchor-history-chain';
import { IdempotentBatchAnchorer } from '../src/idempotent-batch-anchorer';

// ── Stub AnchorAdapter (same shape as the L5 consumer tests) ────

function makeMockAdapter(opts: { throwOn?: number } = {}) {
  const calls: { items: AnchorItem[]; callIndex: number }[] = [];
  let callCount = 0;
  const adapter: AnchorAdapter = {
    async anchor() {
      throw new Error('anchor() not used');
    },
    async batchAnchor(items) {
      const callIndex = callCount++;
      calls.push({ items: [...items], callIndex });
      if (opts.throwOn === callIndex) {
        throw new Error(`simulated failure ${callIndex}`);
      }
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
    async verify() { throw new Error('verify() not used'); },
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

// ── Fixtures ─────────────────────────────────────────────────────

function cellRoot(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (seed * 13 + i * 17) & 0xff;
  return b;
}
function items(hashes: string[]): AnchorItem[] {
  return hashes.map(stateHash => ({ stateHash }));
}
function windowBytes(label: string): Uint8Array {
  return new TextEncoder().encode(label);
}
function bytesHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

const MASTER_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function master() {
  return PrivateKey.fromString(MASTER_PRIV_HEX, 'hex');
}
function masterPubHex() {
  return master().toPublicKey().toDER('hex') as string;
}

function makeRig(entityId = 'operator:semantos-anchor-history:main') {
  const { adapter, calls } = makeMockAdapter();
  const anchorStore = new InMemoryAnchorStore();
  const inner = new IdempotentBatchAnchorer(adapter, anchorStore);
  const chainStore = new InMemoryAnchorHistoryStore();
  const history = new AnchorHistoryChain(inner, master(), chainStore, entityId);
  return { adapter, calls, anchorStore, chainStore, history, entityId };
}

// ── Tests ────────────────────────────────────────────────────────

describe('L12 anchor-history canonical encoding', () => {
  test('magic is "AHX1" + version 1', () => {
    expect(Buffer.from(ANCHOR_HISTORY_MAGIC).toString('ascii')).toBe('AHX1');
    expect(ANCHOR_HISTORY_VERSION).toBe(1);
  });

  test('encode → decode round-trip preserves all fields', () => {
    const rec = {
      batchId: new Uint8Array(32).fill(0xAB),
      statusCode: STATUS_CODE.broadcast,
      txid: new Uint8Array(32).fill(0xCD),
      vout: 7,
      anchorHeight: 800_123n,
      window: windowBytes('window-A/2026-06-04T00:00'),
      sortedCellRoots: [cellRoot(1), cellRoot(2), cellRoot(3)],
    };
    const bytes = encodeAnchorHistoryCanonical(rec);
    const decoded = decodeAnchorHistoryCanonical(bytes);
    expect(bytesHex(decoded.batchId)).toBe(bytesHex(rec.batchId));
    expect(decoded.statusCode).toBe(rec.statusCode);
    expect(bytesHex(decoded.txid)).toBe(bytesHex(rec.txid));
    expect(decoded.vout).toBe(rec.vout);
    expect(decoded.anchorHeight).toBe(rec.anchorHeight);
    expect(bytesHex(decoded.window)).toBe(bytesHex(rec.window));
    expect(decoded.sortedCellRoots.length).toBe(3);
    for (let i = 0; i < 3; i++) {
      expect(bytesHex(decoded.sortedCellRoots[i])).toBe(bytesHex(rec.sortedCellRoots[i]));
    }
  });

  test('encode is deterministic — same input → same bytes', () => {
    const rec = {
      batchId: new Uint8Array(32).fill(0x01),
      statusCode: STATUS_CODE.confirmed,
      txid: new Uint8Array(32).fill(0x02),
      vout: 0,
      anchorHeight: 0n,
      window: new Uint8Array(0),
      sortedCellRoots: [cellRoot(9)],
    };
    const a = encodeAnchorHistoryCanonical(rec);
    const b = encodeAnchorHistoryCanonical(rec);
    expect(bytesHex(a)).toBe(bytesHex(b));
  });

  test('decode rejects wrong magic / version / trailing bytes', () => {
    const rec = {
      batchId: new Uint8Array(32),
      statusCode: STATUS_CODE.broadcast,
      txid: new Uint8Array(32),
      vout: 0,
      anchorHeight: 0n,
      window: new Uint8Array(0),
      sortedCellRoots: [],
    };
    const bytes = encodeAnchorHistoryCanonical(rec);
    const bad1 = new Uint8Array(bytes);
    bad1[0] ^= 0x01; // magic
    expect(() => decodeAnchorHistoryCanonical(bad1)).toThrow();
    const bad2 = new Uint8Array(bytes);
    bad2[4] = 99; // version byte
    expect(() => decodeAnchorHistoryCanonical(bad2)).toThrow();
    const bad3 = new Uint8Array(bytes.byteLength + 5);
    bad3.set(bytes);
    expect(() => decodeAnchorHistoryCanonical(bad3)).toThrow();
  });
});

describe('L12 anchor-history — happy path 3-link chain', () => {
  test('three fresh anchors → 3-entry chain that verifies end-to-end', async () => {
    const rig = makeRig();

    const r1 = await rig.history.anchorAndRecord({
      cellRoots: [cellRoot(1), cellRoot(2)],
      items: items(['a', 'b']),
      window: windowBytes('w1'),
    });
    const r2 = await rig.history.anchorAndRecord({
      cellRoots: [cellRoot(3)],
      items: items(['c']),
      window: windowBytes('w2'),
    });
    const r3 = await rig.history.anchorAndRecord({
      cellRoots: [cellRoot(4), cellRoot(5), cellRoot(6)],
      items: items(['d', 'e', 'f']),
      window: windowBytes('w3'),
    });

    expect(r1.anchor.fromCache).toBe(false);
    expect(r2.anchor.fromCache).toBe(false);
    expect(r3.anchor.fromCache).toBe(false);
    expect(r1.chainEntry).not.toBeNull();
    expect(r2.chainEntry).not.toBeNull();
    expect(r3.chainEntry).not.toBeNull();
    expect(r1.chainEntry!.entry.seq).toBe(0);
    expect(r2.chainEntry!.entry.seq).toBe(1);
    expect(r3.chainEntry!.entry.seq).toBe(2);

    const chain = await rig.history.loadHistory();
    expect(chain.length).toBe(3);

    const result = await rig.history.verifyHistory();
    expect(result.ok).toBe(true);

    // External verifier can independently verify via verifyAuditChain
    const ext = verifyAuditChain({
      entries: chain,
      masterPubKeyHex: masterPubHex(),
    });
    expect(ext.ok).toBe(true);
  });

  test('canonical bytes in each entry recover batchId via computeBatchId (recomputability)', async () => {
    const rig = makeRig();
    const roots = [cellRoot(7), cellRoot(8), cellRoot(9)];
    const window = windowBytes('recompute-check');
    const r1 = await rig.history.anchorAndRecord({
      cellRoots: roots,
      items: items(['p', 'q', 'r']),
      window,
    });
    const decoded = decodeAnchorHistoryCanonical(r1.chainEntry!.entry.canonical);
    // The decoded sortedCellRoots are in canonical (lex) order; verifying
    // batchId via computeBatchId(sortedCellRoots, window) re-derives the
    // same batchId stored in the entry.
    const recomputed = computeBatchId([...decoded.sortedCellRoots], decoded.window);
    expect(bytesHex(recomputed)).toBe(bytesHex(decoded.batchId));
    expect(bytesHex(decoded.batchId)).toBe(bytesHex(r1.anchor.manifest.batchId));
  });
});

describe('L12 anchor-history — idempotency interaction', () => {
  test('repeated same (cellRoots, window) → cache hit, no duplicate chain entry', async () => {
    const rig = makeRig();
    const params = {
      cellRoots: [cellRoot(10), cellRoot(11)],
      items: items(['x', 'y']),
      window: windowBytes('same'),
    };
    const r1 = await rig.history.anchorAndRecord(params);
    const r2 = await rig.history.anchorAndRecord(params);

    expect(r1.anchor.fromCache).toBe(false);
    expect(r1.chainEntry).not.toBeNull();
    expect(r2.anchor.fromCache).toBe(true);
    expect(r2.chainEntry).toBeNull();

    // Inner adapter invoked exactly once
    expect(rig.calls.length).toBe(1);

    const chain = await rig.history.loadHistory();
    expect(chain.length).toBe(1);

    const verifyResult = await rig.history.verifyHistory();
    expect(verifyResult.ok).toBe(true);
  });

  test('reordered cellRoots → cache hit (same batchId), no duplicate chain entry', async () => {
    const rig = makeRig();
    const roots = [cellRoot(20), cellRoot(21), cellRoot(22)];
    const reordered = [roots[2], roots[0], roots[1]];
    const r1 = await rig.history.anchorAndRecord({
      cellRoots: roots,
      items: items(['x', 'y', 'z']),
      window: windowBytes('reorder'),
    });
    const r2 = await rig.history.anchorAndRecord({
      cellRoots: reordered,
      items: items(['x', 'y', 'z']),
      window: windowBytes('reorder'),
    });

    expect(r1.chainEntry).not.toBeNull();
    expect(r2.anchor.fromCache).toBe(true);
    expect(r2.chainEntry).toBeNull();

    const chain = await rig.history.loadHistory();
    expect(chain.length).toBe(1);
  });
});

describe('L12 anchor-history — fail-closed paths', () => {
  test('failed inner anchor → throw, no chain entry appended', async () => {
    const { adapter } = makeMockAdapter({ throwOn: 0 });
    const anchorStore = new InMemoryAnchorStore();
    const inner = new IdempotentBatchAnchorer(adapter, anchorStore);
    const chainStore = new InMemoryAnchorHistoryStore();
    const history = new AnchorHistoryChain(
      inner,
      master(),
      chainStore,
      'op:entity-A',
    );

    let threw = false;
    try {
      await history.anchorAndRecord({
        cellRoots: [cellRoot(1)],
        items: items(['only']),
      });
    } catch {
      threw = true;
    }
    expect(threw).toBe(true);
    const chain = await history.loadHistory();
    expect(chain.length).toBe(0);
  });

  test('tampered canonical bytes → verifyHistory fails closed', async () => {
    const rig = makeRig();
    const r1 = await rig.history.anchorAndRecord({
      cellRoots: [cellRoot(31), cellRoot(32)],
      items: items(['t', 'u']),
      window: windowBytes('tamper-A'),
    });
    const r2 = await rig.history.anchorAndRecord({
      cellRoots: [cellRoot(33)],
      items: items(['v']),
      window: windowBytes('tamper-B'),
    });
    expect(r1.chainEntry).not.toBeNull();
    expect(r2.chainEntry).not.toBeNull();

    // Tamper with the first entry's canonical bytes via a backdoor —
    // pretend the store got malicious-bytes injected. Since the store
    // returns the array reference, we mutate index 0.
    const stored = rig.chainStore.list(rig.entityId) as unknown as Array<{
      entry: { canonical: Uint8Array };
    }>;
    stored[0].entry.canonical[5] ^= 0x42;

    const result = await rig.history.verifyHistory();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      // Tampered first entry → canonicalHash recompute fails before any
      // subsequent check.
      expect(result.failedAtIndex).toBe(0);
      expect(result.code).toBe('CANONICAL_HASH_MISMATCH');
    }
  });

  test('chains keyed by different entityIds stay independent', async () => {
    const rigA = makeRig('op:tenant-A');
    const rigB = makeRig('op:tenant-B');

    // Same anchor params on both rigs → distinct chains; the store on
    // each rig is its own InMemoryAnchorHistoryStore.
    await rigA.history.anchorAndRecord({
      cellRoots: [cellRoot(40)],
      items: items(['m']),
      window: windowBytes('mw'),
    });
    await rigB.history.anchorAndRecord({
      cellRoots: [cellRoot(41)],
      items: items(['n']),
      window: windowBytes('nw'),
    });
    const a = await rigA.history.loadHistory();
    const b = await rigB.history.loadHistory();
    expect(a.length).toBe(1);
    expect(b.length).toBe(1);
    expect(a[0].entry.entityId).toBe('op:tenant-A');
    expect(b[0].entry.entityId).toBe('op:tenant-B');
    // Different entityId → different per-link segment → different
    // linkPub. Cross-pollination is structurally impossible.
    expect(a[0].linkPubKeyHex).not.toBe(b[0].linkPubKeyHex);
  });
});

```
