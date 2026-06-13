---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/customers_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.544262+00:00
---

# cartridges/oddjobz/brain/zig/src/customers_store_lmdb.zig

```zig
// W0.2 — Customers store backed by LmdbCellStore (replaces customers_store_fs.zig).
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5;
//            cartridges/oddjobz/brain/src/cell-types/customer.v2.ts (v2 schema).
//
// Each customer entity is serialised as a JSON payload packed into a
// 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/appendCreatedV2 call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory state
// is NOT updated — the FSM sees an error and returns without partial state.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_CUSTOMER (0x01) and replays them to rebuild the in-memory index.
//
// The public API is identical to the old customers_store_fs.CustomersStore
// so all existing callers (handlers, cli.zig, conformance tests) require
// only the change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114c — encode a customer buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// Linearity: AFFINE (active) by default; archived → RELEVANT.
fn encodeCustomerAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_CUSTOMER, state);
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_CUSTOMER,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_CUSTOMER, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_id,
    invalid_display_name,
    invalid_phone,
    invalid_email,
    invalid_address,
    invalid_notes,
    invalid_normalised_phone,
    invalid_provider_id,
    invalid_provider_item_id,
    invalid_extracted_at,
};

/// Customer roles relative to the linked job/site (v2).  Mirrors the
/// `CUSTOMER_ROLES` enum in `cartridges/oddjobz/brain/src/cell-types/
/// customer.v2.ts` verbatim.  v1 rows have `role == null`.
pub const CustomerRole = enum {
    tenant,
    agent,
    owner,
    pm,
    sub_tradie,
    other,

    pub fn toString(self: CustomerRole) []const u8 {
        return switch (self) {
            .tenant => "tenant",
            .agent => "agent",
            .owner => "owner",
            .pm => "pm",
            .sub_tradie => "sub-tradie",
            .other => "other",
        };
    }

    pub fn fromString(s: []const u8) ?CustomerRole {
        if (std.mem.eql(u8, s, "tenant")) return .tenant;
        if (std.mem.eql(u8, s, "agent")) return .agent;
        if (std.mem.eql(u8, s, "owner")) return .owner;
        if (std.mem.eql(u8, s, "pm")) return .pm;
        if (std.mem.eql(u8, s, "sub-tradie")) return .sub_tradie;
        if (std.mem.eql(u8, s, "other")) return .other;
        return null;
    }
};

pub const CustomerSourceProvenance = struct {
    providerId: []const u8,
    providerItemId: []const u8,
    extractedAt: []const u8,
};

pub const Customer = struct {
    // ── v1 fields ─────────────────────────────────────────────────────
    id: []const u8,
    display_name: []const u8,
    phone: []const u8,
    email: []const u8,
    address: []const u8,
    notes: []const u8,
    created_at: []const u8,

    // ── v2 graph-aware fields (null on legacy v1 rows) ────────────────
    cellId: ?[32]u8 = null,
    typeHash: ?[32]u8 = null,
    role: ?CustomerRole = null,
    normalisedPhone: ?[]const u8 = null,
    sourceProvenance: ?CustomerSourceProvenance = null,
    siteRef: ?[32]u8 = null,
    signedBy: ?[33]u8 = null,
    signature: ?[64]u8 = null,
};

pub const MAX_DISPLAY_NAME_BYTES: usize = 200;
pub const MAX_ID_BYTES: usize = 64;
pub const MAX_PHONE_BYTES: usize = 50;
pub const MAX_EMAIL_BYTES: usize = 200;
pub const MAX_ADDRESS_BYTES: usize = 500;
pub const MAX_NOTES_BYTES: usize = 2000;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_NORMALISED_PHONE_BYTES: usize = 32;
pub const MAX_PROVIDER_ID_BYTES: usize = 64;
pub const MAX_PROVIDER_ITEM_ID_BYTES: usize = 256;
pub const MAX_EXTRACTED_AT_BYTES: usize = 64;

const OwnedStrings = struct {
    id: []u8,
    display_name: []u8,
    phone: []u8,
    email: []u8,
    address: []u8,
    notes: []u8,
    created_at: []u8,
    normalised_phone: ?[]u8 = null,
    provider_id: ?[]u8 = null,
    provider_item_id: ?[]u8 = null,
    extracted_at: ?[]u8 = null,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.display_name);
        allocator.free(self.phone);
        allocator.free(self.email);
        allocator.free(self.address);
        allocator.free(self.notes);
        allocator.free(self.created_at);
        if (self.normalised_phone) |s| allocator.free(s);
        if (self.provider_id) |s| allocator.free(s);
        if (self.provider_item_id) |s| allocator.free(s);
        if (self.extracted_at) |s| allocator.free(s);
    }
};

