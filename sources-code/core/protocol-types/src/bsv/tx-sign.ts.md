---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/tx-sign.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.869485+00:00
---

# core/protocol-types/src/bsv/tx-sign.ts

```ts
/**
 * Wire formats for `bsv.tx.sign.request` + `bsv.tx.sign.response` —
 * the substrate ↔ Dart-wallet sign-and-respond cell pair from
 * LOCKSCRIPT-CLEAVAGE.md §3.5 + §4c + §8.3.
 *
 * `bsv.tx.sign.request` is the cell the substrate emits when it has a
 * 32-byte sighash digest the wallet must sign. It carries:
 *
 *   - the digest (32 bytes, already committed to scope via SIGHASH flags)
 *   - a recipe_id pointing at the leaf-derivation context
 *   - the input_index the signature will land at
 *   - the sighash_flags byte (so the wallet appends it to the DER sig)
 *
 * Critically the wallet NEVER sees the handler script — only the digest
 * and the derivation context. This is the cleavage invariant: signing
 * commits to a hash, not to a script (§3.5).
 *
 * `bsv.tx.sign.response` carries the wallet's signed reply. It
 * references the request cell-hash so the broker can correlate response
 * to request, and carries the DER-encoded signature with the trailing
 * sighash-flag byte already appended (BSV convention).
 */

import {
  TX_PARTIAL_WIRE_VERSION,
  CELL_HASH_BYTES,
  MAX_INLINE_SIG_BYTES,
} from "./tx-partial";

/** Re-exported for callers wiring only the sign pair (no partial-tx group). */
export const TX_SIGN_WIRE_VERSION = TX_PARTIAL_WIRE_VERSION;

// ─────────────────────────── Sign request ─────────────────────────────

/**
 * Decoded sign-request payload.
 *
 * Layout (fixed):
 *
 *     0   1   VERSION = 1
 *     1  32   digest               (the 32-byte sighash to sign)
 *    33  32   recipe_id            (cell-hash of the derivation recipe)
 *    65   4   input_index (LE u32) (where the sig will land)
 *    69   1   sighash_flags        (e.g. 0x41 = SIGHASH_ALL | FORKID)
 *
 * Total: 70 bytes.
 */
export const TX_SIGN_REQUEST_BYTES = 70 as const;

export interface TxSignRequest {
  /** 32-byte sighash digest already committed to the scope via SIGHASH flags. */
  readonly digest: Uint8Array;
  /** Cell-hash of the derivation recipe the wallet uses to derive the leaf key. */
  readonly recipeId: Uint8Array;
  /** Input index in the eventual tx where this sig lands. */
  readonly inputIndex: number;
  /**
   * SIGHASH flags byte — typically 0x41 (SIGHASH_ALL | FORKID) for BIP-143
   * or with the CHRONICLE bit 0x20 set for OTDA-dispatch.
   */
  readonly sighashFlags: number;
}

export function encodeTxSignRequest(req: TxSignRequest): Uint8Array {
  if (req.digest.length !== 32) {
    throw new RangeError(
      `encodeTxSignRequest: digest must be 32 bytes (got ${req.digest.length})`,
    );
  }
  if (req.recipeId.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeTxSignRequest: recipeId must be ${CELL_HASH_BYTES} bytes ` +
        `(got ${req.recipeId.length})`,
    );
  }
  if (req.inputIndex < 0 || req.inputIndex > 0xffffffff) {
    throw new RangeError(
      `encodeTxSignRequest: inputIndex out of u32 range`,
    );
  }
  if (req.sighashFlags < 0 || req.sighashFlags > 0xff) {
    throw new RangeError(
      `encodeTxSignRequest: sighashFlags out of byte range`,
    );
  }
  const out = new Uint8Array(TX_SIGN_REQUEST_BYTES);
  out[0] = TX_SIGN_WIRE_VERSION;
  out.set(req.digest, 1);
  out.set(req.recipeId, 33);
  out[65] = req.inputIndex & 0xff;
  out[66] = (req.inputIndex >>> 8) & 0xff;
  out[67] = (req.inputIndex >>> 16) & 0xff;
  out[68] = (req.inputIndex >>> 24) & 0xff;
  out[69] = req.sighashFlags;
  return out;
}

