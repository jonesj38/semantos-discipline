---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask-and-cell/src/combined.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.017827+00:00
---

# core/pask-and-cell/src/combined.zig

```zig
// Combined kernel + pask entry point.
//
// Both core/cell-engine/src/main.zig and core/pask/src/main.zig declare
// `export fn` symbols. As long as the linker sees both modules referenced,
// it keeps every export alive. Wasm-side, the result is a single module
// exposing `kernel_*` (cell engine) plus `pask_*` (pask) — same linear
// memory, so the host shares one WebAssembly.Memory across both.
//
// Zero-copy boundary: anything written into linear memory by one kernel
// is directly readable by the other. Concretely: cell IDs / type paths
// the cell-engine writes can be passed straight into pask_upsert_node
// as a (ptr,len) pair without copying.

comptime {
    _ = @import("cell_main");
    _ = @import("pask_main");
}

```
