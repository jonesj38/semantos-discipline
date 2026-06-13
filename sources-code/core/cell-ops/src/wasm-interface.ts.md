---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm-interface.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.824852+00:00
---

# core/cell-ops/src/wasm-interface.ts

```ts
/**
 * @deprecated — use the split modules under
 * `core/cell-ops/src/wasm/` instead.
 *
 * Prompt 42 split this 481-LOC file into focused modules:
 *
 *   - error-codes.ts             — KernelError + TypeClassification
 *                                  enums + kernelErrorMessage (pure)
 *   - memory-helpers.ts          — read/write byte ranges + pointer
 *                                  arithmetic helpers (pure)
 *   - host-imports.ts            — PlexusKernelHostImports interface
 *                                  + createNoopHostImports builder
 *   - kernel-core.ts             — Phase 3 core + debug exports
 *                                  (PlexusKernelCoreExports)
 *   - cell-ops.ts                — Phase 1 cell + multicell pack
 *                                  exports (PlexusKernelCellOpsExports)
 *   - bca.ts                     — Phase 2 BCA exports
 *                                  (PlexusKernelBcaExports)
 *   - policy-eval.ts             — Phase 5 capability + optional SPV
 *                                  (PlexusKernelCapability/SpvExports)
 *   - wasm-interface-facade.ts   — composed PlexusKernelWasm
 *   - loader.ts                  — loadKernel + validateKernelExports
 *                                  + REQUIRED_KERNEL_EXPORTS
 *
 * Migration target imports:
 *
 *   import { loadKernel, type PlexusKernelWasm } from './wasm';
 *   import { KernelError } from './wasm/error-codes';
 *   import type { PlexusKernelHostImports } from './wasm/host-imports';
 */

export {
  KernelError,
  TypeClassification,
  isKnownKernelError,
  kernelErrorMessage,
} from './wasm/error-codes';

export type { PlexusKernelHostImports } from './wasm/host-imports';
export { createNoopHostImports } from './wasm/host-imports';

export type { PlexusKernelWasm } from './wasm/wasm-interface-facade';

export { loadKernel } from './wasm/loader';

```
