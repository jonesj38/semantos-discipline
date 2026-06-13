---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/handler_abi_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.182657+00:00
---

# runtime/semantos-brain/tests/handler_abi_conformance.zig

```zig
// Phase WSITE2.5 — handler ABI conformance tests.
//
// Exercises `runner_mod.callHandlerHandle` end-to-end with a hand-rolled
// WAT fixture that implements the handler contract:
//
//   exports:
//     memory                          linear memory
//     handle(method: i32, body_len: i32) -> i64
//
//   wire:
//     - host writes body to memory[0..body_len]
//     - host calls handle(method, body_len)
//     - handler reads body, computes response, overwrites memory[0..]
//     - returns u64 = (status: u16) << 32 | (response_len: u32)
//
// Two-mode coverage:
//   • Stub mode (-Denable-wasmtime=false): asserts callHandlerHandle
//     returns `error.wasmtime_not_enabled` on a stub Instance.
//   • Real mode (-Denable-wasmtime=true): instantiates an "echo" handler
//     that prefixes every body with "echo: " and asserts the response
//     bytes round-trip with status 200.

const std = @import("std");
const build_options = @import("build_options");
const runner_mod = @import("runner");
const broker_mod = @import("broker");
const audit_log_mod = @import("audit_log");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const headers_mod = @import("headers");
const module_loader = @import("module_loader");

const wasmtime_backend = @import("wasmtime_backend");

/// "Echo" handler: prefixes every request body with "echo: " and
/// returns status=200 packed with the new length.
const ECHO_HANDLER_WAT =
    \\(module
    \\  (memory (export "memory") 1)
    \\  (func $handle (export "handle") (param $method i32) (param $body_len i32) (result i64)
    \\    (local $i i32)
    \\    (local.set $i (local.get $body_len))
    \\    (block $done
    \\      (loop $copy
    \\        (br_if $done (i32.eqz (local.get $i)))
    \\        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
    \\        (i32.store8
    \\          (i32.add (local.get $i) (i32.const 6))
    \\          (i32.load8_u (local.get $i)))
    \\        (br $copy)))
    \\    (i32.store8 (i32.const 0) (i32.const 0x65))
    \\    (i32.store8 (i32.const 1) (i32.const 0x63))
    \\    (i32.store8 (i32.const 2) (i32.const 0x68))
    \\    (i32.store8 (i32.const 3) (i32.const 0x6f))
    \\    (i32.store8 (i32.const 4) (i32.const 0x3a))
    \\    (i32.store8 (i32.const 5) (i32.const 0x20))
    \\    (i64.or
    \\      (i64.shl (i64.const 200) (i64.const 32))
    \\      (i64.extend_i32_u (i32.add (local.get $body_len) (i32.const 6))))
    \\  )
    \\)
;

/// Trivial 404 handler: returns status=404 with body "not found\n".
const NOT_FOUND_HANDLER_WAT =
    \\(module
    \\  (memory (export "memory") 1)
    \\  (data (i32.const 0) "not found\n")
    \\  (func $handle (export "handle") (param $method i32) (param $body_len i32) (result i64)
    \\    (i64.or
    \\      (i64.shl (i64.const 404) (i64.const 32))
    \\      (i64.const 10))
    \\  )
    \\)
;

const Fixture = struct {
    slot: slot_store_mod.LocalSlotStore,
    state: derivation_state_mod.LocalStateStore,
    headers: header_store_mod.LocalHeaderStore,
    audit: audit_log_mod.AuditLog,
    broker: broker_mod.Broker,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var f: Fixture = .{
            .slot = slot_store_mod.LocalSlotStore.init(allocator),
            .state = derivation_state_mod.LocalStateStore.init(allocator),
            .headers = header_store_mod.LocalHeaderStore.init(allocator),
            .audit = audit_log_mod.AuditLog.init(),
            .broker = undefined,
        };
        f.broker = broker_mod.Broker.init(
            allocator,
            f.slot.store(),
            f.state.store(),
            f.headers.store(),
            &f.audit,
        );
        return f;
    }

    fn deinit(self: *Fixture) void {
        self.audit.close();
        self.headers.deinit();
        self.state.deinit();
        self.slot.deinit();
    }
};

fn loadFixture(allocator: std.mem.Allocator, c: anytype, wat: []const u8) !module_loader.LoadedModule {
    var wasm_bytes_vec: c.wasm_byte_vec_t = undefined;
    const err = c.wasmtime_wat2wasm(wat.ptr, wat.len, &wasm_bytes_vec);
    if (err != null) {
        c.wasmtime_error_delete(err);
        return error.wat_compile_failed;
    }
    defer c.wasm_byte_vec_delete(&wasm_bytes_vec);

    const dup_bytes = try allocator.dupe(u8, wasm_bytes_vec.data[0..wasm_bytes_vec.size]);
    const sha = module_loader.computeSha256(dup_bytes);
    return .{
        .name = try allocator.dupe(u8, "fixture"),
        .path = try allocator.dupe(u8, "<test-fixture>"),
        .bytes = dup_bytes,
        .sha256 = sha,
        .allocator = allocator,
    };
}

test "WSITE2.5 handler: real path — echo handler round-trips body with status 200" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var lm = try loadFixture(std.testing.allocator, wasmtime_backend.c, ECHO_HANDLER_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    try std.testing.expect(runner.wasmtimeEnabled());

    var instance = try runner.instantiate(&lm, .dynamic_handler);
    defer instance.deinit();

    const body = "ping";
    const resp = try runner_mod.callHandlerHandle(
        &instance,
        std.testing.allocator,
        .post,
        body,
    );
    defer std.testing.allocator.free(resp.body);
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("echo: ping", resp.body);
}

test "WSITE2.5 handler: real path — 404 handler returns the static body" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var lm = try loadFixture(std.testing.allocator, wasmtime_backend.c, NOT_FOUND_HANDLER_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();

    var instance = try runner.instantiate(&lm, .dynamic_handler);
    defer instance.deinit();

    const resp = try runner_mod.callHandlerHandle(
        &instance,
        std.testing.allocator,
        .get,
        "",
    );
    defer std.testing.allocator.free(resp.body);
    try std.testing.expectEqual(@as(u16, 404), resp.status);
    try std.testing.expectEqualStrings("not found\n", resp.body);
}

test "WSITE2.5 handler: real path — empty body produces 6-byte echo prefix" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var lm = try loadFixture(std.testing.allocator, wasmtime_backend.c, ECHO_HANDLER_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();

    var instance = try runner.instantiate(&lm, .dynamic_handler);
    defer instance.deinit();

    const resp = try runner_mod.callHandlerHandle(
        &instance,
        std.testing.allocator,
        .get,
        "",
    );
    defer std.testing.allocator.free(resp.body);
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("echo: ", resp.body);
}

test "WSITE2.5 handler: methodFromHttp covers the common verbs" {
    try std.testing.expectEqual(runner_mod.Method.get, runner_mod.methodFromHttp(.GET));
    try std.testing.expectEqual(runner_mod.Method.post, runner_mod.methodFromHttp(.POST));
    try std.testing.expectEqual(runner_mod.Method.put, runner_mod.methodFromHttp(.PUT));
    try std.testing.expectEqual(runner_mod.Method.delete_, runner_mod.methodFromHttp(.DELETE));
    try std.testing.expectEqual(runner_mod.Method.patch, runner_mod.methodFromHttp(.PATCH));
    try std.testing.expectEqual(runner_mod.Method.options, runner_mod.methodFromHttp(.OPTIONS));
    try std.testing.expectEqual(runner_mod.Method.head, runner_mod.methodFromHttp(.HEAD));
}

```
