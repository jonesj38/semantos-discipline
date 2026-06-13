---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/transfer-cipher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.056416+00:00
---

# runtime/session-protocol/src/swarm/transfer-cipher.ts

```ts
/**
 * transfer-cipher — private contact-to-contact transfer.
 *
 * The transfer plane moves opaque bytes; this seals those bytes to a bilateral
 * CONTACT EDGE so only the two edge holders can read them. The swarm sees only
 * ciphertext (still chunked + merkle-verified — integrity is over the
 * ciphertext); confidentiality is end-to-end via the edge key.
 *
 * Key schedule (deliberately the RIGHT side of the BRC-42 trap — the
 * SHA-256(point) SYMMETRIC convention, NOT the raw `deriveEdgeSk` private key):
 *
 *   ikm = SHA-256( x(ECDH(myPriv, theirPub)) )          // == vendor-sdk computeSharedSecret
 *   key = HKDF-SHA256(ikm, salt = "…:<signingKeyIndex>", info = "aes-256-gcm", 32)
 *
 * Both edge holders derive the SAME key: ECDH(a, B) == ECDH(b, A) (same point),
 * and signingKeyIndex (the EdgeRecord's BKDS index, the only stored derivation
 * param) salts it per-edge. AES-256-GCM with a random IV provides
 * confidentiality + integrity.
 *
 *   sealed = MAGIC(4) ‖ iv(12) ‖ tag(16) ‖ ciphertext
 */

import { PrivateKey, PublicKey } from '@bsv/sdk';
import { createHash, createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';

const MAGIC = Uint8Array.from([0x53, 0x54, 0x58, 0x31]); // "STX1" — sealed transfer v1
const IV_LEN = 12;
const TAG_LEN = 16;
const KEY_LEN = 32;

/** A bilateral contact edge — the two keys + the edge's signing index. */
export interface TransferEdge {
  /** This node's private key. */
  myPriv: PrivateKey;
  /** The contact's public key. */
  theirPub: PublicKey;
  /** EdgeRecord.signingKeyIndex (BKDS invoiceNumber) — binds the key per-edge. */
  signingKeyIndex: number;
}

/** Build a TransferEdge from hex (the shape contacts store: pubkey hex + index). */
export function transferEdge(myPrivHex: string, theirPubHex: string, signingKeyIndex: number): TransferEdge {
  return {
    myPriv: PrivateKey.fromHex(myPrivHex),
    theirPub: PublicKey.fromString(theirPubHex),
    signingKeyIndex,
  };
}

/** Canonical ECDH shared secret: SHA-256 of the shared point's x-coordinate. */
function ecdhIkm(myPriv: PrivateKey, theirPub: PublicKey): Buffer {
  const point = myPriv.deriveSharedSecret(theirPub);
  const xHex = point.x?.toString(16).padStart(64, '0') ?? '';
  return createHash('sha256').update(Buffer.from(xHex, 'hex')).digest();
}

/** Derive the 32-byte AES key for an edge. Both edge holders get the same key. */
export function deriveTransferKey(edge: TransferEdge): Buffer {
  const ikm = ecdhIkm(edge.myPriv, edge.theirPub);
  const salt = Buffer.from(`semantos-transfer-edge:${edge.signingKeyIndex}`, 'utf8');
  const info = Buffer.from('aes-256-gcm', 'utf8');
  return Buffer.from(hkdfSync('sha256', ikm, salt, info, KEY_LEN));
}

/** Seal plaintext to an edge → sealed bytes the swarm can carry. */
export function sealForEdge(plaintext: Uint8Array, edge: TransferEdge): Uint8Array {
  const key = deriveTransferKey(edge);
  const iv = randomBytes(IV_LEN);
  const cipher = createCipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_LEN });
  const ct = Buffer.concat([cipher.update(Buffer.from(plaintext)), cipher.final()]);
  const tag = cipher.getAuthTag();
  const out = new Uint8Array(MAGIC.length + IV_LEN + TAG_LEN + ct.length);
  out.set(MAGIC, 0);
  out.set(iv, MAGIC.length);
  out.set(tag, MAGIC.length + IV_LEN);
  out.set(ct, MAGIC.length + IV_LEN + TAG_LEN);
  return out;
}

/** True if bytes carry the sealed-transfer magic header. */
export function isSealed(bytes: Uint8Array): boolean {
  return bytes.length >= MAGIC.length && MAGIC.every((b, i) => bytes[i] === b);
}

/**
 * Open sealed bytes with an edge. Throws if the magic is wrong or the GCM tag
 * fails to verify (wrong edge / tampering) — the integrity guarantee.
 */
export function openFromEdge(sealed: Uint8Array, edge: TransferEdge): Uint8Array {
  if (!isSealed(sealed)) throw new Error('transfer-cipher: not a sealed payload (bad magic)');
  const min = MAGIC.length + IV_LEN + TAG_LEN;
  if (sealed.length < min) throw new Error('transfer-cipher: sealed payload too short');
  const iv = sealed.subarray(MAGIC.length, MAGIC.length + IV_LEN);
  const tag = sealed.subarray(MAGIC.length + IV_LEN, min);
  const ct = sealed.subarray(min);
  const key = deriveTransferKey(edge);
  const decipher = createDecipheriv('aes-256-gcm', key, iv, { authTagLength: TAG_LEN });
  decipher.setAuthTag(Buffer.from(tag));
  return new Uint8Array(Buffer.concat([decipher.update(Buffer.from(ct)), decipher.final()]));
}

```
