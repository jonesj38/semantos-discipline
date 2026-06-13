---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/bindings/ts/src/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.934819+00:00
---

# core/pask/bindings/ts/src/loader.ts

```ts
/**
 * Pask WASM loader. Instantiates pask.wasm (freestanding profile) and
 * returns a typed-arrays-and-functions handle. The caller controls
 * lifetime — there's no global state on the JS side.
 *
 * The freestanding profile has no imports, so instantiation is trivial.
 * If the future brings a host-callback profile (e.g. for telemetry),
 * extend the imports object here.
 */

export interface PaskExports {
  memory: WebAssembly.Memory;

  // Lifecycle
  pask_init: () => number;
  pask_set_config: (cfgPtr: number) => number;
  pask_reset: () => number;
  pask_last_error: () => number;

  // Mutation
  pask_upsert_node: (
    cellIdPtr: number,
    cellIdLen: number,
    typePathPtr: number,
    typePathLen: number,
    nowMs: bigint,
  ) => number;
  pask_find_node: (cellIdPtr: number, cellIdLen: number) => number;
  pask_interact_run: (
    primaryIdx: number,
    kindPtr: number,
    kindLen: number,
    effectiveStrength: number,
    relatedIdxPtr: number,
    relatedCount: number,
    nowMs: bigint,
  ) => number;
  pask_finalize: (nowMs: bigint) => number;

  // Read
  pask_node_count: () => number;
  pask_edge_count: () => number;
  pask_node_ptr: (idx: number) => number;
  pask_edge_ptr: (idx: number) => number;
  pask_node_cell_id_ptr: (idx: number) => number;
  pask_node_h_state: (idx: number) => number;
  pask_node_is_stable: (idx: number) => number;
  pask_node_is_pruned: (idx: number) => number;
  pask_stable_count: () => number;
  pask_stable_threads_into: (outPtr: number, max: number) => number;

  // Zero-copy array views (Damian's array-extraction hook).
  pask_node_array_ptr: () => number;
  pask_edge_array_ptr: () => number;
  pask_node_stride: () => number;
  pask_edge_stride: () => number;
  pask_stable_thread_stride: () => number;
  pask_stable_threads_build: (max: number) => number;
  pask_stable_threads_buf_ptr: () => number;

  // Snapshot
  pask_snapshot_state: () => number;
  pask_restore_state: (ptr: number) => number;
  pask_snapshot_buf_ptr: () => number;
  pask_snapshot_buf_len: () => number;

  // Scratch buffer
  pask_scratch_ptr: () => number;
  pask_scratch_len: () => number;
}

export interface PaskInstance {
  exports: PaskExports;
  module: WebAssembly.Module;
  instance: WebAssembly.Instance;
}

/**
 * Load and instantiate pask.wasm. Pass the bytes yourself — Node, Deno,
 * Bun, and browser environments all expose `Response`/`fetch` differently
 * and we don't want to ship a polyfill.
 */
export async function loadPask(wasmBytes: BufferSource): Promise<PaskInstance> {
  const module = await WebAssembly.compile(wasmBytes);
  const instance = await WebAssembly.instantiate(module, {});
  const exports = instance.exports as unknown as PaskExports;
  const rc = exports.pask_init();
  if (rc !== 0) throw new Error(`pask_init failed: ${rc}`);
  return { exports, module, instance };
}

```
