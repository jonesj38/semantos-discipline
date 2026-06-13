---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wasmtime_runner_stub.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.212515+00:00
---

# runtime/semantos-brain/src/wasmtime_runner_stub.zig

```zig
// Phase Brain 2.5 — wasmtime backend stub.
//
// Built when `-Denable-wasmtime=false` (the default). Mirrors the public
// surface of `wasmtime_runner_real.zig` so `runner.zig` can call into
// either without branching, but every entry point returns
// `error.wasmtime_not_enabled`.
//
// The stub is *not* dead code: tests run against it (asserting the
// error path) so the wasmtime-disabled build path doesn't bit-rot.

const std = @import("std");
const broker_mod = @import("broker");
const module_loader = @import("module_loader");

/// Empty `c` namespace so that test files can name `wasmtime_backend.c`
/// in both modes. The real namespace has the full wasmtime C-API surface;
/// the stub only declares the symbols our tests reference, and only as
/// types — never values — so dead code in disabled-mode tests still
/// type-checks. Tests are expected to early-return `SkipZigTest` before
/// touching anything in `c` when the flag is off.
pub const c = struct {
    pub const wasm_byte_vec_t = struct { data: [*]const u8 = undefined, size: usize = 0 };
    pub const wasm_trap_t = opaque {};
    pub const wasmtime_val_t = struct {
        kind: u8 = 0,
        of: extern union { i32: i32 } = .{ .i32 = 0 },
    };
    pub const wasmtime_extern_t = struct {
        kind: c_int = 0,
        of: extern union { func: u32 } = .{ .func = 0 },
    };
    pub const WASMTIME_EXTERN_FUNC: c_int = 0;

    pub fn wasmtime_wat2wasm(_: [*]const u8, _: usize, _: *wasm_byte_vec_t) ?*anyopaque {
        return null;
    }
    pub fn wasmtime_error_delete(_: ?*anyopaque) void {}
    pub fn wasm_byte_vec_delete(_: *wasm_byte_vec_t) void {}
    pub fn wasmtime_store_context(_: anytype) ?*anyopaque {
        return null;
    }
    pub fn wasmtime_instance_export_get(_: ?*anyopaque, _: anytype, _: [*]const u8, _: usize, _: *wasmtime_extern_t) bool {
        return false;
    }
    pub fn wasmtime_func_call(_: ?*anyopaque, _: anytype, _: ?[*]const wasmtime_val_t, _: usize, _: [*]wasmtime_val_t, _: usize, _: *?*wasm_trap_t) ?*anyopaque {
        return null;
    }
    pub fn wasm_trap_delete(_: ?*wasm_trap_t) void {}
};

pub const RunnerError = error{
    wasmtime_not_enabled,
    engine_init_failed,
    module_compile_failed,
    instance_link_failed,
    instance_init_failed,
    wasm_trap,
    out_of_memory,
};

pub const EngineState = struct {
    /// Non-zero-sized so std.ArrayList(EngineState) instantiates cleanly
    /// in the stub build. Stub never reads it.
    _stub: u8 = 0,
};

pub const Instance = struct {
    /// Non-zero-sized for the same reason as `EngineState`.
    _stub: u8 = 0,
    pub fn deinit(self: *Instance) void {
        _ = self;
    }
};

pub fn engineInit() !EngineState {
    return error.wasmtime_not_enabled;
}

pub fn engineDeinit(self: *EngineState) void {
    _ = self;
}

pub fn instantiate(
    allocator: std.mem.Allocator,
    eng: *EngineState,
    broker: *broker_mod.Broker,
    loaded: *const module_loader.LoadedModule,
    module_kind: broker_mod.Module,
) !Instance {
    _ = allocator;
    _ = eng;
    _ = broker;
    _ = loaded;
    _ = module_kind;
    return error.wasmtime_not_enabled;
}

// ─────────────────────────────────────────────────────────────────────
// WSITE2.5 — handler ABI (stub)
// ─────────────────────────────────────────────────────────────────────

pub const HandlerError = error{
    handler_export_missing,
    handler_trap,
    handler_oob,
    response_too_large,
    out_of_memory,
    /// Stub-only — the real backend never returns this.
    wasmtime_not_enabled,
};

pub const HandlerResponse = struct {
    status: u16 = 0,
    body: []u8 = &.{},
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

pub const RESPONSE_CAP: usize = 4 * 1024 * 1024;
pub const REQUEST_CAP: usize = 4 * 1024 * 1024;

pub fn callHandlerHandle(
    self: *Instance,
    allocator: std.mem.Allocator,
    method: Method,
    body: []const u8,
) HandlerError!HandlerResponse {
    _ = self;
    _ = allocator;
    _ = method;
    _ = body;
    return error.wasmtime_not_enabled;
}

```
