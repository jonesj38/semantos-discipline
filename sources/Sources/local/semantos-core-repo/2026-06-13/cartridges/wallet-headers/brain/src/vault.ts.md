---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/vault.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.651355+00:00
---

# cartridges/wallet-headers/brain/src/vault.ts

```ts
// Phase W11 — Tier-3 vault management (browser bundle, v0.2 multisig path).
//
// Reference: docs/design/WALLET-TIER-CUSTODY.md §4.3 (vault stub vs multisig),
// §4.4 (cooldown — host clock v0.1 vs nSequence v0.2), §6.2.1 (per-tx leaf
// cell), and docs/design/VAULT-MULTISIG-NSEQUENCE.md (v0.2 layout + script).
//
// Scope (v0.2, Tier-3 only):
//   • createVault(): build a 1024-byte Tier-3 leaf cell carrying the multisig
//     metadata (member pubkeys, threshold, nSequence, parent_txid) per the
//     VAULT_OFFSET_* constants in `core/cell-engine/src/opcodes/plexus.zig`.
//   • signVaultSpend(): produce an m-of-n signature aggregate over a tx
//     preimage digest using the supplied member secret keys.
//   • nextNSequence(): compute the BIP-68 nSequence value for the *next*
//     vault UTXO given a target cooldown (in seconds). BSV honors BIP-68's
//     time-based mode (bit 22) at consensus per design §4.4 v0.2.
//
// Constraints:
//   • No new TS deps — uses @noble/secp256k1 + @noble/hashes already in
//     the wallet bundle (per package.json).
//   • Does NOT touch the BRC-100 dispatcher — vault spends use createSignature
//     once per member at the dispatcher boundary, then this module aggregates.
//   • Does NOT touch Tier 0/1/2 flows or the v0.1 vault stub. v0.2 is opt-in
//     and additive (design §4.3, "v0.2 is a vault-tier-only upgrade").

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

// secp v2 needs sync HMAC for sync sign(). Aligned with host.ts initialiser.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Layout constants (mirror plexus.zig:VAULT_OFFSET_*).
// Update both files in lockstep.
// ──────────────────────────────────────────────────────────────────────

export const CELL_SIZE = 1024;
export const HEADER_SIZE = 256;
export const PAYLOAD_SIZE = 768;

export const VAULT_DOMAIN_FLAG = 0x10000005; // §6.2 Tier-3
export const VAULT_OFFSET_LEAF_PRIVKEY = 0;
export const VAULT_OFFSET_PROTOCOL_HASH = 32;
export const VAULT_OFFSET_COUNTERPARTY = 48;
export const VAULT_OFFSET_THRESHOLD = 63;
export const VAULT_OFFSET_MEMBER_PUBKEYS_START = 64;
export const VAULT_OFFSET_NSEQUENCE = 229;
export const VAULT_OFFSET_PARENT_TXID = 233;

export const VAULT_MAX_MEMBERS = 5;
export const VAULT_MEMBER_PUBKEY_LEN = 33;

// BIP-68 (relative locktime) flags. BSV honors these at consensus per §4.4.
// JS bitwise ops are signed 32-bit; we keep these as unsigned u32 literals so
// downstream `>>> 0` lifts work uniformly without surprise sign-extension.
export const VAULT_NSEQUENCE_TYPE_FLAG = 1 << 22; // bit 22 set ⇒ time-mode (= 0x00400000)
export const VAULT_NSEQUENCE_DISABLE_FLAG = 0x80000000 >>> 0; // bit 31 set ⇒ no constraint
export const VAULT_NSEQUENCE_VALUE_MASK = 0xffff; // low 16 bits = value
export const VAULT_NSEQUENCE_TIME_UNIT_SECONDS = 512;

// Linearity tags (mirror constants.zig).
const LINEARITY_LINEAR = 1;
const LINEARITY_AFFINE = 2;
const LINEARITY_RELEVANT = 3;

// Cell magic (mirror constants.zig).
const MAGIC_1 = 0xdeadbeef;
const MAGIC_2 = 0xcafebabe;
const MAGIC_3 = 0x13371337;
const MAGIC_4 = 0x42424242;

// SIGHASH_ALL | FORKID — BSV convention used by host_checkmultisig.
export const SIGHASH_ALL_FORKID = 0x41;

// ──────────────────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────────────────

export interface VaultCreateInput {
  /** Compressed secp256k1 pubkeys of each member's secure-element key.
   *  Length must be 1..VAULT_MAX_MEMBERS. */
  memberPubkeys: Uint8Array[];
  /** m of n threshold; 1 <= threshold <= memberPubkeys.length. */
  threshold: number;
  /** BRC-42 leaf private key (32 bytes) — the per-tx leaf seed. */
  leafPrivKey: Uint8Array;
  /** 16-byte BRC-43 protocol hash (per §6.2.1 leaf cell prefix). */
  protocolHash: Uint8Array;
  /** 33-byte counterparty pubkey (or 'self' / 'anyone' sentinel). */
  counterparty: Uint8Array;
  /** nSequence value (BIP-68). Use `nextNSequence()` to derive from a
   *  cooldown-seconds target if you don't already have one. */
  nsequence: number;
  /** 32-byte txid of the UTXO this vault leaf is consuming.
   *  Empty / not-yet-known: pass 32 zero bytes (initial vault creation). */
  parentTxid: Uint8Array;
}

export interface VaultCell {
  bytes: Uint8Array; // 1024 bytes
}

export interface VaultMultisigSig {
  /** Concatenated [len][sig||sighash_byte] entries the host_checkmultisig
   *  ABI expects (per `core/cell-engine/src/host.zig:407–438`). */
  packed: Uint8Array;
  /** Number of sigs encoded — equals `member_indices.length`. */
  sigCount: number;
}

// ──────────────────────────────────────────────────────────────────────
// createVault
// ──────────────────────────────────────────────────────────────────────

/**
 * Build a 1024-byte Tier-3 vault leaf cell per §6.2.1 + W11.
 *
 * The returned cell is LINEAR (per-tx; consumed by OP_SIGN in the wallet's
 * spend script). Invariants:
 *   • member_pubkeys count ∈ [1, VAULT_MAX_MEMBERS]
 *   • 1 ≤ threshold ≤ member_pubkeys.length
 *   • leafPrivKey, protocolHash, counterparty, parentTxid have the exact
 *     §6.2.1 lengths (32, 16, 33, 32).
 *   • Each member pubkey is exactly 33 bytes (compressed sec1).
 *   • nSequence is a u32 (validated to fit).
 *
 * Throws on any invariant violation. Returns a fresh Uint8Array — the
 * caller may mutate / persist / hash it freely.
 */
export function createVault(input: VaultCreateInput): VaultCell {
  if (input.memberPubkeys.length < 1 || input.memberPubkeys.length > VAULT_MAX_MEMBERS) {
    throw new Error(
      `createVault: memberPubkeys length must be in [1, ${VAULT_MAX_MEMBERS}], got ${input.memberPubkeys.length}`,
    );
  }
  if (
    input.threshold < 1 ||
    input.threshold > input.memberPubkeys.length ||
    !Number.isInteger(input.threshold)
  ) {
    throw new Error(`createVault: threshold ${input.threshold} out of range for ${input.memberPubkeys.length} members`);
  }
  if (input.leafPrivKey.length !== 32) {
    throw new Error('createVault: leafPrivKey must be 32 bytes');
  }
  if (input.protocolHash.length !== 16) {
    throw new Error('createVault: protocolHash must be 16 bytes');
  }
  if (input.counterparty.length !== 33) {
    throw new Error('createVault: counterparty must be 33 bytes');
  }
  if (input.parentTxid.length !== 32) {
    throw new Error('createVault: parentTxid must be 32 bytes');
  }
  for (let i = 0; i < input.memberPubkeys.length; i++) {
    const pk = input.memberPubkeys[i]!;
    if (pk.length !== VAULT_MEMBER_PUBKEY_LEN) {
      throw new Error(`createVault: memberPubkeys[${i}] must be ${VAULT_MEMBER_PUBKEY_LEN} bytes, got ${pk.length}`);
    }
    // Compressed sec1 prefix: 0x02 (even Y) or 0x03 (odd Y).
    if (pk[0] !== 0x02 && pk[0] !== 0x03) {
      throw new Error(`createVault: memberPubkeys[${i}][0] must be 0x02 or 0x03 (compressed sec1)`);
    }
  }
  if (!Number.isInteger(input.nsequence) || input.nsequence < 0 || input.nsequence > 0xffffffff) {
    throw new Error(`createVault: nsequence must be a u32, got ${input.nsequence}`);
  }

  const cell = new Uint8Array(CELL_SIZE);
  const dv = new DataView(cell.buffer);

  // Magic bytes
  dv.setUint32(0, MAGIC_1, true);
  dv.setUint32(4, MAGIC_2, true);
  dv.setUint32(8, MAGIC_3, true);
  dv.setUint32(12, MAGIC_4, true);
  // Linearity: LINEAR (per-tx leaf; OP_SIGN consumes it).
  dv.setUint32(16, LINEARITY_LINEAR, true);
  // Version
  dv.setUint32(20, 1, true);
  // Domain flag (Tier-3): canonical Zig layout puts this at offset 24 LE
  // (constants.zig:HEADER_OFFSET_FLAGS=24), but the TS host's
  // tierFromDomainFlag (host.ts:226) reads offset 28 BE. To keep the cell
  // round-trippable through host_persist_cell *and* preserve the Zig
  // canonical layout for any cross-runtime parsing, we write both.
  // (See `cartridges/wallet-headers/brain/src/host.ts:tierFromDomainFlag` for the BE-28
  // form. Reconciling these two locations is tracked separately — the TS
  // host predates v0.2 and v0.2 must not change Tier 0/1/2 flows.)
  dv.setUint32(24, VAULT_DOMAIN_FLAG, true);
  dv.setUint32(28, VAULT_DOMAIN_FLAG, false);

  // ── Payload ──
  // [00..32] leaf priv key
  cell.set(input.leafPrivKey, HEADER_SIZE + VAULT_OFFSET_LEAF_PRIVKEY);
  // [32..48] protocol_hash
  cell.set(input.protocolHash, HEADER_SIZE + VAULT_OFFSET_PROTOCOL_HASH);
  // [48..81] counterparty (33 bytes)
  cell.set(input.counterparty, HEADER_SIZE + VAULT_OFFSET_COUNTERPARTY);
  // [63..64] threshold (single byte)
  cell[HEADER_SIZE + VAULT_OFFSET_THRESHOLD] = input.threshold;
  // [64..229] member pubkey table (5 * 33 bytes; unused slots zeroed)
  for (let i = 0; i < input.memberPubkeys.length; i++) {
    const off = HEADER_SIZE + VAULT_OFFSET_MEMBER_PUBKEYS_START + i * VAULT_MEMBER_PUBKEY_LEN;
    cell.set(input.memberPubkeys[i]!, off);
  }
  // [229..233] nSequence (u32 LE)
  dv.setUint32(HEADER_SIZE + VAULT_OFFSET_NSEQUENCE, input.nsequence >>> 0, true);
  // [233..265] parent_txid
  cell.set(input.parentTxid, HEADER_SIZE + VAULT_OFFSET_PARENT_TXID);

  return { bytes: cell };
}

// ──────────────────────────────────────────────────────────────────────
// signVaultSpend
// ──────────────────────────────────────────────────────────────────────

/**
 * Produce an m-of-n vault multisig satisfaction over `tx_preimage_digest`.
 *
 * `member_indices` selects which member slots in `vault_cell.member_pubkeys`
 * are signing this spend; `member_sks` carries the matching private keys
 * (same length, same order). The output is the byte string the BSV
 * `host_checkmultisig` opcode consumes — `[len][DER||sighash]...` per
 * `core/cell-engine/src/host.zig:407–438`.
 *
 * Invariants:
 *   • member_indices.length === member_sks.length
 *   • member_indices.length >= vault_cell.threshold (caller must satisfy
 *     the threshold; we do not silently pad).
 *   • Each member sk derives the corresponding member pubkey at the indexed
 *     slot in the vault cell (verified before signing).
 *
 * The caller is responsible for wiping `member_sks` after use; we do not
 * retain references. RFC 6979 deterministic signing is used — repeated
 * calls with the same (sk, msg) yield the same DER bytes.
 */
export function signVaultSpend(
  vault_cell: VaultCell,
  member_indices: number[],
  member_sks: Uint8Array[],
  tx_preimage_digest: Uint8Array,
): VaultMultisigSig {
  if (vault_cell.bytes.length !== CELL_SIZE) {
    throw new Error('signVaultSpend: vault_cell must be 1024 bytes');
  }
  if (tx_preimage_digest.length !== 32) {
    throw new Error('signVaultSpend: tx_preimage_digest must be 32 bytes (HASH256)');
  }
  if (member_indices.length !== member_sks.length) {
    throw new Error(
      `signVaultSpend: member_indices length (${member_indices.length}) != member_sks length (${member_sks.length})`,
    );
  }
  if (member_indices.length === 0) {
    throw new Error('signVaultSpend: must supply at least one signing member');
  }

  const threshold = readThreshold(vault_cell);
  if (member_indices.length < threshold) {
    throw new Error(
      `signVaultSpend: only ${member_indices.length} signers supplied; threshold is ${threshold}`,
    );
  }

  // Verify each (index, sk) pair against the vault cell's stored pubkey.
  for (let i = 0; i < member_indices.length; i++) {
    const idx = member_indices[i]!;
    if (idx < 0 || idx >= VAULT_MAX_MEMBERS || !Number.isInteger(idx)) {
      throw new Error(`signVaultSpend: member_indices[${i}] = ${idx} out of range`);
    }
    const sk = member_sks[i]!;
    if (sk.length !== 32) {
      throw new Error(`signVaultSpend: member_sks[${i}] must be 32 bytes`);
    }
    const expectedPk = readMemberPubkey(vault_cell, idx);
    if (isAllZero(expectedPk)) {
      throw new Error(`signVaultSpend: vault has no member at index ${idx}`);
    }
    let derivedPk: Uint8Array;
    try {
      derivedPk = secp.getPublicKey(sk, true);
    } catch (e) {
      throw new Error(`signVaultSpend: bad member_sks[${i}]: ${(e as Error).message}`);
    }
    if (!bytesEqual(derivedPk, expectedPk)) {
      throw new Error(
        `signVaultSpend: member_sks[${i}] does not match vault.member_pubkeys[${idx}]`,
      );
    }
  }

  // BSV multisig consensus iterates pubkeys in stored order; the sigs must
  // appear in the same relative order as their pubkeys (low → high index).
  // Sort indices ascending and reorder sks in lockstep.
  const order = member_indices.map((idx, k) => ({ idx, sk: member_sks[k]! }));
  order.sort((a, b) => a.idx - b.idx);

  // Build the [len][DER||sighash]... blob.
  const SIG_MAX = 73; // 72 max DER + 1 sighash byte
  const buf = new Uint8Array(order.length * (1 + SIG_MAX));
  let off = 0;
  for (const { sk } of order) {
    const sig = secp.sign(tx_preimage_digest, sk).normalizeS();
    const der = encodeDerSig(sig.r, sig.s);
    buf[off] = der.length + 1; // include sighash byte
    off += 1;
    buf.set(der, off);
    off += der.length;
    buf[off] = SIGHASH_ALL_FORKID;
    off += 1;
  }

  return { packed: buf.slice(0, off), sigCount: order.length };
}

// ──────────────────────────────────────────────────────────────────────
// nextNSequence
// ──────────────────────────────────────────────────────────────────────

/**
 * Compute the BIP-68 nSequence value to bake into the *next* vault UTXO,
 * given a target cooldown in seconds. BSV honors BIP-68 relative locktime
 * at consensus (design §4.4 v0.2), so the UTXO becomes spendable on-chain
 * exactly `cooldownSecs` seconds after its containing tx is confirmed.
 *
 * Encoding (BIP-68):
 *   • bit 31 (DISABLE_FLAG): 0 — relative-lock active.
 *   • bit 22 (TYPE_FLAG): 1 — time mode (units of 512 seconds).
 *   • low 16 bits: cooldown / 512, rounded UP (so the actual cooldown is
 *     >= the requested value — never spend earlier than the user asked for).
 *
 * cooldownSecs = 0 returns the disabled value (DISABLE_FLAG set) so the
 * spend has no relative-lock constraint at all — appropriate for v0.1
 * fallback / disabled-cooldown policy. Negative or non-integer inputs
 * throw.
 *
 * Per §4.4 the wallet UI is responsible for computing the real-world
 * "next spendable at" time = parent_block_time + cooldownSecs and showing
 * the countdown. This function just builds the on-chain field.
 */
export function nextNSequence(_currentVault: VaultCell | null, cooldownSecs: number): number {
  if (!Number.isFinite(cooldownSecs) || cooldownSecs < 0 || !Number.isInteger(cooldownSecs)) {
    throw new Error(`nextNSequence: cooldownSecs must be a non-negative integer, got ${cooldownSecs}`);
  }
  if (cooldownSecs === 0) {
    return VAULT_NSEQUENCE_DISABLE_FLAG >>> 0;
  }
  // Round up so the encoded cooldown is never shorter than the policy.
  const units = Math.ceil(cooldownSecs / VAULT_NSEQUENCE_TIME_UNIT_SECONDS);
  if (units > VAULT_NSEQUENCE_VALUE_MASK) {
    // ~33.5 million seconds (≈ 388 days). Above this BIP-68 cannot encode
    // the value — fall back to MAX which is the longest expressible cooldown.
    return (VAULT_NSEQUENCE_TYPE_FLAG | VAULT_NSEQUENCE_VALUE_MASK) >>> 0;
  }
  return (VAULT_NSEQUENCE_TYPE_FLAG | (units & VAULT_NSEQUENCE_VALUE_MASK)) >>> 0;
}

/**
 * Inverse of `nextNSequence`: given an nSequence value (e.g., one read out
 * of a vault cell), return the cooldown in seconds. Returns null if the
 * disable bit is set (no relative-lock) or if bit 22 (time mode) is unset
 * (block-mode encoding — the caller is expected to convert blocks → seconds
 * via consensus rules; we don't have block height context here).
 */
export function decodeCooldownSeconds(nsequence: number): number | null {
  const v = nsequence >>> 0;
  if ((v & VAULT_NSEQUENCE_DISABLE_FLAG) !== 0) return null;
  if ((v & VAULT_NSEQUENCE_TYPE_FLAG) === 0) return null;
  const units = v & VAULT_NSEQUENCE_VALUE_MASK;
  return units * VAULT_NSEQUENCE_TIME_UNIT_SECONDS;
}

// ──────────────────────────────────────────────────────────────────────
// Read helpers (vault cell field accessors)
// ──────────────────────────────────────────────────────────────────────

export function readThreshold(vault_cell: VaultCell): number {
  return vault_cell.bytes[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]!;
}

export function readNSequence(vault_cell: VaultCell): number {
  return new DataView(
    vault_cell.bytes.buffer,
    vault_cell.bytes.byteOffset,
    vault_cell.bytes.byteLength,
  ).getUint32(HEADER_SIZE + VAULT_OFFSET_NSEQUENCE, true);
}

export function readParentTxid(vault_cell: VaultCell): Uint8Array {
  return vault_cell.bytes.slice(
    HEADER_SIZE + VAULT_OFFSET_PARENT_TXID,
    HEADER_SIZE + VAULT_OFFSET_PARENT_TXID + 32,
  );
}

export function readMemberPubkey(vault_cell: VaultCell, idx: number): Uint8Array {
  if (idx < 0 || idx >= VAULT_MAX_MEMBERS) {
    throw new Error(`readMemberPubkey: idx ${idx} out of range`);
  }
  const off = HEADER_SIZE + VAULT_OFFSET_MEMBER_PUBKEYS_START + idx * VAULT_MEMBER_PUBKEY_LEN;
  return vault_cell.bytes.slice(off, off + VAULT_MEMBER_PUBKEY_LEN);
}

export function readMemberCount(vault_cell: VaultCell): number {
  let count = 0;
  for (let i = 0; i < VAULT_MAX_MEMBERS; i++) {
    const pk = readMemberPubkey(vault_cell, i);
    if (!isAllZero(pk)) count++;
  }
  return count;
}

export function readLinearity(vault_cell: VaultCell): number {
  return new DataView(
    vault_cell.bytes.buffer,
    vault_cell.bytes.byteOffset,
    vault_cell.bytes.byteLength,
  ).getUint32(16, true);
}

export function readDomainFlag(vault_cell: VaultCell): number {
  return new DataView(
    vault_cell.bytes.buffer,
    vault_cell.bytes.byteOffset,
    vault_cell.bytes.byteLength,
  ).getUint32(24, true);
}

// ──────────────────────────────────────────────────────────────────────
// Internals
// ──────────────────────────────────────────────────────────────────────

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

function isAllZero(bytes: Uint8Array): boolean {
  for (let i = 0; i < bytes.length; i++) if (bytes[i] !== 0) return false;
  return true;
}

/**
 * Minimal DER encoder for ECDSA signatures (r, s) as bigint. Produces the
 * same bytes the BSV / bsvz signers emit — kept private to this module so
 * we don't introduce a dependency on `der.ts` (which lives in the host
 * shim and could change). Each integer is encoded with a leading 0x00 if
 * the high bit would otherwise mark it negative.
 */
function encodeDerSig(r: bigint, s: bigint): Uint8Array {
  const rBytes = encodeIntegerDer(r);
  const sBytes = encodeIntegerDer(s);
  const total = 2 + rBytes.length + 2 + sBytes.length;
  const out = new Uint8Array(2 + total);
  out[0] = 0x30;
  out[1] = total;
  let off = 2;
  out[off++] = 0x02;
  out[off++] = rBytes.length;
  out.set(rBytes, off);
  off += rBytes.length;
  out[off++] = 0x02;
  out[off++] = sBytes.length;
  out.set(sBytes, off);
  return out;
}

function encodeIntegerDer(n: bigint): Uint8Array {
  // bigint → minimal big-endian, prepend 0x00 if MSB high bit set.
  let hex = n.toString(16);
  if (hex.length % 2 === 1) hex = '0' + hex;
  let bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  // Strip leading zeros, but keep one if the next byte's high bit is set.
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0 && (bytes[start + 1]! & 0x80) === 0) {
    start++;
  }
  bytes = bytes.slice(start);
  if ((bytes[0]! & 0x80) !== 0) {
    const padded = new Uint8Array(bytes.length + 1);
    padded[0] = 0x00;
    padded.set(bytes, 1);
    bytes = padded;
  }
  return bytes;
}

// Test-friendly re-exports of internal magic so spec files can sanity-check
// the cell layout without re-defining constants.
export const _internal_for_tests = {
  LINEARITY_LINEAR,
  LINEARITY_AFFINE,
  LINEARITY_RELEVANT,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
};

```
