---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/invoices_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.549931+00:00
---

# cartridges/oddjobz/brain/zig/src/invoices_store_lmdb.zig

```zig
// W0.2 — Invoices store backed by LmdbCellStore (replaces invoices_store_fs.zig).
//
// Each invoice entity is serialised as a JSON payload packed into a
// 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/updateState call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory state
// is NOT updated.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_INVOICE (0x04) and replays them to rebuild the in-memory index.
//
// The public API is identical to the old invoices_store_fs.InvoicesStore so
// all existing callers (handlers, cli.zig, conformance tests) require only
// the change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114g — encode an invoice buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// draft / sent / viewed / partially_paid → LINEAR; paid / void → RELEVANT.
fn encodeInvoiceAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_INVOICE, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_INVOICE,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_INVOICE, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_status,
    invalid_id,
    invalid_job_id,
    invalid_notes,
    invalid_amount,
    invalid_amount_paid,
    invalid_external_invoice_id,
    invalid_sent_at,
    invalid_viewed_at,
    invalid_paid_at,
    invalid_created_at,
    invalid_updated_at,
    /// `updateState` called for an id that doesn't exist in the store.
    not_found,
};

/// Canonical Invoice FSM states — matches `cartridges/oddjobz/brain/src/state-
/// machines/invoice-fsm.ts` INVOICE_FSM_STATES verbatim.
pub const INVOICE_FSM_STATES = [_][]const u8{
    "draft",
    "sent",
    "viewed",
    "partial",
    "paid",
    "overdue",
    "cancelled",
};

