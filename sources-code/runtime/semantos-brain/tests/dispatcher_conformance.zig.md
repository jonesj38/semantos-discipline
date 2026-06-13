---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/dispatcher_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.176192+00:00
---

# runtime/semantos-brain/tests/dispatcher_conformance.zig

```zig
// Phase D-W1 / Phase 0 — dispatcher conformance tests.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §4, §7, §12.
//
// Coverage:
//   • Deny-by-default — undeclared cap on a known cmd → typed error.
//   • Unknown resource / unknown command → typed errors + audit pair.
//   • Capability check — root scopes always pass; bearer with the
//     declared cap passes; bearer without it is denied.
//   • Wildcard + hierarchy in CapabilitySet (also covered inline in
//     src/dispatcher.zig — re-tested here through the public API).
//   • Audit-pair invariant — every dispatch produces exactly one
//     `phase=start` entry and exactly one `phase=end` entry, regardless
//     of outcome.  Property-style sweep over a randomised command
//     sequence.
//
// The fixture uses an in-tree `echo` resource handler defined at the
// bottom of the file.  It deliberately exercises every cap_for_cmd
// outcome (none, require, capability_not_declared, unknown_command).

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");

// ─────────────────────────────────────────────────────────────────────
// Echo resource handler — test-only fixture.
//
// Commands:
//   say     → cap = "cap.echo.say"
//   delete  → cap = "cap.echo.delete"
//   ping    → cap = .none (no auth needed)
//   stowaway → declared in handle_fn but cap-table forgets it
//             → returns error.capability_not_declared
//   anything else → error.unknown_command
//
// The handler ignores `args_json`; it returns a JSON-shaped payload
// `{"echoed":"<cmd>"}` for `say` and `ping`, an empty result for
// `delete`, and never reaches `handle_fn` for the cap_not_declared /
// unknown_command paths because the dispatcher rejects first.
// ─────────────────────────────────────────────────────────────────────

fn echoCapForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "say")) return .{ .require = "cap.echo.say" };
    if (std.mem.eql(u8, cmd, "delete")) return .{ .require = "cap.echo.delete" };
    if (std.mem.eql(u8, cmd, "ping")) return .none;
    if (std.mem.eql(u8, cmd, "stowaway")) return error.capability_not_declared;
    return error.unknown_command;
}

fn echoHandle(
    _: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    _: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    if (std.mem.eql(u8, cmd, "say") or std.mem.eql(u8, cmd, "ping")) {
        const payload = try std.fmt.allocPrint(allocator, "{{\"echoed\":\"{s}\"}}", .{cmd});
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    if (std.mem.eql(u8, cmd, "delete")) {
        return dispatcher.Result.empty();
    }
    // The dispatcher rejects unknown_command and capability_not_declared
    // before reaching here; if execution lands here for those cmds, that
    // itself is a test failure.
    return error.test_failed_handler_reached;
}

fn echoHandler() dispatcher.ResourceHandler {
    return .{
        .name = "echo",
        .state = null,
        .cap_for_cmd_fn = echoCapForCmd,
        .handle_fn = echoHandle,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Per-test fixture: opens a unique audit log on disk, builds a
// dispatcher around it, registers the echo handler.  Caller deinits.
// ─────────────────────────────────────────────────────────────────────

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

/// Heap-allocated so `disp.audit` (a `*AuditLog`) can safely point at
/// the fixture's `audit` field — addresses must be stable.  Stack-local
/// fields would dangle once `init()` returned.
const Fixture = struct {
    allocator: std.mem.Allocator,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator, log_basename: []const u8) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        const path = try tempPath(log_basename, allocator);
        errdefer allocator.free(path);
        self.* = .{
            .allocator = allocator,
            .audit_path = path,
            .audit = audit_log.AuditLog.init(),
            .disp = undefined,
        };
        try self.audit.open(path);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(echoHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.audit.close();
        std.fs.cwd().deleteFile(self.audit_path) catch {};
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    /// The audit log file for inspection.  Caller frees the returned slice.
    fn dumpAudit(self: *Fixture) ![]u8 {
        // Audit_log holds an open handle; flushing across the boundary
        // is OS write-through (unbuffered fs.File). Re-read directly.
        return try readAll(self.allocator, self.audit_path);
    }

    /// Count the number of dispatch audit entries with `phase=<phase>`
    /// (e.g. "start" or "end") in the current log file.
    fn countPhase(self: *Fixture, phase: []const u8) !usize {
        const contents = try self.dumpAudit();
        defer self.allocator.free(contents);
        var count: usize = 0;
        var rest = contents;
        var needle_buf: [32]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buf, "phase={s}", .{phase});
        while (std.mem.indexOf(u8, rest, needle)) |idx| {
            count += 1;
            rest = rest[idx + needle.len ..];
        }
        return count;
    }
};

// ─────────────────────────────────────────────────────────────────────
// AuthContext / DispatchContext helpers.
// ─────────────────────────────────────────────────────────────────────

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test-root", .transport_label = "test" },
    };
}

fn bearerCtx(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .bearer = .{ .fingerprint_hex = [_]u8{'0'} ** 64, .label = "test" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-bearer", .transport_label = "test" },
    };
}

fn anonymousCtx(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .anonymous = .{ .site_origin = "https://example" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-anon", .transport_label = "test" },
    };
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "D-W1 dispatch: in_process_root can dispatch any declared command" {
    var fx = try Fixture.init(std.testing.allocator, "disp-root.log");
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "echo", "say", "{}");
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"echoed\":\"say\"") != null);
}

test "D-W1 dispatch: unknown_resource → typed error + audit pair" {
    var fx = try Fixture.init(std.testing.allocator, "disp-unknown-res.log");
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_resource,
        fx.disp.dispatch(&ctx, "nope", "say", "{}"),
    );

    const contents = try fx.dumpAudit();
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"op\":\"nope.say\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "kind=unknown_resource") != null);
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
}

test "D-W1 dispatch: unknown_command on known resource → typed error + audit pair" {
    var fx = try Fixture.init(std.testing.allocator, "disp-unknown-cmd.log");
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_command,
        fx.disp.dispatch(&ctx, "echo", "scream", "{}"),
    );

    const contents = try fx.dumpAudit();
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "kind=unknown_command") != null);
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
}

test "D-W1 dispatch: capability_not_declared (deny-by-default) → typed error + audit pair" {
    var fx = try Fixture.init(std.testing.allocator, "disp-cap-not-declared.log");
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_not_declared,
        fx.disp.dispatch(&ctx, "echo", "stowaway", "{}"),
    );

    const contents = try fx.dumpAudit();
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "kind=capability_not_declared") != null);
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
}

test "D-W1 dispatch: bearer with declared cap can dispatch echo.say" {
    var fx = try Fixture.init(std.testing.allocator, "disp-bearer-ok.log");
    defer fx.deinit();

    const caps = [_][]const u8{"cap.echo.say"};
    var ctx = bearerCtx(&caps);
    var result = try fx.disp.dispatch(&ctx, "echo", "say", "{}");
    defer result.deinit();
    try std.testing.expect(result.payload.len > 0);
}

test "D-W1 dispatch: bearer without delete cap is denied on echo.delete" {
    var fx = try Fixture.init(std.testing.allocator, "disp-bearer-denied.log");
    defer fx.deinit();

    const caps = [_][]const u8{"cap.echo.say"};
    var ctx = bearerCtx(&caps);
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "echo", "delete", "{}"),
    );

    const contents = try fx.dumpAudit();
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "kind=capability_denied") != null);
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
}

test "D-W1 dispatch: bearer with cap.echo.* wildcard can dispatch any echo.*" {
    var fx = try Fixture.init(std.testing.allocator, "disp-bearer-wildcard.log");
    defer fx.deinit();

    const caps = [_][]const u8{"cap.echo.*"};
    var ctx = bearerCtx(&caps);

    var r1 = try fx.disp.dispatch(&ctx, "echo", "say", "{}");
    defer r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "echo", "delete", "{}");
    defer r2.deinit();
    try std.testing.expect(r1.payload.len > 0);
}

test "D-W1 dispatch: bearer with cap.brain.admin satisfies cap.brain.admin.* sub-scopes" {
    // Register a transient resource whose required cap is below cap.brain.admin
    // to prove the implicit-hierarchy rule from §7.
    var fx = try Fixture.init(std.testing.allocator, "disp-hierarchy.log");
    defer fx.deinit();

    const handler = dispatcher.ResourceHandler{
        .name = "admin",
        .state = null,
        .cap_for_cmd_fn = struct {
            fn f(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
                if (std.mem.eql(u8, cmd, "system_delete")) {
                    return .{ .require = "cap.brain.admin.system.delete" };
                }
                return error.unknown_command;
            }
        }.f,
        .handle_fn = struct {
            fn f(_: ?*anyopaque, _: *const dispatcher.DispatchContext, _: []const u8, _: []const u8, _: std.mem.Allocator) anyerror!dispatcher.Result {
                return dispatcher.Result.empty();
            }
        }.f,
    };
    try fx.disp.register(handler);

    const caps = [_][]const u8{"cap.brain.admin"};
    var ctx = bearerCtx(&caps);
    var result = try fx.disp.dispatch(&ctx, "admin", "system_delete", "{}");
    defer result.deinit();
}

test "D-W1 dispatch: cmd with `.none` cap requirement allows anonymous caller" {
    var fx = try Fixture.init(std.testing.allocator, "disp-none-cap.log");
    defer fx.deinit();

    var ctx = anonymousCtx(&.{});
    var result = try fx.disp.dispatch(&ctx, "echo", "ping", "{}");
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "ping") != null);
}

test "D-W1 dispatch: duplicate registration fails loud" {
    var fx = try Fixture.init(std.testing.allocator, "disp-dup.log");
    defer fx.deinit();

    try std.testing.expectError(
        dispatcher.DispatchError.duplicate_resource,
        fx.disp.register(echoHandler()),
    );
}

test "D-W1 dispatch: handler error path emits err audit-end" {
    // A throwaway handler that always returns a runtime error from
    // handle_fn proves the err-result audit branch.
    var fx = try Fixture.init(std.testing.allocator, "disp-handler-err.log");
    defer fx.deinit();

    const handler = dispatcher.ResourceHandler{
        .name = "boom",
        .state = null,
        .cap_for_cmd_fn = struct {
            fn f(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
                if (std.mem.eql(u8, cmd, "go")) return .none;
                return error.unknown_command;
            }
        }.f,
        .handle_fn = struct {
            fn f(_: ?*anyopaque, _: *const dispatcher.DispatchContext, _: []const u8, _: []const u8, _: std.mem.Allocator) anyerror!dispatcher.Result {
                return error.synthetic_handler_failure;
            }
        }.f,
    };
    try fx.disp.register(handler);

    var ctx = rootCtx();
    try std.testing.expectError(
        error.synthetic_handler_failure,
        fx.disp.dispatch(&ctx, "boom", "go", "{}"),
    );

    const contents = try fx.dumpAudit();
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "kind=handler_err") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "err=synthetic_handler_failure") != null);
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
}

// ─────────────────────────────────────────────────────────────────────
// Property-style audit-pair invariant: random sequence of dispatches
// over every (resource, cmd) shape.  Total audit-pair count must equal
// the number of dispatch calls (one start + one end per call).
// ─────────────────────────────────────────────────────────────────────

test "D-W1 dispatch: audit pair invariant over random command sequence" {
    var fx = try Fixture.init(std.testing.allocator, "disp-invariant.log");
    defer fx.deinit();

    // Sample of (resource, cmd, ctx-builder) pairs that exercises every
    // outcome path through the dispatcher.
    const Case = struct {
        resource: []const u8,
        cmd: []const u8,
        cap_set: []const []const u8,
        // expected_ok: whether dispatch should succeed (otherwise we don't
        // care about the specific error — pair invariant is what we check).
        expected_ok: bool,
    };
    const allow_say = [_][]const u8{"cap.echo.say"};
    const allow_all = [_][]const u8{"cap.echo.*"};
    const cases = [_]Case{
        .{ .resource = "echo", .cmd = "say", .cap_set = &allow_say, .expected_ok = true },
        .{ .resource = "echo", .cmd = "delete", .cap_set = &allow_say, .expected_ok = false }, // capability_denied
        .{ .resource = "echo", .cmd = "ping", .cap_set = &.{}, .expected_ok = true },
        .{ .resource = "echo", .cmd = "scream", .cap_set = &.{}, .expected_ok = false }, // unknown_command
        .{ .resource = "echo", .cmd = "stowaway", .cap_set = &.{}, .expected_ok = false }, // capability_not_declared
        .{ .resource = "ghost", .cmd = "anything", .cap_set = &.{}, .expected_ok = false }, // unknown_resource
        .{ .resource = "echo", .cmd = "say", .cap_set = &allow_all, .expected_ok = true },
        .{ .resource = "echo", .cmd = "delete", .cap_set = &allow_all, .expected_ok = true },
    };

    // Drive a deterministic-but-varied sequence of N dispatches.  Each
    // dispatch must contribute exactly one start + one end audit entry.
    const N: usize = 50;
    var prng = std.Random.DefaultPrng.init(0xD15A7CE7D); // deterministic for CI repro
    const random = prng.random();
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const c = cases[random.intRangeAtMost(usize, 0, cases.len - 1)];
        var ctx = bearerCtx(c.cap_set);
        var result = fx.disp.dispatch(&ctx, c.resource, c.cmd, "{}") catch {
            // expected_ok = false → some error is fine; we don't pin
            // which one because the property under test is the audit
            // pair count, not the error variant (other tests pin those).
            continue;
        };
        defer result.deinit();
        try std.testing.expect(c.expected_ok);
    }

    // Invariant: exactly N start entries and N end entries.
    try std.testing.expectEqual(N, try fx.countPhase("start"));
    try std.testing.expectEqual(N, try fx.countPhase("end"));
}

test "D-W1 capability hierarchy: bare prefix without `.` boundary does not match" {
    // Boundary check spelled out at the public-API level — `cap.brain.admin`
    // does NOT imply `cap.brain.adminx`.
    const caps = [_][]const u8{"cap.brain.admin"};
    const set = dispatcher.CapabilitySet.fromList(&caps);
    try std.testing.expect(!set.contains("cap.brain.adminx"));
    try std.testing.expect(set.contains("cap.brain.admin"));
    try std.testing.expect(set.contains("cap.brain.admin.x"));
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 2 — audit_reads opt-out (per BRAIN-DISPATCHER-UNIFICATION.md
// §10).  High-frequency reads (e.g. `headers.byHeight` from a peer SPV
// client) skip the audit pair to keep the audit log useful.  Mutating
// commands always audit.  Failures (capability_denied, unknown_command,
// handler errors) on opt-out reads still audit — opt-out applies only
// to the happy path.
// ─────────────────────────────────────────────────────────────────────

const ReadOptOut = struct {
    fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
        if (std.mem.eql(u8, cmd, "read_a")) return .none;
        if (std.mem.eql(u8, cmd, "read_admin")) return .{ .require = "cap.test.admin" };
        if (std.mem.eql(u8, cmd, "write_a")) return .{ .require = "cap.test.admin" };
        if (std.mem.eql(u8, cmd, "boom")) return .none;
        return error.unknown_command;
    }
    fn handleFn(
        _: ?*anyopaque,
        _: *const dispatcher.DispatchContext,
        cmd: []const u8,
        _: []const u8,
        allocator: std.mem.Allocator,
    ) anyerror!dispatcher.Result {
        if (std.mem.eql(u8, cmd, "boom")) return error.boom_intentional;
        const payload = try std.fmt.allocPrint(allocator, "{{\"cmd\":\"{s}\"}}", .{cmd});
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    fn isRead(cmd: []const u8) bool {
        if (std.mem.eql(u8, cmd, "read_a")) return true;
        if (std.mem.eql(u8, cmd, "read_admin")) return true;
        if (std.mem.eql(u8, cmd, "boom")) return true;
        return false;
    }
    fn handler() dispatcher.ResourceHandler {
        return .{
            .name = "rw",
            .state = null,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handleFn,
            .audit_reads = false,
            .is_read_fn = isRead,
        };
    }
};

test "D-W1 P2 dispatcher: audit_reads=false read emits a single skip line, no start/end pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, "disp-skip.log");
    defer fx.deinit();
    try fx.disp.register(ReadOptOut.handler());

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "rw", "read_a", "{}");
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("end"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("skip"));
}

test "D-W1 P2 dispatcher: audit_reads=false mutating cmd still emits start/end pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, "disp-skip-write.log");
    defer fx.deinit();
    try fx.disp.register(ReadOptOut.handler());

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "rw", "write_a", "{}");
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("skip"));
}

test "D-W1 P2 dispatcher: capability denial on opt-out read still emits start/end pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, "disp-skip-deny.log");
    defer fx.deinit();
    try fx.disp.register(ReadOptOut.handler());

    var ctx = anonymousCtx(&.{});
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "rw", "read_admin", "{}"),
    );

    // Failures don't opt out — both start AND end emitted, no skip.
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("skip"));
}

test "D-W1 P2 dispatcher: handler error on opt-out read still emits start/end pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, "disp-skip-err.log");
    defer fx.deinit();
    try fx.disp.register(ReadOptOut.handler());

    var ctx = rootCtx();
    try std.testing.expectError(error.boom_intentional, fx.disp.dispatch(&ctx, "rw", "boom", "{}"));

    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("skip"));
}

test "D-W1 P2 dispatcher: audit_reads default (true) keeps start/end pair on every read" {
    // The echo handler registered by the default Fixture sets
    // `audit_reads` to its default (true) — read commands like `ping`
    // emit the full pair.
    var fx = try Fixture.init(std.testing.allocator, "disp-default.log");
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "echo", "ping", "{}");
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("start"));
    try std.testing.expectEqual(@as(usize, 1), try fx.countPhase("end"));
    try std.testing.expectEqual(@as(usize, 0), try fx.countPhase("skip"));
}

```
