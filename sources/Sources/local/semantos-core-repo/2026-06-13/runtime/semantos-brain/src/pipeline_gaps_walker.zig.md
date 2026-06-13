---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pipeline_gaps_walker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.242751+00:00
---

# runtime/semantos-brain/src/pipeline_gaps_walker.zig

```zig
// DLO follow-up — `substrate.find_pipeline_gaps` walker.
//
// Reference:
//   runtime/semantos-brain/src/overdue_jobs_walker.zig (the walker
//     pattern + State/registerInto shape this mirrors 1:1)
//   runtime/semantos-brain/src/substrate_entity.zig (decodeEntity +
//     SPEC_JOB type-hash + cell payload shape)
//   cartridges/oddjobz/brain/src/state-machines/job-fsm.ts (the twelve-state
//     canon whose early states define the pipeline-gap buckets)
//
// Why this exists:
//
//   The twelve-state remodel made the lead-nurture funnel discrete:
//   lead → qualified → visit_pending → visit_scheduled → visited →
//   quoted. Each pre-quote state is a place a job can SIT — a lead
//   nobody engaged, a qualified ROM nobody actioned, a visit nobody
//   booked, a site visited but never quoted. The operator's stated
//   need: "I can ask an agent to optimise my week on a Sunday and it
//   can check what hasn't been visited yet of qualified leads … get
//   notified of a gap between visited and quoted."
//
//   This walker is the on-host query behind that. pask-adjacent
//   systems + the PWA chat resolver call
//   verb.dispatch({extensionId:"substrate", verb:"find_pipeline_gaps",
//   params:{as_of:"YYYY-MM-DD", stale_days?:7}}) and get the bucketed,
//   staleness-ranked pre-quote worklist back, walked straight off the
//   typed cells — no external script, no receipt-store round-trip.
//
// Algorithm (parallels find_overdue_jobs):
//   • cursor-walk the entity cell store
//   • decodeEntity; keep cells whose type_hash == computeTypeHash(
//     SPEC_JOB) and whose magic is the substrate format
//   • bucket by FSM state — ONLY the pre-quote funnel states are
//     pipeline gaps; quoted/scheduled/in_progress/completed/invoiced/
//     paid/closed are progressing or done and are skipped:
//       lead            → "lead_unqualified"     (raw inbound)
//       qualified        → "qualified_unactioned" (visit-or-quote TBD)
//       visit_pending    → "visit_unscheduled"   (need to arrange time)
//       visit_scheduled  → "visit_upcoming"      (booked, awaiting)
//       visited          → "visited_unquoted"    (THE named gap)
//   • age by payload.issuance_date (the only datable field in the
//     slim job payload — there is no created_at/updated_at). When
//     absent the row is still surfaced with days_in_pipeline=-1 and
//     stale=false (undated → operator-review, never auto-stale).
//   • stale = days_in_pipeline >= stale_days (default 7 — a week, the
//     Sunday-planning cadence)
//   • dedupe on cell hash (defensive, mirrors the overdue walker)
//   • return JSON: per-bucket counts + rows ranked oldest-first
//
// Wire shape (params):
//   { "as_of": "2026-05-16", "stale_days": 7, "limit": 200 }
// Result:
//   { "as_of":"…","stale_days":7,"scanned":N,"job_cells":M,
//     "buckets":{ "lead_unqualified":a,"qualified_unactioned":b,
//                  "visit_unscheduled":c,"visit_upcoming":d,
//                  "visited_unquoted":e },
//     "gaps_total":T,
//     "gaps":[ {cell_id,bucket,state,days_in_pipeline,stale,
//               issuance,work_order,summary,site_ref} … ] }

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const substrate_entity = @import("substrate_entity");
const cell_store_mod = @import("cell_store");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub const State = struct {
    /// Entity cell store. When null the walker returns an empty gap
    /// set with `store_unavailable:true` so callers degrade gracefully
    /// rather than erroring.
    cell_store: ?*const cell_store_mod.CellStore = null,
};

const DEFAULT_STALE_DAYS: i64 = 7;
const DEFAULT_LIMIT: usize = 200;
const HARD_LIMIT: usize = 1000;

/// The pre-quote funnel states, in funnel order, paired with the gap
/// bucket name each maps to. A state NOT in this table is progressing
/// or terminal and is skipped — it is not a pipeline gap.
const Bucket = struct { state: []const u8, name: []const u8 };
const BUCKETS = [_]Bucket{
    .{ .state = "lead", .name = "lead_unqualified" },
    .{ .state = "qualified", .name = "qualified_unactioned" },
    .{ .state = "visit_pending", .name = "visit_unscheduled" },
    .{ .state = "visit_scheduled", .name = "visit_upcoming" },
    .{ .state = "visited", .name = "visited_unquoted" },
};

fn bucketFor(state: []const u8) ?[]const u8 {
    for (BUCKETS) |b| {
        if (std.mem.eql(u8, b.state, state)) return b.name;
    }
    return null;
}

// ─── Walker ──────────────────────────────────────────────────────────

pub fn findPipelineGapsWalker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        return verb_dispatcher.DispatchError.invalid_params;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return verb_dispatcher.DispatchError.invalid_params;
    const obj = parsed.value.object;

    const as_of_v = obj.get("as_of") orelse return verb_dispatcher.DispatchError.invalid_params;
    if (as_of_v != .string or as_of_v.string.len != 10) {
        return verb_dispatcher.DispatchError.invalid_params;
    }
    const as_of = as_of_v.string;
    const as_of_days = parseIsoDateToDays(as_of) orelse return verb_dispatcher.DispatchError.invalid_params;

    const stale_days: i64 = blk: {
        if (obj.get("stale_days")) |v| {
            if (v == .integer and v.integer > 0 and v.integer < 3650) break :blk v.integer;
        }
        break :blk DEFAULT_STALE_DAYS;
    };
    const limit: usize = blk: {
        if (obj.get("limit")) |v| {
            if (v == .integer and v.integer > 0) {
                break :blk @min(@as(usize, @intCast(v.integer)), HARD_LIMIT);
            }
        }
        break :blk DEFAULT_LIMIT;
    };

    const store = state.cell_store orelse {
        // Graceful degradation — no store wired (basic-mode brain).
        return allocator.dupe(
            u8,
            "{\"store_unavailable\":true,\"scanned\":0,\"job_cells\":0,\"gaps\":[]}",
        ) catch verb_dispatcher.DispatchError.out_of_memory;
    };

    const job_type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_JOB);

    const Row = struct {
        cell_id_hex: [64]u8,
        // -1 means undated (no issuance_date) — sorts last, never stale.
        days_in_pipeline: i64,
        stale: bool,
        // small fixed copies — payload fields are short (slimJobJson
        // caps summary at 55, WO is < 32, site_ref is 64 hex).
        bucket: []const u8, // points into BUCKETS (static) — no copy
        issuance_buf: [10]u8,
        issuance_len: usize,
        wo_buf: [48]u8,
        wo_len: usize,
        state_buf: [24]u8,
        state_len: usize,
        summary_buf: [120]u8,
        summary_len: usize,
        site_buf: [64]u8,
        site_len: usize,
    };

    var rows = std.ArrayList(Row){};
    defer rows.deinit(allocator);

    var scanned: usize = 0;
    var job_cells: usize = 0;
    // Per-bucket counts, indexed parallel to BUCKETS.
    var counts = [_]usize{0} ** BUCKETS.len;
    var seen = std.AutoHashMap([32]u8, void).init(allocator);
    defer seen.deinit();

    const cursor = store.cursorOpen() catch {
        return verb_dispatcher.DispatchError.walker_failed;
    };
    defer store.cursorClose(cursor);

    while (true) {
        const maybe_cell = store.cursorPull(cursor) catch {
            return verb_dispatcher.DispatchError.walker_failed;
        };
        const cell = maybe_cell orelse break;
        scanned += 1;

        const dec = substrate_entity.decodeEntity(cell);
        if (!dec.magic_ok) continue;
        if (!std.mem.eql(u8, &dec.type_hash, &job_type_hash)) continue;
        job_cells += 1;

        var cid: [32]u8 = undefined;
        Sha256.hash(cell, &cid, .{});
        if (seen.contains(cid)) continue;
        seen.put(cid, {}) catch return verb_dispatcher.DispatchError.out_of_memory;

        const payload = dec.payload;

        const st = jsonStringField(payload, "\"state\":\"") orelse "lead";
        const bucket_name = bucketFor(st) orelse continue; // progressing/terminal

        // Tally per-bucket count.
        for (BUCKETS, 0..) |b, bi| {
            if (std.mem.eql(u8, b.name, bucket_name)) {
                counts[bi] += 1;
                break;
            }
        }

        var row: Row = undefined;
        row.bucket = bucket_name;
        hexEncodeInto(&cid, &row.cell_id_hex);
        copyField(&row.state_buf, &row.state_len, st);
        copyField(&row.wo_buf, &row.wo_len, jsonStringField(payload, "\"work_order_number\":\"") orelse "—");
        copyField(&row.summary_buf, &row.summary_len, jsonStringField(payload, "\"summary\":\"") orelse "");
        copyField(&row.site_buf, &row.site_len, jsonStringField(payload, "\"site_ref\":\"") orelse "");

        if (jsonStringField(payload, "\"issuance_date\":\"")) |iso| {
            if (parseIsoDateToDays(iso)) |d| {
                row.days_in_pipeline = as_of_days - d;
                row.stale = row.days_in_pipeline >= stale_days;
                @memcpy(row.issuance_buf[0..10], iso[0..10]);
                row.issuance_len = 10;
            } else {
                // malformed issuance — treat as undated
                row.days_in_pipeline = -1;
                row.stale = false;
                row.issuance_len = 0;
            }
        } else {
            row.days_in_pipeline = -1; // undated → operator-review
            row.stale = false;
            row.issuance_len = 0;
        }

        rows.append(allocator, row) catch return verb_dispatcher.DispatchError.out_of_memory;
    }

    // Sort oldest-first (descending days_in_pipeline). Undated rows
    // (-1) sort last, which is the desired "review separately" tail.
    std.mem.sort(Row, rows.items, {}, struct {
        fn lt(_: void, a: Row, b: Row) bool {
            return a.days_in_pipeline > b.days_in_pipeline;
        }
    }.lt);

    return buildResult(allocator, as_of, stale_days, scanned, job_cells, &counts, rows.items, limit) catch |err| switch (err) {
        error.OutOfMemory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

// ─── Registration ────────────────────────────────────────────────────

pub fn registerInto(
    registry: *verb_dispatcher.Registry,
    state: *State,
) !void {
    try registry.register(.{
        .extension_id = "substrate",
        .verb = "find_pipeline_gaps",
        .walker_fn = findPipelineGapsWalker,
        .ctx = @ptrCast(state),
    });
}

// ─── Helpers ─────────────────────────────────────────────────────────

/// Find `"<key>":"<value>"` in a flat JSON object string and return
/// the value slice (no escape handling — slimJobJson values are plain
/// ASCII: dates, hex, truncated summary with no embedded quotes).
fn jsonStringField(buf: []const u8, needle: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, buf, needle) orelse return null;
    const start = idx + needle.len;
    if (start >= buf.len) return null;
    const end = std.mem.indexOfScalarPos(u8, buf, start, '"') orelse return null;
    return buf[start..end];
}

/// Civil date → days since 1970-01-01 (Howard Hinnant's algorithm).
/// Returns null on malformed input.
fn parseIsoDateToDays(s: []const u8) ?i64 {
    if (s.len != 10 or s[4] != '-' or s[7] != '-') return null;
    const y = parseInt(s[0..4]) orelse return null;
    const m = parseInt(s[5..7]) orelse return null;
    const d = parseInt(s[8..10]) orelse return null;
    if (m < 1 or m > 12 or d < 1 or d > 31) return null;
    var yy: i64 = y;
    if (m <= 2) yy -= 1;
    const era: i64 = @divFloor(if (yy >= 0) yy else yy - 399, 400);
    const yoe: i64 = yy - era * 400;
    const mp: i64 = @mod(m + 9, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn parseInt(s: []const u8) ?i64 {
    var v: i64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + @as(i64, c - '0');
    }
    return v;
}

fn copyField(dst: []u8, len: *usize, src: []const u8) void {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    len.* = n;
}

const HEX = "0123456789abcdef";
fn hexEncodeInto(bytes: *const [32]u8, out: *[64]u8) void {
    for (bytes, 0..) |b, i| {
        out[i * 2] = HEX[b >> 4];
        out[i * 2 + 1] = HEX[b & 0x0f];
    }
}

fn buildResult(
    allocator: std.mem.Allocator,
    as_of: []const u8,
    stale_days: i64,
    scanned: usize,
    job_cells: usize,
    counts: *const [BUCKETS.len]usize,
    rows: anytype,
    limit: usize,
) ![]u8 {
    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    const w = body.writer(allocator);

    try w.print(
        "{{\"as_of\":\"{s}\",\"stale_days\":{d},\"scanned\":{d},\"job_cells\":{d},\"buckets\":{{",
        .{ as_of, stale_days, scanned, job_cells },
    );
    for (BUCKETS, 0..) |b, bi| {
        if (bi > 0) try w.writeAll(",");
        try w.print("\"{s}\":{d}", .{ b.name, counts[bi] });
    }
    try w.print("}},\"gaps_total\":{d},\"gaps\":[", .{rows.len});

    const emit = @min(rows.len, limit);
    var i: usize = 0;
    while (i < emit) : (i += 1) {
        const r = rows[i];
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"cell_id\":\"{s}\",\"bucket\":\"{s}\",\"days_in_pipeline\":{d},\"stale\":{s},\"issuance\":\"",
            .{
                r.cell_id_hex,
                r.bucket,
                r.days_in_pipeline,
                if (r.stale) "true" else "false",
            },
        );
        try w.writeAll(r.issuance_buf[0..r.issuance_len]);
        try w.writeAll("\",\"work_order\":\"");
        try writeJsonEscaped(w, r.wo_buf[0..r.wo_len]);
        try w.writeAll("\",\"state\":\"");
        try writeJsonEscaped(w, r.state_buf[0..r.state_len]);
        try w.writeAll("\",\"site_ref\":\"");
        try writeJsonEscaped(w, r.site_buf[0..r.site_len]);
        try w.writeAll("\",\"summary\":\"");
        try writeJsonEscaped(w, r.summary_buf[0..r.summary_len]);
        try w.writeAll("\"}");
    }
    try w.writeAll("]}");
    return body.toOwnedSlice(allocator);
}

fn writeJsonEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "bucketFor maps only the five pre-quote funnel states" {
    try testing.expectEqualStrings("lead_unqualified", bucketFor("lead").?);
    try testing.expectEqualStrings("qualified_unactioned", bucketFor("qualified").?);
    try testing.expectEqualStrings("visit_unscheduled", bucketFor("visit_pending").?);
    try testing.expectEqualStrings("visit_upcoming", bucketFor("visit_scheduled").?);
    try testing.expectEqualStrings("visited_unquoted", bucketFor("visited").?);
    // Progressing / terminal states are NOT pipeline gaps.
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("quoted"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("scheduled"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("in_progress"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("completed"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("invoiced"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("paid"));
    try testing.expectEqual(@as(?[]const u8, null), bucketFor("closed"));
}

test "parseIsoDateToDays: epoch + staleness arithmetic" {
    try testing.expectEqual(@as(?i64, 0), parseIsoDateToDays("1970-01-01"));
    const issued = parseIsoDateToDays("2026-05-01").?;
    const sunday = parseIsoDateToDays("2026-05-16").?;
    // 15 days in pipeline as of the Sunday review.
    try testing.expectEqual(@as(i64, 15), sunday - issued);
    // Exact 7-day staleness boundary.
    const d0 = parseIsoDateToDays("2026-05-09").?;
    const d7 = parseIsoDateToDays("2026-05-16").?;
    try testing.expectEqual(d0 + 7, d7);
}

test "jsonStringField extracts flat slim-job values" {
    const j = "{\"intent\":\"job\",\"summary\":\"pergola quote\",\"state\":\"qualified\",\"issuance_date\":\"2026-05-01\"}";
    try testing.expectEqualStrings("qualified", jsonStringField(j, "\"state\":\"").?);
    try testing.expectEqualStrings("2026-05-01", jsonStringField(j, "\"issuance_date\":\"").?);
    try testing.expectEqual(@as(?[]const u8, null), jsonStringField(j, "\"due_date\":\""));
}

test "findPipelineGapsWalker: store_unavailable graceful path" {
    var state = State{}; // no cell_store
    const params = "{\"as_of\":\"2026-05-16\"}";
    const res = try findPipelineGapsWalker(testing.allocator, &state, params);
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"store_unavailable\":true") != null);
}

test "findPipelineGapsWalker: rejects missing/short as_of" {
    var state = State{};
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        findPipelineGapsWalker(testing.allocator, &state, "{}"),
    );
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        findPipelineGapsWalker(testing.allocator, &state, "{\"as_of\":\"2026-5-16\"}"),
    );
}

test "registerInto wires (substrate, find_pipeline_gaps)" {
    var state = State{};
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerInto(&reg, &state);
    const res = try reg.dispatch(
        testing.allocator,
        "substrate",
        "find_pipeline_gaps",
        "{\"as_of\":\"2026-05-16\"}",
    );
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"gaps\":[]") != null);
}

```
