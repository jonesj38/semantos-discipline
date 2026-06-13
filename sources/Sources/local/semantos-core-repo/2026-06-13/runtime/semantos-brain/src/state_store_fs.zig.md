---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/state_store_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.225984+00:00
---

# runtime/semantos-brain/src/state_store_fs.zig

```zig
// Phase Brain 2 — File-backed `DerivationStateStore` for the sovereign-node
// shell.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2 deliverable 3).
//
// Same pragmatic choice as `slot_store_fs.zig`: directory-of-files + atomic
// rename instead of lmdb at v0.1. State is small (a few hundred records
// max), rewrites of the whole file are cheap.
//
// Layout:
//
//     <data-dir>/state.bin
//     <data-dir>/state.bin.tmp       (atomic rewrite scratch)
//
// Binary format (little-endian throughout):
//
//     magic:        "SEMSTATE"      (8 bytes)
//     version:      u32             (= 1)
//     reserved:     u32             (= 0)
//     record_count: u32
//     records:      record_count × Record
//   each Record:
//     protocol_hash:  16 bytes
//     counterparty:   33 bytes
//     current_index:   8 bytes (u64 LE)
//
// Atomicity contract (same as `LocalStateStore` and W6's lmdb_state_store):
//   `next_index` peek-then-mutate: read the in-memory map, write
//   `current+1` to disk via tmp+rename, only then update the in-memory
//   map. A persistence failure leaves the index unconsumed — the index
//   counter is the most safety-critical state in the wallet (re-using
//   would publish two transactions under the same key) so we err on the
//   side of "no progress" over "lost write".

const std = @import("std");
const derivation_state_mod = @import("derivation_state");

pub const DerivationStateStore = derivation_state_mod.DerivationStateStore;
pub const Record = derivation_state_mod.Record;
pub const StoreError = derivation_state_mod.StoreError;

const MAGIC: [8]u8 = .{ 'S', 'E', 'M', 'S', 'T', 'A', 'T', 'E' };
const FORMAT_VERSION: u32 = 1;
const HEADER_BYTES: usize = 8 + 4 + 4 + 4; // magic + version + reserved + record_count
const RECORD_BYTES: usize = 16 + 33 + 8;

pub const FsStateStore = struct {
    allocator: std.mem.Allocator,
    file_path: []u8,
    tmp_path: []u8,
    /// In-memory mirror of the file. `nextIndex` mutates this only after
    /// the on-disk write succeeds.
    map: std.AutoHashMap(Key, u64),

    const Key = [16 + 33]u8;

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !FsStateStore {
        const file_path = try std.fs.path.join(allocator, &.{ data_dir, "state.bin" });
        errdefer allocator.free(file_path);
        const tmp_path = try std.fs.path.join(allocator, &.{ data_dir, "state.bin.tmp" });
        errdefer allocator.free(tmp_path);
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        var self: FsStateStore = .{
            .allocator = allocator,
            .file_path = file_path,
            .tmp_path = tmp_path,
            .map = std.AutoHashMap(Key, u64).init(allocator),
        };
        // Lazy-load the on-disk state. Missing file is fine on first run.
        self.loadFromDisk() catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                self.deinit();
                return err;
            },
        };
        return self;
    }

    pub fn deinit(self: *FsStateStore) void {
        self.map.deinit();
        self.allocator.free(self.file_path);
        self.allocator.free(self.tmp_path);
    }

    pub fn store(self: *FsStateStore) DerivationStateStore {
        return .{ .ctx = @ptrCast(self), .vtable = &fs_vtable };
    }

    fn keyFor(protocol_hash: *const [16]u8, counterparty: *const [33]u8) Key {
        var k: Key = undefined;
        @memcpy(k[0..16], protocol_hash);
        @memcpy(k[16..49], counterparty);
        return k;
    }

    /// Serialize the current in-memory map to `tmp_path`, fsync, rename
    /// over `file_path`. Returns `persistence_failed` on any I/O error.
    fn flushToDisk(self: *const FsStateStore) StoreError!void {
        const tmp = std.fs.cwd().createFile(self.tmp_path, .{ .truncate = true }) catch return error.persistence_failed;
        var ok = false;
        defer if (!ok) {
            std.fs.cwd().deleteFile(self.tmp_path) catch {};
        };

        // Header.
        var hdr: [HEADER_BYTES]u8 = undefined;
        @memcpy(hdr[0..8], &MAGIC);
        std.mem.writeInt(u32, hdr[8..12], FORMAT_VERSION, .little);
        std.mem.writeInt(u32, hdr[12..16], 0, .little);
        std.mem.writeInt(u32, hdr[16..20], @intCast(self.map.count()), .little);
        tmp.writeAll(&hdr) catch {
            tmp.close();
            return error.persistence_failed;
        };

        // Records.
        var rec_buf: [RECORD_BYTES]u8 = undefined;
        var it = self.map.iterator();
        while (it.next()) |entry| {
            @memcpy(rec_buf[0..16], entry.key_ptr.*[0..16]);
            @memcpy(rec_buf[16..49], entry.key_ptr.*[16..49]);
            std.mem.writeInt(u64, rec_buf[49..57], entry.value_ptr.*, .little);
            tmp.writeAll(&rec_buf) catch {
                tmp.close();
                return error.persistence_failed;
            };
        }

        tmp.sync() catch {
            tmp.close();
            return error.persistence_failed;
        };
        tmp.close();
        std.fs.cwd().rename(self.tmp_path, self.file_path) catch return error.persistence_failed;
        ok = true;
    }

    fn loadFromDisk(self: *FsStateStore) !void {
        const file = try std.fs.cwd().openFile(self.file_path, .{});
        defer file.close();
        const stat = try file.stat();
        if (stat.size < HEADER_BYTES) return error.invalid_format;
        var hdr: [HEADER_BYTES]u8 = undefined;
        const got = try file.readAll(&hdr);
        if (got != hdr.len) return error.invalid_format;
        if (!std.mem.eql(u8, hdr[0..8], &MAGIC)) return error.invalid_format;
        const ver = std.mem.readInt(u32, hdr[8..12], .little);
        if (ver != FORMAT_VERSION) return error.invalid_format;
        const count = std.mem.readInt(u32, hdr[16..20], .little);

        // Defensive — refuse a count that doesn't fit the file size.
        const expected_size = HEADER_BYTES + @as(u64, count) * RECORD_BYTES;
        if (expected_size > stat.size) return error.invalid_format;

        var rec_buf: [RECORD_BYTES]u8 = undefined;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            _ = try file.readAll(&rec_buf);
            const k: Key = (rec_buf[0..49]).*;
            const idx = std.mem.readInt(u64, rec_buf[49..57], .little);
            try self.map.put(k, idx);
        }
    }

    fn vGetIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        const self: *FsStateStore = @ptrCast(@alignCast(ctx));
        return self.map.get(keyFor(protocol_hash, counterparty));
    }

    fn vNextIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const self: *FsStateStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(protocol_hash, counterparty);
        const next = if (self.map.get(k)) |cur| cur + 1 else @as(u64, 0);

        // Peek-then-mutate: tentatively put, flush, only confirm on success.
        // If the flush fails we revert the in-memory map so the caller can
        // retry without losing the prior index.
        const prior = self.map.get(k);
        self.map.put(k, next) catch return error.out_of_memory;
        self.flushToDisk() catch |err| {
            // Roll back the in-memory state.
            if (prior) |p| {
                self.map.put(k, p) catch {};
            } else {
                _ = self.map.remove(k);
            }
            return err;
        };
        return next;
    }

    fn vSnapshot(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) StoreError![]Record {
        const self: *FsStateStore = @ptrCast(@alignCast(ctx));
        var records = allocator.alloc(Record, self.map.count()) catch return error.out_of_memory;
        var it = self.map.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            var r: Record = undefined;
            @memcpy(&r.protocol_hash, entry.key_ptr.*[0..16]);
            @memcpy(&r.counterparty, entry.key_ptr.*[16..49]);
            r.current_index = entry.value_ptr.*;
            records[i] = r;
        }
        return records;
    }

    fn vReplay(
        ctx: *anyopaque,
        records: []const Record,
    ) StoreError!void {
        const self: *FsStateStore = @ptrCast(@alignCast(ctx));
        // Snapshot the prior map so we can roll back on flush failure.
        const prior_count = self.map.count();
        var prior = std.AutoHashMap(Key, u64).init(self.allocator);
        defer prior.deinit();
        if (prior_count > 0) {
            var it = self.map.iterator();
            while (it.next()) |entry| {
                prior.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
            }
        }

        self.map.clearRetainingCapacity();
        for (records) |r| {
            self.map.put(keyFor(&r.protocol_hash, &r.counterparty), r.current_index) catch return error.out_of_memory;
        }
        self.flushToDisk() catch |err| {
            // Roll back to the prior state.
            self.map.clearRetainingCapacity();
            var it = prior.iterator();
            while (it.next()) |entry| {
                self.map.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
            }
            return err;
        };
    }

    const fs_vtable: DerivationStateStore.VTable = .{
        .get_index = vGetIndex,
        .next_index = vNextIndex,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
