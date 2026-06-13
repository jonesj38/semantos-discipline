---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/jobs_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.197287+00:00
---

# runtime/semantos-brain/tests/jobs_handler_conformance.zig

```zig
// D-O5.followup-1 / D-O5m.followup-4 — see
// docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm jobs view).
//
// Conformance suite for `resources/jobs_handler.zig`.  Mirrors the
// shape of `bearer_tokens_handler_conformance.zig`: dispatcher →
// ResourceHandler → JobsStore for the three spec'd commands plus the
// cap-gating + state-filter + idempotent-recreate paths required by
// acceptance §6.
//
// What this closes:
//
//   • Both helms (loom-svelte JobList.svelte + oddjobz-mobile
//     jobs_repository.dart) prefer the JSON-array branch when the REPL
//     response starts with `[`.  This suite asserts the bytes the
//     dispatcher returns satisfy that branch — id / customer_name /
//     state / scheduled_at / created_at all show up as JSON strings.
//
//   • Idempotent re-create: helm-side outbox flushes retry naively;
//     the second call must return `status: "already_exists"` (200,
//     not error) so the offline path doesn't get stuck.
//
//   • Cap-gating: `jobs.find` and `jobs.find_by_id` require
//     `cap.oddjobz.read_jobs`; `jobs.create` requires
//     `cap.oddjobz.write_customer`.  Bearer contexts without the cap
//     are rejected with `capability_denied` — root-scope contexts
//     bypass per the dispatcher contract.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const jobs_handler_mod = @import("jobs_handler");
const job_fsm = @import("job_fsm");
const helm_event_broker = @import("helm_event_broker");
// W0.1: JobsStore now needs a CellStore; bring in lmdb helpers.
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
// audit_log + the handler's pointer to JobsStore are address-stable.
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    store: jobs_store_fs.JobsStore,
    handler: jobs_handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
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
        // W0.1: init LMDB env in-place so CellStore pointer stays stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();
        try self.audit.open(audit_path);
        self.store = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = jobs_handler_mod.Handler.init(allocator, &self.store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
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

test "D-O5.followup-1 jobs: create → find returns the job (JSON shape)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();

    var create_result = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-001","customer_name":"Acme Corp","state":"lead","scheduled_at":"2026-05-15T09:00:00Z","created_at":"2026-05-02T10:00:00Z"}
    );
    defer create_result.deinit();

    const status = try jsonString(allocator, create_result.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);
    const id_back = try jsonString(allocator, create_result.payload, "id");
    defer allocator.free(id_back);
    try std.testing.expectEqualStrings("job-001", id_back);

    // find — empty filter returns all jobs.
    var find_result = try fx.disp.dispatch(&ctx, "jobs", "find", "{}");
    defer find_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_result.payload));
    // The exact bytes the helm consumes — assert the JSON-array body
    // shape directly (so a future churn that drops fields breaks loud
    // here, where the operator can see the diff).
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"id\":\"job-001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"customer_name\":\"Acme Corp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"state\":\"lead\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"scheduled_at\":\"2026-05-15T09:00:00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"created_at\":\"2026-05-02T10:00:00Z\"") != null);

    // find_by_id — single job back.
    var byid_result = try fx.disp.dispatch(&ctx, "jobs", "find_by_id",
        \\{"id":"job-001"}
    );
    defer byid_result.deinit();
    const cn_back = try jsonString(allocator, byid_result.payload, "customer_name");
    defer allocator.free(cn_back);
    try std.testing.expectEqualStrings("Acme Corp", cn_back);
}

// ─────────────────────────────────────────────────────────────────────
// state filter
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-1 jobs: find with state filter narrows result set" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c1 = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-001","customer_name":"A","state":"lead","scheduled_at":"","created_at":"2026-01-01T00:00:00Z"}
    );
    c1.deinit();
    var c2 = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-002","customer_name":"B","state":"scheduled","scheduled_at":"2026-05-15T09:00Z","created_at":"2026-01-02T00:00:00Z"}
    );
    c2.deinit();
    var c3 = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-003","customer_name":"C","state":"lead","scheduled_at":"","created_at":"2026-01-03T00:00:00Z"}
    );
    c3.deinit();

    var leads = try fx.disp.dispatch(&ctx, "jobs", "find",
        \\{"state":"lead"}
    );
    defer leads.deinit();
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayLen(allocator, leads.payload));

    var sched = try fx.disp.dispatch(&ctx, "jobs", "find",
        \\{"state":"scheduled"}
    );
    defer sched.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, sched.payload));
    try std.testing.expect(std.mem.indexOf(u8, sched.payload, "\"customer_name\":\"B\"") != null);

    var none = try fx.disp.dispatch(&ctx, "jobs", "find",
        \\{"state":"paid"}
    );
    defer none.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, none.payload));
}

// ─────────────────────────────────────────────────────────────────────
// idempotent re-create (acceptance §3)
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-1 jobs: re-create with same id returns already_exists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var first = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-x","customer_name":"X","state":"lead","scheduled_at":"","created_at":"2026-01-01T00:00:00Z"}
    );
    defer first.deinit();
    const status1 = try jsonString(allocator, first.payload, "status");
    defer allocator.free(status1);
    try std.testing.expectEqualStrings("created", status1);

    var second = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-x","customer_name":"X","state":"lead","scheduled_at":"","created_at":"2026-01-01T00:00:00Z"}
    );
    defer second.deinit();
    const status2 = try jsonString(allocator, second.payload, "status");
    defer allocator.free(status2);
    try std.testing.expectEqualStrings("already_exists", status2);
}

// ─────────────────────────────────────────────────────────────────────
// validation paths
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-1 jobs: create with malformed state returns invalid_state" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_state, fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-bad","customer_name":"X","state":"PAUSED","scheduled_at":"","created_at":"2026-01-01T00:00:00Z"}
    ));
}

test "D-O5.followup-1 jobs: server-stamps id when caller passes empty" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"customer_name":"Stamped","state":"lead"}
    );
    defer result.deinit();
    const id_back = try jsonString(allocator, result.payload, "id");
    defer allocator.free(id_back);
    // 16 random bytes hex-encoded = 32 chars.
    try std.testing.expectEqual(@as(usize, 32), id_back.len);
    const status = try jsonString(allocator, result.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);
}

test "D-O5.followup-1 jobs: find_by_id on missing returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "jobs", "find_by_id",
        \\{"id":"job-does-not-exist"}
    );
    defer result.deinit();
    const err_kind = try jsonString(allocator, result.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// cap-gating
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-1 jobs: bearer without cap.oddjobz.read_jobs is denied for find" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Empty cap set on a bearer-auth'd context.
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "jobs", "find", "{}"));
}

test "D-O5.followup-1 jobs: bearer with cap.oddjobz.read_jobs can find but not create" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // First seed via root so there's something to find.
    var root = rootCtx();
    var seeded = try fx.disp.dispatch(&root, "jobs", "create",
        \\{"id":"job-r","customer_name":"R","state":"lead","scheduled_at":"","created_at":"2026-01-01T00:00:00Z"}
    );
    seeded.deinit();

    const reader = bearerCtxWithCaps(&.{"cap.oddjobz.read_jobs"});
    var find_ok = try fx.disp.dispatch(&reader, "jobs", "find", "{}");
    defer find_ok.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_ok.payload));

    // Reader cannot create — that needs cap.oddjobz.write_customer.
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&reader, "jobs", "create",
        \\{"id":"job-r2","customer_name":"R2","state":"lead"}
    ));
}

test "D-O5.followup-1 jobs: bearer with cap.oddjobz.write_customer can create but not read" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const writer = bearerCtxWithCaps(&.{"cap.oddjobz.write_customer"});
    var ok = try fx.disp.dispatch(&writer, "jobs", "create",
        \\{"id":"job-w","customer_name":"W","state":"lead"}
    );
    defer ok.deinit();

    // write_customer doesn't imply read_jobs — find is denied.
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&writer, "jobs", "find", "{}"));
}

// ─────────────────────────────────────────────────────────────────────
// audit-pair invariant — both phases logged for every dispatch
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-3 — find_calendar
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 jobs: find_calendar groups by day across [from, to]" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();

    // Seed: a single job on 2026-05-04 in [2026-05-04, 2026-05-06].
    // Kept to one seed because jobs_store_fs.zig has a latent string-
    // arena dangling-slice bug (logged separately as a task chip;
    // mirror of the one we fixed in customers_store_fs.zig in #308)
    // that surfaces with multi-record seed sets — this PR doesn't
    // touch jobs_store_fs.zig.  The follow-up test below covers the
    // empty-day-payload and per-day-sort branches with a separate
    // fixture instance.
    var c1 = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-cal-001","customer_name":"Alice","state":"scheduled","scheduled_at":"2026-05-04T09:00:00Z","created_at":"2026-05-01T00:00:00Z"}
    );
    c1.deinit();

    var cal = try fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-04","to":"2026-05-06"}
    );
    defer cal.deinit();

    // Three days inclusive in the response.
    try std.testing.expectEqual(@as(usize, 3), try jsonArrayLen(allocator, cal.payload));

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, cal.payload, .{});
    defer parsed.deinit();
    const arr = parsed.value.array;

    // 2026-05-04 should hold one job (Alice).
    const day0 = arr.items[0].object;
    try std.testing.expectEqualStrings("2026-05-04", day0.get("date").?.string);
    const jobs0 = day0.get("jobs").?.array;
    try std.testing.expectEqual(@as(usize, 1), jobs0.items.len);
    try std.testing.expectEqualStrings("Alice", jobs0.items[0].object.get("customer_name").?.string);

    // 2026-05-05 has no jobs — array present, empty (so the helm can
    // render a calendar grid without missing-key checks).
    const day1 = arr.items[1].object;
    try std.testing.expectEqualStrings("2026-05-05", day1.get("date").?.string);
    try std.testing.expectEqual(@as(usize, 0), day1.get("jobs").?.array.items.len);

    // 2026-05-06 also empty.
    try std.testing.expectEqual(@as(usize, 0), arr.items[2].object.get("jobs").?.array.items.len);
}

test "D-O5.followup-3 jobs: find_calendar yields empty-jobs arrays for days with no scheduled jobs" {
    // Seed an empty store, then run a small range — every day should
    // come back with `jobs: []` rather than missing keys.  This is the
    // "helm renders a calendar grid without missing-key checks"
    // contract.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var cal = try fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-04","to":"2026-05-08"}
    );
    defer cal.deinit();

    try std.testing.expectEqual(@as(usize, 5), try jsonArrayLen(allocator, cal.payload));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, cal.payload, .{});
    defer parsed.deinit();
    for (parsed.value.array.items, 0..) |day, i| {
        // Date entries are present and ascending.
        const date_obj = day.object.get("date").?.string;
        try std.testing.expect(date_obj.len == 10);
        // jobs key present and an empty array.
        const jobs_arr = day.object.get("jobs").?.array;
        try std.testing.expectEqual(@as(usize, 0), jobs_arr.items.len);
        _ = i;
    }
}

test "D-O5.followup-3 jobs: find_calendar default range covers 8 days from start-of-week" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var cal = try fx.disp.dispatch(&ctx, "jobs", "find_calendar", "{}");
    defer cal.deinit();
    // Default span is 7 days inclusive on both ends → 8 day buckets.
    try std.testing.expectEqual(@as(usize, 8), try jsonArrayLen(allocator, cal.payload));
}

test "D-O5.followup-3 jobs: find_calendar rejects malformed dates" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_date_range, fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"05/04/2026","to":"05/08/2026"}
    ));
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_date_range, fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-13-40","to":"2026-13-50"}
    ));
}

test "D-O5.followup-3 jobs: find_calendar rejects from > to and ranges > 31 days" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    // from > to.
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_date_range, fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-10","to":"2026-05-04"}
    ));
    // 32-day span.
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_date_range, fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-01","to":"2026-06-02"}
    ));
}

test "D-O5.followup-3 jobs: find_calendar requires cap.oddjobz.read_jobs" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-04","to":"2026-05-05"}
    ));
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-3 — find_attention
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 jobs: find_attention on empty store returns all-empty categories" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    defer att.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, att.payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_quote").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_schedule").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_invoice").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0), obj.get("total").?.integer);
}

test "D-O5.followup-3 jobs: find_attention surfaces a single lead in pending_quote" {
    // Single-seed shape — kept to one create per fixture because
    // jobs_store_fs.zig has a latent string-arena dangling-slice bug
    // (separate task chip — mirror of the one we fixed in customers_
    // store_fs.zig in #308).  Each isolated fixture proves a single
    // category routes correctly; the audit-pair test below proves the
    // dispatcher round-trip is intact.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-att-lead","customer_name":"Lead Customer","state":"lead","scheduled_at":"","created_at":"2026-05-01T00:00:00Z"}
    );
    c.deinit();

    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    defer att.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, att.payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 1), obj.get("pending_quote").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_schedule").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_invoice").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), obj.get("total").?.integer);

    const lead_row = obj.get("pending_quote").?.array.items[0].object;
    try std.testing.expectEqualStrings("job-att-lead", lead_row.get("id").?.string);
    try std.testing.expectEqualStrings("Lead Customer", lead_row.get("customer_name").?.string);
    try std.testing.expectEqualStrings("lead", lead_row.get("state").?.string);
}

test "D-O5.followup-3 jobs: find_attention routes a quoted job into pending_schedule" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-att-quoted","customer_name":"Quoted Customer","state":"quoted","scheduled_at":"","created_at":"2026-05-01T00:00:00Z"}
    );
    c.deinit();

    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    defer att.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, att.payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_quote").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), obj.get("pending_schedule").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_invoice").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), obj.get("total").?.integer);
}

test "D-O5.followup-3 jobs: find_attention routes a completed job into pending_invoice" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-att-completed","customer_name":"Completed Customer","state":"completed","scheduled_at":"2026-05-04T08:00:00Z","created_at":"2026-05-01T00:00:00Z"}
    );
    c.deinit();

    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    defer att.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, att.payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_quote").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_schedule").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), obj.get("pending_invoice").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), obj.get("total").?.integer);
    // Sanity-check the embedded shape — id, customer_name, state,
    // scheduled_at all surface (canonical helm field set).
    const row = obj.get("pending_invoice").?.array.items[0].object;
    try std.testing.expectEqualStrings("completed", row.get("state").?.string);
    try std.testing.expectEqualStrings("2026-05-04T08:00:00Z", row.get("scheduled_at").?.string);
}

test "D-O5.followup-3 jobs: find_attention excludes a scheduled job (non-action state)" {
    // Seed a single non-action state; every category must be empty.
    // The handler's switch is symmetric across the five excluded
    // states (scheduled / in_progress / invoiced / paid / closed); we
    // sample one and trust the rest by inspection.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-non-sched","customer_name":"Scheduled Co","state":"scheduled","scheduled_at":"2026-05-04T09:00:00Z","created_at":"2026-05-01T00:00:00Z"}
    );
    c.deinit();

    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    defer att.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, att.payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_quote").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_schedule").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), obj.get("pending_invoice").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0), obj.get("total").?.integer);
}

test "D-O5.followup-3 jobs: find_attention requires cap.oddjobz.read_jobs" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}"));
}

test "D-O5.followup-3 jobs: find_calendar + find_attention emit paired audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var cal = try fx.disp.dispatch(&ctx, "jobs", "find_calendar",
        \\{"from":"2026-05-04","to":"2026-05-05"}
    );
    cal.deinit();
    var att = try fx.disp.dispatch(&ctx, "jobs", "find_attention", "{}");
    att.deinit();

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
        // Match find_calendar / find_attention specifically (not just
        // the broader `jobs.*` set).
        const matches_cal = std.mem.indexOf(u8, line, "\"op\":\"jobs.find_calendar\"") != null;
        const matches_att = std.mem.indexOf(u8, line, "\"op\":\"jobs.find_attention\"") != null;
        if (!matches_cal and !matches_att) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// ─────────────────────────────────────────────────────────────────────
// audit-pair invariant — both phases logged for every dispatch
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-1 jobs: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "jobs", "create",
        \\{"id":"job-audit","customer_name":"AuditCo","state":"lead"}
    );
    r.deinit();
    var find_r = try fx.disp.dispatch(&ctx, "jobs", "find", "{}");
    find_r.deinit();

    // Read the audit log + count phase=start / phase=end pairs.  The
    // dispatcher's recordAudit emits both with `module="dispatcher"`
    // and `op="<resource>.<cmd>"`; for `jobs.*` we expect 2 starts + 2
    // ends across our two dispatches.
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
        // The dispatcher writes op as a JSON-escaped string of the
        // form `"op":"<resource>.<cmd>"` and detail as `"detail":
        // "phase=<phase> ..."`.  Match against both substrings.
        if (std.mem.indexOf(u8, line, "\"op\":\"jobs.") == null) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5 followup-1 (this PR) — `jobs.transition` FSM cutover.
//
// Asserts:
//   • The full twelve-state lifecycle (incl. the qualified → quoted
//     skip-path branch) fires happy-path through the dispatcher →
//     handler → store stack.
//   • Cross-language parity: the canonical job_fsm.json oracle drives
//     every TS transition through Zig and each output's `state` matches
//     the TS-side `expectedOutput.status`.
//   • Wrong-cap, not-reachable, wrong-principal, unknown-state,
//     not-found surface as typed JSON bodies (200, NOT dispatcher errs).
//   • Idempotent already-in-state.
//   • Cap-gating: a bearer with no caps gets capability_denied at the
//     dispatcher level (the read-jobs gate); a bearer with read_jobs
//     but missing the FSM-row cap gets a typed wrong_cap body.
// ─────────────────────────────────────────────────────────────────────

/// Seed a job at the given FSM state, then return its id.  Driven by
/// the dispatcher's `jobs.create` so we don't bypass the audit-pair
/// path the rest of the suite relies on.
fn seedJobAt(
    fx: *Fixture,
    ctx: *dispatcher.DispatchContext,
    id: []const u8,
    state: []const u8,
) !void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
    try buf.appendSlice(std.testing.allocator, id);
    try buf.appendSlice(std.testing.allocator, "\",\"customer_name\":\"Acme\",\"state\":\"");
    try buf.appendSlice(std.testing.allocator, state);
    try buf.appendSlice(std.testing.allocator, "\",\"scheduled_at\":\"\",\"created_at\":\"2026-05-01T00:00:00Z\"}");
    var r = try fx.disp.dispatch(ctx, "jobs", "create", buf.items);
    r.deinit();
}

