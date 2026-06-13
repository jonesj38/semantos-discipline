---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/disclosure/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.896552+00:00
---

# core/protocol-types/src/disclosure/index.ts

```ts
/**
 * Scoped-disclosure signed envelope — L9 (Tier 2).
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L9.
 *   source: prof-faustus/triple-entry-evidence-bsv @ crates/disclosure/src/lib.rs
 *
 * What this does:
 *   Adds the AUTHORISATION layer above L8's field-tree disclosure
 *   primitive. L8 (`field-tree/`) makes per-field disclosure proofs
 *   CHECKABLE — given a proof + a trusted root, anyone can confirm
 *   that `(label, value)` is in the field tree. L9 makes those proofs
 *   AUTHORISED — the issuer signs an envelope that names:
 *
 *     - which note (cell)        — 32B noteId
 *     - which field              — utf-8 label
 *     - which leaf commitment    — 32B H(K_field) = L8 field-leaf hash
 *     - WHO can verify           — 33B verifierId (pubkey)
 *     - in WHAT engagement       — 32B engagementId (caller-defined scope)
 *     - for WHAT purpose         — utf-8 purpose string
 *     - until WHEN               — u64 expiry timestamp (ms since epoch)
 *     - replay nonce             — 16B random nonce
 *
 *   The verifier checks (1) signature is by the expected issuer
 *   pubkey, (2) verifierId matches their own pubkey, (3) expiry has
 *   not passed, (4) the bound leaf commitment matches the L8 proof
 *   they were given. Together with L8's field-tree round-trip, this
 *   gives end-to-end "this auditor was authorised to see THIS field of
 *   THIS cell until THIS time" guarantees.
 *
 * Composition with L8:
 *
 *     ┌─ issuer (invoice owner / bottle producer / etc.) ─────────┐
 *     │  buildFieldTree(schemaFp, fields) → tree                  │
 *     │  signDisclosureEnvelope({                                  │
 *     │    noteId,                  ← cell-id                      │
 *     │    fieldLabel,                                             │
 *     │    leafCommitment: tree.fields[i].commitment,              │
 *     │    verifierId, engagementId, purpose, expiry, nonce        │
 *     │  }, issuerPriv)                                            │
 *     │  → SignedDisclosureEnvelope                                │
 *     └────────────────────────────────────────────────────────────┘
 *                              ↓
 *     ┌─ verifier (auditor / partner / etc.) ──────────────────────┐
 *     │  receives: SignedDisclosureEnvelope + FieldDisclosureProof │
 *     │            + trusted root                                   │
 *     │  step 1: verifyDisclosureEnvelope(env, issuerPub, myPubId, │
 *     │            now) → ok                                       │
 *     │  step 2: verifyFieldDisclosure(proof, trusted root) → ok   │
 *     │  step 3: env.leafCommitment === proof.commitment           │
 *     │  all three pass → disclosed field is authorised + verified │
 *     └────────────────────────────────────────────────────────────┘
 *
 * Signature mechanism:
 *   ECDSA over double-SHA-256 of the canonical envelope preimage,
 *   using @bsv/sdk's PrivateKey/PublicKey (same convention as
 *   anchor-attestation, cell-token-chain, etc. in protocol-types).
 *
 *   Caller-supplied signers can use the `canonicalDisclosureEnvelope
 *   Preimage()` helper to compute the same bytes; the
 *   `signDisclosureEnvelope` default uses @bsv/sdk for convenience.
 */

import { createHash } from 'node:crypto';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import PublicKey from '@bsv/sdk/primitives/PublicKey';
import BSM from '@bsv/sdk/compat/BSM';
import { sha256 } from '@bsv/sdk/primitives/Hash';

// ── Constants ─────────────────────────────────────────────────────

/** "L9DS" magic — L9 Disclosure Signed envelope. 4 bytes ASCII. */
export const ENVELOPE_MAGIC = new Uint8Array([0x4c, 0x39, 0x44, 0x53]);

/** Envelope wire-format version. Bumped only when the preimage shape
 *  changes; downstream-cached envelopes are invalidated at the bump. */
export const ENVELOPE_VERSION = 1 as const;

/** Domain separator string for envelope hash inputs. Prevents
 *  cross-protocol collision (anchor-attestation, field-tree, etc.
 *  have their own domain separators). */
export const ENVELOPE_DOMAIN = 'semantos.disclosure-envelope/v1' as const;

/** Sizes in bytes for fixed-width fields. */
export const NOTE_ID_SIZE = 32 as const;
export const LEAF_COMMITMENT_SIZE = 32 as const;
export const VERIFIER_ID_SIZE = 33 as const; // SEC1 compressed pubkey
export const ENGAGEMENT_ID_SIZE = 32 as const;
export const NONCE_SIZE = 16 as const;

// ── Types ─────────────────────────────────────────────────────────

/** Unsigned disclosure envelope — the 8-tuple binding before
 *  signature. */
export interface DisclosureEnvelope {
  /** 32B identifier of the cell whose field is being disclosed. */
  readonly noteId: Uint8Array;
  /** UTF-8 field label being disclosed. */
  readonly fieldLabel: string;
  /** 32B L8 leaf commitment for the disclosed (label, value). The
   *  verifier confirms this matches the field-tree disclosure proof
   *  they receive. */
  readonly leafCommitment: Uint8Array;
  /** 33B SEC1 compressed pubkey of the only verifier this envelope
   *  authorises. Anyone else attempting to verify must reject. */
  readonly verifierId: Uint8Array;
  /** 32B engagement identifier — caller-defined scope (e.g. an
   *  audit-engagement id, a session id, a hat scope). Binds the
   *  envelope to a specific operational context. */
  readonly engagementId: Uint8Array;
  /** UTF-8 purpose string — caller-defined intent (e.g. "tax-audit",
   *  "consumer-scan"). Surfaces in audit logs. */
  readonly purpose: string;
  /** Expiry as milliseconds-since-epoch (bigint to match attestation
   *  height typing throughout protocol-types). Verifier rejects when
   *  `now >= expiry`. */
  readonly expiry: bigint;
  /** 16B random nonce — prevents replay across otherwise-identical
   *  envelopes. */
  readonly nonce: Uint8Array;
}

/** Signed envelope — `envelope` plus a signature over the canonical
 *  preimage by the issuer (the cell owner / data steward who has
 *  authority to authorise disclosures of this cell's fields). */
export interface SignedDisclosureEnvelope {
  readonly envelope: DisclosureEnvelope;
  /** ECDSA signature in DER form. */
  readonly signature: Uint8Array;
  /** 33B SEC1 compressed pubkey of the issuer. Verifier uses this to
   *  check the signature. */
  readonly issuerPubKeyHex: string;
}

// ── Canonical preimage ───────────────────────────────────────────

/**
 * Canonical bytes that get signed/verified.
 *
 * Layout:
 *
 *   ENVELOPE_MAGIC (4B "L9DS")
 *   || u8(ENVELOPE_VERSION)
 *   || varint(|domain|) || ENVELOPE_DOMAIN
 *   || NOTE_ID_SIZE bytes (noteId)
 *   || varint(|fieldLabel.utf8|) || fieldLabel.utf8
 *   || LEAF_COMMITMENT_SIZE bytes (leafCommitment)
 *   || VERIFIER_ID_SIZE bytes (verifierId)
 *   || ENGAGEMENT_ID_SIZE bytes (engagementId)
 *   || varint(|purpose.utf8|) || purpose.utf8
 *   || 8 bytes (expiry as u64 BE)
 *   || NONCE_SIZE bytes (nonce)
 *
 * Domain-separated + magic-prefixed so the preimage cannot collide
 * with any other semantos cryptographic preimage (anchor-attestation,
 * field-tree leaf, batch-id, etc.).
 */
export function canonicalDisclosureEnvelopePreimage(
  env: DisclosureEnvelope,
): Uint8Array {
  assertEnvelopeStructure(env);
  const chunks: Uint8Array[] = [];
  chunks.push(ENVELOPE_MAGIC);
  chunks.push(Uint8Array.of(ENVELOPE_VERSION));
  const domainBytes = new TextEncoder().encode(ENVELOPE_DOMAIN);
  chunks.push(varint(domainBytes.length));
  chunks.push(domainBytes);
  chunks.push(env.noteId);
  const labelBytes = new TextEncoder().encode(env.fieldLabel);
  chunks.push(varint(labelBytes.length));
  chunks.push(labelBytes);
  chunks.push(env.leafCommitment);
  chunks.push(env.verifierId);
  chunks.push(env.engagementId);
  const purposeBytes = new TextEncoder().encode(env.purpose);
  chunks.push(varint(purposeBytes.length));
  chunks.push(purposeBytes);
  chunks.push(u64BE(env.expiry));
  chunks.push(env.nonce);
  return concat(chunks);
}

// ── Sign + verify ────────────────────────────────────────────────

/**
 * Sign an envelope. The signature is over `sha256(canonicalPreimage)`
 * — single SHA-256 (NOT double; the @bsv/sdk ECDSA path hashes again
 * inside `.sign()` when given an unhashed message, so we sign the
 * pre-hashed digest via `signWithHashing: false` semantics).
 *
 * Returns a `SignedDisclosureEnvelope` ready to ship to the verifier.
 */
export function signDisclosureEnvelope(
  env: DisclosureEnvelope,
  issuerPriv: PrivateKey,
): SignedDisclosureEnvelope {
  const preimage = canonicalDisclosureEnvelopePreimage(env);
  const digest = sha256(Array.from(preimage)) as number[];
  const sig = issuerPriv.sign(digest);
  // bsv-sdk Signature has toDER() returning number[]
  const sigDer = sig.toDER() as number[];
  const issuerPub = issuerPriv.toPublicKey();
  return {
    envelope: freezeEnvelope(env),
    signature: Uint8Array.from(sigDer),
    issuerPubKeyHex: issuerPub.toDER('hex') as string,
  };
}

/** Inputs to `verifyDisclosureEnvelope`. */
export interface VerifyDisclosureEnvelopeInput {
  readonly signed: SignedDisclosureEnvelope;
  /** Verifier's own pubkey hex — the envelope's `verifierId` MUST
   *  match this (66-char lowercase hex SEC1 compressed). */
  readonly verifierPubKeyHex: string;
  /** Current time as ms-since-epoch (bigint). Caller supplies for
   *  deterministic testability — `BigInt(Date.now())` in prod. */
  readonly nowMs: bigint;
  /** Optional: if supplied, the envelope's `leafCommitment` MUST
   *  match this. Set to the commitment from the corresponding L8
   *  `FieldDisclosureProof` to enforce that the envelope authorises
   *  the SAME field the proof reveals. */
  readonly expectedLeafCommitment?: Uint8Array;
}

/** Result of envelope verification. */
export type VerifyDisclosureEnvelopeResult =
  | { ok: true; envelope: DisclosureEnvelope }
  | { ok: false; code: VerifyEnvelopeFailure; message: string };

export type VerifyEnvelopeFailure =
  | 'INVALID_VERIFIER_PUBKEY'
  | 'VERIFIER_MISMATCH'
  | 'EXPIRED'
  | 'LEAF_COMMITMENT_MISMATCH'
  | 'INVALID_ISSUER_PUBKEY'
  | 'INVALID_SIGNATURE';

/**
 * Verify a signed disclosure envelope.
 *
 * Fail-closed checks (in order — first failure short-circuits):
 *   1. verifierPubKeyHex is a syntactically valid 66-char hex SEC1.
 *   2. envelope.verifierId equals verifierPubKeyHex (anyone else
 *      attempting to verify gets VERIFIER_MISMATCH).
 *   3. nowMs < envelope.expiry (otherwise EXPIRED).
 *   4. (optional) envelope.leafCommitment === expectedLeafCommitment
 *      — pin the envelope to a specific L8 leaf proof.
 *   5. issuerPubKeyHex parses as a valid pubkey.
 *   6. ECDSA signature verifies under issuerPubKeyHex against
 *      sha256(canonicalPreimage).
 *
 * Never throws.
 */
export function verifyDisclosureEnvelope(
  input: VerifyDisclosureEnvelopeInput,
): VerifyDisclosureEnvelopeResult {
  const { signed, verifierPubKeyHex, nowMs, expectedLeafCommitment } = input;

  if (!/^[0-9a-f]{66}$/.test(verifierPubKeyHex)) {
    return {
      ok: false,
      code: 'INVALID_VERIFIER_PUBKEY',
      message: `verifierPubKeyHex must be 66-char lowercase hex SEC1 (got ${verifierPubKeyHex.length} chars)`,
    };
  }

  // verifierId must match. Compare hex form to be format-independent.
  const verifierIdHex = bytesHex(signed.envelope.verifierId);
  if (verifierIdHex !== verifierPubKeyHex) {
    return {
      ok: false,
      code: 'VERIFIER_MISMATCH',
      message: `envelope.verifierId (${verifierIdHex.slice(0, 16)}...) does not match the calling verifier's pubkey`,
    };
  }

  // Expiry check.
  if (nowMs >= signed.envelope.expiry) {
    return {
      ok: false,
      code: 'EXPIRED',
      message: `envelope expired at ${signed.envelope.expiry}, now is ${nowMs}`,
    };
  }

  // Optional leaf-commitment pin.
  if (expectedLeafCommitment !== undefined) {
    if (!bytesEqual(signed.envelope.leafCommitment, expectedLeafCommitment)) {
      return {
        ok: false,
        code: 'LEAF_COMMITMENT_MISMATCH',
        message: 'envelope.leafCommitment does not match expectedLeafCommitment',
      };
    }
  }

  // Validate issuer pubkey hex format BEFORE attempting to parse —
  // PublicKey.fromString accepts uppercase + DER-encoded too; we want
  // 66-char compressed-hex strictness for round-trip determinism.
  if (!/^[0-9a-f]{66}$/.test(signed.issuerPubKeyHex)) {
    return {
      ok: false,
      code: 'INVALID_ISSUER_PUBKEY',
      message: `signed.issuerPubKeyHex must be 66-char lowercase hex SEC1 (got ${signed.issuerPubKeyHex.length} chars)`,
    };
  }

  // ECDSA signature verification.
  let issuerPub: PublicKey;
  try {
    issuerPub = PublicKey.fromString(signed.issuerPubKeyHex);
  } catch (e) {
    return {
      ok: false,
      code: 'INVALID_ISSUER_PUBKEY',
      message: `failed to parse issuerPubKeyHex: ${(e as Error).message}`,
    };
  }

  try {
    const preimage = canonicalDisclosureEnvelopePreimage(signed.envelope);
    const digest = sha256(Array.from(preimage)) as number[];
    // @bsv/sdk's PublicKey.verify takes the message digest + signature.
    // We use the digest-side `verify` overload.
    const Signature = (PublicKey as unknown as { Signature?: never }).Signature;
    void Signature; // unused; we import via the runtime path below
    const { default: SignatureClass } = require('@bsv/sdk/primitives/Signature');
    const sig = SignatureClass.fromDER(Array.from(signed.signature));
    const ok = issuerPub.verify(digest, sig);
    if (!ok) {
      return {
        ok: false,
        code: 'INVALID_SIGNATURE',
        message: 'ECDSA signature did not verify under issuerPubKeyHex',
      };
    }
  } catch (e) {
    return {
      ok: false,
      code: 'INVALID_SIGNATURE',
      message: `signature verification threw: ${(e as Error).message}`,
    };
  }

  return { ok: true, envelope: signed.envelope };
}

