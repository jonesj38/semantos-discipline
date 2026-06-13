---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/repl_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.198489+00:00
---

# runtime/semantos-brain/tests/repl_conformance.zig

```zig
// Phase Brain 3 — REPL conformance tests.
//
// Drives `repl.handleLine` directly with a captured Output buffer.
// Covers the v0.1 command set (help / status / modules / audit / hash /
// history / clear / exit / unknown / deferred-engine-commands) plus the
// real-path `call` test (gated on -Denable-wasmtime=true).

const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("config");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");
const instance_manager_mod = @import("instance_manager");
const module_loader_mod = @import("module_loader");
const runner_mod = @import("runner");
const repl_mod = @import("repl");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const wasmtime_backend = @import("wasmtime_backend");
const dispatcher_mod = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2 — generic-verb path test
// D-W1 Phase 1 Part 2 — `device` REPL verb tests need a CertStore.
const bkds_mod = @import("bkds");
const identity_certs_mod = @import("identity_certs");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
// Phase 3 — intent-cells REPL verb tests need an IntentCellLmdbStore +
// dispatcher with the intent_cells handler registered.
const lmdb_mod = @import("lmdb");
const lmdb_config_mod = @import("lmdb_config");
const intent_cell_lmdb_store_mod = @import("intent_cell_lmdb_store");
const intent_cells_handler_mod = @import("intent_cells_handler");
const helm_event_broker_mod = @import("helm_event_broker");
// D-O5.followup-5 — site config REPL verb tests need site_config_handler
// + a sites_dir on disk to read/write through.
const site_config_mod = @import("site_config");
const site_config_handler_mod = @import("site_config_handler");

const TEST_CONFIG_JSON =
    \\{
    \\  "shell": { "data_dir": "/tmp/brain-repl-test", "modules_dir": "/tmp/brain-repl-test/wasm" },
    \\  "modules": {}
    \\}
;

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    cfg: config_mod.Config,
    audit_path: []u8,
    audit: audit_log_mod.AuditLog,
    slot_local: slot_store_mod.LocalSlotStore,
    state_local: derivation_state_mod.LocalStateStore,
    header_local: header_store_mod.LocalHeaderStore,
    broker: broker_mod.Broker,
    manager: instance_manager_mod.InstanceManager,
    runner: runner_mod.Runner,
    instances: std.ArrayList(repl_mod.NamedInstance),
    header_store_handle: header_store_mod.HeaderStore,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var cfg = try config_mod.parseJson(allocator, TEST_CONFIG_JSON);
        errdefer cfg.deinit();

        const ap = try tempPath("repl-audit.log", allocator);
        var audit = audit_log_mod.AuditLog.init();
        try audit.open(ap);
        const slot_local = slot_store_mod.LocalSlotStore.init(allocator);
        const state_local = derivation_state_mod.LocalStateStore.init(allocator);
        const header_local = header_store_mod.LocalHeaderStore.init(allocator);

        return .{
            .allocator = allocator,
            .cfg = cfg,
            .audit_path = ap,
            .audit = audit,
            .slot_local = slot_local,
            .state_local = state_local,
            .header_local = header_local,
            .broker = undefined,
            .manager = instance_manager_mod.InstanceManager.init(allocator),
            .runner = undefined,
            .instances = .empty,
            .header_store_handle = undefined,
        };
    }

    fn bind(self: *Fixture) void {
        self.broker = broker_mod.Broker.init(
            self.allocator,
            self.slot_local.store(),
            self.state_local.store(),
            self.header_local.store(),
            &self.audit,
        );
        self.runner = runner_mod.Runner.init(self.allocator, &self.broker);
        self.header_store_handle = self.header_local.store();
    }

    fn session(self: *Fixture) repl_mod.Session {
        return .{
            .allocator = self.allocator,
            .cfg = &self.cfg,
            .audit_path = self.audit_path,
            .audit = &self.audit,
            .broker = &self.broker,
            .manager = &self.manager,
            .runner = &self.runner,
            .instances = self.instances.items,
            .header_store = &self.header_store_handle,
        };
    }

    fn deinit(self: *Fixture) void {
        for (self.instances.items) |*ni| {
            var inst = ni.instance;
            inst.deinit();
        }
        self.instances.deinit(self.allocator);
        self.runner.deinit();
        self.audit.close();
        std.fs.cwd().deleteFile(self.audit_path) catch {};
        self.allocator.free(self.audit_path);
        self.slot_local.deinit();
        self.state_local.deinit();
        self.header_local.deinit();
        self.manager.deinit();
        self.cfg.deinit();
    }
};

// C4 PR-R1 — use the shared concrete writer leaf (handleLine now takes
// `*const Output`, not `anytype`).
const Out = @import("repl_output").Output;

fn newOut(buf: *std.ArrayList(u8)) Out {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "Brain 3 repl: help prints command list" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);

    const exit = try repl_mod.handleLine(&session, &out, "help");
    try std.testing.expectEqual(repl_mod.ReplExit.@"continue", exit);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "help") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "status") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "audit") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "exit") != null);
}

test "Brain 3 repl: exit and quit both signal quit" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    try std.testing.expectEqual(repl_mod.ReplExit.quit, try repl_mod.handleLine(&session, &out, "exit"));
    try std.testing.expectEqual(repl_mod.ReplExit.quit, try repl_mod.handleLine(&session, &out, "quit"));
}

test "Brain 3 repl: empty / whitespace input is ignored" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    try std.testing.expectEqual(repl_mod.ReplExit.@"continue", try repl_mod.handleLine(&session, &out, ""));
    try std.testing.expectEqual(repl_mod.ReplExit.@"continue", try repl_mod.handleLine(&session, &out, "   "));
    try std.testing.expectEqual(repl_mod.ReplExit.@"continue", try repl_mod.handleLine(&session, &out, "\t\n"));
    // No output should have been written.
    try std.testing.expectEqual(@as(usize, 0), buf.items.len);
}

test "Brain 3 repl: unknown command prints hint" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "fizzbuzz");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown command") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "help") != null);
}

test "Brain 3 repl: deferred engine commands print the Brain 3.5 hint" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    const cases = [_][]const u8{ "identity", "balance", "send", "anchor", "policy", "recover", "sync" };
    for (cases) |c| {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(std.testing.allocator);
        const out = newOut(&buf);
        _ = try repl_mod.handleLine(&session, &out, c);
        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Brain 3.5") != null);
        try std.testing.expect(std.mem.indexOf(u8, buf.items, c) != null);
    }
}

test "Brain 3 repl: status prints data_dir + audit + tip state" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "status");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "config:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "audit log:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "wasmtime:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "header store tip: empty") != null);
}

test "Brain 3 repl: modules empty when nothing loaded" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "modules");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "no modules loaded") != null);
}

test "Brain 3 repl: audit prints recorded entries" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();

    // Record a couple of audit entries through the broker.
    try fx.broker.hostPersistCell(.wallet_engine, 1, "x");
    _ = try fx.broker.hostLoadCell(.wallet_engine, 1);

    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "audit");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "host_persist_cell") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "host_load_cell") != null);
}

test "Brain 3 repl: clear emits ANSI clear-screen escape" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "clear");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[2J") != null);
}

test "Brain 3 repl: hash prints SHA-256 of a WASM file" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    const path = try tempPath("repl-hash.wasm", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(&module_loader_mod.WASM_MAGIC);
    }
    const cmd = try std.fmt.allocPrint(std.testing.allocator, "hash {s}", .{path});
    defer std.testing.allocator.free(cmd);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, cmd);

    const expected = module_loader_mod.computeSha256(&module_loader_mod.WASM_MAGIC);
    var hex_buf: [64]u8 = undefined;
    const charset = "0123456789abcdef";
    for (expected, 0..) |b, i| {
        hex_buf[i * 2 + 0] = charset[(b >> 4) & 0xf];
        hex_buf[i * 2 + 1] = charset[b & 0xf];
    }
    try std.testing.expect(std.mem.indexOf(u8, buf.items, &hex_buf) != null);
}

test "Brain 3 repl: call without args prints usage" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "call");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
}

test "Brain 3 repl: call when wasmtime disabled prints rebuild hint" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "call mod export");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "wasmtime not enabled") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Real-path `call` test (only when -Denable-wasmtime=true).  Loads a
// minimal WAT fixture with an exported function and invokes it through
// the REPL.
// ─────────────────────────────────────────────────────────────────────

const CALL_FIXTURE_WAT =
    \\(module
    \\  (memory (export "memory") 1)
    \\  (func (export "answer") (result i32)
    \\    (i32.const 42))
    \\)
;

test "Brain 3 repl: call invokes a wasmtime export" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();

    // Compile the fixture + register an instance into the session.
    const c = wasmtime_backend.c;
    var wasm_bytes_vec: c.wasm_byte_vec_t = undefined;
    {
        const err = c.wasmtime_wat2wasm(CALL_FIXTURE_WAT.ptr, CALL_FIXTURE_WAT.len, &wasm_bytes_vec);
        if (err != null) {
            c.wasmtime_error_delete(err);
            return error.TestFailed;
        }
    }
    defer c.wasm_byte_vec_delete(&wasm_bytes_vec);
    const dup_bytes = try std.testing.allocator.dupe(u8, wasm_bytes_vec.data[0..wasm_bytes_vec.size]);
    const sha = module_loader_mod.computeSha256(dup_bytes);
    var lm = module_loader_mod.LoadedModule{
        .name = try std.testing.allocator.dupe(u8, "fixture"),
        .path = try std.testing.allocator.dupe(u8, "<test>"),
        .bytes = dup_bytes,
        .sha256 = sha,
        .allocator = std.testing.allocator,
    };
    defer lm.deinit();

    const inst = try fx.runner.instantiate(&lm, .wallet_engine);
    try fx.instances.append(std.testing.allocator, .{ .name = "fixture", .instance = inst });

    var session = fx.session();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "call fixture answer");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "=> 42") != null);
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 0 — dispatcher-path tests.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §4, §5.1, §8.
//
// When a Session has a `dispatcher` configured, status/help/exit are
// routed through the dispatcher's `repl` shim handler instead of the
// legacy direct-call path.  The smoke-test invariant is byte-identical
// output: the shim captures cmdStatus / cmdHelp into a buffer and prints
// it verbatim, so the operator sees the same characters as before.
// ─────────────────────────────────────────────────────────────────────

/// Run handleLine through the legacy path (dispatcher=null) and then
/// the dispatcher path on the SAME Session (so audit_path / data_dir /
/// every borrowed pointer is identical) and return both rendered
/// buffers.  Same backing data → byte-identical output is testable.
fn runBothPaths(allocator: std.mem.Allocator, fx: *Fixture, line: []const u8) !struct { legacy: []u8, dispatched: []u8 } {
    var session = fx.session();

    // Legacy path — dispatcher is null, handleLine takes the if-chain
    // straight to cmdStatus / cmdHelp.
    var legacy_buf = std.ArrayList(u8){};
    errdefer legacy_buf.deinit(allocator);
    const legacy_out = newOut(&legacy_buf);
    _ = try repl_mod.handleLine(&session, &legacy_out, line);

    // Dispatcher path — same Session, now with a configured dispatcher.
    var disp = dispatcher_mod.Dispatcher.init(allocator, session.audit);
    defer disp.deinit();
    try repl_mod.registerReplShims(&disp, &session);
    session.dispatcher = &disp;

    var dispatched_buf = std.ArrayList(u8){};
    errdefer dispatched_buf.deinit(allocator);
    const dispatched_out = newOut(&dispatched_buf);
    _ = try repl_mod.handleLine(&session, &dispatched_out, line);

    return .{
        .legacy = try legacy_buf.toOwnedSlice(allocator),
        .dispatched = try dispatched_buf.toOwnedSlice(allocator),
    };
}

test "D-W1 repl: dispatcher-path `help` is byte-identical to legacy path" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    const both = try runBothPaths(std.testing.allocator, &fx, "help");
    defer std.testing.allocator.free(both.legacy);
    defer std.testing.allocator.free(both.dispatched);
    try std.testing.expectEqualStrings(both.legacy, both.dispatched);
}

test "D-W1 repl: dispatcher-path `status` is byte-identical to legacy path" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    const both = try runBothPaths(std.testing.allocator, &fx, "status");
    defer std.testing.allocator.free(both.legacy);
    defer std.testing.allocator.free(both.dispatched);
    try std.testing.expectEqualStrings(both.legacy, both.dispatched);
}

test "D-W1 repl: dispatcher-path `exit` is byte-identical AND signals quit" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    try repl_mod.registerReplShims(&disp, &session);
    session.dispatcher = &disp;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);

    const exit = try repl_mod.handleLine(&session, &out, "exit");
    try std.testing.expectEqual(repl_mod.ReplExit.quit, exit);
    try std.testing.expectEqualStrings("bye.\n", buf.items);
}

test "D-W1 repl: dispatcher-path `?` aliases to help" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    const both = try runBothPaths(std.testing.allocator, &fx, "?");
    defer std.testing.allocator.free(both.legacy);
    defer std.testing.allocator.free(both.dispatched);
    try std.testing.expectEqualStrings(both.legacy, both.dispatched);
    try std.testing.expect(std.mem.indexOf(u8, both.dispatched, "brain REPL") != null);
}

test "D-W1 repl: dispatcher-path emits a phase=start + phase=end audit pair per dispatch" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    try repl_mod.registerReplShims(&disp, &session);
    session.dispatcher = &disp;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "status");

    // Read the audit log and count the start/end phase markers for
    // dispatcher entries.  Exactly one of each.
    const file = try std.fs.cwd().openFile(fx.audit_path, .{});
    defer file.close();
    const stat = try file.stat();
    const contents = try std.testing.allocator.alloc(u8, stat.size);
    defer std.testing.allocator.free(contents);
    _ = try file.readAll(contents);

    var starts: usize = 0;
    var ends: usize = 0;
    var rest = contents;
    while (std.mem.indexOf(u8, rest, "phase=start")) |i| {
        starts += 1;
        rest = rest[i + "phase=start".len ..];
    }
    rest = contents;
    while (std.mem.indexOf(u8, rest, "phase=end")) |i| {
        ends += 1;
        rest = rest[i + "phase=end".len ..];
    }
    try std.testing.expectEqual(@as(usize, 1), starts);
    try std.testing.expectEqual(@as(usize, 1), ends);
    // op tag confirms the dispatcher routed to repl.status
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"op\":\"repl.status\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 Part 2 — `device` REPL verb
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock_DW1P12() i64 {
    return 1_700_000_000;
}

test "D-W1 P1.2 repl: device list with no cert store hints at `brain device`" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    // Deliberately leave session.cert_store = null.

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "device list");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "no cert store") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "brain device") != null);
}

test "D-W1 P1.2 repl: device list with attached cert store enumerates the chain" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    // Attach a cert store rooted in a tmpdir.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try identity_certs_mod.CertStore.init(std.testing.allocator, real, pinnedClock_DW1P12);
    defer store.deinit();
    const root_pub = [_]u8{0xab} ** bkds_mod.KEY_LEN;
    _ = try store.issueRoot(root_pub, "operator");
    session.cert_store = &store;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "device list");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "1 cert(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "root") != null);
}

test "D-W1 P1.followup repl: device pair without name prints usage" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try identity_certs_mod.CertStore.init(std.testing.allocator, real, pinnedClock_DW1P12);
    defer store.deinit();
    session.cert_store = &store;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    // D-W1 Phase 1 follow-up — `device pair` is now a real verb;
    // calling it without a name prints a usage hint.
    _ = try repl_mod.handleLine(&session, &out, "device pair");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage: device pair") != null);
}

test "D-W1 P1.followup repl: device claim without token prints lab-fixture banner" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try identity_certs_mod.CertStore.init(std.testing.allocator, real, pinnedClock_DW1P12);
    defer store.deinit();
    session.cert_store = &store;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "device claim");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "LAB FIXTURE") != null);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-5 — `site config show / set / validate` REPL verbs.
//
// Drives the new verbs through `repl.handleLine` against a fixture
// that owns a tmp sites_dir + a dispatcher with `site_config_handler`
// registered.  Asserts:
//   • `site config show <domain>` round-trips the seeded site.json
//   • `site config validate <domain> <json>` reports ok without
//     touching disk
//   • `site config set <domain> <json>` rewrites the on-disk file
// ─────────────────────────────────────────────────────────────────────

const SITE_CONFIG_REPL_SAMPLE =
    \\{"site":{"domain":"example.test","content_root":"./public","listen_port":8080},"routes":{"/":{"type":"static","file":"index.html","public":true}}}
;

const SITE_CONFIG_REPL_NEW =
    \\{"site":{"domain":"example.test","content_root":"./public","listen_port":9090},"routes":{"/":{"type":"static","file":"index.html","public":true}}}
;

const SiteConfigReplFixture = struct {
    fx: Fixture,
    tmp: std.testing.TmpDir,
    sites_dir: []u8,
    handler: site_config_handler_mod.Handler,
    audit: audit_log_mod.AuditLog,
    disp: dispatcher_mod.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*SiteConfigReplFixture {
        const self = try allocator.create(SiteConfigReplFixture);
        errdefer allocator.destroy(self);
        self.fx = try Fixture.init(allocator);
        errdefer self.fx.deinit();
        self.fx.bind();

        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.sites_dir = try std.fs.path.join(allocator, &.{ real, "sites" });
        errdefer allocator.free(self.sites_dir);
        std.fs.cwd().makePath(self.sites_dir) catch {};

        // Seed `<sites_dir>/example.test/site.json`.
        const dom_dir = try std.fs.path.join(allocator, &.{ self.sites_dir, "example.test" });
        defer allocator.free(dom_dir);
        std.fs.cwd().makePath(dom_dir) catch {};
        const site_json_path = try std.fs.path.join(allocator, &.{ dom_dir, "site.json" });
        defer allocator.free(site_json_path);
        const f = try std.fs.cwd().createFile(site_json_path, .{});
        defer f.close();
        try f.writeAll(SITE_CONFIG_REPL_SAMPLE);

        self.audit = audit_log_mod.AuditLog.init();
        self.handler = site_config_handler_mod.Handler.init(allocator, self.sites_dir);
        self.disp = dispatcher_mod.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *SiteConfigReplFixture, allocator: std.mem.Allocator) void {
        self.disp.deinit();
        self.audit.close();
        allocator.free(self.sites_dir);
        self.tmp.cleanup();
        self.fx.deinit();
        allocator.destroy(self);
    }

    fn session(self: *SiteConfigReplFixture) repl_mod.Session {
        var s = self.fx.session();
        s.dispatcher = &self.disp;
        return s;
    }

    fn readSiteJson(self: *SiteConfigReplFixture, allocator: std.mem.Allocator) ![]u8 {
        const p = try std.fs.path.join(allocator, &.{ self.sites_dir, "example.test", "site.json" });
        defer allocator.free(p);
        const f = try std.fs.cwd().openFile(p, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try allocator.alloc(u8, stat.size);
        _ = try f.readAll(buf);
        return buf;
    }
};

test "D-O5.followup-5 repl: site config show <domain> dispatches site_config.read" {
    var rf = try SiteConfigReplFixture.init(std.testing.allocator);
    defer rf.deinit(std.testing.allocator);
    var session = rf.session();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "site config show example.test");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"domain\":\"example.test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"json\":") != null);
}

test "D-O5.followup-5 repl: site config validate <domain> <json> reports dry_run ok" {
    var rf = try SiteConfigReplFixture.init(std.testing.allocator);
    defer rf.deinit(std.testing.allocator);
    var session = rf.session();

    var line_buf: [4096]u8 = undefined;
    const line = try std.fmt.bufPrint(&line_buf, "site config validate example.test {s}", .{SITE_CONFIG_REPL_NEW});

    // Capture the on-disk bytes so we can confirm the dry-run didn't
    // touch the file.
    const before = try rf.readSiteJson(std.testing.allocator);
    defer std.testing.allocator.free(before);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, line);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"dry_run\":true") != null);

    const after = try rf.readSiteJson(std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "D-O5.followup-5 repl: site config set <domain> <json> rewrites on-disk file" {
    var rf = try SiteConfigReplFixture.init(std.testing.allocator);
    defer rf.deinit(std.testing.allocator);
    var session = rf.session();

    var line_buf: [4096]u8 = undefined;
    const line = try std.fmt.bufPrint(&line_buf, "site config set example.test {s}", .{SITE_CONFIG_REPL_NEW});

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, line);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"written_at\":") != null);

    const after = try rf.readSiteJson(std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expect(std.mem.indexOf(u8, after, "9090") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Smoke-test pass #1, fix #6 — splitArgs honours double-quoted strings.
//
// Pre-fix the tokeniser was a flat whitespace splitter, so
// `add job "Acme Corp" lead 2026-05-15` produced 5 tokens with broken
// quoting around `Acme` and `Corp"`, surfaced as an `invalid_state`
// error from the FSM dispatcher because token[2] was `Corp"` instead
// of `lead`.  These tests pin the corrected shape.
// ─────────────────────────────────────────────────────────────────────