/// Issue a transition through the dispatcher and parse the JSON body.
/// Caller owns the parsed `Value`; the result-payload itself is freed
/// on `Result.deinit`.
fn dispatchTransition(
    fx: *Fixture,
    ctx: *dispatcher.DispatchContext,
    args_json: []const u8,
) !dispatcher.Result {
    return fx.disp.dispatch(ctx, "jobs", "transition", args_json);
}

test "D-O5 followup-1 jobs.transition: qualified → quoted (operator + cap.oddjobz.quote, skip path)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    // The direct `lead → quoted` edge was removed in the twelve-state
    // remodel.  `qualified → quoted` is the skip-path edge (quote
    // straight off an accepted ROM, no site visit).
    try seedJobAt(fx, &ctx, "tx-001", "qualified");

    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-001","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    defer r.deinit();
    const state = try jsonString(allocator, r.payload, "state");
    defer allocator.free(state);
    try std.testing.expectEqualStrings("quoted", state);
}

test "D-O5 followup-1 jobs.transition: the full linear happy path traverses every lifecycle state" {
    // Drive a single job through the entire (non-skip) happy path:
    // lead → qualified → visit_pending → visit_scheduled → visited →
    // quoted → scheduled → in_progress → completed → invoiced → paid →
    // closed.  Asserts each step's response carries the new state and
    // the job is persisted at `closed` in the store.  The skip-path
    // edge (qualified → quoted) is exercised separately above.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-flow", "lead");

    const Step = struct {
        to: []const u8,
        cap: ?[]const u8,
        principal: []const u8,
    };
    const steps = [_]Step{
        .{ .to = "qualified", .cap = null, .principal = "operator" },
        .{ .to = "visit_pending", .cap = null, .principal = "operator" },
        .{ .to = "visit_scheduled", .cap = null, .principal = "operator" },
        .{ .to = "visited", .cap = null, .principal = "operator" },
        .{ .to = "quoted", .cap = "cap.oddjobz.quote", .principal = "operator" },
        .{ .to = "scheduled", .cap = "cap.oddjobz.dispatch", .principal = "operator" },
        .{ .to = "in_progress", .cap = null, .principal = "service" },
        .{ .to = "completed", .cap = null, .principal = "operator" },
        .{ .to = "invoiced", .cap = "cap.oddjobz.invoice", .principal = "operator" },
        .{ .to = "paid", .cap = null, .principal = "service" },
        .{ .to = "closed", .cap = "cap.oddjobz.close", .principal = "operator" },
    };

    for (steps) |s| {
        var args: std.ArrayList(u8) = .{};
        defer args.deinit(allocator);
        try args.appendSlice(allocator, "{\"id\":\"tx-flow\",\"to_state\":\"");
        try args.appendSlice(allocator, s.to);
        try args.appendSlice(allocator, "\",\"principal_kind\":\"");
        try args.appendSlice(allocator, s.principal);
        try args.append(allocator, '"');
        if (s.cap) |c| {
            try args.appendSlice(allocator, ",\"presented_cap\":\"");
            try args.appendSlice(allocator, c);
            try args.append(allocator, '"');
        }
        try args.append(allocator, '}');

        var r = try dispatchTransition(fx, &ctx, args.items);
        defer r.deinit();
        const state = try jsonString(allocator, r.payload, "state");
        defer allocator.free(state);
        try std.testing.expectEqualStrings(s.to, state);
    }

    // Final state in the store is `closed`.
    var byid = try fx.disp.dispatch(&ctx, "jobs", "find_by_id",
        \\{"id":"tx-flow"}
    );
    defer byid.deinit();
    const final_state = try jsonString(allocator, byid.payload, "state");
    defer allocator.free(final_state);
    try std.testing.expectEqualStrings("closed", final_state);
}

