---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/wasm-interface-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.826662+00:00
---

# core/cell-ops/src/wasm/wasm-interface-facade.ts

```ts
/**
 * `PlexusKernelWasm` — the composed export contract that the Zig-
 * compiled WASM module must satisfy.
 *
 * Two profiles exist:
 * - Full profile (cell-engine.wasm): BSVZ native crypto + SPV
 *   verification exports. Crypto host imports are unused (no-ops).
 * - Embedded profile (cell-engine-embedded.wasm): Crypto delegated
 *   to TS host imports. SPV exports (`kernel_verify_beef`,
 *   `kernel_verify_bump`, `kernel_beef_version`,
 *   `kernel_verify_beef_spv`) are NOT present.
 *
 * Per the prompt-42 split, this file is now a thin composition of
 * the per-feature export sub-interfaces declared alongside:
 *
 *   - `./kernel-core.ts`     — Phase 3 kernel core + debug/stepping
 *   - `./cell-ops.ts`        — Phase 1 cell + multicell packing
 *   - `./bca.ts`             — Phase 2 BCA derive/verify
 *   - `./policy-eval.ts`     — Phase 5 capability eval + optional SPV
 *
 * Each phase wrapper can now be improved independently — adding a
 * new BCA export only touches `./bca.ts`, not the kernel core
 * interface.
 */

import type { PlexusKernelBcaExports } from './bca';
import type { PlexusKernelCellOpsExports } from './cell-ops';
import type { PlexusKernelCoreExports } from './kernel-core';
import type {
  PlexusKernelCapabilityExports,
  PlexusKernelSpvExports,
} from './policy-eval';

/**
 * Combined kernel WASM export surface — every export the kernel
 * may provide, across both profiles. Optional members reflect the
 * full-vs-embedded profile distinction (see `policy-eval.ts`).
 */
export interface PlexusKernelWasm
  extends PlexusKernelCoreExports,
    PlexusKernelCellOpsExports,
    PlexusKernelBcaExports,
    PlexusKernelCapabilityExports,
    PlexusKernelSpvExports {
  /** WASM linear memory (for reading script results, error messages, stack values). */
  readonly memory: WebAssembly.Memory;
}

```
