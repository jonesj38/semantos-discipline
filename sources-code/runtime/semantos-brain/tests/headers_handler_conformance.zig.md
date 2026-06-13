---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/headers_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.202217+00:00
---

# runtime/semantos-brain/tests/headers_handler_conformance.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `headers` row), §8 Phase 2, §10.
//
// Conformance suite for `runtime/semantos-brain/src/resources/headers_handler.zig`.
// Builds a `LocalHeaderStore` (the in-memory backing — same vtable
// shape `FsHeaderStore` exposes) seeded with a small synthetic
// chain and exercises every read command.  Also asserts the
// `audit_reads = false` opt-out wires through the dispatcher (reads
// emit `phase=skip`, not the begin/complete pair).

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");
const handler_mod = @import("headers_handler");

// ─────────────────────────────────────────────────────────────────────
// Fixture
// ─────────────────────────────────────────────────────────────────────

/// Build a chain of N synthetic headers anchored at height 0.  We
/// don't satisfy proof-of-work — `LocalHeaderStore.appendValidated`
/// trusts the caller has already validated.  The chain is just
/// enough for the read commands to have something to fetch.
fn synthChain(n: usize) []headers_mod.Header {
    const allocator = std.testing.allocator;
    const out = allocator.alloc(headers_mod.Header, n) catch unreachable;
    var prev_hash: [32]u8 = [_]u8{0} ** 32;
    for (0..n) |i| {
        out[i] = .{
            .version = 1,
            .prev_hash = prev_hash,
            .merkle_root = [_]u8{@intCast(i & 0xff)} ** 32,
            .timestamp = @intCast(1_700_000_000 + i),
            .bits = headers_mod.REGTEST_BITS,
            .nonce = 0,
        };
        prev_hash = out[i].computeHash();
    }
    return out;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    local: header_store_mod.LocalHeaderStore,
    store_handle: header_store_mod.HeaderStore,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    chain: []headers_mod.Header,

    fn init(allocator: std.mem.Allocator, chain_len: usize) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .local = header_store_mod.LocalHeaderStore.init(allocator),
            .store_handle = undefined,
            .handler = undefined,
            .disp = undefined,
            .chain = &.{},
        };
        try self.audit.open(audit_path);
        self.store_handle = self.local.store();
        // Seed the store.
        const chain = synthChain(chain_len);
        for (chain, 0..) |h, i| {
            try self.store_handle.appendValidated(h, @intCast(i));
        }
        self.chain = chain;
        self.handler = handler_mod.Handler.init(allocator, &self.store_handle);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.local.deinit();
        if (self.chain.len > 0) self.allocator.free(self.chain);
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    fn dumpAudit(self: *Fixture) ![]u8 {
        const f = try std.fs.cwd().openFile(self.audit_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn anonymousCtx() dispatcher.DispatchContext {
    return .{
        .auth = .{ .anonymous = .{ .site_origin = "https://example" } },
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test-anon", .transport_label = "test" },
    };
}

// ─────────────────────────────────────────────────────────────────────
// tip
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: tip on empty store reports present:false" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 0);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "tip", "{}");
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"present\":false") != null);
}

test "D-W1 P2 headers: tip on populated store reports height + hash" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 5);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "tip", "{}");
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"present\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"height\":4") != null);
}

// ─────────────────────────────────────────────────────────────────────
// byHeight
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: byHeight returns 80-byte raw header in hex" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 3);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "byHeight",
        \\{"height":2}
    );
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"height\":2") != null);
    // header_hex is 160 chars (80 bytes).
    var idx: usize = std.mem.indexOf(u8, r.payload, "\"header_hex\":\"") orelse unreachable;
    idx += "\"header_hex\":\"".len;
    const end = std.mem.indexOfScalarPos(u8, r.payload, idx, '"') orelse unreachable;
    try std.testing.expectEqual(@as(usize, 160), end - idx);
}

test "D-W1 P2 headers: byHeight beyond tip returns present:false" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 3);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "byHeight",
        \\{"height":99}
    );
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"present\":false") != null);
}