// ── Helpers ──────────────────────────────────────────────────────

function assertEnvelopeStructure(env: DisclosureEnvelope): void {
  if (env.noteId.byteLength !== NOTE_ID_SIZE) {
    throw new Error(`disclosure envelope: noteId must be ${NOTE_ID_SIZE} bytes, got ${env.noteId.byteLength}`);
  }
  if (env.leafCommitment.byteLength !== LEAF_COMMITMENT_SIZE) {
    throw new Error(`disclosure envelope: leafCommitment must be ${LEAF_COMMITMENT_SIZE} bytes, got ${env.leafCommitment.byteLength}`);
  }
  if (env.verifierId.byteLength !== VERIFIER_ID_SIZE) {
    throw new Error(`disclosure envelope: verifierId must be ${VERIFIER_ID_SIZE} bytes, got ${env.verifierId.byteLength}`);
  }
  if (env.engagementId.byteLength !== ENGAGEMENT_ID_SIZE) {
    throw new Error(`disclosure envelope: engagementId must be ${ENGAGEMENT_ID_SIZE} bytes, got ${env.engagementId.byteLength}`);
  }
  if (env.nonce.byteLength !== NONCE_SIZE) {
    throw new Error(`disclosure envelope: nonce must be ${NONCE_SIZE} bytes, got ${env.nonce.byteLength}`);
  }
  if (typeof env.expiry !== 'bigint') {
    throw new Error(`disclosure envelope: expiry must be bigint`);
  }
  if (env.expiry < 0n) {
    throw new Error(`disclosure envelope: expiry must be non-negative`);
  }
  if (env.expiry >> 64n !== 0n) {
    throw new Error(`disclosure envelope: expiry must fit in u64`);
  }
  if (typeof env.fieldLabel !== 'string') {
    throw new Error(`disclosure envelope: fieldLabel must be string`);
  }
  if (typeof env.purpose !== 'string') {
    throw new Error(`disclosure envelope: purpose must be string`);
  }
}

