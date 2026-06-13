---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/operations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.939379+00:00
---

# core/anchor-attestation/src/operations.ts

```ts
/**
 * Anchor-attestation operations — `createAnchorAttestation` and
 * `verifyAnchor`. RM-042.
 *
 * These functions live above the cell-encoding layer:
 *   - `createAnchorAttestation` returns the structured record + its
 *     encoded payload bytes + the computed `domainPayloadRoot`. It does
 *     NOT call `cellPacker` — the host of an anchor cell decides how
 *     to assemble the surrounding cell shell (often a BUMP/BEEF
 *     continuation; see `core/cell-ops/src/packer/`).
 *   - `verifyAnchor` checks structural invariants of an attestation
 *     against an expected target cell-id and recomputes the domain
 *     payload root to confirm it matches.
 *
 * BSV BUMP/BEEF verification (does the on-chain TXID actually exist
 * with this output spend?) lives separately in `core/cell-ops`'s
 * BUMP/BEEF section logic — see `parseAtomicBeefHeader`,
 * `parseBumpHeader`. This package only handles the attestation
 * cell's payload-level guarantees.
 *
 * Schema is v2 (see core/plexus-schema-registry/src/schemas/
 * anchor-attestation.ts for the layout rationale): `bumpHash` retired,
 * `anchor_height: u64` promoted to a first-class queryable field.
 */
import {
  anchorAttestationSchemaV2,
  computeDomainPayloadRoot,
  decodePayload,
  encodePayload,
} from '@semantos/plexus-schema-registry';
import type { AnchorAttestation, VerifyAnchorResult } from './types.js';

/** Inputs to `createAnchorAttestation` — the same fields as
 *  `AnchorAttestation` but allows construction without a frozen
 *  `readonly` view. */
export interface CreateAnchorAttestationInput {
  targetCellId: Uint8Array;
  txid: Uint8Array;
  /** BSV block height of the anchor TX. `bigint` because `u64` is
   *  unsafe in JS `number`. */
  anchorHeight: bigint;
  vout: number;
  derivationIndex: number;
}

export interface CreatedAttestation {
  /** Structured record (read-only view). */
  attestation: AnchorAttestation;
  /** Bytes encoded under `anchorAttestationSchemaV2`. Ready to be
   *  written as the payload of the surrounding anchor cell. */
  payload: Uint8Array;
  /** 32B SHA-256 root of `payload`. Belongs in the anchor cell's
   *  header `domainPayloadRoot` slot. */
  domainPayloadRoot: Uint8Array;
}

/**
 * Build an anchor-attestation. Returns the structured record + its
 * encoded payload bytes + the computed `domainPayloadRoot` (which the
 * caller writes at offset 224 of the surrounding cell's header via
 * `CellHeader.domainPayloadRoot`).
 */
export function createAnchorAttestation(
  input: CreateAnchorAttestationInput,
): CreatedAttestation {
  assertFieldLengths(input);
  const attestation: AnchorAttestation = {
    targetCellId: copyBytes(input.targetCellId),
    txid: copyBytes(input.txid),
    anchorHeight: input.anchorHeight,
    vout: input.vout,
    derivationIndex: input.derivationIndex,
  };
  const values = {
    targetCellId: attestation.targetCellId,
    txid: attestation.txid,
    anchor_height: attestation.anchorHeight,
    vout: attestation.vout,
    derivationIndex: attestation.derivationIndex,
  };
  const payload = encodePayload(anchorAttestationSchemaV2, values);
  const domainPayloadRoot = computeDomainPayloadRoot(
    anchorAttestationSchemaV2,
    values,
  );
  return { attestation, payload, domainPayloadRoot };
}

/**
 * Verify an anchor attestation:
 *   1. Decode `payload` under the attestation schema.
 *   2. Confirm `attestation.targetCellId == expectedTargetCellId`.
 *   3. Recompute `domainPayloadRoot(schema, decoded)` and require it
 *      to equal the supplied `domainPayloadRoot` byte-for-byte.
 *
 * Does NOT touch the BSV network. Pure structural + cryptographic
 * verification of the attestation's payload self-consistency and its
 * targeting of the expected cell.
 */
export function verifyAnchor(input: {
  expectedTargetCellId: Uint8Array;
  payload: Uint8Array;
  domainPayloadRoot: Uint8Array;
}): VerifyAnchorResult {
  let decoded: Record<string, unknown>;
  try {
    decoded = decodePayload(anchorAttestationSchemaV2, input.payload);
  } catch (e) {
    return {
      ok: false,
      code: 'INVALID_SCHEMA',
      message: `payload did not decode under anchorAttestationSchemaV2: ${(e as Error).message}`,
    };
  }

  const targetCellId = decoded.targetCellId as Uint8Array;
  const txid = decoded.txid as Uint8Array;
  const anchorHeight = decoded.anchor_height as bigint;
  const vout = decoded.vout as number;
  const derivationIndex = decoded.derivationIndex as number;

  if (!bytesEqual(targetCellId, input.expectedTargetCellId)) {
    return {
      ok: false,
      code: 'TARGET_MISMATCH',
      message: `targetCellId mismatch (attestation points to a different cell)`,
    };
  }

  const recomputedRoot = computeDomainPayloadRoot(anchorAttestationSchemaV2, {
    targetCellId,
    txid,
    anchor_height: anchorHeight,
    vout,
    derivationIndex,
  });
  if (!bytesEqual(recomputedRoot, input.domainPayloadRoot)) {
    return {
      ok: false,
      code: 'PAYLOAD_ROOT_MISMATCH',
      message: 'domainPayloadRoot does not match the recomputed digest of the decoded payload',
    };
  }

  return {
    ok: true,
    attestation: { targetCellId, txid, anchorHeight, vout, derivationIndex },
  };
}

// ── Helpers ─────────────────────────────────────────────────────────

const U64_MAX = (1n << 64n) - 1n;

function assertFieldLengths(input: CreateAnchorAttestationInput): void {
  if (input.targetCellId.byteLength !== 32) {
    throw new Error(`createAnchorAttestation: targetCellId must be 32B, got ${input.targetCellId.byteLength}`);
  }
  if (input.txid.byteLength !== 32) {
    throw new Error(`createAnchorAttestation: txid must be 32B, got ${input.txid.byteLength}`);
  }
  if (typeof input.anchorHeight !== 'bigint') {
    throw new Error(`createAnchorAttestation: anchorHeight must be a bigint`);
  }
  if (input.anchorHeight < 0n || input.anchorHeight > U64_MAX) {
    throw new Error(`createAnchorAttestation: anchorHeight must fit in u64 (0..2^64-1)`);
  }
  if (!Number.isInteger(input.vout) || input.vout < 0) {
    throw new Error(`createAnchorAttestation: vout must be a non-negative integer`);
  }
  if (!Number.isInteger(input.derivationIndex) || input.derivationIndex < 0) {
    throw new Error(`createAnchorAttestation: derivationIndex must be a non-negative integer`);
  }
}

function copyBytes(src: Uint8Array): Uint8Array {
  const out = new Uint8Array(src.byteLength);
  out.set(src);
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
