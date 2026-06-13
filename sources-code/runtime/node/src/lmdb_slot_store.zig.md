---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/lmdb_slot_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.303662+00:00
---

# runtime/node/src/lmdb_slot_store.zig

```zig
// Phase W6 — LmdbSlotStore: on-disk implementation of `core/cell-engine`'s
// `SlotStore` vtable for the sovereign-node daemon (design §10.2).
//
// Replaces the `LmdbSlotStore` stub at
// `core/cell-engine/src/slot_store.zig` (which is intentionally a 501-style
// `persistence_failed` stub so misuse is loud).
//
// ─── Backing store choice (v0.1) ──────────────────────────────────────
//
// The design doc §10.2 specifies "lmdb" as the backing for the sovereign
// node, but lmdb is a system C library that is non-trivial to vendor
// across darwin/linux toolchains and would force every developer to
// install it before `zig build` succeeds. Per the W6 task brief
// ("link `libmdbx` or `lmdb` via system C library; OR use a pure-Zig
//  kv-store … if simpler"), v0.1 uses a pure-Zig **directory-of-files**
// layout that satisfies the same persistence contract:
//
//     <data-dir>/slots/
//         <slot_id_lower_4_hex>.blob      ← AES-GCM ciphertext envelope
//         <slot_id_lower_4_hex>.blob.tmp  ← write-then-rename atomic
//
// One file per slot, written atomically via `O_TMPFILE`-style
// write-temp-then-rename. Since `SlotStore.put` already holds the
// canonical bytes (the cell envelope is single-blob — host.zig owns
// the layout), this gives us POSIX-rename atomicity without an LSM
// or write-ahead log.
//
// Swapping a real lmdb backend in v0.2 means substituting this file for
// a `mdb_env_open` + `mdb_put`/`mdb_get` impl behind the same vtable;
// callers (host.zig at-rest cell persistence) need not change.
//
// ─── Failure-atomicity ────────────────────────────────────────────────
//
// Per the engine-wide peek-then-mutate convention (`OP_SIGN`,
// `LocalSlotStore.vPut`), every mutating call must either fully succeed
// or leave the slot in its prior state. We achieve this by:
//   1. write to `<id>.blob.tmp`
//   2. fsync + rename to `<id>.blob`
//   3. only on success update the in-memory cache
//
// On `get`, the in-memory cache is filled lazily on first read and
// invalidated on `put`/`delete`. The store owns the cached bytes — same
// semantics as `LocalSlotStore`.

const std = @import("std");
const slot_store_mod = @import("slot_store");

pub const SlotStore = slot_store_mod.SlotStore;
pub const StoreError = slot_store_mod.StoreError;

pub const LmdbSlotStore = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to the slots subdirectory (e.g. `/var/lib/semantos/slots`).
    /// Owned heap allocation freed in `deinit`.
    dir_path: []u8,
    /// Cache of last-loaded blobs. Bytes are owned by the store. Cleared
    /// on `put`/`delete`/`deinit` exactly as `LocalSlotStore` does, so
    /// the `get` slice contract (valid until next mutation) holds.
    cache: std.AutoHashMap(u32, []u8),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !LmdbSlotStore {
        const subdir = try std.fs.path.join(allocator, &.{ data_dir, "slots" });
        // Best-effort mkdir -p — already-exists is fine.
        std.fs.cwd().makePath(subdir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        return .{
            .allocator = allocator,
            .dir_path = subdir,
            .cache = std.AutoHashMap(u32, []u8).init(allocator),
        };
    }

    pub fn deinit(self: *LmdbSlotStore) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| self.allocator.free(entry.value_ptr.*);
        self.cache.deinit();
        self.allocator.free(self.dir_path);
    }

    pub fn store(self: *LmdbSlotStore) SlotStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &lmdb_vtable,
        };
    }

    /// `<dir>/<8-hex-id>.blob` — fixed-width hex so a directory listing is
    /// stable order. Uses `std.fmt.bufPrint` with the caller-supplied buf.
    fn slotPath(self: *const LmdbSlotStore, slot_id: u32, buf: []u8) ![]u8 {
        return try std.fmt.bufPrint(buf, "{s}/{x:0>8}.blob", .{ self.dir_path, slot_id });
    }

    fn slotPathTmp(self: *const LmdbSlotStore, slot_id: u32, buf: []u8) ![]u8 {
        return try std.fmt.bufPrint(buf, "{s}/{x:0>8}.blob.tmp", .{ self.dir_path, slot_id });
    }

    fn vGet(ctx: *anyopaque, slot_id: u32) StoreError![]const u8 {
        const self: *LmdbSlotStore = @ptrCast(@alignCast(ctx));

        // Cache hit: return existing slice (valid until next mutation, per
        // SlotStore contract).
        if (self.cache.get(slot_id)) |cached| return cached;

        // Cache miss: read from disk.
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.not_found,
            else => return error.persistence_failed,
        };
        defer file.close();

        const stat = file.stat() catch return error.persistence_failed;
        // Sanity bound — a single slot blob is bounded by a 256-byte cell
        // header + a few KB of ciphertext. Hard-cap at 1 MiB to fail loud
        // on directory corruption.
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
        const self: *LmdbSlotStore = @ptrCast(@alignCast(ctx));

        // Peek-then-mutate: stage the new bytes on disk first; only then
        // invalidate the cache. If the rename fails the prior on-disk
        // blob (and the cached copy) are untouched.
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;
        const tmp_path = self.slotPathTmp(slot_id, &tmp_buf) catch return error.persistence_failed;

        // Write tmp file, fsync, rename. Truncate any leftover .tmp from
        // a prior aborted run.
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

        // Refresh the in-memory cache (drop old entry, do NOT install the
        // new bytes — let the next `get` re-read so the slice always
        // reflects on-disk state.)
        if (self.cache.fetchRemove(slot_id)) |kv| self.allocator.free(kv.value);
    }

    fn vDelete(ctx: *anyopaque, slot_id: u32) StoreError!void {
        const self: *LmdbSlotStore = @ptrCast(@alignCast(ctx));
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.slotPath(slot_id, &path_buf) catch return error.persistence_failed;
        std.fs.cwd().deleteFile(path) catch |err| switch (err) {
            error.FileNotFound => return error.not_found,
            else => return error.persistence_failed,
        };
        if (self.cache.fetchRemove(slot_id)) |kv| self.allocator.free(kv.value);
    }

    const lmdb_vtable: SlotStore.VTable = .{
        .get = vGet,
        .put = vPut,
        .delete = vDelete,
    };
};

```
