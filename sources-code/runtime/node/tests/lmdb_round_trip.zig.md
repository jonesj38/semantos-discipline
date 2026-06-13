---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/tests/lmdb_round_trip.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.300324+00:00
---

# runtime/node/tests/lmdb_round_trip.zig

```zig
// Phase W6 — `LmdbStateStore` + `LmdbSlotStore` round-trip tests.
//
// Acceptance criterion 4: "Restarting the daemon preserves state (lmdb
// persistence works end-to-end)." We exercise both stores by:
//   1. open store-A in a fresh tmp dir
//   2. write some keys/blobs
//   3. drop store-A (close, deinit)
//   4. open store-B against the same dir
//   5. read back exactly what was written

const std = @import("std");
const slot_store = @import("slot_store");
const derivation_state = @import("derivation_state");
const lmdb_slot = @import("lmdb_slot_store");
const lmdb_state = @import("lmdb_state_store");

fn makeTmpDir(allocator: std.mem.Allocator) ![]u8 {
    const ts = std.time.nanoTimestamp();
    const tmp_root = std.posix.getenv("TMPDIR") orelse "/tmp";
    const path = try std.fmt.allocPrint(
        allocator,
        "{s}/semantos-node-test-{d}-{d}",
        .{ tmp_root, ts, std.crypto.random.int(u32) },
    );
    try std.fs.cwd().makePath(path);
    return path;
}

test "LmdbSlotStore: put then reopen → get returns same bytes" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    const blob_a = "ciphertext-blob-A-padding-padding-padding";
    const blob_b = [_]u8{0xAB} ** 64;

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        const iface = s.store();
        try iface.put(7, blob_a);
        try iface.put(42, &blob_b);
    }

    // Re-open. Same dir, fresh in-memory cache.
    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    const iface2 = s2.store();

    const got_a = try iface2.get(7);
    try std.testing.expectEqualSlices(u8, blob_a, got_a);

    const got_b = try iface2.get(42);
    try std.testing.expectEqualSlices(u8, &blob_b, got_b);

    // Missing slot → not_found.
    try std.testing.expectError(error.not_found, iface2.get(999));

    // Delete, then re-open: the slot stays gone.
    try iface2.delete(7);
    try std.testing.expectError(error.not_found, iface2.get(7));

    var s3 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s3.deinit();
    const iface3 = s3.store();
    try std.testing.expectError(error.not_found, iface3.get(7));
    const still_b = try iface3.get(42);
    try std.testing.expectEqualSlices(u8, &blob_b, still_b);
}

test "LmdbSlotStore: overwrite same slot updates on disk" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        const iface = s.store();
        try iface.put(1, "first");
        try iface.put(1, "second-payload-longer");
    }

    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    const got = try s2.store().get(1);
    try std.testing.expectEqualSlices(u8, "second-payload-longer", got);
}

test "LmdbStateStore: nextIndex monotonic across reopen" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    var ph: [16]u8 = [_]u8{0xAB} ** 16;
    var cp: [33]u8 = [_]u8{0x02} ** 33;

    {
        var s = try lmdb_state.LmdbStateStore.init(allocator, dir);
        defer s.deinit();
        const iface = s.store();
        try std.testing.expect(iface.getIndex(&ph, &cp) == null);
        const first = try iface.nextIndex(&ph, &cp);
        try std.testing.expectEqual(@as(u64, 0), first);
        const second = try iface.nextIndex(&ph, &cp);
        try std.testing.expectEqual(@as(u64, 1), second);
    }

    // Reopen. Counter must continue from 1 (last allocated), so next
    // nextIndex returns 2 — never 0 (would re-use derivation indices).
    var s2 = try lmdb_state.LmdbStateStore.init(allocator, dir);
    defer s2.deinit();
    const iface2 = s2.store();
    try std.testing.expectEqual(@as(u64, 1), iface2.getIndex(&ph, &cp).?);
    const after_reopen = try iface2.nextIndex(&ph, &cp);
    try std.testing.expectEqual(@as(u64, 2), after_reopen);
}

test "LmdbStateStore: snapshot + replay round-trip" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    var s = try lmdb_state.LmdbStateStore.init(allocator, dir);
    defer s.deinit();
    const iface = s.store();

    var ph1: [16]u8 = [_]u8{0x01} ** 16;
    var cp1: [33]u8 = [_]u8{0x02} ** 33;
    var ph2: [16]u8 = [_]u8{0x03} ** 16;
    var cp2: [33]u8 = [_]u8{0x04} ** 33;

    _ = try iface.nextIndex(&ph1, &cp1);
    _ = try iface.nextIndex(&ph1, &cp1);
    _ = try iface.nextIndex(&ph2, &cp2);

    const snap = try iface.snapshot(allocator);
    defer allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 2), snap.len);

    // Replay onto a fresh dir.
    const dir2 = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir2) catch {};
        allocator.free(dir2);
    }
    var s2 = try lmdb_state.LmdbStateStore.init(allocator, dir2);
    defer s2.deinit();
    try s2.store().replay(snap);

    // Reopen dir2 → records are still present.
    var s3 = try lmdb_state.LmdbStateStore.init(allocator, dir2);
    defer s3.deinit();
    try std.testing.expectEqual(@as(u64, 1), s3.store().getIndex(&ph1, &cp1).?);
    try std.testing.expectEqual(@as(u64, 0), s3.store().getIndex(&ph2, &cp2).?);
}

```
