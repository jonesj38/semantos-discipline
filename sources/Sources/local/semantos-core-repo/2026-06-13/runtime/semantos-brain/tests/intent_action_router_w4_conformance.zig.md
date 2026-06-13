---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/intent_action_router_w4_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.189559+00:00
---

# runtime/semantos-brain/tests/intent_action_router_w4_conformance.zig

```zig
// W4.1 — h_state ranking conformance tests for `intent_action_router.zig`.
//
// Wire Pask h_state into intent routing by preferring the most recently
// created/updated job when multiple jobs match the same name fragment.
// This is the TDD RED phase: these tests will fail until the GREEN
// implementation lands.
//
// Coverage:
//
//   • Two jobs match same name fragment → most recently created one wins
//   • Single match still works as before (no regression)
//   • Zero matches still returns NoMatch (no regression)
//   • Older job is NOT picked when newer job also matches
//   • When all matching jobs have the same timestamp, first match is
//     returned (deterministic tiebreak; no error)

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const jobs_handler_mod = @import("jobs_handler");
const helm_event_broker = @import("helm_event_broker");
const intent_action_router = @import("intent_action_router");
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

    /// Create a job with an explicit created_at timestamp for h_state ranking tests.
    fn createJobWithTimestamp(
        self: *Fixture,
        id: []const u8,
        customer_name: []const u8,
        state: []const u8,
        created_at: []const u8,
    ) !void {
        var ctx = self.rootCtx();
        var args_buf: std.ArrayList(u8) = .{};
        defer args_buf.deinit(self.allocator);
        try args_buf.appendSlice(self.allocator, "{\"id\":\"");
        try args_buf.appendSlice(self.allocator, id);
        try args_buf.appendSlice(self.allocator, "\",\"customer_name\":\"");
        try args_buf.appendSlice(self.allocator, customer_name);
        try args_buf.appendSlice(self.allocator, "\",\"state\":\"");
        try args_buf.appendSlice(self.allocator, state);
        try args_buf.appendSlice(self.allocator, "\",\"scheduled_at\":\"\",\"created_at\":\"");
        try args_buf.appendSlice(self.allocator, created_at);
        try args_buf.appendSlice(self.allocator, "\"}");
        var r = try self.disp.dispatch(&ctx, "jobs", "create", args_buf.items);
        defer r.deinit();
    }

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
// W4.1 core: two jobs match same name fragment — newer wins.
// ─────────────────────────────────────────────────────────────────────

test "W4.1: two jobs match same name fragment — most recently created one is transitioned" {
    // Scenario: operator has two "Wattle" jobs. The newer one (job-new)
    // was created more recently. The router should prefer it over the
    // older one (job-old) when disambiguating.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // Older job — created 2026-01-01.
    try fx.createJobWithTimestamp(
        "job-old",
        "Wattle Street Apartments",
        "qualified",
        "2026-01-01T10:00:00Z",
    );
    // Newer job — created 2026-05-01 (same name fragment "wattle").
    try fx.createJobWithTimestamp(
        "job-new",
        "Wattle Lane Electricals",
        "qualified",
        "2026-05-01T10:00:00Z",
    );

    try fx.publishIntentCell(
        "cell-w4-001",
        "quote",
        "quote $800 for the wattle job",
    );

    // The newer job must be transitioned.
    const new_state = try fx.currentState("job-new");
    defer allocator.free(new_state);
    try std.testing.expectEqualStrings("quoted", new_state);

    // The older job must NOT be touched.
    const old_state = try fx.currentState("job-old");
    defer allocator.free(old_state);
    try std.testing.expectEqualStrings("qualified", old_state);
}

// ─────────────────────────────────────────────────────────────────────
// W4.1 ordering: even when older job is inserted second, newer wins.
// ─────────────────────────────────────────────────────────────────────

test "W4.1: insertion order does not affect recency ranking" {
    // Insert the newer job first, then the older one.  The ranking
    // must still pick the job with the later created_at, not the one
    // that appears later in the store scan.
    //
    // "quote" is used (qualified → quoted is a valid skip-path FSM edge) so the
    // chosen job actually transitions and we can assert which one.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    // Newer job inserted first (earlier in the file / scan order).
    try fx.createJobWithTimestamp(
        "job-newer",
        "Parkside Plumbing",
        "qualified",
        "2026-04-15T08:00:00Z",
    );
    // Older job inserted second (later in the file / scan order).
    try fx.createJobWithTimestamp(
        "job-older",
        "Parkside Roofing",
        "qualified",
        "2026-02-10T08:00:00Z",
    );

    // "parkside" matches both jobs.  Newer job (job-newer) has the
    // later created_at and must be transitioned.
    try fx.publishIntentCell(
        "cell-w4-002",
        "quote",
        "quote the parkside job",
    );

    const newer_state = try fx.currentState("job-newer");
    defer allocator.free(newer_state);
    try std.testing.expectEqualStrings("quoted", newer_state);

    const older_state = try fx.currentState("job-older");
    defer allocator.free(older_state);
    try std.testing.expectEqualStrings("qualified", older_state);
}

// ─────────────────────────────────────────────────────────────────────
// W4.1 regression: single match still works (no AmbiguousMatch fired).
// ─────────────────────────────────────────────────────────────────────

test "W4.1: single match still transitions correctly (no regression)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJobWithTimestamp(
        "job-unique",
        "Harbourside Electrical",
        "qualified",
        "2026-03-20T09:00:00Z",
    );
    // A second job that does NOT share the "harbourside" token.
    try fx.createJobWithTimestamp(
        "job-other",
        "Northbridge Plumbing",
        "qualified",
        "2026-04-01T09:00:00Z",
    );

    try fx.publishIntentCell(
        "cell-w4-003",
        "quote",
        "quote the harbourside electrical job",
    );

    const state = try fx.currentState("job-unique");
    defer allocator.free(state);
    try std.testing.expectEqualStrings("quoted", state);

    const other = try fx.currentState("job-other");
    defer allocator.free(other);
    try std.testing.expectEqualStrings("qualified", other);
}

// ─────────────────────────────────────────────────────────────────────
// W4.1 regression: zero matches still returns no transition (no crash).
// ─────────────────────────────────────────────────────────────────────

test "W4.1: zero matches produces no transition (no regression)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJobWithTimestamp(
        "job-001",
        "Wattle Street Apartments",
        "qualified",
        "2026-05-01T10:00:00Z",
    );

    try fx.publishIntentCell(
        "cell-w4-004",
        "quote",
        "quote the moonbase alpha contract",
    );

    const state = try fx.currentState("job-001");
    defer allocator.free(state);
    try std.testing.expectEqualStrings("qualified", state);
}

// ─────────────────────────────────────────────────────────────────────
// W4.1: same-timestamp tiebreak — deterministic (no error).
// ─────────────────────────────────────────────────────────────────────

test "W4.1: same-timestamp tiebreak is deterministic (picks first match, no error)" {
    // When two matching jobs have identical created_at, the router must
    // still pick exactly one (first in store order) and not crash or
    // return AmbiguousMatch.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    const same_ts = "2026-03-01T12:00:00Z";
    try fx.createJobWithTimestamp("job-alpha", "Riverside Roofing Alpha", "qualified", same_ts);
    try fx.createJobWithTimestamp("job-beta", "Riverside Roofing Beta", "qualified", same_ts);

    // Both contain "riverside" — same timestamp → tiebreak picks one.
    // We only assert that EXACTLY ONE is transitioned (not an error).
    try fx.publishIntentCell(
        "cell-w4-005",
        "quote",
        "quote the riverside roofing job",
    );

    const alpha = try fx.currentState("job-alpha");
    defer allocator.free(alpha);
    const beta = try fx.currentState("job-beta");
    defer allocator.free(beta);

    // Exactly one must be "quoted" (the tiebreak winner).
    const alpha_quoted = std.mem.eql(u8, alpha, "quoted");
    const beta_quoted = std.mem.eql(u8, beta, "quoted");
    try std.testing.expect(alpha_quoted or beta_quoted);
    try std.testing.expect(!(alpha_quoted and beta_quoted));
}

// ─────────────────────────────────────────────────────────────────────
// W4.1: three candidates — the newest of three wins.
// ─────────────────────────────────────────────────────────────────────

test "W4.1: three matching jobs — most recently created one wins" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator, true);
    defer fx.deinit();

    try fx.createJobWithTimestamp("job-t1", "Bayside Repairs Ltd",   "qualified", "2026-01-10T00:00:00Z");
    try fx.createJobWithTimestamp("job-t2", "Bayside Electrical Co", "qualified", "2026-03-15T00:00:00Z");
    try fx.createJobWithTimestamp("job-t3", "Bayside Plumbing Corp", "qualified", "2026-05-05T00:00:00Z");

    try fx.publishIntentCell(
        "cell-w4-006",
        "quote",
        "quote the bayside job",
    );

    // job-t3 has the latest created_at; it must be transitioned.
    const t3 = try fx.currentState("job-t3");
    defer allocator.free(t3);
    try std.testing.expectEqualStrings("quoted", t3);

    const t1 = try fx.currentState("job-t1");
    defer allocator.free(t1);
    try std.testing.expectEqualStrings("qualified", t1);

    const t2 = try fx.currentState("job-t2");
    defer allocator.free(t2);
    try std.testing.expectEqualStrings("qualified", t2);
}

```