test "smoke-fix #6 splitArgs: plain whitespace tokens unchanged" {
    var args: [8][]const u8 = undefined;
    const n = repl_mod.splitArgs("add job AcmeCorp lead 2026-05-15", &args);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("add", args[0]);
    try std.testing.expectEqualStrings("job", args[1]);
    try std.testing.expectEqualStrings("AcmeCorp", args[2]);
    try std.testing.expectEqualStrings("lead", args[3]);
    try std.testing.expectEqualStrings("2026-05-15", args[4]);
}

test "smoke-fix #6 splitArgs: quoted middle keeps spaces in one token" {
    var args: [8][]const u8 = undefined;
    const n = repl_mod.splitArgs("add job \"Acme Corp\" lead 2026-05-15", &args);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("add", args[0]);
    try std.testing.expectEqualStrings("job", args[1]);
    try std.testing.expectEqualStrings("Acme Corp", args[2]);
    try std.testing.expectEqualStrings("lead", args[3]);
    try std.testing.expectEqualStrings("2026-05-15", args[4]);
}

test "smoke-fix #6 splitArgs: multiple quoted segments" {
    var args: [8][]const u8 = undefined;
    const n = repl_mod.splitArgs("add job \"Acme\" \"Corp Inc\" lead 2026-05-15", &args);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualStrings("Acme", args[2]);
    try std.testing.expectEqualStrings("Corp Inc", args[3]);
    try std.testing.expectEqualStrings("lead", args[4]);
    try std.testing.expectEqualStrings("2026-05-15", args[5]);
}