export function decodeTxSignRequest(payload: Uint8Array): TxSignRequest {
  if (payload.length < TX_SIGN_REQUEST_BYTES) {
    throw new RangeError(
      `decodeTxSignRequest: payload must be ≥ ${TX_SIGN_REQUEST_BYTES} bytes ` +
        `(got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_SIGN_WIRE_VERSION) {
    throw new RangeError(
      `decodeTxSignRequest: unknown VERSION=${payload[0]}`,
    );
  }
  const inputIndex =
    (payload[65] |
      (payload[66] << 8) |
      (payload[67] << 16) |
      (payload[68] << 24)) >>>
    0;
  return {
    digest: payload.slice(1, 33),
    recipeId: payload.slice(33, 65),
    inputIndex,
    sighashFlags: payload[69],
  };
}

// ─────────────────────────── Sign response ────────────────────────────

/**
 * Decoded sign-response payload.
 *
 * Layout:
 *
 *     0   1     VERSION = 1
 *     1  32     request_cell_hash  (for correlation; cell-hash of the sign.request)
 *    33   2     sig_len (LE u16; 1..MAX_INLINE_SIG_BYTES)
 *    35  sig_len  signature (DER + trailing sighash-flag byte)
 */
export const TX_SIGN_RESPONSE_PREFIX_BYTES = 35 as const;

export interface TxSignResponse {
  /** Cell-hash of the bsv.tx.sign.request this response correlates to. */
  readonly requestCellHash: Uint8Array;
  /** DER-encoded ECDSA signature with trailing sighash-flag byte. */
  readonly signature: Uint8Array;
}

export function encodeTxSignResponse(res: TxSignResponse): Uint8Array {
  if (res.requestCellHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeTxSignResponse: requestCellHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (res.signature.length < 1 || res.signature.length > MAX_INLINE_SIG_BYTES) {
    throw new RangeError(
      `encodeTxSignResponse: signature length ${res.signature.length} ` +
        `out of range [1, ${MAX_INLINE_SIG_BYTES}]`,
    );
  }
  const out = new Uint8Array(TX_SIGN_RESPONSE_PREFIX_BYTES + res.signature.length);
  out[0] = TX_SIGN_WIRE_VERSION;
  out.set(res.requestCellHash, 1);
  out[33] = res.signature.length & 0xff;
  out[34] = (res.signature.length >>> 8) & 0xff;
  out.set(res.signature, TX_SIGN_RESPONSE_PREFIX_BYTES);
  return out;
}

export function decodeTxSignResponse(payload: Uint8Array): TxSignResponse {
  if (payload.length < TX_SIGN_RESPONSE_PREFIX_BYTES) {
    throw new RangeError(
      `decodeTxSignResponse: payload too short (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_SIGN_WIRE_VERSION) {
    throw new RangeError(
      `decodeTxSignResponse: unknown VERSION=${payload[0]}`,
    );
  }
  const sigLen = payload[33] | (payload[34] << 8);
  if (sigLen < 1 || sigLen > MAX_INLINE_SIG_BYTES) {
    throw new RangeError(
      `decodeTxSignResponse: sig_len=${sigLen} out of range`,
    );
  }
  if (payload.length < TX_SIGN_RESPONSE_PREFIX_BYTES + sigLen) {
    throw new RangeError(`decodeTxSignResponse: payload truncated`);
  }
  return {
    requestCellHash: payload.slice(1, 33),
    signature: payload.slice(
      TX_SIGN_RESPONSE_PREFIX_BYTES,
      TX_SIGN_RESPONSE_PREFIX_BYTES + sigLen,
    ),
  };
}

```