function freezeEnvelope(env: DisclosureEnvelope): DisclosureEnvelope {
  return Object.freeze({
    noteId: copy(env.noteId),
    fieldLabel: env.fieldLabel,
    leafCommitment: copy(env.leafCommitment),
    verifierId: copy(env.verifierId),
    engagementId: copy(env.engagementId),
    purpose: env.purpose,
    expiry: env.expiry,
    nonce: copy(env.nonce),
  });
}

function copy(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.byteLength);
  out.set(b);
  return out;
}

function concat(chunks: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const c of chunks) total += c.byteLength;
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.byteLength;
  }
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

function bytesHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

function varint(n: number): Uint8Array {
  if (n < 0 || !Number.isInteger(n)) {
    throw new Error(`varint: must be non-negative integer, got ${n}`);
  }
  if (n < 0xfd) return Uint8Array.of(n);
  if (n <= 0xffff) {
    const b = new Uint8Array(3);
    b[0] = 0xfd;
    b[1] = n & 0xff;
    b[2] = (n >>> 8) & 0xff;
    return b;
  }
  if (n <= 0xffffffff) {
    const b = new Uint8Array(5);
    b[0] = 0xfe;
    b[1] = n & 0xff;
    b[2] = (n >>> 8) & 0xff;
    b[3] = (n >>> 16) & 0xff;
    b[4] = (n >>> 24) & 0xff;
    return b;
  }
  throw new Error(`varint: value ${n} exceeds u32; not supported`);
}

function u64BE(n: bigint): Uint8Array {
  const out = new Uint8Array(8);
  for (let i = 7; i >= 0; i--) {
    out[i] = Number(n & 0xffn);
    n >>= 8n;
  }
  return out;
}

// Re-export BSM so consumers wanting to sign via BRC-77 instead can,
// without re-importing @bsv/sdk themselves. Currently unused by this
// module's default sign path (we use raw ECDSA over the preimage
// digest, matching tea-bsv).
void BSM;
void createHash;

```