pub fn isValidStatus(s: []const u8) bool {
    for (INVOICE_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub const Invoice = struct {
    id: []const u8,
    job_id: []const u8,
    status: []const u8,
    amount: i64,
    amount_paid: i64,
    external_invoice_id: []const u8,
    notes: []const u8,
    sent_at: []const u8,
    viewed_at: []const u8,
    paid_at: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const MAX_ID_BYTES: usize = 64;
pub const MAX_JOB_ID_BYTES: usize = 64;
pub const MAX_STATUS_BYTES: usize = 32;
pub const MAX_EXTERNAL_INVOICE_ID_BYTES: usize = 256;
pub const MAX_NOTES_BYTES: usize = 2000;
pub const MAX_SENT_AT_BYTES: usize = 64;
pub const MAX_VIEWED_AT_BYTES: usize = 64;
pub const MAX_PAID_AT_BYTES: usize = 64;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_UPDATED_AT_BYTES: usize = 64;

const OwnedStrings = struct {
    id: []u8,
    job_id: []u8,
    status: []u8,
    external_invoice_id: []u8,
    notes: []u8,
    sent_at: []u8,
    viewed_at: []u8,
    paid_at: []u8,
    created_at: []u8,
    updated_at: []u8,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.status);
        allocator.free(self.external_invoice_id);
        allocator.free(self.notes);
        allocator.free(self.sent_at);
        allocator.free(self.viewed_at);
        allocator.free(self.paid_at);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

pub const InvoicesStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Invoice),
    by_id: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !InvoicesStore {
        var self = InvoicesStore{
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

    pub fn deinit(self: *InvoicesStore) void {
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
    }

    pub fn append(self: *InvoicesStore, invoice: Invoice) !AppendOutcome {
        if (invoice.id.len == 0 or invoice.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (invoice.job_id.len == 0 or invoice.job_id.len > MAX_JOB_ID_BYTES) return StoreError.invalid_job_id;
        if (!isValidStatus(invoice.status)) return StoreError.invalid_status;
        if (invoice.amount < 0) return StoreError.invalid_amount;
        if (invoice.amount_paid < 0 or invoice.amount_paid > invoice.amount) return StoreError.invalid_amount_paid;
        if (invoice.external_invoice_id.len > MAX_EXTERNAL_INVOICE_ID_BYTES) return StoreError.invalid_external_invoice_id;
        if (invoice.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;
        if (invoice.sent_at.len > MAX_SENT_AT_BYTES) return StoreError.invalid_sent_at;
        if (invoice.viewed_at.len > MAX_VIEWED_AT_BYTES) return StoreError.invalid_viewed_at;
        if (invoice.paid_at.len > MAX_PAID_AT_BYTES) return StoreError.invalid_paid_at;
        if (invoice.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;
        if (invoice.updated_at.len > MAX_UPDATED_AT_BYTES) return StoreError.invalid_updated_at;

        const existing_idx = self.by_id.get(invoice.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(invoice);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneInvoiceIntoArena(invoice);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub fn updateState(
        self: *InvoicesStore,
        id: []const u8,
        new_status: []const u8,
        new_sent_at: ?[]const u8,
        new_viewed_at: ?[]const u8,
        new_paid_at: ?[]const u8,
        new_amount_paid: ?i64,
    ) !Invoice {
        if (!isValidStatus(new_status)) return StoreError.invalid_status;
        if (new_sent_at) |s| {
            if (s.len > MAX_SENT_AT_BYTES) return StoreError.invalid_sent_at;
        }
        if (new_viewed_at) |s| {
            if (s.len > MAX_VIEWED_AT_BYTES) return StoreError.invalid_viewed_at;
        }
        if (new_paid_at) |s| {
            if (s.len > MAX_PAID_AT_BYTES) return StoreError.invalid_paid_at;
        }

        const idx = self.by_id.get(id) orelse return error.not_found;
        const owned = &self.owned_strings.items[idx];

        const new_status_dup = try self.allocator.dupe(u8, new_status);
        errdefer self.allocator.free(new_status_dup);

        const updated_at_str = try renderIsoTimestamp(self.allocator, self.clock());
        errdefer self.allocator.free(updated_at_str);

        var new_sent_at_dup: ?[]u8 = null;
        if (new_sent_at) |s| {
            new_sent_at_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_sent_at_dup) |d| self.allocator.free(d);

        var new_viewed_at_dup: ?[]u8 = null;
        if (new_viewed_at) |s| {
            new_viewed_at_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_viewed_at_dup) |d| self.allocator.free(d);

        var new_paid_at_dup: ?[]u8 = null;
        if (new_paid_at) |s| {
            new_paid_at_dup = try self.allocator.dupe(u8, s);
        }
        errdefer if (new_paid_at_dup) |d| self.allocator.free(d);

        // amount_paid validation against amount.
        const cur_amount = self.records.items[idx].amount;
        if (new_amount_paid) |ap| {
            if (ap < 0 or ap > cur_amount) return StoreError.invalid_amount_paid;
        }
        const cur_amount_paid = self.records.items[idx].amount_paid;
        const final_amount_paid: i64 = if (new_amount_paid) |ap| ap else cur_amount_paid;

        // Build updated invoice for K4 LMDB write before in-memory commit.
        const updated_for_write = Invoice{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = new_status_dup,
            .amount = cur_amount,
            .amount_paid = final_amount_paid,
            .external_invoice_id = owned.external_invoice_id,
            .notes = owned.notes,
            .sent_at = if (new_sent_at_dup) |d| d else owned.sent_at,
            .viewed_at = if (new_viewed_at_dup) |d| d else owned.viewed_at,
            .paid_at = if (new_paid_at_dup) |d| d else owned.paid_at,
            .created_at = owned.created_at,
            .updated_at = updated_at_str,
        };
        self.putCell(updated_for_write) catch {
            self.allocator.free(new_status_dup);
            self.allocator.free(updated_at_str);
            if (new_sent_at_dup) |d| self.allocator.free(d);
            if (new_viewed_at_dup) |d| self.allocator.free(d);
            if (new_paid_at_dup) |d| self.allocator.free(d);
            return StoreError.persistence_failed;
        };

        // Commit: release the old slots and stitch in the new ones.
        self.allocator.free(owned.status);
        owned.status = new_status_dup;
        self.allocator.free(owned.updated_at);
        owned.updated_at = updated_at_str;
        if (new_sent_at_dup) |d| {
            self.allocator.free(owned.sent_at);
            owned.sent_at = d;
        }
        if (new_viewed_at_dup) |d| {
            self.allocator.free(owned.viewed_at);
            owned.viewed_at = d;
        }
        if (new_paid_at_dup) |d| {
            self.allocator.free(owned.paid_at);
            owned.paid_at = d;
        }

        const updated = Invoice{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = owned.status,
            .amount = cur_amount,
            .amount_paid = final_amount_paid,
            .external_invoice_id = owned.external_invoice_id,
            .notes = owned.notes,
            .sent_at = owned.sent_at,
            .viewed_at = owned.viewed_at,
            .paid_at = owned.paid_at,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
        self.records.items[idx] = updated;
        return updated;
    }

    pub fn findAll(self: *const InvoicesStore, allocator: std.mem.Allocator) ![]Invoice {
        const out = try allocator.alloc(Invoice, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn findById(self: *const InvoicesStore, id: []const u8) ?Invoice {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByJobId(self: *const InvoicesStore, allocator: std.mem.Allocator, job_id: []const u8) ![]Invoice {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) n += 1;
        }
        const out = try allocator.alloc(Invoice, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.job_id, job_id)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const InvoicesStore) usize {
        return self.records.items.len;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    fn putCell(self: *InvoicesStore, invoice: Invoice) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeInvoice(self.allocator, &buf, invoice);
        const cell = encodeInvoiceAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *InvoicesStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);

        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_INVOICE) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_INVOICE.domain_flag) continue;
                break :blk decoded.payload;
            };
            self.applyPayload(payload) catch {}; // skip malformed
        }
    }

    fn applyPayload(self: *InvoicesStore, payload: []const u8) !void {
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

        const amount: i64 = if (obj.get("amount")) |v| (if (v == .integer) v.integer else 0) else 0;
        const amount_paid: i64 = if (obj.get("amount_paid")) |v| (if (v == .integer) v.integer else 0) else 0;
        if (amount < 0) return;
        if (amount_paid < 0 or amount_paid > amount) return;

        const external_invoice_id = if (obj.get("external_invoice_id")) |v| (if (v == .string) v.string else "") else "";
        const notes = if (obj.get("notes")) |v| (if (v == .string) v.string else "") else "";
        const sent_at = if (obj.get("sent_at")) |v| (if (v == .string) v.string else "") else "";
        const viewed_at = if (obj.get("viewed_at")) |v| (if (v == .string) v.string else "") else "";
        const paid_at = if (obj.get("paid_at")) |v| (if (v == .string) v.string else "") else "";

        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        const updated_at = if (obj.get("updated_at")) |v| (if (v == .string) v.string else created_at) else created_at;

        if (external_invoice_id.len > MAX_EXTERNAL_INVOICE_ID_BYTES) return;
        if (notes.len > MAX_NOTES_BYTES) return;
        if (sent_at.len > MAX_SENT_AT_BYTES) return;
        if (viewed_at.len > MAX_VIEWED_AT_BYTES) return;
        if (paid_at.len > MAX_PAID_AT_BYTES) return;
        if (created_at.len > MAX_CREATED_AT_BYTES) return;
        if (updated_at.len > MAX_UPDATED_AT_BYTES) return;

        // Latest-wins: if we've seen this id before, update in place.
        if (self.by_id.get(id)) |existing_idx| {
            const owned = &self.owned_strings.items[existing_idx];
            const status_dup = try self.allocator.dupe(u8, status);
            self.allocator.free(owned.status);
            owned.status = status_dup;
            const sa_dup = try self.allocator.dupe(u8, sent_at);
            self.allocator.free(owned.sent_at);
            owned.sent_at = sa_dup;
            const va_dup = try self.allocator.dupe(u8, viewed_at);
            self.allocator.free(owned.viewed_at);
            owned.viewed_at = va_dup;
            const pa_dup = try self.allocator.dupe(u8, paid_at);
            self.allocator.free(owned.paid_at);
            owned.paid_at = pa_dup;
            const ua_dup = try self.allocator.dupe(u8, updated_at);
            self.allocator.free(owned.updated_at);
            owned.updated_at = ua_dup;
            self.records.items[existing_idx] = .{
                .id = owned.id,
                .job_id = owned.job_id,
                .status = owned.status,
                .amount = amount,
                .amount_paid = amount_paid,
                .external_invoice_id = owned.external_invoice_id,
                .notes = owned.notes,
                .sent_at = owned.sent_at,
                .viewed_at = owned.viewed_at,
                .paid_at = owned.paid_at,
                .created_at = owned.created_at,
                .updated_at = owned.updated_at,
            };
            return;
        }

        const stored = try self.cloneInvoiceIntoArena(.{
            .id = id,
            .job_id = job_id,
            .status = status,
            .amount = amount,
            .amount_paid = amount_paid,
            .external_invoice_id = external_invoice_id,
            .notes = notes,
            .sent_at = sent_at,
            .viewed_at = viewed_at,
            .paid_at = paid_at,
            .created_at = created_at,
            .updated_at = updated_at,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
    }

    fn cloneInvoiceIntoArena(self: *InvoicesStore, invoice: Invoice) !Invoice {
        var owned: OwnedStrings = undefined;
        owned.id = try self.allocator.dupe(u8, invoice.id);
        errdefer self.allocator.free(owned.id);
        owned.job_id = try self.allocator.dupe(u8, invoice.job_id);
        errdefer self.allocator.free(owned.job_id);
        owned.status = try self.allocator.dupe(u8, invoice.status);
        errdefer self.allocator.free(owned.status);
        owned.external_invoice_id = try self.allocator.dupe(u8, invoice.external_invoice_id);
        errdefer self.allocator.free(owned.external_invoice_id);
        owned.notes = try self.allocator.dupe(u8, invoice.notes);
        errdefer self.allocator.free(owned.notes);
        owned.sent_at = try self.allocator.dupe(u8, invoice.sent_at);
        errdefer self.allocator.free(owned.sent_at);
        owned.viewed_at = try self.allocator.dupe(u8, invoice.viewed_at);
        errdefer self.allocator.free(owned.viewed_at);
        owned.paid_at = try self.allocator.dupe(u8, invoice.paid_at);
        errdefer self.allocator.free(owned.paid_at);
        owned.created_at = try self.allocator.dupe(u8, invoice.created_at);
        errdefer self.allocator.free(owned.created_at);
        owned.updated_at = try self.allocator.dupe(u8, invoice.updated_at);
        errdefer self.allocator.free(owned.updated_at);

        try self.owned_strings.append(self.allocator, owned);
        return .{
            .id = owned.id,
            .job_id = owned.job_id,
            .status = owned.status,
            .amount = invoice.amount,
            .amount_paid = invoice.amount_paid,
            .external_invoice_id = owned.external_invoice_id,
            .notes = owned.notes,
            .sent_at = owned.sent_at,
            .viewed_at = owned.viewed_at,
            .paid_at = owned.paid_at,
            .created_at = owned.created_at,
            .updated_at = owned.updated_at,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeInvoice(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    invoice: Invoice,
) !void {
    try buf.appendSlice(allocator, "{\"kind\":\"created\",\"id\":");
    try writeJsonString(allocator, buf, invoice.id);
    try buf.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, buf, invoice.job_id);
    try buf.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, buf, invoice.status);
    // amount / amount_paid are integers — write raw.
    var num_buf: [32]u8 = undefined;
    const amount_s = std.fmt.bufPrint(&num_buf, "{d}", .{invoice.amount}) catch unreachable;
    try buf.appendSlice(allocator, ",\"amount\":");
    try buf.appendSlice(allocator, amount_s);
    const amount_paid_s = std.fmt.bufPrint(&num_buf, "{d}", .{invoice.amount_paid}) catch unreachable;
    try buf.appendSlice(allocator, ",\"amount_paid\":");
    try buf.appendSlice(allocator, amount_paid_s);
    try buf.appendSlice(allocator, ",\"external_invoice_id\":");
    try writeJsonString(allocator, buf, invoice.external_invoice_id);
    try buf.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, buf, invoice.notes);
    try buf.appendSlice(allocator, ",\"sent_at\":");
    try writeJsonString(allocator, buf, invoice.sent_at);
    try buf.appendSlice(allocator, ",\"viewed_at\":");
    try writeJsonString(allocator, buf, invoice.viewed_at);
    try buf.appendSlice(allocator, ",\"paid_at\":");
    try writeJsonString(allocator, buf, invoice.paid_at);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, invoice.created_at);
    try buf.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, buf, invoice.updated_at);
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

test "isValidStatus recognises the seven canonical Invoice FSM states" {
    try std.testing.expect(isValidStatus("draft"));
    try std.testing.expect(isValidStatus("sent"));
    try std.testing.expect(isValidStatus("viewed"));
    try std.testing.expect(isValidStatus("partial"));
    try std.testing.expect(isValidStatus("paid"));
    try std.testing.expect(isValidStatus("overdue"));
    try std.testing.expect(isValidStatus("cancelled"));
    try std.testing.expect(!isValidStatus(""));
    try std.testing.expect(!isValidStatus("DRAFT"));
}

```
