---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/policy-eval.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.827224+00:00
---

# core/cell-ops/src/wasm/policy-eval.ts

```ts
/**
 * Phase 5 — capability + SPV verification export contract.
 *
 * The capability evaluator (`kernel_verify_capability`) is present
 * in *both* profiles. The BEEF/BUMP SPV exports are *only* in the
 * full profile (BSVZ-backed); they are declared optional on the
 * facade and the loader skips its presence check for them.
 *
 * The "policy-eval" name reflects that capability-token evaluation
 * is the kernel-side enforcement layer for cell ownership policy
 * — i.e. proving that a caller may unlock or transition a given
 * linear cell.
 */

/**
 * Capability evaluation export (both profiles).
 */
export interface PlexusKernelCapabilityExports {
  /**
   * Evaluate a capability token locking script.
   *
   * Pushes context (time, domain_flag, cap_type, pubkey) onto the
   * stack, enables enforcement, and executes the script.
   * @returns 0=valid capability, negative=error code
   */
  kernel_verify_capability(
    lockScriptPtr: number,
    lockScriptLen: number,
    ownerPubkeyPtr: number,
    capType: number,
    domainFlag: number,
    currentTime: number,
  ): number;
}

/**
 * Phase 5 SPV exports — full profile only.
 *
 * Each method is optional because `cell-engine-embedded.wasm` does
 * not export them. The `loadKernel()` runtime check intentionally
 * omits these from its required-exports list.
 */
export interface PlexusKernelSpvExports {
  /**
   * Detect BEEF version from raw binary data.
   * @returns 1=BRC-62 V1, 2=BRC-96 V2, 3=BRC-95 Atomic, -1=invalid
   */
  kernel_beef_version?(dataPtr: number, dataLen: number): number;

  /**
   * Verify a BEEF envelope contains valid merkle proof for a transaction.
   * @returns 0=valid, negative=error code
   */
  kernel_verify_beef?(
    beefPtr: number,
    beefLen: number,
    txidPtr: number,
  ): number;

  /**
   * Verify a BUMP merkle proof for a specific txid against an expected merkle root.
   * @returns 0=valid, negative=error code
   */
  kernel_verify_bump?(
    bumpPtr: number,
    bumpLen: number,
    txidPtr: number,
    merkleRootPtr: number,
  ): number;

  /**
   * Verify a BEEF envelope with caller-supplied trusted merkle roots (real SPV).
   * @returns 0=valid, negative=error code
   */
  kernel_verify_beef_spv?(
    beefPtr: number,
    beefLen: number,
    txidPtr: number,
    rootsPtr: number,
    rootsCount: number,
  ): number;
}

/**
 * Detect whether a kernel handle has the optional SPV exports
 * (i.e. is the full profile). Useful so callers can branch between
 * native + delegated SPV without inspecting the WASM module
 * directly.
 */
export function hasSpvExports(
  kernel: Partial<PlexusKernelSpvExports>,
): kernel is Required<PlexusKernelSpvExports> {
  return (
    typeof kernel.kernel_beef_version === 'function' &&
    typeof kernel.kernel_verify_beef === 'function' &&
    typeof kernel.kernel_verify_bump === 'function' &&
    typeof kernel.kernel_verify_beef_spv === 'function'
  );
}

```
