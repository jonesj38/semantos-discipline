---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/browser/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.002059+00:00
---

# core/cell-engine/bindings/browser/loader.ts

```ts
/**
 * Browser WASM loader for the Semantos cell engine.
 *
 * Uses fetch() + WebAssembly.instantiateStreaming() for WASM loading.
 * Returns the same CellEngine class as the Bun loader — the engine is runtime-agnostic.
 *
 * Works in: Chrome extensions (MV3 service worker), web apps, iframes.
 */

import type { PlexusKernelWasm } from '@semantos/protocol-types';
import { createHostFunctions, createOctaveCellStore, type ScriptContext, type OctaveCellStore, type HostFunctionRegistry } from '../host-functions';
import { validateExports } from '../validation';
import { CellEngine } from '../bun/cell-engine';

export interface BrowserLoadOptions {
  /** URL to the WASM binary. Required — no filesystem path resolution in browser. */
  wasmUrl: string;
  /** 'full' (default) includes BSVZ native crypto + SPV. 'embedded' delegates crypto to host. */
  profile?: 'full' | 'embedded';
  /** Runtime context for blocktime/sequence. */
  hostContext?: ScriptContext;
  /** Per-instance octave cell store. Created fresh if omitted. */
  cellStore?: OctaveCellStore;
  /** Host function registry for OP_CALLHOST dispatch. */
  hostRegistry?: HostFunctionRegistry;
}

/**
 * Load the Semantos cell engine WASM binary from a URL and return a typed CellEngine.
 */
export async function loadCellEngine(options: BrowserLoadOptions): Promise<CellEngine> {
  const profile = options.profile ?? 'full';
  const cellStore = options.cellStore ?? createOctaveCellStore();

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
    options.hostContext,
    cellStore,
    options.hostRegistry,
  );

  const importObject = { host: hostFunctions };
  const response = await fetch(options.wasmUrl);

  let instance: WebAssembly.Instance;
  try {
    // Prefer streaming compilation when available.
    // Clone the response so the fallback can still read the body if streaming fails.
    const result = await WebAssembly.instantiateStreaming(
      Promise.resolve(response.clone()),
      importObject,
    );
    instance = result.instance;
  } catch {
    // Fallback for environments without streaming support (e.g., wrong MIME type)
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, importObject);
    instance = result.instance;
  }
  instanceRef = instance;

  validateExports(instance.exports, profile);

  return new CellEngine(
    instance.exports as unknown as PlexusKernelWasm,
    profile,
  );
}

```
