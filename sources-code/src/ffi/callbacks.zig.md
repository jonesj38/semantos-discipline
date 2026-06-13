---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/callbacks.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.401723+00:00
---

# src/ffi/callbacks.zig

```zig
// Semantos FFI — Adapter Callback Registration
// Phase 30B: Host registers C-compatible function pointers for adapter I/O.
//
// The kernel is pure and deterministic — no I/O. When it needs storage,
// identity resolution, anchoring, or network access, it invokes callbacks
// that the host registered during init. Callbacks are synchronous from the
// kernel's perspective: the kernel blocks on return.
//
// All function pointer types use callconv(.c). No closures, no Zig error
// unions, no capturing. Each callback returns i32 (0 = success, negative = error).

// ── Error codes (must match semantos.h and exports.zig) ──

const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_ALREADY_INIT: i32 = -4;

// ── Callback function pointer types ──

/// Host provides data for a storage key. Kernel passes a buffer; host fills
/// it with value bytes and sets *inout_len to actual length.
pub const HostStorageReadFn = *const fn (
    path: [*]const u8,
    path_len: usize,
    out_data: [*]u8,
    inout_len: *usize,
) callconv(.c) i32;

/// Kernel asks host to persist a key-value pair. Host is responsible for
/// durability. Returns 0 on success.
pub const HostStorageWriteFn = *const fn (
    path: [*]const u8,
    path_len: usize,
    data: [*]const u8,
    data_len: usize,
) callconv(.c) i32;

/// Given a certificate ID, host returns certificate JSON in the provided buffer.
pub const HostIdentityResolveFn = *const fn (
    cert_id: [*]const u8,
    cert_len: usize,
    out_json: [*]u8,
    inout_len: *usize,
) callconv(.c) i32;

/// Kernel asks host to derive a new certificate from a parent certificate
/// for a given resource and domain. Host returns derived cert JSON.
pub const HostIdentityDeriveFn = *const fn (
    parent_cert: [*]const u8,
    cert_len: usize,
    resource_id: [*]const u8,
    rid_len: usize,
    domain_flag: u32,
    out_json: [*]u8,
    inout_len: *usize,
) callconv(.c) i32;

/// Kernel submits a state hash for anchoring. Host returns an anchor proof
/// in the provided buffer.
pub const HostAnchorSubmitFn = *const fn (
    state_hash: [*]const u8,
    hash_len: usize,
    metadata_json: [*]const u8,
    meta_len: usize,
    out_proof: [*]u8,
    inout_len: *usize,
) callconv(.c) i32;

/// Kernel publishes a JSON object to the network. Host handles distribution.
pub const HostNetworkPublishFn = *const fn (
    object_json: [*]const u8,
    json_len: usize,
) callconv(.c) i32;

/// Kernel queries the network. Host returns matching results in the buffer.
pub const HostNetworkResolveFn = *const fn (
    query_json: [*]const u8,
    json_len: usize,
    out_results: [*]u8,
    inout_len: *usize,
) callconv(.c) i32;

// ── Callback registry ──

pub const CallbackRegistry = struct {
    host_storage_read: ?HostStorageReadFn = null,
    host_storage_write: ?HostStorageWriteFn = null,
    host_identity_resolve: ?HostIdentityResolveFn = null,
    host_identity_derive: ?HostIdentityDeriveFn = null,
    host_anchor_submit: ?HostAnchorSubmitFn = null,
    host_network_publish: ?HostNetworkPublishFn = null,
    host_network_resolve: ?HostNetworkResolveFn = null,
};

// ── Thread-local state ──

threadlocal var g_registry: CallbackRegistry = .{};
threadlocal var g_registered: bool = false;

// ── Internal API (used by exports.zig) ──

pub fn is_registered() bool {
    return g_registered;
}

pub fn get_registry() CallbackRegistry {
    return g_registry;
}

pub fn reset_callbacks() void {
    g_registry = .{};
    g_registered = false;
}

// ── Exported registration function ──

/// Register all 7 adapter callbacks. Each may be null if the host does not
/// implement that adapter. Once registered, re-registration is an error
/// (returns SEMANTOS_ERR_ALREADY_INIT). Call semantos_shutdown to reset.
pub export fn semantos_register_callbacks(
    storage_read: ?HostStorageReadFn,
    storage_write: ?HostStorageWriteFn,
    identity_resolve: ?HostIdentityResolveFn,
    identity_derive: ?HostIdentityDeriveFn,
    anchor_submit: ?HostAnchorSubmitFn,
    network_publish: ?HostNetworkPublishFn,
    network_resolve: ?HostNetworkResolveFn,
) callconv(.c) i32 {
    if (g_registered) {
        return SEMANTOS_ERR_ALREADY_INIT;
    }

    g_registry = .{
        .host_storage_read = storage_read,
        .host_storage_write = storage_write,
        .host_identity_resolve = identity_resolve,
        .host_identity_derive = identity_derive,
        .host_anchor_submit = anchor_submit,
        .host_network_publish = network_publish,
        .host_network_resolve = network_resolve,
    };
    g_registered = true;

    return SEMANTOS_OK;
}

```
