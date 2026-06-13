---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/quote_seed_router_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.188654+00:00
---

# runtime/semantos-brain/tests/quote_seed_router_conformance.zig

```zig
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 4 — Conformance suite for
// `quote_seed_router.zig`.
//
// Cloned from visit_rollup_router_conformance.zig's broker→dispatcher
// fixture, additionally wiring the estimates + quotes stores/handlers
// (so the router's estimates.find / quotes.find / quotes.create
// dispatches resolve, same store+handler+register pattern the
// estimates/quotes conformance suites use). The router subscribes to
// `job.transitioned`; on from=="qualified" AND to=="quoted" it seeds
// a DRAFT Quote from the job's most-recent accepted ROM Estimate.
//
// Coverage:
//   • happy path     — accepted Estimate → qualified→quoted → a draft
//                       Quote with the estimate's cost bounds exists
//   • no accepted    — only pending Estimate → no quote created
//   • idempotent     — publish twice → exactly one quote
//   • non-qualified→quoted ignored (visited→quoted; lead→qualified) —
//                       pendingCount 0 after the callback, no seed
//   • non-job.transitioned event ignored
//   • gate disabled  — enabled=false → no-op

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const jobs_handler_mod = @import("jobs_handler");
const estimates_store_fs = @import("estimates_store_fs");
const estimates_handler_mod = @import("estimates_handler");
const quotes_store_fs = @import("quotes_store_fs");
const quotes_handler_mod = @import("quotes_handler");
const helm_event_broker = @import("helm_event_broker");
const quote_seed_router = @import("quote_seed_router");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 8 * 1024 * 1024,
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
    audit_path: []u8,
    audit: audit_log.AuditLog,
    broker: helm_event_broker.Broker,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    store: jobs_store_fs.JobsStore,
    handler: jobs_handler_mod.Handler,
    estimates_store: estimates_store_fs.EstimatesStore,
    estimates_handler: estimates_handler_mod.Handler,
    quotes_store: quotes_store_fs.QuotesStore,
    quotes_handler: quotes_handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    router: *quote_seed_router.Router,

    fn init(allocator: std.mem.Allocator, enabled: bool) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.allocator = allocator;
        self.tmp_dir = tmp;
        self.data_dir = data_dir;
        self.audit_path = audit_path;
        self.audit = audit_log.AuditLog.init();
        self.broker = helm_event_broker.Broker.init(allocator);
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();
        try self.audit.open(audit_path);
        self.store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = jobs_handler_mod.Handler.initWithBroker(
            allocator,
            &self.store,
            &self.broker,
            &self.audit,
        );
        self.estimates_store = try estimates_store_fs.EstimatesStore.init(allocator, &self.cs, pinnedClock);
        self.estimates_handler = estimates_handler_mod.Handler.init(
            allocator,
            &self.estimates_store,
            &self.store,
        );
        self.quotes_store = try quotes_store_fs.QuotesStore.init(allocator, &self.cs, pinnedClock);
        self.quotes_handler = quotes_handler_mod.Handler.init(
            allocator,
            &self.quotes_store,
            &self.store,
        );
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        try self.disp.register(self.estimates_handler.resourceHandler());
        try self.disp.register(self.quotes_handler.resourceHandler());
        self.router = try quote_seed_router.Router.init(
            allocator,
            &self.broker,
            &self.disp,
            &self.audit,
            enabled,
        );
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.router.deinit();
        self.disp.deinit();
        self.quotes_store.deinit();
        self.estimates_store.deinit();
        self.store.deinit();
        self.broker.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn rootCtx(_: *Fixture) dispatcher.DispatchContext {
        return .{
            .auth = .in_process_root,
            .capabilities = dispatcher.CapabilitySet.empty(),
            .meta = .{ .request_id = "test", .transport_label = "test" },
        };
    }

    fn createJob(self: *Fixture, id: []const u8, state: []const u8) !void {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"id\":\"");
        try args_buf.appendSlice(self.allocator, id);
        try args_buf.appendSlice(self.allocator, "\",\"customer_name\":\"Pergola Co\",\"state\":\"");
        try args_buf.appendSlice(self.allocator, state);
        try args_buf.appendSlice(self.allocator, "\",\"scheduled_at\":\"\",\"created_at\":\"2026-05-02T10:00:00Z\"}");
        var r = try self.disp.dispatch(&ctx, "jobs", "create", args_buf.items);
        defer r.deinit();
    }

    /// Mint an Estimate for `job_id` with the given ack_status + cost
    /// bounds via the dispatcher (exercises the real estimates.create
    /// path the production code reads back).
    fn createEstimate(
        self: *Fixture,
        id: []const u8,
        job_id: []const u8,
        ack_status: []const u8,
        cost_min: i64,
        cost_max: i64,
        created_at: []const u8,
    ) !void {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"id\":\"");
        try args_buf.appendSlice(self.allocator, id);
        try args_buf.appendSlice(self.allocator, "\",\"job_id\":\"");
        try args_buf.appendSlice(self.allocator, job_id);
        try args_buf.appendSlice(self.allocator, "\",\"estimate_type\":\"auto_rom\",\"ack_status\":\"");
        try args_buf.appendSlice(self.allocator, ack_status);
        try args_buf.print(self.allocator, "\",\"cost_min\":{d},\"cost_max\":{d}", .{ cost_min, cost_max });
        try args_buf.appendSlice(self.allocator, ",\"created_at\":\"");
        try args_buf.appendSlice(self.allocator, created_at);
        try args_buf.appendSlice(self.allocator, "\",\"updated_at\":\"");
        try args_buf.appendSlice(self.allocator, created_at);
        try args_buf.appendSlice(self.allocator, "\"}");
        var r = try self.disp.dispatch(&ctx, "estimates", "create", args_buf.items);
        defer r.deinit();
    }

    /// Synthesise the broker payload jobs_handler.emitJobTransitioned
    /// produces, publish it, and drain the router queue via tick().
    fn publishJobTransitioned(
        self: *Fixture,
        job_id: []const u8,
        from: []const u8,
        to: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"id\":\"");
        try buf.appendSlice(self.allocator, job_id);
        try buf.appendSlice(self.allocator, "\",\"from\":\"");
        try buf.appendSlice(self.allocator, from);
        try buf.appendSlice(self.allocator, "\",\"to\":\"");
        try buf.appendSlice(self.allocator, to);
        try buf.appendSlice(self.allocator, "\",\"scheduled_at\":\"\",\"transitioned_at\":\"2026-05-17T09:00:00Z\"}");

        self.broker.publish(.{
            .type = "job.transitioned",
            .payload_json = buf.items,
        });
        self.router.tick();
    }

    fn publishRaw(self: *Fixture, event_type: []const u8, payload: []const u8) void {
        self.broker.publish(.{ .type = event_type, .payload_json = payload });
        self.router.tick();
    }

    /// Return the number of quotes on file for `job_id` and, when
    /// non-zero, the cost bounds of the first one.
    const QuoteProbe = struct {
        count: usize,
        cost_min: i64,
        cost_max: i64,
        status_is_draft: bool,
    };

    fn probeQuotes(self: *Fixture, job_id: []const u8) !QuoteProbe {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"job_id\":\"");
        try args_buf.appendSlice(self.allocator, job_id);
        try args_buf.appendSlice(self.allocator, "\"}");
        var r = try self.disp.dispatch(&ctx, "quotes", "find", args_buf.items);
        defer r.deinit();
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, r.payload, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return error.not_array;
        const items = parsed.value.array.items;
        if (items.len == 0) return .{ .count = 0, .cost_min = 0, .cost_max = 0, .status_is_draft = false };
        const o = items[0].object;
        const cmin = switch (o.get("cost_min").?) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => 0,
        };
        const cmax = switch (o.get("cost_max").?) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => 0,
        };
        const status = o.get("status").?.string;
        return .{
            .count = items.len,
            .cost_min = cmin,
            .cost_max = cmax,
            .status_is_draft = std.mem.eql(u8, status, "draft"),
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Happy path — accepted Estimate → qualified→quoted → draft Quote.
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: qualified→quoted seeds a draft quote from the accepted estimate" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-001", "qualified");
    try fx.createEstimate("est-001", "job-001", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-001", "qualified", "quoted");

    const probe = try fx.probeQuotes("job-001");
    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expectEqual(@as(i64, 5000), probe.cost_min);
    try std.testing.expectEqual(@as(i64, 20000), probe.cost_max);
    try std.testing.expect(probe.status_is_draft);
}

// Most-recent accepted estimate wins when several exist.
test "quote_seed: picks the most-recent accepted estimate" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-rev", "qualified");
    try fx.createEstimate("est-old", "job-rev", "accepted", 1000, 2000, "2026-05-01T09:00:00Z");
    try fx.createEstimate("est-new", "job-rev", "accepted", 7000, 9000, "2026-05-03T09:00:00Z");

    try fx.publishJobTransitioned("job-rev", "qualified", "quoted");

    const probe = try fx.probeQuotes("job-rev");
    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expectEqual(@as(i64, 7000), probe.cost_min);
    try std.testing.expectEqual(@as(i64, 9000), probe.cost_max);
}

// ─────────────────────────────────────────────────────────────────────
// No accepted Estimate → no quote (graceful no-op).
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: no accepted estimate is a graceful no-op" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-002", "qualified");
    try fx.createEstimate("est-002", "job-002", "pending", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-002", "qualified", "quoted");

    const probe = try fx.probeQuotes("job-002");
    try std.testing.expectEqual(@as(usize, 0), probe.count);
}

// ─────────────────────────────────────────────────────────────────────
// Idempotent — publishing the transition twice seeds exactly one quote.
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: double publish seeds exactly one quote" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-003", "qualified");
    try fx.createEstimate("est-003", "job-003", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-003", "qualified", "quoted");
    try fx.publishJobTransitioned("job-003", "qualified", "quoted");

    const probe = try fx.probeQuotes("job-003");
    try std.testing.expectEqual(@as(usize, 1), probe.count);
}

// ─────────────────────────────────────────────────────────────────────
// Non-qualified→quoted transitions are filtered in the callback —
// visited→quoted is a from-scratch operator quote, NOT a ROM
// carry-through; lead→qualified is an unrelated edge.
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: visited→quoted is ignored (no ROM carry-through)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-004", "qualified");
    try fx.createEstimate("est-004", "job-004", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-004", "visited", "quoted");
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const probe = try fx.probeQuotes("job-004");
    try std.testing.expectEqual(@as(usize, 0), probe.count);
}

test "quote_seed: lead→qualified is ignored" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-005", "qualified");
    try fx.createEstimate("est-005", "job-005", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-005", "lead", "qualified");
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const probe = try fx.probeQuotes("job-005");
    try std.testing.expectEqual(@as(usize, 0), probe.count);
}

// ─────────────────────────────────────────────────────────────────────
// Non-target event type ignored (only `job.transitioned`).
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: ignores non-job.transitioned events" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-006", "qualified");
    try fx.createEstimate("est-006", "job-006", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    fx.publishRaw(
        "visit.transitioned",
        "{\"id\":\"job-006\",\"from\":\"qualified\",\"to\":\"quoted\"}",
    );
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const probe = try fx.probeQuotes("job-006");
    try std.testing.expectEqual(@as(usize, 0), probe.count);
}

// ─────────────────────────────────────────────────────────────────────
// Gate disabled — constructed with enabled=false: callback is a no-op.
// ─────────────────────────────────────────────────────────────────────

test "quote_seed: gate disabled is a no-op" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, false);
    defer fx.deinit();

    try fx.createJob("job-007", "qualified");
    try fx.createEstimate("est-007", "job-007", "accepted", 5000, 20000, "2026-05-02T10:00:00Z");

    try fx.publishJobTransitioned("job-007", "qualified", "quoted");
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const probe = try fx.probeQuotes("job-007");
    try std.testing.expectEqual(@as(usize, 0), probe.count);
}

```
