---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/snapshot-anchor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.862487+00:00
---

# core/protocol-types/__tests__/snapshot-anchor.test.ts

```ts
/**
 * Snapshot-anchor tests.
 *
 * Spec source: MNCA-LAYER-COLLAPSE-BRIEF §3 + WALLET-TIER-CUSTODY.md.
 * Verifies the pushdrop anchor plan composes with the codec and that the
 * BRC-42 fresh-leaf-per-anchor invariant (G9) holds via the injected port.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, HeaderOffsets } from '../src/constants';
import { mncaTypeHash, MncaCellTypeName } from '../src/mnca/cell-types';
import { parsePushdropLockingScript, COMPRESSED_PUBKEY_SIZE } from '../src/cell-pushdrop';
import {
  buildSnapshotAnchorPlan,
  buildSnapshotAnchorBatch,
  totalAnchorCostSats,
  cellHasType,
  type LeafDeriver,
} from '../src/mnca/snapshot-anchor';

/** Deterministic stub deriver: leaf pubkey is a function of the index only
 *  (so a fresh index → a fresh, distinct leaf — the G9 property under test). */
const stubDeriver: LeafDeriver = {
  deriveLeafPubkey({ index }) {
    const pk = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
    pk[0] = 0x02; // compressed-even prefix
    const n = index & 0xffffffffn;
    pk[1] = Number(n & 0xffn);
    pk[2] = Number((n >> 8n) & 0xffn);
    for (let i = 3; i < COMPRESSED_PUBKEY_SIZE; i++) pk[i] = (i + Number(n & 0xffn)) & 0xff;
    return pk;
  },
};

function protoHash(): Uint8Array {
  const p = new Uint8Array(16);
  for (let i = 0; i < 16; i++) p[i] = (i + 1) & 0xff;
  return p;
}
function counterparty(): Uint8Array {
  const c = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
  c[0] = 0x03;
  for (let i = 1; i < COMPRESSED_PUBKEY_SIZE; i++) c[i] = (i * 2) & 0xff;
  return c;
}

async function snapshotCell(seed = 1): Promise<Uint8Array> {
  const cell = new Uint8Array(CELL_SIZE);
  const th = mncaTypeHash(MncaCellTypeName.SNAPSHOT);
  cell.set(th, HeaderOffsets.typeHash);
  for (let i = 256; i < CELL_SIZE; i++) cell[i] = (i + seed) & 0xff;
  return cell;
}

describe('buildSnapshotAnchorPlan', () => {
  test('locks the snapshot cell under a fresh Tier-0 leaf pubkey', async () => {
    const cell = await snapshotCell();
    const snapHash = mncaTypeHash(MncaCellTypeName.SNAPSHOT);
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 7n,
      anchorSats: 100n,
      expectedTypeHash: snapHash,
    });

    expect(plan.satoshis).toBe(100n);
    expect(plan.leafIndex).toBe(7n);
    expect(plan.ownerPubkey.length).toBe(COMPRESSED_PUBKEY_SIZE);

    // The locking script parses back to the exact cell + the leaf pubkey.
    const parsed = parsePushdropLockingScript(plan.lockingScript);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(cell));
    expect(Array.from(parsed.pubkey)).toEqual(Array.from(plan.ownerPubkey));
  });

  test('G9: a fresh index yields a fresh, distinct leaf', async () => {
    const cell = await snapshotCell();
    const base = {
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      anchorSats: 100n,
    };
    const a = buildSnapshotAnchorPlan({ ...base, index: 1n });
    const b = buildSnapshotAnchorPlan({ ...base, index: 2n });
    expect(Array.from(a.ownerPubkey)).not.toEqual(Array.from(b.ownerPubkey));
  });

  test('rejects a non-snapshot cell when expectedTypeHash is given', async () => {
    const cell = await snapshotCell();
    const perturbHash = mncaTypeHash(MncaCellTypeName.PERTURB);
    expect(() =>
      buildSnapshotAnchorPlan({
        snapshotCell: cell,
        deriver: stubDeriver,
        protocolHash: protoHash(),
        counterparty: counterparty(),
        index: 1n,
        anchorSats: 100n,
        expectedTypeHash: perturbHash, // cell is snapshot, not perturb
      }),
    ).toThrow();
  });

  test('rejects bad inputs (size, sats, protocol, counterparty)', async () => {
    const cell = await snapshotCell();
    const base = {
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 1n,
      anchorSats: 100n,
    };
    expect(() => buildSnapshotAnchorPlan({ ...base, snapshotCell: new Uint8Array(1000) })).toThrow();
    expect(() => buildSnapshotAnchorPlan({ ...base, anchorSats: 0n })).toThrow();
    expect(() => buildSnapshotAnchorPlan({ ...base, protocolHash: new Uint8Array(15) })).toThrow();
    expect(() => buildSnapshotAnchorPlan({ ...base, counterparty: new Uint8Array(32) })).toThrow();
  });

  test('rejects a deriver that returns a wrong-sized pubkey', async () => {
    const cell = await snapshotCell();
    const badDeriver: LeafDeriver = { deriveLeafPubkey: () => new Uint8Array(32) };
    expect(() =>
      buildSnapshotAnchorPlan({
        snapshotCell: cell,
        deriver: badDeriver,
        protocolHash: protoHash(),
        counterparty: counterparty(),
        index: 1n,
        anchorSats: 100n,
      }),
    ).toThrow();
  });
});

describe('buildSnapshotAnchorBatch', () => {
  test('one plan per cell, each under its own fresh leaf (startIndex + i)', async () => {
    const cells = [await snapshotCell(1), await snapshotCell(2), await snapshotCell(3)];
    const plans = buildSnapshotAnchorBatch(cells, {
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      anchorSats: 100n,
      startIndex: 10n,
    });
    expect(plans.length).toBe(3);
    expect(plans.map((p) => p.leafIndex)).toEqual([10n, 11n, 12n]);
    // Distinct leaves across the batch.
    const hexes = plans.map((p) => Array.from(p.ownerPubkey).join(','));
    expect(new Set(hexes).size).toBe(3);
    // Each plan recovers its own cell.
    for (let i = 0; i < 3; i++) {
      const parsed = parsePushdropLockingScript(plans[i]!.lockingScript);
      expect(Array.from(parsed.cellBytes)).toEqual(Array.from(cells[i]!));
    }
  });

  test('totalAnchorCostSats sums the batch', async () => {
    const cells = [await snapshotCell(1), await snapshotCell(2)];
    const plans = buildSnapshotAnchorBatch(cells, {
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      anchorSats: 100n,
      startIndex: 0n,
    });
    expect(totalAnchorCostSats(plans)).toBe(200n);
    expect(totalAnchorCostSats([])).toBe(0n);
  });
});

describe('cellHasType', () => {
  test('matches the snapshot type-hash at offset 30', async () => {
    const cell = await snapshotCell();
    const snap = mncaTypeHash(MncaCellTypeName.SNAPSHOT);
    const tick = mncaTypeHash(MncaCellTypeName.TILE_TICK);
    expect(cellHasType(cell, snap)).toBe(true);
    expect(cellHasType(cell, tick)).toBe(false);
  });
});

```
