---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/spv-verify.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.870638+00:00
---

# core/protocol-types/src/bsv/spv-verify.ts

```ts
/**
 * Wire format for `bsv.spv.verify.intent` and `bsv.spv.verify.result`
 * cell payloads.
 *
 * Spec: docs/design/LINEAR-CELL-SPV-STATE.md §3.2 (host call ABI),
 *       §2.2 (operation intent / result types).
 *
 * These are the simplest pair of operation cells in the BSV substrate
 * catalog and the first the Dart cell-dispatcher (PR-C11-7f) targets
 * end-to-end. The intent carries a BEEF + txid; the result echoes the
 * txid plus a valid|invalid flag.
 *
 * ## Inline-BEEF limit
 *
 * PR-C11-7e ships the **inline** form only: the BEEF bytes live in
 * the intent cell's payload directly, capped at the cell-payload
 * budget. Above that limit, the BEEF MUST be carried as a
 * `bsv.beef.carriage.head/body` chain and referenced by head-hash —
 * the carriage encoding lands in PR-C11-7e-3 along with the linear-
 * anchor wire format.
 *
 * The inline cap is the cell payload size (1024 − header − layout
 * overhead). The encoder enforces it; the decoder validates it. For
 * a 1024-byte cell with a 62-byte CellHeader (per
 * `core/protocol-types/src/constants.ts`) and our 36-byte intent
 * layout overhead (1 + 32 + 1 + 2), the inline BEEF cap is ~923 bytes.
 *
 * ## Wire layouts
 *
 * ### Intent payload
 *
 *     offset  size  field
 *      0       1    VERSION       — currently 1
 *      1      32    txid          — 32-byte internal byte order
 *     33       1    FLAGS         — bit 0 = inline-beef (1), reserved
 *     34       2    beef_len      — u16 LE; 0 ≤ beef_len ≤ INLINE_BEEF_MAX_BYTES
 *     36     beef_len  beef bytes — inline BEEF (when FLAGS bit 0 set)
 *
 * Total: 36 + beef_len bytes.
 *
 * ### Result payload
 *
 *     offset  size  field
 *      0       1    VERSION       — currently 1
 *      1       1    OUTCOME       — 0 = invalid, 1 = valid, 2 = error
 *      2      32    txid          — echoed from the intent for correlation
 *     34       1    error_tag     — 0 when OUTCOME != error; otherwise
 *                                   one of SpvVerifyErrorTag (below)
 *
 * Total: 35 bytes.
 *
 * The `error_tag` is a short discriminant — it tells the caller which
 * kind of failure occurred (parse error, txid absent, no trusted root,
 * etc.). Detailed diagnostics live in the audit log; the wire stays lean.
 *
 * ## Why u16 (not u32) for beef_len
 *
 * Inline BEEFs never exceed the cell payload budget (~923 bytes), so
 * u16 is sufficient and saves 2 bytes. Larger BEEFs use the carriage
 * chain (PR-C11-7e-3) whose head cell carries its total_len in a u32.
 */

/** Wire-format version for both intent and result. */
export const SPV_VERIFY_WIRE_VERSION = 1 as const;

/** Length of an intent's fixed-layout prefix, in bytes. */
export const SPV_VERIFY_INTENT_PREFIX_BYTES = 36 as const;

/** Length of the result payload, in bytes (fixed). */
export const SPV_VERIFY_RESULT_BYTES = 35 as const;

/**
 * Upper bound on inline-BEEF size for `encodeSpvVerifyIntent`.
 *
 * 1024-byte cell budget − 62-byte CellHeader − 36-byte intent prefix
 * = 926 bytes of inline BEEF, rounded down to a safe 920 to leave a
 * couple bytes for any future header-field growth. BEEFs larger than
 * this MUST use the carriage chain (PR-C11-7e-3).
 */
export const INLINE_BEEF_MAX_BYTES = 920 as const;

/** FLAGS bit positions in the intent payload. */
export const SpvVerifyIntentFlag = {
  /** bit 0 — when set, the BEEF is inline in the payload after the prefix. */
  InlineBeef: 1 << 0,
} as const;

/** Result OUTCOME byte values. */
export const SpvVerifyOutcome = {
  Invalid: 0,
  Valid: 1,
  Error: 2,
} as const;
export type SpvVerifyOutcome = (typeof SpvVerifyOutcome)[keyof typeof SpvVerifyOutcome];

/**
 * Result error_tag values. Coarse-grained on the wire; detailed
 * diagnostics live in the cell-engine + broker audit log.
 */
export const SpvVerifyErrorTag = {
  /** No error (OUTCOME != error). */
  None: 0,
  /** BEEF bytes were not parseable (malformed magic, truncated, etc.). */
  BeefParseFailed: 1,
  /** BEEF parsed but `txid` was not present in any of its transactions. */
  TxidAbsent: 2,
  /** BUMP merkle path resolved to a root that is not in the trusted set. */
  RootNotTrusted: 3,
  /** Empty BEEF buffer. */
  BeefEmpty: 4,
  /** Inline BEEF length exceeded `INLINE_BEEF_MAX_BYTES`. */
  BeefTooLarge: 5,
  /** Reserved for the carriage-chain reference case (PR-C11-7e-3). */
  CarriageRefUnsupported: 6,
  /** Catch-all for broker / host failures. */
  HostError: 7,
} as const;
export type SpvVerifyErrorTag = (typeof SpvVerifyErrorTag)[keyof typeof SpvVerifyErrorTag];

/** Decoded intent payload. */
export interface SpvVerifyIntent {
  /** 32-byte txid, internal byte order. */
  readonly txid: Uint8Array;
  /** Inline BEEF bytes. `null` when the carriage-chain form lands (PR-C11-7e-3). */
  readonly beef: Uint8Array;
}

/** Decoded result payload. */
export interface SpvVerifyResult {
  readonly outcome: SpvVerifyOutcome;
  /** Echoed txid from the intent the caller can use for correlation. */
  readonly txid: Uint8Array;
  /** `None` when `outcome !== Error`. */
  readonly errorTag: SpvVerifyErrorTag;
}

// ─────────────── Encoders ───────────────

/**
 * Encode an SPV verify intent payload. The result is the bytes that go
 * into the cell's payload field; the caller wraps with the CellHeader.
 *
 * Throws `RangeError` if `txid` is not 32 bytes or `beef` exceeds
 * `INLINE_BEEF_MAX_BYTES`.
 */
export function encodeSpvVerifyIntent(intent: SpvVerifyIntent): Uint8Array {
  if (intent.txid.length !== 32) {
    throw new RangeError(
      `encodeSpvVerifyIntent: txid must be 32 bytes (got ${intent.txid.length})`,
    );
  }
  if (intent.beef.length > INLINE_BEEF_MAX_BYTES) {
    throw new RangeError(
      `encodeSpvVerifyIntent: inline BEEF must be ≤ ${INLINE_BEEF_MAX_BYTES} bytes ` +
        `(got ${intent.beef.length}); use a carriage chain for larger BEEFs ` +
        `(PR-C11-7e-3)`,
    );
  }
  const out = new Uint8Array(SPV_VERIFY_INTENT_PREFIX_BYTES + intent.beef.length);
  out[0] = SPV_VERIFY_WIRE_VERSION;
  out.set(intent.txid, 1);
  out[33] = SpvVerifyIntentFlag.InlineBeef;
  // beef_len as u16 LE
  out[34] = intent.beef.length & 0xff;
  out[35] = (intent.beef.length >>> 8) & 0xff;
  out.set(intent.beef, SPV_VERIFY_INTENT_PREFIX_BYTES);
  return out;
}

/**
 * Encode an SPV verify result payload. Always 35 bytes.
 *
 * Throws `RangeError` if `txid` is not 32 bytes.
 */
export function encodeSpvVerifyResult(result: SpvVerifyResult): Uint8Array {
  if (result.txid.length !== 32) {
    throw new RangeError(
      `encodeSpvVerifyResult: txid must be 32 bytes (got ${result.txid.length})`,
    );
  }
  const out = new Uint8Array(SPV_VERIFY_RESULT_BYTES);
  out[0] = SPV_VERIFY_WIRE_VERSION;
  out[1] = result.outcome;
  out.set(result.txid, 2);
  out[34] = result.errorTag;
  return out;
}

// ─────────────── Decoders ───────────────

/**
 * Decode an SPV verify intent payload.
 *
 * Returns the parsed `SpvVerifyIntent`. Throws `RangeError` for any
 * malformed input (version mismatch, length too short, beef_len
 * exceeds inline cap, unknown flags). Decoders are strict: an invalid
 * wire form is a protocol violation, not a verification "no" — those
 * paths go through the result cell.
 */
export function decodeSpvVerifyIntent(payload: Uint8Array): SpvVerifyIntent {
  if (payload.length < SPV_VERIFY_INTENT_PREFIX_BYTES) {
    throw new RangeError(
      `decodeSpvVerifyIntent: payload must be ≥ ${SPV_VERIFY_INTENT_PREFIX_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  const version = payload[0];
  if (version !== SPV_VERIFY_WIRE_VERSION) {
    throw new RangeError(
      `decodeSpvVerifyIntent: unknown VERSION=${version}, expected ${SPV_VERIFY_WIRE_VERSION}`,
    );
  }
  const flags = payload[33];
  if ((flags & SpvVerifyIntentFlag.InlineBeef) === 0) {
    throw new RangeError(
      `decodeSpvVerifyIntent: only inline-beef form is supported in PR-C11-7e ` +
        `(carriage-chain form lands in 7e-3); FLAGS=0x${flags.toString(16)}`,
    );
  }
  const beefLen = payload[34] | (payload[35] << 8);
  if (beefLen > INLINE_BEEF_MAX_BYTES) {
    throw new RangeError(
      `decodeSpvVerifyIntent: beef_len=${beefLen} exceeds inline cap ` +
        `${INLINE_BEEF_MAX_BYTES}`,
    );
  }
  const expectedLen = SPV_VERIFY_INTENT_PREFIX_BYTES + beefLen;
  if (payload.length < expectedLen) {
    throw new RangeError(
      `decodeSpvVerifyIntent: payload truncated; declared beef_len=${beefLen} ` +
        `but only ${payload.length - SPV_VERIFY_INTENT_PREFIX_BYTES} BEEF bytes present`,
    );
  }
  return {
    // Slice ➜ copy so caller mutations don't poison the source buffer.
    txid: payload.slice(1, 33),
    beef: payload.slice(SPV_VERIFY_INTENT_PREFIX_BYTES, expectedLen),
  };
}

