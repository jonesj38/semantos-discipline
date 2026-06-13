---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb_storage_adapter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.226272+00:00
---

# runtime/semantos-brain/src/lmdb_storage_adapter.zig

```zig
// DLO.3b.1 — LMDB-backed StorageAdapter implementation.
//
// Reference: docs/prd/D-LIFT-ODDJOBZ.md §Deliverables / DLO.3
//            (DECISION-3: cartridges consume StorageAdapter rather than
//            opening LMDB directly);
//            runtime/semantos-brain/src/storage_adapter.zig (the
//            vtable interface this module implements).
//
// ── What this module is ──────────────────────────────────────────────
//
// The concrete LMDB-backed `StorageAdapter` impl that brain-core will
// inject into refactored cartridge stores once DLO.3b.2 lands. Today
// this module is loaded-but-unwired: it exists as a substrate primitive
// that the jobs_store_lmdb (DLO.3b.2) + later store refactors
// (DLO.3c-g) consume. The cartridge code stays cartridge-agnostic;
// only brain-core knows about LMDB.
//
// ── Lifecycle ────────────────────────────────────────────────────────
//
// Caller:
//   1. Opens an LMDB Env (via lmdb.Env.open) — brain-core owns the env.
//   2. Inside an init transaction, opens a named DB (via lmdb.Txn.openDb)
//      with MDB_CREATE; commits.
//   3. Constructs LmdbStorageAdapter with (env, dbi).
//   4. Each read / write / list / etc. opens its own txn — short-lived,
//      no caller-managed transaction lifetime.
//   5. On shutdown, brain-core closes the env separately.
//
// The adapter does NOT own the env. Brain-core's existing LMDB env-
// management semantics are preserved verbatim.

const std = @import("std");
const lmdb = @import("lmdb");
const sa = @import("storage_adapter");

pub const LmdbStorageAdapter = struct {
    env: *lmdb.Env,
    dbi: lmdb.Dbi,

    /// Wrap an open Env + opened DBI handle. Both lifetimes are
    /// caller-owned — this adapter just holds references.
    pub fn init(env: *lmdb.Env, dbi: lmdb.Dbi) LmdbStorageAdapter {
        return .{ .env = env, .dbi = dbi };
    }

    pub fn adapter(self: *LmdbStorageAdapter) sa.StorageAdapter {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &lmdb_vtable,
        };
    }

    fn castSelf(ctx: *anyopaque) *LmdbStorageAdapter {
        return @ptrCast(@alignCast(ctx));
    }

    fn mapLmdbErr(err: anyerror) sa.StorageError {
        return switch (err) {
            error.OutOfMemory => sa.StorageError.OutOfMemory,
            // lmdb.LmdbError.lmdb_error covers MDB_NOTFOUND for get/del.
            // Callers detect not-found via vtable null returns, not via
            // raised errors — so a generic lmdb error maps to IoFailed.
            else => sa.StorageError.IoFailed,
        };
    }

    fn readImpl(ctx: *anyopaque, key: []const u8, allocator: std.mem.Allocator) sa.StorageError!?[]u8 {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_only) catch |err| return mapLmdbErr(err);
        defer txn.abort();

        // MDB_NOTFOUND surfaces as lmdb_error; treat as null per
        // StorageAdapter contract. The brain lmdb wrapper conflates
        // all LMDB error codes into error.lmdb_error, so we can't
        // distinguish NOTFOUND from corruption here — caller-facing
        // contract says read-missing-is-null, so return null and
        // let the periodic-fsck pick up any real corruption.
        const value = txn.get(self.dbi, key) catch return null;
        const dup = allocator.dupe(u8, value) catch return sa.StorageError.OutOfMemory;
        return dup;
    }

    fn writeImpl(ctx: *anyopaque, key: []const u8, data: []const u8) sa.StorageError!void {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_write) catch |err| return mapLmdbErr(err);
        errdefer txn.abort();
        txn.put(self.dbi, key, data, .{}) catch |err| return mapLmdbErr(err);
        txn.commit() catch |err| return mapLmdbErr(err);
    }

    fn existsImpl(ctx: *anyopaque, key: []const u8) sa.StorageError!bool {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_only) catch |err| return mapLmdbErr(err);
        defer txn.abort();
        _ = txn.get(self.dbi, key) catch return false;
        return true;
    }

    fn listImpl(ctx: *anyopaque, prefix: []const u8, allocator: std.mem.Allocator) sa.StorageError![][]u8 {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_only) catch |err| return mapLmdbErr(err);
        defer txn.abort();

        const cursor = txn.openCursor(self.dbi) catch |err| return mapLmdbErr(err);
        // The std stdcursor close is implicit via txn lifetime per LMDB
        // contract — readonly txns release cursor on abort/commit.

        var out = std.ArrayList([]u8).empty;
        errdefer {
            for (out.items) |k| allocator.free(k);
            out.deinit(allocator);
        }

        // Use lmdb.Cursor's getCurrent + advance-to-first via getNext-style.
        // The brain lmdb.zig Cursor only exposes getCurrent + we rely on
        // LMDB-internal advance via mdb_cursor_get (FIRST/NEXT). For
        // safe iteration without exposing the C API here, use the brain's
        // existing pattern: walk via repeated cursor positions.
        //
        // Brain's existing stores iterate by calling getCurrent after
        // positioning the cursor with mdb_cursor_get(FIRST/NEXT). Since
        // brain's lmdb.Cursor doesn't yet expose a public next() helper,
        // we use the c-API directly here. This matches the pattern in
        // header_store_lmdb.zig.
        var k: lmdb.c_types.MDB_val = undefined;
        var v: lmdb.c_types.MDB_val = undefined;
        var rc = lmdb.c_types.mdb_cursor_get(@ptrCast(cursor.ptr), &k, &v, lmdb.c_types.MDB_FIRST);
        while (rc == 0) : (rc = lmdb.c_types.mdb_cursor_get(@ptrCast(cursor.ptr), &k, &v, lmdb.c_types.MDB_NEXT)) {
            const key_slice = @as([*]const u8, @ptrCast(k.mv_data))[0..k.mv_size];
            if (prefix.len == 0 or std.mem.startsWith(u8, key_slice, prefix)) {
                const dup = allocator.dupe(u8, key_slice) catch return sa.StorageError.OutOfMemory;
                out.append(allocator, dup) catch return sa.StorageError.OutOfMemory;
            }
        }
        // rc == MDB_NOTFOUND (0xFFFFFFA1 in LMDB) is the loop-exit
        // condition; any other non-zero is an error.
        return out.toOwnedSlice(allocator) catch return sa.StorageError.OutOfMemory;
    }

    fn deleteImpl(ctx: *anyopaque, key: []const u8) sa.StorageError!bool {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_write) catch |err| return mapLmdbErr(err);
        errdefer txn.abort();
        // First check existence to return false-on-missing per
        // StorageAdapter contract; LMDB's del() raises on missing.
        _ = txn.get(self.dbi, key) catch {
            txn.abort();
            return false;
        };
        txn.del(self.dbi, key, null) catch |err| return mapLmdbErr(err);
        txn.commit() catch |err| return mapLmdbErr(err);
        return true;
    }

    fn statImpl(ctx: *anyopaque, key: []const u8) sa.StorageError!?sa.StorageStat {
        const self = castSelf(ctx);
        const txn = self.env.beginTxn(.read_only) catch |err| return mapLmdbErr(err);
        defer txn.abort();
        const value = txn.get(self.dbi, key) catch return null;

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(value);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        // LMDB doesn't track per-key modification time — record the
        // current wall-clock as "last read". This is best-effort; a
        // future enhancement could store a sidecar txnid → mtime map.
        // For now, downstream consumers should treat modified_at_ms as
        // "at-least-as-old-as" rather than authoritative.
        return sa.StorageStat{
            .size = value.len,
            .modified_at_ms = @intCast(std.time.milliTimestamp()),
            .content_hash = hash,
        };
    }
};

const lmdb_vtable: sa.VTable = .{
    .read = LmdbStorageAdapter.readImpl,
    .write = LmdbStorageAdapter.writeImpl,
    .exists = LmdbStorageAdapter.existsImpl,
    .list = LmdbStorageAdapter.listImpl,
    .delete = LmdbStorageAdapter.deleteImpl,
    .stat = LmdbStorageAdapter.statImpl,
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests — exercise the LMDB-backed impl against a tmpDir env.
// ─────────────────────────────────────────────────────────────────────

fn setupTestEnv(allocator: std.mem.Allocator) !struct {
    tmp_dir: std.testing.TmpDir,
    env: lmdb.Env,
    dbi: lmdb.Dbi,
} {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const env_path = try allocator.dupe(u8, tmp_path);
    defer allocator.free(env_path);

    var env = try lmdb.Env.open(env_path, .{
        .max_dbs = 8,
        .map_size = 64 * 1024 * 1024, // 64 MiB plenty for tests
        .open_flags = 0,
        .mode = 0o644,
    });
    errdefer env.close();

    // Open + create the named test DB inside a transaction; commit.
    var txn = try env.beginTxn(.read_write);
    errdefer txn.abort();
    const dbi = try txn.openDb("test_storage", .{ .flags = 0, .create = true });
    try txn.commit();

    return .{ .tmp_dir = tmp, .env = env, .dbi = dbi };
}

test "LmdbStorageAdapter: write + read round-trip" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try adapter.write("jobs/job-1", "payload-bytes");
    const got = try adapter.read("jobs/job-1", allocator) orelse return error.NotFound;
    defer allocator.free(got);
    try std.testing.expectEqualStrings("payload-bytes", got);
}

test "LmdbStorageAdapter: read returns null for missing key" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    const got = try adapter.read("nope", allocator);
    try std.testing.expect(got == null);
}

test "LmdbStorageAdapter: exists round-trip" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try std.testing.expect(!(try adapter.exists("k")));
    try adapter.write("k", "v");
    try std.testing.expect(try adapter.exists("k"));
}

test "LmdbStorageAdapter: list with prefix filters" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try adapter.write("jobs/a", "1");
    try adapter.write("jobs/b", "2");
    try adapter.write("quotes/c", "3");

    const got = try adapter.list("jobs/", allocator);
    defer {
        for (got) |k| allocator.free(k);
        allocator.free(got);
    }
    try std.testing.expectEqual(@as(usize, 2), got.len);
}

test "LmdbStorageAdapter: delete returns true on existing, false on missing" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try adapter.write("k", "v");
    try std.testing.expect(try adapter.delete("k"));
    try std.testing.expect(!(try adapter.delete("k")));
}

test "LmdbStorageAdapter: stat returns size + sha256" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try adapter.write("k", "hello");
    const st = try adapter.stat("k") orelse return error.NotFound;
    try std.testing.expectEqual(@as(u64, 5), st.size);

    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    try std.testing.expectEqualSlices(u8, &expected, &st.content_hash);
}

test "LmdbStorageAdapter: invalid key rejected at vtable boundary" {
    const allocator = std.testing.allocator;
    var setup = try setupTestEnv(allocator);
    defer {
        setup.env.close();
        setup.tmp_dir.cleanup();
    }

    var backend = LmdbStorageAdapter.init(&setup.env, setup.dbi);
    const adapter = backend.adapter();

    try std.testing.expectError(sa.StorageError.InvalidKey, adapter.read("", allocator));
    try std.testing.expectError(sa.StorageError.InvalidKey, adapter.write("", "v"));
}

```
