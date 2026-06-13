---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/visits_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.203072+00:00
---

# runtime/semantos-brain/tests/visits_handler_conformance.zig

```zig
// D-O4.followup-2 — see
// docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (Visit FSM table) §O5
//                                                (helm visits view).
//
// Conformance suite for `resources/visits_handler.zig`.  Mirrors the
// shape of `jobs_handler_conformance.zig` post-#311: dispatcher →
// ResourceHandler → VisitsStore for the four spec'd commands plus the
// FK validation + cap-gating + idempotent-recreate paths required by
// the brief, plus the cross-language parity oracle driven from the
// canonical visit_fsm.json vector.
//
// What this closes:
//
//   • Both helms (loom-svelte VisitList.svelte + oddjobz-mobile
//     visits_repository.dart) prefer the JSON-array branch when the
//     REPL response starts with `[`.  This suite asserts the bytes the
//     dispatcher returns satisfy that branch.
//
//   • FK validation: `visits.create` with a `job_id` that's not in the
//     jobs store returns `{error: "job_not_found", job_id}` (200, NOT
//     a dispatcher error).
//
//   • Cap-gating: read commands require `cap.oddjobz.read_visits`;
//     create requires `cap.oddjobz.write_visit`; transition requires
//     `cap.oddjobz.read_visits` at the dispatcher gate (per-FSM-row
//     caps are checked inside the handler — every Visit row is ungated
//     today but the shape mirrors jobs.transition).
//
//   • Cross-language parity: the canonical visit_fsm.json oracle
//     drives every TS-side transition through Zig and each output's
//     `status` matches the TS-side `expectedOutput.status`.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const visits_store_fs = @import("visits_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const visits_handler_mod = @import("visits_handler");
const visit_fsm = @import("visit_fsm");
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

// ─────────────────────────────────────────────────────────────────────
// Test fixture — heap-allocated so the dispatcher's pointer to
// audit_log + the handler's pointer to VisitsStore + JobsStore are
// address-stable.
// ─────────────────────────────────────────────────────────────────────

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
    visits_store: visits_store_fs.VisitsStore,
    jobs_store: jobs_store_fs.JobsStore,
    handler: visits_handler_mod.Handler,
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

        // Initialize LMDB env and cell store in-place so pointers remain stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.visits_store = try visits_store_fs.VisitsStore.init(allocator, &self.cs, pinnedClock);
        self.jobs_store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = visits_handler_mod.Handler.init(allocator, &self.visits_store, &self.jobs_store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.visits_store.deinit();
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
            .state = "scheduled",
            .scheduled_at = "2026-05-15T09:00:00Z",
            .created_at = "2026-05-01T00:00:00Z",
        });
    }

    /// Seed a Visit at the given FSM state via the dispatcher's
    /// `visits.create` cmd — exercises the same audit-pair path the
    /// rest of the suite asserts on.
    fn seedVisitAt(
        self: *Fixture,
        ctx: *dispatcher.DispatchContext,
        id: []const u8,
        job_id: []const u8,
        status: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(std.testing.allocator);
        try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
        try buf.appendSlice(std.testing.allocator, id);
        try buf.appendSlice(std.testing.allocator, "\",\"job_id\":\"");
        try buf.appendSlice(std.testing.allocator, job_id);
        try buf.appendSlice(std.testing.allocator, "\",\"visit_type\":\"scheduled_work\",\"status\":\"");
        try buf.appendSlice(std.testing.allocator, status);
        try buf.appendSlice(std.testing.allocator, "\",\"created_at\":\"2026-05-01T00:00:00Z\",\"updated_at\":\"2026-05-01T00:00:00Z\"}");
        var r = try self.disp.dispatch(ctx, "visits", "create", buf.items);
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

test "D-O4.followup-2 visits: create → find returns the visit (JSON shape)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var create_r = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-001","job_id":"j-001","visit_type":"scheduled_work","notes":"first inspection"}
    );
    defer create_r.deinit();
    const status = try jsonString(allocator, create_r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);

    var find_r = try fx.disp.dispatch(&ctx, "visits", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_r.payload));
}

test "D-O4.followup-2 visits: find_by_job_id filters on parent job" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    try fx.seedJob("j-A");
    try fx.seedJob("j-B");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-A1", "j-A", "scheduled");
    try fx.seedVisitAt(&ctx, "v-A2", "j-A", "scheduled");
    try fx.seedVisitAt(&ctx, "v-B1", "j-B", "scheduled");

    var r = try fx.disp.dispatch(&ctx, "visits", "find",
        \\{"job_id":"j-A"}
    );
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayLen(allocator, r.payload));
}

test "D-O4.followup-2 visits: find_by_id on missing returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "visits", "find_by_id",
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

test "D-O4.followup-2 visits: create with non-existent job_id returns job_not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-orphan","job_id":"j-not-real","visit_type":"inspection"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("job_not_found", err_kind);

    // Visit was NOT persisted.
    var find_r = try fx.disp.dispatch(&ctx, "visits", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, find_r.payload));
}

// ─────────────────────────────────────────────────────────────────────
// Idempotent re-create
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits: re-create with same id + same contents returns already_exists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    const args =
        \\{"id":"v-idem","job_id":"j-001","visit_type":"inspection","status":"scheduled","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    ;
    var first = try fx.disp.dispatch(&ctx, "visits", "create", args);
    defer first.deinit();
    var second = try fx.disp.dispatch(&ctx, "visits", "create", args);
    defer second.deinit();
    const status = try jsonString(allocator, second.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("already_exists", status);
}

test "D-O4.followup-2 visits: re-create with different contents returns typed handler error" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var first = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-conflict","job_id":"j-001","visit_type":"inspection","status":"scheduled","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    );
    first.deinit();
    // Differs on visit_type.
    try std.testing.expectError(visits_handler_mod.HandlerError.visit_id_in_use_with_different_contents, fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-conflict","job_id":"j-001","visit_type":"return_visit","status":"scheduled","created_at":"2026-05-01T00:00:00Z","updated_at":"2026-05-01T00:00:00Z"}
    ));
}

// ─────────────────────────────────────────────────────────────────────
// Cap-gating
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits: bearer without cap.oddjobz.read_visits is denied for find" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "visits", "find", "{}"));
}

test "D-O4.followup-2 visits: bearer with cap.oddjobz.read_visits can find but not create" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.read_visits"});

    var ok = try fx.disp.dispatch(&ctx, "visits", "find", "{}");
    ok.deinit();
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-001","job_id":"j-001","visit_type":"inspection"}
    ));
}

test "D-O4.followup-2 visits: bearer with cap.oddjobz.write_visit can create but not read" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.write_visit"});

    var ok = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-001","job_id":"j-001","visit_type":"inspection"}
    );
    ok.deinit();
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "visits", "find", "{}"));
}

// ─────────────────────────────────────────────────────────────────────
// FSM transitions — happy paths
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits.transition: scheduled → in_progress (service)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-tx-1", "j-001", "scheduled");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-tx-1","to_state":"in_progress","principal_kind":"service"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("in_progress", status);

    // actual_start is server-stamped on scheduled→in_progress.
    const actual_start = try jsonString(allocator, r.payload, "actual_start");
    defer allocator.free(actual_start);
    try std.testing.expect(actual_start.len > 0);
}

test "D-O4.followup-2 visits.transition: in_progress → completed stamps outcome" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-tx-2", "j-001", "in_progress");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-tx-2","to_state":"completed","principal_kind":"operator"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("completed", status);

    const outcome = try jsonString(allocator, r.payload, "outcome");
    defer allocator.free(outcome);
    try std.testing.expectEqualStrings("completed", outcome);
}

test "D-O4.followup-2 visits.transition: scheduled → cancelled stamps cancelled outcome" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-tx-3", "j-001", "scheduled");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-tx-3","to_state":"cancelled","principal_kind":"operator"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("cancelled", status);
    const outcome = try jsonString(allocator, r.payload, "outcome");
    defer allocator.free(outcome);
    try std.testing.expectEqualStrings("cancelled", outcome);
}

test "D-O4.followup-2 visits.transition: in_progress → cancelled (operator)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-tx-4", "j-001", "in_progress");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-tx-4","to_state":"cancelled","principal_kind":"operator"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("cancelled", status);
}

// ─────────────────────────────────────────────────────────────────────
// FSM transitions — typed errors
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits.transition: not-reachable jump returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-nr", "j-001", "scheduled");

    // scheduled → completed is not in the §O4 Visit table.
    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-nr","to_state":"completed","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_reachable", err_kind);
}

test "D-O4.followup-2 visits.transition: wrong principal returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-wp", "j-001", "scheduled");

    // scheduled → in_progress is service-only.
    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-wp","to_state":"in_progress","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("wrong_principal", err_kind);
}

test "D-O4.followup-2 visits.transition: unknown to_state returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-uk", "j-001", "scheduled");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-uk","to_state":"PAUSED","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("unknown_state", err_kind);
}

test "D-O4.followup-2 visits.transition: not_found id returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"never-existed","to_state":"in_progress","principal_kind":"service"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

test "D-O4.followup-2 visits.transition: idempotent already_in_state" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-idem", "j-001", "scheduled");

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-idem","to_state":"scheduled","principal_kind":"service"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("already_in_state", status);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, r.payload, .{});
    defer parsed.deinit();
    const visit_obj = parsed.value.object.get("visit").?.object;
    try std.testing.expectEqualStrings("v-idem", visit_obj.get("id").?.string);
    try std.testing.expectEqualStrings("scheduled", visit_obj.get("status").?.string);
}

// ─────────────────────────────────────────────────────────────────────
// Cross-language parity oracle — visit_fsm.json
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits.transition: cross-language parity oracle" {
    // Load cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json
    // and drive every transition through the Zig dispatcher.  The TS-
    // side `expectedOutput.status` must equal the Zig-side response's
    // `status` for each row.  This is the load-bearing correctness
    // proof that the Semantos Brain-side FSM port matches the TS canon.
    const allocator = std.testing.allocator;

    const vector_path = "../../cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json";
    const f = try std.fs.cwd().openFile(vector_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed.deinit();

    const transitions = parsed.value.object.get("transitions").?.array;
    // The canonical oracle has at least four LINEAR transitions.
    try std.testing.expect(transitions.items.len >= 4);

    // Each row of the oracle is independent (the canon's input is the
    // pre-state cell shape, NOT a single visit driven through the
    // whole FSM).  Build a fresh fixture per row + seed at the row's
    // `from` state so the test exercises every (from, to) pair.
    for (transitions.items) |t| {
        var fx = try Fixture.init(allocator);
        defer fx.deinit();
        try fx.seedJob("j-parity");
        var ctx = rootCtx();

        const row = t.object;
        const from_state = row.get("from").?.string;
        const to_state = row.get("to").?.string;
        const expected_status = row.get("expectedOutput").?.object.get("status").?.string;
        const principal = row.get("principalKinds").?.array.items[0].string;
        const cap_v = row.get("capRequired").?;
        const visit_id = row.get("input").?.object.get("visitId").?.string;

        try fx.seedVisitAt(&ctx, visit_id, "j-parity", from_state);

        var args: std.ArrayList(u8) = .{};
        defer args.deinit(allocator);
        try args.appendSlice(allocator, "{\"id\":\"");
        try args.appendSlice(allocator, visit_id);
        try args.appendSlice(allocator, "\",\"to_state\":\"");
        try args.appendSlice(allocator, to_state);
        try args.appendSlice(allocator, "\",\"principal_kind\":\"");
        try args.appendSlice(allocator, principal);
        try args.append(allocator, '"');
        if (cap_v == .string) {
            try args.appendSlice(allocator, ",\"presented_cap\":\"");
            try args.appendSlice(allocator, cap_v.string);
            try args.append(allocator, '"');
        }
        try args.append(allocator, '}');

        var r = try fx.disp.dispatch(&ctx, "visits", "transition", args.items);
        defer r.deinit();

        const got_status = try jsonString(allocator, r.payload, "status");
        defer allocator.free(got_status);
        // The brain-side response field is `status`; the TS-side
        // `expectedOutput.status` is the canonical name.  Equality
        // across them IS the parity proof.
        try std.testing.expectEqualStrings(expected_status, got_status);
    }
}

// ─────────────────────────────────────────────────────────────────────
// Audit-pair invariant
// ─────────────────────────────────────────────────────────────────────

test "D-O4.followup-2 visits: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-001");
    var ctx = rootCtx();

    var r1 = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-audit","job_id":"j-001","visit_type":"inspection"}
    );
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "visits", "find", "{}");
    r2.deinit();

    // Read the audit log and count phase=start / phase=end occurrences.
    // Match dispatcher emit shape: `op="visits.<cmd>"`.
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
        const matches_create = std.mem.indexOf(u8, line, "\"op\":\"visits.create\"") != null;
        const matches_find = std.mem.indexOf(u8, line, "\"op\":\"visits.find\"") != null;
        if (!matches_create and !matches_find) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    // Two dispatches → two pairs.
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// Silence the unused-import warning for visit_fsm — we exercise it
// through the dispatcher path above, but keeping the explicit @import
// here means this conformance suite reads as a peer of the FSM module.
comptime {
    _ = visit_fsm.VISIT_FSM_STATES;
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-4 followup-emitters — broker emit assertions for
// visits.create + visits.transition.  Mirrors the jobs.transition
// emit-test in jobs_handler_conformance.zig.
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
    visits_store: visits_store_fs.VisitsStore,
    jobs_store: jobs_store_fs.JobsStore,
    handler: visits_handler_mod.Handler,
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

        // Initialize LMDB env and cell store in-place so pointers remain stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();
        self.broker = helm_event_broker.Broker.init(allocator);

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.visits_store = try visits_store_fs.VisitsStore.init(allocator, &self.cs, pinnedClock);
        self.jobs_store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = visits_handler_mod.Handler.initWithBroker(
            allocator,
            &self.visits_store,
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
        self.visits_store.deinit();
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
            .state = "scheduled",
            .scheduled_at = "2026-05-15T09:00:00Z",
            .created_at = "2026-05-01T00:00:00Z",
        });
    }

    fn seedVisitAt(
        self: *BrokerFixture,
        ctx: *dispatcher.DispatchContext,
        id: []const u8,
        job_id: []const u8,
        status: []const u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(std.testing.allocator);
        try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
        try buf.appendSlice(std.testing.allocator, id);
        try buf.appendSlice(std.testing.allocator, "\",\"job_id\":\"");
        try buf.appendSlice(std.testing.allocator, job_id);
        try buf.appendSlice(std.testing.allocator, "\",\"visit_type\":\"scheduled_work\",\"status\":\"");
        try buf.appendSlice(std.testing.allocator, status);
        try buf.appendSlice(std.testing.allocator, "\",\"created_at\":\"2026-05-01T00:00:00Z\",\"updated_at\":\"2026-05-01T00:00:00Z\"}");
        var r = try self.disp.dispatch(ctx, "visits", "create", buf.items);
        r.deinit();
    }
};

test "D-O5.followup-4 visits.create publishes visit.created to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-pub");

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "visits", "create",
        \\{"id":"v-pub","job_id":"j-pub","visit_type":"scheduled_work","status":"scheduled","created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("visit.created", sink.types.items[0]);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"v-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"job_id\":\"j-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"visit_type\":\"scheduled_work\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"status\":\"scheduled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"created_at\":\"2026-05-02T10:00:00Z\"") != null);
}

test "D-O5.followup-4 visits.transition publishes visit.transitioned to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();
    try fx.seedJob("j-tx");

    var sink = PublishSink.init(allocator);
    defer sink.deinit();

    var ctx = rootCtx();
    try fx.seedVisitAt(&ctx, "v-tx", "j-tx", "scheduled");

    // Subscribe AFTER the seed so the create-emit doesn't pollute the
    // assertion below.
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var r = try fx.disp.dispatch(&ctx, "visits", "transition",
        \\{"id":"v-tx","to_state":"in_progress","principal_kind":"service"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("visit.transitioned", sink.types.items[0]);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"v-tx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"job_id\":\"j-tx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"from\":\"scheduled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"to\":\"in_progress\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"transitioned_at\":") != null);
}

```
