---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/bun/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.002918+00:00
---

# core/cell-engine/bindings/bun/loader.ts

```ts
/**
 * Bun-native WASM loader for the Semantos cell engine.
 *
 * Uses Bun.file() for fast WASM loading.
 * Returns a CellEngine instance with typed API — no raw pointers exposed.
 */

import { join } from 'path';
import { existsSync } from 'fs';
import type { PlexusKernelWasm } from '@semantos/protocol-types';
import { createHostFunctions, createOctaveCellStore, type ScriptContext, type OctaveCellStore, type HostFunctionRegistry } from '../host-functions';
import { validateExports } from '../validation';
import { CellEngine } from './cell-engine';

export interface BunLoadOptions {
  /** Path to the WASM binary. Auto-resolved from package root if omitted. */
  wasmPath?: string;
  /** 'full' (default) includes BSVZ native crypto + SPV. 'embedded' delegates crypto to host. */
  profile?: 'full' | 'embedded';
  /** Runtime context for blocktime/sequence. */
  hostContext?: ScriptContext;
  /** Per-instance octave cell store. Created fresh if omitted. */
  cellStore?: OctaveCellStore;
  /** Host function registry for OP_CALLHOST dispatch. */
  hostRegistry?: HostFunctionRegistry;
}

const PACKAGE_ROOT = join(import.meta.dir, '..', '..');

function resolveWasmPath(profile: 'full' | 'embedded', customPath?: string): string {
  if (customPath) return customPath;
  const filename = profile === 'embedded' ? 'cell-engine-embedded.wasm' : 'cell-engine.wasm';
  // Prefer zig-out/bin/ (dev build), fall back to dist/ (packaged distribution)
  const devPath = join(PACKAGE_ROOT, 'zig-out', 'bin', filename);
  if (existsSync(devPath)) return devPath;
  return join(PACKAGE_ROOT, 'dist', filename);
}

/**
 * Load the Semantos cell engine WASM binary and return a typed CellEngine.
 */
export async function loadCellEngine(options?: BunLoadOptions): Promise<CellEngine> {
  const profile = options?.profile ?? 'full';
  const wasmPath = resolveWasmPath(profile, options?.wasmPath);
  const cellStore = options?.cellStore ?? createOctaveCellStore();

  // Use Bun.file() for fast WASM loading
  const wasmFile = Bun.file(wasmPath);
  const wasmBytes = await wasmFile.arrayBuffer();

  // Create a MemoryProxy that defers to the instance's memory.
  // This is needed because host functions access memory during instantiation,
  // before we have a reference to the instance's memory.
  let instanceRef: WebAssembly.Instance | null = null;
  const memProxy = {
    get buffer(): ArrayBuffer {
      if (instanceRef?.exports.memory) {
        return (instanceRef.exports.memory as WebAssembly.Memory).buffer;
      }
      return new ArrayBuffer(0);
    },
  };

  const hostFunctions = createHostFunctions(
    memProxy as unknown as WebAssembly.Memory,
    options?.hostContext,
    cellStore,
    options?.hostRegistry,
  );

  const { instance } = await WebAssembly.instantiate(wasmBytes, {
    host: hostFunctions,
  });
  instanceRef = instance;

  validateExports(instance.exports, profile);

  return new CellEngine(
    instance.exports as unknown as PlexusKernelWasm,
    profile,
  );
}

```
