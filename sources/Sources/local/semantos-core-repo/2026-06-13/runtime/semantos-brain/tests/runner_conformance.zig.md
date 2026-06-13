---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/runner_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.187805+00:00
---

# runtime/semantos-brain/tests/runner_conformance.zig

```zig
// Phase Brain 2.5 — wasmtime runner conformance.
//
// Runs in BOTH build modes:
//   • -Denable-wasmtime=false (default) — asserts the stub returns
//     `error.wasmtime_not_enabled`. Keeps the disabled-build path
//     from bit-rotting.
//   • -Denable-wasmtime=true            — asserts a real WASM module
//     instantiates and that one host-import call (host_persist_cell)
//     round-trips through the broker into the file-backed slot store.
//
// The "real" test path uses a hand-rolled minimal WAT fixture compiled
// in-process via `wasmtime_wat2wasm`. That keeps the test self-contained
// — no .wasm file in the repo, no build-time wat2wasm step.

const std = @import("std");
const build_options = @import("build_options");
const runner_mod = @import("runner");
const broker_mod = @import("broker");
const module_loader = @import("module_loader");
const audit_log_mod = @import("audit_log");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

const Fixture = struct {
    audit_path: []u8,
    audit: audit_log_mod.AuditLog,
    slot_local: slot_store_mod.LocalSlotStore,
    state_local: derivation_state_mod.LocalStateStore,
    header_local: header_store_mod.LocalHeaderStore,
    broker: broker_mod.Broker,

    fn init(allocator: std.mem.Allocator) !Fixture {
        const p = try tempPath("runner-audit.log", allocator);
        var audit = audit_log_mod.AuditLog.init();
        try audit.open(p);
        return .{
            .audit_path = p,
            .audit = audit,
            .slot_local = slot_store_mod.LocalSlotStore.init(allocator),
            .state_local = derivation_state_mod.LocalStateStore.init(allocator),
            .header_local = header_store_mod.LocalHeaderStore.init(allocator),
            .broker = undefined,
        };
    }

    fn bindBroker(self: *Fixture, allocator: std.mem.Allocator) void {
        self.broker = broker_mod.Broker.init(
            allocator,
            self.slot_local.store(),
            self.state_local.store(),
            self.header_local.store(),
            &self.audit,
        );
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.audit.close();
        std.fs.cwd().deleteFile(self.audit_path) catch {};
        allocator.free(self.audit_path);
        self.slot_local.deinit();
        self.state_local.deinit();
        self.header_local.deinit();
    }
};

test "Brain 2.5 runner: wasmtimeEnabled reports the build flag" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    try std.testing.expectEqual(build_options.enable_wasmtime, runner.wasmtimeEnabled());
}

test "Brain 2.5 runner: stub returns wasmtime_not_enabled on instantiate" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    // Build a fake LoadedModule (empty WASM magic).
    const bytes = try std.testing.allocator.dupe(u8, &module_loader.WASM_MAGIC);
    const sha = module_loader.computeSha256(bytes);
    var lm = module_loader.LoadedModule{
        .name = try std.testing.allocator.dupe(u8, "x"),
        .path = try std.testing.allocator.dupe(u8, "/dev/null"),
        .bytes = bytes,
        .sha256 = sha,
        .allocator = std.testing.allocator,
    };
    defer lm.deinit();
    try std.testing.expectError(
        error.wasmtime_not_enabled,
        runner.instantiate(&lm, .wallet_engine),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Real-path tests (only built when -Denable-wasmtime=true).
// ─────────────────────────────────────────────────────────────────────

/// `wasmtime_backend` resolves to either the real or stub backend
/// depending on the build flag. The test only touches its `c` namespace
/// when `enable_wasmtime` is true.
const wasmtime_backend = @import("wasmtime_backend");

/// Minimal WAT fixture: a module that imports `host.host_persist_cell`
/// and exports `memory` + a `run` function that calls the host with a
/// fixed slot id and a 4-byte payload.
const FIXTURE_WAT =
    \\(module
    \\  (import "host" "host_persist_cell" (func $host_persist (param i32 i32 i32) (result i32)))
    \\  (memory (export "memory") 1)
    \\  (data (i32.const 0) "data")
    \\  (func $run (export "run") (result i32)
    \\    (call $host_persist
    \\      (i32.const 7)        ;; slot_id
    \\      (i32.const 0)        ;; ptr (start of "data")
    \\      (i32.const 4))       ;; len
    \\  )
    \\)
;

test "Brain 2.5 runner: real path — instantiate + exercise host_persist_cell" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    // Compile the WAT fixture to WASM bytes via the wasmtime C API.
    const c = wasmtime_backend.c;
    var wasm_bytes_vec: c.wasm_byte_vec_t = undefined;
    {
        const err = c.wasmtime_wat2wasm(FIXTURE_WAT.ptr, FIXTURE_WAT.len, &wasm_bytes_vec);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return error.TestFailed;
        }
    }
    defer c.wasm_byte_vec_delete(&wasm_bytes_vec);

    // Wrap into a LoadedModule (the runner takes a borrowed reference).
    const dup_bytes = try std.testing.allocator.dupe(u8, wasm_bytes_vec.data[0..wasm_bytes_vec.size]);
    const sha = module_loader.computeSha256(dup_bytes);
    var lm = module_loader.LoadedModule{
        .name = try std.testing.allocator.dupe(u8, "fixture"),
        .path = try std.testing.allocator.dupe(u8, "<test-fixture>"),
        .bytes = dup_bytes,
        .sha256 = sha,
        .allocator = std.testing.allocator,
    };
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    try std.testing.expect(runner.wasmtimeEnabled());

    var instance = try runner.instantiate(&lm, .wallet_engine);
    defer instance.deinit();

    // Look up the exported `run` function and call it; expect rc=1 (the
    // host's success code, propagated from broker.hostPersistCell).
    const ctx = c.wasmtime_store_context(instance.store);
    var run_export: c.wasmtime_extern_t = undefined;
    try std.testing.expect(c.wasmtime_instance_export_get(ctx, &instance.instance, "run", "run".len, &run_export));
    try std.testing.expectEqual(@as(c_int, c.WASMTIME_EXTERN_FUNC), run_export.kind);

    var results: [1]c.wasmtime_val_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    {
        const err = c.wasmtime_func_call(ctx, &run_export.of.func, null, 0, &results, 1, &trap);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return error.TestFailed;
        }
        if (trap != null) {
            c.wasm_trap_delete(trap);
            return error.TestFailed;
        }
    }
    try std.testing.expectEqual(@as(i32, 1), results[0].of.i32);

    // The slot store should now hold "data" at slot 7.
    const stored = try fx.slot_local.store().get(7);
    try std.testing.expectEqualStrings("data", stored);
}

// ─────────────────────────────────────────────────────────────────────
// Brain 2.6 — additional callbacks
// ─────────────────────────────────────────────────────────────────────

/// Fixture exercising every Brain 2.6 hash callback. The module exports a
/// function per algorithm that hashes a fixed 4-byte input and returns
/// a single byte from the output for assertion. This way a single
/// `(memory)` segment carries both the input and the output buffers.
const HASH_FIXTURE_WAT =
    \\(module
    \\  (import "host" "host_sha256"    (func $h_sha256    (param i32 i32 i32)))
    \\  (import "host" "host_sha1"      (func $h_sha1      (param i32 i32 i32)))
    \\  (import "host" "host_ripemd160" (func $h_ripemd160 (param i32 i32 i32)))
    \\  (import "host" "host_hash160"   (func $h_hash160   (param i32 i32 i32)))
    \\  (import "host" "host_hash256"   (func $h_hash256   (param i32 i32 i32)))
    \\  (memory (export "memory") 1)
    \\  ;; Input lives at offset 0; outputs scattered at offsets 16, 64, 96, 128, 160.
    \\  (data (i32.const 0) "abcd")
    \\  (func (export "do_sha256") (result i32)
    \\    (call $h_sha256 (i32.const 0) (i32.const 4) (i32.const 16))
    \\    (i32.load8_u (i32.const 16)))
    \\  (func (export "do_sha1") (result i32)
    \\    (call $h_sha1 (i32.const 0) (i32.const 4) (i32.const 64))
    \\    (i32.load8_u (i32.const 64)))
    \\  (func (export "do_ripemd160") (result i32)
    \\    (call $h_ripemd160 (i32.const 0) (i32.const 4) (i32.const 96))
    \\    (i32.load8_u (i32.const 96)))
    \\  (func (export "do_hash160") (result i32)
    \\    (call $h_hash160 (i32.const 0) (i32.const 4) (i32.const 128))
    \\    (i32.load8_u (i32.const 128)))
    \\  (func (export "do_hash256") (result i32)
    \\    (call $h_hash256 (i32.const 0) (i32.const 4) (i32.const 160))
    \\    (i32.load8_u (i32.const 160)))
    \\)
;

fn callExport(c: anytype, instance: anytype, name: []const u8) !i32 {
    const ctx = c.wasmtime_store_context(instance.store);
    var exp: c.wasmtime_extern_t = undefined;
    if (!c.wasmtime_instance_export_get(ctx, &instance.instance, name.ptr, name.len, &exp)) {
        return error.ExportMissing;
    }
    var res: [1]c.wasmtime_val_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    const err = c.wasmtime_func_call(ctx, &exp.of.func, null, 0, &res, 1, &trap);
    if (err != null) {
        c.wasmtime_error_delete(err);
        return error.CallFailed;
    }
    if (trap != null) {
        c.wasm_trap_delete(trap);
        return error.Trap;
    }
    return res[0].of.i32;
}

fn loadFixture(allocator: std.mem.Allocator, c: anytype, wat: []const u8) !module_loader.LoadedModule {
    var wasm_bytes_vec: c.wasm_byte_vec_t = undefined;
    const err = c.wasmtime_wat2wasm(wat.ptr, wat.len, &wasm_bytes_vec);
    if (err != null) {
        c.wasmtime_error_delete(err);
        return error.Wat2WasmFailed;
    }
    defer c.wasm_byte_vec_delete(&wasm_bytes_vec);
    const dup = try allocator.dupe(u8, wasm_bytes_vec.data[0..wasm_bytes_vec.size]);
    const sha = module_loader.computeSha256(dup);
    return .{
        .name = try allocator.dupe(u8, "fixture"),
        .path = try allocator.dupe(u8, "<test-fixture>"),
        .bytes = dup,
        .sha256 = sha,
        .allocator = allocator,
    };
}

test "Brain 2.6 runner: hash callbacks produce correct digests" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const c = wasmtime_backend.c;
    var lm = try loadFixture(std.testing.allocator, c, HASH_FIXTURE_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    var instance = try runner.instantiate(&lm, .wallet_engine);
    defer instance.deinit();

    // sha256("abcd")     = 88d4266f… → 0x88
    try std.testing.expectEqual(@as(i32, 0x88), try callExport(c, instance, "do_sha256"));
    // sha1("abcd")       = 81fe8bfe… → 0x81
    try std.testing.expectEqual(@as(i32, 0x81), try callExport(c, instance, "do_sha1"));
    // ripemd160("abcd")  = 2e7e536f… → 0x2e
    try std.testing.expectEqual(@as(i32, 0x2e), try callExport(c, instance, "do_ripemd160"));
    // hash160 = ripemd160(sha256("abcd")) = 66d82f8f… → 0x66
    try std.testing.expectEqual(@as(i32, 0x66), try callExport(c, instance, "do_hash160"));
    // hash256 = sha256(sha256("abcd"))   = 7e9c158e… → 0x7e
    try std.testing.expectEqual(@as(i32, 0x7e), try callExport(c, instance, "do_hash256"));
}

const STUB_FIXTURE_WAT =
    \\(module
    \\  (import "host" "host_call_by_name" (func $h_call (param i32 i32) (result i32)))
    \\  (import "host" "host_fetch_cell"   (func $h_fetch (param i32 i32 i32 i32) (result i32)))
    \\  (import "host" "host_get_blocktime" (func $h_bt (result i32)))
    \\  (import "host" "host_get_sequence"  (func $h_seq (result i32)))
    \\  (memory (export "memory") 1)
    \\  (func (export "test_call") (result i32)
    \\    (call $h_call (i32.const 0) (i32.const 0)))
    \\  (func (export "test_fetch") (result i32)
    \\    (call $h_fetch (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0)))
    \\  (func (export "test_blocktime") (result i32) (call $h_bt))
    \\  (func (export "test_sequence")  (result i32) (call $h_seq))
    \\)
;

// ─────────────────────────────────────────────────────────────────────
// Brain 2.7 — real secp256k1 signing + verification round-trip
// ─────────────────────────────────────────────────────────────────────

const SIGN_FIXTURE_WAT =
    \\(module
    \\  (import "host" "host_sign"     (func $h_sign (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    \\  (import "host" "host_checksig" (func $h_check (param i32 i32 i32 i32 i32 i32) (result i32)))
    \\  (memory (export "memory") 1)
    \\  ;; Layout in linear memory:
    \\  ;;   0..32   private key (32 bytes)
    \\  ;;   32..64  public key compressed SEC1 (33 bytes — only first 33 used)
    \\  ;;   65..97  digest (32 bytes)
    \\  ;;   97..101 sig length (u32 LE — host writes here)
    \\  ;;   101..173 DER signature (host writes here, max 72 bytes)
    \\  (func (export "do_sign") (result i32)
    \\    (call $h_sign
    \\      (i32.const 0)   (i32.const 32)    ;; sk
    \\      (i32.const 65)  (i32.const 32)    ;; digest
    \\      (i32.const 101) (i32.const 72)    ;; out_buf, out_buf_len
    \\      (i32.const 97)))                  ;; out_len_ptr
    \\  (func (export "get_sig_len") (result i32) (i32.load (i32.const 97)))
    \\  (func (export "do_verify") (result i32)
    \\    (call $h_check
    \\      (i32.const 32)  (i32.const 33)    ;; pk (compressed SEC1)
    \\      (i32.const 65)  (i32.const 32)    ;; digest
    \\      (i32.const 101) (i32.load (i32.const 97))))   ;; sig + len
    \\)
;

test "Brain 2.7 runner: sign + checksig round-trip via real bsvz secp256k1" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const c = wasmtime_backend.c;
    var lm = try loadFixture(std.testing.allocator, c, SIGN_FIXTURE_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    var instance = try runner.instantiate(&lm, .wallet_engine);
    defer instance.deinit();

    // Seed the linear memory: a deterministic 32-byte private key (the
    // Zig std lib's "test key #1" pattern), its derived compressed
    // pubkey, and a 32-byte digest.
    const ctx = c.wasmtime_store_context(instance.store);
    var mem_export: c.wasmtime_extern_t = undefined;
    try std.testing.expect(c.wasmtime_instance_export_get(ctx, &instance.instance, "memory", "memory".len, &mem_export));
    const mem = mem_export.of.memory;
    const data = c.wasmtime_memory_data(ctx, &mem);

    // sk = 32-byte 0x01 ones (a valid secp256k1 scalar — far below curve order)
    const sk: [32]u8 = .{0x01} ** 32;
    @memcpy(data[0..32], &sk);

    // Derive the matching public key via bsvz so we know what to verify against.
    const bsvz_dep = @import("bsvz");
    const priv = try bsvz_dep.primitives.ec.PrivateKey.fromBytes(sk);
    const pub_key = try priv.publicKey();
    const pk_compressed = pub_key.inner.toCompressedSec1();
    @memcpy(data[32..65], &pk_compressed);

    // digest = SHA256("Brain 2.7-test")
    const digest = blk: {
        var d: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash("Brain 2.7-test", &d, .{});
        break :blk d;
    };
    @memcpy(data[65..97], &digest);

    // Call do_sign — should return 1 (success).
    try std.testing.expectEqual(@as(i32, 1), try callExport(c, instance, "do_sign"));

    // Sig length should be in DER range (typically 70-72 bytes).
    const sig_len = try callExport(c, instance, "get_sig_len");
    try std.testing.expect(sig_len >= 64 and sig_len <= 72);

    // do_verify should return 1 (signature valid).
    try std.testing.expectEqual(@as(i32, 1), try callExport(c, instance, "do_verify"));

    // Tamper with the digest and verify it fails.
    data[65] ^= 0xff;
    try std.testing.expectEqual(@as(i32, 0), try callExport(c, instance, "do_verify"));
}

const DENY_SIGN_FIXTURE_WAT =
    \\(module
    \\  (import "host" "host_sign" (func $h_sign (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    \\  (memory (export "memory") 1)
    \\  (func (export "try_sign") (result i32)
    \\    (call $h_sign
    \\      (i32.const 0) (i32.const 32)
    \\      (i32.const 32) (i32.const 32)
    \\      (i32.const 64) (i32.const 72)
    \\      (i32.const 200)))
    \\)
;

test "Brain 2.7 runner: host_sign denied for headers-verifier module" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const c = wasmtime_backend.c;
    var lm = try loadFixture(std.testing.allocator, c, DENY_SIGN_FIXTURE_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    // Instantiate as headers_verifier — host_sign should be policy-denied.
    var instance = try runner.instantiate(&lm, .headers_verifier);
    defer instance.deinit();

    const ctx = c.wasmtime_store_context(instance.store);
    var mem_export: c.wasmtime_extern_t = undefined;
    try std.testing.expect(c.wasmtime_instance_export_get(ctx, &instance.instance, "memory", "memory".len, &mem_export));
    const mem = mem_export.of.memory;
    const data = c.wasmtime_memory_data(ctx, &mem);
    const sk: [32]u8 = .{0x01} ** 32;
    @memcpy(data[0..32], &sk);
    @memset(data[32..64], 0x42);

    // Returns 0 — policy denied. Audit log should record `denied`.
    try std.testing.expectEqual(@as(i32, 0), try callExport(c, instance, "try_sign"));

    fx.audit.close();
    const file = try std.fs.cwd().openFile(fx.audit_path, .{});
    defer file.close();
    const stat = try file.stat();
    const buf = try std.testing.allocator.alloc(u8, stat.size);
    defer std.testing.allocator.free(buf);
    _ = try file.readAll(buf);
    try std.testing.expect(std.mem.indexOf(u8, buf, "\"result\":\"denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf, "host_sign") != null);
}

test "Brain 2.6 runner: stubs return their documented sentinels" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const c = wasmtime_backend.c;
    var lm = try loadFixture(std.testing.allocator, c, STUB_FIXTURE_WAT);
    defer lm.deinit();

    var runner = runner_mod.Runner.init(std.testing.allocator, &fx.broker);
    defer runner.deinit();
    var instance = try runner.instantiate(&lm, .wallet_engine);
    defer instance.deinit();

    // host_call_by_name → 0xFFFFFFFF (i32 -1).
    try std.testing.expectEqual(@as(i32, -1), try callExport(c, instance, "test_call"));
    // host_fetch_cell → 0.
    try std.testing.expectEqual(@as(i32, 0), try callExport(c, instance, "test_fetch"));
    // host_get_blocktime → wall-clock unix-seconds (positive).
    const bt = try callExport(c, instance, "test_blocktime");
    try std.testing.expect(bt > 0);
    // host_get_sequence → 0 (no tx context bound).
    try std.testing.expectEqual(@as(i32, 0), try callExport(c, instance, "test_sequence"));
}

```
