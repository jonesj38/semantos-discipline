---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/wasm_imports.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.403521+00:00
---

# src/ffi/wasm_imports.zig

```zig
// Semantos FFI — WASM Host Import Declarations
// Phase 30E: Adapter callback imports for wasm32-wasi target.
//
// When the FFI layer compiles to WASM, host adapter callbacks cannot use
// function pointers (those require the host to register C-compatible fn ptrs
// at init time). Instead, WASM uses its import table: the host provides
// implementations at instantiation time, and the kernel calls them as extern
// functions resolved at link time.
//
// These 7 imports match the callback signatures from callbacks.zig exactly.
// The "env" namespace is used (not "host") to avoid collision with the
// cell-engine's existing "host" crypto imports in packages/cell-engine/.
//
// WASI preview version: wasi_snapshot_preview1
// Rationale: wasi_snapshot_preview1 is the most widely supported WASI version
// across Node.js, wasmtime, wasmer, and browser polyfills. Preview2 (component
// model) is not yet stable enough for production use as of April 2026.

pub extern "env" fn host_storage_read(
    path_ptr: [*]const u8,
    path_len: usize,
    out_buf: [*]u8,
    inout_len: *usize,
) i32;

pub extern "env" fn host_storage_write(
    path_ptr: [*]const u8,
    path_len: usize,
    data: [*]const u8,
    data_len: usize,
) i32;

pub extern "env" fn host_identity_resolve(
    cert_id: [*]const u8,
    cert_len: usize,
    out_json: [*]u8,
    inout_len: *usize,
) i32;

pub extern "env" fn host_identity_derive(
    parent_cert: [*]const u8,
    cert_len: usize,
    resource_id: [*]const u8,
    rid_len: usize,
    domain_flag: u32,
    out_json: [*]u8,
    inout_len: *usize,
) i32;

pub extern "env" fn host_anchor_submit(
    state_hash: [*]const u8,
    hash_len: usize,
    metadata_json: [*]const u8,
    meta_len: usize,
    out_proof: [*]u8,
    inout_len: *usize,
) i32;

pub extern "env" fn host_network_publish(
    object_json: [*]const u8,
    json_len: usize,
) i32;

pub extern "env" fn host_network_resolve(
    query_json: [*]const u8,
    json_len: usize,
    out_results: [*]u8,
    inout_len: *usize,
) i32;

```
