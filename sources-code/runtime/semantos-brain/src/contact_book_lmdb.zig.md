---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/contact_book_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.214503+00:00
---

# runtime/semantos-brain/src/contact_book_lmdb.zig

```zig
// D-brain-contacts-api — LMDB-backed contact book.
//
// Stores two entity types in the shared entity cell store:
//   ENTITY_TAG_CONTACT (0x0A): one cell per contact.
//   ENTITY_TAG_EDGE    (0x0B): one cell per edge (including revocation updates).
//
// In-memory index: HashMap<certId → record_index> rebuilt on init by
// scanning the cell store.  Upsert semantics: a later cell with the same
// certId (higher updatedAt) wins; a revocation cell for the same edgeId
// updates revokedAt in place.
//
// K4 atomicity: cell written to LMDB before in-memory index is updated.
// Per Plexus §1.1.8: edges are never hard-deleted — revokedAt is set.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
// Task #22 — canonical 256-byte cell format dual path.  When payload
// fits the substrate 768-byte budget, encode through substrate_entity
// (kernel-readable); else fall back to entity_cell (legacy, supports
// up to 1008 bytes).  See docs/prd/ENTITY-CELL-DECOMMISSION.md §3.
const substrate_entity = @import("substrate_entity");

// ── Field size limits ────────────────────────────────────────────────

pub const MAX_CERT_ID_BYTES: usize = 64; // 32-byte SHA-256 hex
pub const MAX_PUBLIC_KEY_BYTES: usize = 66; // 33-byte compressed secp256k1 hex
pub const MAX_DISPLAY_NAME_BYTES: usize = 256;
pub const MAX_EMAIL_BYTES: usize = 256;
pub const MAX_SOURCE_BYTES: usize = 16; // "manual" | "discovered" | "imported"
pub const MAX_EDGE_ID_BYTES: usize = 128; // generous; Plexus edgeId is opaque
pub const MAX_EDGE_TYPE_BYTES: usize = 32; // "MESSAGING" | "DATA_ACCESS" | ...
pub const MAX_RECOVERY_POLICY_BYTES: usize = 32; // "NONE" | "BACKUP_ON_CREATE" | ...

// ── Errors ────────────────────────────────────────────────────────────

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_cert_id,
    invalid_public_key,
    invalid_display_name,
    invalid_edge_id,
    contact_not_found,
    edge_not_found,
    edge_already_revoked,
};

// ── Public record types ───────────────────────────────────────────────

pub const Contact = struct {
    certId: []const u8,
    publicKey: []const u8,
    displayName: []const u8,
    email: ?[]const u8,
    source: []const u8,
    addedAt: i64,
    updatedAt: i64,
};

pub const EdgeRecord = struct {
    edgeId: []const u8,
    certId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
    revokedAt: ?i64,
    createdAt: i64,
};

pub const AddEdgeOptions = struct {
    edgeId: []const u8,
    certId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
};

// ── Internal owned-string storage ─────────────────────────────────────

const OwnedContact = struct {
    certId: []u8,
    publicKey: []u8,
    displayName: []u8,
    email: ?[]u8,
    source: []u8,

    fn free(self: *OwnedContact, a: std.mem.Allocator) void {
        a.free(self.certId);
        a.free(self.publicKey);
        a.free(self.displayName);
        if (self.email) |e| a.free(e);
        a.free(self.source);
    }
};

const OwnedEdge = struct {
    edgeId: []u8,
    certId: []u8,
    edgeType: []u8,
    recoveryPolicy: []u8,

    fn free(self: *OwnedEdge, a: std.mem.Allocator) void {
        a.free(self.edgeId);
        a.free(self.certId);
        a.free(self.edgeType);
        a.free(self.recoveryPolicy);
    }
};

// ── ContactBookStore ──────────────────────────────────────────────────

pub const ContactBookStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    contacts: std.ArrayListUnmanaged(Contact),
    contact_owned: std.ArrayListUnmanaged(OwnedContact),
    by_cert_id: std.StringHashMap(usize),
    cert_id_keys: std.ArrayListUnmanaged([]u8),
    edges: std.ArrayListUnmanaged(EdgeRecord),
    edge_owned: std.ArrayListUnmanaged(OwnedEdge),
    by_edge_id: std.StringHashMap(usize),
    edge_id_keys: std.ArrayListUnmanaged([]u8),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !ContactBookStore {
        var self = ContactBookStore{
            .allocator = allocator,
            .cell_store = cell_store,
            .contacts = .{},
            .contact_owned = .{},
            .by_cert_id = std.StringHashMap(usize).init(allocator),
            .cert_id_keys = .{},
            .edges = .{},
            .edge_owned = .{},
            .by_edge_id = std.StringHashMap(usize).init(allocator),
            .edge_id_keys = .{},
            .clock = clock_fn,
        };
        try self.replayCellStore();
        return self;
    }

    pub fn deinit(self: *ContactBookStore) void {
        for (self.contact_owned.items) |*c| c.free(self.allocator);
        self.contact_owned.deinit(self.allocator);
        self.contacts.deinit(self.allocator);
        self.by_cert_id.deinit();
        for (self.cert_id_keys.items) |k| self.allocator.free(k);
        self.cert_id_keys.deinit(self.allocator);
        for (self.edge_owned.items) |*e| e.free(self.allocator);
        self.edge_owned.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.by_edge_id.deinit();
        for (self.edge_id_keys.items) |k| self.allocator.free(k);
        self.edge_id_keys.deinit(self.allocator);
    }

    // ── Contact CRUD ──────────────────────────────────────────────────

    pub fn addContact(
        self: *ContactBookStore,
        certId: []const u8,
        publicKey: []const u8,
        displayName: []const u8,
        email: ?[]const u8,
    ) StoreError!Contact {
        if (certId.len == 0 or certId.len > MAX_CERT_ID_BYTES) return StoreError.invalid_cert_id;
        if (publicKey.len == 0 or publicKey.len > MAX_PUBLIC_KEY_BYTES) return StoreError.invalid_public_key;
        if (displayName.len == 0 or displayName.len > MAX_DISPLAY_NAME_BYTES) return StoreError.invalid_display_name;

        const now_ms = self.clock();
        const added_at: i64 = if (self.by_cert_id.get(certId)) |idx|
            self.contacts.items[idx].addedAt
        else
            now_ms;

        const payload = buildContactJson(self.allocator, certId, publicKey, displayName, email, added_at, now_ms) catch
            return StoreError.out_of_memory;
        defer self.allocator.free(payload);

        // Task #22 — try canonical 256-byte (substrate_entity) first;
        // fall back to entity_cell for oversize payloads.  Contacts are
        // small JSON (cert id + name + email + timestamps), well under
        // the 768-byte budget, so the canonical path is the common one.
        const cell = encodeContactCanonicalOrFallback(payload) catch
            return StoreError.persistence_failed;
        _ = self.cell_store.put(&cell) catch return StoreError.persistence_failed;

        return self.upsertContactInMemory(certId, publicKey, displayName, email, "manual", added_at, now_ms) catch
            StoreError.out_of_memory;
    }

    pub fn getContact(self: *const ContactBookStore, certId: []const u8) ?Contact {
        const idx = self.by_cert_id.get(certId) orelse return null;
        return self.contacts.items[idx];
    }

    pub fn listContacts(
        self: *const ContactBookStore,
        allocator: std.mem.Allocator,
    ) StoreError![]Contact {
        return allocator.dupe(Contact, self.contacts.items) catch StoreError.out_of_memory;
    }

    // ── Edge CRUD ─────────────────────────────────────────────────────

    pub fn addEdge(self: *ContactBookStore, opts: AddEdgeOptions) StoreError!EdgeRecord {
        if (opts.edgeId.len == 0 or opts.edgeId.len > MAX_EDGE_ID_BYTES) return StoreError.invalid_edge_id;
        if (self.by_cert_id.get(opts.certId) == null) return StoreError.contact_not_found;

        const now_ms = self.clock();
        const payload = buildEdgeJson(
            self.allocator,
            opts.edgeId, opts.certId, opts.edgeType,
            opts.signingKeyIndex, opts.recoveryPolicy,
            null, now_ms,
        ) catch return StoreError.out_of_memory;
        defer self.allocator.free(payload);

        // Task #22 — edge active state → linearity LINEAR via
        // encodeEdgeCanonicalOrFallback (revoked passes "revoked"
        // for RELEVANT).  This call site is a fresh edge with
        // revokedAt=null, so state is "active" by default.
        const cell = encodeEdgeCanonicalOrFallback(payload, "active") catch
            return StoreError.persistence_failed;
        _ = self.cell_store.put(&cell) catch return StoreError.persistence_failed;

        return self.upsertEdgeInMemory(.{
            .edgeId = opts.edgeId, .certId = opts.certId, .edgeType = opts.edgeType,
            .signingKeyIndex = opts.signingKeyIndex, .recoveryPolicy = opts.recoveryPolicy,
            .revokedAt = null, .createdAt = now_ms,
        }) catch StoreError.out_of_memory;
    }

    pub fn revokeEdge(
        self: *ContactBookStore,
        certId: []const u8,
        edgeId: []const u8,
    ) StoreError!void {
        if (self.by_cert_id.get(certId) == null) return StoreError.contact_not_found;
        const idx = self.by_edge_id.get(edgeId) orelse return StoreError.edge_not_found;
        if (self.edges.items[idx].revokedAt != null) return StoreError.edge_already_revoked;

        const now_ms = self.clock();
        const er = self.edges.items[idx];
        const payload = buildEdgeJson(
            self.allocator,
            er.edgeId, er.certId, er.edgeType,
            er.signingKeyIndex, er.recoveryPolicy,
            now_ms, er.createdAt,
        ) catch return StoreError.out_of_memory;
        defer self.allocator.free(payload);

        // Task #22 — revoke writes a new edge cell with linearity
        // RELEVANT (immutable historical record) per the K1 semantics
        // every edge-revoke implies.
        const cell = encodeEdgeCanonicalOrFallback(payload, "revoked") catch
            return StoreError.persistence_failed;
        _ = self.cell_store.put(&cell) catch return StoreError.persistence_failed;

        self.edges.items[idx].revokedAt = now_ms;
    }

    pub fn listEdges(
        self: *const ContactBookStore,
        certId: []const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]EdgeRecord {
        var result: std.ArrayListUnmanaged(EdgeRecord) = .{};
        for (self.edges.items) |e| {
            if (std.mem.eql(u8, e.certId, certId)) {
                result.append(allocator, e) catch return StoreError.out_of_memory;
            }
        }
        return result.toOwnedSlice(allocator) catch StoreError.out_of_memory;
    }

    // ── Cell store replay ─────────────────────────────────────────────

    fn replayCellStore(self: *ContactBookStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);
        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const tag = entity_cell.cellEntityTag(cell_ptr);
            const payload = entity_cell.cellPayload(cell_ptr);
            if (tag == entity_cell.ENTITY_TAG_CONTACT) {
                self.replayContactPayload(payload) catch {};
            } else if (tag == entity_cell.ENTITY_TAG_EDGE) {
                self.replayEdgePayload(payload) catch {};
            }
        }
    }

    fn replayContactPayload(self: *ContactBookStore, raw: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, raw, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;
        const certId = switch (obj.get("certId") orelse return) {
            .string => |s| s,
            else => return,
        };
        const publicKey = switch (obj.get("publicKey") orelse return) {
            .string => |s| s,
            else => return,
        };
        const displayName = switch (obj.get("displayName") orelse return) {
            .string => |s| s,
            else => return,
        };
        const source = switch (obj.get("source") orelse return) {
            .string => |s| s,
            else => return,
        };
        const addedAt = switch (obj.get("addedAt") orelse return) {
            .integer => |n| n,
            else => return,
        };
        const updatedAt = switch (obj.get("updatedAt") orelse return) {
            .integer => |n| n,
            else => return,
        };
        const email: ?[]const u8 = switch (obj.get("email") orelse .null) {
            .string => |s| s,
            else => null,
        };
        _ = try self.upsertContactInMemory(certId, publicKey, displayName, email, source, addedAt, updatedAt);
    }

    fn replayEdgePayload(self: *ContactBookStore, raw: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, raw, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;
        const edgeId = switch (obj.get("edgeId") orelse return) {
            .string => |s| s,
            else => return,
        };
        const certId = switch (obj.get("certId") orelse return) {
            .string => |s| s,
            else => return,
        };
        const edgeType = switch (obj.get("edgeType") orelse return) {
            .string => |s| s,
            else => return,
        };
        const signingKeyIndex = switch (obj.get("signingKeyIndex") orelse return) {
            .integer => |n| n,
            else => return,
        };
        const recoveryPolicy = switch (obj.get("recoveryPolicy") orelse return) {
            .string => |s| s,
            else => return,
        };
        const createdAt = switch (obj.get("createdAt") orelse return) {
            .integer => |n| n,
            else => return,
        };
        const revokedAt: ?i64 = switch (obj.get("revokedAt") orelse .null) {
            .integer => |n| n,
            else => null,
        };
        _ = try self.upsertEdgeInMemory(.{
            .edgeId = edgeId, .certId = certId, .edgeType = edgeType,
            .signingKeyIndex = signingKeyIndex, .recoveryPolicy = recoveryPolicy,
            .revokedAt = revokedAt, .createdAt = createdAt,
        });
    }

    // ── In-memory upsert helpers ──────────────────────────────────────

    fn upsertContactInMemory(
        self: *ContactBookStore,
        certId: []const u8,
        publicKey: []const u8,
        displayName: []const u8,
        email: ?[]const u8,
        source: []const u8,
        addedAt: i64,
        updatedAt: i64,
    ) !Contact {
        const owned_cert = try self.allocator.dupe(u8, certId);
        errdefer self.allocator.free(owned_cert);
        const owned_pk = try self.allocator.dupe(u8, publicKey);
        errdefer self.allocator.free(owned_pk);
        const owned_dn = try self.allocator.dupe(u8, displayName);
        errdefer self.allocator.free(owned_dn);
        const owned_email: ?[]u8 = if (email) |e| try self.allocator.dupe(u8, e) else null;
        errdefer if (owned_email) |e| self.allocator.free(e);
        const owned_src = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(owned_src);

        if (self.by_cert_id.get(certId)) |idx| {
            // Only update if this cell is newer.
            if (updatedAt >= self.contacts.items[idx].updatedAt) {
                var oc = &self.contact_owned.items[idx];
                oc.free(self.allocator);
                oc.* = .{
                    .certId = owned_cert, .publicKey = owned_pk, .displayName = owned_dn,
                    .email = owned_email, .source = owned_src,
                };
                self.contacts.items[idx] = .{
                    .certId = owned_cert, .publicKey = owned_pk, .displayName = owned_dn,
                    .email = owned_email, .source = owned_src, .addedAt = addedAt, .updatedAt = updatedAt,
                };
            } else {
                self.allocator.free(owned_cert);
                self.allocator.free(owned_pk);
                self.allocator.free(owned_dn);
                if (owned_email) |e| self.allocator.free(e);
                self.allocator.free(owned_src);
            }
            return self.contacts.items[idx];
        }

        // New record.
        const key = try self.allocator.dupe(u8, owned_cert);
        errdefer self.allocator.free(key);
        const contact = Contact{
            .certId = owned_cert, .publicKey = owned_pk, .displayName = owned_dn,
            .email = owned_email, .source = owned_src, .addedAt = addedAt, .updatedAt = updatedAt,
        };
        const idx = self.contacts.items.len;
        try self.contacts.append(self.allocator, contact);
        try self.contact_owned.append(self.allocator, .{
            .certId = owned_cert, .publicKey = owned_pk, .displayName = owned_dn,
            .email = owned_email, .source = owned_src,
        });
        try self.by_cert_id.put(key, idx);
        try self.cert_id_keys.append(self.allocator, key);
        return self.contacts.items[idx];
    }

    fn upsertEdgeInMemory(self: *ContactBookStore, edge: EdgeRecord) !EdgeRecord {
        const owned_eid = try self.allocator.dupe(u8, edge.edgeId);
        errdefer self.allocator.free(owned_eid);
        const owned_cid = try self.allocator.dupe(u8, edge.certId);
        errdefer self.allocator.free(owned_cid);
        const owned_et = try self.allocator.dupe(u8, edge.edgeType);
        errdefer self.allocator.free(owned_et);
        const owned_rp = try self.allocator.dupe(u8, edge.recoveryPolicy);
        errdefer self.allocator.free(owned_rp);

        if (self.by_edge_id.get(edge.edgeId)) |idx| {
            var eo = &self.edge_owned.items[idx];
            eo.free(self.allocator);
            eo.* = .{
                .edgeId = owned_eid, .certId = owned_cid,
                .edgeType = owned_et, .recoveryPolicy = owned_rp,
            };
            self.edges.items[idx] = .{
                .edgeId = owned_eid, .certId = owned_cid, .edgeType = owned_et,
                .signingKeyIndex = edge.signingKeyIndex, .recoveryPolicy = owned_rp,
                .revokedAt = edge.revokedAt, .createdAt = edge.createdAt,
            };
            return self.edges.items[idx];
        }

        const key = try self.allocator.dupe(u8, owned_eid);
        errdefer self.allocator.free(key);
        const stored = EdgeRecord{
            .edgeId = owned_eid, .certId = owned_cid, .edgeType = owned_et,
            .signingKeyIndex = edge.signingKeyIndex, .recoveryPolicy = owned_rp,
            .revokedAt = edge.revokedAt, .createdAt = edge.createdAt,
        };
        const idx = self.edges.items.len;
        try self.edges.append(self.allocator, stored);
        try self.edge_owned.append(self.allocator, .{
            .edgeId = owned_eid, .certId = owned_cid, .edgeType = owned_et, .recoveryPolicy = owned_rp,
        });
        try self.by_edge_id.put(key, idx);
        try self.edge_id_keys.append(self.allocator, key);
        return self.edges.items[idx];
    }
};

// ── Task #22 — substrate_entity dual-path helpers ────────────────────

/// Encode a contact payload through substrate_entity (canonical 256-byte
/// header — kernel-readable) when it fits the 768-byte payload budget;
/// otherwise fall back to entity_cell (legacy 16-byte header, supports
/// up to 1008 bytes).  Contacts are small JSON in practice; the
/// canonical path is the common one.
///
/// owner_id zero-filled today — D-brain-contacts-api doesn't bind a
/// caller cert to the write (the operator's own contact book).  When
/// BRAIN-DISPATCHER-UNIFICATION Phase 1 wires cert auth, owner_id
/// becomes derivable.  Same pattern the oddjobz per-store stores use.
fn encodeContactCanonicalOrFallback(payload: []const u8) entity_cell.EncodeError![entity_cell.CELL_BYTES]u8 {
    if (payload.len <= substrate_entity.PAYLOAD_BUDGET) {
        // Contact lifecycle state for linearity (active|archived).
        // contact JSON doesn't carry a top-level "state" today;
        // extractStateOrStatus returns empty string → linearityFor
        // defaults to .affine (active).  Future: addContact could
        // accept a state arg if archive becomes a separate op.
        const state = substrate_entity.extractStateOrStatus(payload);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_CONTACT, state);
        return substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_CONTACT,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = payload,
        }) catch |err| switch (err) {
            error.payload_too_large => return entity_cell.encodeCell(
                entity_cell.ENTITY_TAG_CONTACT,
                payload,
            ),
        };
    }
    return entity_cell.encodeCell(entity_cell.ENTITY_TAG_CONTACT, payload);
}

/// Encode an edge payload through substrate_entity (canonical) when it
/// fits the budget; else entity_cell fallback.  Linearity is caller-
/// driven via `state_hint` ("active" → LINEAR, "revoked" → RELEVANT)
/// because edge JSON doesn't carry a top-level "state" field that
/// extractStateOrStatus could pick up — the revoke transition is
/// signalled at the call site (addEdge vs revokeEdge).
fn encodeEdgeCanonicalOrFallback(payload: []const u8, state_hint: []const u8) entity_cell.EncodeError![entity_cell.CELL_BYTES]u8 {
    if (payload.len <= substrate_entity.PAYLOAD_BUDGET) {
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_EDGE, state_hint);
        return substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_EDGE,
            .linearity = linearity,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = payload,
        }) catch |err| switch (err) {
            error.payload_too_large => return entity_cell.encodeCell(
                entity_cell.ENTITY_TAG_EDGE,
                payload,
            ),
        };
    }
    return entity_cell.encodeCell(entity_cell.ENTITY_TAG_EDGE, payload);
}

// ── JSON builders ─────────────────────────────────────────────────────

fn buildContactJson(
    allocator: std.mem.Allocator,
    certId: []const u8,
    publicKey: []const u8,
    displayName: []const u8,
    email: ?[]const u8,
    addedAt: i64,
    updatedAt: i64,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);
    try w.print("{{\"certId\":\"", .{});
    try writeJsonEscape(&buf, allocator, certId);
    try w.print("\",\"publicKey\":\"", .{});
    try writeJsonEscape(&buf, allocator, publicKey);
    try w.print("\",\"displayName\":\"", .{});
    try writeJsonEscape(&buf, allocator, displayName);
    try w.print("\",\"email\":", .{});
    if (email) |e| {
        try w.print("\"", .{});
        try writeJsonEscape(&buf, allocator, e);
        try w.print("\"", .{});
    } else {
        try w.print("null", .{});
    }
    try w.print(",\"source\":\"manual\",\"addedAt\":{d},\"updatedAt\":{d}}}", .{ addedAt, updatedAt });
    return buf.toOwnedSlice(allocator);
}

fn buildEdgeJson(
    allocator: std.mem.Allocator,
    edgeId: []const u8,
    certId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
    revokedAt: ?i64,
    createdAt: i64,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);
    try w.print("{{\"edgeId\":\"", .{});
    try writeJsonEscape(&buf, allocator, edgeId);
    try w.print("\",\"certId\":\"", .{});
    try writeJsonEscape(&buf, allocator, certId);
    try w.print("\",\"edgeType\":\"", .{});
    try writeJsonEscape(&buf, allocator, edgeType);
    try w.print("\",\"signingKeyIndex\":{d},\"recoveryPolicy\":\"", .{signingKeyIndex});
    try writeJsonEscape(&buf, allocator, recoveryPolicy);
    try w.print("\"", .{});
    if (revokedAt) |r| {
        try w.print(",\"revokedAt\":{d}", .{r});
    }
    try w.print(",\"createdAt\":{d}}}", .{createdAt});
    return buf.toOwnedSlice(allocator);
}

fn writeJsonEscape(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, ch),
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────
//
// These tests use a NoopCellStore (stub) so they run without LMDB.

const testing = std.testing;

const NoopCellStore = struct {
    const vtable = cell_store_mod.CellStore.VTable{
        .put = noopPut,
        .exists = noopExists,
        .cursor_open = noopCursorOpen,
        .cursor_pull = noopCursorPull,
        .cursor_close = noopCursorClose,
        .count = noopCount,
        .spend = noopSpend,
        .is_spent = noopIsSpent,
        .get_cell = noopGetCell,
        .cells_by_owner = noopCellsByOwner,
        .cells_by_type = noopCellsByType,
        .cells_by_type_prefix = noopCellsByTypePrefix,
        .cells_by_prev_state = noopCellsByPrevState,
        .cells_by_anchor_txid = noopCellsByAnchorTxid,
        .set_anchor_status = noopSetAnchorStatus,
        .get_anchor_status = noopGetAnchorStatus,
        .clear_anchor_status = noopClearAnchorStatus,
        .sweep_pending_anchors = noopSweepPendingAnchors,
        .cells_by_anchor_height_range = noopCellsByAnchorHeightRange,
        .sweep_reorged_from_height = noopSweepReorgedFromHeight,
        .cells_by_prev_state_range = noopCellsByPrevStateRange,
    };

    fn store(self: *NoopCellStore) cell_store_mod.CellStore {
        return cell_store_mod.CellStore{
            .ctx = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    fn noopPut(_: *anyopaque, _: *const [cell_store_mod.CELL_BYTES]u8) cell_store_mod.StoreError![32]u8 {
        return [_]u8{0} ** 32;
    }
    fn noopExists(_: *anyopaque, _: *const [32]u8) bool {
        return false;
    }
    fn noopCursorOpen(_: *anyopaque) cell_store_mod.StoreError!cell_store_mod.CellCursorHandle {
        return @ptrFromInt(1);
    }
    fn noopCursorPull(_: *anyopaque, _: cell_store_mod.CellCursorHandle) cell_store_mod.StoreError!?*const [cell_store_mod.CELL_BYTES]u8 {
        return null;
    }
    fn noopCursorClose(_: *anyopaque, _: cell_store_mod.CellCursorHandle) void {}
    fn noopCount(_: *anyopaque) cell_store_mod.StoreError!u64 {
        return 0;
    }
    fn noopSpend(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!bool {
        return false;
    }
    fn noopIsSpent(_: *anyopaque, _: *const [32]u8) bool {
        return false;
    }
    fn noopGetCell(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!?[cell_store_mod.CELL_BYTES]u8 {
        return null;
    }
    fn noopCellsByOwner(_: *anyopaque, _: std.mem.Allocator, _: *const [cell_store_mod.OWNER_ID_BYTES]u8) cell_store_mod.StoreError![][32]u8 {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopCellsByType(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopCellsByTypePrefix(_: *anyopaque, _: std.mem.Allocator, _: []const u8) cell_store_mod.StoreError![][32]u8 {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopCellsByPrevState(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopCellsByAnchorTxid(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopSetAnchorStatus(_: *anyopaque, _: *const [32]u8, _: cell_store_mod.AnchorStatus) cell_store_mod.StoreError!void {}
    fn noopGetAnchorStatus(_: *anyopaque, _: *const [32]u8) ?cell_store_mod.AnchorStatus {
        return null;
    }
    fn noopClearAnchorStatus(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!void {}
    fn noopSweepPendingAnchors(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!cell_store_mod.SweepResult {
        return cell_store_mod.SweepResult{ .swept = 0, .kept = 0 };
    }
    fn noopCellsByAnchorHeightRange(_: *anyopaque, _: std.mem.Allocator, _: u64, _: u64) cell_store_mod.StoreError![]cell_store_mod.AnchorHeightEntry {
        return cell_store_mod.StoreError.persistence_failed;
    }
    fn noopSweepReorgedFromHeight(_: *anyopaque, _: u64) cell_store_mod.StoreError!cell_store_mod.SweepResult {
        return cell_store_mod.SweepResult{ .swept = 0, .kept = 0 };
    }
    fn noopCellsByPrevStateRange(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8, _: ?*const [32]u8, _: usize) cell_store_mod.StoreError!cell_store_mod.PrevStateRangeResult {
        return cell_store_mod.StoreError.persistence_failed;
    }
};

fn noopClock() i64 { return 1_716_499_200_000; }

test "addContact — happy path stores and retrieves contact" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    const c = try store.addContact("aabbcc", "deadbeef", "Alice", "alice@example.com");
    try testing.expectEqualStrings("aabbcc", c.certId);
    try testing.expectEqualStrings("Alice", c.displayName);
    try testing.expectEqualStrings("alice@example.com", c.email.?);
    try testing.expectEqual(@as(i64, 1_716_499_200_000), c.addedAt);

    const got = store.getContact("aabbcc");
    try testing.expect(got != null);
    try testing.expectEqualStrings("Alice", got.?.displayName);
}

test "addContact — no email" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    const c = try store.addContact("aa", "bb", "Bob", null);
    try testing.expect(c.email == null);
}

test "addContact — upsert updates displayName" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    _ = try store.addContact("certx", "pk1", "Alice Old", null);
    _ = try store.addContact("certx", "pk1", "Alice New", null);
    const got = store.getContact("certx");
    try testing.expectEqualStrings("Alice New", got.?.displayName);
    const list = try store.listContacts(testing.allocator);
    defer testing.allocator.free(list);
    try testing.expectEqual(@as(usize, 1), list.len);
}

test "getContact — returns null for unknown certId" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    try testing.expect(store.getContact("unknown") == null);
}

test "addEdge — happy path" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    _ = try store.addContact("certA", "pubkA", "Alice", null);
    const e = try store.addEdge(.{
        .edgeId = "edge1",
        .certId = "certA",
        .edgeType = "MESSAGING",
        .signingKeyIndex = 42,
        .recoveryPolicy = "NONE",
    });
    try testing.expectEqualStrings("edge1", e.edgeId);
    try testing.expectEqualStrings("MESSAGING", e.edgeType);
    try testing.expect(e.revokedAt == null);
}

test "addEdge — contact_not_found for unknown certId" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    const err = store.addEdge(.{
        .edgeId = "e1", .certId = "nobody", .edgeType = "MESSAGING",
        .signingKeyIndex = 1, .recoveryPolicy = "NONE",
    });
    try testing.expectError(StoreError.contact_not_found, err);
}

test "revokeEdge — sets revokedAt" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    _ = try store.addContact("certA", "pk", "Alice", null);
    _ = try store.addEdge(.{
        .edgeId = "e1", .certId = "certA", .edgeType = "MESSAGING",
        .signingKeyIndex = 7, .recoveryPolicy = "NONE",
    });
    try store.revokeEdge("certA", "e1");

    const edges = try store.listEdges("certA", testing.allocator);
    defer testing.allocator.free(edges);
    try testing.expectEqual(@as(usize, 1), edges.len);
    try testing.expect(edges[0].revokedAt != null);
}

test "revokeEdge — edge_already_revoked on double revoke" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    _ = try store.addContact("c1", "pk", "Alice", null);
    _ = try store.addEdge(.{
        .edgeId = "e1", .certId = "c1", .edgeType = "MESSAGING",
        .signingKeyIndex = 1, .recoveryPolicy = "NONE",
    });
    try store.revokeEdge("c1", "e1");
    try testing.expectError(StoreError.edge_already_revoked, store.revokeEdge("c1", "e1"));
}

test "revokeEdge — edge_not_found for unknown edgeId" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    _ = try store.addContact("c1", "pk", "Alice", null);
    try testing.expectError(StoreError.edge_not_found, store.revokeEdge("c1", "nope"));
}

test "invalid_cert_id — empty certId" {
    var noop = NoopCellStore{};
    const cs = noop.store();
    var store = try ContactBookStore.init(testing.allocator, &cs, noopClock);
    defer store.deinit();

    try testing.expectError(StoreError.invalid_cert_id, store.addContact("", "pk", "Alice", null));
}

```
