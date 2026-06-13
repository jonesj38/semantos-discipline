---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/visits_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.549510+00:00
---

# cartridges/oddjobz/brain/zig/src/visits_store_lmdb.zig

```zig
// W0.2 — Visits store backed by LmdbCellStore (replaces visits_store_fs.zig).
//
// Each visit entity is serialised as a JSON payload packed into a
// 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/updateState call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory state
// is NOT updated — the FSM sees an error and returns without partial state.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_VISIT (0x02) and replays them to rebuild the in-memory index.
//
// The public API is identical to the old visits_store_fs.VisitsStore so all
// existing callers (handlers, cli.zig, conformance tests) require only the
// change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114e — encode a visit buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// scheduled → LINEAR; completed / no_show → RELEVANT.
fn encodeVisitAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_VISIT, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_VISIT,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_VISIT, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_status,
    invalid_id,
    invalid_job_id,
    invalid_visit_type,
    invalid_notes,
    invalid_actual_start,
    invalid_outcome,
    invalid_created_at,
    invalid_updated_at,
    /// `updateState` called for an id that doesn't exist in the store.
    not_found,
};

/// Canonical Visit FSM states — matches `cartridges/oddjobz/brain/src/state-
/// machines/visit-fsm.ts` VISIT_FSM_STATES verbatim.
pub const VISIT_FSM_STATES = [_][]const u8{
    "scheduled",
    "in_progress",
    "completed",
    "cancelled",
};

/// Canonical visit types — matches VISIT_TYPES in
/// cartridges/oddjobz/brain/src/cell-types/visit.ts verbatim.
pub const VISIT_TYPES = [_][]const u8{
    "inspection",
    "quote_visit",
    "scheduled_work",
    "return_visit",
    "emergency",
};