test "smoke-fix #6 splitArgs: empty quoted produces empty token" {
    var args: [8][]const u8 = undefined;
    const n = repl_mod.splitArgs("add job \"\" lead 2026-05-15", &args);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("", args[2]);
    try std.testing.expectEqualStrings("lead", args[3]);
}

test "smoke-fix #6 splitArgs: unclosed quote runs to end-of-line" {
    // Mismatched quote: the partial token absorbs the rest of the line.
    // Documented as fall-through behaviour; the typed dispatcher will
    // surface a domain error if the resulting args are nonsense.
    var args: [8][]const u8 = undefined;
    const n = repl_mod.splitArgs("add job \"Acme Corp lead", &args);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("Acme Corp lead", args[2]);
}

test "smoke-fix #6 splitArgs: quoted token at start of line" {
    var args: [4][]const u8 = undefined;
    const n = repl_mod.splitArgs("\"hello world\" trailing", &args);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("hello world", args[0]);
    try std.testing.expectEqualStrings("trailing", args[1]);
}

// ─────────────────────────────────────────────────────────────────────
// Phase 3 — intent-cells REPL verb tests.
//
// Each test stands up a fresh IntentCellsStore + Dispatcher + Handler
// then drives the REPL `submit-intent-cell --envelope <base64>`,
// `find intent-cells [--hat X]`, `find intent-cell <id>` verbs through
// `repl.handleLine` and asserts the rendered JSON contains the
// expected key fragment.
// ─────────────────────────────────────────────────────────────────────

