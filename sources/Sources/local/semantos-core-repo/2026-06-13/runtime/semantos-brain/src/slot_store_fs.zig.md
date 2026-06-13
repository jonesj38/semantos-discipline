---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/slot_store_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.222269+00:00
---

# runtime/semantos-brain/src/slot_store_fs.zig

```zig
// Phase Brain 2 — File-backed `SlotStore` implementation for the sovereign-node
// shell.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2 deliverable 3).
//
// The spec calls for lmdb. v0.1 uses a directory-of-files layout instead —
// no system C library, no extra build-time dep. The vtable surface is
// identical to lmdb so swapping in a real lmdb backend later is internal.
// (This pattern was first used by `runtime/node/src/lmdb_slot_store.zig`
// in Phase W6; this file is a clean port + simplification for BRAIN.)
//
// Layout:
//
//     <data-dir>/slots/
//         <8-hex-id>.blob       ← AES-GCM ciphertext envelope owned by host.zig
//         <8-hex-id>.blob.tmp   ← write-then-rename atomic scratch
//
// One file per slot. Each `put` writes a temp file, fsyncs, then renames
// over the permanent name — POSIX rename is atomic so a crash mid-write
// leaves the slot in its prior state. Same peek-then-mutate failure-
// atomicity convention as `LocalSlotStore` and `OP_SIGN`.
//
// The store owns every blob it returns from `get` until the next mutation
// for that slot — matching `LocalSlotStore`'s slice-validity contract.

const std = @import("std");
const slot_store_mod = @import("slot_store");

pub const SlotStore = slot_store_mod.SlotStore;
pub const StoreError = slot_store_mod.StoreError;

pub const FsSlotStore = struct {
    allocator: std.mem.Allocator,
    /// Owned absolute path to the `slots/` subdirectory.
    dir_path: []u8,
    /// Lazy-filled cache of last-loaded blobs. Owned. Same contract as
    /// `LocalSlotStore`: `get` returns a slice valid until next mutation.
    cache: std.AutoHashMap(u32, []u8),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !FsSlotStore {
        const subdir = try std.fs.path.join(allocator, &.{ data_dir, "slots" });
        std.fs.cwd().makePath(subdir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                allocator.free(subdir);
                return err;
            },
        };
        return .{
            .allocator = allocator,
            .dir_path = subdir,
            .cache = std.AutoHashMap(u32, []u8).init(allocator),
        };
    }

    pub fn deinit(self: *FsSlotStore) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| self.allocator.free(entry.value_ptr.*);
        self.cache.deinit();
        self.allocator.free(self.dir_path);
    }

    pub fn store(self: *FsSlotStore) SlotStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &fs_vtable,
        };
    }

    fn slotPath(self: *const FsSlotStore, slot_id: u32, buf: []u8) ![]u8 {
        return try std.fmt.bufPrint(buf, "{s}/{x:0>8}.blob", .{ self.dir_path, slot_id });
    }

    fn slotPathTmp(self: *const FsSlotStore, slot_id: u32, buf: []u8) ![]u8 {
        return try std.fmt.bufPrint(buf, "{s}/{x:0>8}.blob.tmp", .{ self.dir_path, slot_id });
    }

    fn vGet(ctx: *anyopaque, slot_id: u32) StoreError![]const u8 {
        const self: *FsSlotStore = @ptrCast(@alignCast(ctx));
        if (self.cache.get(slot_id)) |cached| return cached;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.not_found,
            else => return error.persistence_failed,
        };
        defer file.close();

        const stat = file.stat() catch return error.persistence_failed;
        if (stat.size > 1 << 20) return error.persistence_failed;

        const buf = self.allocator.alloc(u8, @intCast(stat.size)) catch return error.out_of_memory;
        errdefer self.allocator.free(buf);

        var read_total: usize = 0;
        while (read_total < buf.len) {
            const n = file.read(buf[read_total..]) catch return error.persistence_failed;
            if (n == 0) break;
            read_total += n;
        }
        if (read_total != buf.len) return error.persistence_failed;

        self.cache.put(slot_id, buf) catch return error.out_of_memory;
        return buf;
    }

    fn vPut(ctx: *anyopaque, slot_id: u32, bytes: []const u8) StoreError!void {
        const self: *FsSlotStore = @ptrCast(@alignCast(ctx));
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;
        const tmp_path = self.slotPathTmp(slot_id, &tmp_buf) catch return error.persistence_failed;

        const tmp = std.fs.cwd().createFile(tmp_path, .{ .truncate = true }) catch return error.persistence_failed;
        var ok = false;
        defer if (!ok) {
            std.fs.cwd().deleteFile(tmp_path) catch {};
        };
        {
            var written: usize = 0;
            while (written < bytes.len) {
                const n = tmp.write(bytes[written..]) catch {
                    tmp.close();
                    return error.persistence_failed;
                };
                if (n == 0) {
                    tmp.close();
                    return error.persistence_failed;
                }
                written += n;
            }
            tmp.sync() catch {
                tmp.close();
                return error.persistence_failed;
            };
            tmp.close();
        }
        std.fs.cwd().rename(tmp_path, path) catch return error.persistence_failed;
        ok = true;

        // Drop stale cache entry — next `get` re-reads from disk.
        if (self.cache.fetchRemove(slot_id)) |kv| self.allocator.free(kv.value);
    }

    fn vDelete(ctx: *anyopaque, slot_id: u32) StoreError!void {
        const self: *FsSlotStore = @ptrCast(@alignCast(ctx));
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;
        std.fs.cwd().deleteFile(path) catch |err| switch (err) {
            error.FileNotFound => return error.not_found,
            else => return error.persistence_failed,
        };
        if (self.cache.fetchRemove(slot_id)) |kv| self.allocator.free(kv.value);
    }

    const fs_vtable: SlotStore.VTable = .{
        .get = vGet,
        .put = vPut,
        .delete = vDelete,
    };
};

```
