---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/__tests__/verify-against-chain.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.940313+00:00
---

# core/anchor-attestation/src/__tests__/verify-against-chain.test.ts

```ts
/**
 * Tests for the verifyAnchorAttestationInclusion wrapper — first
 * consumer of L4 verifyInclusion.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L4.
 *
 * The wrapper layers on the existing verifyInclusion test fixtures
 * (synthetic anchor attestation + synthetic block merkle proof) plus
 * a TrustedHeaderChain backing the `block_hash` stage.
 *
 * Covers:
 *   - Happy path: in-memory chain returns matching merkle root,
 *     verifyInclusion runs cleanly, wrapper returns the resolved
 *     BlockHeader.
 *   - block_hash stage HEADER_NOT_IN_CHAIN — chain has no entry at
 *     the attestation's claimed height.
 *   - block_hash stage failure when chain's merkle root differs from
 *     the BUMP proof's root (chain says "wrong block at this height").
 *   - Stage 1 attestation failures still propagate (TARGET_MISMATCH,
 *     PAYLOAD_ROOT_MISMATCH).
 *   - InMemoryHeaderChain enforces bigint height + 32B merkle root.
 *   - Async TrustedHeaderChain (returning a Promise) works.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'crypto';
import {
  buildMerkleTree,
  generateMerkleProof,
} from '../../../cell-ops/src/merkleEnvelope.js';
import { createAnchorAttestation } from '../operations.js';
import {
  InMemoryHeaderChain,
  verifyAnchorAttestationInclusion,
  type BlockHeader,
  type TrustedHeaderChain,
} from '../verify-against-chain.js';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function txidBuf(seed: number): Buffer {
  const a = createHash('sha256').update(`tx-${seed}`).digest();
  return createHash('sha256').update(a).digest();
}

function setupFixture(opts: {
  targetCellId?: Uint8Array;
  txid?: Buffer;
  anchorHeight?: bigint;
  leafIndex?: number;
} = {}) {
  const targetCellId = opts.targetCellId ?? bytes(32, 0xAA);
  const txid = opts.txid ?? txidBuf(1);
  const anchorHeight = opts.anchorHeight ?? 312000n;
  const leafIndex = opts.leafIndex ?? 2;

  const created = createAnchorAttestation({
    targetCellId,
    txid: new Uint8Array(txid),
    anchorHeight,
    vout: 0,
    derivationIndex: 7,
  });

  // Build a 4-leaf block with our txid at leafIndex
  const leaves: Buffer[] = [];
  for (let i = 0; i < 4; i++) {
    leaves.push(i === leafIndex ? txid : txidBuf(100 + i));
  }
  const tree = buildMerkleTree(leaves);
  const proof = generateMerkleProof(leaves, leafIndex);

  return {
    created,
    targetCellId,
    txid,
    anchorHeight,
    proof,
    blockRoot: tree.hash,
  };
}

describe('verifyAnchorAttestationInclusion — happy path', () => {
  test('end-to-end verification against an in-memory trusted chain', async () => {
    const fx = setupFixture({});
    const chain = new InMemoryHeaderChain();
    chain.add({
      height: fx.anchorHeight,
      merkleRoot: fx.blockRoot,
      blockHash: Buffer.alloc(32, 0xDE),
    });

    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: chain,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.anchorHeight).toBe(fx.anchorHeight);
      expect(result.attestation.txid).toEqual(new Uint8Array(fx.txid));
      expect(result.header.height).toBe(fx.anchorHeight);
      expect(result.header.merkleRoot.equals(fx.blockRoot)).toBe(true);
    }
  });

  test('result.header carries the same merkleRoot the proof walked to', async () => {
    const fx = setupFixture({ anchorHeight: 700000n });
    const chain = new InMemoryHeaderChain();
    chain.add({ height: 700000n, merkleRoot: fx.blockRoot });
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: chain,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.header.merkleRoot.equals(fx.proof.root)).toBe(true);
    }
  });
});

describe('verifyAnchorAttestationInclusion — block_hash stage', () => {
  test('HEADER_NOT_IN_CHAIN when chain returns null at anchor_height', async () => {
    const fx = setupFixture({});
    const chain = new InMemoryHeaderChain();
    // No headers added.
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: chain,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('block_hash');
      expect(result.code).toBe('HEADER_NOT_IN_CHAIN');
    }
  });

  test('chain has WRONG merkle root at the anchor height → fails at merkle stage', async () => {
    const fx = setupFixture({});
    const chain = new InMemoryHeaderChain();
    // Right height; wrong merkle root.
    chain.add({
      height: fx.anchorHeight,
      merkleRoot: Buffer.alloc(32, 0xFA),
    });
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: chain,
    });
    expect(result.ok).toBe(false);
    // The chain returned a root; verifyInclusion's merkle stage rejects
    // because proof.root !== expectedBlockMerkleRoot.
    if (!result.ok) {
      expect(result.stage).toBe('merkle');
      expect(result.code).toBe('MERKLE_ROOT_MISMATCH');
    }
  });

  test('HEADER_CHAIN_LOOKUP_FAILED when chain throws', async () => {
    const fx = setupFixture({});
    const failingChain: TrustedHeaderChain = {
      getHeaderByHeight: () => {
        throw new Error('simulated header-store unavailable');
      },
    };
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: failingChain,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('block_hash');
      expect(result.code).toBe('HEADER_CHAIN_LOOKUP_FAILED');
      expect(result.message).toContain('simulated header-store unavailable');
    }
  });
});

describe('verifyAnchorAttestationInclusion — stage 1 failures still propagate', () => {
  test('TARGET_MISMATCH propagates through wrapper', async () => {
    const fx = setupFixture({});
    const chain = new InMemoryHeaderChain();
    chain.add({ height: fx.anchorHeight, merkleRoot: fx.blockRoot });
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: bytes(32, 0xBB), // wrong target
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: chain,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('attestation');
      expect(result.code).toBe('TARGET_MISMATCH');
    }
  });

  test('PAYLOAD_ROOT_MISMATCH propagates through wrapper', async () => {
    const fx = setupFixture({});
    const chain = new InMemoryHeaderChain();
    chain.add({ height: fx.anchorHeight, merkleRoot: fx.blockRoot });
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: bytes(32, 0xCC), // wrong root
      merkleProof: fx.proof,
      trustedChain: chain,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('attestation');
      expect(result.code).toBe('PAYLOAD_ROOT_MISMATCH');
    }
  });
});

describe('verifyAnchorAttestationInclusion — async TrustedHeaderChain', () => {
  test('async chain returning a Promise<BlockHeader> works', async () => {
    const fx = setupFixture({});
    const asyncChain: TrustedHeaderChain = {
      getHeaderByHeight: async (height: bigint) => {
        // Simulate async fetch
        await new Promise((resolve) => setTimeout(resolve, 0));
        if (height === fx.anchorHeight) {
          return { height, merkleRoot: fx.blockRoot };
        }
        return null;
      },
    };
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: asyncChain,
    });
    expect(result.ok).toBe(true);
  });

  test('async chain returning Promise<null> fails cleanly', async () => {
    const fx = setupFixture({});
    const asyncChain: TrustedHeaderChain = {
      getHeaderByHeight: async () => null,
    };
    const result = await verifyAnchorAttestationInclusion({
      expectedTargetCellId: fx.targetCellId,
      attestationPayload: fx.created.payload,
      attestationDomainPayloadRoot: fx.created.domainPayloadRoot,
      merkleProof: fx.proof,
      trustedChain: asyncChain,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('block_hash');
      expect(result.code).toBe('HEADER_NOT_IN_CHAIN');
    }
  });
});

describe('InMemoryHeaderChain — reference impl', () => {
  test('add + lookup round-trip', () => {
    const chain = new InMemoryHeaderChain();
    const header: BlockHeader = {
      height: 312000n,
      merkleRoot: Buffer.alloc(32, 0xAB),
    };
    chain.add(header);
    expect(chain.size()).toBe(1);
    const got = chain.getHeaderByHeight(312000n);
    expect(got).not.toBeNull();
    if (got !== null) {
      expect(got.height).toBe(312000n);
      expect(got.merkleRoot.equals(header.merkleRoot)).toBe(true);
    }
  });

  test('returns null for unknown height', () => {
    const chain = new InMemoryHeaderChain();
    expect(chain.getHeaderByHeight(999n)).toBeNull();
  });

  test('rejects non-bigint height', () => {
    const chain = new InMemoryHeaderChain();
    expect(() =>
      chain.add({ height: 312000 as unknown as bigint, merkleRoot: Buffer.alloc(32) }),
    ).toThrow('bigint');
  });

  test('rejects non-32B merkleRoot', () => {
    const chain = new InMemoryHeaderChain();
    expect(() =>
      chain.add({ height: 1n, merkleRoot: Buffer.alloc(31) }),
    ).toThrow('32B');
    expect(() =>
      chain.add({ height: 1n, merkleRoot: Buffer.alloc(33) }),
    ).toThrow('32B');
  });

  test('later add() with same height replaces the entry', () => {
    const chain = new InMemoryHeaderChain();
    chain.add({ height: 1n, merkleRoot: Buffer.alloc(32, 0x11) });
    chain.add({ height: 1n, merkleRoot: Buffer.alloc(32, 0x22) });
    expect(chain.size()).toBe(1);
    const got = chain.getHeaderByHeight(1n);
    expect(got?.merkleRoot.equals(Buffer.alloc(32, 0x22))).toBe(true);
  });
});

```
