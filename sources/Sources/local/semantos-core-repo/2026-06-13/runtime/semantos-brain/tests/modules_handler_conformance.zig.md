---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/modules_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.183666+00:00
---

# runtime/semantos-brain/tests/modules_handler_conformance.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `modules` row), §8 Phase 2.
//
// Conformance suite for `runtime/semantos-brain/src/resources/modules_handler.zig`.
// Same shape as bearer_tokens_handler_conformance.zig: one fixture per
// test, driving the dispatcher → handler → module_loader path.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const module_loader = @import("module_loader");
const instance_manager = @import("instance_manager");
const handler_mod = @import("modules_handler");

const MINIMAL_WASM = module_loader.WASM_MAGIC ++ [_]u8{};

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    manager: instance_manager.InstanceManager,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
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
            .manager = instance_manager.InstanceManager.init(allocator),
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.handler = handler_mod.Handler.init(allocator, &self.manager);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.manager.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    fn writeWasm(self: *Fixture, basename: []const u8, bytes: []const u8) ![]u8 {
        const f = try self.tmp_dir.dir.createFile(basename, .{});
        defer f.close();
        try f.writeAll(bytes);
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp_dir.dir.realpath(basename, &path_buf);
        return self.allocator.dupe(u8, real);
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
// get_hash
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 modules: get_hash returns sha256 + valid_wasm_shape=true" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("ok.wasm", &MINIMAL_WASM);
    defer allocator.free(path);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}"}}
    , .{path});
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "get_hash", args);
    defer r.deinit();

    // 64-char sha256 hex.
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"sha256\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"valid_wasm_shape\":true") != null);
}

test "D-W1 P2 modules: get_hash on non-WASM file flags valid_wasm_shape=false" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("not.wasm", "this is plain text");
    defer allocator.free(path);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}"}}
    , .{path});
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "get_hash", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"valid_wasm_shape\":false") != null);
}

test "D-W1 P2 modules: get_hash on missing file returns not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_found,
        fx.disp.dispatch(&ctx, "modules", "get_hash",
            \\{"path":"/nonexistent/path/to/x.wasm"}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// verify
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 modules: verify with matching hash returns ok:true" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("v.wasm", &MINIMAL_WASM);
    defer allocator.free(path);

    const expected = module_loader.computeSha256(&MINIMAL_WASM);
    const hex = try module_loader.formatHashHex(allocator, &expected);
    defer allocator.free(hex);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}","expected_sha256":"{s}"}}
    , .{ path, hex });
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "verify", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"ok\":true") != null);
}

test "D-W1 P2 modules: verify with mismatched hash returns ok:false kind=hash_mismatch" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("vm.wasm", &MINIMAL_WASM);
    defer allocator.free(path);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}","expected_sha256":"{s}"}}
    , .{ path, "ff" ** 32 });
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "verify", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"kind\":\"hash_mismatch\"") != null);
}

test "D-W1 P2 modules: verify on non-WASM file returns kind=not_wasm" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("nw.bin", "garbage");
    defer allocator.free(path);

    const data = "garbage";
    const expected = module_loader.computeSha256(data);
    const hex = try module_loader.formatHashHex(allocator, &expected);
    defer allocator.free(hex);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}","expected_sha256":"{s}"}}
    , .{ path, hex });
    defer allocator.free(args);

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "verify", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"kind\":\"not_wasm\"") != null);
}

test "D-W1 P2 modules: verify allowed for anonymous (cap = .none)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("a.wasm", &MINIMAL_WASM);
    defer allocator.free(path);

    const expected = module_loader.computeSha256(&MINIMAL_WASM);
    const hex = try module_loader.formatHashHex(allocator, &expected);
    defer allocator.free(hex);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}","expected_sha256":"{s}"}}
    , .{ path, hex });
    defer allocator.free(args);

    var ctx = anonymousCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "verify", args);
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"ok\":true") != null);
}

// ─────────────────────────────────────────────────────────────────────
// list / register / unregister
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 modules: list on empty manager returns empty array" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "modules", "list", "{}");
    defer r.deinit();
    try std.testing.expect(std.mem.indexOf(u8, r.payload, "\"modules\":[]") != null);
}

// Phase 2 MVP — register/unregister are deferred (see module header
// in modules_handler.zig).  Lock the interface in until the wiring
// lands so the surface stays consistent with the §3 row.
test "D-W1 P2 modules: register returns not_yet_implemented (Phase 2 MVP defer)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("reg.wasm", &MINIMAL_WASM);
    defer allocator.free(path);
    const expected = module_loader.computeSha256(&MINIMAL_WASM);
    const hex = try module_loader.formatHashHex(allocator, &expected);
    defer allocator.free(hex);
    const args = try std.fmt.allocPrint(allocator,
        \\{{"name":"x","path":"{s}","expected_sha256":"{s}"}}
    , .{ path, hex });
    defer allocator.free(args);

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_yet_implemented,
        fx.disp.dispatch(&ctx, "modules", "register", args),
    );
}

test "D-W1 P2 modules: unregister returns not_yet_implemented (Phase 2 MVP defer)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_yet_implemented,
        fx.disp.dispatch(&ctx, "modules", "unregister",
            \\{"name":"x"}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Capability gating
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 modules: anonymous caller cannot get_hash" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("anon.wasm", &MINIMAL_WASM);
    defer allocator.free(path);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}"}}
    , .{path});
    defer allocator.free(args);

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "modules", "get_hash", args),
    );
}

test "D-W1 P2 modules: unknown command returns typed unknown_command" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_command,
        fx.disp.dispatch(&ctx, "modules", "no_such", "{}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Audit semantics
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 modules: get_hash + verify + list all skip the audit pair (audit_reads = false)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const path = try fx.writeWasm("aud.wasm", &MINIMAL_WASM);
    defer allocator.free(path);
    const expected = module_loader.computeSha256(&MINIMAL_WASM);
    const hex = try module_loader.formatHashHex(allocator, &expected);
    defer allocator.free(hex);

    const verify_args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}","expected_sha256":"{s}"}}
    , .{ path, hex });
    defer allocator.free(verify_args);
    const get_args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}"}}
    , .{path});
    defer allocator.free(get_args);

    var ctx = rootCtx();
    var r1 = try fx.disp.dispatch(&ctx, "modules", "get_hash", get_args);
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "modules", "verify", verify_args);
    r2.deinit();
    var r3 = try fx.disp.dispatch(&ctx, "modules", "list", "{}");
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
    // 3 reads → 0 start, 0 end, 3 skips.
    try std.testing.expectEqual(@as(usize, 0), start_count);
    try std.testing.expectEqual(@as(usize, 0), end_count);
    try std.testing.expectEqual(@as(usize, 3), skip_count);
}

```
