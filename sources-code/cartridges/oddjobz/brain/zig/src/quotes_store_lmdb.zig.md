---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/quotes_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.550276+00:00
---

# cartridges/oddjobz/brain/zig/src/quotes_store_lmdb.zig

```zig
// W0.2 — Quotes store backed by LmdbCellStore (replaces quotes_store_fs.zig).
//
// Each quote entity is serialised as a JSON payload packed into a
// 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/updateState call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory state
// is NOT updated.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_QUOTE (0x03) and replays them to rebuild the in-memory index.
//
// The public API is identical to the old quotes_store_fs.QuotesStore so all
// existing callers (handlers, cli.zig, conformance tests) require only the
// change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114f — encode a quote buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// open → LINEAR; accepted / declined / expired → RELEVANT.
fn encodeQuoteAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_QUOTE, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_QUOTE,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_QUOTE, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_status,
    invalid_id,
    invalid_job_id,
    invalid_notes,
    invalid_cost,
    invalid_accepted_at,
    invalid_rejected_at,
    invalid_created_at,
    invalid_updated_at,
    /// `updateState` called for an id that doesn't exist in the store.
    not_found,
};

/// Canonical Quote FSM states — matches `cartridges/oddjobz/brain/src/state-
/// machines/quote-fsm.ts` QUOTE_FSM_STATES verbatim.
pub const QUOTE_FSM_STATES = [_][]const u8{
    "draft",
    "presented",
    "accepted",
    "rejected",
    "expired",
    "superseded",
};