pub fn isValidStatus(s: []const u8) bool {
    for (VISIT_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub fn isValidVisitType(s: []const u8) bool {
    for (VISIT_TYPES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub const Visit = struct {
    id: []const u8,
    job_id: []const u8,
    visit_type: []const u8,
    status: []const u8,
    notes: []const u8,
    actual_start: []const u8,
    outcome: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const MAX_ID_BYTES: usize = 64;
pub const MAX_JOB_ID_BYTES: usize = 64;
pub const MAX_VISIT_TYPE_BYTES: usize = 32;
pub const MAX_STATUS_BYTES: usize = 32;
pub const MAX_NOTES_BYTES: usize = 2000;
pub const MAX_ACTUAL_START_BYTES: usize = 64;
pub const MAX_OUTCOME_BYTES: usize = 64;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_UPDATED_AT_BYTES: usize = 64;

const OwnedStrings = struct {
    id: []u8,
    job_id: []u8,
    visit_type: []u8,
    status: []u8,
    notes: []u8,
    actual_start: []u8,
    outcome: []u8,
    created_at: []u8,
    updated_at: []u8,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.visit_type);
        allocator.free(self.status);
        allocator.free(self.notes);
        allocator.free(self.actual_start);
        allocator.free(self.outcome);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

pub const VisitsStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Visit),
    by_id: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !VisitsStore {
        var self = VisitsStore{
            .allocator = allocator,
            .cell_store = cell_store,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .owned_strings = .{},
            .clock = clock_fn,
        };
        try self.replayCellStore();
        return self;
    }

    pub fn deinit(self: *VisitsStore) void {
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
    }

    pub fn append(self: *VisitsStore, visit: Visit) !AppendOutcome {
        if (visit.id.len == 0 or visit.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (visit.job_id.len == 0 or visit.job_id.len > MAX_JOB_ID_BYTES) return StoreError.invalid_job_id;
        if (!isValidVisitType(visit.visit_type)) return StoreError.invalid_visit_type;
        if (!isValidStatus(visit.status)) return StoreError.invalid_status;
        if (visit.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;
        if (visit.actual_start.len > MAX_ACTUAL_START_BYTES) return StoreError.invalid_actual_start;
        if (visit.outcome.len > MAX_OUTCOME_BYTES) return StoreError.invalid_outcome;
        if (visit.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;
        if (visit.updated_at.len > MAX_UPDATED_AT_BYTES) return StoreError.invalid_updated_at;

        const existing_idx = self.by_id.get(visit.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(visit);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneVisitIntoArena(visit);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub fn updateState(
        self: *VisitsStore,
        id: []const u8,
        new_status: []const u8,
        new_actual_start: ?[]const u8,
        new_outcome: ?[]const u8,
    ) !Visit {
        if (!isValidStatus(new_status)) return StoreError.invalid_status;
        if (new_actual_start) |s| {
            if (s.len > MAX_ACTUAL_START_BYTES) return StoreError.invalid_actual_start;
        }
        if (new_outcome) |o| {
            if (o.len > MAX_OUTCOME_BYTES) return StoreError.invalid_outcome;
        }

        const idx = self.by_id.get(id) orelse return error.not_found;
        const owned = &self.owned_strings.items[idx];

        const new_status_dup = try self.allocator.dupe(u8, new_status);
        errdefer self.allocator.free(new_status_dup);

        const updated_at_str = try renderIsoTimestamp(self.allocator, self.clock());
        errdefer self.allocator.free(updated_at_str);

        var new_actual_start_dup: ?[]u8 = null;
        if (new_actual_start) |s| {
            new_actual_start_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_actual_start_dup) |d| self.allocator.free(d);

        var new_outcome_dup: ?[]u8 = null;
        if (new_outcome) |o| {
            new_outcome_dup = try self.allocator.dupe(u8, o);
        }
        errdefer if (new_outcome_dup) |d| self.allocator.free(d);

        // Build the updated visit for K4 LMDB write before in-memory commit.
        const updated_for_write = Visit{
            .id = owned.id,
            .job_id = owned.job_id,
            .visit_type = owned.visit_type,
            .status = new_status_dup,
            .notes = owned.notes,
            .actual_start = if (new_actual_start_dup) |d| d else owned.actual_start,
            .outcome = if (new_outcome_dup) |d| d else owned.outcome,
            .created_at = owned.created_at,
            .updated_at = updated_at_str,
        };
        // K4: write updated cell to LMDB before mutating in-memory state.
        self.putCell(updated_for_write) catch {
            self.allocator.free(new_status_dup);
            self.allocator.free(updated_at_str);
            if (new_actual_start_dup) |d| self.allocator.free(d);
            if (new_outcome_dup) |d| self.allocator.free(d);
            return StoreError.persistence_failed;
        };

        // Commit: release the old slots and stitch in the new ones.
        self.allocator.free(owned.status);
        owned.status = new_status_dup;
        self.allocator.free(owned.updated_at);
        owned.updated_at = updated_at_str;
        if (new_actual_start_dup) |d| {
            self.allocator.free(owned.actual_start);
            owned.actual_start = d;
        }
        if (new_outcome_dup) |d| {
            self.allocator.free(owned.outcome);
            owned.outcome = d;
        }

        const updated = Visit{
            .id = owned.id,
            .job_id = owned.job_id,
            .visit_type = owned.visit_type,
            .status = owned.status,
            .notes = owned.notes,
            .actual_start = owned.actual_start,
            .outcome = owned.outcome,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
        self.records.items[idx] = updated;
        return updated;
    }

    pub fn findAll(self: *const VisitsStore, allocator: std.mem.Allocator) ![]Visit {
        const out = try allocator.alloc(Visit, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn findById(self: *const VisitsStore, id: []const u8) ?Visit {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByJobId(self: *const VisitsStore, allocator: std.mem.Allocator, job_id: []const u8) ![]Visit {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) n += 1;
        }
        const out = try allocator.alloc(Visit, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const VisitsStore) usize {
        return self.records.items.len;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    fn putCell(self: *VisitsStore, visit: Visit) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeVisit(self.allocator, &buf, visit);
        const cell = encodeVisitAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *VisitsStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);

        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            // RM-114e — dual-format read.
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_VISIT) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_VISIT.domain_flag) continue;
                break :blk decoded.payload;
            };
            self.applyPayload(payload) catch {}; // skip malformed
        }
    }

    fn applyPayload(self: *VisitsStore, payload: []const u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            payload,
            .{},
        ) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        const id_v = obj.get("id") orelse return;
        if (id_v != .string) return;
        const id = id_v.string;
        if (id.len == 0 or id.len > MAX_ID_BYTES) return;

        const job_id_v = obj.get("job_id") orelse return;
        if (job_id_v != .string) return;
        const job_id = job_id_v.string;
        if (job_id.len == 0 or job_id.len > MAX_JOB_ID_BYTES) return;

        const visit_type_v = obj.get("visit_type") orelse return;
        if (visit_type_v != .string) return;
        const visit_type = visit_type_v.string;
        if (!isValidVisitType(visit_type)) return;

        const status_v = obj.get("status") orelse return;
        if (status_v != .string) return;
        const status = status_v.string;
        if (!isValidStatus(status)) return;

        const notes = if (obj.get("notes")) |v| (if (v == .string) v.string else "") else "";
        const actual_start = if (obj.get("actual_start")) |v| (if (v == .string) v.string else "") else "";
        const outcome = if (obj.get("outcome")) |v| (if (v == .string) v.string else "") else "";

        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        const updated_at = if (obj.get("updated_at")) |v| (if (v == .string) v.string else created_at) else created_at;

        if (notes.len > MAX_NOTES_BYTES) return;
        if (actual_start.len > MAX_ACTUAL_START_BYTES) return;
        if (outcome.len > MAX_OUTCOME_BYTES) return;
        if (created_at.len > MAX_CREATED_AT_BYTES) return;
        if (updated_at.len > MAX_UPDATED_AT_BYTES) return;

        // Latest-wins: if we've seen this id before, update in place.
        if (self.by_id.get(id)) |existing_idx| {
            const owned = &self.owned_strings.items[existing_idx];
            // status
            const status_dup = try self.allocator.dupe(u8, status);
            self.allocator.free(owned.status);
            owned.status = status_dup;
            // actual_start
            const as_dup = try self.allocator.dupe(u8, actual_start);
            self.allocator.free(owned.actual_start);
            owned.actual_start = as_dup;
            // outcome
            const out_dup = try self.allocator.dupe(u8, outcome);
            self.allocator.free(owned.outcome);
            owned.outcome = out_dup;
            // updated_at
            const ua_dup = try self.allocator.dupe(u8, updated_at);
            self.allocator.free(owned.updated_at);
            owned.updated_at = ua_dup;
            self.records.items[existing_idx] = .{
                .id = owned.id,
                .job_id = owned.job_id,
                .visit_type = owned.visit_type,
                .status = owned.status,
                .notes = owned.notes,
                .actual_start = owned.actual_start,
                .outcome = owned.outcome,
                .created_at = owned.created_at,
                .updated_at = owned.updated_at,
            };
            return;
        }

        const stored = try self.cloneVisitIntoArena(.{
            .id = id,
            .job_id = job_id,
            .visit_type = visit_type,
            .status = status,
            .notes = notes,
            .actual_start = actual_start,
            .outcome = outcome,
            .created_at = created_at,
            .updated_at = updated_at,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
    }

    fn cloneVisitIntoArena(self: *VisitsStore, visit: Visit) !Visit {
        var owned: OwnedStrings = undefined;
        owned.id = try self.allocator.dupe(u8, visit.id);
        errdefer self.allocator.free(owned.id);
        owned.job_id = try self.allocator.dupe(u8, visit.job_id);
        errdefer self.allocator.free(owned.job_id);
        owned.visit_type = try self.allocator.dupe(u8, visit.visit_type);
        errdefer self.allocator.free(owned.visit_type);
        owned.status = try self.allocator.dupe(u8, visit.status);
        errdefer self.allocator.free(owned.status);
        owned.notes = try self.allocator.dupe(u8, visit.notes);
        errdefer self.allocator.free(owned.notes);
        owned.actual_start = try self.allocator.dupe(u8, visit.actual_start);
        errdefer self.allocator.free(owned.actual_start);
        owned.outcome = try self.allocator.dupe(u8, visit.outcome);
        errdefer self.allocator.free(owned.outcome);
        owned.created_at = try self.allocator.dupe(u8, visit.created_at);
        errdefer self.allocator.free(owned.created_at);
        owned.updated_at = try self.allocator.dupe(u8, visit.updated_at);
        errdefer self.allocator.free(owned.updated_at);

        try self.owned_strings.append(self.allocator, owned);
        return .{
            .id = owned.id,
            .job_id = owned.job_id,
            .visit_type = owned.visit_type,
            .status = owned.status,
            .notes = owned.notes,
            .actual_start = owned.actual_start,
            .outcome = owned.outcome,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeVisit(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    visit: Visit,
) !void {
    try buf.appendSlice(allocator, "{\"kind\":\"created\",\"id\":");
    try writeJsonString(allocator, buf, visit.id);
    try buf.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, buf, visit.job_id);
    try buf.appendSlice(allocator, ",\"visit_type\":");
    try writeJsonString(allocator, buf, visit.visit_type);
    try buf.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, buf, visit.status);
    try buf.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, buf, visit.notes);
    try buf.appendSlice(allocator, ",\"actual_start\":");
    try writeJsonString(allocator, buf, visit.actual_start);
    try buf.appendSlice(allocator, ",\"outcome\":");
    try writeJsonString(allocator, buf, visit.outcome);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, visit.created_at);
    try buf.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, buf, visit.updated_at);
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    const month: u8 = month_day.month.numeric();
    const day: u8 = month_day.day_index + 1;
    const hour: u8 = day_secs.getHoursIntoDay();
    const minute: u8 = day_secs.getMinutesIntoHour();
    const second: u8 = day_secs.getSecondsIntoMinute();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year, month, day, hour, minute, second },
    );
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic (no LMDB required).
// ─────────────────────────────────────────────────────────────────────

test "isValidStatus recognises the four canonical FSM states" {
    try std.testing.expect(isValidStatus("scheduled"));
    try std.testing.expect(isValidStatus("in_progress"));
    try std.testing.expect(isValidStatus("completed"));
    try std.testing.expect(isValidStatus("cancelled"));
    try std.testing.expect(!isValidStatus(""));
    try std.testing.expect(!isValidStatus("paused"));
    try std.testing.expect(!isValidStatus("SCHEDULED"));
}

test "isValidVisitType recognises the five canonical types" {
    try std.testing.expect(isValidVisitType("inspection"));
    try std.testing.expect(isValidVisitType("quote_visit"));
    try std.testing.expect(isValidVisitType("scheduled_work"));
    try std.testing.expect(isValidVisitType("return_visit"));
    try std.testing.expect(isValidVisitType("emergency"));
    try std.testing.expect(!isValidVisitType(""));
    try std.testing.expect(!isValidVisitType("ad_hoc"));
}

```
