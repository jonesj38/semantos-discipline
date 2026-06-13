---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/disclosure-authoriser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.639367+00:00
---

# cartridges/tessera/brain/src/disclosure-authoriser.ts

```ts
/**
 * Tessera disclosure authoriser — L9 consumer composing with L8.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L8 (per-field intra-tx Merkle) + L9
 *   (scoped-disclosure signed envelope).
 *
 * What this does:
 *   Bridges tessera's existing field-tree adapter (#832 —
 *   `field-tree-adapter.ts`) with the L9 envelope primitive (#842 —
 *   `@semantos/protocol-types/disclosure`). The producer of a tessera
 *   cell (bottle, care-event, etc.) can call ONE method to authorise
 *   disclosure of a SPECIFIC field to a SPECIFIC verifier (consumer,
 *   retailer, auditor) for a SPECIFIC duration.
 *
 * Care-chain scenarios this enables:
 *   - CONSUMER scanning a bottle's QR receives an envelope authorising
 *     them to see `origin`, `vintage`, `certifications` — not
 *     `costBasisCents`, `internalSku`, `distributorMarginPct`.
 *   - RETAILER receiving a shipment cell gets envelopes for `lotId` +
 *     `batchId` + `expectedArrival` — not producer margins.
 *   - AUDITOR walking the chain of custody receives envelopes per
 *     care-event with longer expiries for compliance review.
 *
 * Greenfield discipline (TESSERA-CARTRIDGE.md §0.1 #2 +
 * tests/gates/tessera-adapter-consumption.test.ts):
 *   This module accesses substrate ONLY through
 *   `@semantos/protocol-types/*` — no @bsv/sdk, no @plexus/vendor-sdk,
 *   no relative-path escapes from cartridges/tessera.
 *
 * Signing seam — the cartridge does NOT hold private keys. Producers
 * supply a `DisclosureSigner` callback at construction time. The
 * callback is responsible for computing the signature over the
 * preimage (typically backed by IdentityAdapter or a brain-side
 * signer); this cartridge only knows about the preimage + the
 * envelope-bind step.
 */

import {
  canonicalDisclosureEnvelopePreimage,
  verifyDisclosureEnvelope,
  ENGAGEMENT_ID_SIZE,
  NONCE_SIZE,
  NOTE_ID_SIZE,
  VERIFIER_ID_SIZE,
  type DisclosureEnvelope,
  type SignedDisclosureEnvelope,
  type VerifyDisclosureEnvelopeResult,
} from '@semantos/protocol-types/disclosure';
import type { FieldDisclosureProof } from '@semantos/protocol-types/field-tree';
import {
  buildTesseraFieldTree,
  discloseTesseraField,
  verifyTesseraFieldDisclosure,
} from './field-tree-adapter.js';
import type { TesseraCellType } from './store-adapter.js';

// ── Signing seam ─────────────────────────────────────────────────

/**
 * Caller-supplied signer for L9 envelopes. Receives the canonical
 * preimage bytes; returns `{ signature, issuerPubKeyHex }`.
 *
 * Tessera's greenfield discipline forbids importing @bsv/sdk directly,
 * so the actual ECDSA call happens at a layer the consumer controls
 * (substrate-side via IdentityAdapter, brain-side signer, or vendor-sdk
 * users supplying their own callback). The cartridge sees only the
 * abstract signer.
 */
export type DisclosureSigner = (
  preimage: Uint8Array,
) => Promise<{ signature: Uint8Array; issuerPubKeyHex: string }>;

// ── Authorise (producer side) ────────────────────────────────────

export interface AuthoriseTesseraDisclosureInput {
  readonly cellType: TesseraCellType;
  readonly body: unknown;
  readonly noteId: Uint8Array;
  readonly fieldLabel: string;
  readonly verifierId: Uint8Array;
  readonly engagementId: Uint8Array;
  readonly purpose: string;
  readonly expiry: bigint;
  readonly nonce: Uint8Array;
}

/**
 * Authorise disclosure of ONE field of a tessera cell. Composes:
 *   1. Compute L8 field-tree leaf commitment via discloseTesseraField
 *   2. Build L9 envelope binding (noteId, fieldLabel, leafCommitment, …)
 *   3. Sign the canonical preimage via the supplied DisclosureSigner
 *   4. Return SignedDisclosureEnvelope
 */
