---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/disclosure-authoriser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.504850+00:00
---

# cartridges/oddjobz/brain/src/cell-types/disclosure-authoriser.ts

```ts
/**
 * Oddjobz disclosure authoriser — L9 consumer composing with L8.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L8 (per-field intra-tx Merkle) + L9
 *   (scoped-disclosure signed envelope).
 *
 * What this does:
 *   Bridges oddjobz's existing field-tree adapter (#827 —
 *   `field-tree-adapter.ts`) with the L9 envelope primitive (#842 —
 *   `@semantos/protocol-types/disclosure`). The producer of an oddjobz
 *   cell can call ONE method:
 *
 *     authoriseFieldDisclosure({
 *       cellType, value, cellId, fieldLabel,
 *       verifierPubKeyHex, engagementId, purpose, expiry, nonce
 *     }, issuerPriv)
 *
 *   and get back a `SignedDisclosureEnvelope` whose `leafCommitment`
 *   is bound to the EXACT field-tree leaf the auditor will receive
 *   via `discloseCellField(...)`. The auditor's `verifyAuthorisedFieldDisclosure`
 *   composes envelope-check + L8 verify in one call.
 *
 * Why oddjobz uses the L9 module directly (not via the tessera-style
 * subpath import): oddjobz's L8 adapter (`field-tree-adapter.ts`)
 * already imports via relative path to keep the workspace-resolution
 * surface predictable; L9 follows the same convention.
 *
 * Composition flow:
 *
 *   producer (operator) holds invoice cell + issuer private key
 *     │
 *     ├─ buildCellFieldTree(invoiceCellType, value) → tree
 *     ├─ authoriseFieldDisclosure({ ..., fieldLabel: 'amount',
 *     │     verifierPubKeyHex: auditor, expiry: in 7d })
 *     │   → SignedDisclosureEnvelope
 *     ├─ discloseCellField(invoiceCellType, value, 'amount')
 *     │   → FieldDisclosureProof
 *     │
 *     └─ ship (envelope + proof + trusted tree.root) to auditor
 *
 *   auditor receives all three artifacts
 *     │
 *     └─ verifyAuthorisedFieldDisclosure({ envelope, proof, tree.root,
 *           verifierPubKeyHex: my own pub, nowMs })
 *         → ok (envelope sig + verifier-id + expiry + leaf-commitment-pin
 *               + L8 merkle path + root match)
 */

import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  signDisclosureEnvelope,
  verifyDisclosureEnvelope,
  ENGAGEMENT_ID_SIZE,
  NONCE_SIZE,
  NOTE_ID_SIZE,
  VERIFIER_ID_SIZE,
  type DisclosureEnvelope,
  type SignedDisclosureEnvelope,
  type VerifyDisclosureEnvelopeResult,
} from '../../../../../core/protocol-types/src/disclosure/index.js';
import {
  buildCellFieldTree,
  discloseCellField,
  verifyCellFieldDisclosure,
} from './field-tree-adapter.js';
import type { CellTypeDef } from './cell-type.js';
import type { FieldDisclosureProof } from '../../../../../core/protocol-types/src/field-tree/index.js';

// ── Authorise (producer side) ────────────────────────────────────

export interface AuthoriseFieldDisclosureInput<T> {
  /** The oddjobz cell-type definition (invoice, customer, quote, …). */
  readonly cellType: CellTypeDef<T>;
  /** The typed cell value whose field is being authorised. */
  readonly value: T;
  /** 32B identifier of the cell — the L9 envelope's `noteId`. Typically
   *  the cell's instance hash; callers choose the convention. */
  readonly noteId: Uint8Array;
  /** Which top-level canonical field to authorise. Must be present in
   *  the cell's `toCanonical(value)` output. */
  readonly fieldLabel: string;
  /** 33B SEC1 compressed pubkey of the only verifier this envelope
   *  authorises. */
  readonly verifierId: Uint8Array;
  /** 32B engagement scope (audit-engagement, session, hat). */
  readonly engagementId: Uint8Array;
  /** Caller-defined purpose tag (e.g. "tax-audit", "compliance-review"). */
  readonly purpose: string;
  /** Expiry as ms-since-epoch (bigint). */
  readonly expiry: bigint;
  /** 16B random nonce (caller supplies; replays are prevented at the
   *  envelope-level by this + verifier+purpose+expiry). */
  readonly nonce: Uint8Array;
}

/**
 * Producer-side: authorise disclosure of ONE field of an oddjobz cell
 * to a specific verifier.
 *
 * Computes the L8 leaf commitment internally (via
 * `discloseCellField → proof.commitment`) and binds it into the L9
 * envelope's `leafCommitment` field. The matching `discloseCellField`
 * call gives the auditor the proof whose `commitment` matches.
 */
export function authoriseFieldDisclosure<T>(
  input: AuthoriseFieldDisclosureInput<T>,
  issuerPriv: PrivateKey,
): SignedDisclosureEnvelope {
  assertFixedSize('noteId', input.noteId, NOTE_ID_SIZE);
  assertFixedSize('verifierId', input.verifierId, VERIFIER_ID_SIZE);
  assertFixedSize('engagementId', input.engagementId, ENGAGEMENT_ID_SIZE);
  assertFixedSize('nonce', input.nonce, NONCE_SIZE);

  // The leaf commitment is what the auditor will receive via the L8
  // disclosure proof. We compute it here (via discloseCellField,
  // which validates the label exists) so the envelope binds to the
  // exact byte sequence the auditor verifies.
  const proof = discloseCellField(input.cellType, input.value, input.fieldLabel);

  const envelope: DisclosureEnvelope = {
    noteId: input.noteId,
    fieldLabel: input.fieldLabel,
    leafCommitment: proof.commitment,
    verifierId: input.verifierId,
    engagementId: input.engagementId,
    purpose: input.purpose,
    expiry: input.expiry,
    nonce: input.nonce,
  };
  return signDisclosureEnvelope(envelope, issuerPriv);
}

// ── Verify (auditor side, composed) ──────────────────────────────

export interface VerifyAuthorisedFieldDisclosureInput<T> {
  readonly cellType: CellTypeDef<T>;
  readonly envelope: SignedDisclosureEnvelope;
  readonly proof: FieldDisclosureProof;
  /** The trusted L8 field-tree root (typically pinned in the cell
   *  header's domainPayloadRoot or transmitted out-of-band). */
  readonly trustedRoot: Uint8Array;
  /** Auditor's own pubkey hex — must match envelope.verifierId. */
  readonly verifierPubKeyHex: string;
  /** Current time as ms-since-epoch. */
  readonly nowMs: bigint;
}

export type VerifyAuthorisedFieldDisclosureResult =
  | { ok: true; envelope: DisclosureEnvelope }
  | {
      ok: false;
      stage: 'envelope' | 'leaf_pin' | 'field_tree';
      code: string;
      message: string;
    };

/**
 * Auditor-side: verify BOTH the L9 envelope AND the L8 field-tree proof
 * in one composed call. Returns success only when:
 *
 *   1. Envelope signature verifies under its issuer pubkey
 *   2. envelope.verifierId === verifierPubKeyHex
 *   3. nowMs < envelope.expiry
 *   4. envelope.leafCommitment === proof.commitment (L8/L9 pin)
 *   5. proof's merkle path walks to trustedRoot
 *
 * Stage labels tell the caller WHICH check failed for diagnostics.
 * Never throws.
 */
export function verifyAuthorisedFieldDisclosure<T>(
  input: VerifyAuthorisedFieldDisclosureInput<T>,
): VerifyAuthorisedFieldDisclosureResult {
  // Stage 1 + 4: envelope check, including the leaf-commitment pin
  // against the L8 proof we received.
  const envResult: VerifyDisclosureEnvelopeResult = verifyDisclosureEnvelope({
    signed: input.envelope,
    verifierPubKeyHex: input.verifierPubKeyHex,
    nowMs: input.nowMs,
    expectedLeafCommitment: input.proof.commitment,
  });
  if (!envResult.ok) {
    return {
      ok: false,
      stage:
        envResult.code === 'LEAF_COMMITMENT_MISMATCH' ? 'leaf_pin' : 'envelope',
      code: envResult.code,
      message: envResult.message,
    };
  }

  // Stage 2: field-tree proof walks to the trusted root.
  const proofOk = verifyCellFieldDisclosure(
    input.cellType,
    input.proof,
    input.trustedRoot,
  );
  if (!proofOk) {
    return {
      ok: false,
      stage: 'field_tree',
      code: 'FIELD_TREE_VERIFY_FAILED',
      message:
        'L8 field-tree disclosure proof did not verify against trustedRoot ' +
        '(leaf hash, sibling path, schemaFingerprint, or trusted root mismatch).',
    };
  }

  return { ok: true, envelope: envResult.envelope };
}

// ── Convenience: bind both into one builder ─────────────────────

/**
 * Producer-side convenience: returns BOTH the signed envelope AND the
 * matching L8 proof in one call, plus the field-tree root the auditor
 * needs to anchor verification.
 *
 * Useful for the "happy path" where the producer wants to ship the
 * complete bundle in one shot.
 */
export function buildFullAuthorisedDisclosure<T>(
  input: AuthoriseFieldDisclosureInput<T>,
  issuerPriv: PrivateKey,
): {
  envelope: SignedDisclosureEnvelope;
  proof: FieldDisclosureProof;
  treeRoot: Uint8Array;
} {
  const tree = buildCellFieldTree(input.cellType, input.value);
  const envelope = authoriseFieldDisclosure(input, issuerPriv);
  const proof = discloseCellField(input.cellType, input.value, input.fieldLabel);
  return { envelope, proof, treeRoot: tree.root };
}

// ── Helpers ──────────────────────────────────────────────────────

function assertFixedSize(name: string, b: Uint8Array, expected: number): void {
  if (b.byteLength !== expected) {
    throw new Error(
      `oddjobz disclosure authoriser: ${name} must be ${expected} bytes (got ${b.byteLength})`,
    );
  }
}

```
