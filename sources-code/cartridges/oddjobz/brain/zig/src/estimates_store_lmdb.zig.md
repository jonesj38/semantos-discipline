---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/estimates_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.547608+00:00
---

# cartridges/oddjobz/brain/zig/src/estimates_store_lmdb.zig

```zig
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2 — Estimates store backed by
// LmdbCellStore.  Cloned from `quotes_store_lmdb.zig`, minus the FSM
// linear-consume machinery: the Estimate cell type is AFFINE
// (`cartridges/oddjobz/brain/src/cell-types/estimate.ts`), so there is no
// transition table — `ack_status` is a plain field set via
// `acknowledge` (write of an `updated` cell), never a linear consume.
//
// Each estimate entity is serialised as a JSON payload packed into a
// 1024-byte substrate cell via substrate_entity.encodeEntity (legacy
// entity_cell fallback for >768B payloads) and written to
// LmdbCellStore.
//
// K4 atomicity: every append/acknowledge call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory
// state is NOT updated.
//
// On init, the store scans the cell store for all cells tagged with the
// estimate domain (substrate SPEC_ESTIMATE / legacy
// ENTITY_TAG_ESTIMATE) and replays them to rebuild the in-memory index.
//
// Live-index hook: `rescanCreatedCells` (cloned from
// jobs_store_lmdb_entity.zig, commit 956eb81) is called on a by_id miss
// in `findById` before returning null — a boot-only in-memory index
// misses estimate cells minted by a separate writer (e.g. the
// intent-action router in Slice 3) over the same shared env after the
// handler booted.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// Encode an estimate buffer as a 1024-byte cell.  Prefers substrate
/// format; legacy entity_cell fallback for >768B payloads.  Estimate is
/// AFFINE for every ack_status (no FSM), so linearity is fixed — we
/// still route through `linearityFor` for the canonical mapping.
fn encodeEstimateAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_ESTIMATE, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_ESTIMATE,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_ESTIMATE, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_ack_status,
    invalid_estimate_type,
    invalid_id,
    invalid_job_id,
    invalid_notes,
    invalid_cost,
    invalid_acknowledged_at,
    invalid_created_at,
    invalid_updated_at,
    /// `acknowledge` called for an id that doesn't exist in the store.
    not_found,
};

/// Canonical Estimate ack-status values — matches
/// `cartridges/oddjobz/brain/src/cell-types/estimate.ts` ESTIMATE_ACK_STATUSES
/// verbatim.  NOT an FSM (Estimate is AFFINE): this is a plain-field
/// enum, not a transition table.
pub const ESTIMATE_ACK_STATUSES = [_][]const u8{
    "pending",
    "accepted",
    "tentative",
    "pushback",
    "rejected",
    "wants_exact_price",
    "rate_shopping",
};

/// Canonical Estimate type values — matches ESTIMATE_TYPES in
/// `estimate.ts`.
pub const ESTIMATE_TYPES = [_][]const u8{
    "auto_rom",
    "operator_rom",
    "revised",
};

pub fn isValidAckStatus(s: []const u8) bool {
    for (ESTIMATE_ACK_STATUSES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub fn isValidEstimateType(s: []const u8) bool {
    for (ESTIMATE_TYPES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub const Estimate = struct {
    id: []const u8,
    job_id: []const u8,
    estimate_type: []const u8,
    cost_min: i64,
    cost_max: i64,
    ack_status: []const u8,
    acknowledged_at: []const u8,
    notes: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const MAX_ID_BYTES: usize = 64;
pub const MAX_JOB_ID_BYTES: usize = 64;
pub const MAX_ESTIMATE_TYPE_BYTES: usize = 32;
pub const MAX_ACK_STATUS_BYTES: usize = 32;
pub const MAX_NOTES_BYTES: usize = 2000;
pub const MAX_ACKNOWLEDGED_AT_BYTES: usize = 64;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_UPDATED_AT_BYTES: usize = 64;

const OwnedStrings = struct {
    id: []u8,
    job_id: []u8,
    estimate_type: []u8,
    ack_status: []u8,
    acknowledged_at: []u8,
    notes: []u8,
    created_at: []u8,
    updated_at: []u8,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.estimate_type);
        allocator.free(self.ack_status);
        allocator.free(self.acknowledged_at);
        allocator.free(self.notes);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

pub const EstimatesStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Estimate),
    by_id: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !EstimatesStore {
        var self = EstimatesStore{
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

    pub fn deinit(self: *EstimatesStore) void {
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
    }

    pub fn append(self: *EstimatesStore, estimate: Estimate) !AppendOutcome {
        if (estimate.id.len == 0 or estimate.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (estimate.job_id.len == 0 or estimate.job_id.len > MAX_JOB_ID_BYTES) return StoreError.invalid_job_id;
        if (!isValidEstimateType(estimate.estimate_type)) return StoreError.invalid_estimate_type;
        if (!isValidAckStatus(estimate.ack_status)) return StoreError.invalid_ack_status;
        if (estimate.cost_min < 0 or estimate.cost_max < 0) return StoreError.invalid_cost;
        if (estimate.cost_max < estimate.cost_min) return StoreError.invalid_cost;
        if (estimate.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;
        if (estimate.acknowledged_at.len > MAX_ACKNOWLEDGED_AT_BYTES) return StoreError.invalid_acknowledged_at;
        if (estimate.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;
        if (estimate.updated_at.len > MAX_UPDATED_AT_BYTES) return StoreError.invalid_updated_at;

        const existing_idx = self.by_id.get(estimate.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(estimate);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneEstimateIntoArena(estimate);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    /// AFFINE acknowledge: set `ack_status` (+ optional
    /// `acknowledged_at`) and stamp `updated_at`.  There is NO
    /// consumed-cell linearity gate — the Estimate has no FSM; this is a
    /// plain field write that emits an `updated` cell.  Idempotent on an
    /// identical re-ack (the caller-side handler short-circuits; the
    /// store still writes the cell so replay stays consistent).
    pub fn acknowledge(
        self: *EstimatesStore,
        id: []const u8,
        new_ack_status: []const u8,
        new_acknowledged_at: ?[]const u8,
    ) !Estimate {
        if (!isValidAckStatus(new_ack_status)) return StoreError.invalid_ack_status;
        if (new_acknowledged_at) |s| {
            if (s.len > MAX_ACKNOWLEDGED_AT_BYTES) return StoreError.invalid_acknowledged_at;
        }

        const idx = self.by_id.get(id) orelse return error.not_found;
        const owned = &self.owned_strings.items[idx];

        const new_ack_dup = try self.allocator.dupe(u8, new_ack_status);
        errdefer self.allocator.free(new_ack_dup);

        const updated_at_str = try renderIsoTimestamp(self.allocator, self.clock());
        errdefer self.allocator.free(updated_at_str);

        var new_ack_at_dup: ?[]u8 = null;
        if (new_acknowledged_at) |s| {
            new_ack_at_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_ack_at_dup) |d| self.allocator.free(d);

        // Build updated estimate for K4 LMDB write before in-memory commit.
        const updated_for_write = Estimate{
            .id = owned.id,
            .job_id = owned.job_id,
            .estimate_type = owned.estimate_type,
            .cost_min = self.records.items[idx].cost_min,
            .cost_max = self.records.items[idx].cost_max,
            .ack_status = new_ack_dup,
            .acknowledged_at = if (new_ack_at_dup) |d| d else owned.acknowledged_at,
            .notes = owned.notes,
            .created_at = owned.created_at,
            .updated_at = updated_at_str,
        };
        self.putUpdatedCell(updated_for_write) catch {
            self.allocator.free(new_ack_dup);
            self.allocator.free(updated_at_str);
            if (new_ack_at_dup) |d| self.allocator.free(d);
            return StoreError.persistence_failed;
        };

        // Commit: release the old slots and stitch in the new ones.
        self.allocator.free(owned.ack_status);
        owned.ack_status = new_ack_dup;
        self.allocator.free(owned.updated_at);
        owned.updated_at = updated_at_str;
        if (new_ack_at_dup) |d| {
            self.allocator.free(owned.acknowledged_at);
            owned.acknowledged_at = d;
        }

        const updated = Estimate{
            .id = owned.id,
            .job_id = owned.job_id,
            .estimate_type = owned.estimate_type,
            .cost_min = self.records.items[idx].cost_min,
            .cost_max = self.records.items[idx].cost_max,
            .ack_status = owned.ack_status,
            .acknowledged_at = owned.acknowledged_at,
            .notes = owned.notes,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
        self.records.items[idx] = updated;
        return updated;
    }

    pub fn findAll(self: *const EstimatesStore, allocator: std.mem.Allocator) ![]Estimate {
        const out = try allocator.alloc(Estimate, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    /// Const find-by-id over the in-memory index.  Mirrors
    /// jobs_store_lmdb_entity.zig: the handler is responsible for the
    /// live-index `rescanCreatedCells()`-then-retry on a miss (see
    /// resources/estimates_handler.zig) so this stays a pure read.
    pub fn findById(self: *const EstimatesStore, id: []const u8) ?Estimate {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByJobId(self: *const EstimatesStore, allocator: std.mem.Allocator, job_id: []const u8) ![]Estimate {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) n += 1;
        }
        const out = try allocator.alloc(Estimate, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const EstimatesStore) usize {
        return self.records.items.len;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    fn putCell(self: *EstimatesStore, estimate: Estimate) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeEstimate(self.allocator, &buf, estimate, "created");
        const cell = encodeEstimateAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    fn putUpdatedCell(self: *EstimatesStore, estimate: Estimate) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeEstimate(self.allocator, &buf, estimate, "updated");
        const cell = encodeEstimateAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *EstimatesStore) !void {
        // Pass 1: created (idempotent — see rescanCreatedCells).
        self.rescanCreatedCells();
        // Pass 2: updated (apply ack writes regardless of cursor order).
        {
            const cursor = self.cell_store.cursorOpen() catch return;
            defer self.cell_store.cursorClose(cursor);
            while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
                const payload = blk: {
                    if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                        if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_ESTIMATE) continue;
                        break :blk entity_cell.cellPayload(cell_ptr);
                    }
                    const decoded = substrate_entity.decodeEntity(cell_ptr);
                    if (!decoded.magic_ok) continue;
                    if (decoded.domain_flag != substrate_entity.SPEC_ESTIMATE.domain_flag) continue;
                    break :blk decoded.payload;
                };
                if (kindOfPayload(payload) == .updated) {
                    self.applyPayload(payload, false) catch {};
                }
            }
        }
    }

    /// Incremental pass-1 scan: index every `created` estimate cell
    /// currently in the shared entity store.
    ///
    /// `by_id` is otherwise built ONCE at init. A separate writer (the
    /// Slice 3 intent-action router minting an Estimate on `accept_rom`)
    /// that lands a new estimate cell while the brain is already running
    /// would be invisible to the estimates handler until the next
    /// process restart — the cell IS in the same LMDB env, the
    /// handler's in-memory index is stale. That is the "store-split"
    /// symptom; the lesson learned for jobs (commit 956eb81) applies
    /// identically here.
    ///
    /// Safe to call on any `by_id` miss before declaring not_found
    /// because it is fully idempotent: `created` rows are guarded by the
    /// `by_id.contains(id)` check inside `applyPayload`; `updated` rows
    /// are skipped here (pass 2 / acknowledge handles those), so a
    /// rescan never clobbers an in-memory ack.
    pub fn rescanCreatedCells(self: *EstimatesStore) void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);
        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_ESTIMATE) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_ESTIMATE.domain_flag) continue;
                break :blk decoded.payload;
            };
            if (kindOfPayload(payload) == .created) {
                self.applyPayload(payload, true) catch {}; // skip malformed
            }
        }
    }

    const PayloadKind = enum { created, updated, unknown };

    fn kindOfPayload(payload: []const u8) PayloadKind {
        const marker = "\"kind\":\"";
        const start = std.mem.indexOf(u8, payload, marker) orelse return .unknown;
        const after = payload[start + marker.len ..];
        if (std.mem.startsWith(u8, after, "created")) return .created;
        if (std.mem.startsWith(u8, after, "updated")) return .updated;
        return .unknown;
    }

    /// Apply a decoded estimate payload to the in-memory index.
    ///
    /// `created_only == true` (pass-1 / rescan of `created` cells):
    /// contains-guarded — if the id is already indexed we return
    /// WITHOUT mutating it.  This is the load-bearing idempotency
    /// property the jobs store learned (commit 956eb81): a rescan that
    /// re-reads the original `created` cell after an `acknowledge` must
    /// NOT clobber the in-memory ack back to its minted `ack_status`.
    ///
    /// `created_only == false` (pass-2 of `replayCellStore` over
    /// `updated` cells): latest-wins update-in-place, replaying the ack.
    fn applyPayload(self: *EstimatesStore, payload: []const u8, created_only: bool) !void {
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

        const estimate_type_v = obj.get("estimate_type") orelse return;
        if (estimate_type_v != .string) return;
        const estimate_type = estimate_type_v.string;
        if (!isValidEstimateType(estimate_type)) return;

        const ack_status_v = obj.get("ack_status") orelse return;
        if (ack_status_v != .string) return;
        const ack_status = ack_status_v.string;
        if (!isValidAckStatus(ack_status)) return;

        const cost_min: i64 = if (obj.get("cost_min")) |v| (if (v == .integer) v.integer else 0) else 0;
        const cost_max: i64 = if (obj.get("cost_max")) |v| (if (v == .integer) v.integer else 0) else 0;
        if (cost_min < 0 or cost_max < 0) return;
        if (cost_max < cost_min) return;

        const acknowledged_at = if (obj.get("acknowledged_at")) |v| (if (v == .string) v.string else "") else "";
        const notes = if (obj.get("notes")) |v| (if (v == .string) v.string else "") else "";

        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        const updated_at = if (obj.get("updated_at")) |v| (if (v == .string) v.string else created_at) else created_at;

        if (acknowledged_at.len > MAX_ACKNOWLEDGED_AT_BYTES) return;
        if (notes.len > MAX_NOTES_BYTES) return;
        if (created_at.len > MAX_CREATED_AT_BYTES) return;
        if (updated_at.len > MAX_UPDATED_AT_BYTES) return;

        if (self.by_id.get(id)) |existing_idx| {
            // Contains-guard for the `created` pass: never clobber an
            // already-indexed record from a re-read of its mint cell.
            if (created_only) return;
            // Latest-wins (pass-2 `updated` cells): update in place.
            const owned = &self.owned_strings.items[existing_idx];
            const ack_dup = try self.allocator.dupe(u8, ack_status);
            self.allocator.free(owned.ack_status);
            owned.ack_status = ack_dup;
            const aa_dup = try self.allocator.dupe(u8, acknowledged_at);
            self.allocator.free(owned.acknowledged_at);
            owned.acknowledged_at = aa_dup;
            const ua_dup = try self.allocator.dupe(u8, updated_at);
            self.allocator.free(owned.updated_at);
            owned.updated_at = ua_dup;
            self.records.items[existing_idx] = .{
                .id = owned.id,
                .job_id = owned.job_id,
                .estimate_type = owned.estimate_type,
                .cost_min = cost_min,
                .cost_max = cost_max,
                .ack_status = owned.ack_status,
                .acknowledged_at = owned.acknowledged_at,
                .notes = owned.notes,
                .created_at = owned.created_at,
                .updated_at = owned.updated_at,
            };
            return;
        }

        const stored = try self.cloneEstimateIntoArena(.{
            .id = id,
            .job_id = job_id,
            .estimate_type = estimate_type,
            .cost_min = cost_min,
            .cost_max = cost_max,
            .ack_status = ack_status,
            .acknowledged_at = acknowledged_at,
            .notes = notes,
            .created_at = created_at,
            .updated_at = updated_at,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
    }

    fn cloneEstimateIntoArena(self: *EstimatesStore, estimate: Estimate) !Estimate {
        var owned: OwnedStrings = undefined;
        owned.id = try self.allocator.dupe(u8, estimate.id);
        errdefer self.allocator.free(owned.id);
        owned.job_id = try self.allocator.dupe(u8, estimate.job_id);
        errdefer self.allocator.free(owned.job_id);
        owned.estimate_type = try self.allocator.dupe(u8, estimate.estimate_type);
        errdefer self.allocator.free(owned.estimate_type);
        owned.ack_status = try self.allocator.dupe(u8, estimate.ack_status);
        errdefer self.allocator.free(owned.ack_status);
        owned.acknowledged_at = try self.allocator.dupe(u8, estimate.acknowledged_at);
        errdefer self.allocator.free(owned.acknowledged_at);
        owned.notes = try self.allocator.dupe(u8, estimate.notes);
        errdefer self.allocator.free(owned.notes);
        owned.created_at = try self.allocator.dupe(u8, estimate.created_at);
        errdefer self.allocator.free(owned.created_at);
        owned.updated_at = try self.allocator.dupe(u8, estimate.updated_at);
        errdefer self.allocator.free(owned.updated_at);

        try self.owned_strings.append(self.allocator, owned);
        return .{
            .id = owned.id,
            .job_id = owned.job_id,
            .estimate_type = owned.estimate_type,
            .cost_min = estimate.cost_min,
            .cost_max = estimate.cost_max,
            .ack_status = owned.ack_status,
            .acknowledged_at = owned.acknowledged_at,
            .notes = owned.notes,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeEstimate(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    estimate: Estimate,
    kind: []const u8,
) !void {
    try buf.appendSlice(allocator, "{\"kind\":");
    try writeJsonString(allocator, buf, kind);
    try buf.appendSlice(allocator, ",\"id\":");
    try writeJsonString(allocator, buf, estimate.id);
    try buf.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, buf, estimate.job_id);
    try buf.appendSlice(allocator, ",\"estimate_type\":");
    try writeJsonString(allocator, buf, estimate.estimate_type);
    // cost_min / cost_max are integers — write raw.
    var num_buf: [32]u8 = undefined;
    const cost_min_s = std.fmt.bufPrint(&num_buf, "{d}", .{estimate.cost_min}) catch unreachable;
    try buf.appendSlice(allocator, ",\"cost_min\":");
    try buf.appendSlice(allocator, cost_min_s);
    const cost_max_s = std.fmt.bufPrint(&num_buf, "{d}", .{estimate.cost_max}) catch unreachable;
    try buf.appendSlice(allocator, ",\"cost_max\":");
    try buf.appendSlice(allocator, cost_max_s);
    try buf.appendSlice(allocator, ",\"ack_status\":");
    try writeJsonString(allocator, buf, estimate.ack_status);
    try buf.appendSlice(allocator, ",\"acknowledged_at\":");
    try writeJsonString(allocator, buf, estimate.acknowledged_at);
    try buf.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, buf, estimate.notes);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, estimate.created_at);
    try buf.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, buf, estimate.updated_at);
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
// Inline tests — pure logic + LMDB-backed round-trips.
// ─────────────────────────────────────────────────────────────────────

test "isValidAckStatus recognises the seven canonical Estimate ack statuses" {
    try std.testing.expect(isValidAckStatus("pending"));
    try std.testing.expect(isValidAckStatus("accepted"));
    try std.testing.expect(isValidAckStatus("tentative"));
    try std.testing.expect(isValidAckStatus("pushback"));
    try std.testing.expect(isValidAckStatus("rejected"));
    try std.testing.expect(isValidAckStatus("wants_exact_price"));
    try std.testing.expect(isValidAckStatus("rate_shopping"));
    try std.testing.expect(!isValidAckStatus(""));
    try std.testing.expect(!isValidAckStatus("draft"));
    try std.testing.expect(!isValidAckStatus("PENDING"));
}

test "isValidEstimateType recognises the three canonical Estimate types" {
    try std.testing.expect(isValidEstimateType("auto_rom"));
    try std.testing.expect(isValidEstimateType("operator_rom"));
    try std.testing.expect(isValidEstimateType("revised"));
    try std.testing.expect(!isValidEstimateType(""));
    try std.testing.expect(!isValidEstimateType("rom"));
    try std.testing.expect(!isValidEstimateType("AUTO_ROM"));
}

const lmdb = @import("lmdb");
const lmdb_cell_store_test_mod = @import("lmdb_cell_store");

fn openInlineTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

fn testClock() i64 {
    return 1_700_000_000;
}

fn baseEstimate(id: []const u8) Estimate {
    return .{
        .id = id,
        .job_id = "j-001",
        .estimate_type = "auto_rom",
        .cost_min = 5000,
        .cost_max = 20000,
        .ack_status = "pending",
        .acknowledged_at = "",
        .notes = "rough order of magnitude",
        .created_at = "2026-05-17T00:00:00Z",
        .updated_at = "2026-05-17T00:00:00Z",
    };
}

test "EstimatesStore: append → findAll → findById round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try EstimatesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    const outcome = try store.append(baseEstimate("e-001"));
    try std.testing.expectEqual(EstimatesStore.AppendOutcome.created, outcome);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const got = store.findById("e-001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("j-001", got.job_id);
    try std.testing.expectEqualStrings("auto_rom", got.estimate_type);
    try std.testing.expectEqualStrings("pending", got.ack_status);
    try std.testing.expectEqual(@as(i64, 5000), got.cost_min);
    try std.testing.expectEqual(@as(i64, 20000), got.cost_max);

    const all = try store.findAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 1), all.len);
}

test "EstimatesStore: idempotent re-append returns already_exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try EstimatesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    try std.testing.expectEqual(EstimatesStore.AppendOutcome.created, try store.append(baseEstimate("e-dup")));
    try std.testing.expectEqual(EstimatesStore.AppendOutcome.already_exists, try store.append(baseEstimate("e-dup")));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "EstimatesStore: invalid ack_status / estimate_type rejected" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try EstimatesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var bad_ack = baseEstimate("e-bad-ack");
    bad_ack.ack_status = "bogus";
    try std.testing.expectError(StoreError.invalid_ack_status, store.append(bad_ack));

    var bad_type = baseEstimate("e-bad-type");
    bad_type.estimate_type = "bogus";
    try std.testing.expectError(StoreError.invalid_estimate_type, store.append(bad_type));

    var bad_cost = baseEstimate("e-bad-cost");
    bad_cost.cost_min = 9000;
    bad_cost.cost_max = 100;
    try std.testing.expectError(StoreError.invalid_cost, store.append(bad_cost));
}

test "EstimatesStore: acknowledge sets ack_status (AFFINE field write)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try EstimatesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    _ = try store.append(baseEstimate("e-ack"));
    const acked = try store.acknowledge("e-ack", "accepted", "2026-05-17T01:00:00Z");
    try std.testing.expectEqualStrings("accepted", acked.ack_status);
    try std.testing.expectEqualStrings("2026-05-17T01:00:00Z", acked.acknowledged_at);

    // Idempotent re-ack with the same status (no FSM gate — AFFINE).
    const reacked = try store.acknowledge("e-ack", "accepted", "2026-05-17T01:00:00Z");
    try std.testing.expectEqualStrings("accepted", reacked.ack_status);

    try std.testing.expectError(error.not_found, store.acknowledge("nope", "accepted", null));
}

test "EstimatesStore: rescanCreatedCells picks up a cell minted after boot (store-split fix)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    // The estimates handler's store — boots over an empty cell store, so
    // its in-memory by_id index starts empty.
    var handler_store = try EstimatesStore.init(allocator, &cs, testClock);
    defer handler_store.deinit();

    // Simulate the Slice-3 intent-action router landing a NEW estimate
    // cell into the SAME shared entity store AFTER the handler booted (a
    // separate writer over the same env).
    var router = try EstimatesStore.init(allocator, &cs, testClock);
    defer router.deinit();
    _ = try router.append(baseEstimate("e-router"));

    // Stale index: the handler's store cannot see it yet — this is
    // exactly the "store-split" not_found symptom (the cell IS in the
    // shared env; the handler index doesn't have it).
    try std.testing.expect(handler_store.findById("e-router") == null);

    // Index-liveness: one incremental rescan and the post-boot cell is
    // indexed + acknowledgeable (mirrors the jobs handler's
    // rescan-then-retry on a by_id miss).
    handler_store.rescanCreatedCells();
    const found = handler_store.findById("e-router") orelse return error.RescanMissedCell;
    try std.testing.expectEqualStrings("pending", found.ack_status);

    // The freshly-indexed estimate is acknowledgeable.
    const acked = try handler_store.acknowledge("e-router", "accepted", null);
    try std.testing.expectEqualStrings("accepted", acked.ack_status);

    // Idempotent: a second rescan neither duplicates the record nor
    // clobbers the just-applied ack (pass-1 contains-guard + updated
    // cells skipped on rescan).
    const before_count = handler_store.count();
    handler_store.rescanCreatedCells();
    try std.testing.expectEqual(before_count, handler_store.count());
    const after = handler_store.findById("e-router") orelse return error.RescanMissedCell;
    try std.testing.expectEqualStrings("accepted", after.ack_status);
}

```
