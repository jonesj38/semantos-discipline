---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.826941+00:00
---

# core/cell-ops/src/wasm/index.ts

```ts
/**
 * core/cell-ops wasm — public surface for the prompt-42 split.
 *
 * Migration target imports:
 *
 *   import { loadKernel } from '@semantos/cell-ops/wasm';
 *   import { KernelError, kernelErrorMessage } from '@semantos/cell-ops/wasm/error-codes';
 *   import { readBytes, writeBytes } from '@semantos/cell-ops/wasm/memory-helpers';
 *
 * Existing imports of the legacy `wasm-interface.ts` re-export shim
 * continue to work for one release cycle and forward to this folder.
 */

export {
  KernelError,
  TypeClassification,
  isKnownKernelError,
  kernelErrorMessage,
} from './error-codes';

export {
  pointerAdd,
  readBytes,
  readBytesView,
  readCString,
  readU32LE,
  readUtf8,
  writeBytes,
  writeU32LE,
  writeUtf8,
  type WasmMemoryLike,
} from './memory-helpers';

export {
  createNoopHostImports,
  type PlexusKernelHostImports,
} from './host-imports';

export {
  executeScript,
  initKernelCore,
  resetKernel,
  type PlexusKernelCoreExports,
} from './kernel-core';

export type { PlexusKernelCellOpsExports } from './cell-ops';
export type { PlexusKernelBcaExports } from './bca';

export {
  hasSpvExports,
  type PlexusKernelCapabilityExports,
  type PlexusKernelSpvExports,
} from './policy-eval';

export type { PlexusKernelWasm } from './wasm-interface-facade';

export {
  REQUIRED_KERNEL_EXPORTS,
  loadKernel,
  validateKernelExports,
  type RequiredKernelExport,
} from './loader';

```
