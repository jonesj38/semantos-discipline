---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/lmdb_state_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.301485+00:00
---

# runtime/node/src/lmdb_state_store.zig

```zig
// Phase W6 — LmdbStateStore: on-disk implementation of `core/cell-engine`'s
// `DerivationStateStore` vtable for the sovereign-node daemon (design §10.2,
// §3.5.2 / §6.4 — BRC-42 fresh-key-per-tx index allocator).
//
// ─── Backing store choice (v0.1) ──────────────────────────────────────
//
// Same rationale as `lmdb_slot_store.zig` — pure-Zig, single binary,
// no system C dep. Layout:
//
//     <data-dir>/state.bin
//     <data-dir>/state.bin.tmp (atomic rewrite scratch)
//
// Format (binary, little-endian):
//     magic:        "SEMSTATE"  (8 bytes)
//     version:      u32         (= 1)
//     reserved:     u32         (= 0)
//     record_count: u32
//     records:      record_count × Record
//   where each Record is the same 57-byte layout as
//   `derivation_state.zig`:
//     protocol_hash:  16 bytes
//     counterparty:   33 bytes
//     current_index:   8 bytes (u64 LE)
//
// On every `next_index` we rewrite the whole file — this is
// O(records-in-store), which for a typical wallet is at most a few
// hundred contexts. A real lmdb backend in v0.2 will do per-key
// updates; the v0.1 file rewrite trades throughput for simplicity
// while keeping the on-disk format stable.
//
// ─── Failure-atomicity ────────────────────────────────────────────────
//
// `nextIndex` MUST guarantee that "the returned value is never returned
// again for the same context" (per `DerivationStateStore.VTable`
// contract — re-using an index would leak two transactions worth of
// derivation under the same public key, a privacy + security bug).
//
// We implement this by:
//   1. peek the in-memory map for the current value
//   2. write `current+1` to disk via tmp-then-rename
//   3. only on rename success update the in-memory map
//
// If step 2 fails the caller sees `persistence_failed` and the index
// is *not* consumed — same semantics as `OP_SIGN`'s peek-then-mutate.

const std = @import("std");
const derivation_state_mod = @import("derivation_state");

pub const DerivationStateStore = derivation_state_mod.DerivationStateStore;
pub const Record = derivation_state_mod.Record;
pub const StoreError = derivation_state_mod.StoreError;

const MAGIC = "SEMSTATE";
const FORMAT_VERSION: u32 = 1;
const FILE_HEADER_BYTES: usize = 8 + 4 + 4 + 4; // magic + version + reserved + record_count
const RECORD_BYTES: usize = 16 + 33 + 8; // = 57

pub const LmdbStateStore = struct {
    allocator: std.mem.Allocator,
    /// Heap-allocated copy of `<data-dir>/state.bin`.
    file_path: []u8,
    tmp_path: []u8,
    /// In-memory mirror of the on-disk records. Filled at `init` from the
    /// existing file (if any), kept in lock-step with the file by every
    /// mutating op.
    map: std.AutoHashMap(Key, u64),

    const Key = [16 + 33]u8;

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !LmdbStateStore {
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const file_path = try std.fs.path.join(allocator, &.{ data_dir, "state.bin" });
        errdefer allocator.free(file_path);
        const tmp_path = try std.fs.path.join(allocator, &.{ data_dir, "state.bin.tmp" });
        errdefer allocator.free(tmp_path);

        var self: LmdbStateStore = .{
            .allocator = allocator,
            .file_path = file_path,
            .tmp_path = tmp_path,
            .map = std.AutoHashMap(Key, u64).init(allocator),
        };
        errdefer self.map.deinit();

        // Best-effort load. A missing file is fine (fresh install).
        self.loadFromDisk() catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        return self;
    }

    pub fn deinit(self: *LmdbStateStore) void {
        self.map.deinit();
        self.allocator.free(self.file_path);
        self.allocator.free(self.tmp_path);
    }

    pub fn store(self: *LmdbStateStore) DerivationStateStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &lmdb_vtable,
        };
    }

    fn keyFor(protocol_hash: *const [16]u8, counterparty: *const [33]u8) Key {
        var k: Key = undefined;
        @memcpy(k[0..16], protocol_hash);
        @memcpy(k[16..49], counterparty);
        return k;
    }

    /// Read state.bin into the in-memory map. Caller has set `self.map`
    /// to an empty AutoHashMap. Returns `error.FileNotFound` if the file
    /// is absent (fresh install) — the init wrapper swallows that.
    fn loadFromDisk(self: *LmdbStateStore) !void {
        const file = try std.fs.cwd().openFile(self.file_path, .{});
        defer file.close();

        const stat = try file.stat();
        if (stat.size < FILE_HEADER_BYTES) return error.InvalidStateFile;
        if (stat.size > 64 * 1024 * 1024) return error.InvalidStateFile; // sanity cap

        const buf = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(buf);

        var read_total: usize = 0;
        while (read_total < buf.len) {
            const n = try file.read(buf[read_total..]);
            if (n == 0) break;
            read_total += n;
        }
        if (read_total != buf.len) return error.InvalidStateFile;

        if (!std.mem.eql(u8, buf[0..8], MAGIC)) return error.InvalidStateFile;
        const version = std.mem.readInt(u32, buf[8..12], .little);
        if (version != FORMAT_VERSION) return error.InvalidStateFile;
        const count = std.mem.readInt(u32, buf[16..20], .little);

        const required = FILE_HEADER_BYTES + @as(usize, count) * RECORD_BYTES;
        if (required != buf.len) return error.InvalidStateFile;

        var off: usize = FILE_HEADER_BYTES;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            var k: Key = undefined;
            @memcpy(&k, buf[off .. off + 49]);
            off += 49;
            const idx = std.mem.readInt(u64, buf[off..][0..8], .little);
            off += 8;
            try self.map.put(k, idx);
        }
    }

    /// Serialize the entire map and rewrite state.bin atomically.
    fn flushToDisk(self: *LmdbStateStore) StoreError!void {
        const count: u32 = @intCast(self.map.count());
        const total = FILE_HEADER_BYTES + @as(usize, count) * RECORD_BYTES;

        const buf = self.allocator.alloc(u8, total) catch return error.out_of_memory;
        defer self.allocator.free(buf);

        @memcpy(buf[0..8], MAGIC);
        std.mem.writeInt(u32, buf[8..12], FORMAT_VERSION, .little);
        std.mem.writeInt(u32, buf[12..16], 0, .little);
        std.mem.writeInt(u32, buf[16..20], count, .little);

        var off: usize = FILE_HEADER_BYTES;
        var it = self.map.iterator();
        while (it.next()) |entry| {
            @memcpy(buf[off .. off + 49], entry.key_ptr);
            off += 49;
            std.mem.writeInt(u64, buf[off..][0..8], entry.value_ptr.*, .little);
            off += 8;
        }

        // tmp-then-rename, fsync the tmp before rename for crash safety.
        const tmp = std.fs.cwd().createFile(self.tmp_path, .{ .truncate = true }) catch return error.persistence_failed;
        var ok = false;
        defer if (!ok) {
            std.fs.cwd().deleteFile(self.tmp_path) catch {};
        };
        {
            var written: usize = 0;
            while (written < buf.len) {
                const n = tmp.write(buf[written..]) catch {
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
        std.fs.cwd().rename(self.tmp_path, self.file_path) catch return error.persistence_failed;
        ok = true;
    }

    fn vGetIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        const self: *LmdbStateStore = @ptrCast(@alignCast(ctx));
        return self.map.get(keyFor(protocol_hash, counterparty));
    }

    fn vNextIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const self: *LmdbStateStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(protocol_hash, counterparty);
        const next = if (self.map.get(k)) |cur| cur + 1 else @as(u64, 0);

        // Peek-then-mutate: stage the new value in the map first, attempt
        // the disk write; on disk failure, restore the prior map state.
        const prior = self.map.get(k);
        self.map.put(k, next) catch return error.out_of_memory;
        self.flushToDisk() catch |err| {
            // Roll back the in-memory mutation so the caller sees a
            // consistent view (failed → no index consumed).
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
        const self: *LmdbStateStore = @ptrCast(@alignCast(ctx));
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
        const self: *LmdbStateStore = @ptrCast(@alignCast(ctx));

        // Snapshot the prior state so we can roll back on flush failure.
        var backup = std.AutoHashMap(Key, u64).init(self.allocator);
        defer backup.deinit();
        var it = self.map.iterator();
        while (it.next()) |entry| {
            backup.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.out_of_memory;
        }

        self.map.clearRetainingCapacity();
        for (records) |r| {
            self.map.put(keyFor(&r.protocol_hash, &r.counterparty), r.current_index) catch {
                // Restore prior state on partial failure.
                self.map.clearRetainingCapacity();
                var bit = backup.iterator();
                while (bit.next()) |e| {
                    self.map.put(e.key_ptr.*, e.value_ptr.*) catch {};
                }
                return error.out_of_memory;
            };
        }

        self.flushToDisk() catch |err| {
            self.map.clearRetainingCapacity();
            var bit = backup.iterator();
            while (bit.next()) |e| {
                self.map.put(e.key_ptr.*, e.value_ptr.*) catch {};
            }
            return err;
        };
    }

    const lmdb_vtable: DerivationStateStore.VTable = .{
        .get_index = vGetIndex,
        .next_index = vNextIndex,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
