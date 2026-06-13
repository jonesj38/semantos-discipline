---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/runner.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.243038+00:00
---

# runtime/semantos-brain/src/runner.zig

```zig
// Phase Brain 2.5 — wasmtime instantiation runner.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2.5).
//
// Bridges Brain 1's verified `LoadedModule` bytes to a live wasmtime
// instance, with host imports routed through Brain 2's `Broker`.
//
// The actual wasmtime calls live in `wasmtime_runner_real.zig`
// (built when `-Denable-wasmtime=true`) or `wasmtime_runner_stub.zig`
// (the default — returns `error.wasmtime_not_enabled` for everything).
// build.zig wires the right one under the `wasmtime_backend` import.
//
// This split keeps the wasmtime C-API + libwasmtime link out of the
// build graph entirely when the operator hasn't installed wasmtime.

const std = @import("std");
const build_options = @import("build_options");
const broker_mod = @import("broker");
const module_loader = @import("module_loader");
const backend = @import("wasmtime_backend");

pub const RunnerError = backend.RunnerError;
pub const Instance = backend.Instance;

/// WSITE2.5 — handler ABI re-exports.  See wasmtime_runner_real.zig for
/// the wire-protocol commentary.
pub const HandlerError = backend.HandlerError;
pub const HandlerResponse = backend.HandlerResponse;
pub const Method = backend.Method;
pub const methodFromHttp = backend.methodFromHttp;
pub const callHandlerHandle = backend.callHandlerHandle;
pub const RESPONSE_CAP = backend.RESPONSE_CAP;
pub const REQUEST_CAP = backend.REQUEST_CAP;

pub const Runner = struct {
    allocator: std.mem.Allocator,
    broker: *broker_mod.Broker,
    engine: backend.EngineState,
    initialized: bool,

    pub fn init(allocator: std.mem.Allocator, broker: *broker_mod.Broker) Runner {
        var r: Runner = .{
            .allocator = allocator,
            .broker = broker,
            .engine = undefined,
            .initialized = false,
        };
        if (build_options.enable_wasmtime) {
            r.engine = backend.engineInit() catch return r;
            r.initialized = true;
        }
        return r;
    }

    pub fn deinit(self: *Runner) void {
        if (self.initialized) backend.engineDeinit(&self.engine);
    }

    /// Instantiate a verified module. Returns `error.wasmtime_not_enabled`
    /// when the binary was built without `-Denable-wasmtime=true`.
    pub fn instantiate(
        self: *Runner,
        loaded: *const module_loader.LoadedModule,
        module_kind: broker_mod.Module,
    ) !Instance {
        if (!self.initialized) return error.wasmtime_not_enabled;
        return try backend.instantiate(self.allocator, &self.engine, self.broker, loaded, module_kind);
    }

    pub fn wasmtimeEnabled(self: *const Runner) bool {
        return self.initialized;
    }
};

```
