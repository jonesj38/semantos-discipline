---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/sites_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.547269+00:00
---

# cartridges/oddjobz/brain/zig/src/sites_store_lmdb.zig

```zig
// W6.2 — SitesStore backed by LmdbCellStore (replaces sites_store_fs.zig JSONL).
//
// Reference: docs/design/BRAIN-BRAIN-FIELD-APP-DB-INTEGRATION-PIPELINE.md W6.2
//
// Each site entity is serialised as a JSON payload packed into a 1024-byte
// cell via entity_cell.encodeCell and written to LmdbCellStore using tag
// ENTITY_TAG_SITE (0x07).
//
// K4 atomicity: appendCreated encodes the cell first; only on successful
// cell_store.put() is the in-memory index updated.
//
// On init the store scans the cell store for all ENTITY_TAG_SITE cells
// and replays them (two passes: "created" first, "signed" second) to
// rebuild the in-memory indexes.
//
// The public API is identical to sites_store_fs.SitesStore so all existing
// callers (cli.zig, conformance tests, ratify handler) require only:
//   SitesStore.init(allocator, &cell_store, clock_fn)
// instead of:
//   SitesStore.init(allocator, data_dir, clock_fn)

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114d — encode a site buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// Linearity: AFFINE (active) by default; archived → RELEVANT.
fn encodeSiteAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_SITE, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_SITE,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_SITE, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_normalised_address,
    invalid_lookup_key,
    invalid_full_address,
    invalid_suburb,
    invalid_postcode,
    invalid_state_field,
    invalid_key_number,
};

pub const MAX_NORMALISED_ADDRESS_BYTES: usize = 500;
pub const MAX_LOOKUP_KEY_BYTES: usize = MAX_NORMALISED_ADDRESS_BYTES + 64 + 1;
pub const MAX_FULL_ADDRESS_BYTES: usize = 500;
pub const MAX_SUBURB_BYTES: usize = 100;
pub const MAX_POSTCODE_BYTES: usize = 10;
pub const MAX_STATE_BYTES: usize = 50;
pub const MAX_KEY_NUMBER_BYTES: usize = 64;

/// One row in the helm Sites view.  All string slices are valid until
/// the store is deinit'd (OwnedStrings per record, same as jobs_store_lmdb).
pub const Site = struct {
    cellId: [32]u8,
    typeHash: [32]u8,
    normalisedAddress: []const u8,
    keyNumber: ?[]const u8,
    lookupKey: []const u8,
    fullAddress: []const u8,
    suburb: ?[]const u8,
    postcode: ?[]const u8,
    state: ?[]const u8,
    signedBy: ?[33]u8,
    signature: ?[64]u8,
    createdAt: i64,
};

/// Per-record owned string storage (heap-allocated copies of every
/// variable-length string field, freed in deinit).
const OwnedStrings = struct {
    normalised_address: []u8,
    lookup_key: []u8,
    full_address: []u8,
    key_number: ?[]u8 = null,
    suburb: ?[]u8 = null,
    postcode: ?[]u8 = null,
    state: ?[]u8 = null,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.normalised_address);
        allocator.free(self.lookup_key);
        allocator.free(self.full_address);
        if (self.key_number) |s| allocator.free(s);
        if (self.suburb) |s| allocator.free(s);
        if (self.postcode) |s| allocator.free(s);
        if (self.state) |s| allocator.free(s);
    }
};

/// Per-record owned hex cellId key for by_id and by_lookup_key maps.
const OwnedKey = struct {
    id_hex: []u8,

    fn free(self: *OwnedKey, allocator: std.mem.Allocator) void {
        allocator.free(self.id_hex);
    }
};

pub const SitesStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Site),
    by_id: std.StringHashMap(usize),
    by_lookup_key: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    owned_keys: std.ArrayList(OwnedKey),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cs: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !SitesStore {
        var self = SitesStore{
            .allocator = allocator,
            .cell_store = cs,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .by_lookup_key = std.StringHashMap(usize).init(allocator),
            .owned_strings = .{},
            .owned_keys = .{},
            .clock = clock_fn,
        };
        try self.replayCellStore();
        return self;
    }

    pub fn deinit(self: *SitesStore) void {
        self.records.deinit(self.allocator);
        self.by_id.deinit();
        self.by_lookup_key.deinit();
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        for (self.owned_keys.items) |*k| k.free(self.allocator);
        self.owned_keys.deinit(self.allocator);
    }

    pub const SitePayload = struct {
        cellId: [32]u8,
        typeHash: [32]u8,
        normalisedAddress: []const u8,
        keyNumber: ?[]const u8,
        lookupKey: []const u8,
        fullAddress: []const u8,
        suburb: ?[]const u8,
        postcode: ?[]const u8,
        state: ?[]const u8,
        signedBy: ?[33]u8 = null,
        signature: ?[64]u8 = null,
    };

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    /// Append a `created` event for `payload` to the cell store and
    /// update the in-memory indexes.  Idempotent on duplicate cellId:
    /// returns the existing Site without mutating the in-memory record.
    pub fn appendCreated(self: *SitesStore, payload: SitePayload) !Site {
        if (payload.normalisedAddress.len == 0 or payload.normalisedAddress.len > MAX_NORMALISED_ADDRESS_BYTES) {
            return StoreError.invalid_normalised_address;
        }
        if (payload.lookupKey.len == 0 or payload.lookupKey.len > MAX_LOOKUP_KEY_BYTES) {
            return StoreError.invalid_lookup_key;
        }
        if (payload.fullAddress.len == 0 or payload.fullAddress.len > MAX_FULL_ADDRESS_BYTES) {
            return StoreError.invalid_full_address;
        }
        if (payload.keyNumber) |kn| {
            if (kn.len == 0 or kn.len > MAX_KEY_NUMBER_BYTES) return StoreError.invalid_key_number;
        }
        if (payload.suburb) |s| {
            if (s.len > MAX_SUBURB_BYTES) return StoreError.invalid_suburb;
        }
        if (payload.postcode) |p| {
            if (p.len > MAX_POSTCODE_BYTES) return StoreError.invalid_postcode;
        }
        if (payload.state) |st| {
            if (st.len > MAX_STATE_BYTES) return StoreError.invalid_state_field;
        }

        const created_at = self.clock();

        const id_hex_arr = std.fmt.bytesToHex(payload.cellId, .lower);
        const id_hex: []const u8 = id_hex_arr[0..];

        // Idempotent: if cellId already in by_id, write cell for audit
        // but return the existing in-memory record unchanged.
        if (self.by_id.get(id_hex)) |existing_idx| {
            // K4: still write to LMDB (idempotent since same content →
            // same SHA256 key; the put is a no-op at the storage level).
            try self.putCell(payload, created_at);
            return self.records.items[existing_idx];
        }

        // K4: write LMDB cell first.
        try self.putCell(payload, created_at);

        // K4: write LMDB cell first — only update in-memory on success.
        // Clone into owned heap storage.
        const stored = try self.cloneSite(payload, created_at);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;

        // Insert by_id using an owned copy of the hex key so the map key
        // stays valid for the store's lifetime.
        const id_key = try self.allocator.dupe(u8, id_hex);
        errdefer self.allocator.free(id_key);
        try self.owned_keys.append(self.allocator, .{ .id_hex = id_key });
        try self.by_id.put(id_key, idx);

        // by_lookup_key borrows the owned lookupKey slice on the stored Site.
        try self.by_lookup_key.put(self.records.items[idx].lookupKey, idx);

        return self.records.items[idx];
    }

    pub fn getById(self: *const SitesStore, cellId: [32]u8) ?Site {
        const id_hex_arr = std.fmt.bytesToHex(cellId, .lower);
        const idx = self.by_id.get(id_hex_arr[0..]) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByLookupKey(self: *const SitesStore, key: []const u8) ?Site {
        const idx = self.by_lookup_key.get(key) orelse return null;
        return self.records.items[idx];
    }

    pub fn listAll(self: *const SitesStore, allocator: std.mem.Allocator) ![]Site {
        const out = try allocator.alloc(Site, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn count(self: *const SitesStore) usize {
        return self.records.items.len;
    }

    /// D-DOG.1.0c Phase 4 — append a `signed` event, updating signedBy
    /// and signature on the in-memory row and writing a cell to LMDB.
    pub fn appendSigned(
        self: *SitesStore,
        cell_id: [32]u8,
        signed_by: [33]u8,
        signature: [64]u8,
    ) !void {
        for (self.records.items, 0..) |row, idx| {
            if (std.mem.eql(u8, &row.cellId, &cell_id)) {
                self.records.items[idx].signedBy = signed_by;
                self.records.items[idx].signature = signature;
                // Write a "signed" cell for durability.
                self.putSignedCell(cell_id, signed_by, signature) catch {};
                return;
            }
        }
    }

    // ── LMDB cell writes ──────────────────────────────────────────────

    fn putCell(self: *SitesStore, payload: SitePayload, ts: i64) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeSiteCreated(self.allocator, &buf, payload, ts);
        const cell = encodeSiteAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    fn putSignedCell(
        self: *SitesStore,
        cell_id: [32]u8,
        signed_by: [33]u8,
        signature: [64]u8,
    ) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeSiteSigned(self.allocator, &buf, cell_id, signed_by, signature, self.clock());
        const cell = encodeSiteAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ─────────────────────────────────────────────
    //
    // Two-pass: pass 1 applies "created" cells; pass 2 applies "signed"
    // cells.  The LMDB cursor iterates in SHA256-hash-sorted order, so
    // a "signed" cell may appear before its "created" cell in the cursor
    // stream even though it was written later.  Two-pass replay ensures
    // that by the time "signed" cells are applied, every "created" row is
    // already in the in-memory index.

    fn replayCellStore(self: *SitesStore) !void {
        // Pass 1: created
        {
            const cursor = self.cell_store.cursorOpen() catch return;
            defer self.cell_store.cursorClose(cursor);
            while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
                // RM-114d — dual-format read.
                const payload = blk: {
                    if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                        if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_SITE) continue;
                        break :blk entity_cell.cellPayload(cell_ptr);
                    }
                    const decoded = substrate_entity.decodeEntity(cell_ptr);
                    if (!decoded.magic_ok) continue;
                    if (decoded.domain_flag != substrate_entity.SPEC_SITE.domain_flag) continue;
                    break :blk decoded.payload;
                };
                if (kindOfPayload(payload) == .created) {
                    self.applyCreatedPayload(payload) catch {};
                }
            }
        }
        // Pass 2: signed
        {
            const cursor = self.cell_store.cursorOpen() catch return;
            defer self.cell_store.cursorClose(cursor);
            while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
                // RM-114d — dual-format read.
                const payload = blk: {
                    if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                        if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_SITE) continue;
                        break :blk entity_cell.cellPayload(cell_ptr);
                    }
                    const decoded = substrate_entity.decodeEntity(cell_ptr);
                    if (!decoded.magic_ok) continue;
                    if (decoded.domain_flag != substrate_entity.SPEC_SITE.domain_flag) continue;
                    break :blk decoded.payload;
                };
                if (kindOfPayload(payload) == .signed) {
                    self.applySignedPayload(payload) catch {};
                }
            }
        }
    }

    const PayloadKind = enum { created, signed, unknown };

    fn kindOfPayload(payload: []const u8) PayloadKind {
        const marker = "\"kind\":\"";
        const start = std.mem.indexOf(u8, payload, marker) orelse return .unknown;
        const after = payload[start + marker.len ..];
        if (std.mem.startsWith(u8, after, "created")) return .created;
        if (std.mem.startsWith(u8, after, "signed")) return .signed;
        return .unknown;
    }

    fn applyCreatedPayload(self: *SitesStore, raw: []const u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        ) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        const cell_id_v = obj.get("cellId") orelse return;
        if (cell_id_v != .string or cell_id_v.string.len != 64) return;
        const type_hash_v = obj.get("typeHash") orelse return;
        if (type_hash_v != .string or type_hash_v.string.len != 64) return;
        const normalised_v = obj.get("normalisedAddress") orelse return;
        if (normalised_v != .string) return;
        const lookup_v = obj.get("lookupKey") orelse return;
        if (lookup_v != .string) return;
        const full_v = obj.get("fullAddress") orelse return;
        if (full_v != .string) return;

        var cell_id: [32]u8 = undefined;
        var type_hash: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&cell_id, cell_id_v.string) catch return;
        _ = std.fmt.hexToBytes(&type_hash, type_hash_v.string) catch return;

        if (normalised_v.string.len == 0 or normalised_v.string.len > MAX_NORMALISED_ADDRESS_BYTES) return;
        if (lookup_v.string.len == 0 or lookup_v.string.len > MAX_LOOKUP_KEY_BYTES) return;
        if (full_v.string.len == 0 or full_v.string.len > MAX_FULL_ADDRESS_BYTES) return;

        const key_number: ?[]const u8 = blk: {
            if (obj.get("keyNumber")) |v| {
                switch (v) {
                    .string => |s| {
                        if (s.len > MAX_KEY_NUMBER_BYTES) return;
                        break :blk s;
                    },
                    .null => break :blk null,
                    else => break :blk null,
                }
            }
            break :blk null;
        };
        const suburb = optStringField(obj, "suburb");
        const postcode = optStringField(obj, "postcode");
        const state = optStringField(obj, "state");

        if (suburb) |s| { if (s.len > MAX_SUBURB_BYTES) return; }
        if (postcode) |p| { if (p.len > MAX_POSTCODE_BYTES) return; }
        if (state) |st| { if (st.len > MAX_STATE_BYTES) return; }

        const created_at: i64 = blk: {
            if (obj.get("createdAt")) |v| {
                if (v == .integer) break :blk v.integer;
            }
            break :blk 0;
        };

        const signed_by_opt: ?[33]u8 = blk: {
            if (obj.get("signedBy")) |v| {
                if (v == .string and v.string.len == 66) {
                    var sb: [33]u8 = undefined;
                    if (std.fmt.hexToBytes(&sb, v.string)) |_| break :blk sb else |_| {}
                }
            }
            break :blk null;
        };
        const signature_opt: ?[64]u8 = blk: {
            if (obj.get("signature")) |v| {
                if (v == .string and v.string.len == 128) {
                    var sig: [64]u8 = undefined;
                    if (std.fmt.hexToBytes(&sig, v.string)) |_| break :blk sig else |_| {}
                }
            }
            break :blk null;
        };

        // Idempotent: first cell wins.
        if (self.by_id.contains(cell_id_v.string)) return;

        const stored = try self.cloneSite(.{
            .cellId = cell_id,
            .typeHash = type_hash,
            .normalisedAddress = normalised_v.string,
            .keyNumber = key_number,
            .lookupKey = lookup_v.string,
            .fullAddress = full_v.string,
            .suburb = suburb,
            .postcode = postcode,
            .state = state,
            .signedBy = signed_by_opt,
            .signature = signature_opt,
        }, created_at);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;

        const id_key = try self.allocator.dupe(u8, cell_id_v.string);
        errdefer self.allocator.free(id_key);
        try self.owned_keys.append(self.allocator, .{ .id_hex = id_key });
        try self.by_id.put(id_key, idx);
        try self.by_lookup_key.put(self.records.items[idx].lookupKey, idx);
    }

    fn applySignedPayload(self: *SitesStore, raw: []const u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        ) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        const cell_v = obj.get("cellId") orelse return;
        if (cell_v != .string or cell_v.string.len != 64) return;
        var cell_id: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&cell_id, cell_v.string) catch return;

        const sb_v = obj.get("signedBy") orelse return;
        if (sb_v != .string or sb_v.string.len != 66) return;
        var signed_by: [33]u8 = undefined;
        _ = std.fmt.hexToBytes(&signed_by, sb_v.string) catch return;

        const sig_v = obj.get("signature") orelse return;
        if (sig_v != .string or sig_v.string.len != 128) return;
        var signature: [64]u8 = undefined;
        _ = std.fmt.hexToBytes(&signature, sig_v.string) catch return;

        for (self.records.items, 0..) |row, idx| {
            if (std.mem.eql(u8, &row.cellId, &cell_id)) {
                self.records.items[idx].signedBy = signed_by;
                self.records.items[idx].signature = signature;
                return;
            }
        }
    }

    // ── Clone helpers ─────────────────────────────────────────────────

    fn cloneSite(self: *SitesStore, payload: SitePayload, created_at: i64) !Site {
        var owned = OwnedStrings{
            .normalised_address = try self.allocator.dupe(u8, payload.normalisedAddress),
            .lookup_key = undefined,
            .full_address = undefined,
        };
        errdefer self.allocator.free(owned.normalised_address);
        owned.lookup_key = try self.allocator.dupe(u8, payload.lookupKey);
        errdefer self.allocator.free(owned.lookup_key);
        owned.full_address = try self.allocator.dupe(u8, payload.fullAddress);
        errdefer self.allocator.free(owned.full_address);

        if (payload.keyNumber) |kn| {
            owned.key_number = try self.allocator.dupe(u8, kn);
        }
        errdefer if (owned.key_number) |s| self.allocator.free(s);

        if (payload.suburb) |s| {
            owned.suburb = try self.allocator.dupe(u8, s);
        }
        errdefer if (owned.suburb) |s| self.allocator.free(s);

        if (payload.postcode) |p| {
            owned.postcode = try self.allocator.dupe(u8, p);
        }
        errdefer if (owned.postcode) |p| self.allocator.free(p);

        if (payload.state) |st| {
            owned.state = try self.allocator.dupe(u8, st);
        }
        errdefer if (owned.state) |st| self.allocator.free(st);

        try self.owned_strings.append(self.allocator, owned);

        return .{
            .cellId = payload.cellId,
            .typeHash = payload.typeHash,
            .normalisedAddress = owned.normalised_address,
            .keyNumber = owned.key_number,
            .lookupKey = owned.lookup_key,
            .fullAddress = owned.full_address,
            .suburb = owned.suburb,
            .postcode = owned.postcode,
            .state = owned.state,
            .signedBy = payload.signedBy,
            .signature = payload.signature,
            .createdAt = created_at,
        };
    }
};

// ── Serialisation helpers ────────────────────────────────────────────────────

fn serializeSiteCreated(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    payload: SitesStore.SitePayload,
    ts: i64,
) !void {
    try buf.print(allocator, "{{\"ts\":{d},\"kind\":\"created\",\"cellId\":\"", .{ts});
    try writeHex32(allocator, buf, &payload.cellId);
    try buf.appendSlice(allocator, "\",\"typeHash\":\"");
    try writeHex32(allocator, buf, &payload.typeHash);
    try buf.appendSlice(allocator, "\",\"normalisedAddress\":");
    try writeJsonString(allocator, buf, payload.normalisedAddress);
    try buf.appendSlice(allocator, ",\"keyNumber\":");
    if (payload.keyNumber) |kn| {
        try writeJsonString(allocator, buf, kn);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"lookupKey\":");
    try writeJsonString(allocator, buf, payload.lookupKey);
    try buf.appendSlice(allocator, ",\"fullAddress\":");
    try writeJsonString(allocator, buf, payload.fullAddress);
    try buf.appendSlice(allocator, ",\"suburb\":");
    if (payload.suburb) |s| {
        try writeJsonString(allocator, buf, s);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"postcode\":");
    if (payload.postcode) |p| {
        try writeJsonString(allocator, buf, p);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"state\":");
    if (payload.state) |st| {
        try writeJsonString(allocator, buf, st);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"signedBy\":");
    if (payload.signedBy) |sb| {
        try buf.append(allocator, '"');
        try writeHex33(allocator, buf, &sb);
        try buf.append(allocator, '"');
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"signature\":");
    if (payload.signature) |sig| {
        try buf.append(allocator, '"');
        try writeHex64(allocator, buf, &sig);
        try buf.append(allocator, '"');
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"createdAt\":");
    try buf.print(allocator, "{d}", .{ts});
    try buf.append(allocator, '}');
}

fn serializeSiteSigned(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    cell_id: [32]u8,
    signed_by: [33]u8,
    signature: [64]u8,
    ts: i64,
) !void {
    try buf.print(allocator, "{{\"ts\":{d},\"kind\":\"signed\",\"cellId\":\"", .{ts});
    try writeHex32(allocator, buf, &cell_id);
    try buf.appendSlice(allocator, "\",\"signedBy\":\"");
    try writeHex33(allocator, buf, &signed_by);
    try buf.appendSlice(allocator, "\",\"signature\":\"");
    try writeHex64(allocator, buf, &signature);
    try buf.append(allocator, '"');
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn writeHex32(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [32]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn writeHex33(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [33]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn writeHex64(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [64]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn optStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| {
        switch (v) {
            .string => |s| return s,
            else => return null,
        }
    }
    return null;
}

// ── Inline tests ──────────────────────────────────────────────────────────────

fn testClock() i64 {
    return 1_700_000_000;
}

const lmdb = @import("lmdb");
const lmdb_cell_store_mod = @import("lmdb_cell_store");

fn openInlineTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "SitesStore: appendCreated → getById → findByLookupKey round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var cellId: [32]u8 = undefined;
    @memset(&cellId, 0xab);
    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0xcd);

    const stored = try store.appendCreated(.{
        .cellId = cellId,
        .typeHash = typeHash,
        .normalisedAddress = "13 orealla cr",
        .keyNumber = "key #177",
        .lookupKey = "13 orealla cr|key #177",
        .fullAddress = "13 Orealla Cr, Surfers Paradise",
        .suburb = "Surfers Paradise",
        .postcode = "4217",
        .state = "QLD",
    });
    try std.testing.expectEqualSlices(u8, &cellId, &stored.cellId);
    try std.testing.expectEqualStrings("13 orealla cr", stored.normalisedAddress);
    try std.testing.expectEqualStrings("13 orealla cr|key #177", stored.lookupKey);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const got = store.getById(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("13 orealla cr", got.normalisedAddress);
    try std.testing.expectEqualStrings("Surfers Paradise", got.suburb.?);

    const by_lookup = store.findByLookupKey("13 orealla cr|key #177") orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId, &by_lookup.cellId);

    var other_id: [32]u8 = undefined;
    @memset(&other_id, 0xff);
    try std.testing.expect(store.getById(other_id) == null);
    try std.testing.expect(store.findByLookupKey("nope|") == null);
}

test "SitesStore: idempotent re-append returns same row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var cellId: [32]u8 = undefined;
    @memset(&cellId, 0x01);
    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0x02);

    const payload: SitesStore.SitePayload = .{
        .cellId = cellId,
        .typeHash = typeHash,
        .normalisedAddress = "1 example st",
        .keyNumber = null,
        .lookupKey = "1 example st|",
        .fullAddress = "1 Example St",
        .suburb = null,
        .postcode = null,
        .state = null,
    };
    const first = try store.appendCreated(payload);
    const second = try store.appendCreated(payload);
    try std.testing.expectEqualSlices(u8, &first.cellId, &second.cellId);
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "SitesStore: rejects empty / oversized fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var cellId: [32]u8 = undefined;
    @memset(&cellId, 0x03);
    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0x04);

    try std.testing.expectError(StoreError.invalid_normalised_address, store.appendCreated(.{
        .cellId = cellId,
        .typeHash = typeHash,
        .normalisedAddress = "",
        .keyNumber = null,
        .lookupKey = "x|",
        .fullAddress = "X",
        .suburb = null,
        .postcode = null,
        .state = null,
    }));

    var huge_pc: [MAX_POSTCODE_BYTES + 1]u8 = undefined;
    @memset(&huge_pc, '0');
    try std.testing.expectError(StoreError.invalid_postcode, store.appendCreated(.{
        .cellId = cellId,
        .typeHash = typeHash,
        .normalisedAddress = "x",
        .keyNumber = null,
        .lookupKey = "x|",
        .fullAddress = "X",
        .suburb = null,
        .postcode = &huge_pc,
        .state = null,
    }));
}

test "SitesStore: wide field envelopes round-trip correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var cellId: [32]u8 = undefined;
    @memset(&cellId, 0x05);
    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0x06);

    var na_buf: [MAX_NORMALISED_ADDRESS_BYTES]u8 = undefined;
    @memset(&na_buf, 'a');
    var fa_buf: [MAX_FULL_ADDRESS_BYTES]u8 = undefined;
    @memset(&fa_buf, 'f');
    var lk_buf: [MAX_NORMALISED_ADDRESS_BYTES + 1]u8 = undefined;
    @memset(lk_buf[0..MAX_NORMALISED_ADDRESS_BYTES], 'a');
    lk_buf[MAX_NORMALISED_ADDRESS_BYTES] = '|';
    var sub_buf: [MAX_SUBURB_BYTES]u8 = undefined;
    @memset(&sub_buf, 's');
    var st_buf: [MAX_STATE_BYTES]u8 = undefined;
    @memset(&st_buf, 't');

    _ = try store.appendCreated(.{
        .cellId = cellId,
        .typeHash = typeHash,
        .normalisedAddress = &na_buf,
        .keyNumber = null,
        .lookupKey = &lk_buf,
        .fullAddress = &fa_buf,
        .suburb = &sub_buf,
        .postcode = "9999",
        .state = &st_buf,
    });
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const got = store.getById(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(&na_buf, got.normalisedAddress);
    try std.testing.expectEqualStrings(&lk_buf, got.lookupKey);
    try std.testing.expectEqualStrings(&fa_buf, got.fullAddress);
    try std.testing.expectEqualStrings(&sub_buf, got.suburb.?);
    try std.testing.expectEqualStrings("9999", got.postcode.?);
    try std.testing.expectEqualStrings(&st_buf, got.state.?);
}

test "SitesStore: replay rebuilds both indexes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();

    var cellId_a: [32]u8 = undefined;
    @memset(&cellId_a, 0x07);
    var cellId_b: [32]u8 = undefined;
    @memset(&cellId_b, 0x08);
    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0x09);

    {
        var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
        const cs = cs_impl.store();
        var store = try SitesStore.init(allocator, &cs, testClock);
        defer store.deinit();
        _ = try store.appendCreated(.{
            .cellId = cellId_a,
            .typeHash = typeHash,
            .normalisedAddress = "1 a st",
            .keyNumber = null,
            .lookupKey = "1 a st|",
            .fullAddress = "1 A St",
            .suburb = null,
            .postcode = null,
            .state = null,
        });
        _ = try store.appendCreated(.{
            .cellId = cellId_b,
            .typeHash = typeHash,
            .normalisedAddress = "2 b \"quoted\" rd",
            .keyNumber = "unit 5",
            .lookupKey = "2 b \"quoted\" rd|unit 5",
            .fullAddress = "2 B Rd",
            .suburb = "Brisbane",
            .postcode = "4000",
            .state = "QLD",
        });
    }

    var cs_impl2 = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try SitesStore.init(allocator, &cs2, testClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 2), store2.count());

    const a = store2.getById(cellId_a) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("1 a st", a.normalisedAddress);
    try std.testing.expect(a.keyNumber == null);

    const b = store2.findByLookupKey("2 b \"quoted\" rd|unit 5") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("2 b \"quoted\" rd", b.normalisedAddress);
    try std.testing.expectEqualStrings("unit 5", b.keyNumber.?);
    try std.testing.expectEqualStrings("Brisbane", b.suburb.?);
    try std.testing.expectEqualStrings("4000", b.postcode.?);
    try std.testing.expectEqualStrings("QLD", b.state.?);
    try std.testing.expect(b.signedBy == null);
    try std.testing.expect(b.signature == null);
}

test "SitesStore: listAll returns rows in insertion order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var typeHash: [32]u8 = undefined;
    @memset(&typeHash, 0x0a);

    inline for (.{ 0x10, 0x11, 0x12 }) |b| {
        var cellId: [32]u8 = undefined;
        @memset(&cellId, b);
        const lk_str = std.fmt.comptimePrint("{d}|", .{b});
        _ = try store.appendCreated(.{
            .cellId = cellId,
            .typeHash = typeHash,
            .normalisedAddress = lk_str[0 .. lk_str.len - 1],
            .keyNumber = null,
            .lookupKey = lk_str,
            .fullAddress = "X",
            .suburb = null,
            .postcode = null,
            .state = null,
        });
    }

    const all = try store.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 3), all.len);
    try std.testing.expectEqual(@as(u8, 0x10), all[0].cellId[0]);
    try std.testing.expectEqual(@as(u8, 0x11), all[1].cellId[0]);
    try std.testing.expectEqual(@as(u8, 0x12), all[2].cellId[0]);
}

```
