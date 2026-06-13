---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/pask_snapshot_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.281227+00:00
---

# runtime/semantos-brain/src/lmdb/pask_snapshot_store.zig

```zig
// M1.11 — PaskSnapshotStore vtable interface.
//
// Defines the abstract vtable for persisting Pask kernel snapshots.
// The concrete implementation is LmdbPaskSnapshotStore in
// pask_snapshot_store_lmdb.zig.
//
// Snapshot blob format (from core/pask/src/main.zig):
//   [00..04]  magic   = 0x4B534150 ("PASK") little-endian
//   [04..08]  version = 1           little-endian
//   [08..12]  length  = sizeof(Store) little-endian
//   [12..12+length]  Store image

const std = @import("std");

pub const PaskSnapshotStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Load the blob for the current (latest) snapshot for this user.
        /// Caller owns the returned slice; free with the supplied allocator.
        /// Returns null when no snapshot exists for the user.
        loadCurrent: *const fn (ptr: *anyopaque, user_cert_id: []const u8, allocator: std.mem.Allocator) Error!?[]u8,

        /// Validate and persist a new snapshot blob.
        /// Returns the new snapshot_version (monotonically increasing).
        commitSnapshot: *const fn (ptr: *anyopaque, user_cert_id: []const u8, blob: []const u8) Error!u64,

        /// Delete all versions > `version`; update current pointer to `version`.
        rollbackTo: *const fn (ptr: *anyopaque, user_cert_id: []const u8, version: u64) Error!void,

        /// Return metadata for the most recent `limit` snapshots in reverse
        /// version order.  Caller owns the returned slice; free with allocator.
        snapshotHistory: *const fn (ptr: *anyopaque, user_cert_id: []const u8, limit: u32, allocator: std.mem.Allocator) Error![]SnapshotMeta,

        /// Release any resources held by the implementation.
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub const SnapshotMeta = struct {
        version: u64,
        size: usize,
        magic_ok: bool,
    };

    pub const Error = error{
        not_found,
        corrupt_snapshot,
        lmdb_error,
        out_of_memory,
    };

    // ── Convenience dispatch helpers ──────────────────────────────────────

    pub fn loadCurrent(
        self: PaskSnapshotStore,
        user_cert_id: []const u8,
        allocator: std.mem.Allocator,
    ) Error!?[]u8 {
        return self.vtable.loadCurrent(self.ptr, user_cert_id, allocator);
    }

    pub fn commitSnapshot(
        self: PaskSnapshotStore,
        user_cert_id: []const u8,
        blob: []const u8,
    ) Error!u64 {
        return self.vtable.commitSnapshot(self.ptr, user_cert_id, blob);
    }

    pub fn rollbackTo(
        self: PaskSnapshotStore,
        user_cert_id: []const u8,
        version: u64,
    ) Error!void {
        return self.vtable.rollbackTo(self.ptr, user_cert_id, version);
    }

    pub fn snapshotHistory(
        self: PaskSnapshotStore,
        user_cert_id: []const u8,
        limit: u32,
        allocator: std.mem.Allocator,
    ) Error![]SnapshotMeta {
        return self.vtable.snapshotHistory(self.ptr, user_cert_id, limit, allocator);
    }

    pub fn deinit(self: PaskSnapshotStore) void {
        self.vtable.deinit(self.ptr);
    }
};

```
