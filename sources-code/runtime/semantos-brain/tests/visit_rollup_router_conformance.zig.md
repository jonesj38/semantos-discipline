---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/visit_rollup_router_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.210933+00:00
---

# runtime/semantos-brain/tests/visit_rollup_router_conformance.zig

```zig
// Tier 3 follow-up — Conformance suite for `visit_rollup_router.zig`.
//
// Mirrors intent_action_router_conformance.zig's broker→dispatcher
// fixture. The router subscribes to `visit.transitioned`; on
// to=="completed" it dispatches jobs.transition rolling the parent
// job to `visited`. Coverage:
//
//   • happy path  — job in visit_scheduled → completed visit → visited
//   • FSM-rejected — job in `lead` → completed visit → job unchanged
//                     (visited's only incoming edge is
//                      visit_scheduled→visited; dispatcher returns a
//                      typed not_reachable body; router audit-skips)
//   • idempotent  — job already `visited` → completed visit → visited
//                     (already_in_state success body, recorded ok)
//   • non-completed visit transition ignored (callback filter; never
//     enqueued)
//   • non-target event type ignored
//   • missing job_id skips cleanly (no crash, no transition)
//   • gate disabled → no-op

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const jobs_handler_mod = @import("jobs_handler");
const helm_event_broker = @import("helm_event_broker");
const visit_rollup_router = @import("visit_rollup_router");
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
    audit_path: []u8,
    audit: audit_log.AuditLog,
    broker: helm_event_broker.Broker,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    store: jobs_store_fs.JobsStore,
    handler: jobs_handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    router: *visit_rollup_router.Router,

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
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        self.router = try visit_rollup_router.Router.init(
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

    /// Synthesise the broker payload visits_handler.emitVisitTransitioned
    /// produces, publish it, and drain the router queue via tick().
    fn publishVisitTransitioned(
        self: *Fixture,
        visit_id: []const u8,
        job_id: []const u8,
        from: []const u8,
        to: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"id\":\"");
        try buf.appendSlice(self.allocator, visit_id);
        try buf.appendSlice(self.allocator, "\",\"job_id\":\"");
        try buf.appendSlice(self.allocator, job_id);
        try buf.appendSlice(self.allocator, "\",\"from\":\"");
        try buf.appendSlice(self.allocator, from);
        try buf.appendSlice(self.allocator, "\",\"to\":\"");
        try buf.appendSlice(self.allocator, to);
        try buf.appendSlice(self.allocator, "\",\"transitioned_at\":\"2026-05-17T09:00:00Z\"}");

        self.broker.publish(.{
            .type = "visit.transitioned",
            .payload_json = buf.items,
        });
        self.router.tick();
    }

    fn publishRaw(self: *Fixture, event_type: []const u8, payload: []const u8) void {
        self.broker.publish(.{ .type = event_type, .payload_json = payload });
        self.router.tick();
    }

    fn currentState(self: *Fixture, id: []const u8) ![]u8 {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"id\":\"");
        try args_buf.appendSlice(self.allocator, id);
        try args_buf.appendSlice(self.allocator, "\"}");
        var r = try self.disp.dispatch(&ctx, "jobs", "find_by_id", args_buf.items);
        defer r.deinit();
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, r.payload, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.not_object;
        const v = parsed.value.object.get("state") orelse return error.missing_state;
        if (v != .string) return error.not_string;
        return try self.allocator.dupe(u8, v.string);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Happy path — a completed site visit rolls its parent job to visited.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: completed visit rolls a visit_scheduled job to visited" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-001", "visit_scheduled");

    try fx.publishVisitTransitioned("visit-001", "job-001", "in_progress", "completed");

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("visited", after);
}

// ─────────────────────────────────────────────────────────────────────
// FSM-rejected — `visited`'s only incoming edge is visit_scheduled →
// visited.  A completed visit whose parent job is in some other state
// must NOT regress/leapfrog it; the router audit-skips.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: completed visit on a lead-state job is a graceful no-op" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-lead", "lead");

    try fx.publishVisitTransitioned("visit-002", "job-lead", "in_progress", "completed");

    const after = try fx.currentState("job-lead");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Idempotent — job already `visited`.  jobs.transition returns the
// already_in_state success body; the job stays visited; no crash.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: completed visit on an already-visited job stays visited" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-v", "visited");

    try fx.publishVisitTransitioned("visit-003", "job-v", "in_progress", "completed");

    const after = try fx.currentState("job-v");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("visited", after);
}

// ─────────────────────────────────────────────────────────────────────
// Non-completed visit transitions are filtered in the callback —
// scheduled→in_progress must never enqueue or transition the job.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: non-completed visit transition is ignored" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-002", "visit_scheduled");

    try fx.publishVisitTransitioned("visit-004", "job-002", "scheduled", "in_progress");
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const after = try fx.currentState("job-002");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("visit_scheduled", after);
}

// ─────────────────────────────────────────────────────────────────────
// Non-target event type ignored (the router only cares about
// `visit.transitioned`).
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: ignores non-visit.transitioned events" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-003", "visit_scheduled");

    fx.publishRaw(
        "job.transitioned",
        "{\"id\":\"job-003\",\"job_id\":\"job-003\",\"to\":\"completed\"}",
    );
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const after = try fx.currentState("job-003");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("visit_scheduled", after);
}

// ─────────────────────────────────────────────────────────────────────
// Missing job_id — completed visit with no parent link skips cleanly.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: completed visit missing job_id skips without error" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    fx.publishRaw(
        "visit.transitioned",
        "{\"id\":\"visit-x\",\"from\":\"in_progress\",\"to\":\"completed\"}",
    );
    // No job_id → enqueueFromEvent records a skip and returns; nothing
    // queued, nothing dispatched, no panic.
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());
}

// ─────────────────────────────────────────────────────────────────────
// Gate disabled — constructed with enabled=false: callback is a no-op.
// ─────────────────────────────────────────────────────────────────────

test "visit_rollup: gate disabled is a no-op" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, false);
    defer fx.deinit();

    try fx.createJob("job-004", "visit_scheduled");

    try fx.publishVisitTransitioned("visit-005", "job-004", "in_progress", "completed");
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());

    const after = try fx.currentState("job-004");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("visit_scheduled", after);
}

```
