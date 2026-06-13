---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/estimates_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.185748+00:00
---

# runtime/semantos-brain/tests/estimates_handler_conformance.zig

```zig
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2 — conformance suite for
// `resources/estimates_handler.zig`.
//
// Cloned from `quotes_handler_conformance.zig` MINUS every
// FSM-transition case + the cross-language parity oracle (the Estimate
// cell type is AFFINE — no FSM, no `quote_fsm.json`-style oracle, per
// docs/design/ODDJOBZ-ESTIMATE-ROM-INGRESS.md §3.1 / §5).
//
// What this closes:
//
//   • create → find round-trip (JSON-array shape every helm parser
//     prefers when the response starts with `[`).
//   • FK validation: `estimates.create` with a `job_id` not in the
//     jobs store returns `{error: "job_not_found", job_id}` (200, NOT
//     a dispatcher error).
//   • find_by_job_id filter.
//   • find_by_id miss → typed `{error:"not_found", id}` body.
//   • acknowledge sets ack_status (AFFINE plain-field write; idempotent
//     on identical re-ack).
//   • invalid ack_status / estimate_type rejected.
//   • cap-gating: read cmds require `cap.oddjobz.read_estimates`;
//     create + acknowledge require `cap.oddjobz.write_estimate`.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const estimates_store_fs = @import("estimates_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const estimates_handler_mod = @import("estimates_handler");
const helm_event_broker = @import("helm_event_broker");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    estimates_store: estimates_store_fs.EstimatesStore,
    jobs_store: jobs_store_fs.JobsStore,
    handler: estimates_handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        self.tmp_dir = tmp;
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);
        self.audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(self.audit_path);

        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.estimates_store = try estimates_store_fs.EstimatesStore.init(allocator, &self.cs, pinnedClock);
        self.jobs_store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = estimates_handler_mod.Handler.init(allocator, &self.estimates_store, &self.jobs_store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.estimates_store.deinit();
        self.jobs_store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    /// Seed a Job in the JobsStore directly (bypass the jobs handler —
    /// we don't register it on the dispatcher in this suite).
    fn seedJob(self: *Fixture, id: []const u8) !void {
        _ = try self.jobs_store.append(.{
            .id = id,
            .customer_name = "Acme",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-01T00:00:00Z",
        });
    }

    /// Seed an Estimate via the dispatcher's `estimates.create` cmd —
    /// exercises the same audit-pair path the rest of the suite asserts.
    fn seedEstimateAt(
        self: *Fixture,
        ctx: *dispatcher.DispatchContext,
        id: []const u8,
        job_id: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(std.testing.allocator);
        try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
        try buf.appendSlice(std.testing.allocator, id);
        try buf.appendSlice(std.testing.allocator, "\",\"job_id\":\"");
        try buf.appendSlice(std.testing.allocator, job_id);
        try buf.appendSlice(std.testing.allocator, "\",\"estimate_type\":\"auto_rom\",\"cost_min\":5000,\"cost_max\":20000,\"created_at\":\"2026-05-01T00:00:00Z\",\"updated_at\":\"2026-05-01T00:00:00Z\"}");
        var r = try self.disp.dispatch(ctx, "estimates", "create", buf.items);
        r.deinit();
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn bearerCtxWithCaps(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .bearer = .{ .fingerprint_hex = [_]u8{'0'} ** 64, .label = "test" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-bearer", .transport_label = "test" },
    };
}

fn jsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.not_string;
    return try allocator.dupe(u8, v.string);
}

fn jsonArrayLen(allocator: std.mem.Allocator, json: []const u8) !usize {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.not_array;
    return parsed.value.array.items.len;
}

// ─────────────────────────────────────────────────────────────────────
// create → find → find_by_id round-trip (root scope)
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: create → find returns the estimate (JSON shape)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var create_r = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-001","job_id":"j-001","cost_min":5000,"cost_max":20000,"notes":"first rom"}
    );
    defer create_r.deinit();
    const status = try jsonString(allocator, create_r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);

    var find_r = try fx.disp.dispatch(&ctx, "estimates", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_r.payload));

    // ack_status defaults to "pending"; estimate_type defaults to "auto_rom".
    var byid = try fx.disp.dispatch(&ctx, "estimates", "find_by_id",
        \\{"id":"e-001"}
    );
    defer byid.deinit();
    const ack = try jsonString(allocator, byid.payload, "ack_status");
    defer allocator.free(ack);
    try std.testing.expectEqualStrings("pending", ack);
    const et = try jsonString(allocator, byid.payload, "estimate_type");
    defer allocator.free(et);
    try std.testing.expectEqualStrings("auto_rom", et);
}

test "Slice2 estimates: find_by_job_id filters on parent job" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    try fx.seedJob("j-A");
    try fx.seedJob("j-B");
    var ctx = rootCtx();
    try fx.seedEstimateAt(&ctx, "e-A1", "j-A");
    try fx.seedEstimateAt(&ctx, "e-A2", "j-A");
    try fx.seedEstimateAt(&ctx, "e-B1", "j-B");

    var r = try fx.disp.dispatch(&ctx, "estimates", "find",
        \\{"job_id":"j-A"}
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayLen(allocator, r.payload));
}

test "Slice2 estimates: find_by_id on missing returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "estimates", "find_by_id",
        \\{"id":"nope"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// FK validation
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: create with non-existent job_id returns job_not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-orphan","job_id":"j-not-real","cost_min":100,"cost_max":200}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("job_not_found", err_kind);

    // Estimate was NOT persisted.
    var find_r = try fx.disp.dispatch(&ctx, "estimates", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, find_r.payload));
}

// ─────────────────────────────────────────────────────────────────────
// Idempotent re-create
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: re-create with same id + same contents returns already_exists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    const args =
        \\{"id":"e-idem","job_id":"j-001","estimate_type":"auto_rom","cost_min":5000,"cost_max":20000,"ack_status":"pending","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    ;
    var first = try fx.disp.dispatch(&ctx, "estimates", "create", args);
    defer first.deinit();
    var second = try fx.disp.dispatch(&ctx, "estimates", "create", args);
    defer second.deinit();
    const status = try jsonString(allocator, second.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("already_exists", status);
}

test "Slice2 estimates: re-create with different contents returns typed handler error" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var first = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-conflict","job_id":"j-001","estimate_type":"auto_rom","cost_min":5000,"cost_max":20000,"ack_status":"pending","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    );
    first.deinit();
    // Differs on cost_max.
    try std.testing.expectError(estimates_handler_mod.HandlerError.estimate_id_in_use_with_different_contents, fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-conflict","job_id":"j-001","estimate_type":"auto_rom","cost_min":5000,"cost_max":99999,"ack_status":"pending","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    ));
}

// ─────────────────────────────────────────────────────────────────────
// Invalid input
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: invalid ack_status / estimate_type rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    try std.testing.expectError(estimates_handler_mod.HandlerError.invalid_ack_status, fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-bad-ack","job_id":"j-001","cost_min":1,"cost_max":2,"ack_status":"bogus"}
    ));
    try std.testing.expectError(estimates_handler_mod.HandlerError.invalid_estimate_type, fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-bad-type","job_id":"j-001","cost_min":1,"cost_max":2,"estimate_type":"bogus"}
    ));
}

// ─────────────────────────────────────────────────────────────────────
// acknowledge — AFFINE plain-field write (no FSM)
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: acknowledge sets ack_status + acknowledged_at" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedEstimateAt(&ctx, "e-ack", "j-001");

    var r = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-ack","ack_status":"accepted","acknowledged_at":"2026-05-02T10:00:00Z"}
    );
    defer r.deinit();
    const ack = try jsonString(allocator, r.payload, "ack_status");
    defer allocator.free(ack);
    try std.testing.expectEqualStrings("accepted", ack);
    const ack_at = try jsonString(allocator, r.payload, "acknowledged_at");
    defer allocator.free(ack_at);
    try std.testing.expectEqualStrings("2026-05-02T10:00:00Z", ack_at);
}

test "Slice2 estimates: acknowledge is idempotent on identical re-ack" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedEstimateAt(&ctx, "e-reack", "j-001");

    var r1 = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-reack","ack_status":"accepted"}
    );
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-reack","ack_status":"accepted"}
    );
    defer r2.deinit();
    const ack = try jsonString(allocator, r2.payload, "ack_status");
    defer allocator.free(ack);
    try std.testing.expectEqualStrings("accepted", ack);
}

test "Slice2 estimates: acknowledge with bad ack_status is a typed handler error" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedEstimateAt(&ctx, "e-bad", "j-001");

    try std.testing.expectError(estimates_handler_mod.HandlerError.invalid_ack_status, fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-bad","ack_status":"bogus"}
    ));
}

test "Slice2 estimates: acknowledge missing id returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"never-existed","ack_status":"accepted"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// Cap-gating
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: bearer without cap.oddjobz.read_estimates is denied for find" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "estimates", "find", "{}"));
}

test "Slice2 estimates: bearer with read_estimates can find but not create" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.read_estimates"});

    var ok = try fx.disp.dispatch(&ctx, "estimates", "find", "{}");
    ok.deinit();
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-001","job_id":"j-001","cost_min":100,"cost_max":200}
    ));
}

test "Slice2 estimates: bearer with write_estimate can create + acknowledge but not read" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.write_estimate"});

    var ok = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-001","job_id":"j-001","cost_min":100,"cost_max":200}
    );
    ok.deinit();
    var ack = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-001","ack_status":"accepted"}
    );
    ack.deinit();
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "estimates", "find", "{}"));
}

// ─────────────────────────────────────────────────────────────────────
// Audit-pair invariant
// ─────────────────────────────────────────────────────────────────────

test "Slice2 estimates: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var r1 = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-audit","job_id":"j-001","cost_min":100,"cost_max":200}
    );
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "estimates", "find", "{}");
    r2.deinit();

    const f = try std.fs.cwd().openFile(fx.audit_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    var starts: usize = 0;
    var ends: usize = 0;
    var it = std.mem.splitScalar(u8, buf, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const matches_create = std.mem.indexOf(u8, line, "\"op\":\"estimates.create\"") != null;
        const matches_find = std.mem.indexOf(u8, line, "\"op\":\"estimates.find\"") != null;
        if (!matches_create and !matches_find) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// ─────────────────────────────────────────────────────────────────────
// Broker emit assertions for estimates.create + estimates.acknowledge.
// ─────────────────────────────────────────────────────────────────────

const PublishSink = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList([]u8),
    payloads: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) PublishSink {
        return .{ .allocator = allocator, .types = .{}, .payloads = .{} };
    }

    fn deinit(self: *PublishSink) void {
        for (self.types.items) |s| self.allocator.free(s);
        for (self.payloads.items) |s| self.allocator.free(s);
        self.types.deinit(self.allocator);
        self.payloads.deinit(self.allocator);
    }

    fn callback(state: ?*anyopaque, event: helm_event_broker.Event) void {
        const self: *PublishSink = @ptrCast(@alignCast(state.?));
        const t = self.allocator.dupe(u8, event.type) catch return;
        const p = self.allocator.dupe(u8, event.payload_json) catch {
            self.allocator.free(t);
            return;
        };
        self.types.append(self.allocator, t) catch {
            self.allocator.free(t);
            self.allocator.free(p);
            return;
        };
        self.payloads.append(self.allocator, p) catch {
            self.allocator.free(p);
            return;
        };
    }
};

const BrokerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    estimates_store: estimates_store_fs.EstimatesStore,
    jobs_store: jobs_store_fs.JobsStore,
    handler: estimates_handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    broker: helm_event_broker.Broker,

    fn init(allocator: std.mem.Allocator) !*BrokerFixture {
        const self = try allocator.create(BrokerFixture);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        self.tmp_dir = tmp;
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);
        self.audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(self.audit_path);

        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();
        self.broker = helm_event_broker.Broker.init(allocator);

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.estimates_store = try estimates_store_fs.EstimatesStore.init(allocator, &self.cs, pinnedClock);
        self.jobs_store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = estimates_handler_mod.Handler.initWithBroker(
            allocator,
            &self.estimates_store,
            &self.jobs_store,
            &self.broker,
            &self.audit,
        );
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *BrokerFixture) void {
        self.broker.deinit();
        self.disp.deinit();
        self.estimates_store.deinit();
        self.jobs_store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn seedJob(self: *BrokerFixture, id: []const u8) !void {
        _ = try self.jobs_store.append(.{
            .id = id,
            .customer_name = "Acme",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-01T00:00:00Z",
        });
    }

    fn seedEstimateAt(
        self: *BrokerFixture,
        ctx: *dispatcher.DispatchContext,
        id: []const u8,
        job_id: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(std.testing.allocator);
        try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
        try buf.appendSlice(std.testing.allocator, id);
        try buf.appendSlice(std.testing.allocator, "\",\"job_id\":\"");
        try buf.appendSlice(std.testing.allocator, job_id);
        try buf.appendSlice(std.testing.allocator, "\",\"estimate_type\":\"auto_rom\",\"cost_min\":5000,\"cost_max\":20000,\"created_at\":\"2026-05-01T00:00:00Z\",\"updated_at\":\"2026-05-01T00:00:00Z\"}");
        var r = try self.disp.dispatch(ctx, "estimates", "create", buf.items);
        r.deinit();
    }
};

test "Slice2 estimates.create publishes estimate.created to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-pub");

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "estimates", "create",
        \\{"id":"e-pub","job_id":"j-pub","estimate_type":"auto_rom","cost_min":1000,"cost_max":2500,"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("estimate.created", sink.types.items[0]);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"e-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"job_id\":\"j-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"estimate_type\":\"auto_rom\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"ack_status\":\"pending\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"cost_min\":1000") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"cost_max\":2500") != null);
}

test "Slice2 estimates.acknowledge publishes estimate.acknowledged to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-ack");

    var sink = PublishSink.init(allocator);
    defer sink.deinit();

    var ctx = rootCtx();
    try fx.seedEstimateAt(&ctx, "e-ack", "j-ack");

    // Subscribe AFTER seed so create-emit doesn't interfere.
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var r = try fx.disp.dispatch(&ctx, "estimates", "acknowledge",
        \\{"id":"e-ack","ack_status":"accepted"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("estimate.acknowledged", sink.types.items[0]);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"e-ack\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"job_id\":\"j-ack\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"from\":\"pending\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"to\":\"accepted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"acknowledged_at\":") != null);
}

```
