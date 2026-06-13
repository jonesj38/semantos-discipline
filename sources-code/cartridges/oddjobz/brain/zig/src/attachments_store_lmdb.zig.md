---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/attachments_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.550948+00:00
---

# cartridges/oddjobz/brain/zig/src/attachments_store_lmdb.zig

```zig
// W0.2 — Attachments store backed by LmdbCellStore (replaces attachments_store_fs.zig).
//
// Each attachment entity is serialised as a JSON payload packed into a
// 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/appendV2 call encodes the cell bytes first,
// then calls cell_store.put().  If put() fails, the in-memory state is NOT
// updated.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_ATTACHMENT (0x05) and replays them to rebuild the in-memory
// index.
//
// The public API is identical to the old attachments_store_fs.AttachmentsStore
// so all existing callers (handlers, cli.zig, conformance tests) require only
// the change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

/// RM-114h — encode an attachment buffer as a 1024-byte cell. Prefers
/// substrate format; legacy entity_cell fallback for >768B payloads
/// (RM-118 will replace with continuation cells).
/// Attachments are always RELEVANT (immutable evidence — never consumed).
fn encodeAttachmentAsSubstrate(buf: []const u8) ![1024]u8 {
    if (buf.len <= substrate_entity.PAYLOAD_BUDGET) {
        return try substrate_entity.encodeEntity(.{
            .spec = substrate_entity.SPEC_ATTACHMENT,
            .linearity = .relevant,
            .owner_id = [_]u8{0} ** 16,
            .payload_json = buf,
        });
    }
    return try entity_cell.encodeCell(entity_cell.ENTITY_TAG_ATTACHMENT, buf);
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_id,
    invalid_visit_id,
    invalid_kind,
    invalid_content_hash,
    invalid_content_size,
    invalid_mime_type,
    invalid_captured_at,
    invalid_captured_by_cert_id,
    invalid_caption,
    invalid_created_at,
    invalid_source_blob_key,
    invalid_page_count,
    invalid_photo_count,
    has_photos_mismatch,
};

/// Canonical Attachment kinds — matches ATTACHMENT_KINDS in
/// cartridges/oddjobz/brain/src/cell-types/attachment.ts verbatim.
pub const ATTACHMENT_KINDS = [_][]const u8{
    "photo",
    "voice_memo",
    "gps_pin",
    "file_other",
};

pub fn isValidKind(s: []const u8) bool {
    for (ATTACHMENT_KINDS) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub fn isValidHex(s: []const u8, expected_len: usize) bool {
    if (s.len != expected_len) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        if (!ok) return false;
    }
    return true;
}

pub const Attachment = struct {
    // ── v1 fields ─────────────────────────────────────────────────────
    id: []const u8,
    visit_id: []const u8,
    kind: []const u8,
    content_hash: []const u8,
    content_size: i64,
    mime_type: []const u8,
    captured_at: []const u8,
    captured_by_cert_id: []const u8,
    caption: []const u8,
    created_at: []const u8,

    // ── v2 graph-aware fields (null on legacy v1 rows) ───────────────
    cellId: ?[32]u8 = null,
    typeHash: ?[32]u8 = null,
    jobRef: ?[32]u8 = null,
    sourceBlobKey: ?[]const u8 = null,
    pageCount: ?u32 = null,
    photoCount: ?u32 = null,
    hasPhotos: bool = false,
    signedBy: ?[33]u8 = null,
    signature: ?[64]u8 = null,
};

pub const MAX_ID_BYTES: usize = 64;
pub const MAX_VISIT_ID_BYTES: usize = 64;
pub const MAX_KIND_BYTES: usize = 32;
pub const CONTENT_HASH_LEN: usize = 64;
pub const MAX_MIME_TYPE_BYTES: usize = 128;
pub const MAX_CAPTURED_AT_BYTES: usize = 64;
pub const CERT_ID_LEN: usize = 32;
pub const MAX_CAPTION_BYTES: usize = 500;
pub const MAX_CREATED_AT_BYTES: usize = 64;
pub const MAX_SOURCE_BLOB_KEY_BYTES: usize = 256;

const OwnedStrings = struct {
    id: []u8,
    visit_id: []u8,
    kind: []u8,
    content_hash: []u8,
    mime_type: []u8,
    captured_at: []u8,
    captured_by_cert_id: []u8,
    caption: []u8,
    created_at: []u8,
    source_blob_key: ?[]u8 = null,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.visit_id);
        allocator.free(self.kind);
        allocator.free(self.content_hash);
        allocator.free(self.mime_type);
        allocator.free(self.captured_at);
        allocator.free(self.captured_by_cert_id);
        allocator.free(self.caption);
        allocator.free(self.created_at);
        if (self.source_blob_key) |sbk| allocator.free(sbk);
    }
};

pub const AttachmentsStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Attachment),
    by_id: std.StringHashMap(usize),
    by_cell_id: std.StringHashMap(usize),
    id_keys: std.ArrayList([]u8),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !AttachmentsStore {
        var self = AttachmentsStore{
            .allocator = allocator,
            .cell_store = cell_store,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .by_cell_id = std.StringHashMap(usize).init(allocator),
            .id_keys = .{},
            .owned_strings = .{},
            .clock = clock_fn,
        };
        try self.replayCellStore();
        return self;
    }

    pub fn deinit(self: *AttachmentsStore) void {
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
        self.by_cell_id.deinit();
        for (self.id_keys.items) |k| self.allocator.free(k);
        self.id_keys.deinit(self.allocator);
    }

    pub fn append(self: *AttachmentsStore, att: Attachment) !AppendOutcome {
        if (att.id.len == 0 or att.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (att.visit_id.len == 0 or att.visit_id.len > MAX_VISIT_ID_BYTES) return StoreError.invalid_visit_id;
        if (!isValidKind(att.kind)) return StoreError.invalid_kind;
        if (!isValidHex(att.content_hash, CONTENT_HASH_LEN)) return StoreError.invalid_content_hash;
        if (att.content_size < 0) return StoreError.invalid_content_size;
        if (att.mime_type.len == 0 or att.mime_type.len > MAX_MIME_TYPE_BYTES) return StoreError.invalid_mime_type;
        if (att.captured_at.len == 0 or att.captured_at.len > MAX_CAPTURED_AT_BYTES) return StoreError.invalid_captured_at;
        if (!isValidHex(att.captured_by_cert_id, CERT_ID_LEN)) return StoreError.invalid_captured_by_cert_id;
        if (att.caption.len > MAX_CAPTION_BYTES) return StoreError.invalid_caption;
        if (att.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;

        const existing_idx = self.by_id.get(att.id);

        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(att);

        if (existing_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneAttachmentIntoArena(att);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub const AttachmentV2Payload = struct {
        // v1 carry-over (relaxed: empty allowed on PDF-source rows).
        id: []const u8,
        visit_id: []const u8 = "",
        kind: []const u8 = "",
        content_hash: []const u8 = "",
        content_size: i64 = 0,
        mime_type: []const u8,
        captured_at: []const u8 = "",
        captured_by_cert_id: []const u8 = "",
        caption: []const u8 = "",
        created_at: []const u8,
        // v2 graph-aware additions.
        cellId: [32]u8,
        typeHash: [32]u8,
        jobRef: ?[32]u8,
        sourceBlobKey: ?[]const u8,
        pageCount: ?u32,
        photoCount: ?u32,
        hasPhotos: bool,
        signedBy: ?[33]u8 = null,
        signature: ?[64]u8 = null,
    };

    pub fn appendV2(self: *AttachmentsStore, payload: AttachmentV2Payload) !AppendOutcome {
        if (payload.id.len == 0 or payload.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (payload.mime_type.len == 0 or payload.mime_type.len > MAX_MIME_TYPE_BYTES) return StoreError.invalid_mime_type;
        if (payload.caption.len > MAX_CAPTION_BYTES) return StoreError.invalid_caption;
        if (payload.created_at.len > MAX_CREATED_AT_BYTES) return StoreError.invalid_created_at;

        if (payload.visit_id.len > 0) {
            if (payload.visit_id.len > MAX_VISIT_ID_BYTES) return StoreError.invalid_visit_id;
            if (!isValidKind(payload.kind)) return StoreError.invalid_kind;
            if (!isValidHex(payload.content_hash, CONTENT_HASH_LEN)) return StoreError.invalid_content_hash;
            if (payload.content_size < 0) return StoreError.invalid_content_size;
            if (payload.captured_at.len == 0 or payload.captured_at.len > MAX_CAPTURED_AT_BYTES) return StoreError.invalid_captured_at;
            if (!isValidHex(payload.captured_by_cert_id, CERT_ID_LEN)) return StoreError.invalid_captured_by_cert_id;
        } else {
            if (payload.kind.len > MAX_KIND_BYTES) return StoreError.invalid_kind;
            if (payload.content_hash.len > 0 and !isValidHex(payload.content_hash, CONTENT_HASH_LEN)) return StoreError.invalid_content_hash;
            if (payload.content_size < 0) return StoreError.invalid_content_size;
            if (payload.captured_at.len > MAX_CAPTURED_AT_BYTES) return StoreError.invalid_captured_at;
            if (payload.captured_by_cert_id.len > 0 and !isValidHex(payload.captured_by_cert_id, CERT_ID_LEN)) return StoreError.invalid_captured_by_cert_id;
        }

        if (payload.sourceBlobKey) |sbk| {
            if (sbk.len == 0 or sbk.len > MAX_SOURCE_BLOB_KEY_BYTES) return StoreError.invalid_source_blob_key;
        }
        const derived_has_photos = if (payload.photoCount) |pc| pc > 0 else false;
        if (payload.hasPhotos != derived_has_photos) return StoreError.has_photos_mismatch;

        const id_hex_arr = std.fmt.bytesToHex(payload.cellId, .lower);
        const id_hex: []const u8 = id_hex_arr[0..];
        const existing_cell_idx = self.by_cell_id.get(id_hex);
        const existing_uuid_idx = self.by_id.get(payload.id);

        // Build the Attachment stub for K4 LMDB write.
        const stub: Attachment = .{
            .id = payload.id,
            .visit_id = payload.visit_id,
            .kind = payload.kind,
            .content_hash = payload.content_hash,
            .content_size = payload.content_size,
            .mime_type = payload.mime_type,
            .captured_at = payload.captured_at,
            .captured_by_cert_id = payload.captured_by_cert_id,
            .caption = payload.caption,
            .created_at = payload.created_at,
            .cellId = payload.cellId,
            .typeHash = payload.typeHash,
            .jobRef = payload.jobRef,
            .sourceBlobKey = payload.sourceBlobKey,
            .pageCount = payload.pageCount,
            .photoCount = payload.photoCount,
            .hasPhotos = payload.hasPhotos,
            .signedBy = payload.signedBy,
            .signature = payload.signature,
        };
        // K4: write to LMDB first; in-memory update only on success.
        try self.putCell(stub);

        if (existing_cell_idx != null or existing_uuid_idx != null) {
            return .already_exists;
        }

        const stored = try self.cloneAttachmentIntoArena(stub);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        const id_key_owned = try self.dupIdKey(id_hex);
        try self.by_cell_id.put(id_key_owned, idx);
        return .created;
    }

    pub fn findAll(self: *const AttachmentsStore, allocator: std.mem.Allocator) ![]Attachment {
        const out = try allocator.alloc(Attachment, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn findById(self: *const AttachmentsStore, id: []const u8) ?Attachment {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByVisitId(self: *const AttachmentsStore, allocator: std.mem.Allocator, visit_id: []const u8) ![]Attachment {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.visit_id, visit_id)) n += 1;
        }
        const out = try allocator.alloc(Attachment, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.visit_id, visit_id)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const AttachmentsStore) usize {
        return self.records.items.len;
    }

    pub fn getByCellId(self: *const AttachmentsStore, cellId: [32]u8) ?Attachment {
        const id_hex_arr = std.fmt.bytesToHex(cellId, .lower);
        const idx = self.by_cell_id.get(id_hex_arr[0..]) orelse return null;
        return self.records.items[idx];
    }

    pub fn appendSigned(
        self: *AttachmentsStore,
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
                self.putCell(self.records.items[idx]) catch {};
                return;
            }
        }
    }

    pub fn findForJob(self: *const AttachmentsStore, allocator: std.mem.Allocator, jobCellId: [32]u8) ![]Attachment {
        var n: usize = 0;
        for (self.records.items) |r| {
            const r_job = r.jobRef orelse continue;
            if (std.mem.eql(u8, &r_job, &jobCellId)) n += 1;
        }
        const out = try allocator.alloc(Attachment, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            const r_job = r.jobRef orelse continue;
            if (std.mem.eql(u8, &r_job, &jobCellId)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    // ── LMDB cell write ────────────────────────────────────────────────

    fn putCell(self: *AttachmentsStore, att: Attachment) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeAttachment(self.allocator, &buf, att);
        const cell = encodeAttachmentAsSubstrate(buf.items) catch return;
        _ = self.cell_store.put(&cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────

    fn replayCellStore(self: *AttachmentsStore) !void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);

        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_ATTACHMENT) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_ATTACHMENT.domain_flag) continue;
                break :blk decoded.payload;
            };
            self.applyPayload(payload) catch {}; // skip malformed
        }
    }

    fn applyPayload(self: *AttachmentsStore, payload: []const u8) !void {
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

        const visit_id = if (obj.get("visit_id")) |v| (if (v == .string) v.string else "") else "";
        const kind_field = if (obj.get("kind_field")) |v| (if (v == .string) v.string else "") else "";
        const content_hash = if (obj.get("content_hash")) |v| (if (v == .string) v.string else "") else "";
        const content_size: i64 = blk_cs: {
            if (obj.get("content_size")) |v| {
                switch (v) {
                    .integer => |n| break :blk_cs n,
                    .float => |f| break :blk_cs @intFromFloat(f),
                    else => break :blk_cs 0,
                }
            }
            break :blk_cs 0;
        };
        const mime_type_v = obj.get("mime_type") orelse return;
        if (mime_type_v != .string) return;
        const mime_type = mime_type_v.string;
        const captured_at = if (obj.get("captured_at")) |v| (if (v == .string) v.string else "") else "";
        const captured_by_cert_id = if (obj.get("captured_by_cert_id")) |v| (if (v == .string) v.string else "") else "";
        const caption = if (obj.get("caption")) |v| (if (v == .string) v.string else "") else "";
        const created_at_v = obj.get("created_at") orelse return;
        if (created_at_v != .string) return;
        const created_at = created_at_v.string;

        // Common envelope checks.
        if (mime_type.len == 0 or mime_type.len > MAX_MIME_TYPE_BYTES) return;
        if (caption.len > MAX_CAPTION_BYTES) return;
        if (created_at.len > MAX_CREATED_AT_BYTES) return;
        if (content_size < 0) return;

        // ── Detect v2 fields ─────────────────────────────────────────
        var cell_id_opt: ?[32]u8 = null;
        var type_hash_opt: ?[32]u8 = null;
        var job_ref_opt: ?[32]u8 = null;
        var source_blob_key_opt: ?[]const u8 = null;
        var page_count_opt: ?u32 = null;
        var photo_count_opt: ?u32 = null;
        var has_photos_opt: ?bool = null;

        if (obj.get("cellId")) |cell_v| dec_v2: {
            if (cell_v != .string) break :dec_v2;
            if (cell_v.string.len != 64) break :dec_v2;
            var cell_id: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&cell_id, cell_v.string) catch break :dec_v2;

            const type_v = obj.get("typeHash") orelse break :dec_v2;
            if (type_v != .string or type_v.string.len != 64) break :dec_v2;
            var type_hash: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&type_hash, type_v.string) catch break :dec_v2;

            const job_ref: ?[32]u8 = blk_jref: {
                if (obj.get("jobRef")) |v| {
                    switch (v) {
                        .string => |s| {
                            if (s.len != 64) break :blk_jref null;
                            var b: [32]u8 = undefined;
                            _ = std.fmt.hexToBytes(&b, s) catch break :blk_jref null;
                            break :blk_jref b;
                        },
                        else => break :blk_jref null,
                    }
                }
                break :blk_jref null;
            };

            const source_blob_key: ?[]const u8 = blk_sbk: {
                if (obj.get("sourceBlobKey")) |v| {
                    switch (v) {
                        .string => |s| {
                            if (s.len == 0 or s.len > MAX_SOURCE_BLOB_KEY_BYTES) break :blk_sbk null;
                            break :blk_sbk s;
                        },
                        else => break :blk_sbk null,
                    }
                }
                break :blk_sbk null;
            };

            const page_count: ?u32 = blk_pgc: {
                if (obj.get("pageCount")) |v| {
                    switch (v) {
                        .integer => |n| {
                            if (n < 0) break :blk_pgc null;
                            break :blk_pgc @intCast(n);
                        },
                        else => break :blk_pgc null,
                    }
                }
                break :blk_pgc null;
            };

            const photo_count: ?u32 = blk_phc: {
                if (obj.get("photoCount")) |v| {
                    switch (v) {
                        .integer => |n| {
                            if (n < 0) break :blk_phc null;
                            break :blk_phc @intCast(n);
                        },
                        else => break :blk_phc null,
                    }
                }
                break :blk_phc null;
            };

            const has_photos: bool = blk_hp: {
                if (obj.get("hasPhotos")) |v| {
                    switch (v) {
                        .bool => |b| break :blk_hp b,
                        else => break :blk_hp false,
                    }
                }
                break :blk_hp false;
            };

            cell_id_opt = cell_id;
            type_hash_opt = type_hash;
            job_ref_opt = job_ref;
            source_blob_key_opt = source_blob_key;
            page_count_opt = page_count;
            photo_count_opt = photo_count;
            has_photos_opt = has_photos;
        }

        // Shape-specific validation.
        if (visit_id.len > 0) {
            if (visit_id.len > MAX_VISIT_ID_BYTES) return;
            if (!isValidKind(kind_field)) return;
            if (!isValidHex(content_hash, CONTENT_HASH_LEN)) return;
            if (captured_at.len == 0 or captured_at.len > MAX_CAPTURED_AT_BYTES) return;
            if (!isValidHex(captured_by_cert_id, CERT_ID_LEN)) return;
        } else {
            // PDF-source row: must have v2 + sourceBlobKey.
            if (cell_id_opt == null) return;
            if (source_blob_key_opt == null) return;
        }

        // Optional signedBy / signature.
        const signed_by_opt: ?[33]u8 = blk_sb: {
            if (obj.get("signedBy")) |v| {
                switch (v) {
                    .string => |s| {
                        if (s.len != 66) break :blk_sb null;
                        var sb: [33]u8 = undefined;
                        _ = std.fmt.hexToBytes(&sb, s) catch break :blk_sb null;
                        break :blk_sb sb;
                    },
                    else => break :blk_sb null,
                }
            }
            break :blk_sb null;
        };
        const signature_opt: ?[64]u8 = blk_sig: {
            if (obj.get("signature")) |v| {
                switch (v) {
                    .string => |s| {
                        if (s.len != 128) break :blk_sig null;
                        var sig: [64]u8 = undefined;
                        _ = std.fmt.hexToBytes(&sig, s) catch break :blk_sig null;
                        break :blk_sig sig;
                    },
                    else => break :blk_sig null,
                }
            }
            break :blk_sig null;
        };

        // Idempotent: latest cell wins.
        if (self.by_id.contains(id)) return;
        if (cell_id_opt) |cid| {
            const id_hex_arr = std.fmt.bytesToHex(cid, .lower);
            if (self.by_cell_id.contains(id_hex_arr[0..])) return;
        }

        const stored_has_photos: bool = blk_hp_st: {
            const supplied = has_photos_opt orelse break :blk_hp_st false;
            const derived = if (photo_count_opt) |pc| pc > 0 else false;
            break :blk_hp_st supplied and derived;
        };

        const att: Attachment = .{
            .id = id,
            .visit_id = visit_id,
            .kind = kind_field,
            .content_hash = content_hash,
            .content_size = content_size,
            .mime_type = mime_type,
            .captured_at = captured_at,
            .captured_by_cert_id = captured_by_cert_id,
            .caption = caption,
            .created_at = created_at,
            .cellId = cell_id_opt,
            .typeHash = type_hash_opt,
            .jobRef = job_ref_opt,
            .sourceBlobKey = source_blob_key_opt,
            .pageCount = page_count_opt,
            .photoCount = photo_count_opt,
            .hasPhotos = if (cell_id_opt != null) stored_has_photos else false,
            .signedBy = signed_by_opt,
            .signature = signature_opt,
        };

        const stored = try self.cloneAttachmentIntoArena(att);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        if (att.cellId) |cid| {
            const id_hex_arr = std.fmt.bytesToHex(cid, .lower);
            const id_key_owned = try self.dupIdKey(id_hex_arr[0..]);
            try self.by_cell_id.put(id_key_owned, idx);
        }
    }

    fn dupIdKey(self: *AttachmentsStore, id_hex: []const u8) ![]const u8 {
        const owned = try self.allocator.dupe(u8, id_hex);
        errdefer self.allocator.free(owned);
        try self.id_keys.append(self.allocator, owned);
        return owned;
    }

    fn cloneAttachmentIntoArena(self: *AttachmentsStore, att: Attachment) !Attachment {
        var owned: OwnedStrings = .{
            .id = undefined,
            .visit_id = undefined,
            .kind = undefined,
            .content_hash = undefined,
            .mime_type = undefined,
            .captured_at = undefined,
            .captured_by_cert_id = undefined,
            .caption = undefined,
            .created_at = undefined,
            .source_blob_key = null,
        };
        owned.id = try self.allocator.dupe(u8, att.id);
        errdefer self.allocator.free(owned.id);
        owned.visit_id = try self.allocator.dupe(u8, att.visit_id);
        errdefer self.allocator.free(owned.visit_id);
        owned.kind = try self.allocator.dupe(u8, att.kind);
        errdefer self.allocator.free(owned.kind);
        owned.content_hash = try self.allocator.dupe(u8, att.content_hash);
        errdefer self.allocator.free(owned.content_hash);
        owned.mime_type = try self.allocator.dupe(u8, att.mime_type);
        errdefer self.allocator.free(owned.mime_type);
        owned.captured_at = try self.allocator.dupe(u8, att.captured_at);
        errdefer self.allocator.free(owned.captured_at);
        owned.captured_by_cert_id = try self.allocator.dupe(u8, att.captured_by_cert_id);
        errdefer self.allocator.free(owned.captured_by_cert_id);
        owned.caption = try self.allocator.dupe(u8, att.caption);
        errdefer self.allocator.free(owned.caption);
        owned.created_at = try self.allocator.dupe(u8, att.created_at);
        errdefer self.allocator.free(owned.created_at);
        if (att.sourceBlobKey) |sbk| {
            owned.source_blob_key = try self.allocator.dupe(u8, sbk);
        }
        errdefer if (owned.source_blob_key) |s| self.allocator.free(s);

        try self.owned_strings.append(self.allocator, owned);

        return .{
            .id = owned.id,
            .visit_id = owned.visit_id,
            .kind = owned.kind,
            .content_hash = owned.content_hash,
            .content_size = att.content_size,
            .mime_type = owned.mime_type,
            .captured_at = owned.captured_at,
            .captured_by_cert_id = owned.captured_by_cert_id,
            .caption = owned.caption,
            .created_at = owned.created_at,
            .cellId = att.cellId,
            .typeHash = att.typeHash,
            .jobRef = att.jobRef,
            .sourceBlobKey = owned.source_blob_key,
            .pageCount = att.pageCount,
            .photoCount = att.photoCount,
            .hasPhotos = att.hasPhotos,
            .signedBy = att.signedBy,
            .signature = att.signature,
        };
    }
};

// ── Serialisation ──────────────────────────────────────────────────────────

fn serializeAttachment(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    att: Attachment,
) !void {
    try buf.appendSlice(allocator, "{\"kind\":\"created\",\"id\":");
    try writeJsonString(allocator, buf, att.id);
    try buf.appendSlice(allocator, ",\"visit_id\":");
    try writeJsonString(allocator, buf, att.visit_id);
    try buf.appendSlice(allocator, ",\"kind_field\":");
    try writeJsonString(allocator, buf, att.kind);
    try buf.appendSlice(allocator, ",\"content_hash\":");
    try writeJsonString(allocator, buf, att.content_hash);
    var num_buf: [32]u8 = undefined;
    const cs_s = std.fmt.bufPrint(&num_buf, "{d}", .{att.content_size}) catch unreachable;
    try buf.appendSlice(allocator, ",\"content_size\":");
    try buf.appendSlice(allocator, cs_s);
    try buf.appendSlice(allocator, ",\"mime_type\":");
    try writeJsonString(allocator, buf, att.mime_type);
    try buf.appendSlice(allocator, ",\"captured_at\":");
    try writeJsonString(allocator, buf, att.captured_at);
    try buf.appendSlice(allocator, ",\"captured_by_cert_id\":");
    try writeJsonString(allocator, buf, att.captured_by_cert_id);
    try buf.appendSlice(allocator, ",\"caption\":");
    try writeJsonString(allocator, buf, att.caption);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, att.created_at);

    // v2 fields
    if (att.cellId) |cid| {
        const hex = std.fmt.bytesToHex(cid, .lower);
        try buf.appendSlice(allocator, ",\"cellId\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (att.typeHash) |th| {
        const hex = std.fmt.bytesToHex(th, .lower);
        try buf.appendSlice(allocator, ",\"typeHash\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (att.jobRef) |jr| {
        const hex = std.fmt.bytesToHex(jr, .lower);
        try buf.appendSlice(allocator, ",\"jobRef\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (att.sourceBlobKey) |sbk| {
        try buf.appendSlice(allocator, ",\"sourceBlobKey\":");
        try writeJsonString(allocator, buf, sbk);
    }
    if (att.pageCount) |pc| {
        const pc_s = std.fmt.bufPrint(&num_buf, "{d}", .{pc}) catch unreachable;
        try buf.appendSlice(allocator, ",\"pageCount\":");
        try buf.appendSlice(allocator, pc_s);
    }
    if (att.photoCount) |phc| {
        const phc_s = std.fmt.bufPrint(&num_buf, "{d}", .{phc}) catch unreachable;
        try buf.appendSlice(allocator, ",\"photoCount\":");
        try buf.appendSlice(allocator, phc_s);
    }
    try buf.appendSlice(allocator, ",\"hasPhotos\":");
    try buf.appendSlice(allocator, if (att.hasPhotos) "true" else "false");

    if (att.signedBy) |sb| {
        const hex = std.fmt.bytesToHex(sb, .lower);
        try buf.appendSlice(allocator, ",\"signedBy\":\"");
        try buf.appendSlice(allocator, hex[0..]);
        try buf.append(allocator, '"');
    }
    if (att.signature) |sig| {
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

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic (no LMDB required).
// ─────────────────────────────────────────────────────────────────────

test "isValidKind recognises the four canonical attachment kinds" {
    try std.testing.expect(isValidKind("photo"));
    try std.testing.expect(isValidKind("voice_memo"));
    try std.testing.expect(isValidKind("gps_pin"));
    try std.testing.expect(isValidKind("file_other"));
    try std.testing.expect(!isValidKind(""));
    try std.testing.expect(!isValidKind("video"));
}

test "isValidHex validates hex strings correctly" {
    try std.testing.expect(isValidHex("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", 64));
    try std.testing.expect(!isValidHex("ABCDEF", 6)); // uppercase not valid
    try std.testing.expect(!isValidHex("abc", 64)); // wrong length
    try std.testing.expect(isValidHex("abcdef0123456789abcdef0123456789", 32));
}

```