const IntentCellsReplFixture = struct {
    fx: Fixture,
    tmp: std.testing.TmpDir,
    env: lmdb_mod.Env,
    store: intent_cell_lmdb_store_mod.IntentCellLmdbStore,
    handler: intent_cells_handler_mod.Handler,
    audit: audit_log_mod.AuditLog,
    broker: helm_event_broker_mod.Broker,
    disp: dispatcher_mod.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*IntentCellsReplFixture {
        const self = try allocator.create(IntentCellsReplFixture);
        errdefer allocator.destroy(self);
        self.fx = try Fixture.init(allocator);
        errdefer self.fx.deinit();
        self.fx.bind();

        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);

        // Open a fresh LMDB env in a subdir of the tmp dir.
        const lmdb_path = try std.fs.path.join(allocator, &.{ real, "lmdb" });
        defer allocator.free(lmdb_path);
        std.fs.makeDirAbsolute(lmdb_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
        self.env = try lmdb_mod.Env.open(lmdb_path, .{
            .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
            .open_flags = lmdb_config_mod.LmdbConfig.ci_flags,
            .mode = lmdb_config_mod.LmdbConfig.default.mode,
        });

        self.audit = audit_log_mod.AuditLog.init();
        self.broker = helm_event_broker_mod.Broker.init(allocator);
        self.store = try intent_cell_lmdb_store_mod.IntentCellLmdbStore.init(&self.env, allocator);
        self.handler = intent_cells_handler_mod.Handler.initWithDeps(
            allocator,
            &self.store,
            null,
            &self.broker,
            &self.audit,
        );
        self.disp = dispatcher_mod.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *IntentCellsReplFixture, allocator: std.mem.Allocator) void {
        self.disp.deinit();
        self.store.deinit();
        self.env.close();
        self.broker.deinit();
        self.audit.close();
        self.tmp.cleanup();
        self.fx.deinit();
        allocator.destroy(self);
    }

    fn session(self: *IntentCellsReplFixture) repl_mod.Session {
        var s = self.fx.session();
        s.dispatcher = &self.disp;
        return s;
    }
};

