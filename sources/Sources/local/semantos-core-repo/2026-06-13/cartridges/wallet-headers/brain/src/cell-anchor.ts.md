---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/cell-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.651059+00:00
---

# cartridges/wallet-headers/brain/src/cell-anchor.ts

```ts
// cell-anchor.ts — UTXO tracking for LINEAR cell anchor outputs.
//
// Each cell type, identified by its 32-byte type_hash, gets a unique
// deriveSegment domain (protocolHash = SHA256(hex(type_hash))[0:16]) — a
// UNILATERAL key tree (kdf-v2, EP3259724B1), not BRC-42 (which is the
// bilateral/edge case).  This makes linearity enforcement cryptographic:
// spending the anchor UTXO is the on-chain act of consuming the LINEAR cell.
//
// Sovereign domain flags per Plexus Contracts Library §2.2.2:
//   0x00010000–0xFFFFFFFF  →  client-defined sovereignty
//
// Recovery bootstrap: the wallet exports {domainFlag → typeHashHex} entries
// in the Plexus `schemaMappings` field.  On device restore, Plexus supplies
// those mappings so the wallet can reconstruct every anchor protocolHash and
// scan for unspent anchor UTXOs without any other state.

import * as secp from '@noble/secp256k1';
import { sha256 } from '@noble/hashes/sha2';
import { buildP2pkhLock, pubkeyToHash160 } from './tx-builder';

const N = secp.CURVE.n;

// ── Protocol hash ─────────────────────────────────────────────────────────────

/** Derive the 16-byte BRC-42 protocolHash for a cell anchor.
 *  protocolHash = SHA256(hex(typeHash))[0:16] */
export function anchorProtocolHash(typeHash: Uint8Array): Uint8Array {
  return sha256(new TextEncoder().encode(bytesToHex(typeHash))).slice(0, 16);
}

// ── Domain flag ───────────────────────────────────────────────────────────────

/** Derive a sovereign Plexus domain flag (uint32) from a type_hash.
 *  Uses the first 3 bytes of type_hash as a discriminator in the
 *  client-defined sovereignty range 0x00010000–0xFFFFFFFF.
 *  Collision space: 16,777,216 distinct values. */
export function domainFlagFromTypeHash(typeHash: Uint8Array): number {
  return (
    0x00010000 |
    ((typeHash[0]! & 0xff) << 16) |
    ((typeHash[1]! & 0xff) << 8) |
    (typeHash[2]! & 0xff)
  );
}

// ── Schema mapping ────────────────────────────────────────────────────────────

/** Entry in the Plexus `schemaMappings` recovery export field.
 *  The recovering device reads these to reconstruct each anchor protocolHash. */
export interface SchemaMapping {
  domainFlag: number;
  typeHashHex: string;
  label?: string;
  /** L11.5 (2b): the KDF this anchor domain derives under, stamped per record
   *  so recovery is decoupled from any flag→version mapping. 'plexus-kdf-v3' =
   *  domain-separated `deriveDomainSegment` (flag folded into the tweak). */
  kdfVersion: 'plexus-kdf-v3';
}

/** Build a schemaMapping entry for a cell type.
 *  Sort multiple entries ascending by domainFlag before exporting (Plexus §2.2.8). */
export function buildSchemaMapping(typeHash: Uint8Array, label?: string): SchemaMapping {
  return {
    domainFlag: domainFlagFromTypeHash(typeHash),
    typeHashHex: bytesToHex(typeHash),
    label,
    kdfVersion: 'plexus-kdf-v3',
  };
}

// ── Key derivation ────────────────────────────────────────────────────────────

/** Derive the spending secret key for a cell anchor UTXO at anchorIndex.
 *
 * UNILATERAL, DOMAIN-SEPARATED derivation (kdf-v3, CW Lift L11.5 —
 * EP3259724B1 `deriveDomainSegment`):
 *   child_sk = identitySk
 *            + SHA-256( u32_be(domainFlag) || protocolHash || anchorIndex_le8 )  (mod N)
 * where domainFlag = domainFlagFromTypeHash(typeHash) — the per-type SOVEREIGN
 * flag already exported in schemaMappings. Folding it into the tweak binds the
 * spending key to the cell's declared header domainFlag: an anchor key for
 * type X cannot satisfy OP_CHECKDOMAINFLAG for a type-Y cell. Byte-identical to
 * `deriveDomainSegment(identitySk, domainFlag, invoice)` (plexus-vendor-sdk).
 *
 * (kdf-v2 was `SHA-256(invoice)` with the flag unbound; v0 self-ECDH before
 * that. Clean cutover, no version gate — the existing on-chain anchors are
 * throwaway prototyping artefacts with no spend/binding intent. See
 * docs/canon/domainflag-tag-unification.md.)
 *
 * Recovery: given identitySk (from PBKDF2 root seed) + typeHash (from Plexus
 * schemaMappings), this deterministically reproduces the spending key — the
 * domainFlag is recomputed from typeHash, so no extra recovery state is needed.
 */
export function deriveCellAnchorSk(
  identitySk: Uint8Array,
  typeHash: Uint8Array,
  anchorIndex: number,
): Uint8Array | null {
  const protocolHash = anchorProtocolHash(typeHash);

  // Invoice (the deriveSegment segment): protocolHash(16) || anchorIndex_le8(8)
  const invoice = new Uint8Array(24);
  invoice.set(protocolHash, 0);
  new DataView(invoice.buffer).setBigUint64(16, BigInt(anchorIndex), true);

  // L11.5 (kdf-v3): prepend the domain-separation tag = u32_be(domainFlag).
  //   tweak = SHA-256( tag || invoice )  ≡  deriveDomainSegment(sk, flag, invoice)
  const domainFlag = domainFlagFromTypeHash(typeHash);
  const preimage = new Uint8Array(4 + invoice.length);
  new DataView(preimage.buffer).setUint32(0, domainFlag, false); // big-endian
  preimage.set(invoice, 4);

  const tweak = sha256(preimage);
  const base = secp.etc.bytesToNumberBE(identitySk);
  const t = secp.etc.bytesToNumberBE(tweak);
  const child = (base + t) % N;
  if (child === 0n) return null;
  return secp.etc.numberToBytesBE(child, 32);
}

/** Build a P2PKH locking script for a cell anchor output at anchorIndex.
 *  Counterpart to deriveCellAnchorSk — spend by calling deriveCellAnchorSk
 *  with the same (identitySk, typeHash, anchorIndex). */
export function buildCellAnchorLock(
  identitySk: Uint8Array,
  typeHash: Uint8Array,
  anchorIndex: number,
): Uint8Array | null {
  const childSk = deriveCellAnchorSk(identitySk, typeHash, anchorIndex);
  if (!childSk) return null;
  const childPk = secp.getPublicKey(childSk, true);
  return buildP2pkhLock(pubkeyToHash160(childPk));
}

// ── PushDrop anchor lock ─────────────────────────────────────────────────────

/** Build a PushDrop locking script that publishes (cell_hash, type_hash) on
 *  chain alongside the BRC-42 derived anchor pubkey for spending.
 *
 *  Shape (per Todd 2026-05-26 + memory `mnca_anchor_onchain_mainnet`):
 *    PUSHDATA(32) <cell_hash>
 *    PUSHDATA(32) <type_hash>
 *    OP_2DROP
 *    PUSHDATA(33) <derived compressed pubkey>
 *    OP_CHECKSIG
 *
 *  Why PushDrop over plain P2PKH (the buildCellAnchorLock above):
 *    - Anyone scanning chain history can verify "this anchor commits to
 *      exactly this cell_hash" without needing the brain's audit log —
 *      the commitment IS the script.
 *    - The derived pubkey controls SPENDING (consume the LINEAR cell on
 *      chain); the data pushes ride along as zero-cost commitment.
 *    - Total script length: 1+32+1+32+1+1+33+1 = 102 bytes.  Well under
 *      Genesis-restored BSV limits.
 *
 *  Recovery + spending: spending side calls deriveCellAnchorSk with the
 *  same (identitySk, typeHash, anchorIndex) → same childSk → can sign
 *  the OP_CHECKSIG.  The data pushes are dropped before the verify so
 *  they don't affect spending — they're pure observability. */
export function buildCellAnchorPushDropLock(
  identitySk: Uint8Array,
  typeHash: Uint8Array,
  cellHash: Uint8Array,
  anchorIndex: number,
): Uint8Array | null {
  if (typeHash.length !== 32 || cellHash.length !== 32) return null;
  const childSk = deriveCellAnchorSk(identitySk, typeHash, anchorIndex);
  if (!childSk) return null;
  const childPk = secp.getPublicKey(childSk, true); // 33 bytes compressed-SEC1
  if (childPk.length !== 33) return null;

  // PUSHDATA(32) <cell_hash>  PUSHDATA(32) <type_hash>  OP_2DROP
  //   PUSHDATA(33) <childPk>  OP_CHECKSIG
  const out = new Uint8Array(1 + 32 + 1 + 32 + 1 + 1 + 33 + 1);
  let i = 0;
  out[i++] = 0x20; // push 32 bytes (cell_hash)
  out.set(cellHash, i); i += 32;
  out[i++] = 0x20; // push 32 bytes (type_hash)
  out.set(typeHash, i); i += 32;
  out[i++] = 0x6d; // OP_2DROP — pop type_hash + cell_hash (data carriers)
  out[i++] = 0x21; // push 33 bytes (compressed pubkey)
  out.set(childPk, i); i += 33;
  out[i++] = 0xac; // OP_CHECKSIG
  return out;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

```
