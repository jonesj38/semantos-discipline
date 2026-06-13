---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/broker_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.180462+00:00
---

# runtime/semantos-brain/tests/broker_conformance.zig

```zig
// Phase Brain 2 — Broker dispatch + module-isolation policy conformance.
//
// Drives the broker directly with synthetic Zig calls (mimicking what
// wasmtime will call once instantiation lands in Brain 2.5). Verifies:
//   1. Storage round-trips for both modules.
//   2. Cross-module routing — wallet asks broker for SPV root.
//   3. Module-isolation policy — wallet engine forbidden from
//      headers-verifier-only ops, and vice versa.
//   4. Audit log accumulates the right entries.

const std = @import("std");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const headers_mod = @import("headers");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

fn readAll(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    const got = try file.readAll(buf);
    if (got != buf.len) return error.ShortRead;
    return buf;
}

fn buildHeader(merkle: [32]u8, ts: u32) headers_mod.Header {
    var h = headers_mod.Header{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = merkle,
        .timestamp = ts,
        .bits = headers_mod.REGTEST_BITS,
        .nonce = 0,
    };
    var n: u32 = 0;
    while (n < 200_000) : (n += 1) {
        h.nonce = n;
        if (h.satisfiesProofOfWork()) return h;
    }
    return h;
}

const Fixture = struct {
    audit_path: []u8,
    audit: audit_log_mod.AuditLog,
    slot_local: slot_store_mod.LocalSlotStore,
    state_local: derivation_state_mod.LocalStateStore,
    header_local: header_store_mod.LocalHeaderStore,
    broker: broker_mod.Broker,

    fn init(allocator: std.mem.Allocator) !Fixture {
        const audit_path = try tempPath("broker-audit.log", allocator);
        var audit = audit_log_mod.AuditLog.init();
        try audit.open(audit_path);
        const slot_local = slot_store_mod.LocalSlotStore.init(allocator);
        const state_local = derivation_state_mod.LocalStateStore.init(allocator);
        const header_local = header_store_mod.LocalHeaderStore.init(allocator);

        return .{
            .audit_path = audit_path,
            .audit = audit,
            .slot_local = slot_local,
            .state_local = state_local,
            .header_local = header_local,
            .broker = undefined, // bound after struct lives at a stable address
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

test "Brain 2 broker: hostPersistCell + hostLoadCell round-trip" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    try fx.broker.hostPersistCell(.wallet_engine, 7, "blob-bytes");
    const got = try fx.broker.hostLoadCell(.wallet_engine, 7);
    try std.testing.expectEqualStrings("blob-bytes", got);
}

test "Brain 2 broker: hostStateNextIndex denied for headers-verifier" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const proto: [16]u8 = .{0xaa} ** 16;
    const cp: [33]u8 = .{0xbb} ** 33;
    try std.testing.expectError(
        error.policy_denied,
        fx.broker.hostStateNextIndex(.headers_verifier, &proto, &cp),
    );
    // Same call from the wallet engine succeeds.
    const idx = try fx.broker.hostStateNextIndex(.wallet_engine, &proto, &cp);
    try std.testing.expectEqual(@as(u64, 0), idx);
}

test "Brain 2 broker: hostAppendValidatedHeader denied for wallet-engine" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const merkle: [32]u8 = .{0xab} ** 32;
    const h = buildHeader(merkle, 1_700_000_000);
    try std.testing.expectError(
        error.policy_denied,
        fx.broker.hostAppendValidatedHeader(.wallet_engine, h, 0),
    );
    try fx.broker.hostAppendValidatedHeader(.headers_verifier, h, 0);
}

test "Brain 2 broker: hostVerifyBeefRoot returns the local merkle root" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const merkle: [32]u8 = .{0xcd} ** 32;
    const h = buildHeader(merkle, 1_700_000_000);
    try fx.broker.hostAppendValidatedHeader(.headers_verifier, h, 0);

    const root = try fx.broker.hostVerifyBeefRoot(.wallet_engine, 0);
    try std.testing.expectEqualSlices(u8, &merkle, &root);
}

test "Brain 2 broker: hostVerifyBeefRoot rejects unknown height" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);
    try std.testing.expectError(
        error.invalid_height,
        fx.broker.hostVerifyBeefRoot(.wallet_engine, 99),
    );
}

test "Brain 2 broker: audit log records every dispatch" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    try fx.broker.hostPersistCell(.wallet_engine, 1, "data");
    _ = try fx.broker.hostLoadCell(.wallet_engine, 1);
    fx.audit.close();

    const contents = try readAll(std.testing.allocator, fx.audit_path);
    defer std.testing.allocator.free(contents);

    // Two ok lines.
    var ok_count: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, contents, idx, "\"result\":\"ok\"")) |pos| {
        ok_count += 1;
        idx = pos + 1;
    }
    try std.testing.expectEqual(@as(usize, 2), ok_count);
    try std.testing.expect(std.mem.indexOf(u8, contents, "host_persist_cell") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "host_load_cell") != null);
}

test "Brain 2 broker: denied dispatch records denied audit entry" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const merkle: [32]u8 = .{0xab} ** 32;
    const h = buildHeader(merkle, 1_700_000_000);
    _ = fx.broker.hostAppendValidatedHeader(.wallet_engine, h, 0) catch {};
    fx.audit.close();

    const contents = try readAll(std.testing.allocator, fx.audit_path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "host_append_validated_header") != null);
}

// ─────────────────────────────────────────────────────────────────────
// C11 PR-C11-7d — hostVerifyBeefSpv conformance.
//
// Coverage:
//   - Malformed BEEF returns false (verification failed; not an error).
//   - Empty BEEF returns false.
//   - Audit log records every dispatch with a result line.
//   - Both wallet_engine and headers_verifier modules are permitted
//     (capability-style gating — read-only verify is open until 7e
//     lands cell-type-manifest capability declarations).
//
// What we do NOT exercise here:
//   - A real-BEEF happy path. That requires a fixture BEEF whose BUMP
//     merkle path resolves to a header we can synthesise into the
//     HeaderStore. The cell-engine `verifyBeefSpv` already has its own
//     fixture-driven conformance tests against BSVZ-emitted BEEFs;
//     pulling those fixtures across into the brain test is a follow-up
//     (likely 7e's surface). Until then we rely on the cell-engine's
//     test suite for the happy-path round-trip and exercise the
//     broker's plumbing (audit + policy + error mapping) here.
// ─────────────────────────────────────────────────────────────────────

test "Brain 2 broker: hostVerifyBeefSpv malformed BEEF returns false" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const garbage = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    const txid: [32]u8 = .{0} ** 32;
    const ok = try fx.broker.hostVerifyBeefSpv(.wallet_engine, &garbage, txid);
    try std.testing.expect(!ok);
}

test "Brain 2 broker: hostVerifyBeefSpv empty BEEF returns false" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const txid: [32]u8 = .{0} ** 32;
    const ok = try fx.broker.hostVerifyBeefSpv(.wallet_engine, "", txid);
    try std.testing.expect(!ok);
}

test "Brain 2 broker: hostVerifyBeefSpv permits both module kinds" {
    // Until 7e lands cell-type-manifest capability declarations, the
    // read-only verifier is open to any module. Both module kinds get
    // a clean (false) result rather than a policy_denied error.
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const garbage = [_]u8{ 0xde, 0xad };
    const txid: [32]u8 = .{0} ** 32;
    const ok_wallet = try fx.broker.hostVerifyBeefSpv(.wallet_engine, &garbage, txid);
    const ok_headers = try fx.broker.hostVerifyBeefSpv(.headers_verifier, &garbage, txid);
    try std.testing.expect(!ok_wallet);
    try std.testing.expect(!ok_headers);
}

test "Brain 2 broker: hostVerifyBeefSpv audits every dispatch" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    // Seed a header so the trusted-roots set is non-empty (covers the
    // `beef_len=... roots_n=N` detail format).
    const merkle: [32]u8 = .{0xef} ** 32;
    const h = buildHeader(merkle, 1_700_000_000);
    try fx.broker.hostAppendValidatedHeader(.headers_verifier, h, 0);

    const garbage = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    const txid: [32]u8 = .{0} ** 32;
    _ = try fx.broker.hostVerifyBeefSpv(.wallet_engine, &garbage, txid);
    fx.audit.close();

    const contents = try readAll(std.testing.allocator, fx.audit_path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "host_verify_beef_spv") != null);
    // The verifier returns false on parse error; broker records that
    // as an `error` audit line (not `denied` — denied is for policy).
    // Result.err serialises as "error" per audit_log.zig's JSON shape.
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"error\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// checkInvocationCapabilities (Layer-2 authz gate)
//
// Structural no-op gate semantics — `granted` only when no real
// verifier is needed, `cert_verifier_pending` otherwise. Phase-1b
// BCA un-park closes the deferral.
//
// Note: callers exercise this gate via `.dynamic_handler` (the
// existing untrusted-module kind); a future script-handler
// dispatcher reuses the same gate.
// ─────────────────────────────────────────────────────────────────────

test "checkInvocationCapabilities: require_cert=false + caps=[] grants" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const handler_id: [32]u8 = .{0xaa} ** 32;
    const result = try fx.broker.checkInvocationCapabilities(
        .dynamic_handler,
        handler_id,
        &.{}, // required_caps empty
        false, // require_cert false
        &.{}, // presented_caps empty
    );
    switch (result) {
        .granted => {},
        else => return error.TestExpectedGranted,
    }
}

test "checkInvocationCapabilities: require_cert=true defers regardless of caps" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const handler_id: [32]u8 = .{0xbb} ** 32;
    const result = try fx.broker.checkInvocationCapabilities(
        .dynamic_handler,
        handler_id,
        &.{}, // no caps required
        true, // BUT require_cert=true → verifier needed
        &.{},
    );
    switch (result) {
        .cert_verifier_pending => |reason| {
            try std.testing.expect(reason.len > 0);
        },
        else => return error.TestExpectedCertPending,
    }
}

test "checkInvocationCapabilities: any required cap defers (verifier needed)" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const handler_id: [32]u8 = .{0xcc} ** 32;
    const required = [_][]const u8{"wallet.sign"};
    const result = try fx.broker.checkInvocationCapabilities(
        .dynamic_handler,
        handler_id,
        &required, // declares a real cap requirement
        false, // even without require_cert, real caps need a verifier
        &.{},
    );
    switch (result) {
        .cert_verifier_pending => {},
        else => return error.TestExpectedCertPending,
    }
}

test "checkInvocationCapabilities: audits every invocation" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit(std.testing.allocator);
    fx.bindBroker(std.testing.allocator);

    const handler_id: [32]u8 = .{0xdd} ** 32;
    _ = try fx.broker.checkInvocationCapabilities(
        .dynamic_handler,
        handler_id,
        &.{},
        false,
        &.{},
    );
    fx.audit.close();

    const contents = try readAll(std.testing.allocator, fx.audit_path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "check_invocation_capabilities") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "dynamic-handler") != null);
}

```
