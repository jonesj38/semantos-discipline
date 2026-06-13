---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/verify-inclusion.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.939090+00:00
---

# core/anchor-attestation/src/verify-inclusion.ts

```ts
/**
 * Two-step composed SPV verification for anchor attestations.
 *
 * CW Lift L4 (docs/canon/cw-lift-matrix.yml).
 *
 * Semantos already has every piece needed to verify that an anchor
 * attestation is genuine — payload integrity (`verifyAnchor` in
 * `./operations.ts`), Merkle proof verification (`verifyMerkleProof`
 * in `core/cell-ops/src/merkleEnvelope.ts`), BUMP envelope parsing
 * (`parseBumpHeader` in `core/cell-ops/src/packer/op-packers/pack-bump.ts`),
 * and `AnchorProof` carrying the BRC-10 BUMP hex + block hash
 * (`core/protocol-types/src/anchor.ts`). They were split across three
 * modules; callers had to wire them up themselves.
 *
 * `verifyInclusion` composes them into one fail-closed sequential call:
 *
 *   ┌─ stage 'attestation' ────────────────────────────────────────┐
 *   │ 1. decode attestationPayload under anchor-attestation schema │
 *   │ 2. check attestation.targetCellId == expectedTargetCellId    │
 *   │ 3. recompute domainPayloadRoot, check it matches             │
 *   └──────────────────────────────────────────────────────────────┘
 *                            ↓
 *   ┌─ stage 'txid_binding' ───────────────────────────────────────┐
 *   │ 4. assert merkle.leafHash hashes to attestation.txid         │
 *   │    (the leaf of the block-tree IS the anchor txid)           │
 *   └──────────────────────────────────────────────────────────────┘
 *                            ↓
 *   ┌─ stage 'merkle' ─────────────────────────────────────────────┐
 *   │ 5. walk merkle proof from leaf to root                       │
 *   │ 6. assert computed root == expectedBlockMerkleRoot           │
 *   └──────────────────────────────────────────────────────────────┘
 *                            ↓
 *   ┌─ stage 'block_hash' ─────────────────────────────────────────┐
 *   │ 7. (caller's HeaderChain) — expected block hash matches      │
 *   │    the chain at attestation.anchorHeight                     │
 *   │ NB: this function does NOT fetch headers; the caller passes  │
 *   │ the trusted expectedBlockHash and we compare to the          │
 *   │ AnchorProof.blockHash. HeaderChain lookups live in the       │
 *   │ caller's trust boundary (see L24 — fail-closed SPV inside).  │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * Each stage fails closed and the result carries the stage label so
 * callers can debug which level rejected. The composition is pure —
 * no network, no clock, no random.
 */

import type { MerkleProof } from '../../cell-ops/src/merkleEnvelope.js';
import { verifyMerkleProof } from '../../cell-ops/src/merkleEnvelope.js';
import { verifyAnchor } from './operations.js';
import type { AnchorAttestation } from './types.js';

/**
 * Composed verify-inclusion stage labels. Fail-closed: the first stage
 * that rejects determines the failure. Stages run in order:
 *
 *   attestation  → txid_binding  → merkle  → block_hash
 */
export type VerifyInclusionStage =
  | 'attestation'
  | 'txid_binding'
  | 'merkle'
  | 'block_hash';

export type VerifyInclusionResult =
  | {
      ok: true;
      attestation: AnchorAttestation;
      /** Block height the anchor was mined into. Populated from the
       *  attestation payload (u64, exposed as bigint). */
      anchorHeight: bigint;
    }
  | {
      ok: false;
      stage: VerifyInclusionStage;
      code: string;
      message: string;
    };

export interface VerifyInclusionInput {
  // ── Stage 1: attestation-level (mirrors verifyAnchor) ────────────
  /** 32B cell-id of the target cell whose anchor we're verifying. */
  expectedTargetCellId: Uint8Array;
  /** Encoded attestation payload (anchorAttestationSchemaV2). */
  attestationPayload: Uint8Array;
  /** 32B domainPayloadRoot from the attestation cell's header. */
  attestationDomainPayloadRoot: Uint8Array;

  // ── Stages 2-3: BUMP merkle proof ────────────────────────────────
  /** BUMP merkle proof: leafHash (= the anchor txid) → block root.
   *  `merkle.root` MUST equal the block's merkle root. */
  merkleProof: MerkleProof;
  /** Expected block merkle root (32B Buffer; matches merkleProof.root
   *  on success). Conventionally fetched from the caller's trusted
   *  HeaderChain at the attestation's anchorHeight. */
  expectedBlockMerkleRoot: Buffer;

  // ── Stage 4: block-hash binding (optional, off by default) ───────
  /** If supplied, also assert that the merkle root corresponds to the
   *  expected block hash. The actual headerChain lookup is the caller's
   *  job (see L24 — SPV inside the trust boundary). Pass `undefined`
   *  if the caller checks block hash externally. */
  expectedBlockHash?: string;
  /** Optional callback for the block-hash binding step. If supplied,
   *  it must return true when `merkleRoot` corresponds to a header in
   *  the trusted chain at the attestation's anchorHeight. The default
   *  (when both expectedBlockHash and this are omitted) is to skip
   *  stage 4 — payload + BUMP merkle is verified but the block-hash
   *  binding is the caller's external concern. */
  assertHeaderChainContainsBlock?: (
    anchorHeight: bigint,
    merkleRoot: Buffer,
  ) => boolean | { ok: true } | { ok: false; reason: string };
}

/**
 * Compose the four verification stages into one call. Pure; no I/O.
 *
 * The caller is responsible for fetching:
 *   - the attestation payload + domainPayloadRoot (from the on-chain
 *     anchor attestation cell or the local cell-store)
 *   - the BUMP merkle proof (from `AnchorProof.merkleProof` or the
 *     wire format; deserialise via `core/cell-ops`)
 *   - the expected block merkle root + optional block hash (from the
 *     caller's trusted HeaderChain)
 *
 * What this function guarantees on `ok: true`:
 *   1. The attestation payload decodes cleanly under schema v2.
 *   2. The attestation targets the expected cell.
 *   3. The attestation's `domainPayloadRoot` matches the recomputed
 *      digest of its decoded payload (no tampering).
 *   4. The Merkle leaf hashes to the attestation's claimed txid.
 *   5. The Merkle proof walks to the expected block merkle root.
 *   6. (Optional) The block merkle root is anchored in the trusted
 *      HeaderChain at the attestation's anchorHeight.
 */
export function verifyInclusion(
  input: VerifyInclusionInput,
): VerifyInclusionResult {
  // ── Stage 1: attestation payload (delegates to verifyAnchor) ─────
  const attRes = verifyAnchor({
    expectedTargetCellId: input.expectedTargetCellId,
    payload: input.attestationPayload,
    domainPayloadRoot: input.attestationDomainPayloadRoot,
  });
  if (!attRes.ok) {
    return {
      ok: false,
      stage: 'attestation',
      code: attRes.code,
      message: attRes.message,
    };
  }
  const att = attRes.attestation;

  // ── Stage 2: leaf binding (BUMP leaf == attestation txid) ────────
  if (!bytesEqualUA(uint8(input.merkleProof.leafHash), att.txid)) {
    return {
      ok: false,
      stage: 'txid_binding',
      code: 'TXID_LEAF_MISMATCH',
      message:
        'Merkle proof leaf hash does not match the attestation.txid — the ' +
        'BUMP proof is for a different transaction than the one the ' +
        'attestation claims to anchor.',
    };
  }

  // ── Stage 3: merkle proof walks to expected block root ───────────
  if (!input.merkleProof.root.equals(input.expectedBlockMerkleRoot)) {
    return {
      ok: false,
      stage: 'merkle',
      code: 'MERKLE_ROOT_MISMATCH',
      message:
        `Merkle proof's stated root does not match the expected block ` +
        `merkle root — the BUMP proof is for a different block than ` +
        `expected at this height.`,
    };
  }
  if (
    !verifyMerkleProof(input.merkleProof, input.expectedBlockMerkleRoot)
  ) {
    return {
      ok: false,
      stage: 'merkle',
      code: 'MERKLE_PATH_INVALID',
      message:
        'Merkle proof walk from leaf to root failed — siblings do not ' +
        'compose to the expected root via double-SHA-256.',
    };
  }

  // ── Stage 4: block-hash binding (optional) ───────────────────────
  if (input.assertHeaderChainContainsBlock !== undefined) {
    const ok = input.assertHeaderChainContainsBlock(
      att.anchorHeight,
      input.expectedBlockMerkleRoot,
    );
    const isOk = typeof ok === 'boolean' ? ok : ok.ok;
    if (!isOk) {
      const reason =
        typeof ok === 'object' && !ok.ok ? ok.reason : 'header chain does not contain this block';
      return {
        ok: false,
        stage: 'block_hash',
        code: 'HEADER_CHAIN_REJECTED',
        message: `HeaderChain check failed: ${reason}`,
      };
    }
  }

  return {
    ok: true,
    attestation: att,
    anchorHeight: att.anchorHeight,
  };
}

// ── Helpers ─────────────────────────────────────────────────────────

/** Coerce a Node Buffer (or anything Buffer-shaped) to a Uint8Array view. */
function uint8(b: Buffer | Uint8Array): Uint8Array {
  // Node Buffers are already Uint8Arrays at the prototype-chain level,
  // but TS narrows them differently; this normalises for byte compare.
  if (b instanceof Uint8Array) return b;
  // Defensive: wrap arbitrary array-likes.
  return Uint8Array.from(b as ArrayLike<number>);
}

function bytesEqualUA(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
