---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/sites_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.192646+00:00
---

# runtime/semantos-brain/tests/sites_handler_conformance.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `sites` row), §8 Phase 2.
//
// Conformance suite for `runtime/semantos-brain/src/resources/sites_handler.zig`.
// Mirrors the bearer_tokens_handler and identity_certs_handler suites:
// per-command happy path + cap-deny + audit-pair invariant + typed
// error paths.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const handler_mod = @import("sites_handler");

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    sites_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const sites_dir = try std.fs.path.join(allocator, &.{ real, "sites" });
        errdefer allocator.free(sites_dir);
        std.fs.cwd().makePath(sites_dir) catch {};
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .sites_dir = sites_dir,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.handler = handler_mod.Handler.init(allocator, self.sites_dir);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.sites_dir);
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
// init / list / get_config / validate happy path
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 sites: init scaffolds site.json + list shows the domain" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var init_result = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"poker.example.com"}
    );
    defer init_result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, init_result.payload, "poker.example.com") != null);

    var list_result = try fx.disp.dispatch(&ctx, "sites", "list", "{}");
    defer list_result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, list_result.payload, "poker.example.com") != null);
}

test "D-W1 P2 sites: init duplicate returns duplicate_resource" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var first = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"foo.example.com"}
    );
    defer first.deinit();
    try std.testing.expectError(
        handler_mod.HandlerError.duplicate_resource,
        fx.disp.dispatch(&ctx, "sites", "init",
            \\{"domain":"foo.example.com"}
        ),
    );
}

test "D-W1 P2 sites: init rejects path-traversal-shaped domain" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "sites", "init",
            \\{"domain":"../escape"}
        ),
    );
}

test "D-W1 P2 sites: get_config returns shape of fresh init" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"a.example.com"}
    );
    defer ir.deinit();
    var cfg = try fx.disp.dispatch(&ctx, "sites", "get_config",
        \\{"domain":"a.example.com"}
    );
    defer cfg.deinit();
    try std.testing.expect(std.mem.indexOf(u8, cfg.payload, "\"domain\":\"a.example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.payload, "\"listen_port\":8080") != null);
}

test "D-W1 P2 sites: validate of fresh init returns 0 errors" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"valid.example.com"}
    );
    defer ir.deinit();
    var rep = try fx.disp.dispatch(&ctx, "sites", "validate",
        \\{"domain":"valid.example.com"}
    );
    defer rep.deinit();
    try std.testing.expect(std.mem.indexOf(u8, rep.payload, "\"err_count\":0") != null);
}

test "D-W1 P2 sites: validate of unknown domain returns not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_found,
        fx.disp.dispatch(&ctx, "sites", "validate",
            \\{"domain":"missing.example.com"}
        ),
    );
}

test "D-W1 P2 sites: validate flags invalid config (payment_required without recipient)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"pay.example.com"}
    );
    defer ir.deinit();

    // route_add a payment_required route with no recipient.
    var add_res = try fx.disp.dispatch(&ctx, "sites", "route_add",
        \\{"domain":"pay.example.com","path":"/premium","type":"static","file":"premium.html","auth":"payment_required","price_sats":1000}
    );
    defer add_res.deinit();

    var rep = try fx.disp.dispatch(&ctx, "sites", "validate",
        \\{"domain":"pay.example.com"}
    );
    defer rep.deinit();
    // Expect at least one validation error.
    try std.testing.expect(std.mem.indexOf(u8, rep.payload, "\"err_count\":0") == null);
    try std.testing.expect(std.mem.indexOf(u8, rep.payload, "payment_recipient") != null);
}

// ─────────────────────────────────────────────────────────────────────
// route_add / route_remove / set_listen_port
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 sites: route_add of static route reflects in get_config" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"r.example.com"}
    );
    defer ir.deinit();
    var add = try fx.disp.dispatch(&ctx, "sites", "route_add",
        \\{"domain":"r.example.com","path":"/about","type":"static","file":"about.html"}
    );
    defer add.deinit();
    try std.testing.expect(std.mem.indexOf(u8, add.payload, "\"ok\":true") != null);

    var cfg = try fx.disp.dispatch(&ctx, "sites", "get_config",
        \\{"domain":"r.example.com"}
    );
    defer cfg.deinit();
    try std.testing.expect(std.mem.indexOf(u8, cfg.payload, "/about") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.payload, "about.html") != null);
}

test "D-W1 P2 sites: route_add duplicate path returns duplicate_route" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"d.example.com"}
    );
    defer ir.deinit();
    // "/" already exists from defaultJsonTemplate; adding a second
    // "/" entry should fail loud.
    try std.testing.expectError(
        handler_mod.HandlerError.duplicate_route,
        fx.disp.dispatch(&ctx, "sites", "route_add",
            \\{"domain":"d.example.com","path":"/","type":"static","file":"alt.html"}
        ),
    );
}