test "D-O5 followup-1 jobs.transition: cross-language parity oracle" {
    // Load cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json
    // and drive every transition through the Zig dispatcher.  The TS-
    // side `expectedOutput.status` must equal the Zig-side response's
    // `state` for each row.  This is the load-bearing correctness
    // proof that the Semantos Brain-side FSM port matches the TS canon.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const vector_path = "../../cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json";
    const f = try std.fs.cwd().openFile(vector_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed.deinit();

    const transitions = parsed.value.object.get("transitions").?.array;
    // The canonical oracle has exactly twelve transitions in the
    // twelve-state remodel (including the qualified → quoted skip-path
    // branch).  We assert the floor so a regression that drops the
    // table is loud; the parity loop grows automatically if rows are
    // added.
    try std.testing.expect(transitions.items.len >= 12);

    var ctx = rootCtx();

    // The table now has a BRANCH at `qualified` (→ visit_pending and
    // → quoted), so a single job can't be threaded through every row.
    // Instead, seed a FRESH job per row at that row's `from` state and
    // assert the transition lands at `expectedOutput.status`.  This is
    // a strictly stronger parity proof — each edge is exercised in
    // isolation rather than only along one happy path.
    for (transitions.items, 0..) |t, i| {
        const row = t.object;
        const from_state = row.get("from").?.string;
        const to_state = row.get("to").?.string;
        const expected_status = row.get("expectedOutput").?.object.get("status").?.string;
        // capRequired and principalKinds drive the args; we use the
        // first principalKind in the array (every row has exactly one
        // today, but the table is set-typed in the TS canon).
        const principal = row.get("principalKinds").?.array.items[0].string;
        const cap_v = row.get("capRequired").?;

        var id_buf: [32]u8 = undefined;
        const job_id = try std.fmt.bufPrint(&id_buf, "parity-{d}", .{i});
        try seedJobAt(fx, &ctx, job_id, from_state);

        var args: std.ArrayList(u8) = .{};
        defer args.deinit(allocator);
        try args.appendSlice(allocator, "{\"id\":\"");
        try args.appendSlice(allocator, job_id);
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

        var r = try dispatchTransition(fx, &ctx, args.items);
        defer r.deinit();

        const got_state = try jsonString(allocator, r.payload, "state");
        defer allocator.free(got_state);
        // The brain-side response field is `state`; the TS-side
        // `expectedOutput.status` is the canonical name.  Both encode
        // the same value (the post-transition state); equality across
        // them IS the parity proof.
        try std.testing.expectEqualStrings(expected_status, got_state);
    }
}

test "D-O5 followup-1 jobs.transition: wrong cap returns typed body, not dispatcher error" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-wc", "qualified");

    // Present cap.oddjobz.invoice for a qualified → quoted move that
    // wants cap.oddjobz.quote.  Body should carry `error: "wrong_cap"` +
    // the required cap so the helm can render a useful message.
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-wc","to_state":"quoted","presented_cap":"cap.oddjobz.invoice","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("wrong_cap", err_kind);
    const cap_required = try jsonString(allocator, r.payload, "cap_required");
    defer allocator.free(cap_required);
    try std.testing.expectEqualStrings("cap.oddjobz.quote", cap_required);
}

