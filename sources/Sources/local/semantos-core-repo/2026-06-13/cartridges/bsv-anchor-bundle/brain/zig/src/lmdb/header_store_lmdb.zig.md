---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/header_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.449582+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/header_store_lmdb.zig

```zig
// M1.2 — LmdbHeaderStore: HeaderStore vtable backed by LMDB.
//
// Storage layout (two named databases inside one LMDB env):
//   DB "hdr_by_height"  — key: height_be_4 (big-endian u32), value: SerialRecord
//   DB "hdr_by_hash"    — key: hash_32, value: height_be_4
//
// The big-endian height key gives lexicographic == numeric order, so the
// tip is always the last key the cursor lands on and rollback is a
// forward scan from `from_height` to EOF.
//
// SerialRecord layout (116 bytes):
//   [00..04]  height     (u32 LE)
//   [04..08]  version    (u32 LE)
//   [08..40]  prev_hash  (32 bytes)
//   [40..72]  merkle_root(32 bytes)
//   [72..76]  timestamp  (u32 LE)
//   [76..80]  bits       (u32 LE)
//   [80..84]  nonce      (u32 LE)
//   [84..116] hash       (32 bytes) — precomputed, avoids re-hashing on read

const std = @import("std");
const lmdb = @import("lmdb");
const header_store_mod = @import("header_store");

pub const HeaderRecord = header_store_mod.HeaderRecord;
pub const Header = header_store_mod.Header;
pub const StoreError = header_store_mod.StoreError;

const SERIAL_BYTES: usize = 4 + 4 + 32 + 32 + 4 + 4 + 4 + 32; // 116

/// Big-endian u32 key — ensures lexicographic == numeric sort in LMDB.
fn heightKey(height: u32) [4]u8 {
    var k: [4]u8 = undefined;
    std.mem.writeInt(u32, &k, height, .big);
    return k;
}

fn serializeRecord(rec: HeaderRecord) [SERIAL_BYTES]u8 {
    var buf: [SERIAL_BYTES]u8 = undefined;
    std.mem.writeInt(u32, buf[0..4], rec.height, .little);
    std.mem.writeInt(u32, buf[4..8], rec.header.version, .little);
    @memcpy(buf[8..40], &rec.header.prev_hash);
    @memcpy(buf[40..72], &rec.header.merkle_root);
    std.mem.writeInt(u32, buf[72..76], rec.header.timestamp, .little);
    std.mem.writeInt(u32, buf[76..80], rec.header.bits, .little);
    std.mem.writeInt(u32, buf[80..84], rec.header.nonce, .little);
    @memcpy(buf[84..116], &rec.hash);
    return buf;
}

fn deserializeRecord(buf: []const u8) StoreError!HeaderRecord {
    if (buf.len < SERIAL_BYTES) return error.persistence_failed;
    const height = std.mem.readInt(u32, buf[0..4], .little);
    const version = std.mem.readInt(u32, buf[4..8], .little);
    var prev_hash: [32]u8 = undefined;
    @memcpy(&prev_hash, buf[8..40]);
    var merkle_root: [32]u8 = undefined;
    @memcpy(&merkle_root, buf[40..72]);
    const timestamp = std.mem.readInt(u32, buf[72..76], .little);
    const bits = std.mem.readInt(u32, buf[76..80], .little);
    const nonce = std.mem.readInt(u32, buf[80..84], .little);
    var hash: [32]u8 = undefined;
    @memcpy(&hash, buf[84..116]);
    return .{
        .height = height,
        .header = .{
            .version = version,
            .prev_hash = prev_hash,
            .merkle_root = merkle_root,
            .timestamp = timestamp,
            .bits = bits,
            .nonce = nonce,
        },
        .hash = hash,
    };
}

pub const LmdbHeaderStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi_by_height: lmdb.Dbi,
    dbi_by_hash: lmdb.Dbi,

    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!LmdbHeaderStore {
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        const dbi_h = txn.openDb("hdr_by_height", .{ .create = true }) catch
            return error.persistence_failed;
        const dbi_hash = txn.openDb("hdr_by_hash", .{ .create = true }) catch
            return error.persistence_failed;
        txn.commit() catch return error.persistence_failed;
        return .{
            .env = env,
            .allocator = allocator,
            .dbi_by_height = dbi_h,
            .dbi_by_hash = dbi_hash,
        };
    }

    pub fn deinit(_: *LmdbHeaderStore) void {}

    pub fn store(self: *LmdbHeaderStore) header_store_mod.HeaderStore {
        return .{ .ctx = @ptrCast(self), .vtable = &vtable };
    }

    // ── internal helpers ──────────────────────────────────────────────

    fn getRecordByHeight(self: *LmdbHeaderStore, height: u32) ?HeaderRecord {
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        const k = heightKey(height);
        const raw = txn.get(self.dbi_by_height, &k) catch return null;
        return deserializeRecord(raw) catch null;
    }

    fn getRecordByHash(self: *LmdbHeaderStore, hash: *const [32]u8) ?HeaderRecord {
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        const height_bytes = txn.get(self.dbi_by_hash, hash) catch return null;
        if (height_bytes.len < 4) return null;
        const height_be: *const [4]u8 = height_bytes[0..4];
        const height = std.mem.readInt(u32, height_be, .big);
        const k = heightKey(height);
        const raw = txn.get(self.dbi_by_height, &k) catch return null;
        return deserializeRecord(raw) catch null;
    }

    fn getTip(self: *LmdbHeaderStore) ?HeaderRecord {
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_height) catch return null;
        defer cur.close();
        const entry = cur.last() catch return null;
        if (entry == null) return null;
        return deserializeRecord(entry.?.val) catch null;
    }

    fn doAppendValidated(
        self: *LmdbHeaderStore,
        header: Header,
        height: u32,
    ) StoreError!void {
        const tip_opt = self.getTip();
        if (tip_opt) |t| {
            if (height != t.height + 1) return error.height_out_of_order;
            if (!std.mem.eql(u8, &header.prev_hash, &t.hash)) {
                return error.prev_hash_mismatch;
            }
        }

        const new_hash = header.computeHash();
        const rec = HeaderRecord{ .header = header, .height = height, .hash = new_hash };
        const serial = serializeRecord(rec);

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        const hk = heightKey(height);
        txn.put(self.dbi_by_height, &hk, &serial, .{}) catch return error.persistence_failed;

        const height_be = heightKey(height); // big-endian height stored as value in hash index
        txn.put(self.dbi_by_hash, &new_hash, &height_be, .{}) catch return error.persistence_failed;

        txn.commit() catch return error.persistence_failed;
    }

    fn doSnapshot(self: *LmdbHeaderStore, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();

        var cur = txn.openCursor(self.dbi_by_height) catch return error.persistence_failed;
        defer cur.close();

        var list: std.ArrayList(HeaderRecord) = .empty;
        errdefer list.deinit(allocator);

        while (cur.next() catch return error.persistence_failed) |entry| {
            const rec = deserializeRecord(entry.val) catch return error.persistence_failed;
            list.append(allocator, rec) catch return error.out_of_memory;
        }
        return list.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn doReplay(self: *LmdbHeaderStore, records: []const HeaderRecord) StoreError!void {
        for (records, 0..) |r, i| {
            if (i > 0) {
                const prev = records[i - 1];
                if (r.height != prev.height + 1) return error.height_out_of_order;
                if (!std.mem.eql(u8, &r.header.prev_hash, &prev.hash)) {
                    return error.prev_hash_mismatch;
                }
            }
        }

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        txn.clear(self.dbi_by_height) catch return error.persistence_failed;
        txn.clear(self.dbi_by_hash) catch return error.persistence_failed;

        for (records) |r| {
            const serial = serializeRecord(r);
            const hk = heightKey(r.height);
            txn.put(self.dbi_by_height, &hk, &serial, .{}) catch return error.persistence_failed;
            const height_be = heightKey(r.height);
            txn.put(self.dbi_by_hash, &r.hash, &height_be, .{}) catch return error.persistence_failed;
        }

        txn.commit() catch return error.persistence_failed;
    }

    fn doRollbackFrom(self: *LmdbHeaderStore, from_height: u32) StoreError!u32 {
        // Collect records to delete first (read txn), then delete in a write txn.
        // This avoids holding a write txn while scanning.
        var txn_r = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        var to_drop: std.ArrayList(struct { height: u32, hash: [32]u8 }) = .empty;
        defer to_drop.deinit(self.allocator);
        {
            defer txn_r.abort();
            var cur = txn_r.openCursor(self.dbi_by_height) catch return error.persistence_failed;
            defer cur.close();

            const seek_k = heightKey(from_height);
            const first = cur.seek(&seek_k) catch return error.persistence_failed;
            if (first == null) return 0;

            // First entry.
            const rec0 = deserializeRecord(first.?.val) catch return error.persistence_failed;
            to_drop.append(self.allocator, .{ .height = rec0.height, .hash = rec0.hash }) catch
                return error.out_of_memory;

            // Remaining entries.
            while (cur.step() catch return error.persistence_failed) |entry| {
                const rec = deserializeRecord(entry.val) catch return error.persistence_failed;
                to_drop.append(self.allocator, .{ .height = rec.height, .hash = rec.hash }) catch
                    return error.out_of_memory;
            }
        }

        if (to_drop.items.len == 0) return 0;

        var txn_w = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn_w.abort();
        for (to_drop.items) |item| {
            const hk = heightKey(item.height);
            txn_w.del(self.dbi_by_height, &hk, null) catch {};
            txn_w.del(self.dbi_by_hash, &item.hash, null) catch {};
        }
        txn_w.commit() catch return error.persistence_failed;
        return @intCast(to_drop.items.len);
    }

    // ── vtable shims ──────────────────────────────────────────────────

    fn vGetByHeight(ctx: *anyopaque, height: u32) ?HeaderRecord {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.getRecordByHeight(height);
    }
    fn vGetByHash(ctx: *anyopaque, hash: *const [32]u8) ?HeaderRecord {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.getRecordByHash(hash);
    }
    fn vAppendValidated(ctx: *anyopaque, header: Header, height: u32) StoreError!void {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.doAppendValidated(header, height);
    }
    fn vTip(ctx: *anyopaque) ?HeaderRecord {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.getTip();
    }
    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.doSnapshot(allocator);
    }
    fn vReplay(ctx: *anyopaque, records: []const HeaderRecord) StoreError!void {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.doReplay(records);
    }
    fn vRollbackFrom(ctx: *anyopaque, from_height: u32) StoreError!u32 {
        const self: *LmdbHeaderStore = @ptrCast(@alignCast(ctx));
        return self.doRollbackFrom(from_height);
    }

    const vtable = header_store_mod.HeaderStore.VTable{
        .get_by_height = vGetByHeight,
        .get_by_hash = vGetByHash,
        .append_validated = vAppendValidated,
        .tip = vTip,
        .snapshot = vSnapshot,
        .replay = vReplay,
        .rollback_from = vRollbackFrom,
    };
};

```
