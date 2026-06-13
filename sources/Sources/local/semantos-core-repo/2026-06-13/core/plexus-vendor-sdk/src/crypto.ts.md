---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/crypto.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.019034+00:00
---

# core/plexus-vendor-sdk/src/crypto.ts

```ts
/**
 * Pure cryptographic functions using @bsv/sdk.
 *
 * BRC-42 key derivation, BRC-52 cert ID computation, ECDH shared secrets.
 * All functions are pure — no side effects, no database, no network.
 */

import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import PublicKey from '@bsv/sdk/primitives/PublicKey';
import BigNumber from '@bsv/sdk/primitives/BigNumber';
import Curve from '@bsv/sdk/primitives/Curve';
import { SHA256 } from '@bsv/sdk/primitives/Hash';
import { pbkdf2, sha256, sha256hmac } from '@bsv/sdk/primitives/Hash';
import type { CertificatePreimage } from '@plexus/contracts';

/**
 * Derive a root private key from email + salt via PBKDF2.
 *
 * Per Plexus spec (Identity Domain, component 9): root seed generation uses
 * PBKDF2 with 100,000 iterations, executed exclusively on the client side.
 */
export function deriveRootKey(email: string, salt: string, iterations = 100_000): PrivateKey {
  const passwordBytes = Array.from(new TextEncoder().encode(email));
  const saltBytes = Array.from(new TextEncoder().encode(salt));
  const derived = pbkdf2(passwordBytes, saltBytes, iterations, 32, 'sha512');
  const hex = derived.map(b => b.toString(16).padStart(2, '0')).join('');
  return PrivateKey.fromString(hex, 'hex');
}

/**
 * EP3259724B1 base derivation primitive (Craig Wright):
 *
 *   child = parent + SHA-256(segment) mod n
 *
 * where `segment` is any input (path string, account label, counter, …) and
 * `n` is the secp256k1 curve order. Pubkey side matches via point-add.
 *
 * This is the UNILATERAL foundation primitive — no ECDH binding. BRC-42
 * is the bilateral specialisation where segment = HMAC(ECDH-shared, data);
 * see `deriveScalar` (the raw `parent + scalar mod n` form) for composing
 * the BRC-42 shape from the foundation primitive — `deriveChildKey` below
 * is the convenience wrapper for the BRC-42 self-derivation case.
 *
 * Use for any internal key tree where no ECDH counterparty exists:
 * operator cell-tree, hat-internal keys, cartridge-local key paths.
 *
 * CW Lift L11 (docs/canon/cw-lift-matrix.yml).
 */
export function deriveSegment(parentPrivKey: PrivateKey, segment: Uint8Array | string): PrivateKey {
  const segmentBytes = typeof segment === 'string'
    ? Array.from(new TextEncoder().encode(segment))
    : Array.from(segment);
  const hashBytes = sha256(segmentBytes);
  return deriveScalar(parentPrivKey, hashBytes);
}

/**
 * Lower-level scalar-addition primitive: child = parent + scalar mod n.
 *
 * Use when the caller has an already-hashed 32-byte scalar (e.g. an HMAC
 * output) and wants to apply it directly without an extra SHA-256 pass.
 * This is what makes the BRC-42 composition expressible:
 *
 *   const shared = parent.deriveSharedSecret(counterparty);
 *   const segmentBytes = sha256hmac(shared.encode(true), utf8(invoiceNumber));
 *   const child = deriveScalar(parent, segmentBytes);   // ≡ BRC-42
 *
 * For string segments where you want the SHA-256 step done for you, use
 * `deriveSegment` instead.
 *
 * CW Lift L11 (docs/canon/cw-lift-matrix.yml).
 */
export function deriveScalar(parentPrivKey: PrivateKey, scalarBytes: Uint8Array | number[]): PrivateKey {
  const arr = Array.isArray(scalarBytes) ? scalarBytes : Array.from(scalarBytes);
  const curve = new Curve();
  return new PrivateKey(parentPrivKey.add(new BigNumber(arr)).mod(curve.n).toArray());
}

/**
 * EP3259724B1 PUBLIC-KEY-SIDE derivation primitive:
 *
 *   child_pub = parent_pub + SHA-256(segment) * G
 *
 * where `G` is the secp256k1 generator. By the linearity of the curve
 * operation, this is byte-equal to `deriveSegment(parentPriv, segment).toPublicKey()`
 * — both sides land on the same child pub. That symmetry is the
 * structural argument BRC-42 + brain-side verification rely on.
 *
 * Use the public-key side when the caller HOLDS A PUBLIC KEY but not
 * the matching private key — e.g. the device-pair flow where the
 * device holds operator_root_pub (not _priv) and derives the device's
 * child pub for advertised commitments.
 *
 * CW Lift L11 (docs/canon/cw-lift-matrix.yml).
 */
export function deriveSegmentPub(parentPubKey: PublicKey, segment: Uint8Array | string): PublicKey {
  const segmentBytes = typeof segment === 'string'
    ? Array.from(new TextEncoder().encode(segment))
    : Array.from(segment);
  const hashBytes = sha256(segmentBytes);
  return deriveScalarPub(parentPubKey, hashBytes);
}

/**
 * PUBLIC-KEY-SIDE lower-level: child_pub = parent_pub + scalar * G.
 *
 * Use when the caller has an already-hashed 32-byte scalar (e.g. an
 * HMAC output) and wants to apply it directly on the public-key side.
 * This is what makes the BRC-42 public-key composition expressible:
 *
 *   const shared = devicePriv.deriveSharedSecret(operatorRootPub);
 *   const segmentBytes = sha256hmac(shared.encode(true), invoice);
 *   const childPub = deriveScalarPub(operatorRootPub, segmentBytes);
 *
 * Symmetric with deriveScalar on the private side:
 *
 *   deriveScalar(priv, s).toPublicKey()  ≡  deriveScalarPub(priv.toPublicKey(), s)
 *
 * Both produce byte-identical child pubs (proven in tests).
 *
 * CW Lift L11 (docs/canon/cw-lift-matrix.yml).
 */
export function deriveScalarPub(parentPubKey: PublicKey, scalarBytes: Uint8Array | number[]): PublicKey {
  const arr = Array.isArray(scalarBytes) ? scalarBytes : Array.from(scalarBytes);
  const curve = new Curve();
  const scalar = new BigNumber(arr);
  // child_pub = scalar * G + parent_pub
  const tweakPoint = curve.g.mul(scalar);
  // PublicKey extends Point in @bsv/sdk; `.add` returns a Point-shaped
  // value whose (x, y) feed PublicKey's ctor. The cast mirrors the
  // upstream pattern in @bsv/sdk's PublicKey.deriveChild implementation.
  const sumPoint = (parentPubKey as unknown as {
    add: (p: unknown) => { x: BigNumber; y: BigNumber };
  }).add(tweakPoint);
  return new PublicKey(sumPoint.x, sumPoint.y);
}

// ── L11.5: domain-separated derivation (kdf-v3) ──────────────────────────────

/**
 * Algorithm-version marker for the domain-separated unilateral primitive.
 * v2 = `deriveSegment` (bare `SHA-256(segment)`); v3 folds the canonical
 * u32 domain flag into the tweak. See `derive_segment.zig` KDF_VERSION and
 * the `KdfVersion` union below.
 */
export const KDF_VERSION_DOMAIN: KdfVersion = 'plexus-kdf-v3';

/**
 * Compute the L11.5 domain-separated tweak scalar:
 *
 *   SHA-256( u32_be(domainFlag) ‖ segment )
 *
 * `domainFlag` is a canonical u32 from `core/constants/constants.json`
 * (the SAME value the cell header carries and `OP_CHECKDOMAINFLAG` asserts),
 * encoded big-endian as a 4-byte domain-separation tag. This is exactly
 * prof-faustus/bsv-universal-sdk's pay-to-contract `H(tag ‖ m)` with
 * `tag = u32_be(domainFlag)` and `m = segment`.
 */
function domainTweak(domainFlag: number, segment: Uint8Array | string): number[] {
  if (!Number.isInteger(domainFlag) || domainFlag < 0 || domainFlag > 0xffff_ffff) {
    throw new RangeError(`domainFlag must be a u32 (0..2^32-1); got ${domainFlag}`);
  }
  const segmentBytes = typeof segment === 'string'
    ? Array.from(new TextEncoder().encode(segment))
    : Array.from(segment);
  const tag = [
    (domainFlag >>> 24) & 0xff,
    (domainFlag >>> 16) & 0xff,
    (domainFlag >>> 8) & 0xff,
    domainFlag & 0xff,
  ];
  return sha256([...tag, ...segmentBytes]);
}

/**
 * L11.5 — domain-separated EP3259724B1 derivation (kdf-v3):
 *
 *   child = parent + SHA-256( u32_be(domainFlag) ‖ segment ) mod n
 *
 * Folds the canonical u32 domain flag into the derivation tweak as a
 * domain separator, binding the derived key to its declared domain: a key
 * derived under domain X cannot be replayed to authorize a cell flagged
 * domain Y (and `OP_CHECKDOMAINFLAG` then transitively gates the key, not
 * just the cell at rest).
 *
 * This is the v3 unilateral primitive. `deriveSegment` (v2, bare segment)
 * is retained for stored test trees and bilateral-adjacent composition;
 * new unilateral call-sites should use this. The Zig mirror
 * (`derive_segment.zig` `deriveDomainSegment`) is byte-identical.
 *
 * CW Lift L11.5 (docs/canon/domainflag-tag-unification.md).
 */
export function deriveDomainSegment(
  parentPrivKey: PrivateKey,
  domainFlag: number,
  segment: Uint8Array | string,
): PrivateKey {
  return deriveScalar(parentPrivKey, domainTweak(domainFlag, segment));
}

/**
 * Public-key side of `deriveDomainSegment` — symmetric verifier path:
 *
 *   child_pub = parent_pub + SHA-256( u32_be(domainFlag) ‖ segment )·G
 *
 * Byte-equal to `deriveDomainSegment(parentPriv, domainFlag, segment).toPublicKey()`.
 *
 * CW Lift L11.5 (docs/canon/domainflag-tag-unification.md).
 */
export function deriveDomainSegmentPub(
  parentPubKey: PublicKey,
  domainFlag: number,
  segment: Uint8Array | string,
): PublicKey {
  return deriveScalarPub(parentPubKey, domainTweak(domainFlag, segment));
}

/**
 * Derive a child private key via BRC-42 (HMAC over ECDH shared secret).
 *
 * Uses self-derivation pattern: parent derives child under its own public key.
 * The invoiceNumber encodes resourceId, domainFlag, and childIndex for uniqueness.
 *
 * Equivalent to:
 *   const pub = parentPrivKey.toPublicKey();
 *   const shared = parentPrivKey.deriveSharedSecret(pub).encode(true);
 *   const segmentBytes = sha256hmac(shared, utf8(invoiceNumber));
 *   return deriveScalar(parentPrivKey, segmentBytes);
 *
 * Kept as a delegate to `@bsv/sdk`'s `deriveChild` to preserve byte-equal
 * BRC-42 semantics for existing callers; the composition above is asserted
 * in tests (see `__tests__/derive-segment.test.ts`).
 *
 * BRC-42 = EP3259724B1 with segment = HMAC(ECDH-shared-secret, data).
 * For non-bilateral derivation use `deriveSegment` directly.
 */
export function deriveChildKey(parentPrivKey: PrivateKey, invoiceNumber: string): PrivateKey {
  const parentPubKey = parentPrivKey.toPublicKey();
  return parentPrivKey.deriveChild(parentPubKey, invoiceNumber);
}

/**
 * KDF algorithm version for hierarchical (unilateral) node derivation.
 *
 * Per Plexus Technical Requirements §2 (Core Library) and §10 (Derivation
 * Domain): the derivation engine must accept an algorithm-version parameter and
 * retain legacy logic so older keys stay recoverable.
 *
 *   plexus-kdf-v2 (canonical) — node key = EP3259724B1 `deriveSegment` directly
 *                               (child = parent + SHA-256(invoice) mod n). The
 *                               correct primitive for DAG nodes: there is no
 *                               counterparty, so no ECDH belongs in the path.
 *   plexus-kdf-v1 (legacy)    — node key = BRC-42 self-derivation
 *                               (child = parent + HMAC(ECDH(parent,parentPub), invoice)).
 *                               The bilateral primitive applied to itself — the
 *                               shape semantos shipped before the L11 reframe.
 *                               Retained ONLY so v1 trees remain reconstructible.
 *   plexus-kdf-v3 (L11.5)     — domain-separated node key
 *                               (child = parent + SHA-256(u32_be(domainFlag) ‖
 *                               segment) mod n). Binds the key to its canonical
 *                               u32 domain flag. Because it needs the extra
 *                               domainFlag input it is NOT expressible through
 *                               `deriveNodeKey`'s (parent, invoice) signature —
 *                               call `deriveDomainSegment` directly. Listed here
 *                               so recovery notation can name it.
 *                               See docs/canon/domainflag-tag-unification.md.
 */
export type KdfVersion = 'plexus-kdf-v1' | 'plexus-kdf-v2' | 'plexus-kdf-v3';

export const DEFAULT_KDF_VERSION: KdfVersion = 'plexus-kdf-v2';

/**
 * Derive a hierarchical DAG node key — UNILATERAL (no ECDH counterparty).
 *
 * This is "Specialisation A" of the EP3259724B1 foundation: a parent cert
 * deriving a child cert in the identity DAG. Because there is no second party,
 * the canonical (v2) path is the base primitive `deriveSegment`, NOT a
 * degenerate self-ECDH. The v1 path is preserved only for recovering trees
 * minted before the L11 reframe (CW Lift L11; docs/prd/CW-LIFT-ROADMAP.md §2.2).
 *
 * Edge / relationship derivation is the OTHER specialisation — bilateral, real
 * ECDH — see `deriveChildKey` + `computeSharedSecret`. Do not route edges here.
 */
export function deriveNodeKey(
  parentPrivKey: PrivateKey,
  invoiceNumber: string,
  version: KdfVersion = DEFAULT_KDF_VERSION,
): PrivateKey {
  return version === 'plexus-kdf-v1'
    ? deriveChildKey(parentPrivKey, invoiceNumber)
    : deriveSegment(parentPrivKey, invoiceNumber);
}

/**
 * Compute a BRC-52 cert_id from a canonical certificate preimage.
 *
 * cert_id = SHA-256 of the deterministic JSON serialization (sorted keys).
 * Returns 64-char lowercase hex string.
 */
export function computeCertId(preimage: CertificatePreimage): string {
  const canonical = JSON.stringify(preimage, Object.keys(preimage).sort());
  const hash = new SHA256().update(canonical).digestHex();
  return hash;
}

/**
 * Compute an ECDH shared secret between two identities.
 *
 * Returns SHA-256 of the x-coordinate of the shared point, as 64-char hex.
 * The actual shared secret point is never exposed.
 */
export function computeSharedSecret(privKey: PrivateKey, pubKey: PublicKey): string {
  const sharedPoint = privKey.deriveSharedSecret(pubKey);
  const xHex = sharedPoint.x?.toString(16).padStart(64, '0') ?? '';
  const hash = new SHA256().update(xHex, 'hex').digestHex();
  return hash;
}

/**
 * EP3259724B1 / US12375287B2 common-secret primitive (verifiable-accounting-chain):
 *
 *   commonSecret = ECDH(myMasterPriv + gv,  theirMasterPub + gv·G)
 *
 * where `gv` ("group variable") is any segment both parties have agreed
 * to apply (a per-link counter, an invoice number, a chain seq, …).
 *
 * BOTH parties can compute the same secret without per-link key exchange:
 *   - I hold (myMasterPriv, theirMasterPub) and apply `gv`.
 *   - Counterparty holds (theirMasterPriv, myMasterPub) and applies the
 *     same `gv`. By ECDH symmetry they land on the same shared bytes.
 *
 * Pure composition of L11 (`deriveScalar` / `deriveScalarPub`) +
 * the existing `computeSharedSecret`. No new mechanism; this helper just
 * names the va-chain pattern so callers don't reinvent it.
 *
 * Use for L9 scoped-disclosure envelope delivery (point-to-point auditor
 * handoff under a chain-segment binding), L12 audit-chain link key
 * derivation under counterparty binding, and any bilateral per-link
 * shared key where the binding is "we both apply the same gv".
 *
 * The `gv` may be supplied as either a raw 32-byte scalar (`Uint8Array`)
 * or as a string segment (UTF-8-encoded, then SHA-256-hashed to a scalar
 * via the same shape as `deriveSegment`). The two overloads map to
 * `deriveScalar` and `deriveSegment` respectively.
 *
 * Returns SHA-256(x-coordinate) of the derived shared point as 64-char
 * hex, matching `computeSharedSecret`'s contract.
 *
 * CW Lift L12 (docs/canon/cw-lift-matrix.yml).
 */
export function computeCommonSecret(
  myMasterPriv: PrivateKey,
  theirMasterPub: PublicKey,
  gv: Uint8Array | number[] | string,
): string {
  const myDerivedPriv = typeof gv === 'string'
    ? deriveSegment(myMasterPriv, gv)
    : deriveScalar(myMasterPriv, gv);
  const theirDerivedPub = typeof gv === 'string'
    ? deriveSegmentPub(theirMasterPub, gv)
    : deriveScalarPub(theirMasterPub, gv);
  return computeSharedSecret(myDerivedPriv, theirDerivedPub);
}

/**
 * Get the 33-byte compressed public key as a 66-char hex string.
 * Starts with 02 or 03 per SEC1 encoding.
 */
export function compressedPubKeyHex(pubKey: PublicKey): string {
  return pubKey.toDER('hex') as string;
}

/**
 * SHA-256 hash of a UTF-8 string. Returns 64-char hex.
 */
export function sha256hex(input: string): string {
  return new SHA256().update(input).digestHex();
}

/**
 * Build a canonical CertificatePreimage for a root identity.
 */
export function buildRootPreimage(
  publicKey: string,
  email: string,
): CertificatePreimage {
  return {
    subjectPublicKey: publicKey,
    certifierPublicKey: publicKey, // self-certified root
    type: 'plexus.identity.root',
    serialNumber: sha256hex(`root:${email}`),
    fields: { email },
  };
}

/**
 * Build a canonical CertificatePreimage for a derived child.
 */
export function buildChildPreimage(
  childPubKey: string,
  parentPubKey: string,
  resourceId: string,
  domainFlag: number,
  childIndex: number,
): CertificatePreimage {
  return {
    subjectPublicKey: childPubKey,
    certifierPublicKey: parentPubKey,
    type: 'plexus.identity.derived',
    serialNumber: sha256hex(`child:${parentPubKey}:${resourceId}:${domainFlag}:${childIndex}`),
    fields: { resourceId, domainFlag: domainFlag.toString(), childIndex: childIndex.toString() },
  };
}

```