test "D-O5 followup-1 jobs.transition: not-reachable transition returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-nr", "lead");

    // lead → invoiced is not in the §O4 table.
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-nr","to_state":"invoiced","presented_cap":"cap.oddjobz.invoice","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_reachable", err_kind);
}

test "D-O5 followup-1 jobs.transition: unknown to_state returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-uk", "lead");

    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-uk","to_state":"PAUSED","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("unknown_state", err_kind);
}

test "D-O5 followup-1 jobs.transition: wrong principal returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-wp", "qualified");

    // qualified → quoted is operator-only; service principal must reject.
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-wp","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"service"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("wrong_principal", err_kind);
}

test "D-O5 followup-1 jobs.transition: not_found id returns typed body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"never-existed","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

test "D-O5 followup-1 jobs.transition: idempotent already_in_state" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-idem", "scheduled");

    // Re-issuing scheduled → scheduled returns the current job under
    // the `already_in_state` typed-success body shape.
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-idem","to_state":"scheduled","principal_kind":"service"}
    );
    defer r.deinit();
    const status = try jsonString(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("already_in_state", status);

    // Embedded `job` matches the seeded record shape.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, r.payload, .{});
    defer parsed.deinit();
    const job_obj = parsed.value.object.get("job").?.object;
    try std.testing.expectEqualStrings("tx-idem", job_obj.get("id").?.string);
    try std.testing.expectEqualStrings("scheduled", job_obj.get("state").?.string);
}

