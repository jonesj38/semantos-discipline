---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pask_snapshot_serve_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.195842+00:00
---

# runtime/semantos-brain/tests/pask_snapshot_serve_conformance.zig

```zig
// W0.5 — Conformance suite for LmdbPaskSnapshotStore serve-wiring contract.
//
// These tests validate the lifecycle behaviours that `cmdServe` must implement
// when wiring LmdbPaskSnapshotStore into the boot/shutdown/FSM-transition
// sequence:
//
//   W0.5-T-store-init-on-boot
//       LmdbPaskSnapshotStore.init succeeds when an LMDB env is open.
//       Analogous to "store is created on boot when LMDB backend is active".
//
//   W0.5-T-load-current-null-first-boot
//       loadCurrent returns null for a cert_id that has no prior snapshot.
//       cmdServe must call this on boot and skip restore when null is returned.
//
//   W0.5-T-commit-snapshot-on-shutdown
//       commitSnapshot succeeds and returns a monotonically-increasing version.
//       cmdServe calls this on shutdown (deferred) with the current Pask blob.
//
//   W0.5-T-commit-snapshot-on-fsm-transition
//       A second commitSnapshot (simulating an FSM transition) increments the
//       version.  cmdServe must call commitSnapshot after each confirmed FSM
//       transition.
//
//   W0.5-T-load-restores-after-shutdown
//       After a commitSnapshot, loadCurrent returns the same blob.
//       This verifies the boot-restore path finds the committed state.
//
// Run: zig build test-pask-snapshot-serve-conformance

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_config = @import("lmdb_config");
const pask_snapshot_store_lmdb = @import("pask_snapshot_store_lmdb");
const LmdbPaskSnapshotStore = pask_snapshot_store_lmdb.LmdbPaskSnapshotStore;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn openEnv(tmp_dir: std.testing.TmpDir, allocator: std.mem.Allocator) !lmdb.Env {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp_dir.dir.realpath(".", &path_buf);
    const lmdb_path = try std.fs.path.join(allocator, &.{ dir_path, "lmdb" });
    defer allocator.free(lmdb_path);
    std.fs.makeDirAbsolute(lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    return lmdb.Env.open(lmdb_path, .{
        .map_size = lmdb_config.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config.LmdbConfig.default.max_dbs,
        .open_flags = lmdb_config.LmdbConfig.ci_flags,
        .mode = lmdb_config.LmdbConfig.default.mode,
    });
}

/// Build a minimal valid PASK blob (12-byte header + payload).
/// Header format (LE):
///   [00..04]  magic   = 0x4B534150 ("PASK")
///   [04..08]  version = 1
///   [08..12]  length  = payload_len
fn makePaskBlob(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const blob = try allocator.alloc(u8, 12 + payload.len);
    std.mem.writeInt(u32, blob[0..4], 0x4B534150, .little);
    std.mem.writeInt(u32, blob[4..8], 1, .little);
    std.mem.writeInt(u32, blob[8..12], @as(u32, @intCast(payload.len)), .little);
    @memcpy(blob[12..], payload);
    return blob;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "W0.5-T-store-init-on-boot" {
    // LmdbPaskSnapshotStore.init must succeed when an LMDB env is already open.
    // This corresponds to the serve-boot path: after lmdb_env is opened and
    // lmdb_backend_active is set to true, cmdServe constructs the store.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    // Init must not error.
    const store = try LmdbPaskSnapshotStore.init(&env, allocator);
    _ = store; // cmdServe keeps the store alive until shutdown.
}

test "W0.5-T-load-current-null-first-boot" {
    // On first boot there is no prior snapshot for a cert_id.
    // loadCurrent must return null — cmdServe skips Pask state restore.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try LmdbPaskSnapshotStore.init(&env, allocator);
    const vtable = store.store();

    const cert_id = "test-cert-0000000000000001";
    const blob_opt = try vtable.loadCurrent(cert_id, allocator);

    // No snapshot exists yet — must return null, not an error.
    try std.testing.expect(blob_opt == null);
}

test "W0.5-T-commit-snapshot-on-shutdown" {
    // On shutdown cmdServe calls commitSnapshot with the current Pask state.
    // The call must succeed and return version 1 (first snapshot for this cert).
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try LmdbPaskSnapshotStore.init(&env, allocator);
    const vtable = store.store();

    const cert_id = "test-cert-shutdown-001";

    // Build a valid PASK blob (stub: 4-byte payload).
    const blob = try makePaskBlob(allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    defer allocator.free(blob);

    const version = try vtable.commitSnapshot(cert_id, blob);
    // First commit for this cert_id must yield version 1.
    try std.testing.expectEqual(@as(u64, 1), version);
}

test "W0.5-T-commit-snapshot-on-fsm-transition" {
    // On each confirmed FSM transition cmdServe commits a new snapshot.
    // The second commit must yield version 2 (monotonically increasing).
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try LmdbPaskSnapshotStore.init(&env, allocator);
    const vtable = store.store();

    const cert_id = "test-cert-fsm-001";

    const blob = try makePaskBlob(allocator, &[_]u8{ 0x01, 0x02, 0x03, 0x04 });
    defer allocator.free(blob);

    // Boot commit (shutdown / first-write path).
    const v1 = try vtable.commitSnapshot(cert_id, blob);
    try std.testing.expectEqual(@as(u64, 1), v1);

    // FSM transition commit.
    const blob2 = try makePaskBlob(allocator, &[_]u8{ 0x05, 0x06, 0x07, 0x08 });
    defer allocator.free(blob2);

    const v2 = try vtable.commitSnapshot(cert_id, blob2);
    try std.testing.expectEqual(@as(u64, 2), v2);
}

test "W0.5-T-load-restores-after-shutdown" {
    // After commitSnapshot, loadCurrent must return the same blob bytes.
    // This validates the boot-restore path: brain restarts and loads the state
    // that was committed on the previous shutdown.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try LmdbPaskSnapshotStore.init(&env, allocator);
    const vtable = store.store();

    const cert_id = "test-cert-restore-001";

    // A blob with a recognisable payload pattern.
    const payload: []const u8 = "pask-state-restore-roundtrip";
    const blob = try makePaskBlob(allocator, payload);
    defer allocator.free(blob);

    _ = try vtable.commitSnapshot(cert_id, blob);

    // "Reboot": loadCurrent must return the committed blob.
    const loaded_opt = try vtable.loadCurrent(cert_id, allocator);
    try std.testing.expect(loaded_opt != null);
    const loaded = loaded_opt.?;
    defer allocator.free(loaded);

    // Full byte equality.
    try std.testing.expectEqualSlices(u8, blob, loaded);
}

```