test "Phase 3 repl: submit-intent-cell --envelope <b64> dispatches to intent_cells.submit" {
    var lf = try IntentCellsReplFixture.init(std.testing.allocator);
    defer lf.deinit(std.testing.allocator);
    var session = lf.session();

    // Inline envelope matching the cross-language fixture.
    const envelope: []const u8 =
        "{\"kind\":\"oddjobz.intent_cell.v1\",\"version\":1," ++
        "\"cellId\":\"cell-000010-deadbeef-87654321\"," ++
        "\"opcodeBytes\":\"UQ==\"," ++
        "\"hatId\":\"00112233445566778899aabbccddeeff\"," ++
        "\"certId\":\"ffeeddccbbaa99887766554433221100\"," ++
        "\"correlationId\":\"00000000-0000-4000-8000-000000000077\"," ++
        "\"kernelResult\":{\"ok\":true,\"opcount\":1,\"stackDepth\":1,\"gasUsed\":1,\"errorKind\":null}," ++
        "\"originalIntent\":{\"summary\":\"Find wattle\",\"action\":\"find\",\"taxonomyJson\":\"{}\"}}";

    // Base64-encode the envelope (the REPL transport expects base64).
    const encoder = std.base64.standard.Encoder;
    const enc_len = encoder.calcSize(envelope.len);
    const b64 = try std.testing.allocator.alloc(u8, enc_len);
    defer std.testing.allocator.free(b64);
    _ = encoder.encode(b64, envelope);

    var line_buf: std.ArrayList(u8) = .{};
    defer line_buf.deinit(std.testing.allocator);
    try line_buf.appendSlice(std.testing.allocator, "submit-intent-cell --envelope ");
    try line_buf.appendSlice(std.testing.allocator, b64);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, line_buf.items);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"status\":\"accepted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "cell-000010-deadbeef-87654321") != null);
}