test "D-O5 followup-1 jobs.transition: bearer without read_jobs gets capability_denied" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var root = rootCtx();
    try seedJobAt(fx, &root, "tx-cd", "lead");

    // Bearer with empty cap set must be denied at the dispatcher's
    // capability gate before the FSM check runs.
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-cd","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    ));
}

test "D-O5 followup-1 jobs.transition: bearer with read_jobs but missing FSM-row cap gets wrong_cap body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var root = rootCtx();
    try seedJobAt(fx, &root, "tx-rcap", "qualified");

    // Bearer holds read_jobs (so dispatcher gate passes) but neither
    // presents cap.oddjobz.quote nor holds it in CapabilitySet.  The
    // handler's per-FSM-row cap check fires and returns the typed
    // wrong_cap body with `cap_required` populated.
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.read_jobs"});
    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-rcap","to_state":"quoted","principal_kind":"operator"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("wrong_cap", err_kind);
    const cap_required = try jsonString(allocator, r.payload, "cap_required");
    defer allocator.free(cap_required);
    try std.testing.expectEqualStrings("cap.oddjobz.quote", cap_required);
}

test "D-O5 followup-1 jobs.transition: bearer with read_jobs + per-row cap completes the transition" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var root = rootCtx();
    try seedJobAt(fx, &root, "tx-okcap", "qualified");

    // Bearer holds both read_jobs (dispatcher gate) AND the FSM-row
    // cap (handler gate).  Transition succeeds.
    const ctx = bearerCtxWithCaps(&.{ "cap.oddjobz.read_jobs", "cap.oddjobz.quote" });
    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-okcap","to_state":"quoted","principal_kind":"operator"}
    );
    defer r.deinit();
    const state = try jsonString(allocator, r.payload, "state");
    defer allocator.free(state);
    try std.testing.expectEqualStrings("quoted", state);
}

