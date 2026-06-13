---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/validation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.984438+00:00
---

# core/cell-engine/bindings/validation.ts

```ts
/**
 * Shared WASM export validation — single source of truth for both loaders.
 */

/** Exports required in both full and embedded profiles. */
export const REQUIRED_EXPORTS = [
  'kernel_init', 'kernel_reset', 'kernel_load_script', 'kernel_load_unlock',
  'kernel_execute', 'kernel_get_type_class', 'kernel_get_opcount', 'kernel_get_error',
  'kernel_stack_depth', 'kernel_stack_peek',
  'kernel_step', 'kernel_get_pc', 'kernel_get_current_op',
  'kernel_alt_stack_depth', 'kernel_alt_stack_peek',
  'kernel_load_tx_context', 'kernel_set_enforcement',
  'cell_pack', 'cell_unpack', 'cell_validate_magic',
  'multicell_pack', 'multicell_unpack',
  'bca_derive', 'bca_verify',
  'kernel_verify_capability',
  'kernel_stack_value_length',
  'kernel_alt_stack_value_length',
  'memory',
] as const;

/** Additional exports required only in the full profile (BSVZ native crypto + SPV). */
export const FULL_PROFILE_EXPORTS = [
  'kernel_beef_version', 'kernel_verify_beef', 'kernel_verify_bump',
] as const;

/**
 * Validate that a WASM instance exports all required functions for the given profile.
 * Throws with a descriptive message listing any missing exports.
 */
export function validateExports(
  exports: WebAssembly.Exports,
  profile: 'full' | 'embedded',
): void {
  const missing: string[] = [];
  for (const name of REQUIRED_EXPORTS) {
    if (!(name in exports)) missing.push(name);
  }
  if (profile === 'full') {
    for (const name of FULL_PROFILE_EXPORTS) {
      if (!(name in exports)) missing.push(name);
    }
  }
  if (missing.length > 0) {
    throw new Error(
      `WASM module (${profile} profile) missing required exports: ${missing.join(', ')}`
    );
  }
}

```
