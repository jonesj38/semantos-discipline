---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/access-grant.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.870068+00:00
---

# core/protocol-types/src/bsv/access-grant.ts

```ts
/**
 * access-grant — wire formats + challenge digest for Engine-Checked Data
 * Access (DAM), the substrate-native, revocable, scoped file-sharing scheme
 * (docs/design/LOCKSCRIPT-CLEAVAGE.md; plan jiggly-munching-crab).
 *
 * This is the CANONICAL, language-portable surface for the DAM cell-type
 * family — byte-identical to the Zig sibling that the brain's 2-PDA evaluates
 * (cartridges/swarm/brain/access_grant_context.zig + access_grant_handler.zig).
 * A grantee (TS) building a `verify.intent` and the brain (Zig) checking it MUST
 * agree on every byte, or the grantee's signature never verifies.
 *
 * Three cell types (DAM Slice-1):
 *   - `access.grant`               LINEAR     the revocable grant (state)
 *   - `access.grant.verify.intent` EPHEMERAL  the grantee's signed challenge
 *   - `access.grant.verify.result` EPHEMERAL  { ok, content_cell_hash }
 *
 * The grant proves access by the grantee signing `accessChallengeDigest(...)`
 * (the canonical BIP-143 sighash of a synthetic access tx) with their
 * edge-derived key (BRC-42; see cartridges/wallet-headers/brain/src/ecdh42.ts).
 * Signing lives with the keys (wallet-headers); this module is pure wire —
 * payload/cell codecs + the digest. The cross-impl digest vector is pinned on
 * the Zig side too (access_grant_context.zig conformance test).
 *
 * Substrate governance: pure wire — depends only on other substrate packages
 * (@semantos/cell-ops, local constants/cell-header). MUST NOT import from
 * cartridges/ or runtime/.
 */

import { cellMerkleSha256 as sha256 } from '@semantos/cell-ops/packer';
import { CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE, VERSION, Linearity } from '../constants';
import type { CellHeader } from '../cell-header';
import { serializeCellHeader } from '../cell-header';

// ── type names + hashes (sha256 of the canonical type string; matches Zig) ──

export const ACCESS_GRANT_TYPE_NAME = 'access.grant' as const;
export const ACCESS_GRANT_VERIFY_INTENT_TYPE_NAME = 'access.grant.verify.intent' as const;
export const ACCESS_GRANT_VERIFY_RESULT_TYPE_NAME = 'access.grant.verify.result' as const;

export const ACCESS_GRANT_TYPE_HASH: Uint8Array = sha256(new TextEncoder().encode(ACCESS_GRANT_TYPE_NAME));
export const VERIFY_INTENT_TYPE_HASH: Uint8Array = sha256(new TextEncoder().encode(ACCESS_GRANT_VERIFY_INTENT_TYPE_NAME));
export const VERIFY_RESULT_TYPE_HASH: Uint8Array = sha256(new TextEncoder().encode(ACCESS_GRANT_VERIFY_RESULT_TYPE_NAME));

/** Capability type carried at payload byte 0 of an `access.grant` (linearity.zig: 2 = DATA_ACCESS). */
export const CAP_DATA_ACCESS = 2 as const;

/** Plexus domain flag for the edge (counterparty) derivation domain — ecdh42 EDGE_DOMAIN_FLAG. */
export const EDGE_DOMAIN_FLAG = 0x01 as const;

// ── payload layouts (offsets within the 768-byte payload; mirror DAM-1 Zig) ──
//
// access.grant:
//   [0]      capability_type (u8, = DATA_ACCESS)
//   [1..34]  grantee_pubkey  (33, compressed — the contact's edge-derived key)
//   [34..66] content_hash    (32)
//   [66..74] expiry_ts       (u64 LE, unix seconds)
const GRANT_CAP_OFF = 0;
const GRANT_PUBKEY_OFF = 1;
const GRANT_PUBKEY_LEN = 33;
const GRANT_CONTENT_HASH_OFF = 34;
const GRANT_EXPIRY_OFF = 66;
export const GRANT_PAYLOAD_LEN = 74 as const;

// access.grant.verify.intent:
//   [0..32]  grant_cell_hash
//   [32..34] sig_len (u16 LE)
//   [34..]   signature (DER ‖ trailing sighash-flag byte, BSV convention)
const VI_GRANT_HASH_OFF = 0;
const VI_SIG_LEN_OFF = 32;
const VI_SIG_OFF = 34;

// access.grant.verify.result:
//   [0]      ok (u8: 1 = granted)
//   [1..33]  content_cell_hash (32) — the cell the grant unlocks
const VR_OK_OFF = 0;
const VR_CONTENT_HASH_OFF = 1;
export const RESULT_PAYLOAD_LEN = 33 as const;

/** The BSV sighash flag the grantee appends to its DER signature. */
export const SIGHASH_ALL_FORKID = 0x41 as const;

const ZERO16 = new Uint8Array(16);
const ZERO32 = new Uint8Array(32);

function sha256d(b: Uint8Array): Uint8Array {
  return sha256(sha256(b));
}

function assertLen(name: string, b: Uint8Array, n: number): void {
  if (b.length !== n) throw new Error(`access-grant: ${name} must be ${n} bytes, got ${b.length}`);
}

// ── access.grant ────────────────────────────────────────────────────────────

export interface AccessGrant {
  /** The contact's edge-derived compressed pubkey (33B) — who may prove access. */
  granteePubkey: Uint8Array;
  /** sha256 of the shared content cell (32B). */
  contentHash: Uint8Array;
  /** Expiry as unix seconds. */
  expiry: bigint;
}

export function encodeAccessGrantPayload(g: AccessGrant): Uint8Array {
  assertLen('granteePubkey', g.granteePubkey, GRANT_PUBKEY_LEN);
  assertLen('contentHash', g.contentHash, 32);
  const p = new Uint8Array(GRANT_PAYLOAD_LEN);
  p[GRANT_CAP_OFF] = CAP_DATA_ACCESS;
  p.set(g.granteePubkey, GRANT_PUBKEY_OFF);
  p.set(g.contentHash, GRANT_CONTENT_HASH_OFF);
  new DataView(p.buffer).setBigUint64(GRANT_EXPIRY_OFF, g.expiry, true);
  return p;
}

export function decodeAccessGrantPayload(payload: Uint8Array): AccessGrant & { capability: number } {
  if (payload.length < GRANT_PAYLOAD_LEN) {
    throw new Error(`decodeAccessGrantPayload: payload too short (${payload.length} < ${GRANT_PAYLOAD_LEN})`);
  }
  return {
    capability: payload[GRANT_CAP_OFF]!,
    granteePubkey: payload.slice(GRANT_PUBKEY_OFF, GRANT_PUBKEY_OFF + GRANT_PUBKEY_LEN),
    contentHash: payload.slice(GRANT_CONTENT_HASH_OFF, GRANT_CONTENT_HASH_OFF + 32),
    expiry: new DataView(payload.buffer, payload.byteOffset).getBigUint64(GRANT_EXPIRY_OFF, true),
  };
}

export interface EncodeCellOptions {
  ownerId?: Uint8Array;
  timestamp?: bigint;
  /** Plexus domain flag (header offset 24). Defaults to the edge domain. */
  domainFlag?: number;
}

function packCell(typeHash: Uint8Array, linearity: number, payload: Uint8Array, opts: EncodeCellOptions): Uint8Array {
  if (payload.length > PAYLOAD_SIZE) {
    throw new Error(`access-grant: payload (${payload.length}B) exceeds PAYLOAD_SIZE (${PAYLOAD_SIZE})`);
  }
  const header: CellHeader = {
    magic: new Uint8Array(16),
    linearity,
    version: VERSION,
    flags: opts.domainFlag ?? EDGE_DOMAIN_FLAG,
    refCount: 0,
    typeHash,
    ownerId: opts.ownerId ?? ZERO16,
    timestamp: opts.timestamp ?? 0n,
    cellCount: 1,
    totalSize: payload.length,
    parentHash: ZERO32,
    prevStateHash: ZERO32,
    domainPayloadRoot: sha256(payload),
  };
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(serializeCellHeader(header), 0);
  cell.set(payload, HEADER_SIZE);
  return cell;
}

/** Pack an `access.grant` into a canonical 1024-byte LINEAR cell. */
export function encodeAccessGrantCell(g: AccessGrant, opts: EncodeCellOptions = {}): Uint8Array {
  return packCell(ACCESS_GRANT_TYPE_HASH, Linearity.LINEAR, encodeAccessGrantPayload(g), opts);
}

/**
 * The grant's content-address — sha256 of the full 1024-byte cell. This is the
 * `grant_hash` the cell store keys on and the value the challenge digest binds
 * to. Both grantor and grantee must compute it over the IDENTICAL grant bytes.
 */
export function accessGrantCellHash(grantCell: Uint8Array): Uint8Array {
  assertLen('grantCell', grantCell, CELL_SIZE);
  return sha256(grantCell);
}

// ── access.grant.verify.intent ────────────────────────────────────────────────

export interface VerifyIntent {
  /** sha256 of the `access.grant` cell being proven against (32B). */
  grantHash: Uint8Array;
  /** The grantee's signature: DER ‖ sighash-flag byte. */
  signature: Uint8Array;
}

export function encodeVerifyIntentPayload(vi: VerifyIntent): Uint8Array {
  assertLen('grantHash', vi.grantHash, 32);
  if (vi.signature.length < 2 || vi.signature.length > 0xffff) {
    throw new Error(`encodeVerifyIntentPayload: signature length out of range (${vi.signature.length})`);
  }
  const p = new Uint8Array(VI_SIG_OFF + vi.signature.length);
  p.set(vi.grantHash, VI_GRANT_HASH_OFF);
  // sig_len as u16 LE (matches the Zig builder's payload[32] | payload[33]<<8 decode).
  p[VI_SIG_LEN_OFF] = vi.signature.length & 0xff;
  p[VI_SIG_LEN_OFF + 1] = (vi.signature.length >> 8) & 0xff;
  p.set(vi.signature, VI_SIG_OFF);
  return p;
}

export function decodeVerifyIntentPayload(payload: Uint8Array): VerifyIntent {
  if (payload.length < VI_SIG_OFF) {
    throw new Error(`decodeVerifyIntentPayload: payload too short (${payload.length} < ${VI_SIG_OFF})`);
  }
  const sigLen = payload[VI_SIG_LEN_OFF]! | (payload[VI_SIG_LEN_OFF + 1]! << 8);
  if (VI_SIG_OFF + sigLen > payload.length) {
    throw new Error('decodeVerifyIntentPayload: declared sig_len overruns payload');
  }
  return {
    grantHash: payload.slice(VI_GRANT_HASH_OFF, VI_GRANT_HASH_OFF + 32),
    signature: payload.slice(VI_SIG_OFF, VI_SIG_OFF + sigLen),
  };
}

/** Pack a `verify.intent` into a canonical 1024-byte cell. */
export function encodeVerifyIntentCell(vi: VerifyIntent, opts: EncodeCellOptions = {}): Uint8Array {
  return packCell(VERIFY_INTENT_TYPE_HASH, Linearity.RELEVANT, encodeVerifyIntentPayload(vi), opts);
}

// ── access.grant.verify.result ────────────────────────────────────────────────

export interface VerifyResult {
  ok: boolean;
  /** The unlocked content cell's hash (32B); zeros if not bound. */
  contentHash?: Uint8Array;
}

export function encodeVerifyResultPayload(r: VerifyResult): Uint8Array {
  const p = new Uint8Array(RESULT_PAYLOAD_LEN);
  p[VR_OK_OFF] = r.ok ? 1 : 0;
  if (r.contentHash) {
    assertLen('contentHash', r.contentHash, 32);
    p.set(r.contentHash, VR_CONTENT_HASH_OFF);
  }
  return p;
}

export function decodeVerifyResultPayload(payload: Uint8Array): VerifyResult {
  if (payload.length < 1) throw new Error('decodeVerifyResultPayload: empty payload');
  return {
    ok: payload[VR_OK_OFF] === 1,
    contentHash:
      payload.length >= RESULT_PAYLOAD_LEN
        ? payload.slice(VR_CONTENT_HASH_OFF, VR_CONTENT_HASH_OFF + 32)
        : undefined,
  };
}

export function encodeVerifyResultCell(r: VerifyResult, opts: EncodeCellOptions = {}): Uint8Array {
  return packCell(VERIFY_RESULT_TYPE_HASH, Linearity.RELEVANT, encodeVerifyResultPayload(r), opts);
}

// ── the canonical access-challenge digest (BIP-143 port; gotcha #3) ──────────

function writeVarInt(out: number[], n: number): void {
  // Our synthetic tx only ever needs single-byte varints (<0xFD), but keep the
  // full encoding so the port stays faithful to the Zig writeVarInt.
  if (n < 0xfd) {
    out.push(n & 0xff);
  } else if (n <= 0xffff) {
    out.push(0xfd, n & 0xff, (n >> 8) & 0xff);
  } else {
    out.push(0xfe, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff);
  }
}

function le32(out: number[], n: number): void {
  out.push(n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff);
}

/**
 * The canonical access-challenge digest — a byte-exact port of the Zig
 * `accessChallengeDigest` (access_grant_context.zig). It is the BIP-143 sighash
 * of a synthetic 1-in/1-out access tx that spends the grant cell
 * (input.prev_txid = grantHash) under a P2PK scriptCode to the grantee, with
 * SIGHASH_ALL|FORKID. The grantee signs THIS digest with their edge key.
 *
 * Synthetic tx: version=2, locktime=0; 1 input {prev_txid=grantHash, vout=0,
 * seq=0xFFFFFFFF}, input_value=1; 1 output {value=0, empty script};
 * subscript = 0x21 ‖ granteePubkey(33) ‖ 0xAC; sighash_type=0x41.
 *
 * Pinned against the Zig impl by a cross-impl conformance vector (see tests +
 * access_grant_context.zig's conformance test).
 */
export function accessChallengeDigest(grantHash: Uint8Array, granteePubkey: Uint8Array): Uint8Array {
  assertLen('grantHash', grantHash, 32);
  assertLen('granteePubkey', granteePubkey, 33);

  const VOUT0 = new Uint8Array(4); // 0x00000000
  const SEQ = Uint8Array.from([0xff, 0xff, 0xff, 0xff]);

  // subscript = PUSH(33) ‖ pubkey ‖ OP_CHECKSIG
  const subscript = new Uint8Array(35);
  subscript[0] = 0x21;
  subscript.set(granteePubkey, 1);
  subscript[34] = 0xac;

  // 2. hashPrevouts = sha256d(prev_txid ‖ vout_LE)
  const prevouts = new Uint8Array(36);
  prevouts.set(grantHash, 0);
  prevouts.set(VOUT0, 32);
  const hashPrevouts = sha256d(prevouts);

  // 3. hashSequence = sha256d(seq_LE)  [base==ALL, not ANYONECANPAY]
  const hashSequence = sha256d(SEQ);

  // 8. hashOutputs = sha256d(value_LE(0) ‖ varint(script_len=0))  [base==ALL]
  const out0 = [...new Uint8Array(8)]; // value = 0 (8B LE)
  writeVarInt(out0, 0); // empty script
  const hashOutputs = sha256d(Uint8Array.from(out0));

  const preimage: number[] = [];
  le32(preimage, 2); // 1. nVersion = 2
  preimage.push(...hashPrevouts); // 2.
  preimage.push(...hashSequence); // 3.
  preimage.push(...grantHash, ...VOUT0); // 4. outpoint
  writeVarInt(preimage, subscript.length); // 5. scriptCode len
  preimage.push(...subscript); //    scriptCode
  // 6. value of the UTXO being spent (8B LE) — input_value = 1
  preimage.push(1, 0, 0, 0, 0, 0, 0, 0);
  preimage.push(...SEQ); // 7. nSequence
  preimage.push(...hashOutputs); // 8.
  le32(preimage, 0); // 9. nLockTime = 0
  le32(preimage, SIGHASH_ALL_FORKID); // 10. nHashType = 0x41 (as u32 LE)

  return sha256d(Uint8Array.from(preimage));
}

/**
 * Assemble a `verify.intent` cell from a grant the grantee already signed.
 * `signature` is the DER ‖ 0x41 blob produced by signing
 * `accessChallengeDigest(grantHash, granteePubkey)` with the edge key (the
 * signing step lives with the keys — cartridges/wallet-headers).
 */
export function buildVerifyIntentCell(
  args: { grantHash: Uint8Array; signature: Uint8Array },
  opts: EncodeCellOptions = {},
): Uint8Array {
  return encodeVerifyIntentCell({ grantHash: args.grantHash, signature: args.signature }, opts);
}

```