test "D-O5 followup-1 jobs.transition: schedule transition records scheduled_at" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-sched", "qualified");
    var quoted = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-sched","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    quoted.deinit();

    // schedule transition with a `scheduled_at` arg.
    var sched = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-sched","to_state":"scheduled","presented_cap":"cap.oddjobz.dispatch","principal_kind":"operator","scheduled_at":"2026-05-15T09:00:00Z"}
    );
    defer sched.deinit();
    const scheduled_at = try jsonString(allocator, sched.payload, "scheduled_at");
    defer allocator.free(scheduled_at);
    try std.testing.expectEqualStrings("2026-05-15T09:00:00Z", scheduled_at);
}

test "D-O5 followup-1 jobs.transition: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-audit", "qualified");
    var r = try dispatchTransition(fx, &ctx,
        \\{"id":"tx-audit","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    r.deinit();

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
        if (std.mem.indexOf(u8, line, "\"op\":\"jobs.transition\"") == null) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), starts);
    try std.testing.expectEqual(@as(usize, 1), ends);
}

test "D-O5 followup-1 jobs.transition: malformed principal_kind returns invalid_principal_kind handler error" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try seedJobAt(fx, &ctx, "tx-bad-pk", "lead");

    // Wire-shape failure (principal_kind missing) — the handler
    // returns the typed error so the dispatcher tags audit-end with
    // err=invalid_principal_kind.  Distinguished from FSM-level
    // wrong_principal: that one returns a typed JSON body.
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_principal_kind, fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-bad-pk","to_state":"quoted","presented_cap":"cap.oddjobz.quote"}
    ));
    try std.testing.expectError(jobs_handler_mod.HandlerError.invalid_principal_kind, fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-bad-pk","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"alien"}
    ));
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-4 — broker-emit assertion.  A successful
// jobs.transition publishes "job.transitioned" to the broker; both
// helms (mobile + svelte) consume the same fan-out as `helm.event`
// JSON-RPC notifications over WSS.
//
// Substrate scope: only this handler emits in this PR; other emitters
// (customers / visits / quotes / invoices / attachments) land in
// followup PRs — adding them is mechanical (`broker.publish` after the
// store write).
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

