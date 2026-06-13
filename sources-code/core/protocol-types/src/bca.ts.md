---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bca.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.846420+00:00
---

# core/protocol-types/src/bca.ts

```ts
/**
 * BCA (Blockchain Channel Address) derivation and verification.
 *
 * Canonical TypeScript mirror of `core/cell-engine/src/bca.zig`.
 * This is the D-A0 deliverable — the shared BCA library consumed by every
 * adapter that needs to derive or verify peer identity from a BRC-52 cert.
 *
 * Spec source:   docs/spec/protocol-v0.5.md §4.3 (BCA derivation).
 * Reference impl: core/cell-engine/src/bca.zig.
 * Vectors:       core/cell-engine/tests/vectors/bca_*.json.
 *
 * Algorithm (from bca.zig::computeInterfaceId):
 *   data  = modifier(16B) ‖ subnetPrefix(8B) ‖ collisionCount(1B) ‖ pubkey(33B)
 *             = 58 bytes total
 *   hash1 = SHA-256(data)                          [32 bytes out]
 *   iid   = hash1[0..8]                            [first 8 bytes]
 *   iid[0] &= ~0x03                                // clear u-bit (0x02) and g-bit (0x01)
 *   iid[0]  = (iid[0] & 0x1F) | ((sec & 0x07) << 5)  // encode sec in 3 MSBs
 *   BCA   = subnetPrefix(8B) ‖ iid(8B)            [16 bytes = IPv6 address]
 *
 * NOTE (E-P2.1, from bca.zig): collision_count is always 0. The simplified
 * Semantos BCA algorithm has no collision oracle — derivation always succeeds
 * on the first hash. The sec parameter only affects bit encoding in the
 * interface identifier.
 *
 * Canonical term: BCA (glossary id: bca). K invariants: K2 (boundary
 * verification) is satisfied by verifyBca; K1 does not apply to this module.
 *
 * BRC standards: BRC-52 (cert identity binding — the pubkey input is the
 * BRC-52 cert's subjectPublicKey). This module is pure-TS with no I/O, no
 * side effects, and no mutation of inputs.
 */

import { Hash } from "@bsv/sdk";

// ── Constants (mirrors core/cell-engine/src/constants.zig BCA section) ──────

/** Maximum value of the sec parameter. Matches BCA_COLLISION_COUNT_MAX in constants.zig. */
export const BCA_COLLISION_COUNT_MAX = 2;

/** Size of the modifier field in bytes. */
export const BCA_MODIFIER_SIZE = 16;

/** Size of the subnet prefix field in bytes. */
export const BCA_SUBNET_PREFIX_SIZE = 8;

/** Size of the compressed secp256k1 public key in bytes. */
export const BCA_PUBLIC_KEY_SIZE = 33;

/** Size of the BCA (IPv6 address) in bytes. */
export const BCA_IPV6_ADDRESS_SIZE = 16;

/**
 * Total size of the hash input buffer:
 *   modifier(16) + subnetPrefix(8) + collisionCount(1) + pubkey(33) = 58 bytes.
 * Matches BCA_DATA_SIZE in bca.zig.
 */
export const BCA_DATA_SIZE = 58;

/** Default subnet prefix: fe80::/64 (link-local). */
export const BCA_DEFAULT_SUBNET_PREFIX: Readonly<Uint8Array> = new Uint8Array([
  0xfe, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]);

/** Default modifier: 16 zero bytes. */
export const BCA_DEFAULT_MODIFIER: Readonly<Uint8Array> = new Uint8Array(
  BCA_MODIFIER_SIZE,
);

/** Default sec parameter. */
export const BCA_DEFAULT_SEC = 0;

// ── Input / output types ─────────────────────────────────────────────────────

/**
 * Input to `deriveBca` / `verifyBca`.
 *
 * All byte fields accept either a `Uint8Array` (preferred) or a lowercase
 * hex string of the appropriate length. Defaults are applied for optional
 * fields as documented below.
 */
export interface BcaInput {
  /**
   * 33-byte compressed secp256k1 public key (the BRC-52 cert's
   * subjectPublicKey). Accepts Uint8Array or 66-char hex string.
   */
  subjectPublicKey: Uint8Array | string;

  /**
   * 8-byte IPv6 subnet prefix. Accepts Uint8Array or 16-char hex string.
   * Default: `fe80::/64` (link-local, `fe80000000000000`).
   */
  subnetPrefix?: Uint8Array | string;

  /**
   * 16-byte modifier (opaque; distinguishes BCA universes).
   * Accepts Uint8Array or 32-char hex string.
   * Default: 16 zero bytes.
   */
  modifier?: Uint8Array | string;

  /**
   * Security parameter (0–7). Encoded in the 3 MSBs (bits 5-7 from LSB)
   * of interface identifier byte 0. Values above BCA_COLLISION_COUNT_MAX (2)
   * are validated — `deriveBca` throws; `verifyBca` returns false.
   * Default: 0.
   */
  sec?: number;
}

/**
 * Result returned by `deriveBca`.
 *
 * The `controllerId` field holds the raw 16-byte BCA address bytes, which is
 * the canonical internal representation (analogous to BCAOutput.address in
 * bca.zig). The `bca` field is the 32-char lowercase hex encoding — this is
 * the wire/log/response format consumed by World Host and the overlay.
 */
export interface BcaResult {
  /**
   * The derived BCA as a 32-char lowercase hex string (16 bytes).
   * This matches the `expectedAddress` field in the conformance vectors.
   */
  bca: string;

  /**
   * The raw 16-byte BCA address bytes.
   * Equivalent to `BCAOutput.address` in bca.zig.
   */
  controllerId: Uint8Array;

  /**
   * Collision count used during derivation. Always 0 in the simplified
   * algorithm (NOTE E-P2.1: no collision oracle).
   */
  collisionCount: number;
}

// ── Hex utility helpers ───────────────────────────────────────────────────────

/**
 * Convert a lowercase hex string to a Uint8Array.
 * Throws on odd length or non-hex characters.
 */
export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) {
    throw new Error(
      `BCA: hex string has odd length ${hex.length}; must be even`,
    );
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    const b = parseInt(hex.slice(i, i + 2), 16);
    if (Number.isNaN(b)) {
      throw new Error(`BCA: invalid hex byte at offset ${i}: "${hex.slice(i, i + 2)}"`);
    }
    out[i / 2] = b;
  }
  return out;
}

/**
 * Convert a Uint8Array to a lowercase hex string.
 */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Normalise a byte-field input: accept either Uint8Array or hex string.
 * Validates the byte length against `expectedLen`.
 */
function normaliseBytes(
  field: Uint8Array | string,
  fieldName: string,
  expectedLen: number,
): Uint8Array {
  let bytes: Uint8Array;
  if (typeof field === "string") {
    bytes = hexToBytes(field);
  } else {
    // Copy to avoid mutating caller's buffer.
    bytes = new Uint8Array(field);
  }
  if (bytes.length !== expectedLen) {
    throw new Error(
      `BCA: ${fieldName} must be ${expectedLen} bytes, got ${bytes.length}`,
    );
  }
  return bytes;
}

// ── Core algorithm ────────────────────────────────────────────────────────────

/**
 * Compute the 8-byte interface identifier for a given collision count.
 *
 * Direct port of `computeInterfaceId` from `core/cell-engine/src/bca.zig`.
 * This function is the inner loop of both `deriveBca` and `verifyBca`.
 *
 * @param pubkey      - 33-byte compressed pubkey
 * @param subnetPrefix - 8-byte subnet prefix
 * @param modifier    - 16-byte modifier
 * @param sec         - security parameter (0–7)
 * @param cc          - collision count for this attempt
 * @returns           - 8-byte interface identifier
 */
function computeInterfaceId(
  pubkey: Uint8Array,
  subnetPrefix: Uint8Array,
  modifier: Uint8Array,
  sec: number,
  cc: number,
): Uint8Array {
  // Concatenate: modifier(16) ‖ subnetPrefix(8) ‖ collisionCount(1) ‖ pubkey(33)
  // = 58 bytes total. Matches BCA_DATA_SIZE in bca.zig.
  const data = new Uint8Array(BCA_DATA_SIZE);
  data.set(modifier, 0);       // [0..16)
  data.set(subnetPrefix, 16);  // [16..24)
  data[24] = cc;               // [24]
  data.set(pubkey, 25);        // [25..58)

  // SHA-256 via @bsv/sdk's Hash.sha256 — produces a number[].
  const digest = Hash.sha256(Array.from(data)) as number[];

  // Interface identifier = first 8 bytes of hash.
  const iid = new Uint8Array(digest.slice(0, 8));

  // RFC 4291 bit manipulation on byte 0 (mirrors bca.zig exactly):
  //   u-bit = bit 6 from MSB (= bit 1 from LSB, mask 0x02) → clear
  //   g-bit = bit 7 from MSB (= bit 0 from LSB, mask 0x01) → clear
  //   Combined: iid[0] &= ~0x03  (i.e. &= 0xFC)
  iid[0] = iid[0]! & 0xfc;

  // Encode sec in 3 MSBs (bits 0-2 from MSB = bits 5-7 from LSB):
  //   iid[0] = (iid[0] & 0x1F) | ((sec & 0x07) << 5)
  iid[0] = (iid[0] & 0x1f) | ((sec & 0x07) << 5);

  return iid;
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Derive a BCA (Bitcoin-Certified Address / IPv6 peer identifier) from a
 * BRC-52 cert's subject public key and network parameters.
 *
 * This is the canonical entry point for the D-A0 BCA library. It is a pure
 * function: no I/O, no side effects, no mutation of inputs.
 *
 * Direct port of `deriveBCA` from `core/cell-engine/src/bca.zig` (the
 * simplified algorithm with no collision oracle — collision_count is always 0).
 *
 * @param input - Typed input; see {@link BcaInput} for field descriptions.
 * @returns     - {@link BcaResult} containing the hex BCA, raw bytes, and
 *               collision count (always 0 in the simplified algorithm).
 * @throws      - If `sec` exceeds {@link BCA_COLLISION_COUNT_MAX} (mirrors
 *               `BCAError.invalid_sec_parameter` from bca.zig).
 * @throws      - If any byte field has wrong length or non-hex content.
 */
export function deriveBca(input: BcaInput): BcaResult {
  const sec = input.sec ?? BCA_DEFAULT_SEC;

  if (sec > BCA_COLLISION_COUNT_MAX) {
    throw new Error(
      `BCA: invalid_sec_parameter — sec must be 0..${BCA_COLLISION_COUNT_MAX}, got ${sec}`,
    );
  }

  const pubkey = normaliseBytes(
    input.subjectPublicKey,
    "subjectPublicKey",
    BCA_PUBLIC_KEY_SIZE,
  );
  const subnetPrefix = normaliseBytes(
    input.subnetPrefix ?? BCA_DEFAULT_SUBNET_PREFIX,
    "subnetPrefix",
    BCA_SUBNET_PREFIX_SIZE,
  );
  const modifier = normaliseBytes(
    input.modifier ?? BCA_DEFAULT_MODIFIER,
    "modifier",
    BCA_MODIFIER_SIZE,
  );

  // NOTE (E-P2.1): simplified algorithm — cc is always 0. No collision oracle.
  const iid = computeInterfaceId(pubkey, subnetPrefix, modifier, sec, 0);

  // BCA = subnetPrefix(8B) ‖ iid(8B) = 16 bytes (IPv6 address).
  const controllerId = new Uint8Array(BCA_IPV6_ADDRESS_SIZE);
  controllerId.set(subnetPrefix, 0);
  controllerId.set(iid, 8);

  return {
    bca: bytesToHex(controllerId),
    controllerId,
    collisionCount: 0,
  };
}

/**
 * Verify that a 16-byte BCA address was derived from the given public key and
 * parameters.
 *
 * Direct port of `verifyBCA` from `core/cell-engine/src/bca.zig`. Tries
 * collision counts 0, 1, 2 (at most 3 hash evaluations). The sec used for
 * matching is extracted from the address itself (the 3 MSBs of iid[0]), not
 * from the input — this mirrors the Zig reference exactly.
 *
 * This is a pure function: no I/O, no side effects, no mutation of inputs.
 *
 * @param addressHex - 32-char hex string (16 bytes) of the BCA to verify.
 * @param input      - Parameters used during derivation. `sec` in input is
 *                     ignored — the sec is extracted from the address itself.
 * @returns          - `true` if the address matches any cc ∈ [0, BCA_COLLISION_COUNT_MAX].
 */
export function verifyBca(addressHex: string, input: BcaInput): boolean {
  let addressBytes: Uint8Array;
  try {
    addressBytes = normaliseBytes(addressHex, "address", BCA_IPV6_ADDRESS_SIZE);
  } catch {
    return false;
  }

  let pubkey: Uint8Array;
  let subnetPrefix: Uint8Array;
  let modifier: Uint8Array;
  try {
    pubkey = normaliseBytes(
      input.subjectPublicKey,
      "subjectPublicKey",
      BCA_PUBLIC_KEY_SIZE,
    );
    subnetPrefix = normaliseBytes(
      input.subnetPrefix ?? BCA_DEFAULT_SUBNET_PREFIX,
      "subnetPrefix",
      BCA_SUBNET_PREFIX_SIZE,
    );
    modifier = normaliseBytes(
      input.modifier ?? BCA_DEFAULT_MODIFIER,
      "modifier",
      BCA_MODIFIER_SIZE,
    );
  } catch {
    return false;
  }

  const targetIid = addressBytes.slice(8, 16);

  // Extract sec from the address's interface identifier (3 MSBs of byte 0).
  // This mirrors verifyBCA in bca.zig exactly.
  const sec = (targetIid[0]! >> 5) & 0x07;

  for (let cc = 0; cc <= BCA_COLLISION_COUNT_MAX; cc++) {
    const candidate = computeInterfaceId(pubkey, subnetPrefix, modifier, sec, cc);
    // Re-encode the sec from the address (not from input) to match — same as Zig.
    candidate[0] = (candidate[0]! & 0x1f) | (sec << 5);

    if (candidate.every((b, i) => b === targetIid[i])) {
      return true;
    }
  }

  return false;
}

/**
 * Convenience function: derive a BCA from a 66-char hex-encoded compressed
 * pubkey using the default parameters (fe80::/64, zero modifier, sec=0).
 *
 * This is the function signature the D-V3 stub (`deriveBcaFromPubkey`) used.
 * It is re-exported from `runtime/verifier-sidecar/src/bca.ts` to preserve
 * backward compatibility with the World Host integration.
 *
 * @param pubkeyHex - 33-byte compressed pubkey, hex-encoded (66 chars).
 * @returns         - 32-char lowercase hex BCA string.
 */
export function deriveBcaFromPubkey(pubkeyHex: string): string {
  return deriveBca({ subjectPublicKey: pubkeyHex }).bca;
}

```