pub fn isValidStatus(s: []const u8) bool {
    for (QUOTE_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub const Quote = struct {
    id: []const u8,
    job_id: []const u8,
    status: []const u8,
    cost_min: i64,
    cost_max: i64,
    notes: []const u8,
    accepted_at: []const u8,
    rejected_at: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const MAX_ID_BYTES: usize = 64;
pub const MAX_JOB_ID_BYTES: usize = 64;
pub const MAX_STATUS_BYTES: usize = 32;
pub const MAX_NOTES_BYTES: usize = 2000;
pub const MAX_ACCEPTED_AT_BYTES: usize = 64;
pub const MAX_REJECTED_AT_BYTES: usize = 64;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_UPDATED_AT_BYTES: usize = 64;

const OwnedStrings = struct {
    id: []u8,
    job_id: []u8,
    status: []u8,
    notes: []u8,
    accepted_at: []u8,
    rejected_at: []u8,
    created_at: []u8,
    updated_at: []u8,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.status);
        allocator.free(self.notes);
        allocator.free(self.accepted_at);
        allocator.free(self.rejected_at);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

pub const QuotesStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Quote),
    by_id: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !QuotesStore {
        var self = QuotesStore{
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

    pub fn deinit(self: *QuotesStore) void {
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
    }

    pub fn append(self: *QuotesStore, quote: Quote) !AppendOutcome {
        if (quote.id.len == 0 or quote.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (quote.job_id.len == 0 or quote.job_id.len > MAX_JOB_ID_BYTES) return StoreError.invalid_job_id;
        if (!isValidStatus(quote.status)) return StoreError.invalid_status;
        if (quote.cost_min < 0 or quote.cost_max < 0) return StoreError.invalid_cost;
        if (quote.cost_max < quote.cost_min) return StoreError.invalid_cost;
        if (quote.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;
        if (quote.accepted_at.len > MAX_ACCEPTED_AT_BYTES) return StoreError.invalid_accepted_at;
        if (quote.rejected_at.len > MAX_REJECTED_AT_BYTES) return StoreError.invalid_rejected_at;
        if (quote.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;
        if (quote.updated_at.len > MAX_UPDATED_AT_BYTES) return StoreError.invalid_updated_at;

        const existing_idx = self.by_id.get(quote.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(quote);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneQuoteIntoArena(quote);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub fn updateState(
        self: *QuotesStore,
        id: []const u8,
        new_status: []const u8,
        new_accepted_at: ?[]const u8,
        new_rejected_at: ?[]const u8,
    ) !Quote {
        if (!isValidStatus(new_status)) return StoreError.invalid_status;
        if (new_accepted_at) |s| {
            if (s.len > MAX_ACCEPTED_AT_BYTES) return StoreError.invalid_accepted_at;
        }
        if (new_rejected_at) |r| {
            if (r.len > MAX_REJECTED_AT_BYTES) return StoreError.invalid_rejected_at;
        }

        const idx = self.by_id.get(id) orelse return error.not_found;
        const owned = &self.owned_strings.items[idx];

        const new_status_dup = try self.allocator.dupe(u8, new_status);
        errdefer self.allocator.free(new_status_dup);

        const updated_at_str = try renderIsoTimestamp(self.allocator, self.clock());
        errdefer self.allocator.free(updated_at_str);

        var new_accepted_at_dup: ?[]u8 = null;
        if (new_accepted_at) |s| {
            new_accepted_at_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_accepted_at_dup) |d| self.allocator.free(d);

        var new_rejected_at_dup: ?[]u8 = null;
        if (new_rejected_at) |r| {
            new_rejected_at_dup = try self.allocator.dupe(u8, r);
        }
        errdefer if (new_rejected_at_dup) |d| self.allocator.free(d);

        // Build updated quote for K4 LMDB write before in-memory commit.
        const updated_for_write = Quote{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = new_status_dup,
            .cost_min = self.records.items[idx].cost_min,
            .cost_max = self.records.items[idx].cost_max,
            .notes = owned.notes,
            .accepted_at = if (new_accepted_at_dup) |d| d else owned.accepted_at,
            .rejected_at = if (new_rejected_at_dup) |d| d else owned.rejected_at,
            .created_at = owned.created_at,
            .updated_at = updated_at_str,
        };
        self.putCell(updated_for_write) catch {
            self.allocator.free(new_status_dup);
            self.allocator.free(updated_at_str);
            if (new_accepted_at_dup) |d| self.allocator.free(d);
            if (new_rejected_at_dup) |d| self.allocator.free(d);
            return StoreError.persistence_failed;
        };

        // Commit: release the old slots and stitch in the new ones.
        self.allocator.free(owned.status);
        owned.status = new_status_dup;
        self.allocator.free(owned.updated_at);
        owned.updated_at = updated_at_str;
        if (new_accepted_at_dup) |d| {
            self.allocator.free(owned.accepted_at);
            owned.accepted_at = d;
        }
        if (new_rejected_at_dup) |d| {
            self.allocator.free(owned.rejected_at);
            owned.rejected_at = d;
        }

        const updated = Quote{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = owned.status,
            .cost_min = self.records.items[idx].cost_min,
            .cost_max = self.records.items[idx].cost_max,
            .notes = owned.notes,
            .accepted_at = owned.accepted_at,
            .rejected_at = owned.rejected_at,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
        self.records.items[idx] = updated;
        return updated;
    }

    pub fn findAll(self: *const QuotesStore, allocator: std.mem.Allocator) ![]Quote {
        const out = try allocator.alloc(Quote, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn findById(self: *const QuotesStore, id: []const u8) ?Quote {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByJobId(self: *const QuotesStore, allocator: std.mem.Allocator, job_id: []const u8) ![]Quote {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) n += 1;
        }
        const out = try allocator.alloc(Quote, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const QuotesStore) usize {
        return self.records.items.len;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    fn putCell(self: *QuotesStore, quote: Quote) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeQuote(self.allocator, &buf, quote);
        const cell = encodeQuoteAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *QuotesStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);

        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_QUOTE) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_QUOTE.domain_flag) continue;
                break :blk decoded.payload;
            };
            self.applyPayload(payload) catch {}; // skip malformed
        }
    }

    fn applyPayload(self: *QuotesStore, payload: []const u8) !void {
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

        const status_v = obj.get("status") orelse return;
        if (status_v != .string) return;
        const status = status_v.string;
        if (!isValidStatus(status)) return;

        const cost_min: i64 = if (obj.get("cost_min")) |v| (if (v == .integer) v.integer else 0) else 0;
        const cost_max: i64 = if (obj.get("cost_max")) |v| (if (v == .integer) v.integer else 0) else 0;
        if (cost_min < 0 or cost_max < 0) return;
        if (cost_max < cost_min) return;

        const notes = if (obj.get("notes")) |v| (if (v == .string) v.string else "") else "";
        const accepted_at = if (obj.get("accepted_at")) |v| (if (v == .string) v.string else "") else "";
        const rejected_at = if (obj.get("rejected_at")) |v| (if (v == .string) v.string else "") else "";

        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        const updated_at = if (obj.get("updated_at")) |v| (if (v == .string) v.string else created_at) else created_at;

        if (notes.len > MAX_NOTES_BYTES) return;
        if (accepted_at.len > MAX_ACCEPTED_AT_BYTES) return;
        if (rejected_at.len > MAX_REJECTED_AT_BYTES) return;
        if (created_at.len > MAX_CREATED_AT_BYTES) return;
        if (updated_at.len > MAX_UPDATED_AT_BYTES) return;

        // Latest-wins: if we've seen this id before, update in place.
        if (self.by_id.get(id)) |existing_idx| {
            const owned = &self.owned_strings.items[existing_idx];
            const status_dup = try self.allocator.dupe(u8, status);
            self.allocator.free(owned.status);
            owned.status = status_dup;
            const aa_dup = try self.allocator.dupe(u8, accepted_at);
            self.allocator.free(owned.accepted_at);
            owned.accepted_at = aa_dup;
            const ra_dup = try self.allocator.dupe(u8, rejected_at);
            self.allocator.free(owned.rejected_at);
            owned.rejected_at = ra_dup;
            const ua_dup = try self.allocator.dupe(u8, updated_at);
            self.allocator.free(owned.updated_at);
            owned.updated_at = ua_dup;
            self.records.items[existing_idx] = .{
                .id = owned.id,
                .job_id = owned.job_id,
                .status = owned.status,
                .cost_min = cost_min,
                .cost_max = cost_max,
                .notes = owned.notes,
                .accepted_at = owned.accepted_at,
                .rejected_at = owned.rejected_at,
                .created_at = owned.created_at,
                .updated_at = owned.updated_at,
            };
            return;
        }

        const stored = try self.cloneQuoteIntoArena(.{
            .id = id,
            .job_id = job_id,
            .status = status,
            .cost_min = cost_min,
            .cost_max = cost_max,
            .notes = notes,
            .accepted_at = accepted_at,
            .rejected_at = rejected_at,
            .created_at = created_at,
            .updated_at = updated_at,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
    }

    fn cloneQuoteIntoArena(self: *QuotesStore, quote: Quote) !Quote {
        var owned: OwnedStrings = undefined;
        owned.id = try self.allocator.dupe(u8, quote.id);
        errdefer self.allocator.free(owned.id);
        owned.job_id = try self.allocator.dupe(u8, quote.job_id);
        errdefer self.allocator.free(owned.job_id);
        owned.status = try self.allocator.dupe(u8, quote.status);
        errdefer self.allocator.free(owned.status);
        owned.notes = try self.allocator.dupe(u8, quote.notes);
        errdefer self.allocator.free(owned.notes);
        owned.accepted_at = try self.allocator.dupe(u8, quote.accepted_at);
        errdefer self.allocator.free(owned.accepted_at);
        owned.rejected_at = try self.allocator.dupe(u8, quote.rejected_at);
        errdefer self.allocator.free(owned.rejected_at);
        owned.created_at = try self.allocator.dupe(u8, quote.created_at);
        errdefer self.allocator.free(owned.created_at);
        owned.updated_at = try self.allocator.dupe(u8, quote.updated_at);
        errdefer self.allocator.free(owned.updated_at);

        try self.owned_strings.append(self.allocator, owned);
        return .{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = owned.status,
            .cost_min = quote.cost_min,
            .cost_max = quote.cost_max,
            .notes = owned.notes,
            .accepted_at = owned.accepted_at,
            .rejected_at = owned.rejected_at,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeQuote(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    quote: Quote,
) !void {
    try buf.appendSlice(allocator, "{\"kind\":\"created\",\"id\":");
    try writeJsonString(allocator, buf, quote.id);
    try buf.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, buf, quote.job_id);
    try buf.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, buf, quote.status);
    // cost_min / cost_max are integers — write raw.
    var num_buf: [32]u8 = undefined;
    const cost_min_s = std.fmt.bufPrint(&num_buf, "{d}", .{quote.cost_min}) catch unreachable;
    try buf.appendSlice(allocator, ",\"cost_min\":");
    try buf.appendSlice(allocator, cost_min_s);
    const cost_max_s = std.fmt.bufPrint(&num_buf, "{d}", .{quote.cost_max}) catch unreachable;
    try buf.appendSlice(allocator, ",\"cost_max\":");
    try buf.appendSlice(allocator, cost_max_s);
    try buf.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, buf, quote.notes);
    try buf.appendSlice(allocator, ",\"accepted_at\":");
    try writeJsonString(allocator, buf, quote.accepted_at);
    try buf.appendSlice(allocator, ",\"rejected_at\":");
    try writeJsonString(allocator, buf, quote.rejected_at);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, quote.created_at);
    try buf.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, buf, quote.updated_at);
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

test "isValidStatus recognises the six canonical Quote FSM states" {
    try std.testing.expect(isValidStatus("draft"));
    try std.testing.expect(isValidStatus("presented"));
    try std.testing.expect(isValidStatus("accepted"));
    try std.testing.expect(isValidStatus("rejected"));
    try std.testing.expect(isValidStatus("expired"));
    try std.testing.expect(isValidStatus("superseded"));
    try std.testing.expect(!isValidStatus(""));
    try std.testing.expect(!isValidStatus("pending"));
    try std.testing.expect(!isValidStatus("DRAFT"));
}

```
