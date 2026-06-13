---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.828066+00:00
---

# core/cell-ops/src/wasm/loader.ts

```ts
/**
 * WASM kernel loader — instantiates the compiled WASM bytes against
 * a host-imports object and verifies the export contract.
 *
 * Per prompt-42: the loader is the lifecycle module (similar to
 * `packages/game-sdk/src/engine/kernel-loader.ts`'s `bootKernel`
 * pattern). The pure pieces (error codes, memory helpers, per-feature
 * wrappers) are kept separate so this file owns *only* WASM
 * instantiation + export validation.
 */

import type { PlexusKernelHostImports } from './host-imports';
import type { PlexusKernelWasm } from './wasm-interface-facade';

/**
 * Required exports present in *both* WASM profiles.
 *
 * The full profile additionally exports the optional SPV functions
 * (`kernel_verify_beef`, `kernel_verify_bump`, `kernel_beef_version`,
 * `kernel_verify_beef_spv`); those are intentionally NOT in this
 * list because the embedded profile omits them.
 */
export const REQUIRED_KERNEL_EXPORTS = [
  // Phase 3: Kernel core
  'kernel_init',
  'kernel_reset',
  'kernel_load_script',
  'kernel_load_unlock',
  'kernel_execute',
  'kernel_get_type_class',
  'kernel_get_opcount',
  'kernel_get_error',
  'kernel_stack_depth',
  'kernel_stack_peek',
  // Phase 3: Debug/stepping
  'kernel_step',
  'kernel_get_pc',
  'kernel_get_current_op',
  'kernel_alt_stack_depth',
  'kernel_alt_stack_peek',
  'kernel_load_tx_context',
  'kernel_set_output_index',
  'kernel_set_enforcement',
  // Phase 1: Cell packing
  'cell_pack',
  'cell_unpack',
  'cell_validate_magic',
  // Phase 1: Multi-cell packing
  'multicell_pack',
  'multicell_unpack',
  // Phase 2: BCA
  'bca_derive',
  'bca_verify',
  // Phase 5: Capability (both profiles)
  'kernel_verify_capability',
  // WASM memory
  'memory',
] as const;

export type RequiredKernelExport = (typeof REQUIRED_KERNEL_EXPORTS)[number];

/**
 * Loads a WASM module and instantiates it with host imports.
 * Returns the `PlexusKernelWasm` interface bound to the instantiated
 * module.
 *
 * Validates that every entry in `REQUIRED_KERNEL_EXPORTS` is
 * present on the instance — throws if any export is missing.
 *
 * @param wasmBytes - The compiled WASM binary
 * @param hostImports - Implementation of host import functions
 * @returns Promise resolving to the initialized PlexusKernelWasm interface
 */
export async function loadKernel(
  wasmBytes: BufferSource,
  hostImports: PlexusKernelHostImports,
): Promise<PlexusKernelWasm> {
  const importObject = {
    host: hostImports as unknown as Record<string, unknown>,
  };

  const wasmModule = await WebAssembly.instantiate(
    wasmBytes,
    importObject as WebAssembly.Imports,
  );
  const exports = wasmModule.instance.exports as unknown as PlexusKernelWasm;

  validateKernelExports(exports as unknown as Record<string, unknown>);

  return exports;
}

/**
 * Verify that every required export is present on `exports`.
 * Exposed independently so callers that already have a WASM
 * instance handle (e.g. tests, custom loaders) can validate it
 * without re-instantiating.
 */
export function validateKernelExports(
  exports: Record<string, unknown>,
): void {
  for (const exportName of REQUIRED_KERNEL_EXPORTS) {
    if (!(exportName in exports)) {
      throw new Error(`WASM module missing required export: ${exportName}`);
    }
  }
}

```