/// RM-119 — pure ingest→customer field mapping (no store, no LMDB),
/// extracted so the judgment-laden part (shape discrimination + the
/// name→display_name / clamp / role decisions) is unit-tested in this
/// file's "pure logic" test convention. Slices borrow from `obj`
/// (valid while the caller's parsed JSON is alive).
const IngestCustomerView = struct {
    display_name: []const u8,
    phone: []const u8,
    email: []const u8,
    notes: []const u8,
    role: ?CustomerRole,
};

/// Returns the mapped view iff `obj` is the gmail/Bricks ingest
/// customer shape: has a non-empty in-bounds `name`, and lacks the
/// brain-native `id` + `display_name` (those take the applyPayload
/// path). Null ⇒ not ingest-shape / invalid ⇒ caller no-ops.
fn mapIngestCustomer(obj: std.json.ObjectMap) ?IngestCustomerView {
    if (obj.get("id") != null) return null;
    if (obj.get("display_name") != null) return null;
    const name_v = obj.get("name") orelse return null;
    if (name_v != .string or name_v.string.len == 0 or
        name_v.string.len > MAX_DISPLAY_NAME_BYTES) return null;

    const sclamp = struct {
        fn f(o: std.json.ObjectMap, key: []const u8, max: usize) []const u8 {
            if (o.get(key)) |v| {
                if (v == .string and v.string.len <= max) return v.string;
            }
            return "";
        }
    }.f;

    var role_opt: ?CustomerRole = null;
    if (obj.get("role")) |rv| {
        if (rv == .string) role_opt = CustomerRole.fromString(rv.string);
    }

    return .{
        .display_name = name_v.string,
        .phone = sclamp(obj, "phone", MAX_PHONE_BYTES),
        .email = sclamp(obj, "email", MAX_EMAIL_BYTES),
        .notes = sclamp(obj, "notes", MAX_NOTES_BYTES),
        .role = role_opt,
    };
}

