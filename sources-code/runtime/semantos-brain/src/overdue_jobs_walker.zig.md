---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/overdue_jobs_walker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.242159+00:00
---

# runtime/semantos-brain/src/overdue_jobs_walker.zig

```zig
// D-RTC follow-up — `substrate.find_overdue_jobs` walker.
//
// Reference:
//   apps/legacy-cli/src/diag-overdue.ts (the local-script prototype
//     this replaces with an on-host capability)
//   runtime/semantos-brain/src/entity_encode_walker.zig (the walker
//     pattern + State/registerInto shape)
//   runtime/semantos-brain/src/substrate_entity.zig (decodeEntity +
//     SPEC_JOB type-hash + cell payload shape)
//
// Why this exists:
//
//   The reingest mints TAG_JOB cells into the substrate cell store
//   carrying due_date / issuance_date / state in their payload JSON.
//   "Which jobs am I overdue on" was a local TS script
//   (diag-overdue.ts) the operator had to run by hand against the
//   receipt store. This walker makes it an on-host dispatcher verb:
//   pask-adjacent systems + the PWA chat resolver call
//   verb.dispatch({extensionId:"substrate", verb:"find_overdue_jobs",
//   params:{as_of:"YYYY-MM-DD", sla_days?:14}}) and get the ranked
//   overdue worklist back, walked straight off the typed cells — no
//   external script, no receipt-store round-trip.
//
// Algorithm (mirrors diag-overdue.ts):
//   • cursor-walk the entity cell store
//   • decodeEntity; keep cells whose type_hash == computeTypeHash(
//     SPEC_JOB) and whose magic is the substrate format
//   • effective due = payload.due_date, else payload.issuance_date +
//     sla_days (default 14 — Clever/RJR "attend within N days")
//   • overdue = effective_due < as_of AND state ∉ {completed,
//     closed, paid}
//   • dedupe on cell_id (job-dedupe already collapses dupes onto one
//     cell, but a cursor can surface the same cell once per page
//     boundary in some stores — defensive)
//   • return JSON ranked most-overdue-first
//
// Wire shape (params):
//   { "as_of": "2026-05-16", "sla_days": 14, "limit": 200 }
// Result:
//   { "as_of":"…","sla_days":14,"scanned":N,"job_cells":M,
//     "overdue":[ {cell_id,due,due_source,days_overdue,
//                  work_order,state,summary,site_ref} … ] }

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const substrate_entity = @import("substrate_entity");
const cell_store_mod = @import("cell_store");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub const State = struct {
    /// Entity cell store. When null the walker returns an empty
    /// overdue set with `store_unavailable:true` so callers degrade
    /// gracefully rather than erroring.
    cell_store: ?*const cell_store_mod.CellStore = null,
};

const DEFAULT_SLA_DAYS: i64 = 14;
const DEFAULT_LIMIT: usize = 200;
const HARD_LIMIT: usize = 1000;

// ─── Walker ──────────────────────────────────────────────────────────

pub fn findOverdueJobsWalker(
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

    const sla_days: i64 = blk: {
        if (obj.get("sla_days")) |v| {
            if (v == .integer and v.integer > 0 and v.integer < 3650) break :blk v.integer;
        }
        break :blk DEFAULT_SLA_DAYS;
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
            "{\"store_unavailable\":true,\"scanned\":0,\"job_cells\":0,\"overdue\":[]}",
        ) catch verb_dispatcher.DispatchError.out_of_memory;
    };

    const job_type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_JOB);

    const Row = struct {
        cell_id_hex: [64]u8,
        due_days: i64,
        days_overdue: i64,
        due_source: enum { due_date, issuance_sla },
        // small fixed copies — payload fields are short (slimJobJson
        // caps summary at 55, WO is < 32, site_ref is 64 hex).
        due_buf: [10]u8,
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

        // state ∉ {completed, closed, paid} → still open
        const st = jsonStringField(payload, "\"state\":\"") orelse "";
        if (std.mem.eql(u8, st, "completed") or
            std.mem.eql(u8, st, "closed") or
            std.mem.eql(u8, st, "paid")) continue;

        // effective due
        var due_days: i64 = undefined;
        var due_str: []const u8 = undefined;
        var due_source: @TypeOf(@as(Row, undefined).due_source) = .due_date;
        if (jsonStringField(payload, "\"due_date\":\"")) |dd| {
            const d = parseIsoDateToDays(dd) orelse continue;
            due_days = d;
            due_str = dd;
        } else if (jsonStringField(payload, "\"issuance_date\":\"")) |iso| {
            const d = parseIsoDateToDays(iso) orelse continue;
            due_days = d + sla_days;
            due_str = iso; // surfaced verbatim; due_source flags the +SLA
            due_source = .issuance_sla;
        } else {
            continue; // undated — cannot age; operator-review bucket
        }

        if (due_days >= as_of_days) continue; // not overdue yet

        var row: Row = undefined;
        row.due_days = due_days;
        row.days_overdue = as_of_days - due_days;
        row.due_source = due_source;
        hexEncodeInto(&cid, &row.cell_id_hex);
        // due_str is always a valid 10-char ISO date here (both
        // branches went through parseIsoDateToDays).
        @memcpy(row.due_buf[0..10], due_str[0..10]);
        copyField(&row.wo_buf, &row.wo_len, jsonStringField(payload, "\"work_order_number\":\"") orelse "—");
        copyField(&row.state_buf, &row.state_len, if (st.len > 0) st else "lead");
        copyField(&row.summary_buf, &row.summary_len, jsonStringField(payload, "\"summary\":\"") orelse "");
        copyField(&row.site_buf, &row.site_len, jsonStringField(payload, "\"site_ref\":\"") orelse "");
        rows.append(allocator, row) catch return verb_dispatcher.DispatchError.out_of_memory;
    }

    // Sort most-overdue-first (descending days_overdue).
    std.mem.sort(Row, rows.items, {}, struct {
        fn lt(_: void, a: Row, b: Row) bool {
            return a.days_overdue > b.days_overdue;
        }
    }.lt);

    return buildResult(allocator, as_of, sla_days, scanned, job_cells, rows.items, limit) catch |err| switch (err) {
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
        .verb = "find_overdue_jobs",
        .walker_fn = findOverdueJobsWalker,
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
    sla_days: i64,
    scanned: usize,
    job_cells: usize,
    rows: anytype,
    limit: usize,
) ![]u8 {
    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    const w = body.writer(allocator);

    try w.print(
        "{{\"as_of\":\"{s}\",\"sla_days\":{d},\"scanned\":{d},\"job_cells\":{d},\"overdue_total\":{d},\"overdue\":[",
        .{ as_of, sla_days, scanned, job_cells, rows.len },
    );

    const emit = @min(rows.len, limit);
    var i: usize = 0;
    while (i < emit) : (i += 1) {
        const r = rows[i];
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"cell_id\":\"{s}\",\"days_overdue\":{d},\"due\":\"{s}\",\"due_source\":\"{s}\",\"work_order\":\"",
            .{
                r.cell_id_hex,
                r.days_overdue,
                r.due_buf[0..10],
                if (r.due_source == .due_date) "due_date" else "issuance+sla",
            },
        );
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

test "parseIsoDateToDays: epoch + invariants" {
    // Epoch anchor.
    try testing.expectEqual(@as(?i64, 0), parseIsoDateToDays("1970-01-01"));
    try testing.expectEqual(@as(?i64, 1), parseIsoDateToDays("1970-01-02"));
    try testing.expectEqual(@as(?i64, 365), parseIsoDateToDays("1971-01-01"));
    // Chronological ordering (the only property the walker relies on).
    const a = parseIsoDateToDays("2025-08-06").?;
    const b = parseIsoDateToDays("2026-05-16").?;
    try testing.expect(b > a);
    // 14-day SLA arithmetic is exact day-count addition.
    const d0 = parseIsoDateToDays("2025-12-29").?;
    const d14 = parseIsoDateToDays("2026-01-12").?;
    try testing.expectEqual(d0 + 14, d14);
}

test "parseIsoDateToDays: rejects malformed" {
    try testing.expectEqual(@as(?i64, null), parseIsoDateToDays("2026/05/16"));
    try testing.expectEqual(@as(?i64, null), parseIsoDateToDays("2026-13-01"));
    try testing.expectEqual(@as(?i64, null), parseIsoDateToDays("not-a-date"));
    try testing.expectEqual(@as(?i64, null), parseIsoDateToDays("2026-05-1"));
}

test "jsonStringField extracts flat values" {
    const j = "{\"due_date\":\"2025-08-06\",\"state\":\"lead\",\"site_ref\":\"abc\"}";
    try testing.expectEqualStrings("2025-08-06", jsonStringField(j, "\"due_date\":\"").?);
    try testing.expectEqualStrings("lead", jsonStringField(j, "\"state\":\"").?);
    try testing.expectEqualStrings("abc", jsonStringField(j, "\"site_ref\":\"").?);
    try testing.expectEqual(@as(?[]const u8, null), jsonStringField(j, "\"missing\":\""));
}

test "findOverdueJobsWalker: store_unavailable graceful path" {
    var state = State{}; // no cell_store
    const params = "{\"as_of\":\"2026-05-16\"}";
    const res = try findOverdueJobsWalker(testing.allocator, &state, params);
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"store_unavailable\":true") != null);
}

test "findOverdueJobsWalker: rejects missing/short as_of" {
    var state = State{};
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        findOverdueJobsWalker(testing.allocator, &state, "{}"),
    );
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        findOverdueJobsWalker(testing.allocator, &state, "{\"as_of\":\"2026-5-16\"}"),
    );
}

test "registerInto wires (substrate, find_overdue_jobs)" {
    var state = State{};
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerInto(&reg, &state);
    const res = try reg.dispatch(
        testing.allocator,
        "substrate",
        "find_overdue_jobs",
        "{\"as_of\":\"2026-05-16\"}",
    );
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"overdue\":[]") != null);
}

```
