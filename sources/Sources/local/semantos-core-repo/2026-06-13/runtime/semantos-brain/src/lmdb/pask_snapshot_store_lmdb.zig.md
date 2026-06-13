---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/pask_snapshot_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.278787+00:00
---

# runtime/semantos-brain/src/lmdb/pask_snapshot_store_lmdb.zig

```zig
// M1.11 / W7.10 — LmdbPaskSnapshotStore: PaskSnapshotStore vtable backed by LMDB.
//
// Storage layout (two named databases inside one LMDB env):
//
//   DB "pask_snapshots"
//     key:   op_pkh (8B) ++ user_cert_id_bytes ++ be_u64(version)
//     value: raw snapshot blob (12-byte header + Store image)
//
//   DB "pask_snapshot_current"
//     key:   op_pkh (8B) ++ user_cert_id_bytes
//     value: be_u64(latest_version)   (8 bytes)
//
// W7.10 — op_pkh prefix (8 raw bytes = 16 hex chars, matching the W7.1 LMDB
// cell prefix) ensures that operator A's snapshots never overlap operator B's.
// Single-tenant deployments use `init()` which sets op_pkh = [0]*8.
// Hosted operators use `initForOperator(op_pkh)`.
//
// Big-endian version bytes give lexicographic == numeric ordering, so
// "last key with this cert prefix" == "highest version".  Cursor reverse
// scans for rollbackTo and snapshotHistory exploit this directly.
//
// Version counter: monotonically increasing u64 stored per-user in
// "pask_snapshot_current" as the latest version.  commitSnapshot reads it
// (+1), then writes both DBs atomically in a single write txn.
//
// Magic validation:
//   [00..04]  0x4B534150 ("PASK") LE
//   [04..08]  version (must be 1)
//   [08..12]  payload length (must equal blob.len - 12)
// Blobs that fail this check are rejected with error.corrupt_snapshot.

const std = @import("std");
const lmdb = @import("lmdb");
const pask_snapshot_store_mod = @import("pask_snapshot_store");

pub const PaskSnapshotStore = pask_snapshot_store_mod.PaskSnapshotStore;
pub const SnapshotMeta = PaskSnapshotStore.SnapshotMeta;
pub const StoreError = PaskSnapshotStore.Error;

/// W7.10 — operator prefix length in bytes (8 raw bytes = 16 hex chars).
pub const OP_PKH_BYTES: usize = 8;

const PASK_MAGIC: u32 = 0x4B534150;
const PASK_VERSION: u32 = 1;
const HEADER_SIZE: usize = 12;

// ── Key helpers ───────────────────────────────────────────────────────────

/// Concatenate op_pkh (8B) + cert_id bytes + big-endian version into `buf`.
/// Returns a slice into `buf`.  `buf` must be >= OP_PKH_BYTES + cert_id.len + 8.
fn snapshotKey(buf: []u8, op_pkh: *const [OP_PKH_BYTES]u8, cert_id: []const u8, version: u64) []u8 {
    const key_len = OP_PKH_BYTES + cert_id.len + 8;
    @memcpy(buf[0..OP_PKH_BYTES], op_pkh);
    @memcpy(buf[OP_PKH_BYTES .. OP_PKH_BYTES + cert_id.len], cert_id);
    std.mem.writeInt(u64, buf[OP_PKH_BYTES + cert_id.len ..][0..8], version, .big);
    return buf[0..key_len];
}

/// Concatenate op_pkh (8B) + cert_id bytes into `buf`.  Used for current-pointer key.
fn currentKey(buf: []u8, op_pkh: *const [OP_PKH_BYTES]u8, cert_id: []const u8) []u8 {
    const key_len = OP_PKH_BYTES + cert_id.len;
    @memcpy(buf[0..OP_PKH_BYTES], op_pkh);
    @memcpy(buf[OP_PKH_BYTES..key_len], cert_id);
    return buf[0..key_len];
}

fn versionFromBytes(b: []const u8) u64 {
    return std.mem.readInt(u64, b[0..8], .big);
}

fn versionToBytes(version: u64) [8]u8 {
    var b: [8]u8 = undefined;
    std.mem.writeInt(u64, &b, version, .big);
    return b;
}

// ── Blob validation ───────────────────────────────────────────────────────

fn validateBlob(blob: []const u8) StoreError!void {
    if (blob.len < HEADER_SIZE) return error.corrupt_snapshot;
    const magic = std.mem.readInt(u32, blob[0..4], .little);
    const ver = std.mem.readInt(u32, blob[4..8], .little);
    const length = std.mem.readInt(u32, blob[8..12], .little);
    if (magic != PASK_MAGIC) return error.corrupt_snapshot;
    if (ver != PASK_VERSION) return error.corrupt_snapshot;
    if (length != blob.len - HEADER_SIZE) return error.corrupt_snapshot;
}

fn blobMagicOk(blob: []const u8) bool {
    validateBlob(blob) catch return false;
    return true;
}

// ── LmdbPaskSnapshotStore ─────────────────────────────────────────────────

pub const LmdbPaskSnapshotStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi_snapshots: lmdb.Dbi,
    dbi_current: lmdb.Dbi,
    /// W7.10 — operator prefix.  Zero bytes for single-tenant deployments.
    op_pkh: [OP_PKH_BYTES]u8,

    // ── Constructors ──────────────────────────────────────────────────────

    /// Single-tenant constructor.  op_pkh = all-zero bytes.
    /// All existing call sites use this form — no signature change.
    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!LmdbPaskSnapshotStore {
        return initInternal(env, allocator, [_]u8{0} ** OP_PKH_BYTES);
    }

    /// W7.10 — hosted-operator constructor.  `op_pkh` must be exactly
    /// OP_PKH_BYTES bytes (first 8 bytes of the operator's pubkey hash).
    pub fn initForOperator(
        env: *lmdb.Env,
        allocator: std.mem.Allocator,
        op_pkh: [OP_PKH_BYTES]u8,
    ) StoreError!LmdbPaskSnapshotStore {
        return initInternal(env, allocator, op_pkh);
    }

    fn initInternal(
        env: *lmdb.Env,
        allocator: std.mem.Allocator,
        op_pkh: [OP_PKH_BYTES]u8,
    ) StoreError!LmdbPaskSnapshotStore {
        var txn = env.beginTxn(.read_write) catch return error.lmdb_error;
        errdefer txn.abort();
        const dbi_snap = txn.openDb("pask_snapshots", .{ .create = true }) catch
            return error.lmdb_error;
        const dbi_cur = txn.openDb("pask_snapshot_current", .{ .create = true }) catch
            return error.lmdb_error;
        txn.commit() catch return error.lmdb_error;
        return .{
            .env = env,
            .allocator = allocator,
            .dbi_snapshots = dbi_snap,
            .dbi_current = dbi_cur,
            .op_pkh = op_pkh,
        };
    }

    pub fn deinit(_: *LmdbPaskSnapshotStore) void {}

    pub fn store(self: *LmdbPaskSnapshotStore) PaskSnapshotStore {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }

    // ── Stack-buffer size ─────────────────────────────────────────────────
    // Keys: op_pkh(8) + cert_id(up to 4096) + version(8) = up to 4112.
    const KEY_BUF_SIZE = OP_PKH_BYTES + 4096 + 8;

    // ── Internal helpers ──────────────────────────────────────────────────

    /// Read the latest version for a user from dbi_current.
    /// Returns null when the user has no snapshots.
    fn getLatestVersion(self: *LmdbPaskSnapshotStore, txn: lmdb.Txn, cert_id: []const u8) ?u64 {
        var buf: [KEY_BUF_SIZE]u8 = undefined;
        if (cert_id.len > 4096) return null;
        const key = currentKey(&buf, &self.op_pkh, cert_id);
        const raw = txn.get(self.dbi_current, key) catch return null;
        if (raw.len < 8) return null;
        return versionFromBytes(raw);
    }

    fn doLoadCurrent(
        self: *LmdbPaskSnapshotStore,
        cert_id: []const u8,
        allocator: std.mem.Allocator,
    ) StoreError!?[]u8 {
        var txn = self.env.beginTxn(.read_only) catch return error.lmdb_error;
        defer txn.abort();

        const latest = self.getLatestVersion(txn, cert_id) orelse return null;

        var key_buf: [KEY_BUF_SIZE]u8 = undefined;
        if (cert_id.len > 4096) return error.lmdb_error;
        const key = snapshotKey(&key_buf, &self.op_pkh, cert_id, latest);

        const raw = txn.get(self.dbi_snapshots, key) catch |e| {
            if (e == error.not_found) return error.not_found;
            return error.lmdb_error;
        };

        const copy = allocator.dupe(u8, raw) catch return error.out_of_memory;
        return copy;
    }

    fn doCommitSnapshot(
        self: *LmdbPaskSnapshotStore,
        cert_id: []const u8,
        blob: []const u8,
    ) StoreError!u64 {
        try validateBlob(blob);

        var txn = self.env.beginTxn(.read_write) catch return error.lmdb_error;
        errdefer txn.abort();

        const prev_version = self.getLatestVersion(txn, cert_id);
        const new_version: u64 = if (prev_version) |v| v + 1 else 1;

        var key_buf: [KEY_BUF_SIZE]u8 = undefined;
        if (cert_id.len > 4096) return error.lmdb_error;
        const snap_key = snapshotKey(&key_buf, &self.op_pkh, cert_id, new_version);
        txn.put(self.dbi_snapshots, snap_key, blob, .{}) catch return error.lmdb_error;

        var cur_buf: [KEY_BUF_SIZE]u8 = undefined;
        const cur_key = currentKey(&cur_buf, &self.op_pkh, cert_id);
        const ver_bytes = versionToBytes(new_version);
        txn.put(self.dbi_current, cur_key, &ver_bytes, .{}) catch return error.lmdb_error;

        txn.commit() catch return error.lmdb_error;
        return new_version;
    }

    fn doRollbackTo(
        self: *LmdbPaskSnapshotStore,
        cert_id: []const u8,
        version: u64,
    ) StoreError!void {
        // Build the full key prefix for this operator + cert_id.
        var prefix_buf: [KEY_BUF_SIZE]u8 = undefined;
        if (cert_id.len > 4096) return error.lmdb_error;
        const prefix_len = OP_PKH_BYTES + cert_id.len;
        @memcpy(prefix_buf[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix_buf[OP_PKH_BYTES..prefix_len], cert_id);
        const prefix = prefix_buf[0..prefix_len];

        var keys_to_del: std.ArrayList([]u8) = .empty;
        defer {
            for (keys_to_del.items) |k| self.allocator.free(k);
            keys_to_del.deinit(self.allocator);
        }

        {
            var txn_r = self.env.beginTxn(.read_only) catch return error.lmdb_error;
            defer txn_r.abort();

            // Seek to op_pkh ++ cert_id ++ be_u64(0).
            var seek_buf: [KEY_BUF_SIZE]u8 = undefined;
            const seek_key = snapshotKey(&seek_buf, &self.op_pkh, cert_id, 0);

            var cur = txn_r.openCursor(self.dbi_snapshots) catch return error.lmdb_error;
            defer cur.close();

            var entry_opt = cur.seek(seek_key) catch return error.lmdb_error;
            while (entry_opt) |entry| {
                if (!std.mem.startsWith(u8, entry.key, prefix)) break;
                if (entry.key.len < prefix_len + 8) {
                    entry_opt = cur.step() catch return error.lmdb_error;
                    continue;
                }
                const entry_ver = versionFromBytes(entry.key[prefix_len..]);
                if (entry_ver > version) {
                    const key_copy = self.allocator.dupe(u8, entry.key) catch
                        return error.out_of_memory;
                    keys_to_del.append(self.allocator, key_copy) catch return error.out_of_memory;
                }
                entry_opt = cur.step() catch return error.lmdb_error;
            }
        }

        var txn_w = self.env.beginTxn(.read_write) catch return error.lmdb_error;
        errdefer txn_w.abort();

        for (keys_to_del.items) |k| {
            txn_w.del(self.dbi_snapshots, k, null) catch {};
        }

        var check_buf: [KEY_BUF_SIZE]u8 = undefined;
        const check_key = snapshotKey(&check_buf, &self.op_pkh, cert_id, version);
        const exists = blk: {
            _ = txn_w.get(self.dbi_snapshots, check_key) catch |e| {
                if (e == error.not_found) break :blk false;
                txn_w.abort();
                return error.lmdb_error;
            };
            break :blk true;
        };
        if (!exists) {
            txn_w.abort();
            return error.not_found;
        }

        var cur_buf: [KEY_BUF_SIZE]u8 = undefined;
        const cur_key = currentKey(&cur_buf, &self.op_pkh, cert_id);
        const ver_bytes = versionToBytes(version);
        txn_w.put(self.dbi_current, cur_key, &ver_bytes, .{}) catch return error.lmdb_error;

        txn_w.commit() catch return error.lmdb_error;
    }

    fn doSnapshotHistory(
        self: *LmdbPaskSnapshotStore,
        cert_id: []const u8,
        limit: u32,
        allocator: std.mem.Allocator,
    ) StoreError![]SnapshotMeta {
        var txn = self.env.beginTxn(.read_only) catch return error.lmdb_error;
        defer txn.abort();

        var cur = txn.openCursor(self.dbi_snapshots) catch return error.lmdb_error;
        defer cur.close();

        // Build full prefix: op_pkh ++ cert_id.
        var prefix_buf: [KEY_BUF_SIZE]u8 = undefined;
        if (cert_id.len > 4096) return error.lmdb_error;
        const prefix_len = OP_PKH_BYTES + cert_id.len;
        @memcpy(prefix_buf[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix_buf[OP_PKH_BYTES..prefix_len], cert_id);
        const prefix = prefix_buf[0..prefix_len];

        // Seek to op_pkh ++ cert_id ++ be_u64(maxInt) to land at or before the
        // last snapshot, then walk backwards.
        var max_buf: [KEY_BUF_SIZE]u8 = undefined;
        const max_key = snapshotKey(&max_buf, &self.op_pkh, cert_id, std.math.maxInt(u64));

        var cur_entry_opt = cur.seek(max_key) catch null;
        if (cur_entry_opt == null) {
            cur_entry_opt = cur.last() catch return error.lmdb_error;
        }

        var list: std.ArrayList(SnapshotMeta) = .empty;
        errdefer list.deinit(allocator);

        var collected: u32 = 0;
        while (cur_entry_opt) |entry| {
            if (collected >= limit) break;
            if (!std.mem.startsWith(u8, entry.key, prefix)) {
                cur_entry_opt = cur.prev() catch return error.lmdb_error;
                continue;
            }
            if (entry.key.len < prefix_len + 8) {
                cur_entry_opt = cur.prev() catch return error.lmdb_error;
                continue;
            }
            const entry_ver = versionFromBytes(entry.key[prefix_len..]);
            const meta = SnapshotMeta{
                .version = entry_ver,
                .size = entry.val.len,
                .magic_ok = blobMagicOk(entry.val),
            };
            list.append(allocator, meta) catch return error.out_of_memory;
            collected += 1;
            cur_entry_opt = cur.prev() catch return error.lmdb_error;
        }

        return list.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    /// W7.10 / W7.8 operator exit — delete all snapshots for this op_pkh.
    /// Uses a cursor scan over the op_pkh prefix in both DBs.
    pub fn deleteAllSnapshots(self: *LmdbPaskSnapshotStore) StoreError!void {
        var txn = self.env.beginTxn(.read_write) catch return error.lmdb_error;
        errdefer txn.abort();

        // Delete from dbi_snapshots (op_pkh prefix).
        try deletePrefixedKeys(&txn, self.dbi_snapshots, &self.op_pkh, self.allocator);
        // Delete from dbi_current (op_pkh prefix).
        try deletePrefixedKeys(&txn, self.dbi_current, &self.op_pkh, self.allocator);

        txn.commit() catch return error.lmdb_error;
    }

    fn deletePrefixedKeys(
        txn: *lmdb.Txn,
        dbi: lmdb.Dbi,
        op_pkh: *const [OP_PKH_BYTES]u8,
        allocator: std.mem.Allocator,
    ) StoreError!void {
        var keys: std.ArrayList([]u8) = .empty;
        defer {
            for (keys.items) |k| allocator.free(k);
            keys.deinit(allocator);
        }

        // Collect phase: scan op_pkh prefix and copy all matching keys.
        {
            var cur = txn.openCursor(dbi) catch return error.lmdb_error;
            defer cur.close();

            const first = cur.seek(op_pkh) catch null;
            if (first == null) return;

            var entry_opt: ?lmdb.CursorEntry = first;
            while (entry_opt) |entry| {
                if (!std.mem.startsWith(u8, entry.key, op_pkh)) break;
                const key_copy = allocator.dupe(u8, entry.key) catch return error.out_of_memory;
                keys.append(allocator, key_copy) catch return error.out_of_memory;
                entry_opt = cur.step() catch null;
            }
            // defer closes cursor here before the delete phase
        }

        // Delete phase: cursor is closed, safe to delete via txn.
        for (keys.items) |k| {
            txn.del(dbi, k, null) catch {};
        }
    }

    /// W7.7 — Export all snapshot data for this op_pkh as a flat binary blob.
    ///
    /// Format: length-prefixed pairs — for each entry:
    ///   [4B: key_len LE] [key_len bytes: raw key] [4B: val_len LE] [val_len bytes: raw val]
    ///
    /// Returns null if there are no snapshots.  Caller frees returned slice.
    pub fn exportRaw(self: *LmdbPaskSnapshotStore, allocator: std.mem.Allocator) StoreError!?[]u8 {
        var txn = self.env.beginTxn(.read_only) catch return error.lmdb_error;
        defer txn.abort();

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        // Export from dbi_snapshots.
        try exportPrefixedEntries(&txn, self.dbi_snapshots, &self.op_pkh, &out, allocator);
        // Export from dbi_current.
        try exportPrefixedEntries(&txn, self.dbi_current, &self.op_pkh, &out, allocator);

        if (out.items.len == 0) {
            out.deinit(allocator);
            return null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn exportPrefixedEntries(
        txn: *lmdb.Txn,
        dbi: lmdb.Dbi,
        op_pkh: *const [OP_PKH_BYTES]u8,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
    ) StoreError!void {
        var cur = txn.openCursor(dbi) catch return error.lmdb_error;
        defer cur.close();

        const first = cur.seek(op_pkh) catch null;
        if (first == null) return;

        var entry_opt: ?lmdb.CursorEntry = first;
        while (entry_opt) |entry| {
            if (!std.mem.startsWith(u8, entry.key, op_pkh)) break;
            // [4B key_len][key][4B val_len][val]
            var len_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &len_buf, @intCast(entry.key.len), .little);
            out.appendSlice(allocator, &len_buf) catch return error.out_of_memory;
            out.appendSlice(allocator, entry.key) catch return error.out_of_memory;
            std.mem.writeInt(u32, &len_buf, @intCast(entry.val.len), .little);
            out.appendSlice(allocator, &len_buf) catch return error.out_of_memory;
            out.appendSlice(allocator, entry.val) catch return error.out_of_memory;
            entry_opt = cur.step() catch null;
        }
    }

    // ── Vtable shims ──────────────────────────────────────────────────────

    fn vLoadCurrent(
        ptr: *anyopaque,
        cert_id: []const u8,
        allocator: std.mem.Allocator,
    ) StoreError!?[]u8 {
        const self: *LmdbPaskSnapshotStore = @ptrCast(@alignCast(ptr));
        return self.doLoadCurrent(cert_id, allocator);
    }

    fn vCommitSnapshot(
        ptr: *anyopaque,
        cert_id: []const u8,
        blob: []const u8,
    ) StoreError!u64 {
        const self: *LmdbPaskSnapshotStore = @ptrCast(@alignCast(ptr));
        return self.doCommitSnapshot(cert_id, blob);
    }

    fn vRollbackTo(ptr: *anyopaque, cert_id: []const u8, version: u64) StoreError!void {
        const self: *LmdbPaskSnapshotStore = @ptrCast(@alignCast(ptr));
        return self.doRollbackTo(cert_id, version);
    }

    fn vSnapshotHistory(
        ptr: *anyopaque,
        cert_id: []const u8,
        limit: u32,
        allocator: std.mem.Allocator,
    ) StoreError![]SnapshotMeta {
        const self: *LmdbPaskSnapshotStore = @ptrCast(@alignCast(ptr));
        return self.doSnapshotHistory(cert_id, limit, allocator);
    }

    fn vDeinit(ptr: *anyopaque) void {
        const self: *LmdbPaskSnapshotStore = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    const vtable = PaskSnapshotStore.VTable{
        .loadCurrent = vLoadCurrent,
        .commitSnapshot = vCommitSnapshot,
        .rollbackTo = vRollbackTo,
        .snapshotHistory = vSnapshotHistory,
        .deinit = vDeinit,
    };
};

// ── Inline tests ──────────────────────────────────────────────────────────────
//
// W7.10 acceptance: snapshot read/write paths scoped by op_pkh;
// cross-operator reads return null; deleteAllSnapshots removes only the
// operator's own snapshots.

fn makeBlob(allocator: std.mem.Allocator, payload_byte: u8, payload_len: usize) ![]u8 {
    const total = HEADER_SIZE + payload_len;
    const blob = try allocator.alloc(u8, total);
    std.mem.writeInt(u32, blob[0..4], PASK_MAGIC, .little);
    std.mem.writeInt(u32, blob[4..8], PASK_VERSION, .little);
    std.mem.writeInt(u32, blob[8..12], @intCast(payload_len), .little);
    @memset(blob[HEADER_SIZE..], payload_byte);
    return blob;
}

test "W7.10: single-tenant init uses zero op_pkh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .max_dbs = 8 });
    defer env.close();

    var s = try LmdbPaskSnapshotStore.init(&env, std.testing.allocator);
    defer s.deinit();

    const expected = [_]u8{0} ** OP_PKH_BYTES;
    try std.testing.expectEqualSlices(u8, &expected, &s.op_pkh);
}

test "W7.10: commit and load scoped to op_pkh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .max_dbs = 8 });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0xAA } ++ [_]u8{0} ** 7;
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0xBB } ++ [_]u8{0} ** 7;

    var store_a = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    const blob = try makeBlob(std.testing.allocator, 0x42, 64);
    defer std.testing.allocator.free(blob);

    const cert_id = "cert-abc";

    // Commit under operator A.
    const ver = try store_a.doCommitSnapshot(cert_id, blob);
    try std.testing.expectEqual(@as(u64, 1), ver);

    // Operator A can load it back.
    const loaded_a = try store_a.doLoadCurrent(cert_id, std.testing.allocator);
    try std.testing.expect(loaded_a != null);
    try std.testing.expectEqualSlices(u8, blob, loaded_a.?);
    std.testing.allocator.free(loaded_a.?);

    // Operator B cannot see it (different op_pkh prefix).
    const loaded_b = try store_b.doLoadCurrent(cert_id, std.testing.allocator);
    try std.testing.expect(loaded_b == null);
}

test "W7.10: version counter is per-op_pkh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .max_dbs = 8 });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0x01 } ++ [_]u8{0} ** 7;
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0x02 } ++ [_]u8{0} ** 7;

    var sa = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var sb = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer sa.deinit();
    defer sb.deinit();

    const blob = try makeBlob(std.testing.allocator, 0x11, 16);
    defer std.testing.allocator.free(blob);

    // Each operator's version counter starts at 1 independently.
    const ver_a1 = try sa.doCommitSnapshot("cert-x", blob);
    const ver_b1 = try sb.doCommitSnapshot("cert-x", blob);
    const ver_a2 = try sa.doCommitSnapshot("cert-x", blob);

    try std.testing.expectEqual(@as(u64, 1), ver_a1);
    try std.testing.expectEqual(@as(u64, 1), ver_b1);
    try std.testing.expectEqual(@as(u64, 2), ver_a2);
}

test "W7.10: deleteAllSnapshots removes only this operator's snapshots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .max_dbs = 8 });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0xCA } ++ [_]u8{0} ** 7;
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0xCB } ++ [_]u8{0} ** 7;

    var sa = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var sb = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer sa.deinit();
    defer sb.deinit();

    const blob = try makeBlob(std.testing.allocator, 0xDD, 32);
    defer std.testing.allocator.free(blob);

    _ = try sa.doCommitSnapshot("cert-del", blob);
    _ = try sb.doCommitSnapshot("cert-del", blob);

    // Delete operator A's snapshots.
    try sa.deleteAllSnapshots();

    // A's snapshot is gone.
    const after_a = try sa.doLoadCurrent("cert-del", std.testing.allocator);
    try std.testing.expect(after_a == null);

    // B's snapshot is intact.
    const after_b = try sb.doLoadCurrent("cert-del", std.testing.allocator);
    try std.testing.expect(after_b != null);
    std.testing.allocator.free(after_b.?);
}

test "W7.10: rollbackTo works within op_pkh scope" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .max_dbs = 8 });
    defer env.close();

    const pkh: [OP_PKH_BYTES]u8 = [_]u8{ 0xEE } ++ [_]u8{0} ** 7;
    var s = try LmdbPaskSnapshotStore.initForOperator(&env, std.testing.allocator, pkh);
    defer s.deinit();

    const blob1 = try makeBlob(std.testing.allocator, 0x01, 16);
    const blob2 = try makeBlob(std.testing.allocator, 0x02, 16);
    const blob3 = try makeBlob(std.testing.allocator, 0x03, 16);
    defer std.testing.allocator.free(blob1);
    defer std.testing.allocator.free(blob2);
    defer std.testing.allocator.free(blob3);

    _ = try s.doCommitSnapshot("cert-rb", blob1);
    _ = try s.doCommitSnapshot("cert-rb", blob2);
    _ = try s.doCommitSnapshot("cert-rb", blob3);

    // Rollback to version 1.
    try s.doRollbackTo("cert-rb", 1);

    // Current pointer should now be version 1.
    const meta = try s.doSnapshotHistory("cert-rb", 10, std.testing.allocator);
    defer std.testing.allocator.free(meta);
    try std.testing.expectEqual(@as(usize, 1), meta.len);
    try std.testing.expectEqual(@as(u64, 1), meta[0].version);
}

```
