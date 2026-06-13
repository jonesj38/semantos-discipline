---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/intent_cell_lmdb_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.231944+00:00
---

# runtime/semantos-brain/src/intent_cell_lmdb_store.zig

```zig
// W0.3 — Intent cell LMDB store: phase-0x06 cells in LmdbCellStore.
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md;
//            runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig (the backing store);
//            runtime/semantos-brain/src/action_cell_teachback.zig (phase-0x06 layout);
//            core/cell-engine/src/constants.zig (HEADER_OFFSET_COMMERCE_PHASE=94,
//            HEADER_SIZE=256, PAYLOAD_SIZE=768).
//
// Storage design:
//
//   Two LMDB named databases in the same env:
//
//   1. "cells" (via LmdbCellStore): 1024-byte canonical phase-0x06 cells.
//      Key = SHA256(cell_bytes).  Phase byte at offset 94.  First 32 bytes
//      of payload (bytes 256..287) = sir_program_hash (32 zero bytes for
//      M5.14 prereq).  Compact binary record in remaining payload space.
//
//   2. "intent_cells_meta": full record JSON keyed by cell_id string.
//      Key = cell_id bytes (variable length, ≤ 128 bytes).
//      Value = JSON-encoded IntentCellRecord (≤ 16 KiB).
//
//   The 1024-byte cell (1) carries the kernel-verifiable data (phase,
//   kernel verdict, sir_hash) and a compact binary header.  The meta DB
//   (2) carries the full text fields needed by findById/list queries.
//
// Cell payload layout (bytes 256..1023, 768 bytes):
//   [256..287]  sir_program_hash (32 bytes, zero until M5.14)
//   [288..291]  opcount     (u32 LE)
//   [292..295]  stack_depth (u32 LE)
//   [296..299]  gas_used    (u32 LE)
//   [300]       kernel_ok   (u8, 0 or 1)
//   [301..428]  cell_id     (u8 length-prefix + up to 127 bytes)
//   [429..493]  hat_id      (u8 length-prefix + up to 63 bytes)
//   [494..621]  cert_id     (u8 length-prefix + up to 127 bytes)
//   [622..686]  corr_id     (u8 length-prefix + up to 63 bytes)
//   [687..750]  received_at (u8 length-prefix + up to 63 bytes)
//   [751..1023] zero padding

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");

// Re-export the IntentCellRecord type so callers import from one place.
pub const IntentCellRecord = @import("intent_cells_store_fs").IntentCellRecord;

pub const PHASE_ACTION: u8 = 0x06;

/// 256-byte header, commerce-phase byte at offset 94.
const HEADER_OFFSET_COMMERCE_PHASE: usize = 94;
const CELL_HEADER_SIZE: usize = 256;
const SIR_HASH_LEN: usize = 32;
const SIR_HASH_OFFSET: usize = CELL_HEADER_SIZE; // first 32 bytes of payload

/// Maximum cell_id length (bytes, excluding length prefix).
pub const MAX_CELL_ID_BYTES: usize = 128;

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    invalid_cell_id,
    /// Same cellId already exists with DIFFERENT content.
    cell_id_in_use_with_different_contents,
};

pub const CreateResult = enum {
    created,
    already_exists,
};

pub const ListOpts = struct {
    hat_id: ?[]const u8 = null,
    since: ?[]const u8 = null,
    limit: ?usize = null,
};

/// A heap-owned decoded record returned from findById / list.
/// Call `deinit` to free.
pub const OwnedRecord = struct {
    record: IntentCellRecord,
    _buf: []u8, // backing buffer for all string slices

    pub fn deinit(self: OwnedRecord, allocator: std.mem.Allocator) void {
        allocator.free(self._buf);
    }
};

pub const IntentCellLmdbStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    cell_store: lmdb_cell_store_mod.LmdbCellStore,
    /// LMDB named DB for full record JSON keyed by cell_id.
    meta_dbi: lmdb.Dbi,

    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!IntentCellLmdbStore {
        // Open the "cells" named DB via LmdbCellStore.
        var cs = lmdb_cell_store_mod.LmdbCellStore.init(env, allocator) catch
            return error.persistence_failed;
        errdefer cs.deinit();

        // Open (or create) the "intent_cells_meta" named DB for full record JSON.
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        const meta_dbi = txn.openDb("intent_cells_meta", .{ .create = true }) catch {
            txn.abort();
            return error.persistence_failed;
        };
        txn.commit() catch return error.persistence_failed;

        return .{
            .env = env,
            .allocator = allocator,
            .cell_store = cs,
            .meta_dbi = meta_dbi,
        };
    }

    pub fn deinit(_: *IntentCellLmdbStore) void {}

    /// Returns a `CellStore` vtable handle backed by the "cells" LMDB DB.
    pub fn cellStore(self: *IntentCellLmdbStore) cell_store_mod.CellStore {
        return self.cell_store.store();
    }

    /// Store an intent cell.  Idempotent on `cell_id`:
    ///   • Same cell_id + byte-identical content → `.already_exists`
    ///   • Same cell_id + different content → `cell_id_in_use_with_different_contents`
    pub fn create(self: *IntentCellLmdbStore, record: IntentCellRecord) StoreError!CreateResult {
        if (record.cell_id.len == 0 or record.cell_id.len > MAX_CELL_ID_BYTES)
            return error.invalid_cell_id;

        // Encode the 1024-byte cell.
        const cell_bytes = encodeCell(record);

        // Build the full record JSON for the meta DB.
        const meta_json = encodeMetaJson(self.allocator, record) catch return error.out_of_memory;
        defer self.allocator.free(meta_json);

        // Check if cell_id already exists in meta DB.
        {
            var ro_txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
            defer ro_txn.abort();
            const existing_val = ro_txn.get(self.meta_dbi, record.cell_id) catch |e| blk: {
                if (e == error.not_found) break :blk null;
                return error.persistence_failed;
            };
            if (existing_val != null) {
                // Cell_id already exists.  Compare stored JSON with new JSON.
                if (std.mem.eql(u8, existing_val.?, meta_json)) {
                    return .already_exists;
                }
                return error.cell_id_in_use_with_different_contents;
            }
        }

        // Write 1024-byte cell to "cells" DB via LmdbCellStore vtable.
        const cs = self.cell_store.store();
        _ = cs.put(&cell_bytes) catch return error.persistence_failed;

        // Write full JSON to "intent_cells_meta" DB.
        {
            var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
            txn.put(self.meta_dbi, record.cell_id, meta_json, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            txn.commit() catch return error.persistence_failed;
        }

        return .created;
    }

    /// Look up a record by `cell_id`.  Returns null on miss.
    /// Caller owns the returned `OwnedRecord`; call `.deinit(allocator)`.
    pub fn findById(self: *IntentCellLmdbStore, allocator: std.mem.Allocator, cell_id: []const u8) StoreError!?OwnedRecord {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();

        const val = txn.get(self.meta_dbi, cell_id) catch |e| {
            if (e == error.not_found) return null;
            return error.persistence_failed;
        };

        return decodeMetaJson(allocator, val) catch return error.out_of_memory;
    }

    /// List all records.  Caller owns the returned slice and each `OwnedRecord`.
    pub fn list(self: *IntentCellLmdbStore, allocator: std.mem.Allocator, opts: ListOpts) StoreError![]OwnedRecord {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();

        var cur = txn.openCursor(self.meta_dbi) catch return error.persistence_failed;
        defer cur.close();

        var results: std.ArrayList(OwnedRecord) = .{};
        errdefer {
            for (results.items) |*r| r.deinit(allocator);
            results.deinit(allocator);
        }

        while (cur.next() catch return error.persistence_failed) |entry| {
            const rec = decodeMetaJson(allocator, entry.val) catch return error.out_of_memory;
            if (rec == null) continue;
            var owned = rec.?;

            // Apply filters.
            if (opts.hat_id) |h| {
                if (!std.mem.eql(u8, owned.record.hat_id, h)) {
                    owned.deinit(allocator);
                    continue;
                }
            }
            if (opts.since) |s| {
                if (std.mem.lessThan(u8, owned.record.received_at, s)) {
                    owned.deinit(allocator);
                    continue;
                }
            }

            results.append(allocator, owned) catch {
                owned.deinit(allocator);
                return error.out_of_memory;
            };
        }

        // Apply limit (tail-cut: keep most-recent N).
        if (opts.limit) |lim| {
            if (results.items.len > lim) {
                const start = results.items.len - lim;
                // Free the records we are dropping (the earliest ones).
                for (results.items[0..start]) |*r| r.deinit(allocator);
                const kept = allocator.alloc(OwnedRecord, lim) catch {
                    results.deinit(allocator);
                    return error.out_of_memory;
                };
                @memcpy(kept, results.items[start..]);
                results.deinit(allocator);
                return kept;
            }
        }

        return results.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    pub fn count(self: *IntentCellLmdbStore) StoreError!u64 {
        return self.cell_store.store().count() catch return error.persistence_failed;
    }
};

// ─── Cell encoding ────────────────────────────────────────────────────────────

/// Build the 1024-byte canonical cell for an intent record.
///
/// Header layout (bytes 0..255):
///   byte 94 = 0x06 (PHASE_ACTION)
///   all other header bytes = 0 (reserved / not yet populated)
///
/// Payload layout (bytes 256..1023, 768 bytes):
///   [256..287]  sir_program_hash (32 zero bytes — M5.14 prereq)
///   [288..291]  opcount  (u32 LE)
///   [292..295]  stack_depth (u32 LE)
///   [296..299]  gas_used (u32 LE)
///   [300]       kernel_ok (0 or 1)
///   [301..]     cell_id (u8 length + bytes), hat_id, cert_id, corr_id, received_at
/// Encode an IntentCellRecord into the canonical 1024-byte cell layout
/// (256-byte header + payload).  Exposed so cartridge handlers can
/// compute the cell SHA-256 hash deterministically without re-implementing
/// the layout (e.g. for AnchorEmitter post-write — see §11.10 order 3a).
pub fn encodeCell(r: IntentCellRecord) [1024]u8 {
    var cell: [1024]u8 = [_]u8{0} ** 1024;

    // Phase byte.
    cell[HEADER_OFFSET_COMMERCE_PHASE] = PHASE_ACTION;

    // sir_program_hash: 32 zero bytes at payload start (M5.14 prereq).
    // (Already zeroed above.)

    // Kernel verdict fields.
    var offset: usize = CELL_HEADER_SIZE + SIR_HASH_LEN; // = 288
    std.mem.writeInt(u32, cell[offset..][0..4], r.opcount, .little);
    offset += 4;
    std.mem.writeInt(u32, cell[offset..][0..4], r.stack_depth, .little);
    offset += 4;
    std.mem.writeInt(u32, cell[offset..][0..4], r.gas_used, .little);
    offset += 4;
    cell[offset] = if (r.kernel_ok) 1 else 0;
    offset += 1;

    // cell_id (length-prefixed).
    offset = writeLenPrefixed(cell[offset..], r.cell_id) + offset;
    // hat_id.
    offset = writeLenPrefixed(cell[offset..], r.hat_id) + offset;
    // cert_id.
    offset = writeLenPrefixed(cell[offset..], r.cert_id) + offset;
    // correlation_id.
    offset = writeLenPrefixed(cell[offset..], r.correlation_id) + offset;
    // received_at.
    _ = writeLenPrefixed(cell[offset..], r.received_at);

    return cell;
}

/// Write a length-prefixed string into `buf` (u8 length byte + bytes).
/// Returns the number of bytes written.
fn writeLenPrefixed(buf: []u8, s: []const u8) usize {
    const len: u8 = @intCast(@min(s.len, 255));
    if (buf.len < 1 + len) return 0; // silent truncate — won't exceed 1024
    buf[0] = len;
    @memcpy(buf[1 .. 1 + len], s[0..len]);
    return 1 + len;
}

// ─── Meta JSON encode / decode ────────────────────────────────────────────────

/// Encode an IntentCellRecord as a compact JSON string.
/// Caller must free the returned slice.
fn encodeMetaJson(allocator: std.mem.Allocator, r: IntentCellRecord) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"cell_id\":");
    try appendJsonString(allocator, &buf, r.cell_id);
    try buf.appendSlice(allocator, ",\"hat_id\":");
    try appendJsonString(allocator, &buf, r.hat_id);
    try buf.appendSlice(allocator, ",\"cert_id\":");
    try appendJsonString(allocator, &buf, r.cert_id);
    try buf.appendSlice(allocator, ",\"correlation_id\":");
    try appendJsonString(allocator, &buf, r.correlation_id);
    try buf.print(allocator, ",\"opcount\":{d}", .{r.opcount});
    try buf.print(allocator, ",\"stack_depth\":{d}", .{r.stack_depth});
    try buf.print(allocator, ",\"gas_used\":{d}", .{r.gas_used});
    try buf.appendSlice(allocator, ",\"kernel_ok\":");
    try buf.appendSlice(allocator, if (r.kernel_ok) "true" else "false");
    try buf.appendSlice(allocator, ",\"phone_kernel_result_json\":");
    try appendJsonString(allocator, &buf, r.phone_kernel_result_json);
    try buf.appendSlice(allocator, ",\"opcode_bytes_b64\":");
    try appendJsonString(allocator, &buf, r.opcode_bytes_b64);
    try buf.appendSlice(allocator, ",\"intent_summary\":");
    try appendJsonString(allocator, &buf, r.intent_summary);
    try buf.appendSlice(allocator, ",\"intent_action\":");
    try appendJsonString(allocator, &buf, r.intent_action);
    try buf.appendSlice(allocator, ",\"intent_taxonomy_json\":");
    try appendJsonString(allocator, &buf, r.intent_taxonomy_json);
    try buf.appendSlice(allocator, ",\"received_at\":");
    try appendJsonString(allocator, &buf, r.received_at);
    try buf.append(allocator, '}');

    return buf.toOwnedSlice(allocator);
}

/// Decode a JSON blob back into an OwnedRecord.
/// Returns null if the JSON is malformed.
fn decodeMetaJson(allocator: std.mem.Allocator, json_bytes: []const u8) !?OwnedRecord {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    const cell_id_v = obj.get("cell_id") orelse return null;
    const hat_id_v = obj.get("hat_id") orelse return null;
    const cert_id_v = obj.get("cert_id") orelse return null;
    const corr_v = obj.get("correlation_id") orelse return null;
    const opcount_v = obj.get("opcount") orelse return null;
    const sd_v = obj.get("stack_depth") orelse return null;
    const gu_v = obj.get("gas_used") orelse return null;
    const ok_v = obj.get("kernel_ok") orelse return null;
    const pkr_v = obj.get("phone_kernel_result_json") orelse return null;
    const ob_v = obj.get("opcode_bytes_b64") orelse return null;
    const sum_v = obj.get("intent_summary") orelse return null;
    const act_v = obj.get("intent_action") orelse return null;
    const tax_v = obj.get("intent_taxonomy_json") orelse return null;
    const ra_v = obj.get("received_at") orelse return null;

    if (cell_id_v != .string or hat_id_v != .string or cert_id_v != .string or
        corr_v != .string or opcount_v != .integer or sd_v != .integer or
        gu_v != .integer or ok_v != .bool or pkr_v != .string or ob_v != .string or
        sum_v != .string or act_v != .string or tax_v != .string or ra_v != .string)
    {
        return null;
    }

    // Copy all strings into one contiguous buffer so the OwnedRecord has a
    // single allocation to free.
    const total_len = cell_id_v.string.len + hat_id_v.string.len +
        cert_id_v.string.len + corr_v.string.len + pkr_v.string.len +
        ob_v.string.len + sum_v.string.len + act_v.string.len +
        tax_v.string.len + ra_v.string.len;
    const buf = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    inline for (.{
        cell_id_v.string,
        hat_id_v.string,
        cert_id_v.string,
        corr_v.string,
        pkr_v.string,
        ob_v.string,
        sum_v.string,
        act_v.string,
        tax_v.string,
        ra_v.string,
    }) |s| {
        @memcpy(buf[pos .. pos + s.len], s);
        pos += s.len;
    }

    // Build slices into the buffer.
    var p: usize = 0;
    const cell_id = buf[p .. p + cell_id_v.string.len]; p += cell_id_v.string.len;
    const hat_id = buf[p .. p + hat_id_v.string.len]; p += hat_id_v.string.len;
    const cert_id = buf[p .. p + cert_id_v.string.len]; p += cert_id_v.string.len;
    const correlation_id = buf[p .. p + corr_v.string.len]; p += corr_v.string.len;
    const phone_kernel = buf[p .. p + pkr_v.string.len]; p += pkr_v.string.len;
    const opcode_b64 = buf[p .. p + ob_v.string.len]; p += ob_v.string.len;
    const summary = buf[p .. p + sum_v.string.len]; p += sum_v.string.len;
    const action = buf[p .. p + act_v.string.len]; p += act_v.string.len;
    const taxonomy = buf[p .. p + tax_v.string.len]; p += tax_v.string.len;
    const received_at = buf[p .. p + ra_v.string.len];

    return OwnedRecord{
        .record = .{
            .cell_id = cell_id,
            .hat_id = hat_id,
            .cert_id = cert_id,
            .correlation_id = correlation_id,
            .opcount = @intCast(opcount_v.integer),
            .stack_depth = @intCast(sd_v.integer),
            .gas_used = @intCast(gu_v.integer),
            .kernel_ok = ok_v.bool,
            .phone_kernel_result_json = phone_kernel,
            .opcode_bytes_b64 = opcode_b64,
            .intent_summary = summary,
            .intent_action = action,
            .intent_taxonomy_json = taxonomy,
            .received_at = received_at,
        },
        ._buf = buf,
    };
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

```