/**
 * Decode an SPV verify result payload. Always 35 bytes.
 *
 * Throws `RangeError` on any malformed input.
 */
export function decodeSpvVerifyResult(payload: Uint8Array): SpvVerifyResult {
  if (payload.length < SPV_VERIFY_RESULT_BYTES) {
    throw new RangeError(
      `decodeSpvVerifyResult: payload must be ≥ ${SPV_VERIFY_RESULT_BYTES} bytes ` +
        `(got ${payload.length})`,
    );
  }
  const version = payload[0];
  if (version !== SPV_VERIFY_WIRE_VERSION) {
    throw new RangeError(
      `decodeSpvVerifyResult: unknown VERSION=${version}, expected ${SPV_VERIFY_WIRE_VERSION}`,
    );
  }
  const outcome = payload[1] as SpvVerifyOutcome;
  if (
    outcome !== SpvVerifyOutcome.Invalid &&
    outcome !== SpvVerifyOutcome.Valid &&
    outcome !== SpvVerifyOutcome.Error
  ) {
    throw new RangeError(`decodeSpvVerifyResult: unknown OUTCOME=${outcome}`);
  }
  const errorTag = payload[34] as SpvVerifyErrorTag;
  // Range-check the tag enum strictly — silent corruption of error
  // semantics on the wire would be worse than a hard parse failure.
  const validTags = Object.values(SpvVerifyErrorTag) as number[];
  if (!validTags.includes(errorTag)) {
    throw new RangeError(`decodeSpvVerifyResult: unknown error_tag=${errorTag}`);
  }
  return {
    outcome,
    txid: payload.slice(2, 34),
    errorTag,
  };
}

```
