---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wasmtime_runner_real.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.265445+00:00
---

# runtime/semantos-brain/src/wasmtime_runner_real.zig

```zig
// Phase Brain 2.5 — wasmtime backend (compiled only when
// `enable-wasmtime=true`).
//
// Wraps the wasmtime C API (`wasm.h` + `wasmtime/*.h`) and exposes:
//   • engineInit / engineDeinit                — process-level engine + linker
//   • instantiate                              — module → live Instance
//   • host-import callbacks (host_log, host_persist_cell, host_load_cell)
//
// Each callback's lifetime story:
//   1. `engineInit` creates the engine + a single linker shared across
//      modules.
//   2. For every host import we register a callback via
//      `wasmtime_linker_define_func`, with the user `env` pointing at a
//      `CallbackEnv` struct that carries (broker, module-kind, allocator).
//   3. `instantiate` compiles the module bytes, instantiates against the
//      linker, looks up the exported `memory` so subsequent callbacks
//      can decode (ptr, len) arguments into Zig slices.
//
// Module isolation: the `module_kind` is part of `CallbackEnv`, set
// per-instance, so when wallet-engine and headers-verifier are both
// loaded the broker's policy gate works on every dispatch.

const std = @import("std");
const broker_mod = @import("broker");
const module_loader = @import("module_loader");
const ripemd160 = @import("ripemd160");
const bsvz = @import("bsvz");
const content_store_local_fs_mod = @import("content_store_local_fs");
const ContentStoreLocalFs = content_store_local_fs_mod.ContentStoreLocalFs;
const content_store_uhrp_http_mod = @import("content_store_uhrp_http");
const UhrpHttpStore = content_store_uhrp_http_mod.UhrpHttpStore;

pub const c = @cImport({
    @cInclude("wasm.h");
    @cInclude("wasmtime.h");
});

const RunnerError = error{
    wasmtime_not_enabled,
    engine_init_failed,
    module_compile_failed,
    instance_link_failed,
    instance_init_failed,
    wasm_trap,
    out_of_memory,
};

/// Per-engine state. Owned by `Runner.impl`.
///
/// Linkers are *per-instance* (held in `Instance`) — wasmtime linkers
/// don't tolerate redefining the same import twice, and we need a
/// per-instance `CallbackEnv` so the broker's module-isolation policy
/// gate sees the right `Module` enum on every dispatch.
pub const EngineState = struct {
    engine: *c.wasm_engine_t,
};

/// Per-instance state.  Owned by the caller via `Instance.deinit`.
pub const Instance = struct {
    store: *c.wasmtime_store_t,
    linker: *c.wasmtime_linker_t,
    instance: c.wasmtime_instance_t,
    /// Exported `memory` — every wasm module we accept must export
    /// linear memory under the conventional name "memory".
    memory: c.wasmtime_memory_t,
    /// Heap-allocated; freed by `deinit`. Held by callbacks via the
    /// `env` pointer registered with each linker function.
    callback_env: *CallbackEnv,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Instance) void {
        c.wasmtime_linker_delete(self.linker);
        c.wasmtime_store_delete(self.store);
        self.allocator.destroy(self.callback_env);
    }
};

// ─────────────────────────────────────────────────────────────────────
// WSITE2.5 — handler invocation ABI
//
// Dynamic-route handlers expose:
//
//   exports:
//     memory:                                       linear memory
//     handle(method: u32, body_len: u32) -> u64     status<<32 | resp_len
//
// Wire protocol:
//   • Host writes the request body to memory[0..body_len].
//   • Host calls handle(method, body_len).
//   • Handler reads body from memory[0..body_len], computes response,
//     overwrites memory[0..resp_len] with the response bytes, and
//     returns u64 = (status: u16) << 32 | (resp_len: u32).
//   • Host reads the response back from memory[0..resp_len] and emits
//     it as the HTTP body with the matching status.
//
// `method` encoding (u32):
//   1=GET, 2=POST, 3=PUT, 4=DELETE, 5=PATCH, 6=OPTIONS, 7=HEAD, 0=other.
//
// Path is intentionally *not* passed at v0.1 — handlers are bound to a
// single `site.json` route, so they know what they serve.  Path-aware
// dispatch lands when wildcard / prefix routing does (WSITE2.6+).
// ─────────────────────────────────────────────────────────────────────

pub const HandlerError = error{
    handler_export_missing,
    handler_trap,
    handler_oob,
    response_too_large,
    out_of_memory,
};

pub const HandlerResponse = struct {
    status: u16,
    /// Allocator-owned bytes — the caller frees.
    body: []u8,
};

pub const Method = enum(u32) {
    other = 0,
    get = 1,
    post = 2,
    put = 3,
    delete_ = 4,
    patch = 5,
    options = 6,
    head = 7,
};

pub fn methodFromHttp(method: std.http.Method) Method {
    return switch (method) {
        .GET => .get,
        .POST => .post,
        .PUT => .put,
        .DELETE => .delete_,
        .PATCH => .patch,
        .OPTIONS => .options,
        .HEAD => .head,
        else => .other,
    };
}

/// Cap a single response at 4 MiB.  Operators wanting to stream large
/// payloads should fall back to static routes; v0.1 handlers are for
/// JSON / HTML / small binary responses.
pub const RESPONSE_CAP: usize = 4 * 1024 * 1024;

/// Cap inbound bodies at the same 4 MiB.  Larger bodies → 413.
pub const REQUEST_CAP: usize = 4 * 1024 * 1024;

/// Invoke the handler's `handle` export.  Caller owns the returned
/// `body` — free with the same allocator.  Resets the handler's memory
/// to all-zeros at the response window before write to keep a previous
/// request's response from leaking on early returns.
pub fn callHandlerHandle(
    self: *Instance,
    allocator: std.mem.Allocator,
    method: Method,
    body: []const u8,
) HandlerError!HandlerResponse {
    if (body.len > REQUEST_CAP) return error.response_too_large;
    const ctx = c.wasmtime_store_context(self.store) orelse return error.handler_trap;

    // 1. Look up the `handle` export.
    var handle_extern: c.wasmtime_extern_t = undefined;
    if (!c.wasmtime_instance_export_get(ctx, &self.instance, "handle", "handle".len, &handle_extern)) {
        return error.handler_export_missing;
    }
    if (handle_extern.kind != c.WASMTIME_EXTERN_FUNC) return error.handler_export_missing;
    const handle_func = handle_extern.of.func;

    // 2. Write the request body to memory[0..body.len].
    var memory = self.memory;
    const data = c.wasmtime_memory_data(ctx, &memory);
    const data_size = c.wasmtime_memory_data_size(ctx, &memory);
    if (body.len > data_size) return error.handler_oob;
    if (body.len > 0) @memcpy(data[0..body.len], body);

    // 3. Pack args + call.
    var args: [2]c.wasmtime_val_t = .{
        .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(@intFromEnum(method)) } },
        .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @intCast(body.len) } },
    };
    var results: [1]c.wasmtime_val_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    const err = c.wasmtime_func_call(ctx, &handle_func, &args[0], 2, &results[0], 1, &trap);
    if (err != null) {
        c.wasmtime_error_delete(err);
        return error.handler_trap;
    }
    if (trap != null) {
        c.wasm_trap_delete(trap);
        return error.handler_trap;
    }

    // 4. Decode the packed return: high 32 = status, low 32 = resp_len.
    if (results[0].kind != c.WASMTIME_I64) return error.handler_trap;
    const packed_ret: u64 = @bitCast(results[0].of.i64);
    const status_u32: u32 = @truncate(packed_ret >> 32);
    const resp_len_u32: u32 = @truncate(packed_ret & 0xFFFFFFFF);
    const status: u16 = @truncate(status_u32);
    const resp_len: usize = resp_len_u32;

    if (resp_len > RESPONSE_CAP) return error.response_too_large;
    // Re-fetch memory pointer in case the handler grew memory during handle().
    const data_after = c.wasmtime_memory_data(ctx, &memory);
    const data_after_size = c.wasmtime_memory_data_size(ctx, &memory);
    if (resp_len > data_after_size) return error.handler_oob;

    const body_dup = allocator.alloc(u8, resp_len) catch return error.out_of_memory;
    if (resp_len > 0) @memcpy(body_dup, data_after[0..resp_len]);
    return .{ .status = status, .body = body_dup };
}

/// User-data carried into every host-import callback. Lifetimes:
/// allocated when the instance is created; freed when the instance is
/// torn down. The store retains it via the linker's `void *data`
/// parameter so wasmtime keeps the pointer alive for callback duration.
const CallbackEnv = struct {
    broker: *broker_mod.Broker,
    module_kind: broker_mod.Module,
    allocator: std.mem.Allocator,
    /// Filled in *after* instantiate so callbacks can decode pointer/len
    /// arguments against the right linear memory. The runner sets this
    /// once the instance has its exported memory looked up.
    memory: ?c.wasmtime_memory_t,
    /// M4.1: optional octave-1 content store. Null when not configured —
    /// hostFetchCell returns 0 (failure) in that case. Caller owns the
    /// store lifetime; it must outlive the Instance.
    content_store: ?*ContentStoreLocalFs,
    /// M4.2: optional octave-2 UHRP-HTTP content store. Null when not configured —
    /// hostFetchCell returns 0 (failure) for octave=2 in that case. Caller owns the
    /// store lifetime; it must outlive the Instance.
    octave_2_store: ?*UhrpHttpStore,
};

// ─────────────────────────────────────────────────────────────────────
// Engine / linker lifecycle
// ─────────────────────────────────────────────────────────────────────

pub fn engineInit() !EngineState {
    // The 2PDA-WASM excise (PR1, commit edf91c1) removed fireTwoPda,
    // which was the only caller setting per-instance fuel caps. PR
    // #755 had enabled wasmtime_config_consume_fuel_set(config, true)
    // on the engine + paired it with an effectively-unlimited fuel
    // cap in instantiate for the legitimate (non-2PDA) module kinds.
    // With fireTwoPda gone, both pieces are orphaned — revert to
    // plain wasm_engine_new() and drop the instantiate-side workaround
    // (see below). PR4b's eventual script-handler dispatcher will use
    // executor opcount budgets, not wasmtime fuel.
    const engine = c.wasm_engine_new() orelse return error.engine_init_failed;
    return .{ .engine = engine };
}

pub fn engineDeinit(self: *EngineState) void {
    c.wasm_engine_delete(self.engine);
}

// ─────────────────────────────────────────────────────────────────────
// Instantiation
// ─────────────────────────────────────────────────────────────────────

pub fn instantiate(
    allocator: std.mem.Allocator,
    eng: *EngineState,
    broker: *broker_mod.Broker,
    loaded: *const module_loader.LoadedModule,
    module_kind: broker_mod.Module,
) !Instance {
    // 1. Compile the module bytes.
    var module: ?*c.wasmtime_module_t = null;
    {
        const err = c.wasmtime_module_new(eng.engine, loaded.bytes.ptr, loaded.bytes.len, &module);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return error.module_compile_failed;
        }
    }
    defer c.wasmtime_module_delete(module);

    // 2. Build a fresh store + context.
    const store = c.wasmtime_store_new(eng.engine, null, null) orelse return error.engine_init_failed;
    errdefer c.wasmtime_store_delete(store);
    const ctx = c.wasmtime_store_context(store) orelse return error.engine_init_failed;

    // 3. Allocate the callback env.  Memory is filled in after we look
    //    up the instance's exported memory; until then callbacks see
    //    `memory == null` and trap.
    const env_ptr = try allocator.create(CallbackEnv);
    errdefer allocator.destroy(env_ptr);
    env_ptr.* = .{
        .broker = broker,
        .module_kind = module_kind,
        .allocator = allocator,
        .memory = null,
        .content_store = null,
        .octave_2_store = null,
    };

    // 4. Build a fresh linker for this instance and register host imports
    //    with the per-instance env.  Per-instance linkers let each module
    //    have its own `CallbackEnv` (carrying the right `module_kind` for
    //    the broker policy gate) without redefining-import errors.
    const linker = c.wasmtime_linker_new(eng.engine) orelse return error.engine_init_failed;
    errdefer c.wasmtime_linker_delete(linker);
    try registerHostImports(linker, env_ptr);

    // 5. Instantiate.
    var instance: c.wasmtime_instance_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    {
        const err = c.wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return error.instance_link_failed;
        }
        if (trap != null) {
            c.wasm_trap_delete(trap);
            return error.instance_init_failed;
        }
    }

    // 6. Look up the exported "memory".  Modules without an exported
    //    memory can't pass byte buffers to the host — refuse to start
    //    those (they're not the wallet engine or headers verifier).
    var mem_export: c.wasmtime_extern_t = undefined;
    if (!c.wasmtime_instance_export_get(ctx, &instance, "memory", "memory".len, &mem_export)) {
        return error.instance_init_failed;
    }
    if (mem_export.kind != c.WASMTIME_EXTERN_MEMORY) return error.instance_init_failed;
    const memory = mem_export.of.memory;
    env_ptr.memory = memory;

    return .{
        .store = store,
        .linker = linker,
        .instance = instance,
        .memory = memory,
        .callback_env = env_ptr,
        .allocator = allocator,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Host imports
// ─────────────────────────────────────────────────────────────────────

fn registerHostImports(linker: *c.wasmtime_linker_t, env: *CallbackEnv) !void {
    // Module name on the WASM-import-side. The cell-engine uses "host"
    // (per `pub extern "host" fn host_*` declarations in host.zig).
    const host_module = "host";

    const i32_x2: []const c.wasm_valkind_t = &.{ c.WASM_I32, c.WASM_I32 };
    const i32_x3: []const c.wasm_valkind_t = &.{ c.WASM_I32, c.WASM_I32, c.WASM_I32 };
    const i32_x4: []const c.wasm_valkind_t = &.{ c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32 };
    const i32_x6: []const c.wasm_valkind_t = &.{ c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32 };
    const i32_x7: []const c.wasm_valkind_t = &.{ c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32, c.WASM_I32 };
    const empty: []const c.wasm_valkind_t = &.{};
    const ret_i32: []const c.wasm_valkind_t = &.{c.WASM_I32};

    // ── Brain 2.5 — storage + log ──────────────────────────────────────
    try defineFunc(linker, host_module, "host_log", i32_x2, empty, env, hostLog);
    try defineFunc(linker, host_module, "host_persist_cell", i32_x3, ret_i32, env, hostPersistCell);
    try defineFunc(linker, host_module, "host_load_cell", i32_x2, ret_i32, env, hostLoadCell);

    // ── Brain 2.6 — pure-Zig hashing ───────────────────────────────────
    // (ptr, len, out_ptr) → ()  where the host writes the digest at
    // *out_ptr in the module's linear memory.
    try defineFunc(linker, host_module, "host_sha256", i32_x3, empty, env, hostSha256);
    try defineFunc(linker, host_module, "host_sha1", i32_x3, empty, env, hostSha1);
    try defineFunc(linker, host_module, "host_ripemd160", i32_x3, empty, env, hostRipemd160);
    try defineFunc(linker, host_module, "host_hash160", i32_x3, empty, env, hostHash160);
    try defineFunc(linker, host_module, "host_hash256", i32_x3, empty, env, hostHash256);

    // ── Brain 2.6 — runtime context ────────────────────────────────────
    try defineFunc(linker, host_module, "host_get_blocktime", empty, ret_i32, env, hostGetBlocktime);
    try defineFunc(linker, host_module, "host_get_sequence", empty, ret_i32, env, hostGetSequence);

    // ── Brain 2.6 stubs that remain stubs ──────────────────────────────
    // host_call_by_name(ptr, len) → i32 (returns 0xFFFFFFFF for unknown)
    try defineFunc(linker, host_module, "host_call_by_name", i32_x2, ret_i32, env, hostCallByName);
    // host_fetch_cell(octave, slot, offset, out_ptr) → i32
    try defineFunc(linker, host_module, "host_fetch_cell", i32_x4, ret_i32, env, hostFetchCell);

    // ── Brain 2.7 — real secp256k1 + BRC-42 derivation via bsvz ────────
    // host_sign(sk_ptr, sk_len, msg_ptr, msg_len, out_ptr, out_buf_len, out_len_ptr) → i32
    try defineFunc(linker, host_module, "host_sign", i32_x7, ret_i32, env, hostSign);
    // host_checksig(pk_ptr, pk_len, msg_ptr, msg_len, sig_ptr, sig_len) → i32
    try defineFunc(linker, host_module, "host_checksig", i32_x6, ret_i32, env, hostChecksig);
    // host_derive_leaf(base_sk_ptr, base_sk_len, protocol_hash_ptr,
    //                   counterparty_ptr, index_lo, index_hi, out_leaf_ptr) → i32
    // The two i32s carrying `index` are the lo/hi halves of the u64 — Zig's
    // host.zig declares it as u64 in the host signature, but WASM passes
    // 64-bit values via 2 × i32 parameters in the C-API representation.
    // Actually wasmtime's func types let us declare i64 — let's use that
    // for clarity and match the cell-engine's `index: u64` signature.
    const i64_index_sig: []const c.wasm_valkind_t = &.{
        c.WASM_I32, c.WASM_I32, // base_sk_ptr, base_sk_len
        c.WASM_I32, // protocol_hash_ptr
        c.WASM_I32, // counterparty_ptr
        c.WASM_I64, // index
        c.WASM_I32, // out_leaf_ptr
    };
    try defineFunc(linker, host_module, "host_derive_leaf", i64_index_sig, ret_i32, env, hostDeriveLeaf);
    // host_state_next_index(protocol_hash_ptr, counterparty_ptr, out_index_ptr) → i32
    try defineFunc(linker, host_module, "host_state_next_index", i32_x3, ret_i32, env, hostStateNextIndex);

    // ── C11 PR-C11-7d — BEEF SPV verification ──────────────────────────
    // host_verify_beef_spv(beef_ptr, beef_len, txid_ptr) → i32
    //   beef_ptr / beef_len: serialized BEEF bytes
    //   txid_ptr:            pointer to 32-byte txid (internal byte order)
    //   returns: 0 = invalid (verification failed or BEEF malformed),
    //            1 = valid, propagates trap on broker / host error.
    //
    // The host-side broker composes `core/cell-engine/src/beef.zig::
    // verifyBeefSpv` with the HeaderStore-derived trusted roots.
    // See docs/design/LINEAR-CELL-SPV-STATE.md §3.2.
    try defineFunc(linker, host_module, "host_verify_beef_spv", i32_x3, ret_i32, env, hostVerifyBeefSpv);
}

fn defineFunc(
    linker: *c.wasmtime_linker_t,
    module: []const u8,
    name: []const u8,
    params: []const c.wasm_valkind_t,
    results: []const c.wasm_valkind_t,
    env: *CallbackEnv,
    cb: c.wasmtime_func_callback_t,
) !void {
    var param_vec: c.wasm_valtype_vec_t = undefined;
    var result_vec: c.wasm_valtype_vec_t = undefined;

    if (params.len == 0) {
        c.wasm_valtype_vec_new_empty(&param_vec);
    } else {
        // Largest current host import is host_sign with 7 i32 params.
        var ps: [8]?*c.wasm_valtype_t = .{ null, null, null, null, null, null, null, null };
        std.debug.assert(params.len <= ps.len);
        for (params, 0..) |k, i| ps[i] = c.wasm_valtype_new(k);
        c.wasm_valtype_vec_new(&param_vec, params.len, &ps[0]);
    }
    if (results.len == 0) {
        c.wasm_valtype_vec_new_empty(&result_vec);
    } else {
        var rs: [2]?*c.wasm_valtype_t = .{ null, null };
        std.debug.assert(results.len <= rs.len);
        for (results, 0..) |k, i| rs[i] = c.wasm_valtype_new(k);
        c.wasm_valtype_vec_new(&result_vec, results.len, &rs[0]);
    }

    const ftype = c.wasm_functype_new(&param_vec, &result_vec) orelse return error.engine_init_failed;
    defer c.wasm_functype_delete(ftype);

    const err = c.wasmtime_linker_define_func(
        linker,
        module.ptr,
        module.len,
        name.ptr,
        name.len,
        ftype,
        cb,
        env,
        null, // env finalizer — we own the env in the Instance and free on deinit
    );
    if (err != null) {
        c.wasmtime_error_delete(err);
        return error.engine_init_failed;
    }
}

/// Decode (i32 ptr, i32 len) WASM args into a Zig byte slice over the
/// instance's linear memory. Returns null if the (ptr, len) is out of
/// bounds.
fn readBytes(env: *CallbackEnv, ctx: *c.wasmtime_context_t, ptr: i32, len: i32) ?[]const u8 {
    if (ptr < 0 or len < 0) return null;
    const memory = env.memory orelse return null;
    const data = c.wasmtime_memory_data(ctx, &memory);
    const data_size = c.wasmtime_memory_data_size(ctx, &memory);
    const ptr_u: usize = @intCast(ptr);
    const len_u: usize = @intCast(len);
    if (ptr_u + len_u > data_size) return null;
    return data[ptr_u .. ptr_u + len_u];
}

fn writeBytes(env: *CallbackEnv, ctx: *c.wasmtime_context_t, ptr: i32, src: []const u8) bool {
    if (ptr < 0) return false;
    const memory = env.memory orelse return false;
    const data = c.wasmtime_memory_data(ctx, &memory);
    const data_size = c.wasmtime_memory_data_size(ctx, &memory);
    const ptr_u: usize = @intCast(ptr);
    if (ptr_u + src.len > data_size) return false;
    @memcpy(data[ptr_u .. ptr_u + src.len], src);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Concrete callbacks
// ─────────────────────────────────────────────────────────────────────

fn hostLog(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 2) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const ptr = args[0].of.i32;
    const len = args[1].of.i32;
    const slice = readBytes(e, ctx, ptr, len) orelse {
        // Out-of-bounds — silently ignore, audit it.
        e.broker.auditRecord(e.module_kind, "host_log", .err, "oob") catch {};
        return null;
    };
    // Trim to a safe bound for the audit detail (don't let a misbehaving
    // module dump megabytes into the log).
    const snippet = slice[0..@min(slice.len, 256)];
    e.broker.auditRecord(e.module_kind, "host_log", .ok, snippet) catch {};
    return null;
}

fn hostPersistCell(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 3 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const slot_id_signed = args[0].of.i32;
    const ptr = args[1].of.i32;
    const len = args[2].of.i32;
    const slot_id: u32 = @intCast(slot_id_signed);
    const bytes = readBytes(e, ctx, ptr, len) orelse {
        results[0] = .{
            .kind = c.WASMTIME_I32,
            .of = .{ .i32 = 0 },
        };
        return null;
    };
    e.broker.hostPersistCell(e.module_kind, slot_id, bytes) catch {
        results[0] = .{
            .kind = c.WASMTIME_I32,
            .of = .{ .i32 = 0 },
        };
        return null;
    };
    results[0] = .{
        .kind = c.WASMTIME_I32,
        .of = .{ .i32 = 1 },
    };
    return null;
}

fn hostLoadCell(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 2 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const slot_id: u32 = @intCast(args[0].of.i32);
    const out_ptr = args[1].of.i32;
    const blob = e.broker.hostLoadCell(e.module_kind, slot_id) catch {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    if (!writeBytes(e, ctx, out_ptr, blob)) {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 1 } };
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Brain 2.6 — pure-Zig hashing callbacks
//
// These bypass the broker's audit log: the wallet engine calls them
// thousands of times per signing operation and audit-logging every
// invocation would be useless noise. Stateless cryptographic primitives
// are commodity — no policy enforcement needed at this layer.
// ─────────────────────────────────────────────────────────────────────

fn hostSha256(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 3) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const ptr = args[0].of.i32;
    const len = args[1].of.i32;
    const out_ptr = args[2].of.i32;
    const data = readBytes(e, ctx, ptr, len) orelse return null;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    _ = writeBytes(e, ctx, out_ptr, &digest);
    return null;
}

fn hostSha1(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 3) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const data = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse return null;
    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &digest, .{});
    _ = writeBytes(e, ctx, args[2].of.i32, &digest);
    return null;
}

fn hostRipemd160(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 3) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const data = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse return null;
    var digest: [20]u8 = undefined;
    ripemd160.hash(data, &digest);
    _ = writeBytes(e, ctx, args[2].of.i32, &digest);
    return null;
}

fn hostHash160(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 3) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const data = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse return null;
    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &sha, .{});
    var out: [20]u8 = undefined;
    ripemd160.hash(&sha, &out);
    _ = writeBytes(e, ctx, args[2].of.i32, &out);
    return null;
}

fn hostHash256(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = results;
    _ = nresults;
    if (nargs != 3) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse return null;
    const data = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse return null;
    var first: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &first, .{});
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    _ = writeBytes(e, ctx, args[2].of.i32, &second);
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Brain 2.6 — runtime context
// ─────────────────────────────────────────────────────────────────────

fn hostGetBlocktime(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = env;
    _ = caller;
    _ = args;
    _ = nargs;
    if (nresults != 1) return null;
    // u32 truncation of unix-seconds — fine until 2106. Same convention
    // the cell-engine uses today.
    const ts: u32 = @intCast(@as(i64, @intCast(@max(0, std.time.timestamp()))) & 0xFFFF_FFFF);
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @bitCast(ts) } };
    return null;
}

fn hostGetSequence(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = env;
    _ = caller;
    _ = args;
    _ = nargs;
    if (nresults != 1) return null;
    // The sequence number is set by the caller-side tx context. With no
    // tx context bound (Brain 2.6 isn't yet running real spends through the
    // engine), 0 is the safe default — same as the engine's `g_tx_ctx`
    // initial state.
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Brain 2.6 — stubs for crypto + advanced features (real impls in Brain 2.7)
//
// Returning a deterministic "failure" value lets the wasm module
// instantiate cleanly + reach the host-call site, where the failure
// becomes a VERIFY_FAILED-style script error rather than an
// instance_link_failed at startup.
// ─────────────────────────────────────────────────────────────────────

fn hostCallByName(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    _ = caller;
    _ = args;
    if (nargs != 2 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    e.broker.auditRecord(e.module_kind, "host_call_by_name", .err, "stub") catch {};
    // 0xFFFFFFFF = "unknown function" per the cell-engine convention.
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @bitCast(@as(u32, 0xFFFF_FFFF)) } };
    return null;
}

fn hostFetchCell(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    // ABI: host_fetch_cell(octave: u8, slot: u32, offset: u32, out_ptr: u32) → i32
    // All four WASM arguments arrive as i32 (WASM has no u8/u32 distinction).
    if (nargs != 4 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));

    const octave: u8 = @intCast(args[0].of.i32 & 0xFF);
    const slot: u32 = @bitCast(args[1].of.i32);
    const offset: u32 = @bitCast(args[2].of.i32);
    const out_ptr: i32 = args[3].of.i32;

    // Resolve the appropriate store based on octave.
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const memory = e.memory orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const mem_data = c.wasmtime_memory_data(ctx, &memory);
    const mem_size = c.wasmtime_memory_data_size(ctx, &memory);
    if (out_ptr < 0) {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    const out_ptr_u: usize = @intCast(out_ptr);
    if (out_ptr_u + 1024 > mem_size) {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    const out_buf: *[1024]u8 = @ptrCast(mem_data + out_ptr_u);

    switch (octave) {
        1 => {
            const cs = e.content_store orelse {
                e.broker.auditRecord(e.module_kind, "host_fetch_cell", .err, "no octave-1 content store configured") catch {};
                results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
                return null;
            };
            cs.fetchWindow(slot, offset, out_buf) catch {
                results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
                return null;
            };
        },
        2 => {
            const hs = e.octave_2_store orelse {
                e.broker.auditRecord(e.module_kind, "host_fetch_cell", .err, "no octave-2 UHRP-HTTP store configured") catch {};
                results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
                return null;
            };
            hs.fetchWindow(slot, offset, out_buf) catch {
                results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
                return null;
            };
        },
        else => {
            e.broker.auditRecord(e.module_kind, "host_fetch_cell", .err, "unsupported octave") catch {};
            results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
            return null;
        },
    }

    e.broker.auditRecord(e.module_kind, "host_fetch_cell", .ok, "ok") catch {};
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 1 } };
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Brain 2.7 — real secp256k1 + BRC-42 callbacks via bsvz
//
// host_sign         — wallet-engine only.  ECDSA over a 32-byte digest;
//                     writes DER (≤ 72 bytes) at out_ptr, length at
//                     out_len_ptr. Audit logged.
// host_checksig     — both modules permitted (commodity verification).
//                     No audit (called per-opcode during script eval).
// host_derive_leaf  — wallet-engine only.  BRC-42 child key. Audit
//                     logged with protocol-hash + index summary.
// host_state_next_index — wallet-engine only. Forwards to
//                          broker.hostStateNextIndex (audit + persist
//                          atomicity already in the broker method).
// ─────────────────────────────────────────────────────────────────────

fn hostSign(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 7 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    if (e.module_kind != .wallet_engine) {
        e.broker.auditRecord(e.module_kind, "host_sign", .denied, "wallet-engine-only") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const sk_bytes = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const msg_bytes = readBytes(e, ctx, args[2].of.i32, args[3].of.i32) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const out_ptr = args[4].of.i32;
    const out_buf_len: usize = @intCast(args[5].of.i32);
    const out_len_ptr = args[6].of.i32;

    if (sk_bytes.len != 32 or msg_bytes.len != 32 or out_buf_len == 0) {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "bad-args") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    var sk: [32]u8 = undefined;
    @memcpy(&sk, sk_bytes[0..32]);
    var digest: [32]u8 = undefined;
    @memcpy(&digest, msg_bytes[0..32]);

    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(sk) catch {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "bad-sk") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const der_sig = priv.signDigest(digest) catch {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "sign-failed") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const der = der_sig.bytes[0..der_sig.len];
    if (der.len > out_buf_len) {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "out-buf-too-small") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    if (!writeBytes(e, ctx, out_ptr, der)) {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "out-write-oob") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    // Write the DER length at out_len_ptr (4 bytes LE).
    var len_le: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_le, @intCast(der.len), .little);
    if (!writeBytes(e, ctx, out_len_ptr, &len_le)) {
        e.broker.auditRecord(e.module_kind, "host_sign", .err, "out-len-oob") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    e.broker.auditRecord(e.module_kind, "host_sign", .ok, "32-byte digest") catch {};
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 1 } };
    return null;
}

fn hostChecksig(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 6 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const pk_bytes = readBytes(e, ctx, args[0].of.i32, args[1].of.i32) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const msg_bytes = readBytes(e, ctx, args[2].of.i32, args[3].of.i32) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const sig_bytes = readBytes(e, ctx, args[4].of.i32, args[5].of.i32) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    if (msg_bytes.len != 32) {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    var digest: [32]u8 = undefined;
    @memcpy(&digest, msg_bytes[0..32]);

    const ok = bsvz.crypto.verifyDigest256RelaxedSec1(pk_bytes, digest, sig_bytes) catch false;
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = if (ok) 1 else 0 } };
    return null;
}

fn hostDeriveLeaf(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 6 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    if (e.module_kind != .wallet_engine) {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .denied, "wallet-engine-only") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const base_sk_ptr = args[0].of.i32;
    const base_sk_len = args[1].of.i32;
    const protocol_hash_ptr = args[2].of.i32;
    const counterparty_ptr = args[3].of.i32;
    const index = args[4].of.i64;
    const out_leaf_ptr = args[5].of.i32;

    const sk_bytes = readBytes(e, ctx, base_sk_ptr, base_sk_len) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const proto_bytes = readBytes(e, ctx, protocol_hash_ptr, 16) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const cp_bytes = readBytes(e, ctx, counterparty_ptr, 33) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    if (sk_bytes.len != 32) {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .err, "bad-sk-len") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }

    // BRC-42 invoice format: protocol_hash (16) || counterparty (33) || index (LE u64).
    var invoice: [16 + 33 + 8]u8 = undefined;
    @memcpy(invoice[0..16], proto_bytes[0..16]);
    @memcpy(invoice[16..49], cp_bytes[0..33]);
    std.mem.writeInt(u64, invoice[49..57], @bitCast(index), .little);

    var sk: [32]u8 = undefined;
    @memcpy(&sk, sk_bytes[0..32]);
    const ec_priv = bsvz.primitives.ec.PrivateKey.fromBytes(sk) catch {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .err, "bad-base-sk") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    // BRC-42 derives the child against a counterparty pubkey (compressed
    // SEC1, 33 bytes). The cell-engine's caller passes that as
    // `counterparty`.
    const ec_other = bsvz.primitives.ec.PublicKey.fromSec1(cp_bytes[0..33]) catch {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .err, "bad-cp-pubkey") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const child = ec_priv.deriveChild(ec_other, &invoice) catch {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .err, "derive-failed") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const child_bytes = child.toBytes();
    if (!writeBytes(e, ctx, out_leaf_ptr, &child_bytes)) {
        e.broker.auditRecord(e.module_kind, "host_derive_leaf", .err, "out-write-oob") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    var detail_buf: [64]u8 = undefined;
    const detail = std.fmt.bufPrint(&detail_buf, "index={d}", .{index}) catch "index=?";
    e.broker.auditRecord(e.module_kind, "host_derive_leaf", .ok, detail) catch {};
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 1 } };
    return null;
}

fn hostStateNextIndex(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 3 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const proto_bytes = readBytes(e, ctx, args[0].of.i32, 16) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const cp_bytes = readBytes(e, ctx, args[1].of.i32, 33) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const out_index_ptr = args[2].of.i32;

    var proto: [16]u8 = undefined;
    @memcpy(&proto, proto_bytes[0..16]);
    var cp: [33]u8 = undefined;
    @memcpy(&cp, cp_bytes[0..33]);

    const idx = e.broker.hostStateNextIndex(e.module_kind, &proto, &cp) catch {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    var idx_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &idx_le, idx, .little);
    if (!writeBytes(e, ctx, out_index_ptr, &idx_le)) {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    }
    results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 1 } };
    return null;
}

// C11 PR-C11-7d — BEEF SPV verification host import binding.
//
// Wire signature:  host_verify_beef_spv(beef_ptr i32, beef_len i32,
//                                       txid_ptr i32) -> i32
//   beef_ptr / beef_len: serialized BEEF bytes in linear memory.
//   txid_ptr:            pointer to 32-byte txid (internal byte order).
//   returns:
//     0  — invalid: structurally bad BEEF, txid absent, no matching
//          trusted root, OR an out-of-bounds linear-memory read.
//          Fail-closed; never silently succeeds.
//     1  — valid: BEEF parses, txid present, all BUMP roots match
//          a header in the broker's HeaderStore.
//
// Mirrors the pattern of every other host import in this file: decode
// (ptr, len) from linear memory, forward to the broker, encode the
// boolean result back into the i32 return slot. The broker owns
// policy + audit + composition with `core/cell-engine/src/beef.zig::
// verifyBeefSpv`.
//
// See docs/design/LINEAR-CELL-SPV-STATE.md §3.2 + §7 for the ABI
// context.
fn hostVerifyBeefSpv(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize,
) callconv(.c) ?*c.wasm_trap_t {
    if (nargs != 3 or nresults != 1) return null;
    const e: *CallbackEnv = @ptrCast(@alignCast(env.?));
    const ctx = c.wasmtime_caller_context(caller) orelse {
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const beef_ptr = args[0].of.i32;
    const beef_len = args[1].of.i32;
    const txid_ptr = args[2].of.i32;

    const beef_bytes = readBytes(e, ctx, beef_ptr, beef_len) orelse {
        // OOB read — fail-closed. Audit so a misbehaving module is
        // observable.
        e.broker.auditRecord(e.module_kind, "host_verify_beef_spv", .err, "oob-beef") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    const txid_slice = readBytes(e, ctx, txid_ptr, 32) orelse {
        e.broker.auditRecord(e.module_kind, "host_verify_beef_spv", .err, "oob-txid") catch {};
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    var txid: [32]u8 = undefined;
    @memcpy(&txid, txid_slice[0..32]);

    const ok = e.broker.hostVerifyBeefSpv(e.module_kind, beef_bytes, txid) catch {
        // Broker error (allocator OOM, audit failure). Fail-closed.
        results[0] = .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = 0 } };
        return null;
    };
    results[0] = .{
        .kind = c.WASMTIME_I32,
        .of = .{ .i32 = if (ok) 1 else 0 },
    };
    return null;
}


```