test "D-W1 P2 headers: byHeight rejects negative height" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "headers", "byHeight",
            \\{"height":-1}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// byHash
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: byHash round-trips against tip's hash" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 4);
    defer fx.deinit();

    const tip = fx.chain[fx.chain.len - 1].computeHash();
    var hex: [64]u8 = undefined;
    const charset = "0123456789abcdef";
    for (tip, 0..) |b, i| {
        hex[i * 2] = charset[(b >> 4) & 0xf];
        hex[i * 2 + 1] = charset[b & 0xf];
    }

    const args = try std.fmt.allocPrint(allocator,
        \\{{"hash":"{s}"}}
    , .{hex});
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "byHash", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"present\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"height\":3") != null);
}

test "D-W1 P2 headers: byHash with malformed hex returns invalid_args" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "headers", "byHash",
            \\{"hash":"not-hex"}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// range
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: range returns N consecutive headers" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 5);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "range",
        \\{"from":1,"to":3}
    );
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"count\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"height\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"height\":3") != null);
}

test "D-W1 P2 headers: range bigger than MAX returns range_too_large" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.range_too_large,
        fx.disp.dispatch(&ctx, "headers", "range",
            \\{"from":0,"to":5000}
        ),
    );
}

test "D-W1 P2 headers: range with from>to returns invalid_args" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 5);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "headers", "range",
            \\{"from":3,"to":1}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// sync_state
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: sync_state on populated store reports tip_height" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 7);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "sync_state", "{}");
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"tip_height\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"tip_present\":true") != null);
}

// ─────────────────────────────────────────────────────────────────────
// append_validated deferred
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: append_validated returns not_yet_implemented (Phase 2 MVP defer)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_yet_implemented,
        fx.disp.dispatch(&ctx, "headers", "append_validated", "{}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Capability gating + audit_reads opt-out
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 headers: anonymous caller can read tip (cap = .none)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 2);
    defer fx.deinit();

    var ctx = anonymousCtx();
    var r = try fx.disp.dispatch(&ctx, "headers", "tip", "{}");
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"present\":true") != null);
}

test "D-W1 P2 headers: read commands skip the audit pair (audit_reads = false)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 3);
    defer fx.deinit();

    var ctx = rootCtx();
    var r1 = try fx.disp.dispatch(&ctx, "headers", "tip", "{}");
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "headers", "byHeight",
        \\{"height":1}
    );
    r2.deinit();
    var r3 = try fx.disp.dispatch(&ctx, "headers", "sync_state", "{}");
    r3.deinit();

    const text = try fx.dumpAudit();
    defer allocator.free(text);

    var start_count: usize = 0;
    var end_count: usize = 0;
    var skip_count: usize = 0;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "phase=start")) |idx| {
        start_count += 1;
        rest = rest[idx + "phase=start".len ..];
    }
    rest = text;
    while (std.mem.indexOf(u8, rest, "phase=end")) |idx| {
        end_count += 1;
        rest = rest[idx + "phase=end".len ..];
    }
    rest = text;
    while (std.mem.indexOf(u8, rest, "phase=skip")) |idx| {
        skip_count += 1;
        rest = rest[idx + "phase=skip".len ..];
    }
    try std.testing.expectEqual(@as(usize, 0), start_count);
    try std.testing.expectEqual(@as(usize, 0), end_count);
    try std.testing.expectEqual(@as(usize, 3), skip_count);
}

test "D-W1 P2 headers: handler errors still audit (failures don't opt out)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    _ = fx.disp.dispatch(&ctx, "headers", "byHeight",
        \\{"height":-1}
    ) catch {};

    const text = try fx.dumpAudit();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "phase=start") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "kind=handler_err") != null);
}

test "D-W1 P2 headers: unknown command returns typed unknown_command + audit pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, 1);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_command,
        fx.disp.dispatch(&ctx, "headers", "no_such", "{}"),
    );

    const text = try fx.dumpAudit();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "kind=unknown_command") != null);
}

```
