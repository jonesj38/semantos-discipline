---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/bca.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.827786+00:00
---

# core/cell-ops/src/wasm/bca.ts

```ts
/**
 * Phase 2 — Bitcoin Cellular Address (BCA) export contract.
 *
 * BCA derive + verify are the only Phase-2 exports; both are present
 * in both WASM profiles (no host-imports dependency, no SPV).
 */

/**
 * Phase 2 BCA exports (both profiles).
 */
export interface PlexusKernelBcaExports {
  /**
   * Derive a Bitcoin Cellular Address from a public key.
   * @returns 0 on success, error code otherwise
   */
  bca_derive(
    pubkeyPtr: number,
    prefixPtr: number,
    modifierPtr: number,
    sec: number,
    outPtr: number,
  ): number;

  /**
   * Verify a BCA against its derivation parameters.
   * @returns 0 if valid, error code otherwise
   */
  bca_verify(
    addrPtr: number,
    pubkeyPtr: number,
    prefixPtr: number,
    modifierPtr: number,
  ): number;
}

```