pub const CustomersStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Customer),
    by_id: std.StringHashMap(usize),
    by_cell_id: std.StringHashMap(usize),
    cell_id_keys: std.ArrayList([]u8),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !CustomersStore {
        var self = CustomersStore{
            .allocator = allocator,
            .cell_store = cell_store,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .by_cell_id = std.StringHashMap(usize).init(allocator),
            .cell_id_keys = .{},
            .owned_strings = .{},
            .clock = clock_fn,
        };
        try self.replayCellStore();
        return self;
    }

    pub fn deinit(self: *CustomersStore) void {
        self.records.deinit(self.allocator);
        self.by_id.deinit();
        self.by_cell_id.deinit();
        for (self.cell_id_keys.items) |k| self.allocator.free(k);
        self.cell_id_keys.deinit(self.allocator);
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
    }

    /// Append a v1 customer.  K4: encodes cell, writes to LMDB, then
    /// updates in-memory state.  If put() fails, returns error without
    /// any in-memory mutation.
    pub fn append(self: *CustomersStore, customer: Customer) !AppendOutcome {
        if (customer.id.len == 0 or customer.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (customer.display_name.len == 0 or customer.display_name.len > MAX_DISPLAY_NAME_BYTES) return StoreError.invalid_display_name;
        if (customer.phone.len > MAX_PHONE_BYTES) return StoreError.invalid_phone;
        if (customer.email.len > MAX_EMAIL_BYTES) return StoreError.invalid_email;
        if (customer.address.len > MAX_ADDRESS_BYTES) return StoreError.invalid_address;
        if (customer.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;

        const existing_idx = self.by_id.get(customer.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(customer, false);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneCustomerIntoArena(.{
            .id = customer.id,
            .display_name = customer.display_name,
            .phone = customer.phone,
            .email = customer.email,
            .address = customer.address,
            .notes = customer.notes,
            .created_at = customer.created_at,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub const CustomerV2Payload = struct {
        id: []const u8,
        display_name: []const u8,
        phone: []const u8 = "",
        email: []const u8 = "",
        address: []const u8 = "",
        notes: []const u8 = "",
        created_at: []const u8,
        cellId: [32]u8,
        typeHash: [32]u8,
        role: CustomerRole,
        normalisedPhone: ?[]const u8,
        sourceProvenance: CustomerSourceProvenance,
        siteRef: ?[32]u8,
        signedBy: ?[33]u8 = null,
        signature: ?[64]u8 = null,
    };

    /// Append a v2-shape customer.  K4: writes cell to LMDB before
    /// in-memory update.
    pub fn appendCreatedV2(self: *CustomersStore, payload: CustomerV2Payload) !AppendOutcome {
        if (payload.id.len == 0 or payload.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (payload.display_name.len == 0 or payload.display_name.len > MAX_DISPLAY_NAME_BYTES) return StoreError.invalid_display_name;
        if (payload.phone.len > MAX_PHONE_BYTES) return StoreError.invalid_phone;
        if (payload.email.len > MAX_EMAIL_BYTES) return StoreError.invalid_email;
        if (payload.address.len > MAX_ADDRESS_BYTES) return StoreError.invalid_address;
        if (payload.notes.len > MAX_NOTES_BYTES) return StoreError.invalid_notes;
        if (payload.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_address;

        if (payload.normalisedPhone) |np| {
            if (np.len == 0 or np.len > MAX_NORMALISED_PHONE_BYTES) return StoreError.invalid_normalised_phone;
        }
        const prov = payload.sourceProvenance;
        if (prov.providerId.len == 0 or prov.providerId.len > MAX_PROVIDER_ID_BYTES) return StoreError.invalid_provider_id;
        if (prov.providerItemId.len == 0 or prov.providerItemId.len > MAX_PROVIDER_ITEM_ID_BYTES) return StoreError.invalid_provider_item_id;
        if (prov.extractedAt.len == 0 or prov.extractedAt.len > MAX_EXTRACTED_AT_BYTES) return StoreError.invalid_extracted_at;

        const id_hex_arr = std.fmt.bytesToHex(payload.cellId, .lower);
        const id_hex: []const u8 = id_hex_arr[0..];
        const existing_cell_idx = self.by_cell_id.get(id_hex);
        const existing_uuid_idx = self.by_id.get(payload.id);

        // K4: build Customer struct, write to LMDB first.
        const stub: Customer = .{
            .id = payload.id,
            .display_name = payload.display_name,
            .phone = payload.phone,
            .email = payload.email,
            .address = payload.address,
            .notes = payload.notes,
            .created_at = payload.created_at,
            .cellId = payload.cellId,
            .typeHash = payload.typeHash,
            .role = payload.role,
            .normalisedPhone = payload.normalisedPhone,
            .sourceProvenance = payload.sourceProvenance,
            .siteRef = payload.siteRef,
            .signedBy = payload.signedBy,
            .signature = payload.signature,
        };
        try self.putCell(stub, true);

        if (existing_cell_idx != null or existing_uuid_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneCustomerIntoArena(stub);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        const id_key_owned = try self.dupIdKey(id_hex);
        try self.by_cell_id.put(id_key_owned, idx);
        return .created;
    }

    pub fn findAll(self: *const CustomersStore, allocator: std.mem.Allocator) ![]Customer {
        const out = try allocator.alloc(Customer, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn listAll(self: *const CustomersStore, allocator: std.mem.Allocator) ![]Customer {
        return self.findAll(allocator);
    }

    pub fn findById(self: *const CustomersStore, id: []const u8) ?Customer {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByName(self: *const CustomersStore, allocator: std.mem.Allocator, query: []const u8) ![]Customer {
        if (query.len == 0) return self.findAll(allocator);

        var n: usize = 0;
        for (self.records.items) |r| {
            if (containsIgnoreCase(r.display_name, query)) n += 1;
        }
        const out = try allocator.alloc(Customer, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (containsIgnoreCase(r.display_name, query)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const CustomersStore) usize {
        return self.records.items.len;
    }

    pub fn getByCellId(self: *const CustomersStore, cellId: [32]u8) ?Customer {
        const id_hex_arr = std.fmt.bytesToHex(cellId, .lower);
        const idx = self.by_cell_id.get(id_hex_arr[0..]) orelse return null;
        return self.records.items[idx];
    }

    pub const CustomerDedupeKey = union(enum) {
        phone: []const u8,
        email: []const u8,
        nameRoleAndSite: struct {
            name: []const u8,
            role: CustomerRole,
            siteRef: [32]u8,
        },
    };

    pub fn findByDedupeKey(self: *const CustomersStore, key: CustomerDedupeKey) ?Customer {
        switch (key) {
            .phone => |needle| {
                if (needle.len == 0) return null;
                for (self.records.items) |r| {
                    if (r.normalisedPhone) |np| {
                        if (std.mem.eql(u8, np, needle)) return r;
                    }
                }
                return null;
            },
            .email => |needle| {
                if (needle.len == 0) return null;
                for (self.records.items) |r| {
                    if (r.email.len == 0) continue;
                    if (std.mem.eql(u8, r.email, needle)) return r;
                }
                return null;
            },
            .nameRoleAndSite => |triple| {
                if (triple.name.len == 0) return null;
                for (self.records.items) |r| {
                    const r_role = r.role orelse continue;
                    const r_site = r.siteRef orelse continue;
                    if (r_role != triple.role) continue;
                    if (!std.mem.eql(u8, &r_site, &triple.siteRef)) continue;
                    if (!std.mem.eql(u8, r.display_name, triple.name)) continue;
                    return r;
                }
                return null;
            },
        }
    }

    pub fn appendSigned(
        self: *CustomersStore,
        cell_id: [32]u8,
        signed_by: [33]u8,
        signature: [64]u8,
    ) !void {
        // Update in-memory record.
        for (self.records.items, 0..) |row, idx| {
            const row_cid = row.cellId orelse continue;
            if (std.mem.eql(u8, &row_cid, &cell_id)) {
                self.records.items[idx].signedBy = signed_by;
                self.records.items[idx].signature = signature;
                // Write updated cell to LMDB (K4: best-effort; signing is
                // idempotent so failure is non-fatal for in-memory state).
                self.putCell(self.records.items[idx], true) catch {};
                return;
            }
        }
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    /// Encode `customer` as a JSON payload and write to LMDB cell store.
    /// K4: caller must NOT update in-memory state before this returns ok.
    fn putCell(self: *CustomersStore, customer: Customer, is_v2: bool) !void {
        _ = is_v2;
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeCustomer(self.allocator, &buf, customer, self.clock());
        // Silently skip persistence for oversized payloads — the record stays
        // in-memory but won't be replayed after a restart.  This is a graceful
        // degradation for records that hit the 1008-byte cell payload limit.
        const cell = encodeCustomerAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *CustomersStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);

        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            // RM-114c — dual-format read.
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_CUSTOMER) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_CUSTOMER.domain_flag) continue;
                break :blk decoded.payload;
            };
            self.applyPayload(payload) catch {}; // skip malformed
            // RM-119 — ingest-shape customer cell (no id/display_name).
            // applyPayload no-ops on it; this adapts it to a v1 record.
            // Self-discriminating + idempotent (no-ops on brain-native).
            // content_hash = sha256(cell) = the cell's LMDB key (op_pkh-less),
            // the value job customer_refs point at — stamped as cellId so
            // cell.query + dedupe-lookup resolve it (§6.1 / §6.2).
            var content_hash: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(cell_ptr[0..substrate_entity.CELL_BYTES], &content_hash, .{});
            self.applyIngestCustomerPayload(payload, content_hash) catch {};
        }
    }

    fn applyPayload(self: *CustomersStore, payload: []const u8) !void {
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

        const display_name_v = obj.get("display_name") orelse return;
        if (display_name_v != .string) return;
        const display_name = display_name_v.string;
        if (display_name.len == 0 or display_name.len > MAX_DISPLAY_NAME_BYTES) return;

        const phone = if (obj.get("phone")) |v| (if (v == .string) v.string else "") else "";
        const email = if (obj.get("email")) |v| (if (v == .string) v.string else "") else "";
        const address = if (obj.get("address")) |v| (if (v == .string) v.string else "") else "";
        const notes = if (obj.get("notes")) |v| (if (v == .string) v.string else "") else "";
        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        // v2 fields
        var cell_id_opt: ?[32]u8 = null;
        var type_hash_opt: ?[32]u8 = null;
        var role_opt: ?CustomerRole = null;
        var normalised_phone_opt: ?[]const u8 = null;
        var provenance_opt: ?CustomerSourceProvenance = null;
        var site_ref_opt: ?[32]u8 = null;
        var signed_by_opt: ?[33]u8 = null;
        var signature_opt: ?[64]u8 = null;

        if (obj.get("cellId")) |cell_v| dec_v2: {
            if (cell_v != .string or cell_v.string.len != 64) break :dec_v2;
            var cell_id: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&cell_id, cell_v.string) catch break :dec_v2;

            const type_v = obj.get("typeHash") orelse break :dec_v2;
            if (type_v != .string or type_v.string.len != 64) break :dec_v2;
            var type_hash: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&type_hash, type_v.string) catch break :dec_v2;

            const role_v = obj.get("role") orelse break :dec_v2;
            if (role_v != .string) break :dec_v2;
            const role = CustomerRole.fromString(role_v.string) orelse break :dec_v2;

            const np: ?[]const u8 = blk_np: {
                if (obj.get("normalisedPhone")) |v| {
                    switch (v) {
                        .string => |s| {
                            if (s.len == 0 or s.len > MAX_NORMALISED_PHONE_BYTES) break :blk_np null;
                            break :blk_np s;
                        },
                        else => break :blk_np null,
                    }
                }
                break :blk_np null;
            };

            const prov_v = obj.get("sourceProvenance") orelse break :dec_v2;
            if (prov_v != .object) break :dec_v2;
            const prov_obj = prov_v.object;
            const prov_pid = prov_obj.get("providerId") orelse break :dec_v2;
            if (prov_pid != .string) break :dec_v2;
            const prov_pii = prov_obj.get("providerItemId") orelse break :dec_v2;
            if (prov_pii != .string) break :dec_v2;
            const prov_ext = prov_obj.get("extractedAt") orelse break :dec_v2;
            if (prov_ext != .string) break :dec_v2;

            const sref: ?[32]u8 = blk_sref: {
                if (obj.get("siteRef")) |v| {
                    switch (v) {
                        .string => |s| {
                            if (s.len != 64) break :blk_sref null;
                            var sref_bytes: [32]u8 = undefined;
                            _ = std.fmt.hexToBytes(&sref_bytes, s) catch break :blk_sref null;
                            break :blk_sref sref_bytes;
                        },
                        else => break :blk_sref null,
                    }
                }
                break :blk_sref null;
            };

            cell_id_opt = cell_id;
            type_hash_opt = type_hash;
            role_opt = role;
            normalised_phone_opt = np;
            provenance_opt = .{
                .providerId = prov_pid.string,
                .providerItemId = prov_pii.string,
                .extractedAt = prov_ext.string,
            };
            site_ref_opt = sref;
        }

        if (obj.get("signedBy")) |v| {
            if (v == .string and v.string.len == 66) {
                var sb: [33]u8 = undefined;
                if (std.fmt.hexToBytes(&sb, v.string)) |_| {
                    signed_by_opt = sb;
                } else |_| {}
            }
        }
        if (obj.get("signature")) |v| {
            if (v == .string and v.string.len == 128) {
                var sig: [64]u8 = undefined;
                if (std.fmt.hexToBytes(&sig, v.string)) |_| {
                    signature_opt = sig;
                } else |_| {}
            }
        }

        // Idempotent: skip duplicates.
        if (self.by_id.contains(id)) return;
        if (cell_id_opt) |cid| {
            const id_hex_arr = std.fmt.bytesToHex(cid, .lower);
            if (self.by_cell_id.contains(id_hex_arr[0..])) return;
        }

        const stored = try self.cloneCustomerIntoArena(.{
            .id = id,
            .display_name = display_name,
            .phone = phone,
            .email = email,
            .address = address,
            .notes = notes,
            .created_at = created_at,
            .cellId = cell_id_opt,
            .typeHash = type_hash_opt,
            .role = role_opt,
            .normalisedPhone = normalised_phone_opt,
            .sourceProvenance = provenance_opt,
            .siteRef = site_ref_opt,
            .signedBy = signed_by_opt,
            .signature = signature_opt,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        if (cell_id_opt) |cid| {
            const id_hex_arr = std.fmt.bytesToHex(cid, .lower);
            const id_key_owned = try self.dupIdKey(id_hex_arr[0..]);
            try self.by_cell_id.put(id_key_owned, idx);
        }
    }

    /// RM-119 — ingest→customer schema adapter (operator-approved
    /// 2026-05-19; sibling of jobs_store_lmdb_entity.applyIngestJob
    /// Payload). The gmail/Bricks ingest writes customer cells as
    /// `{name,email,phone,role,linked_site_id,notes,state}` — NO `id`,
    /// NO `display_name`, NO `created_at`, so `applyPayload` bails at
    /// `obj.get("id") orelse return` and all 170 ingested customers
    /// were skipped (`find customers` = []). RM-115 migration faith-
    /// fully preserved the ingest JSON; this is a READER adapter (no
    /// data mutation) mapping the ingest shape onto a v1 customer
    /// record. Idempotent: id = hex(sha256(payload)[0..32]) is stable
    /// per cell, guarded by `by_id.contains`. Best-effort — malformed
    /// payloads are skipped, never fatal. Self-discriminating, so it
    /// is safe to call unconditionally alongside applyPayload (each
    /// no-ops on the other's shape).
    /// `content_hash` is the cell's content hash = sha256(cell) = its LMDB key
    /// (minus the 8-byte op_pkh prefix). The 2026-06-10 prod census proved
    /// job `customer_refs[].cell_id` (and `site_ref`) point at exactly this
    /// value (261/261, 233/233), and that canonical customer payloads carry NO
    /// logical `cellId` field — so stamping `cellId = content_hash` is the
    /// unique correct identity: it makes `enumerate`/`getByCellId`/cell.query
    /// resolve these cells (was the §6.1 0-rows bug) and gives `findByDedupeKey`
    /// a real cell id to return (the §6.2 brain-backed view).
    fn applyIngestCustomerPayload(
        self: *CustomersStore,
        payload: []const u8,
        content_hash: [32]u8,
    ) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            payload,
            .{},
        ) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;
        const v = mapIngestCustomer(obj) orelse return;

        // Stable, deterministic logical id (idempotent across replays). Kept
        // distinct from cellId — `id` is the payload-derived uuid the app's v1
        // rows carry; `cellId` is the content-addressed cell identity.
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
        const id_hex = std.fmt.bytesToHex(digest, .lower); // [64]u8
        const id: []const u8 = id_hex[0..];
        if (self.by_id.contains(id)) return;

        // Canonical ingest cells carry the resolved (deduped) site as a 64-hex
        // `linked_site_id`; surface it as siteRef so the nameRoleAndSite dedupe
        // key matches. normalisedPhone = raw phone (what the ingest writer sets).
        var site_ref_opt: ?[32]u8 = null;
        if (obj.get("linked_site_id")) |sv| {
            if (sv == .string and sv.string.len == 64) {
                var sref: [32]u8 = undefined;
                if (std.fmt.hexToBytes(&sref, sv.string)) |_| {
                    site_ref_opt = sref;
                } else |_| {}
            }
        }
        const np_opt: ?[]const u8 =
            if (v.phone.len > 0 and v.phone.len <= MAX_NORMALISED_PHONE_BYTES) v.phone else null;

        const stored = try self.cloneCustomerIntoArena(.{
            .id = id,
            .display_name = v.display_name,
            .phone = v.phone,
            .email = v.email,
            .address = "",
            .notes = v.notes,
            .created_at = "",
            .cellId = content_hash,
            .role = v.role,
            .normalisedPhone = np_opt,
            .siteRef = site_ref_opt,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        // Index by content hash so getByCellId(ref)/enumerate resolve it.
        const cid_hex = std.fmt.bytesToHex(content_hash, .lower);
        if (!self.by_cell_id.contains(cid_hex[0..])) {
            const cid_key = try self.dupIdKey(cid_hex[0..]);
            try self.by_cell_id.put(cid_key, idx);
        }
    }

    fn dupIdKey(self: *CustomersStore, id_hex: []const u8) ![]const u8 {
        const owned = try self.allocator.dupe(u8, id_hex);
        errdefer self.allocator.free(owned);
        try self.cell_id_keys.append(self.allocator, owned);
        return owned;
    }

    fn cloneCustomerIntoArena(self: *CustomersStore, customer: Customer) !Customer {
        var owned: OwnedStrings = .{
            .id = undefined,
            .display_name = undefined,
            .phone = undefined,
            .email = undefined,
            .address = undefined,
            .notes = undefined,
            .created_at = undefined,
            .normalised_phone = null,
            .provider_id = null,
            .provider_item_id = null,
            .extracted_at = null,
        };
        owned.id = try self.allocator.dupe(u8, customer.id);
        errdefer self.allocator.free(owned.id);
        owned.display_name = try self.allocator.dupe(u8, customer.display_name);
        errdefer self.allocator.free(owned.display_name);
        owned.phone = try self.allocator.dupe(u8, customer.phone);
        errdefer self.allocator.free(owned.phone);
        owned.email = try self.allocator.dupe(u8, customer.email);
        errdefer self.allocator.free(owned.email);
        owned.address = try self.allocator.dupe(u8, customer.address);
        errdefer self.allocator.free(owned.address);
        owned.notes = try self.allocator.dupe(u8, customer.notes);
        errdefer self.allocator.free(owned.notes);
        owned.created_at = try self.allocator.dupe(u8, customer.created_at);
        errdefer self.allocator.free(owned.created_at);

        if (customer.normalisedPhone) |np| {
            owned.normalised_phone = try self.allocator.dupe(u8, np);
        }
        errdefer if (owned.normalised_phone) |s| self.allocator.free(s);

        var sourceProv: ?CustomerSourceProvenance = null;
        if (customer.sourceProvenance) |prov| {
            owned.provider_id = try self.allocator.dupe(u8, prov.providerId);
            errdefer self.allocator.free(owned.provider_id.?);
            owned.provider_item_id = try self.allocator.dupe(u8, prov.providerItemId);
            errdefer self.allocator.free(owned.provider_item_id.?);
            owned.extracted_at = try self.allocator.dupe(u8, prov.extractedAt);
            errdefer self.allocator.free(owned.extracted_at.?);
            sourceProv = .{
                .providerId = owned.provider_id.?,
                .providerItemId = owned.provider_item_id.?,
                .extractedAt = owned.extracted_at.?,
            };
        }

        try self.owned_strings.append(self.allocator, owned);

        return .{
            .id = owned.id,
            .display_name = owned.display_name,
            .phone = owned.phone,
            .email = owned.email,
            .address = owned.address,
            .notes = owned.notes,
            .created_at = owned.created_at,
            .cellId = customer.cellId,
            .typeHash = customer.typeHash,
            .role = customer.role,
            .normalisedPhone = owned.normalised_phone,
            .sourceProvenance = sourceProv,
            .siteRef = customer.siteRef,
            .signedBy = customer.signedBy,
            .signature = customer.signature,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeCustomer(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    customer: Customer,
    ts: i64,
) !void {
    _ = ts;
    try buf.appendSlice(allocator, "{\"kind\":\"created\",\"id\":");
    try writeJsonString(allocator, buf, customer.id);
    try buf.appendSlice(allocator, ",\"display_name\":");
    try writeJsonString(allocator, buf, customer.display_name);
    try buf.appendSlice(allocator, ",\"phone\":");
    try writeJsonString(allocator, buf, customer.phone);
    try buf.appendSlice(allocator, ",\"email\":");
    try writeJsonString(allocator, buf, customer.email);
    try buf.appendSlice(allocator, ",\"address\":");
    try writeJsonString(allocator, buf, customer.address);
    try buf.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, buf, customer.notes);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, customer.created_at);

    if (customer.cellId) |cid| {
        const hex = std.fmt.bytesToHex(cid, .lower);
        try buf.appendSlice(allocator, ",\"cellId\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (customer.typeHash) |th| {
        const hex = std.fmt.bytesToHex(th, .lower);
        try buf.appendSlice(allocator, ",\"typeHash\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (customer.role) |r| {
        try buf.appendSlice(allocator, ",\"role\":");
        try writeJsonString(allocator, buf, r.toString());
    }
    if (customer.normalisedPhone) |np| {
        try buf.appendSlice(allocator, ",\"normalisedPhone\":");
        try writeJsonString(allocator, buf, np);
    }
    if (customer.sourceProvenance) |prov| {
        try buf.appendSlice(allocator, ",\"sourceProvenance\":{\"providerId\":");
        try writeJsonString(allocator, buf, prov.providerId);
        try buf.appendSlice(allocator, ",\"providerItemId\":");
        try writeJsonString(allocator, buf, prov.providerItemId);
        try buf.appendSlice(allocator, ",\"extractedAt\":");
        try writeJsonString(allocator, buf, prov.extractedAt);
        try buf.append(allocator, '}');
    }
    if (customer.siteRef) |sref| {
        const hex = std.fmt.bytesToHex(sref, .lower);
        try buf.appendSlice(allocator, ",\"siteRef\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (customer.signedBy) |sb| {
        const hex = std.fmt.bytesToHex(sb, .lower);
        try buf.appendSlice(allocator, ",\"signedBy\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (customer.signature) |sig| {
        const hex = std.fmt.bytesToHex(sig, .lower);
        try buf.appendSlice(allocator, ",\"signature\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            const a = std.ascii.toLower(haystack[i + j]);
            const b = std.ascii.toLower(needle[j]);
            if (a != b) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic (no LMDB required).
// ─────────────────────────────────────────────────────────────────────

test "containsIgnoreCase: matches case-insensitively" {
    try std.testing.expect(containsIgnoreCase("Acme Corp", "acme"));
    try std.testing.expect(containsIgnoreCase("Acme Corp", "ACME"));
    try std.testing.expect(containsIgnoreCase("Acme Corp", "rp"));
    try std.testing.expect(containsIgnoreCase("Acme Corp", ""));
    try std.testing.expect(!containsIgnoreCase("Acme Corp", "globex"));
    try std.testing.expect(!containsIgnoreCase("Acme", "acme corp"));
}

test "RM-119 mapIngestCustomer: ingest shape maps; brain-native + invalid → null" {
    const allocator = std.testing.allocator;

    // Real gmail/Bricks ingest customer payload (no id/display_name/
    // created_at; `name` + email/phone/role/notes/state). Pre-RM-119
    // applyPayload bailed at `obj.get("id") orelse return`.
    const ingest =
        \\{"name":"Zoe Welch","email":"zoe.welch@cleverproperty.com.au","phone":"0754730508","role":"agent","linked_site_id":"7dfb737b","notes":null,"state":"active"}
    ;
    {
        const p = try std.json.parseFromSlice(std.json.Value, allocator, ingest, .{});
        defer p.deinit();
        const v = mapIngestCustomer(p.value.object) orelse return error.IngestCustomerNotMapped;
        try std.testing.expectEqualStrings("Zoe Welch", v.display_name);
        try std.testing.expectEqualStrings("zoe.welch@cleverproperty.com.au", v.email);
        try std.testing.expectEqualStrings("0754730508", v.phone);
        try std.testing.expectEqualStrings("", v.notes); // null → ""
        try std.testing.expect(v.role != null); // "agent" parsed
    }

    // Brain-native shape (has id + display_name) → null (applyPayload's job).
    {
        const native =
            \\{"kind":"created","id":"abc","display_name":"X","phone":"","email":"","address":"","notes":"","created_at":"2026-01-01T00:00:00Z"}
        ;
        const p = try std.json.parseFromSlice(std.json.Value, allocator, native, .{});
        defer p.deinit();
        try std.testing.expect(mapIngestCustomer(p.value.object) == null);
    }

    // Missing `name` → null (not a usable ingest customer).
    {
        const noname =
            \\{"email":"a@b.c","phone":"1","role":"tenant","state":"active"}
        ;
        const p = try std.json.parseFromSlice(std.json.Value, allocator, noname, .{});
        defer p.deinit();
        try std.testing.expect(mapIngestCustomer(p.value.object) == null);
    }
}

// ── §6.1/§6.2 — cellId-stamp on ingest-shape replay (LMDB-backed) ───────────
//
// Proves the 2026-06-10 census fix: a canonical ingest-shape customer cell
// (name/role/linked_site_id, NO logical cellId) loads with cellId = the cell's
// content hash, so it is resolvable by the value job customer_refs point at
// (was the §6.1 cell.query 0-rows bug) and findByDedupeKey returns a row with a
// real cellId (the §6.2 brain-backed dedupe view).

const lmdb = @import("lmdb");
const lmdb_cell_store_test_mod = @import("lmdb_cell_store");

fn testClockC() i64 {
    return 1_700_000_000;
}

fn openInlineTestEnvC(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "ingest-shape customer cell loads with cellId=content hash → resolvable + dedupe-able (§6.1/§6.2)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnvC(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    // Canonical prod shape: name/role/email/phone/linked_site_id — NO
    // id/display_name/cellId (the census-confirmed 152-customer shape).
    const site_hex = "11" ** 32; // 64 hex chars
    const payload =
        "{\"name\":\"Tanya Healy\",\"role\":\"agent\",\"email\":\"tanya@clever.com\"," ++
        "\"phone\":\"0400000001\",\"linked_site_id\":\"" ++ site_hex ++ "\",\"state\":\"active\"}";
    const cell = try encodeCustomerAsSubstrate(payload);
    const chash = try cs.put(&cell); // put returns the content hash (= LMDB key)

    var store = try CustomersStore.init(allocator, &cs, testClockC);
    defer store.deinit();

    // §6.1 — resolvable by the content hash (the value job customer_refs point at).
    const got = store.getByCellId(chash) orelse return error.NotResolvableByContentHash;
    try std.testing.expectEqualStrings("Tanya Healy", got.display_name);
    try std.testing.expect(got.cellId != null);
    try std.testing.expectEqualSlices(u8, &chash, &got.cellId.?);

    // siteRef surfaced from linked_site_id (for the nameRoleAndSite dedupe key).
    try std.testing.expect(got.siteRef != null);
    var want_site: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&want_site, site_hex);
    try std.testing.expectEqualSlices(u8, &want_site, &got.siteRef.?);

    // enumerate path: listAll carries a non-null cellId.
    const all = try store.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 1), all.len);
    try std.testing.expect(all[0].cellId != null);

    // §6.2 — findByDedupeKey(.email) returns the row WITH the content-hash cellId.
    const by_email = store.findByDedupeKey(.{ .email = "tanya@clever.com" }) orelse
        return error.NoEmailDedupeHit;
    try std.testing.expect(by_email.cellId != null);
    try std.testing.expectEqualSlices(u8, &chash, &by_email.cellId.?);
}

```