export async function authoriseTesseraDisclosure(
  input: AuthoriseTesseraDisclosureInput,
  signer: DisclosureSigner,
): Promise<SignedDisclosureEnvelope> {
  assertFixedSize('noteId', input.noteId, NOTE_ID_SIZE);
  assertFixedSize('verifierId', input.verifierId, VERIFIER_ID_SIZE);
  assertFixedSize('engagementId', input.engagementId, ENGAGEMENT_ID_SIZE);
  assertFixedSize('nonce', input.nonce, NONCE_SIZE);

  // Compute the L8 leaf commitment — same bytes the auditor's proof
  // will carry. Bind into the envelope so envelope.leafCommitment ==
  // proof.commitment after the auditor receives both.
  const proof = discloseTesseraField(input.cellType, input.body, input.fieldLabel);

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

  const preimage = canonicalDisclosureEnvelopePreimage(envelope);
  const { signature, issuerPubKeyHex } = await signer(preimage);

  return {
    envelope: freezeEnvelope(envelope),
    signature: copyBytes(signature),
    issuerPubKeyHex,
  };
}

// ── Verify (consumer / auditor side, composed) ────────────────────

export interface VerifyAuthorisedTesseraDisclosureInput {
  readonly cellType: TesseraCellType;
  readonly envelope: SignedDisclosureEnvelope;
  readonly proof: FieldDisclosureProof;
  /** The trusted L8 field-tree root. Consumer received it out-of-band
   *  (cell-header pin, producer-signed manifest, etc.). */
  readonly trustedRoot: Uint8Array;
  /** Verifier's own pubkey hex — must match envelope.verifierId. */
  readonly verifierPubKeyHex: string;
  /** Current time as ms-since-epoch. */
  readonly nowMs: bigint;
}

export type VerifyAuthorisedTesseraDisclosureResult =
  | { ok: true; envelope: DisclosureEnvelope }
  | {
      ok: false;
      stage: 'envelope' | 'leaf_pin' | 'field_tree';
      code: string;
      message: string;
    };

/**
 * Compose envelope-verify + field-tree-verify into one call. Returns
 * `ok: true` only when:
 *   1. envelope signature verifies under issuerPubKeyHex
 *   2. envelope.verifierId === verifierPubKeyHex
 *   3. nowMs < envelope.expiry
 *   4. envelope.leafCommitment === proof.commitment (L8/L9 pin)
 *   5. proof's merkle path walks to trustedRoot
 *
 * Never throws.
 */
export function verifyAuthorisedTesseraDisclosure(
  input: VerifyAuthorisedTesseraDisclosureInput,
): VerifyAuthorisedTesseraDisclosureResult {
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

  const proofOk = verifyTesseraFieldDisclosure(
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
        'L8 field-tree disclosure proof did not verify against trustedRoot.',
    };
  }
  return { ok: true, envelope: envResult.envelope };
}

// ── Convenience: bundle envelope + proof + root ─────────────────

/**
 * Producer-side convenience: return the COMPLETE bundle the verifier
 * needs — envelope, L8 proof, and the tree root (so the verifier can
 * anchor against it).
 *
 * Useful for "ship one packet to the consumer-app" workflows like
 * QR-scan / NFC bump.
 */
export async function buildFullAuthorisedTesseraDisclosure(
  input: AuthoriseTesseraDisclosureInput,
  signer: DisclosureSigner,
): Promise<{
  envelope: SignedDisclosureEnvelope;
  proof: FieldDisclosureProof;
  treeRoot: Uint8Array;
}> {
  const tree = buildTesseraFieldTree(input.cellType, input.body);
  const envelope = await authoriseTesseraDisclosure(input, signer);
  const proof = discloseTesseraField(input.cellType, input.body, input.fieldLabel);
  return { envelope, proof, treeRoot: tree.root };
}

// ── Helpers ──────────────────────────────────────────────────────

function assertFixedSize(name: string, b: Uint8Array, expected: number): void {
  if (b.byteLength !== expected) {
    throw new Error(
      `tessera disclosure authoriser: ${name} must be ${expected} bytes (got ${b.byteLength})`,
    );
  }
}

function freezeEnvelope(env: DisclosureEnvelope): DisclosureEnvelope {
  return Object.freeze({
    noteId: copyBytes(env.noteId),
    fieldLabel: env.fieldLabel,
    leafCommitment: copyBytes(env.leafCommitment),
    verifierId: copyBytes(env.verifierId),
    engagementId: copyBytes(env.engagementId),
    purpose: env.purpose,
    expiry: env.expiry,
    nonce: copyBytes(env.nonce),
  });
}

function copyBytes(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.byteLength);
  out.set(b);
  return out;
}

```
