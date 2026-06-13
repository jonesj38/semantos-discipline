---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wasm-contract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.844442+00:00
---

# core/protocol-types/src/wasm-contract.ts

```ts
/**
 * WASM export contract — derived from PlexusKernelWasm in CORE:WASM.
 */

export const REQUIRED_WASM_EXPORTS = [
  "kernel_init",
  "kernel_reset",
  "kernel_load_script",
  "kernel_load_unlock",
  "kernel_execute",
  "kernel_get_type_class",
  "kernel_get_opcount",
  "kernel_get_error",
  "kernel_stack_depth",
  "kernel_stack_peek",
  "kernel_stack_value_length",
  "kernel_alt_stack_value_length",
  "memory",
] as const;

export type WasmExportName = (typeof REQUIRED_WASM_EXPORTS)[number];

```
