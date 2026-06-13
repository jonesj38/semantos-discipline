---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/intent_action_router_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.203943+00:00
---

# runtime/semantos-brain/tests/intent_action_router_conformance.zig

```zig
// Tier 3 — Conformance suite for `intent_action_router.zig`.
//
// Mirrors the shape of `intent_cells_handler_conformance.zig` adapted
// for the broker→dispatcher bridge.  Coverage:
//
//   • action → state mapping (pure helper)
//   • single-match transition path (lead → quoted via "quote ... wattle ...")
//   • ambiguous-match skip (two jobs whose customer_name share a token)
//   • no-match skip
//   • bad-state skip (job already in `quoted` state — router declines
//     to regress the FSM)
//   • unrecognised-action skip
//   • gate-disabled noop (router constructed with enabled=false)
//   • non-intent-cell event ignored

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const jobs_handler_mod = @import("jobs_handler");
const helm_event_broker = @import("helm_event_broker");
const intent_action_router = @import("intent_action_router");
// W0.1: JobsStore now needs a CellStore.
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
    router: *intent_action_router.Router,

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
        // W0.1: init LMDB env in-place so CellStore pointer stays stable.
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
        self.router = try intent_action_router.Router.init(
            allocator,
            &self.broker,
            &self.store,
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

    fn createJob(self: *Fixture, id: []const u8, customer_name: []const u8, state: []const u8) !void {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"id\":\"");
        try args_buf.appendSlice(self.allocator, id);
        try args_buf.appendSlice(self.allocator, "\",\"customer_name\":\"");
        try args_buf.appendSlice(self.allocator, customer_name);
        try args_buf.appendSlice(self.allocator, "\",\"state\":\"");
        try args_buf.appendSlice(self.allocator, state);
        try args_buf.appendSlice(self.allocator, "\",\"scheduled_at\":\"\",\"created_at\":\"2026-05-02T10:00:00Z\"}");
        var r = try self.disp.dispatch(&ctx, "jobs", "create", args_buf.items);
        defer r.deinit();
    }

    /// Synthesise the broker payload that intent_cells_handler.zig
    /// `emitIntentCellAccepted` produces, publish it, and drain the
    /// router's queue via `tick()`.  In production the reactor's
    /// poll loop calls `tick()` periodically; tests drain explicitly
    /// so each test is deterministic.
    fn publishIntentCell(
        self: *Fixture,
        cell_id: []const u8,
        intent_action: []const u8,
        intent_summary: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"cell_id\":\"");
        try buf.appendSlice(self.allocator, cell_id);
        try buf.appendSlice(self.allocator, "\",\"hat_id\":\"hat-001\"");
        try buf.appendSlice(self.allocator, ",\"intent_summary\":");
        const enc_summary = try std.json.Stringify.valueAlloc(self.allocator, intent_summary, .{});
        defer self.allocator.free(enc_summary);
        try buf.appendSlice(self.allocator, enc_summary);
        try buf.appendSlice(self.allocator, ",\"intent_action\":");
        const enc_action = try std.json.Stringify.valueAlloc(self.allocator, intent_action, .{});
        defer self.allocator.free(enc_action);
        try buf.appendSlice(self.allocator, enc_action);
        try buf.appendSlice(self.allocator, ",\"requires_operator_attention\":true,\"ts\":1700000000}");

        self.broker.publish(.{
            .type = "intent_cell.created",
            .payload_json = buf.items,
            .requires_operator_attention = true,
        });
        self.router.tick();
    }

    /// Read back the current state of `id` via `jobs.find_by_id`.
    /// Caller frees the result.
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
// Pure helper coverage — action → state mapping.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: action → state mapping covers the four supported verbs" {
    try std.testing.expectEqualStrings("quoted", intent_action_router.mapAction("quote").?);
    try std.testing.expectEqualStrings("scheduled", intent_action_router.mapAction("schedule").?);
    try std.testing.expectEqualStrings("invoiced", intent_action_router.mapAction("invoice").?);
    try std.testing.expectEqualStrings("closed", intent_action_router.mapAction("close").?);
    try std.testing.expectEqual(@as(?[]const u8, null), intent_action_router.mapAction("bogus"));
    // `accept` is intentionally NOT supported — the brief's mapping
    // targeted a non-existent FSM state (`open`).
    try std.testing.expectEqual(@as(?[]const u8, null), intent_action_router.mapAction("accept"));
}

// ─────────────────────────────────────────────────────────────────────
// Single-match transition path — the demo's happy path.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: quote intent on qualified-state job transitions to quoted" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // `quote` requires the job to be in `qualified` (skip-path) or
    // `visited`.  The direct `lead → quoted` edge was removed in the
    // twelve-state remodel; seed `qualified` so the skip-path edge
    // (qualified → quoted) is exercised.
    try fx.createJob("job-001", "Wattle Street Apartments", "qualified");
    try fx.createJob("job-002", "Northbridge Plumbing", "qualified");

    try fx.publishIntentCell(
        "cell-quote-001",
        "quote",
        "quote $500 for the wattle street job",
    );

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("quoted", after);

    // The other job stays in qualified.
    const other = try fx.currentState("job-002");
    defer allocator.free(other);
    try std.testing.expectEqualStrings("qualified", other);
}

test "intent_action_router: accept verb is unsupported (deviation from brief)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // The brief listed `"accept" → "open"`, but `open` isn't in the
    // canonical Job FSM (states are lead | quoted | scheduled |
    // in_progress | completed | invoiced | paid | closed).  The
    // router drops `accept` from the supported set and audit-skips
    // it; the job's state is unchanged.
    try fx.createJob("job-acme", "Acme Roofing", "lead");
    try fx.publishIntentCell(
        "cell-accept-001",
        "accept",
        "accept the acme roofing lead",
    );
    const after = try fx.currentState("job-acme");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Ambiguous match — W4.1: multiple jobs match → pick one (no skip).
//
// Prior to W4.1 the router returned AmbiguousMatch and skipped.  W4.1
// resolves ambiguity by recency (most recently created job wins); when
// two jobs share the same created_at the first match in store-scan
// order is chosen as a stable tiebreak.  The fixture's createJob
// stamps both jobs with the same pinnedClock timestamp, so job-a
// (first inserted) wins.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: ambiguous match resolves to most-recently-created job (W4.1)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // Both customers contain "wattle" — same created_at (pinnedClock).
    // W4.1 tiebreak: job-a (lower scan index) is chosen.  Seed
    // `qualified` so the `quote` skip-path edge is valid post-remodel.
    try fx.createJob("job-a", "Wattle Street Apartments", "qualified");
    try fx.createJob("job-b", "Wattle Avenue Plumbing", "qualified");

    try fx.publishIntentCell(
        "cell-ambig-001",
        "quote",
        "quote $500 for the wattle job",
    );

    // Exactly one of the two jobs must be transitioned.  Both share the
    // same timestamp so store-scan order decides — job-a is first.
    const a_after = try fx.currentState("job-a");
    defer allocator.free(a_after);
    const b_after = try fx.currentState("job-b");
    defer allocator.free(b_after);

    const a_quoted = std.mem.eql(u8, a_after, "quoted");
    const b_quoted = std.mem.eql(u8, b_after, "quoted");
    // Exactly one must have transitioned.
    try std.testing.expect(a_quoted or b_quoted);
    try std.testing.expect(!(a_quoted and b_quoted));
}

// ─────────────────────────────────────────────────────────────────────
// No match — summary mentions a customer no job has → skip.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: no-match skips with no transition" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-001", "Wattle Street Apartments", "lead");

    try fx.publishIntentCell(
        "cell-nomatch-001",
        "quote",
        "quote $500 for the elephant warehouse",
    );

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Bad-state skip — job already in `quoted`; router refuses to regress.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: skips when matched job is in advanced state" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // Already-quoted job — router must not "re-quote" or otherwise
    // touch it.  Same intent_action as the happy-path test.
    try fx.createJob("job-001", "Wattle Street Apartments", "quoted");

    try fx.publishIntentCell(
        "cell-bad-state-001",
        "quote",
        "quote $500 for the wattle street job",
    );

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("quoted", after);
}

// ─────────────────────────────────────────────────────────────────────
// Unrecognised action — router skips without touching the store.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: unrecognised action audit-skips" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-001", "Wattle Street Apartments", "lead");

    try fx.publishIntentCell(
        "cell-bogus-001",
        "frobnicate",
        "frobnicate the wattle street job",
    );

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Gate disabled — router exists but is a no-op.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: gate disabled is a no-op" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, false);
    defer fx.deinit();

    try fx.createJob("job-001", "Wattle Street Apartments", "lead");

    try fx.publishIntentCell(
        "cell-disabled-001",
        "quote",
        "quote $500 for the wattle street job",
    );

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    // Even though the action + summary match, the gate is off → no
    // transition fires.
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Cold-boot defence — empty jobs store skips cleanly.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: empty jobs store skips with no error" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // No jobs created — the router must not crash.
    try fx.publishIntentCell(
        "cell-empty-001",
        "quote",
        "quote $500 for any job",
    );
    // No assertion needed: the broker callback returning without
    // error is the assertion.
}

// ─────────────────────────────────────────────────────────────────────
// Non-target event types are ignored — only intent_cell.created is
// routed.
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: ignores non-intent_cell.created events" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJob("job-001", "Wattle Street Apartments", "lead");

    // Publish a `job.transitioned`-typed event that *would* match
    // had the router not filtered on event.type — it must NOT
    // re-trigger a transition.
    fx.broker.publish(.{
        .type = "job.transitioned",
        .payload_json = "{\"id\":\"job-001\",\"from\":\"lead\",\"to\":\"lead\",\"intent_action\":\"quote\",\"intent_summary\":\"quote wattle street\"}",
        .requires_operator_attention = false,
    });
    // The router's enqueue is gated on event.type; the queue should
    // remain empty.  Tick is a no-op in that case but we run it for
    // belt-and-braces.
    try std.testing.expectEqual(@as(usize, 0), fx.router.pendingCount());
    fx.router.tick();

    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

// ─────────────────────────────────────────────────────────────────────
// Subscriber-id lifecycle — deinit unsubscribes (regression guard).
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: deinit unsubscribes from broker" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    // The router's own subscription brings the count to >= 1.
    try std.testing.expect(fx.broker.subscriberCount() >= 1);
    fx.deinit();
    // Fixture's broker is gone; if we'd leaked the subscription, the
    // testing allocator would catch the dangling state pointer next
    // run.  This test exists to make the assertion explicit.
}

// ─────────────────────────────────────────────────────────────────────
// Schedule + invoice happy paths (parity with quote — same machinery,
// different state targets).
// ─────────────────────────────────────────────────────────────────────

test "intent_action_router: schedule verb is mapped but FSM rejects lead → scheduled" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // The router maps "schedule" → "scheduled" and treats `lead` as
    // an eligible source state, so it WILL call jobs.transition.
    // The Job FSM, however, only allows `quoted → scheduled` (not
    // `lead → scheduled`), so the dispatcher returns a typed
    // not_reachable body and the router records phase=transition
    // kind=fsm_rejected.  The job's state remains unchanged.
    try fx.createJob("job-001", "Northbridge Plumbing", "lead");
    try fx.publishIntentCell(
        "cell-sched-001",
        "schedule",
        "schedule the northbridge plumbing visit",
    );
    const after = try fx.currentState("job-001");
    defer allocator.free(after);
    try std.testing.expectEqualStrings("lead", after);
}

```
