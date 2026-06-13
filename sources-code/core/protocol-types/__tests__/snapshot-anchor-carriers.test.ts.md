---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/snapshot-anchor-carriers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.859492+00:00
---

# core/protocol-types/__tests__/snapshot-anchor-carriers.test.ts

```ts
/**
 * Snapshot-anchor × L13 carrier-choice tests.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L13.
 *
 * Verifies the snapshot-anchor builder picks the right L13 carrier
 * shape based on the `carrier?` field, and the existing PushDrop
 * default behaviour is preserved.
 *
 * Each carrier scenario:
 *   1. build the plan with that carrier choice
 *   2. confirm AnchorPlan.carrier reflects the choice
 *   3. parse the lockingScript via parseDataCarrier and recover the
 *      cell bytes + key material
 *   4. assert byte-equality with the input cell
 *
 * This proves the canonical MNCA anchor flow now lets callers pick any
 * of the three L13 carriers — the first real production-path consumer
 * of variants (b) and (c).
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { CELL_SIZE, HeaderOffsets } from '../src/constants';
import { mncaTypeHash, MncaCellTypeName } from '../src/mnca/cell-types';
import {
  parseDataCarrier,
  PKH_SIZE,
} from '../src/cell-data-carriers';
import { COMPRESSED_PUBKEY_SIZE } from '../src/cell-pushdrop';
import {
  buildSnapshotAnchorPlan,
  buildSnapshotAnchorBatch,
  type LeafDeriver,
} from '../src/mnca/snapshot-anchor';

const stubDeriver: LeafDeriver = {
  deriveLeafPubkey({ index }) {
    const pk = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
    pk[0] = 0x02;
    const n = index & 0xffffffffn;
    pk[1] = Number(n & 0xffn);
    pk[2] = Number((n >> 8n) & 0xffn);
    for (let i = 3; i < COMPRESSED_PUBKEY_SIZE; i++) {
      pk[i] = (i + Number(n & 0xffn)) & 0xff;
    }
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

function snapshotCell(seed = 1): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const th = mncaTypeHash(MncaCellTypeName.SNAPSHOT);
  cell.set(th, HeaderOffsets.typeHash);
  for (let i = 256; i < CELL_SIZE; i++) cell[i] = (i + seed) & 0xff;
  return cell;
}

function hash160(input: Uint8Array): Uint8Array {
  const sha = createHash('sha256').update(input).digest();
  const ripe = createHash('ripemd160').update(sha).digest();
  return new Uint8Array(ripe);
}

describe('buildSnapshotAnchorPlan × L13: default carrier = pushdrop', () => {
  test('omitting `carrier` produces a PushDrop locking script (backward compat)', () => {
    const cell = snapshotCell();
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
    });

    expect(plan.carrier).toBe('pushdrop');
    const parsed = parseDataCarrier(plan.lockingScript);
    expect(parsed.shape).toBe('pushdrop');
    if (parsed.shape === 'pushdrop') {
      expect(parsed.cellBytes).toEqual(cell);
      expect(parsed.pubkey).toEqual(plan.ownerPubkey);
    }
  });

  test('explicit carrier: "pushdrop" matches the default exactly', () => {
    const cell = snapshotCell(7);
    const a = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
    });
    const b = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'pushdrop',
    });
    expect(a.lockingScript).toEqual(b.lockingScript);
    expect(a.carrier).toBe(b.carrier);
  });
});

describe('buildSnapshotAnchorPlan × L13: carrier = op_false_op_if', () => {
  test('produces an OP_FALSE OP_IF carrier locking script', () => {
    const cell = snapshotCell(2);
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'op_false_op_if',
    });

    expect(plan.carrier).toBe('op_false_op_if');
    const parsed = parseDataCarrier(plan.lockingScript);
    expect(parsed.shape).toBe('op_false_op_if');
    if (parsed.shape === 'op_false_op_if') {
      expect(parsed.cellBytes).toEqual(cell);
      expect(parsed.pubkey).toEqual(plan.ownerPubkey);
    }
  });

  test('1024B cell + 33B pubkey → 1065-byte locking script (2 more than pushdrop)', () => {
    const cell = snapshotCell();
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'op_false_op_if',
    });
    expect(plan.lockingScript.length).toBe(1065);
  });
});

describe('buildSnapshotAnchorPlan × L13: carrier = op_drop_p2pkh', () => {
  test('produces an OP_DROP+P2PKH carrier locking script with hash160(pubkey)', () => {
    const cell = snapshotCell(3);
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'op_drop_p2pkh',
    });

    expect(plan.carrier).toBe('op_drop_p2pkh');
    const parsed = parseDataCarrier(plan.lockingScript);
    expect(parsed.shape).toBe('op_drop_p2pkh');
    if (parsed.shape === 'op_drop_p2pkh') {
      expect(parsed.cellBytes).toEqual(cell);
      // The pkh in the locking script must be hash160(ownerPubkey)
      const expectedPkh = hash160(plan.ownerPubkey);
      expect(parsed.pkh).toEqual(expectedPkh);
      expect(parsed.pkh.length).toBe(PKH_SIZE);
    }
  });

  test('1024B cell + 20B pkh → 1053-byte locking script (10 less than pushdrop)', () => {
    const cell = snapshotCell();
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'op_drop_p2pkh',
    });
    expect(plan.lockingScript.length).toBe(1053);
  });

  test('AnchorPlan.ownerPubkey is still the 33B compressed pubkey (NOT the pkh)', () => {
    // The pkh is only in the locking script. The plan exposes the
    // full pubkey so the wallet can re-derive + sign on the spend
    // side (P2PKH spends require the pubkey to satisfy OP_DUP/HASH160
    // /EQUALVERIFY).
    const cell = snapshotCell();
    const plan = buildSnapshotAnchorPlan({
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
      carrier: 'op_drop_p2pkh',
    });
    expect(plan.ownerPubkey.length).toBe(COMPRESSED_PUBKEY_SIZE);
  });
});

describe('buildSnapshotAnchorPlan × L13: cross-carrier invariants', () => {
  test('cell bytes recoverable identically from all three carrier shapes', () => {
    const cell = snapshotCell(42);
    const shared = {
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
    };
    const a = buildSnapshotAnchorPlan({ ...shared, carrier: 'pushdrop' });
    const b = buildSnapshotAnchorPlan({ ...shared, carrier: 'op_false_op_if' });
    const c = buildSnapshotAnchorPlan({ ...shared, carrier: 'op_drop_p2pkh' });

    for (const plan of [a, b, c]) {
      const parsed = parseDataCarrier(plan.lockingScript);
      expect(parsed.cellBytes).toEqual(cell);
    }
  });

  test('three locking scripts are distinct (different bytes for different carriers)', () => {
    const cell = snapshotCell();
    const shared = {
      snapshotCell: cell,
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      index: 0n,
      anchorSats: 1n,
    };
    const a = buildSnapshotAnchorPlan({ ...shared, carrier: 'pushdrop' });
    const b = buildSnapshotAnchorPlan({ ...shared, carrier: 'op_false_op_if' });
    const c = buildSnapshotAnchorPlan({ ...shared, carrier: 'op_drop_p2pkh' });
    const hex = (b: Uint8Array) => Buffer.from(b).toString('hex');
    expect(hex(a.lockingScript)).not.toBe(hex(b.lockingScript));
    expect(hex(b.lockingScript)).not.toBe(hex(c.lockingScript));
    expect(hex(a.lockingScript)).not.toBe(hex(c.lockingScript));
  });
});

describe('buildSnapshotAnchorBatch × L13: carrier flows through batch builder', () => {
  test('every plan in the batch uses the shared carrier choice', () => {
    const cells = [snapshotCell(1), snapshotCell(2), snapshotCell(3)];
    const plans = buildSnapshotAnchorBatch(cells, {
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      anchorSats: 1n,
      startIndex: 100n,
      carrier: 'op_drop_p2pkh',
    });
    expect(plans.length).toBe(3);
    for (const plan of plans) {
      expect(plan.carrier).toBe('op_drop_p2pkh');
      const parsed = parseDataCarrier(plan.lockingScript);
      expect(parsed.shape).toBe('op_drop_p2pkh');
    }
  });

  test('default carrier batch still pushdrops (backward compat)', () => {
    const cells = [snapshotCell(1), snapshotCell(2)];
    const plans = buildSnapshotAnchorBatch(cells, {
      deriver: stubDeriver,
      protocolHash: protoHash(),
      counterparty: counterparty(),
      anchorSats: 1n,
      startIndex: 100n,
    });
    for (const plan of plans) {
      expect(plan.carrier).toBe('pushdrop');
      const parsed = parseDataCarrier(plan.lockingScript);
      expect(parsed.shape).toBe('pushdrop');
    }
  });
});

```
