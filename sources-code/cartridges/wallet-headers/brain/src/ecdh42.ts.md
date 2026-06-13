---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/ecdh42.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.662033+00:00
---

# cartridges/wallet-headers/brain/src/ecdh42.ts

```ts
// ecdh42.ts — Phase D: BRC-42 ECDH key rotation for per-payment privacy
//
// Implements per-BRC-42 spec (https://bsv.brc.dev/key-derivation/0042):
//   shared  = ECDH(senderSk, recipientPk)       [compressed 33 bytes]
//   tweak   = HMAC-SHA256(shared, invoice)       [raw point as HMAC key per spec]
//   child_pk = recipientPk + tweak*G             [only recipient can spend]
//   child_sk = recipientSk + tweak  (mod N)      [recipient derives on demand]
//
// Invoice format:
//   invoice = protocolHash(16) || signingKeyIndex_le(8)   [24 bytes total]
//
// Two derivation domains are exposed:
//
//   EDGE domain (0x01) — payments to a counterparty (BILATERAL):
//     protocolHash = SHA256("BRC-42-edge-creation")[0:16]
//     tweak = HMAC(ECDH(own sk, their pk), invoice)  — BRC-42 proper.
//     Both parties get the same shared secret. UNCHANGED.
//
//   CHANGE domain (0x0B) — self-directed outputs (wallet change, UNILATERAL):
//     protocolHash = SHA256("BRC-42-wallet-change")[0:16]
//     tweak = SHA256(invoice)  — EP3259724B1 deriveSegment (kdf-v2).
//     There is no counterparty, so the v0 self-ECDH (ECDH(identitySk,
//     identityPk)) was a degenerate BRC-42 misuse; deriveSegment replaces it.
//     See CW Lift L11; docs/prd/CW-LIFT-ROADMAP.md §2.2.
//
// signingKeyIndex is monotonically increasing per §2.3 BKDS — never rewinds.
//
// deriveEdgeSk() / buildRotatedLock()   — edge (counterparty) domain, BRC-42.
// deriveChangeSk() / buildChangeLock()  — change (self) domain, deriveSegment.
//
// kdf-v2 clean cutover: no version gate here — the existing on-chain change
// outputs are throwaway prototyping artefacts with no spend/binding intent, so
// v2 is the sole change-domain algorithm (unlike the Plexus SDK, which keeps
// v1 for stored test trees).

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';
import { buildP2pkhLock, pubkeyToHash160 } from './tx-builder';

// Wire sync HMAC backend for @noble/secp256k1
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

const N = secp.CURVE.n;

const enc = new TextEncoder();

const EDGE_PROTOCOL_HASH: Uint8Array = sha256(enc.encode('BRC-42-edge-creation')).slice(0, 16);
const CHANGE_PROTOCOL_HASH: Uint8Array = sha256(enc.encode('BRC-42-wallet-change')).slice(0, 16);

/** Plexus domain flag for the edge (counterparty payment) derivation domain. */
export const EDGE_DOMAIN_FLAG = 0x01;
/** Plexus domain flag for the wallet-change (self) derivation domain. */
export const CHANGE_DOMAIN_FLAG = 0x0B;

function buildInvoice(protocolHash: Uint8Array, signingKeyIndex: number): Uint8Array {
  const invoice = new Uint8Array(24);
  invoice.set(protocolHash, 0);
  new DataView(invoice.buffer).setBigUint64(16, BigInt(signingKeyIndex), true);
  return invoice;
}

function computeTweak(
  mySk: Uint8Array,
  theirPk: Uint8Array,
  protocolHash: Uint8Array,
  signingKeyIndex: number,
): Uint8Array | null {
  let shared: Uint8Array;
  try {
    // BRC-42: HMAC key = raw compressed ECDH point (per spec test vectors)
    shared = secp.getSharedSecret(mySk, theirPk, true); // 33-byte compressed
  } catch {
    return null;
  }
  return hmac(sha256, shared, buildInvoice(protocolHash, signingKeyIndex));
}

/**
 * kdf-v3 domain-separated segment tweak (CW Lift L11.5 — EP3259724B1
 * `deriveDomainSegment`, matching prof-faustus P2C `H(tag ‖ m)`): the
 * UNILATERAL derivation tweak for domains with no counterparty (change).
 *   tweak = SHA-256( u32_be(domainFlag) ‖ invoice ) — no ECDH, no HMAC.
 * The 4-byte big-endian domainFlag binds the derived key to its declared
 * domain (the cell-at-rest / OP_CHECKDOMAINFLAG u32), so a key derived for
 * one domain can't be replayed against a cell flagged for another. Byte-
 * identical to the SDK `deriveDomainSegment(sk, domainFlag, invoice)` and to
 * `cell-anchor.ts deriveCellAnchorSk`. `computeTweak` above is the bilateral
 * (BRC-42) specialisation, which stays v1.
 */
function segmentTweak(
  domainFlag: number,
  protocolHash: Uint8Array,
  signingKeyIndex: number,
): Uint8Array {
  const invoice = buildInvoice(protocolHash, signingKeyIndex);
  const preimage = new Uint8Array(4 + invoice.length);
  new DataView(preimage.buffer).setUint32(0, domainFlag, false); // big-endian tag
  preimage.set(invoice, 4);
  return sha256(preimage);
}

/**
 * Derive the BRC-42 child secret key for the RECIPIENT at the given signing key index.
 *
 * The recipient calls this with (theirOwnSk, senderPk, index) to get the
 * spending key for a payment the sender addressed to them.
 *
 * Returns the 32-byte child SK, or null on failure.  Never store the result.
 */
export function deriveEdgeSk(
  recipientSk: Uint8Array,
  senderPk: Uint8Array,
  signingKeyIndex: number,
): Uint8Array | null {
  const tweak = computeTweak(recipientSk, senderPk, EDGE_PROTOCOL_HASH, signingKeyIndex);
  if (!tweak) return null;

  const base = secp.etc.bytesToNumberBE(recipientSk);
  const t = secp.etc.bytesToNumberBE(tweak);
  const child = (base + t) % N;
  if (child === 0n) return null;
  return secp.etc.numberToBytesBE(child, 32);
}

/**
 * Build a P2PKH locking script addressed to the RECIPIENT's BRC-42 child key.
 *
 * The sender calls this with (theirPk, mySk, index) to compute the address
 * that the recipient can later spend via deriveEdgeSk(theirSk, myPk, index).
 *
 * Returns null if derivation fails — caller should fall back to the raw cert pubkey.
 */
export function buildRotatedLock(
  theirPk: Uint8Array,
  mySk: Uint8Array,
  signingKeyIndex: number,
): Uint8Array | null {
  const tweak = computeTweak(mySk, theirPk, EDGE_PROTOCOL_HASH, signingKeyIndex);
  if (!tweak) return null;

  let childPk: Uint8Array;
  try {
    // child_pk = theirPk + tweak*G   (EC point addition)
    const tweakN = secp.etc.bytesToNumberBE(tweak);
    const recipientPoint = secp.ProjectivePoint.fromHex(theirPk);
    const tweakPoint = secp.ProjectivePoint.BASE.multiply(tweakN);
    childPk = recipientPoint.add(tweakPoint).toRawBytes(true);
  } catch {
    return null;
  }

  return buildP2pkhLock(pubkeyToHash160(childPk));
}

/**
 * Derive the RECIPIENT's BRC-42 child PUBLIC key (compressed, 33 bytes) at the
 * given signing key index — the sender/grantor side.
 *
 * Same edge derivation as `buildRotatedLock`, but returns the raw child pubkey
 * instead of a P2PKH lock — for callers that bind the key into a payload (e.g.
 * the DAM access-grant cell's `grantee_pubkey`) rather than a script. By BRC-42
 * symmetry, `deriveEdgeChildPk(theirPk, mySk, i)` equals
 * `getPublicKey(deriveEdgeSk(theirSk, myPk, i))`, so the recipient can sign with
 * the matching child SK.
 *
 * Returns null if derivation fails — caller should fall back to the raw cert pubkey.
 */
export function deriveEdgeChildPk(
  theirPk: Uint8Array,
  mySk: Uint8Array,
  signingKeyIndex: number,
): Uint8Array | null {
  const tweak = computeTweak(mySk, theirPk, EDGE_PROTOCOL_HASH, signingKeyIndex);
  if (!tweak) return null;
  try {
    const tweakN = secp.etc.bytesToNumberBE(tweak);
    const recipientPoint = secp.ProjectivePoint.fromHex(theirPk);
    const tweakPoint = secp.ProjectivePoint.BASE.multiply(tweakN);
    return recipientPoint.add(tweakPoint).toRawBytes(true);
  } catch {
    return null;
  }
}

/**
 * Derive a self-directed change key at the given index — UNILATERAL (kdf-v3).
 *
 * The change domain has no counterparty, so it uses the domain-separated
 * EP3259724B1 deriveDomainSegment (CW Lift L11.5):
 *   child_sk = identitySk
 *            + SHA-256( u32_be(CHANGE_DOMAIN_FLAG) || changeProtocolHash || index_le8 )  (mod N)
 * The CHANGE flag (0x0b) is folded into the tweak so the key is bound to the
 * change domain. Recovery needs only the identity key. (v0 used a degenerate
 * self-ECDH; v2 omitted the flag; see the file header.)
 *
 * Returns the 32-byte child SK, or null on failure.  Never store the result.
 */
export function deriveChangeSk(
  identitySk: Uint8Array,
  changeIndex: number,
): Uint8Array | null {
  const tweak = segmentTweak(CHANGE_DOMAIN_FLAG, CHANGE_PROTOCOL_HASH, changeIndex);

  const base = secp.etc.bytesToNumberBE(identitySk);
  const t = secp.etc.bytesToNumberBE(tweak);
  const child = (base + t) % N;
  if (child === 0n) return null;
  return secp.etc.numberToBytesBE(child, 32);
}

/**
 * Build a P2PKH locking script for a wallet change output at the given index.
 * Counterpart to deriveChangeSk — the same wallet can spend this output on
 * recovery by calling deriveChangeSk(identitySk, changeIndex).  Derives the
 * child SK then takes its pubkey, so the priv/pub sides are reduced mod N
 * identically (no raw-tweak point multiply).
 *
 * Returns null if derivation fails.
 */
export function buildChangeLock(
  identitySk: Uint8Array,
  changeIndex: number,
): Uint8Array | null {
  const childSk = deriveChangeSk(identitySk, changeIndex);
  if (!childSk) return null;
  const childPk = secp.getPublicKey(childSk, true);
  return buildP2pkhLock(pubkeyToHash160(childPk));
}

```