test "Phase 3 repl: find intent-cells returns JSON array (empty store → [])" {
    var lf = try IntentCellsReplFixture.init(std.testing.allocator);
    defer lf.deinit(std.testing.allocator);
    var session = lf.session();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "find intent-cells");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[]") != null);
}

test "Phase 3 repl: find intent-cell <id> on miss returns typed not_found body" {
    var lf = try IntentCellsReplFixture.init(std.testing.allocator);
    defer lf.deinit(std.testing.allocator);
    var session = lf.session();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "find intent-cell never-existed-1");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"error\":\"not_found\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// C4 PR-R2 — generic `<resource> <verb> [args]` REPL path.
//
// A stub resource self-describes its verbs (verbs_fn); the generic path
// resolves it via dispatcher.findHandler, parses CLI args into the dispatch
// envelope per the schema, dispatches, and prints the result. No JobsStore /
// LMDB needed — this exercises the wiring (the envelope parser itself is
// unit-tested in src/verb_schema.zig).
// ─────────────────────────────────────────────────────────────────────

const STUB_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "echo", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
        .{ .name = "foo", .kind = .string },
    } },
};
fn stubVerbs(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &STUB_VERBS;
}
fn stubCap(_: ?*anyopaque, cmd: []const u8) dispatcher_mod.CapDeclError!dispatcher_mod.CapDecl {
    if (std.mem.eql(u8, cmd, "echo")) return .none;
    return error.unknown_command;
}
fn stubHandle(
    _: ?*anyopaque,
    _: *const dispatcher_mod.DispatchContext,
    _: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher_mod.Result {
    // Echo the built envelope back as the payload.
    return dispatcher_mod.Result.ownedPayload(allocator, try allocator.dupe(u8, args_json));
}

fn stubResource() dispatcher_mod.ResourceHandler {
    return .{
        .name = "stub",
        .state = null,
        .cap_for_cmd_fn = stubCap,
        .handle_fn = stubHandle,
        .verbs_fn = stubVerbs,
    };
}

test "R2 repl: generic <resource> <verb> path parses schema args + dispatches" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    try disp.register(stubResource());
    session.dispatcher = &disp;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    // positional `myid` → id; `--foo bar` → foo
    _ = try repl_mod.handleLine(&session, &out, "stub echo myid --foo bar");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"id\":\"myid\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"foo\":\"bar\"") != null);
}