/// Variant fixture that wires a broker into the handler.  Mirrors the
/// main Fixture but uses Handler.initWithBroker so the substrate's
/// emit path is exercised.
const BrokerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    store: jobs_store_fs.JobsStore,
    handler: jobs_handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    broker: helm_event_broker.Broker,

    fn init(allocator: std.mem.Allocator) !*BrokerFixture {
        const self = try allocator.create(BrokerFixture);
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
        return self;
    }

    fn deinit(self: *BrokerFixture) void {
        self.broker.deinit();
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }
};

fn seedJobAtBroker(
    fx: *BrokerFixture,
    ctx: *dispatcher.DispatchContext,
    id: []const u8,
    state: []const u8,
) !void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try buf.appendSlice(std.testing.allocator, "{\"id\":\"");
    try buf.appendSlice(std.testing.allocator, id);
    try buf.appendSlice(std.testing.allocator, "\",\"customer_name\":\"Acme\",\"state\":\"");
    try buf.appendSlice(std.testing.allocator, state);
    try buf.appendSlice(std.testing.allocator, "\",\"scheduled_at\":\"\",\"created_at\":\"2026-05-01T00:00:00Z\"}");
    var r = try fx.disp.dispatch(ctx, "jobs", "create", buf.items);
    r.deinit();
}

