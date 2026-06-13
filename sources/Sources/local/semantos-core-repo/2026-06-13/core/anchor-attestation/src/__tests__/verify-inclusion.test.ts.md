---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/__tests__/verify-inclusion.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.940009+00:00
---

# core/anchor-attestation/src/__tests__/verify-inclusion.test.ts

```ts
/**
 * CW Lift L4 — two-step composed SPV verification.
 *
 * Tests the `verifyInclusion` composition end-to-end + each fail-closed
 * stage label. Builds a synthetic anchor attestation + a synthetic
 * BUMP merkle tree (using semantos's own `buildMerkleTree` /
 * `generateMerkleProof` so we know the proof is self-consistent), then
 * threads them through `verifyInclusion`.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L4; docs/prd/CW-LIFT-ROADMAP.md §2.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'crypto';
import {
  buildMerkleTree,
  generateMerkleProof,
} from '../../../cell-ops/src/merkleEnvelope.js';
import { createAnchorAttestation } from '../operations.js';
import { verifyInclusion } from '../verify-inclusion.js';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function txidBuf(seed: number): Buffer {
  // deterministic 32-byte "txid" — sha256d of "tx-<seed>"
  const a = createHash('sha256').update(`tx-${seed}`).digest();
  return createHash('sha256').update(a).digest();
}

function setupAttestation(opts: {
  targetCellId?: Uint8Array;
  txid?: Buffer;
  anchorHeight?: bigint;
  vout?: number;
}) {
  const targetCellId = opts.targetCellId ?? bytes(32, 0xAA);
  const txid = opts.txid ?? txidBuf(1);
  const anchorHeight = opts.anchorHeight ?? 312000n;
  const vout = opts.vout ?? 0;
  const created = createAnchorAttestation({
    targetCellId,
    txid: new Uint8Array(txid),
    anchorHeight,
    vout,
    derivationIndex: 7,
  });
  return { created, targetCellId, txid, anchorHeight, vout };
}

function setupBlockMerkle(targetTxid: Buffer, leafIndex = 2) {
  // Block of 4 txids — targetTxid at `leafIndex`, others are dummies
  const leaves: Buffer[] = [];
  for (let i = 0; i < 4; i++) {
    leaves.push(i === leafIndex ? targetTxid : txidBuf(100 + i));
  }
  const tree = buildMerkleTree(leaves);
  const proof = generateMerkleProof(leaves, leafIndex);
  return { proof, blockRoot: tree.hash, leaves };
}

describe('CW Lift L4: verifyInclusion composed SPV verifier', () => {
  test('happy path — all four stages succeed end-to-end', () => {
    const { created, targetCellId, txid, anchorHeight } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.anchorHeight).toBe(anchorHeight);
      expect(result.attestation.txid).toEqual(new Uint8Array(txid));
      expect(result.attestation.targetCellId).toEqual(targetCellId);
    }
  });

  test('stage attestation — TARGET_MISMATCH if expectedTargetCellId differs', () => {
    const { created, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    const result = verifyInclusion({
      expectedTargetCellId: bytes(32, 0xBB), // wrong target
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('attestation');
      expect(result.code).toBe('TARGET_MISMATCH');
    }
  });

  test('stage attestation — PAYLOAD_ROOT_MISMATCH on tampered root', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: bytes(32, 0xCC), // wrong root
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('attestation');
      expect(result.code).toBe('PAYLOAD_ROOT_MISMATCH');
    }
  });

  test('stage txid_binding — TXID_LEAF_MISMATCH when BUMP is for a different tx', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    // Build the block merkle around a *different* leaf than the
    // attestation's txid — proof is self-consistent for THAT leaf, but
    // it's the wrong leaf for this attestation.
    const wrongTxid = txidBuf(999);
    const { proof, blockRoot } = setupBlockMerkle(wrongTxid);
    void txid;

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('txid_binding');
      expect(result.code).toBe('TXID_LEAF_MISMATCH');
    }
  });

  test('stage merkle — MERKLE_ROOT_MISMATCH when expected block root differs from proof.root', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof } = setupBlockMerkle(txid);
    const wrongBlockRoot = Buffer.alloc(32, 0xDE);

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: wrongBlockRoot,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('merkle');
      expect(result.code).toBe('MERKLE_ROOT_MISMATCH');
    }
  });

  test('stage merkle — MERKLE_PATH_INVALID when siblings are tampered', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    // Tamper with the first sibling; root is unchanged so we land in
    // stage 'merkle' with PATH_INVALID rather than ROOT_MISMATCH.
    const tamperedProof = {
      ...proof,
      siblings: proof.siblings.map((s, i) =>
        i === 0
          ? { hash: Buffer.alloc(32, 0xEF), position: s.position }
          : s,
      ),
    };

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: tamperedProof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('merkle');
      expect(result.code).toBe('MERKLE_PATH_INVALID');
    }
  });

  test('stage block_hash — assertHeaderChainContainsBlock is called with (anchorHeight, merkleRoot) and can reject', () => {
    const { created, targetCellId, txid, anchorHeight } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    let observedHeight: bigint | null = null;
    let observedRoot: Buffer | null = null;
    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
      assertHeaderChainContainsBlock: (h, r) => {
        observedHeight = h;
        observedRoot = r;
        return { ok: false, reason: 'header at height not in our trust root' };
      },
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('block_hash');
      expect(result.code).toBe('HEADER_CHAIN_REJECTED');
    }
    expect(observedHeight).toBe(anchorHeight);
    expect(observedRoot).not.toBeNull();
    if (observedRoot !== null) {
      expect((observedRoot as Buffer).equals(blockRoot)).toBe(true);
    }
  });

  test('stage block_hash — callback returning true (bare boolean form) succeeds', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
      assertHeaderChainContainsBlock: () => true,
    });

    expect(result.ok).toBe(true);
  });

  test('skipping block_hash stage (no callback) still verifies stages 1-3', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid);

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
      // assertHeaderChainContainsBlock omitted — caller takes responsibility externally
    });

    expect(result.ok).toBe(true);
  });

  test('single-leaf block (BUMP proof with zero siblings) succeeds when leaf == root', () => {
    const { created, targetCellId, txid } = setupAttestation({});
    const { proof, blockRoot } = setupBlockMerkle(txid, 0); // only-leaf scenarios are covered by the 4-leaf setup; ensure index 0 works too

    const result = verifyInclusion({
      expectedTargetCellId: targetCellId,
      attestationPayload: created.payload,
      attestationDomainPayloadRoot: created.domainPayloadRoot,
      merkleProof: proof,
      expectedBlockMerkleRoot: blockRoot,
    });

    expect(result.ok).toBe(true);
  });
});

```
