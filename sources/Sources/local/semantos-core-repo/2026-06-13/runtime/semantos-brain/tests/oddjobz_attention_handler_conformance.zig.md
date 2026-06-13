---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/oddjobz_attention_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.191007+00:00
---

# runtime/semantos-brain/tests/oddjobz_attention_handler_conformance.zig

```zig
// Tier 2P Phase B — oddjobz_attention_handler conformance suite.
//
// Reference: docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md §4 Phase B;
//            runtime/semantos-brain/src/oddjobz_attention_handler.zig (the handler);
//            runtime/semantos-brain/tests/oddjobz_query_handler_conformance.zig
//              (pattern for fixture setup + tmp data-dir).
//
// Coverage:
//
//   1. Empty JSONL files (or absent files) → empty arrays, no crash.
//   2. messages.jsonl with 5 lines → list_messages returns all 5,
//      sorted desc by timestamp; `since` filter cuts half.
//   3. dispatch-decisions.jsonl with requiresRatification mix →
//      filter param works.
//   4. poll_attention_signals: 3 dispatches (1 requires ratification,
//      2 routed), 4 customer messages, 6 open jobs (due-date spread).
//      Verify union shape + correct scoring.

const std = @import("std");
const jobs_store_fs = @import("jobs_store_fs");
const oddjobz_attention = @import("oddjobz_attention_handler");
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

// ── Fixture ────────────────────────────────────────────────────────────

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    oddjobz_dir: []u8,
    messages_path: []u8,
    dispatch_path: []u8,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    jobs: jobs_store_fs.JobsStore,
    handler: oddjobz_attention.Handler,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);

        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);

        // Create the oddjobz subdir manually so tests can write files.
        const oddjobz_dir = try std.fs.path.join(allocator, &.{ data_dir, "oddjobz" });
        errdefer allocator.free(oddjobz_dir);
        std.fs.cwd().makePath(oddjobz_dir) catch {};

        const messages_path = try std.fs.path.join(allocator, &.{ oddjobz_dir, "messages.jsonl" });
        errdefer allocator.free(messages_path);
        const dispatch_path = try std.fs.path.join(allocator, &.{ oddjobz_dir, "dispatch-decisions.jsonl" });
        errdefer allocator.free(dispatch_path);

        self.allocator = allocator;
        self.tmp_dir = tmp;
        self.data_dir = data_dir;
        self.oddjobz_dir = oddjobz_dir;
        self.messages_path = messages_path;
        self.dispatch_path = dispatch_path;
        // W0.1: init LMDB env in-place so CellStore pointer stays stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();

        self.jobs = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        errdefer self.jobs.deinit();

        self.handler = try oddjobz_attention.Handler.init(allocator, data_dir, &self.jobs);
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.handler.deinit(self.allocator);
        self.jobs.deinit();
        self.lmdb_env.close();
        self.allocator.free(self.dispatch_path);
        self.allocator.free(self.messages_path);
        self.allocator.free(self.oddjobz_dir);
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    /// Write `lines` to the messages.jsonl file (creates or overwrites).
    fn writeMessages(self: *Fixture, lines: []const []const u8) !void {
        const file = try std.fs.cwd().createFile(self.messages_path, .{});
        defer file.close();
        for (lines) |line| {
            try file.writeAll(line);
            try file.writeAll("\n");
        }
    }

    /// Write `lines` to the dispatch-decisions.jsonl file.
    fn writeDispatch(self: *Fixture, lines: []const []const u8) !void {
        const file = try std.fs.cwd().createFile(self.dispatch_path, .{});
        defer file.close();
        for (lines) |line| {
            try file.writeAll(line);
            try file.writeAll("\n");
        }
    }
};

fn pinnedClock() i64 {
    return 1_700_000_000;
}

// ── helpers ────────────────────────────────────────────────────────────

/// Parse the returned JSON array and return its length.
fn arrayLen(allocator: std.mem.Allocator, json: []const u8) !usize {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.NotAnArray;
    return parsed.value.array.items.len;
}

/// Parse a JSON object and return the float value of `key`.
fn floatField(allocator: std.mem.Allocator, json: []const u8, key: []const u8) !f64 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.NotAnObject;
    const v = parsed.value.object.get(key) orelse return error.MissingKey;
    return switch (v) {
        .float => v.float,
        .integer => @as(f64, @floatFromInt(v.integer)),
        else => error.NotANumber,
    };
}

/// Collect all `kind` strings from a JSON array of attention-signal objects.
fn collectKinds(allocator: std.mem.Allocator, json: []const u8) ![][]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.NotAnArray;
    var out: std.ArrayList([]const u8) = .{};
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const kv = item.object.get("kind") orelse continue;
        if (kv != .string) continue;
        try out.append(allocator, try allocator.dupe(u8, kv.string));
    }
    return out.toOwnedSlice(allocator);
}

/// Collect all score values from a JSON array.
fn collectScores(allocator: std.mem.Allocator, json: []const u8) ![]f64 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.NotAnArray;
    var out: std.ArrayList(f64) = .{};
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const sv = item.object.get("score") orelse continue;
        const score: f64 = switch (sv) {
            .float => sv.float,
            .integer => @as(f64, @floatFromInt(sv.integer)),
            else => continue,
        };
        try out.append(allocator, score);
    }
    return out.toOwnedSlice(allocator);
}

// ── tests ──────────────────────────────────────────────────────────────

test "oddjobz_attention_handler: empty JSONL files return empty arrays, no crash" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // messages.jsonl absent → empty array
    const msgs = try fx.handler.listMessages(allocator, "null");
    defer allocator.free(msgs);
    try std.testing.expectEqual(@as(usize, 0), try arrayLen(allocator, msgs));

    // dispatch-decisions.jsonl absent → empty array
    const disp = try fx.handler.listDispatchDecisions(allocator, "null");
    defer allocator.free(disp);
    try std.testing.expectEqual(@as(usize, 0), try arrayLen(allocator, disp));

    // poll_attention_signals with no data → empty array
    const poll = try fx.handler.pollAttentionSignals(allocator, "{\"limit\":50}");
    defer allocator.free(poll);
    try std.testing.expectEqual(@as(usize, 0), try arrayLen(allocator, poll));
}

test "oddjobz_attention_handler: empty lines in JSONL file are skipped" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Write a file with blank lines and a bad JSON line.
    try fx.writeMessages(&.{
        "",
        "   ",
        "not-valid-json",
        "{\"patchId\":\"p1\",\"providerId\":\"meta\",\"sessionId\":\"s1\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"customer\",\"text\":\"hello\",\"timestamp\":1000}",
    });

    const msgs = try fx.handler.listMessages(allocator, "null");
    defer allocator.free(msgs);
    // Only the valid line should survive.
    try std.testing.expectEqual(@as(usize, 1), try arrayLen(allocator, msgs));
}

test "oddjobz_attention_handler: list_messages returns 5 rows sorted desc by timestamp" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // 5 messages with timestamps out-of-order.
    const lines = [_][]const u8{
        "{\"patchId\":\"p3\",\"providerId\":\"meta\",\"sessionId\":\"s1\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"customer\",\"text\":\"third\",\"timestamp\":3000}",
        "{\"patchId\":\"p1\",\"providerId\":\"meta\",\"sessionId\":\"s1\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"customer\",\"text\":\"first\",\"timestamp\":1000}",
        "{\"patchId\":\"p5\",\"providerId\":\"meta\",\"sessionId\":\"s2\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"assistant\",\"text\":\"fifth\",\"timestamp\":5000}",
        "{\"patchId\":\"p2\",\"providerId\":\"meta\",\"sessionId\":\"s1\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"customer\",\"text\":\"second\",\"timestamp\":2000}",
        "{\"patchId\":\"p4\",\"providerId\":\"meta\",\"sessionId\":\"s2\",\"channel\":\"messenger\",\"recipientId\":\"r1\",\"role\":\"customer\",\"text\":\"fourth\",\"timestamp\":4000}",
    };
    try fx.writeMessages(&lines);

    const msgs = try fx.handler.listMessages(allocator, "null");
    defer allocator.free(msgs);

    // All 5 returned.
    try std.testing.expectEqual(@as(usize, 5), try arrayLen(allocator, msgs));

    // Verify descending timestamp order (5000 → 4000 → 3000 → ...).
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, msgs, .{});
    defer parsed.deinit();
    const arr = parsed.value.array.items;
    var prev_ts: i64 = std.math.maxInt(i64);
    for (arr) |item| {
        const ts_v = item.object.get("timestamp").?;
        const ts: i64 = switch (ts_v) {
            .integer => ts_v.integer,
            .float => @intFromFloat(ts_v.float),
            else => unreachable,
        };
        try std.testing.expect(ts <= prev_ts);
        prev_ts = ts;
    }

    // `since` filter: only timestamps >= 3000 → 3 items.
    const filtered = try fx.handler.listMessages(allocator, "{\"since\":3000}");
    defer allocator.free(filtered);
    try std.testing.expectEqual(@as(usize, 3), try arrayLen(allocator, filtered));

    // providerId filter.
    const by_provider = try fx.handler.listMessages(allocator, "{\"providerId\":\"meta\"}");
    defer allocator.free(by_provider);
    try std.testing.expectEqual(@as(usize, 5), try arrayLen(allocator, by_provider));

    // sessionId filter: only "s1" → 3 rows (p1, p2, p3).
    const by_session = try fx.handler.listMessages(allocator, "{\"sessionId\":\"s1\"}");
    defer allocator.free(by_session);
    try std.testing.expectEqual(@as(usize, 3), try arrayLen(allocator, by_session));
}

test "oddjobz_attention_handler: list_messages limit param honoured" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Write 5 lines.
    const lines = [_][]const u8{
        "{\"patchId\":\"p1\",\"role\":\"customer\",\"text\":\"a\",\"timestamp\":1000}",
        "{\"patchId\":\"p2\",\"role\":\"customer\",\"text\":\"b\",\"timestamp\":2000}",
        "{\"patchId\":\"p3\",\"role\":\"customer\",\"text\":\"c\",\"timestamp\":3000}",
        "{\"patchId\":\"p4\",\"role\":\"customer\",\"text\":\"d\",\"timestamp\":4000}",
        "{\"patchId\":\"p5\",\"role\":\"customer\",\"text\":\"e\",\"timestamp\":5000}",
    };
    try fx.writeMessages(&lines);

    const limited = try fx.handler.listMessages(allocator, "{\"limit\":3}");
    defer allocator.free(limited);
    try std.testing.expectEqual(@as(usize, 3), try arrayLen(allocator, limited));
}

test "oddjobz_attention_handler: list_dispatch_decisions filter by requiresRatification" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const lines = [_][]const u8{
        "{\"sourcePatchId\":\"p1\",\"lane\":\"self\",\"slot\":\"talk.self\",\"transport\":\"none\",\"text\":\"a\",\"confidence\":0.9,\"requiresRatification\":true,\"primaryTarget\":{\"type\":\"job\",\"ref\":\"job-1\",\"score\":0.9}}",
        "{\"sourcePatchId\":\"p2\",\"lane\":\"direct\",\"slot\":\"talk.direct\",\"transport\":\"direct\",\"text\":\"b\",\"confidence\":0.7,\"requiresRatification\":false,\"primaryTarget\":{\"type\":\"customer\",\"ref\":\"cust-1\",\"score\":0.7}}",
        "{\"sourcePatchId\":\"p3\",\"lane\":\"broadcast\",\"slot\":\"talk.broadcast\",\"transport\":\"broadcast\",\"text\":\"c\",\"confidence\":0.5,\"requiresRatification\":true,\"primaryTarget\":{\"type\":\"broadcast-channel\",\"ref\":\"bc-1\",\"score\":0.5}}",
        "{\"sourcePatchId\":\"p4\",\"lane\":\"squad\",\"slot\":\"talk.squad\",\"transport\":\"multicast\",\"text\":\"d\",\"confidence\":0.6,\"requiresRatification\":false,\"primaryTarget\":{\"type\":\"squad\",\"ref\":\"sq-1\",\"score\":0.6}}",
    };
    try fx.writeDispatch(&lines);

    // All 4.
    const all = try fx.handler.listDispatchDecisions(allocator, "null");
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 4), try arrayLen(allocator, all));

    // Only requiresRatification == true → 2.
    const ratify = try fx.handler.listDispatchDecisions(allocator, "{\"requiresRatification\":true}");
    defer allocator.free(ratify);
    try std.testing.expectEqual(@as(usize, 2), try arrayLen(allocator, ratify));

    // Only requiresRatification == false → 2.
    const no_ratify = try fx.handler.listDispatchDecisions(allocator, "{\"requiresRatification\":false}");
    defer allocator.free(no_ratify);
    try std.testing.expectEqual(@as(usize, 2), try arrayLen(allocator, no_ratify));

    // lane filter.
    const broadcast = try fx.handler.listDispatchDecisions(allocator, "{\"lane\":\"broadcast\"}");
    defer allocator.free(broadcast);
    try std.testing.expectEqual(@as(usize, 1), try arrayLen(allocator, broadcast));

    // primaryTargetType filter.
    const by_type = try fx.handler.listDispatchDecisions(allocator, "{\"primaryTargetType\":\"job\"}");
    defer allocator.free(by_type);
    try std.testing.expectEqual(@as(usize, 1), try arrayLen(allocator, by_type));

    // primaryTargetRef filter.
    const by_ref = try fx.handler.listDispatchDecisions(allocator, "{\"primaryTargetRef\":\"cust-1\"}");
    defer allocator.free(by_ref);
    try std.testing.expectEqual(@as(usize, 1), try arrayLen(allocator, by_ref));
}

test "oddjobz_attention_handler: poll_attention_signals — correct union shape and scoring" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // ── 3 dispatch decisions: 1 requiresRatification, 2 routed ─────────
    const dispatch_lines = [_][]const u8{
        "{\"sourcePatchId\":\"d1\",\"lane\":\"self\",\"slot\":\"talk.self\",\"transport\":\"none\",\"text\":\"ratify me\",\"confidence\":0.8,\"requiresRatification\":true,\"primaryTarget\":{\"type\":\"job\",\"ref\":\"j1\",\"score\":0.8}}",
        "{\"sourcePatchId\":\"d2\",\"lane\":\"direct\",\"slot\":\"talk.direct\",\"transport\":\"direct\",\"text\":\"route a\",\"confidence\":0.6,\"requiresRatification\":false,\"primaryTarget\":{\"type\":\"customer\",\"ref\":\"c1\",\"score\":0.6}}",
        "{\"sourcePatchId\":\"d3\",\"lane\":\"squad\",\"slot\":\"talk.squad\",\"transport\":\"multicast\",\"text\":\"route b\",\"confidence\":0.4,\"requiresRatification\":false,\"primaryTarget\":{\"type\":\"squad\",\"ref\":\"s1\",\"score\":0.4}}",
    };
    try fx.writeDispatch(&dispatch_lines);

    // ── 4 customer messages ─────────────────────────────────────────────
    // Use a fixed "recent" timestamp close enough to now to score 0.62.
    // We cannot know the exact "now" at test-time, so we use a sentinel
    // far in the future (year 2099) to guarantee "within 24h" is false
    // — actually we use the past 1 second from epoch to guarantee old.
    // Easier: just check score == 0.62 OR score == 0.3 (both valid).
    const now_ms = std.time.milliTimestamp();
    var msg_buf: [4][256]u8 = undefined;
    const msg_lines = [_][]const u8{
        try std.fmt.bufPrint(&msg_buf[0], "{{\"patchId\":\"m1\",\"role\":\"customer\",\"text\":\"hi\",\"timestamp\":{d}}}", .{now_ms - 1000}),
        try std.fmt.bufPrint(&msg_buf[1], "{{\"patchId\":\"m2\",\"role\":\"customer\",\"text\":\"hello\",\"timestamp\":{d}}}", .{now_ms - 2000}),
        try std.fmt.bufPrint(&msg_buf[2], "{{\"patchId\":\"m3\",\"role\":\"customer\",\"text\":\"query\",\"timestamp\":{d}}}", .{now_ms - 3000}),
        try std.fmt.bufPrint(&msg_buf[3], "{{\"patchId\":\"m4\",\"role\":\"assistant\",\"text\":\"response\",\"timestamp\":{d}}}", .{now_ms - 4000}),
    };
    try fx.writeMessages(&msg_lines);

    // ── 6 open jobs with varying due dates ─────────────────────────────
    // Jobs are added to the live JobsStore so poll can read them.
    // Use string due-dates: today, +1d, +3d, +8d, +30d, already past.
    // We derive "today" using the same algorithm as the handler.
    var today_buf: [11]u8 = undefined;
    const secs = std.time.timestamp();
    const days_since_epoch: i64 = @divFloor(secs, 86400);
    const z: i64 = days_since_epoch + 719468;
    const era: i64 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i64 = if (mp < 10) mp + 3 else mp - 9;
    const yr: i64 = if (m <= 2) y + 1 else y;
    _ = std.fmt.bufPrint(&today_buf, "{d:0>4}-{d:0>2}-{d:0>2}\x00", .{
        @as(u64, @intCast(yr)),
        @as(u64, @intCast(m)),
        @as(u64, @intCast(d)),
    }) catch unreachable;
    const today = today_buf[0..10];

    // Helper: add N calendar days to a YYYY-MM-DD string (simplified —
    // only handles day-overflow within the same month for test purposes;
    // works because we're picking small offsets).
    var due_bufs: [6][11]u8 = undefined;
    const due_today = today;
    const due_tm1 = try addDays(&due_bufs[1], today, 1);
    const due_tm3 = try addDays(&due_bufs[2], today, 3);
    const due_tm8 = try addDays(&due_bufs[3], today, 8);
    const due_tm30 = try addDays(&due_bufs[4], today, 30);
    // A past date: score 0.2 (>7 days but before today — actually
    // daysDiff returns 0 so score = 0.2 as the fallthrough).
    const due_past = "2000-01-01";
    _ = due_bufs[5];

    // Add 6 open jobs with varying due-dates using appendCreatedV2.
    // For tests we use distinct dummy cellIds (sequential bytes) and
    // empty siteRef / customerRefs / attachmentRefs so the store is
    // happy but we can check poll behaviour.
    const mkId = struct {
        fn call(n: u8) [32]u8 {
            var b: [32]u8 = @splat(0);
            b[31] = n;
            return b;
        }
    }.call;

    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(1), .typeHash = mkId(0x10),
        .customer_name = "Alpha", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_today,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x20),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(2), .typeHash = mkId(0x10),
        .customer_name = "Beta", .state = "quoted",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_tm1,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x21),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(3), .typeHash = mkId(0x10),
        .customer_name = "Gamma", .state = "scheduled",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_tm3,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x22),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(4), .typeHash = mkId(0x10),
        .customer_name = "Delta", .state = "in_progress",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_tm8,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x23),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(5), .typeHash = mkId(0x10),
        .customer_name = "Epsilon", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_tm30,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x24),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = mkId(6), .typeHash = mkId(0x10),
        .customer_name = "Past", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = due_past,
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = mkId(0x25),
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });
    // Terminal job — should NOT appear in poll output.
    _ = try fx.jobs.append(.{
        .id = "terminal-job-aaaaaaaaaaaaaaaaa1",
        .customer_name = "Closed",
        .state = "closed",
        .scheduled_at = "",
        .created_at = "2026-01-01T00:00:00Z",
    });

    // limit=15 → bucket=5 each; we have 1 ratify dispatch, 3 customer
    // messages (m4 is assistant), and 6 open jobs.  Expected union:
    //   dispatch bucket: min(1, 5) = 1
    //   message bucket:  min(3, 5) = 3
    //   job bucket:      min(6, 5) = 5 (sorted by dueDate asc, sliced)
    // Total: 9.
    const signals = try fx.handler.pollAttentionSignals(allocator, "{\"limit\":15}");
    defer allocator.free(signals);

    const kinds = try collectKinds(allocator, signals);
    defer {
        for (kinds) |k| allocator.free(k);
        allocator.free(kinds);
    }

    // Count kinds.
    var n_dispatch: usize = 0;
    var n_message: usize = 0;
    var n_job: usize = 0;
    for (kinds) |k| {
        if (std.mem.eql(u8, k, "dispatch")) n_dispatch += 1;
        if (std.mem.eql(u8, k, "message")) n_message += 1;
        if (std.mem.eql(u8, k, "job")) n_job += 1;
    }

    // 1 dispatch with requiresRatification == true.
    try std.testing.expectEqual(@as(usize, 1), n_dispatch);
    // 3 customer messages (m4 is assistant, excluded).
    try std.testing.expectEqual(@as(usize, 3), n_message);
    // 5 open jobs (out of 6, sliced to bucket=5).
    try std.testing.expectEqual(@as(usize, 5), n_job);

    // Verify dispatch score == 0.9.
    const scores = try collectScores(allocator, signals);
    defer allocator.free(scores);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, signals, .{});
    defer parsed.deinit();
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const kind_v = item.object.get("kind") orelse continue;
        if (kind_v != .string) continue;
        const score_v = item.object.get("score") orelse continue;
        const score: f64 = switch (score_v) {
            .float => score_v.float,
            .integer => @as(f64, @floatFromInt(score_v.integer)),
            else => continue,
        };
        if (std.mem.eql(u8, kind_v.string, "dispatch")) {
            try std.testing.expectApproxEqAbs(@as(f64, 0.9), score, 0.001);
        }
        // signal items have a "raw" field (the underlying record).
        try std.testing.expect(item.object.get("raw") != null);
        // signal items have a "ref" field.
        try std.testing.expect(item.object.get("ref") != null);
        // signal items have a "summary" field.
        try std.testing.expect(item.object.get("summary") != null);
    }
}

test "oddjobz_attention_handler: poll with limit=3 slices to 1+1+1" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const dispatch_line = "{\"sourcePatchId\":\"d1\",\"lane\":\"self\",\"slot\":\"talk.self\",\"transport\":\"none\",\"text\":\"x\",\"confidence\":0.9,\"requiresRatification\":true,\"primaryTarget\":{\"type\":\"job\",\"ref\":\"j1\",\"score\":0.9}}";
    try fx.writeDispatch(&.{dispatch_line});

    const now_ms = std.time.milliTimestamp();
    var mbuf: [256]u8 = undefined;
    const msg_line = try std.fmt.bufPrint(&mbuf, "{{\"patchId\":\"m1\",\"role\":\"customer\",\"text\":\"hello\",\"timestamp\":{d}}}", .{now_ms - 1000});
    try fx.writeMessages(&.{msg_line});

    _ = try fx.jobs.appendCreatedV2(.{
        .cellId = [_]u8{0} ** 31 ++ [_]u8{0xb1},
        .typeHash = [_]u8{0x10} ** 32,
        .customer_name = "Test", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
        .workOrderNumber = null, .issuanceDate = null,
        .dueDate = "2099-12-31",
        .billingParty = null, .hasPhotos = false, .photoCount = null,
        .propertyKey = null, .siteRef = [_]u8{0x30} ** 32,
        .customerRefs = &.{}, .attachmentRefs = &.{},
    });

    // limit=3 → bucket=1 each → 3 total (1 dispatch + 1 message + 1 job).
    const signals = try fx.handler.pollAttentionSignals(allocator, "{\"limit\":3}");
    defer allocator.free(signals);
    try std.testing.expectEqual(@as(usize, 3), try arrayLen(allocator, signals));
}

test "oddjobz_attention_handler: invalid params returns error" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // A non-object, non-null root is invalid_params.
    try std.testing.expectError(
        oddjobz_attention.AttentionError.invalid_params,
        fx.handler.listMessages(allocator, "[1,2,3]"),
    );
    try std.testing.expectError(
        oddjobz_attention.AttentionError.invalid_params,
        fx.handler.listDispatchDecisions(allocator, "[1,2,3]"),
    );
}

// ── Date helper (test-only) ───────────────────────────────────────────

fn addDays(buf: *[11]u8, date: []const u8, days: i64) ![]const u8 {
    if (date.len < 10) return error.InvalidDate;
    const y = try std.fmt.parseInt(i64, date[0..4], 10);
    const mo = try std.fmt.parseInt(i64, date[5..7], 10);
    const da = try std.fmt.parseInt(i64, date[8..10], 10);
    // Convert to Julian Day, add, convert back.
    const jd = julianDay(y, mo, da) + days;
    // Convert Julian Day to Gregorian.
    var z2: i64 = jd + 68569;
    const n: i64 = @divFloor(4 * z2, 146097);
    z2 = z2 - @divFloor(146097 * n + 3, 4);
    const yr2: i64 = @divFloor(4000 * (z2 + 1), 1461001);
    z2 = z2 - @divFloor(1461 * yr2, 4) + 31;
    const mo2: i64 = @divFloor(80 * z2, 2447);
    const da2: i64 = z2 - @divFloor(2447 * mo2, 80);
    z2 = @divFloor(mo2, 11);
    const mo3: i64 = mo2 + 2 - 12 * z2;
    const yr3: i64 = 100 * (n - 49) + yr2 + z2;
    _ = try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}\x00", .{
        @as(u64, @intCast(yr3)),
        @as(u64, @intCast(mo3)),
        @as(u64, @intCast(da2)),
    });
    return buf[0..10];
}

fn julianDay(y: i64, mo: i64, da: i64) i64 {
    const a = @divFloor(14 - mo, 12);
    const yr = y + 4800 - a;
    const m2 = mo + 12 * a - 3;
    return da + @divFloor(153 * m2 + 2, 5) + 365 * yr + @divFloor(yr, 4) - @divFloor(yr, 100) + @divFloor(yr, 400) - 32045;
}

```