test "D-O5.followup-4 jobs.transition publishes job.transitioned to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    try seedJobAtBroker(fx, &ctx, "tx-pub", "qualified");

    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-pub","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    defer r.deinit();

    // Exactly one event published — the transition we just drove.
    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("job.transitioned", sink.types.items[0]);

    // Payload carries the canonical {id, from, to, scheduled_at,
    // transitioned_at} shape both helms parse.
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"tx-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"from\":\"qualified\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"to\":\"quoted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"transitioned_at\":") != null);
}

test "D-O5.followup-4 jobs.transition does NOT publish on FSM rejection" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    try seedJobAtBroker(fx, &ctx, "tx-rej", "lead");

    // lead → invoiced is not_reachable per the §O4 FSM table; the
    // handler returns a typed JSON body but does NOT publish.
    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-rej","to_state":"invoiced","presented_cap":"cap.oddjobz.invoice","principal_kind":"operator"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 0), sink.types.items.len);
}

test "D-O5.followup-4 jobs.transition does NOT publish on already_in_state idempotency" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    try seedJobAtBroker(fx, &ctx, "tx-idem-pub", "scheduled");

    // scheduled → scheduled is the idempotent re-issue path; the
    // store write doesn't fire so neither does the publish.
    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-idem-pub","to_state":"scheduled","principal_kind":"service"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 0), sink.types.items.len);
}

test "D-O5.followup-4 jobs.transition fan-out reaches multiple subscribers" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();

    var sink_a = PublishSink.init(allocator);
    defer sink_a.deinit();
    var sink_b = PublishSink.init(allocator);
    defer sink_b.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink_a, .callback = PublishSink.callback });
    _ = try fx.broker.subscribe(.{ .state = &sink_b, .callback = PublishSink.callback });

    var ctx = rootCtx();
    try seedJobAtBroker(fx, &ctx, "tx-fan", "qualified");

    var r = try fx.disp.dispatch(&ctx, "jobs", "transition",
        \\{"id":"tx-fan","to_state":"quoted","presented_cap":"cap.oddjobz.quote","principal_kind":"operator"}
    );
    defer r.deinit();

    // Both subscribers receive the event (one transition → two
    // notifications across the fan-out).
    try std.testing.expectEqual(@as(usize, 1), sink_a.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), sink_b.types.items.len);
}

```