test "D-W1 P2 sites: route_add static without file returns validation_failed" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"v.example.com"}
    );
    defer ir.deinit();
    try std.testing.expectError(
        handler_mod.HandlerError.validation_failed,
        fx.disp.dispatch(&ctx, "sites", "route_add",
            \\{"domain":"v.example.com","path":"/x","type":"static"}
        ),
    );
}

test "D-W1 P2 sites: route_remove drops route, idempotent on missing" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"rm.example.com"}
    );
    defer ir.deinit();
    var add = try fx.disp.dispatch(&ctx, "sites", "route_add",
        \\{"domain":"rm.example.com","path":"/help","type":"static","file":"help.html"}
    );
    defer add.deinit();

    var rem1 = try fx.disp.dispatch(&ctx, "sites", "route_remove",
        \\{"domain":"rm.example.com","path":"/help"}
    );
    defer rem1.deinit();
    try std.testing.expect(std.mem.indexOf(u8, rem1.payload, "\"removed\":true") != null);

    // Idempotent — second remove is a no-op.
    var rem2 = try fx.disp.dispatch(&ctx, "sites", "route_remove",
        \\{"domain":"rm.example.com","path":"/help"}
    );
    defer rem2.deinit();
    try std.testing.expect(std.mem.indexOf(u8, rem2.payload, "\"removed\":false") != null);
}

test "D-W1 P2 sites: set_listen_port updates port; get_config sees it" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"port.example.com"}
    );
    defer ir.deinit();
    var sp = try fx.disp.dispatch(&ctx, "sites", "set_listen_port",
        \\{"domain":"port.example.com","port":9000}
    );
    defer sp.deinit();
    try std.testing.expect(std.mem.indexOf(u8, sp.payload, "\"port\":9000") != null);

    var cfg = try fx.disp.dispatch(&ctx, "sites", "get_config",
        \\{"domain":"port.example.com"}
    );
    defer cfg.deinit();
    try std.testing.expect(std.mem.indexOf(u8, cfg.payload, "\"listen_port\":9000") != null);
}

test "D-W1 P2 sites: set_listen_port out-of-range returns invalid_args" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"bad.example.com"}
    );
    defer ir.deinit();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "sites", "set_listen_port",
            \\{"domain":"bad.example.com","port":70000}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Capability gating
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 sites: anonymous caller cannot init" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "sites", "init",
            \\{"domain":"x.example.com"}
        ),
    );
}

test "D-W1 P2 sites: anonymous caller can validate" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Seed with root.
    var root = rootCtx();
    var ir = try fx.disp.dispatch(&root, "sites", "init",
        \\{"domain":"pub.example.com"}
    );
    defer ir.deinit();

    var ctx = anonymousCtx();
    var rep = try fx.disp.dispatch(&ctx, "sites", "validate",
        \\{"domain":"pub.example.com"}
    );
    defer rep.deinit();
    try std.testing.expect(std.mem.indexOf(u8, rep.payload, "\"err_count\":0") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Unknown command
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 sites: unknown command returns typed unknown_command" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_command,
        fx.disp.dispatch(&ctx, "sites", "no_such_op", "{}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Audit semantics (audit_reads = false)
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 sites: mutating commands emit audit pair; reads emit single skip line" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var ir = try fx.disp.dispatch(&ctx, "sites", "init",
        \\{"domain":"audit.example.com"}
    );
    defer ir.deinit();
    var listed = try fx.disp.dispatch(&ctx, "sites", "list", "{}");
    defer listed.deinit();

    const text = try fx.dumpAudit();
    defer allocator.free(text);

    // init is mutating → start + end pair.
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
    // 1 mutation (init) → 1 start + 1 end. 1 read (list) → 1 skip,
    // no start, no end.
    try std.testing.expectEqual(@as(usize, 1), start_count);
    try std.testing.expectEqual(@as(usize, 1), end_count);
    try std.testing.expectEqual(@as(usize, 1), skip_count);

    // The skip detail tag carries `kind=read_no_audit`.
    try std.testing.expect(std.mem.indexOf(u8, text, "kind=read_no_audit") != null);
}

test "D-W1 P2 sites: capability-denied on a read still audits (failures don't opt out)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // get_config requires cap.brain.admin; anonymous caller hits
    // capability_denied.  Even though `get_config` is a read, the
    // failure path still emits the audit pair so denials show up
    // in the log.
    var ctx = anonymousCtx();
    _ = fx.disp.dispatch(&ctx, "sites", "get_config",
        \\{"domain":"x.example.com"}
    ) catch {};

    const text = try fx.dumpAudit();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "phase=start") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "kind=capability_denied") != null);
}

```