test "R2 repl: generic path reports unknown verb on a self-describing resource" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    try disp.register(stubResource());
    session.dispatcher = &disp;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "stub nope");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown verb") != null);
}

test "R2 repl: unknown resource still falls through to unknown command" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    session.dispatcher = &disp;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "nonexistent thing");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown command") != null);
}

// ─────────────────────────────────────────────────────────────────────
// C4 PR-R3 — cartridge-registered REPL verb forms.
//
// handleLine consults session.repl_verb_registry (after the hardcoded
// branches, before the generic path). A registered `<cmd> <resource>` fires
// its handler over the remaining args. No cmd code moved yet (R3b) — this
// proves the seam.
// ─────────────────────────────────────────────────────────────────────

const repl_verb_registry_mod = @import("repl_verb_registry");

fn stubReplVerb(
    _: std.mem.Allocator,
    _: *dispatcher_mod.Dispatcher,
    out: *const @import("repl_output").Output,
    args: []const []const u8,
) anyerror!void {
    try out.print("frobbed:{d}", .{args.len});
}

test "R3 repl: a registered verb form fires via handleLine" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();

    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    session.dispatcher = &disp;

    var reg: repl_verb_registry_mod.ReplVerbRegistry = .{};
    reg.add(.{ .cmd = "frobnicate", .resource = "widget", .handler = stubReplVerb });
    session.repl_verb_registry = &reg;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "frobnicate widget a b");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "frobbed:2") != null);
}

test "R3 repl: unregistered verb form falls through (no registry crash)" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    var disp = dispatcher_mod.Dispatcher.init(std.testing.allocator, session.audit);
    defer disp.deinit();
    session.dispatcher = &disp;
    var reg: repl_verb_registry_mod.ReplVerbRegistry = .{};
    session.repl_verb_registry = &reg;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "frobnicate widget");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown command") != null);
}

test "R4 repl: help lists cartridge-registered verbs (derived, not hardcoded)" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    fx.bind();
    var session = fx.session();
    // No dispatcher: `help` goes straight to cmdHelp (with a dispatcher, prod
    // routes help through the repl shim which also calls cmdHelp(session)).
    var reg: repl_verb_registry_mod.ReplVerbRegistry = .{};
    reg.add(.{ .cmd = "frobnicate", .resource = "widget", .handler = stubReplVerb });
    session.repl_verb_registry = &reg;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOut(&buf);
    _ = try repl_mod.handleLine(&session, &out, "help");
    // The brain hardcodes no oddjobz verbs; the registered one shows up derived.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Cartridge verbs") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "frobnicate widget") != null);
    // And the old hardcoded oddjobz help lines are gone.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "quote job <id>") == null);
}

```
