---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/error-codes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.829173+00:00
---

# core/cell-ops/src/wasm/error-codes.ts

```ts
/**
 * Plexus 2-PDA kernel error codes — pure module, zero project imports.
 *
 * Per the prompt-42 spec acceptance criterion: "error-codes.ts has zero
 * imports from outside this folder (purity)." The error-code numeric values
 * mirror the kernel-side `core/cell-engine/src/errors.zig` enum and are
 * the wire-level contract returned from every `kernel_*` export.
 *
 * The lookup `kernelErrorMessage(code)` translates a numeric code into a
 * human-readable string for log + diagnostic output. It is intentionally
 * total — unknown values fall back to a "kernel error N" string rather
 * than throwing — so callers can log raw kernel return codes without
 * wrapping each call site in try/catch.
 */

/**
 * Error codes returned by kernel operations.
 *
 * The numeric values are the wire contract with the WASM module —
 * adding new variants must mirror the Zig source. SUCCESS is always 0.
 */
export enum KernelError {
  SUCCESS = 0,
  STACK_OVERFLOW = 1,
  STACK_UNDERFLOW = 2,
  SCRIPT_TOO_LARGE = 3,
  INVALID_OPCODE = 4,
  TYPE_MISMATCH = 5,
  VERIFY_FAILED = 6,
  DISABLED_OPCODE = 7,
  EXECUTION_LIMIT = 8,
  // Phase 1-2
  INVALID_MAGIC = 9,
  PAYLOAD_TOO_LARGE = 10,
  INVALID_CELL_COUNT = 11,
  BUFFER_TOO_SMALL = 12,
  INVALID_CONTINUATION_HEADER = 13,
  INVALID_SEC_PARAMETER = 14,
  BCA_COLLISION_EXCEEDED = 15,
  // Phase 3
  INVALID_SCRIPT = 16,
  INVALID_SIGHASH = 17,
  NO_TX_CONTEXT = 18,
  NESTING_DEPTH_EXCEEDED = 19,
  UNKNOWN_MACRO = 20,
  INVALID_PUSHDATA = 21,
  // Phase 4 — linearity enforcement + plexus opcodes
  CANNOT_DUPLICATE_LINEAR = 22,
  CANNOT_DISCARD_LINEAR = 23,
  CANNOT_DUPLICATE_AFFINE = 24,
  CANNOT_DISCARD_RELEVANT = 25,
  INVALID_LINEARITY_TYPE = 26,
  LINEARITY_CHECK_FAILED = 27,
  DOMAIN_FLAG_MISMATCH = 28,
  TYPE_HASH_MISMATCH = 29,
  OWNER_ID_MISMATCH = 30,
  CAPABILITY_TYPE_MISMATCH = 31,
  RESERVED_OPCODE = 32,
  // Phase 5 — BEEF/BUMP/SPV + capability verification
  BEEF_PARSE_ERROR = 33,
  BEEF_INVALID_PROOF = 34,
  BEEF_TXID_NOT_FOUND = 35,
  BUMP_INVALID_PROOF = 36,
  BUMP_PARSE_ERROR = 37,
  CAPABILITY_SCRIPT_FAILED = 38,
  CAPABILITY_NOT_LINEAR = 39,
  CHECKSIG_FAILED = 40,
  // Phase 6 — octave memory / pointer cells
  INVALID_POINTER_CELL = 41,
  HOST_FETCH_FAILED = 42,
  // Reserved
  NOT_IMPLEMENTED = 255,
}

/**
 * Type classification of a script or value.
 *
 * `UNCLASSIFIED` (-1) is the "no last-evaluated-script" sentinel
 * returned by `kernel_get_type_class()` before any execute call.
 */
export enum TypeClassification {
  LINEAR = 0,
  AFFINE = 1,
  RELEVANT = 2,
  UNCLASSIFIED = -1,
}

/**
 * Translate a numeric kernel error code into a human-readable string.
 *
 * Unknown codes return `"kernel error N"` rather than throwing — this
 * keeps the function total so callers can log any raw kernel return
 * value without extra guards. Use `KernelError[code]` directly if you
 * need the enum-name form (returns `undefined` for unknown values).
 */
export function kernelErrorMessage(code: number): string {
  switch (code) {
    case KernelError.SUCCESS:
      return 'success';
    case KernelError.STACK_OVERFLOW:
      return 'stack overflow';
    case KernelError.STACK_UNDERFLOW:
      return 'stack underflow';
    case KernelError.SCRIPT_TOO_LARGE:
      return 'script too large';
    case KernelError.INVALID_OPCODE:
      return 'invalid opcode';
    case KernelError.TYPE_MISMATCH:
      return 'type mismatch';
    case KernelError.VERIFY_FAILED:
      return 'verify failed';
    case KernelError.DISABLED_OPCODE:
      return 'disabled opcode';
    case KernelError.EXECUTION_LIMIT:
      return 'execution limit exceeded';
    case KernelError.INVALID_MAGIC:
      return 'invalid magic bytes';
    case KernelError.PAYLOAD_TOO_LARGE:
      return 'payload too large';
    case KernelError.INVALID_CELL_COUNT:
      return 'invalid cell count';
    case KernelError.BUFFER_TOO_SMALL:
      return 'buffer too small';
    case KernelError.INVALID_CONTINUATION_HEADER:
      return 'invalid continuation header';
    case KernelError.INVALID_SEC_PARAMETER:
      return 'invalid sec parameter';
    case KernelError.BCA_COLLISION_EXCEEDED:
      return 'BCA collision exceeded';
    case KernelError.INVALID_SCRIPT:
      return 'invalid script';
    case KernelError.INVALID_SIGHASH:
      return 'invalid sighash';
    case KernelError.NO_TX_CONTEXT:
      return 'no tx context';
    case KernelError.NESTING_DEPTH_EXCEEDED:
      return 'nesting depth exceeded';
    case KernelError.UNKNOWN_MACRO:
      return 'unknown macro';
    case KernelError.INVALID_PUSHDATA:
      return 'invalid pushdata';
    case KernelError.CANNOT_DUPLICATE_LINEAR:
      return 'cannot duplicate linear value';
    case KernelError.CANNOT_DISCARD_LINEAR:
      return 'cannot discard linear value';
    case KernelError.CANNOT_DUPLICATE_AFFINE:
      return 'cannot duplicate affine value';
    case KernelError.CANNOT_DISCARD_RELEVANT:
      return 'cannot discard relevant value';
    case KernelError.INVALID_LINEARITY_TYPE:
      return 'invalid linearity type';
    case KernelError.LINEARITY_CHECK_FAILED:
      return 'linearity check failed';
    case KernelError.DOMAIN_FLAG_MISMATCH:
      return 'domain flag mismatch';
    case KernelError.TYPE_HASH_MISMATCH:
      return 'type hash mismatch';
    case KernelError.OWNER_ID_MISMATCH:
      return 'owner id mismatch';
    case KernelError.CAPABILITY_TYPE_MISMATCH:
      return 'capability type mismatch';
    case KernelError.RESERVED_OPCODE:
      return 'reserved opcode';
    case KernelError.BEEF_PARSE_ERROR:
      return 'BEEF parse error';
    case KernelError.BEEF_INVALID_PROOF:
      return 'BEEF invalid proof';
    case KernelError.BEEF_TXID_NOT_FOUND:
      return 'BEEF txid not found';
    case KernelError.BUMP_INVALID_PROOF:
      return 'BUMP invalid proof';
    case KernelError.BUMP_PARSE_ERROR:
      return 'BUMP parse error';
    case KernelError.CAPABILITY_SCRIPT_FAILED:
      return 'capability script failed';
    case KernelError.CAPABILITY_NOT_LINEAR:
      return 'capability not linear';
    case KernelError.CHECKSIG_FAILED:
      return 'CHECKSIG failed';
    case KernelError.INVALID_POINTER_CELL:
      return 'invalid pointer cell';
    case KernelError.HOST_FETCH_FAILED:
      return 'host fetch failed';
    case KernelError.NOT_IMPLEMENTED:
      return 'not implemented';
    default:
      return `kernel error ${code}`;
  }
}

/** True iff the numeric code is a recognized `KernelError` variant. */
export function isKnownKernelError(code: number): boolean {
  return code in KernelError;
}

```
