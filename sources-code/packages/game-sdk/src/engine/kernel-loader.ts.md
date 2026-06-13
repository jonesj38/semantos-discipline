---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/kernel-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.526275+00:00
---

# packages/game-sdk/src/engine/kernel-loader.ts

```ts
/**
 * WASM kernel loader — extracted from the legacy
 * `GameCellEngine.create()` so the platform-detection +
 * `kernel_init` path can be tested with explicit byte input.
 */

import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

import {
  loadKernel,
  type PlexusKernelWasm,
} from '../../../../core/cell-ops/src/wasm-interface';

import { createHostImports, type HostImportOptions } from './host-imports';

export interface LoadKernelOptions extends HostImportOptions {
  /** Raw WASM binary bytes (skip platform detection). */
  wasmBytes?: BufferSource;
  /** URL to fetch WASM binary from (browser). */
  wasmUrl?: string;
}

/** Resolve + load + init the WASM kernel. Throws on init failure. */
export async function bootKernel(opts: LoadKernelOptions): Promise<PlexusKernelWasm> {
  const wasmBytes = await resolveWasmBytes(opts);
  const memRef = { buffer: new ArrayBuffer(0) };
  const hostImports = createHostImports(memRef, { hostRegistry: opts.hostRegistry });
  const kernel = await loadKernel(wasmBytes, hostImports);
  // Patch memory reference so host fns can read/write live linear memory.
  memRef.buffer = kernel.memory.buffer;
  const rc = kernel.kernel_init();
  if (rc !== 0) {
    throw new Error(`kernel_init failed with code ${rc}`);
  }
  return kernel;
}

async function resolveWasmBytes(opts: LoadKernelOptions): Promise<BufferSource> {
  if (opts.wasmBytes) return opts.wasmBytes;
  if (opts.wasmUrl) {
    const response = await fetch(opts.wasmUrl);
    return response.arrayBuffer();
  }
  // Node/Bun fallback: walk up from `packages/game-sdk/src/engine/` to the
  // repo root and read from `core/cell-engine/zig-out/bin/cell-engine.wasm`.
  // (The original prompt-22 path was off by one — it pointed at
  // `extensions/cell-engine/...` which does not exist; cell-engine lives
  // under `core/`. Multiple wave-2 agents flagged the broken fallback.)
  const thisDir = dirname(fileURLToPath(import.meta.url));
  const wasmPath = join(thisDir, '../../../../core/cell-engine/zig-out/bin/cell-engine.wasm');
  return readFile(wasmPath);
}

```
