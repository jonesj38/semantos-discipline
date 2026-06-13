---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/header_store_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.448173+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/header_store_fs.zig

```zig
// Phase Brain 2 — File-backed `HeaderStore` for the sovereign-node shell.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2 deliverable 3).
//
// Persists the wallet's PoW-validated header chain on disk. The on-disk
// format is the simplest thing that works: an append-only flat file with
// one 80-byte header at offset `height * 80`. ~70MB at BSV mainnet tip
// (~860k blocks). A small sidecar index file caches the (hash → height)
// map so `getByHash` is O(1).
//
// Layout:
//
//     <data-dir>/headers.bin            — N × 80-byte raw headers
//     <data-dir>/headers.idx            — append-only (height,hash) records
//     <data-dir>/headers.bin.tmp        — atomic-rewrite scratch (rare)
//
// Append-only: `appendValidated` writes a single 80-byte block at the
// correct offset (no temp+rename — append is atomic). The index file
// gets a single `<hash:32 bytes><height:u32 LE>` record appended.
// Rollback truncates both files.

const std = @import("std");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");

pub const HeaderStore = header_store_mod.HeaderStore;
pub const HeaderRecord = header_store_mod.HeaderRecord;
pub const StoreError = header_store_mod.StoreError;
pub const Header = headers_mod.Header;

const HEADER_BYTES: usize = 80;
const IDX_RECORD_BYTES: usize = 32 + 4;

pub const FsHeaderStore = struct {
    allocator: std.mem.Allocator,
    headers_path: []u8,
    idx_path: []u8,
    /// In-memory cache of all loaded HeaderRecords, indexed by height.
    /// Lazy-filled from disk on init. Keeps `getByHeight` O(1).
    by_height: std.ArrayList(HeaderRecord),
    /// hash → height map for `getByHash`.
    by_hash: std.AutoHashMap([32]u8, u32),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !FsHeaderStore {
        const headers_path = try std.fs.path.join(allocator, &.{ data_dir, "headers.bin" });
        errdefer allocator.free(headers_path);
        const idx_path = try std.fs.path.join(allocator, &.{ data_dir, "headers.idx" });
        errdefer allocator.free(idx_path);
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        var self: FsHeaderStore = .{
            .allocator = allocator,
            .headers_path = headers_path,
            .idx_path = idx_path,
            .by_height = .empty,
            .by_hash = std.AutoHashMap([32]u8, u32).init(allocator),
        };
        self.loadFromDisk() catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                self.deinit();
                return err;
            },
        };
        return self;
    }

    pub fn deinit(self: *FsHeaderStore) void {
        self.by_height.deinit(self.allocator);
        self.by_hash.deinit();
        self.allocator.free(self.headers_path);
        self.allocator.free(self.idx_path);
    }

    pub fn store(self: *FsHeaderStore) HeaderStore {
        return .{ .ctx = @ptrCast(self), .vtable = &fs_vtable };
    }

    fn loadFromDisk(self: *FsHeaderStore) !void {
        // Load headers.bin into the in-memory cache.
        const f = try std.fs.cwd().openFile(self.headers_path, .{});
        defer f.close();
        const stat = try f.stat();
        if (stat.size % HEADER_BYTES != 0) return error.invalid_format;
        const count: u32 = @intCast(stat.size / HEADER_BYTES);
        var buf: [HEADER_BYTES]u8 = undefined;
        var h: u32 = 0;
        while (h < count) : (h += 1) {
            const got = try f.readAll(&buf);
            if (got != HEADER_BYTES) return error.invalid_format;
            const header = headers_mod.Header.parseRaw(&buf);
            const hash = header.computeHash();
            try self.by_height.append(self.allocator, .{
                .header = header,
                .height = h,
                .hash = hash,
            });
            try self.by_hash.put(hash, h);
        }
    }

    fn vGetByHeight(ctx: *anyopaque, height: u32) ?HeaderRecord {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        if (height >= self.by_height.items.len) return null;
        return self.by_height.items[height];
    }

    fn vGetByHash(ctx: *anyopaque, hash: *const [32]u8) ?HeaderRecord {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        const h = self.by_hash.get(hash.*) orelse return null;
        return vGetByHeight(ctx, h);
    }

    fn vAppendValidated(ctx: *anyopaque, header: Header, height: u32) StoreError!void {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        // Strict append-only: height must be tip+1.
        if (self.by_height.items.len == 0) {
            // First record may be at any height — caller's choice.
        } else {
            const last = self.by_height.items[self.by_height.items.len - 1];
            if (height != last.height + 1) return error.height_out_of_order;
            const hash_field = header.prev_hash;
            if (!std.mem.eql(u8, &hash_field, &last.hash)) {
                return error.prev_hash_mismatch;
            }
        }

        // Serialize the header.
        var raw: [HEADER_BYTES]u8 = undefined;
        header.serialize(&raw);
        const new_hash = header.computeHash();

        // Append to headers.bin. We deliberately don't do tmp+rename here:
        // append is atomic (in the sense that a partial write at EOF is
        // detectable on next load by the size%80 check) and the cost of
        // per-append rename would be substantial during bulk sync.
        const f = std.fs.cwd().createFile(self.headers_path, .{
            .truncate = false,
            .read = false,
        }) catch return error.persistence_failed;
        defer f.close();
        f.seekFromEnd(0) catch return error.persistence_failed;
        f.writeAll(&raw) catch return error.persistence_failed;
        f.sync() catch return error.persistence_failed;

        // Append to headers.idx — used purely as a rebuild aid; the
        // canonical hash→height map is reconstructed from headers.bin
        // on next start.
        const idx_f = std.fs.cwd().createFile(self.idx_path, .{
            .truncate = false,
            .read = false,
        }) catch return error.persistence_failed;
        defer idx_f.close();
        idx_f.seekFromEnd(0) catch return error.persistence_failed;
        var idx_rec: [IDX_RECORD_BYTES]u8 = undefined;
        @memcpy(idx_rec[0..32], &new_hash);
        std.mem.writeInt(u32, idx_rec[32..36], height, .little);
        idx_f.writeAll(&idx_rec) catch return error.persistence_failed;

        // Update in-memory state last so a disk-write failure leaves
        // memory in the prior consistent state.
        const rec: HeaderRecord = .{ .header = header, .height = height, .hash = new_hash };
        self.by_height.append(self.allocator, rec) catch return error.out_of_memory;
        self.by_hash.put(new_hash, height) catch {
            _ = self.by_height.pop();
            return error.out_of_memory;
        };
    }

    fn vTip(ctx: *anyopaque) ?HeaderRecord {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.by_height.items.len == 0) return null;
        return self.by_height.items[self.by_height.items.len - 1];
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        const out = allocator.alloc(HeaderRecord, self.by_height.items.len) catch return error.out_of_memory;
        @memcpy(out, self.by_height.items);
        return out;
    }

    fn vReplay(ctx: *anyopaque, records: []const HeaderRecord) StoreError!void {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        // Truncate both files + clear in-memory state, then re-append each
        // record (which writes both headers.bin and headers.idx).
        std.fs.cwd().deleteFile(self.headers_path) catch {};
        std.fs.cwd().deleteFile(self.idx_path) catch {};
        self.by_height.clearRetainingCapacity();
        self.by_hash.clearRetainingCapacity();
        for (records) |r| try vAppendValidated(ctx, r.header, r.height);
    }

    fn vRollbackFrom(ctx: *anyopaque, from_height: u32) StoreError!u32 {
        const self: *FsHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.by_height.items.len == 0) return 0;
        const first_height = self.by_height.items[0].height;
        if (from_height < first_height) {
            const dropped: u32 = @intCast(self.by_height.items.len);
            for (self.by_height.items) |r| _ = self.by_hash.remove(r.hash);
            self.by_height.clearRetainingCapacity();
            // Truncate headers.bin to zero. We tolerate idx file lingering;
            // it'll be rewritten as appends resume.
            std.fs.cwd().deleteFile(self.headers_path) catch {};
            std.fs.cwd().deleteFile(self.idx_path) catch {};
            return dropped;
        }
        const idx = from_height - first_height;
        if (idx >= self.by_height.items.len) return 0;
        const dropped: u32 = @intCast(self.by_height.items.len - idx);
        for (self.by_height.items[idx..]) |r| _ = self.by_hash.remove(r.hash);
        self.by_height.shrinkRetainingCapacity(idx);

        // Truncate headers.bin to the new tip.
        const f = std.fs.cwd().openFile(self.headers_path, .{ .mode = .read_write }) catch return error.persistence_failed;
        defer f.close();
        const new_size = @as(u64, idx) * HEADER_BYTES;
        f.setEndPos(new_size) catch return error.persistence_failed;
        return dropped;
    }

    const fs_vtable: HeaderStore.VTable = .{
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
