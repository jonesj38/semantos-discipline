---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_pask_snapshot_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.962867+00:00
---

# core/cell-engine/tests/lmdb_pask_snapshot_conformance.zig

```zig
// M1.11 — LmdbPaskSnapshotStore conformance tests.
//
// TDD specification for the LMDB-backed Pask kernel snapshot store.
//
// Tests:
//   M1.11-T1: commit + loadCurrent round-trip
//   M1.11-T2: commit two versions; loadCurrent returns second
//   M1.11-T3: rollbackTo first version; loadCurrent returns first; second gone
//   M1.11-T4: corrupt magic rejected at commit time
//   M1.11-T5: snapshotHistory returns correct metadata in reverse-version order
//   M1.11-T6: two different user_cert_ids are isolated
//
// Run: zig build test-lmdb-pask-snapshot

const std = @import("std");
const lmdb = @import("lmdb");
const pask_snapshot_store = @import("pask_snapshot_store");
const lmdb_pask_snapshot_store = @import("lmdb_pask_snapshot_store");

const LmdbPaskSnapshotStore = lmdb_pask_snapshot_store.LmdbPaskSnapshotStore;
const StoreError = pask_snapshot_store.PaskSnapshotStore.Error;

// ── Snapshot blob construction ────────────────────────────────────────────

const PASK_MAGIC: u32 = 0x4B534150;
const PASK_VER: u32 = 1;
const HEADER_SIZE: usize = 12;

/// Build a minimal valid Pask snapshot blob of `payload_size` Store bytes.
fn makeBlob(alloc: std.mem.Allocator, payload_size: usize) ![]u8 {
    const total = HEADER_SIZE + payload_size;
    const blob = try alloc.alloc(u8, total);
    std.mem.writeInt(u32, blob[0..4], PASK_MAGIC, .little);
    std.mem.writeInt(u32, blob[4..8], PASK_VER, .little);
    std.mem.writeInt(u32, blob[8..12], @intCast(payload_size), .little);
    // Fill payload with a recognizable byte pattern.
    for (blob[HEADER_SIZE..]) |*b| b.* = 0xAB;
    return blob;
}

/// Build a blob with a different payload byte so round-trip checks distinguish versions.
fn makeBlobTagged(alloc: std.mem.Allocator, payload_size: usize, tag: u8) ![]u8 {
    const blob = try makeBlob(alloc, payload_size);
    for (blob[HEADER_SIZE..]) |*b| b.* = tag;
    return blob;
}

/// Build a blob with a bad magic value.
fn makeBadBlob(alloc: std.mem.Allocator, payload_size: usize) ![]u8 {
    const blob = try makeBlob(alloc, payload_size);
    std.mem.writeInt(u32, blob[0..4], 0xDEADBEEF, .little); // wrong magic
    return blob;
}

// ── Temp dir helper ───────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-pask-snap-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

// ── M1.11-T1: commit + loadCurrent round-trip ────────────────────────────

test "M1.11-T1: commit then loadCurrent returns the blob" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    const blob = try makeBlob(alloc, 128);
    defer alloc.free(blob);

    const ver = try s.commitSnapshot("user-alice", blob);
    try std.testing.expectEqual(@as(u64, 1), ver);

    const loaded = try s.loadCurrent("user-alice", alloc);
    defer if (loaded) |b| alloc.free(b);

    try std.testing.expect(loaded != null);
    try std.testing.expectEqualSlices(u8, blob, loaded.?);
}

// ── M1.11-T2: second commit; loadCurrent returns newest ──────────────────

test "M1.11-T2: second commit; loadCurrent returns newest version" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    const blob1 = try makeBlobTagged(alloc, 64, 0x11);
    defer alloc.free(blob1);
    const blob2 = try makeBlobTagged(alloc, 64, 0x22);
    defer alloc.free(blob2);

    const ver1 = try s.commitSnapshot("user-bob", blob1);
    const ver2 = try s.commitSnapshot("user-bob", blob2);

    try std.testing.expectEqual(@as(u64, 1), ver1);
    try std.testing.expectEqual(@as(u64, 2), ver2);

    const loaded = try s.loadCurrent("user-bob", alloc);
    defer if (loaded) |b| alloc.free(b);

    try std.testing.expect(loaded != null);
    // The second blob's payload is all 0x22.
    try std.testing.expectEqual(@as(u8, 0x22), loaded.?[HEADER_SIZE]);
    try std.testing.expectEqualSlices(u8, blob2, loaded.?);
}

// ── M1.11-T3: rollbackTo; loadCurrent returns first; second deleted ───────

test "M1.11-T3: rollbackTo first version; second version is gone" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    const blob1 = try makeBlobTagged(alloc, 32, 0xAA);
    defer alloc.free(blob1);
    const blob2 = try makeBlobTagged(alloc, 32, 0xBB);
    defer alloc.free(blob2);

    const ver1 = try s.commitSnapshot("user-carol", blob1);
    _ = try s.commitSnapshot("user-carol", blob2);

    // Roll back to version 1.
    try s.rollbackTo("user-carol", ver1);

    // loadCurrent must return the v1 blob.
    const loaded = try s.loadCurrent("user-carol", alloc);
    defer if (loaded) |b| alloc.free(b);
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualSlices(u8, blob1, loaded.?);

    // snapshotHistory should show only one entry (version 1).
    const hist = try s.snapshotHistory("user-carol", 10, alloc);
    defer alloc.free(hist);
    try std.testing.expectEqual(@as(usize, 1), hist.len);
    try std.testing.expectEqual(@as(u64, 1), hist[0].version);
}

// ── M1.11-T4: corrupt magic rejected at commit time ───────────────────────

test "M1.11-T4: blob with bad magic is rejected by commitSnapshot" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    const bad_blob = try makeBadBlob(alloc, 64);
    defer alloc.free(bad_blob);

    const result = s.commitSnapshot("user-dave", bad_blob);
    try std.testing.expectError(error.corrupt_snapshot, result);

    // No snapshot should have been written.
    const loaded = try s.loadCurrent("user-dave", alloc);
    try std.testing.expect(loaded == null);
}

// ── M1.11-T5: snapshotHistory returns metadata in reverse-version order ───

test "M1.11-T5: snapshotHistory returns reverse-version-ordered metadata" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    // Commit 3 snapshots of increasing payload size for easy identification.
    const b1 = try makeBlob(alloc, 16);
    defer alloc.free(b1);
    const b2 = try makeBlob(alloc, 32);
    defer alloc.free(b2);
    const b3 = try makeBlob(alloc, 48);
    defer alloc.free(b3);

    _ = try s.commitSnapshot("user-erin", b1);
    _ = try s.commitSnapshot("user-erin", b2);
    _ = try s.commitSnapshot("user-erin", b3);

    // Request up to 10 — expect all 3 in descending version order.
    const hist = try s.snapshotHistory("user-erin", 10, alloc);
    defer alloc.free(hist);

    try std.testing.expectEqual(@as(usize, 3), hist.len);

    // Versions should be 3, 2, 1.
    try std.testing.expectEqual(@as(u64, 3), hist[0].version);
    try std.testing.expectEqual(@as(u64, 2), hist[1].version);
    try std.testing.expectEqual(@as(u64, 1), hist[2].version);

    // Sizes should reflect HEADER_SIZE + payload sizes.
    try std.testing.expectEqual(@as(usize, HEADER_SIZE + 48), hist[0].size);
    try std.testing.expectEqual(@as(usize, HEADER_SIZE + 32), hist[1].size);
    try std.testing.expectEqual(@as(usize, HEADER_SIZE + 16), hist[2].size);

    // All magic should be valid.
    try std.testing.expect(hist[0].magic_ok);
    try std.testing.expect(hist[1].magic_ok);
    try std.testing.expect(hist[2].magic_ok);

    // Respect the limit parameter.
    const hist2 = try s.snapshotHistory("user-erin", 2, alloc);
    defer alloc.free(hist2);
    try std.testing.expectEqual(@as(usize, 2), hist2.len);
    try std.testing.expectEqual(@as(u64, 3), hist2[0].version);
    try std.testing.expectEqual(@as(u64, 2), hist2[1].version);
}

// ── M1.11-T6: two users are isolated ─────────────────────────────────────

test "M1.11-T6: snapshots for different cert_ids do not interfere" {
    const alloc = std.testing.allocator;

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try LmdbPaskSnapshotStore.init(&env, alloc);
    defer impl.deinit();
    const s = impl.store();

    const bA = try makeBlobTagged(alloc, 32, 0xAA);
    defer alloc.free(bA);
    const bB = try makeBlobTagged(alloc, 32, 0xBB);
    defer alloc.free(bB);

    const verA = try s.commitSnapshot("user-alpha", bA);
    const verB = try s.commitSnapshot("user-beta", bB);

    // Both start at version 1 (independent counters).
    try std.testing.expectEqual(@as(u64, 1), verA);
    try std.testing.expectEqual(@as(u64, 1), verB);

    // loadCurrent for alpha returns alpha's blob.
    const la = try s.loadCurrent("user-alpha", alloc);
    defer if (la) |b| alloc.free(b);
    try std.testing.expect(la != null);
    try std.testing.expectEqual(@as(u8, 0xAA), la.?[HEADER_SIZE]);

    // loadCurrent for beta returns beta's blob.
    const lb = try s.loadCurrent("user-beta", alloc);
    defer if (lb) |b| alloc.free(b);
    try std.testing.expect(lb != null);
    try std.testing.expectEqual(@as(u8, 0xBB), lb.?[HEADER_SIZE]);

    // snapshotHistory for alpha shows only 1 entry.
    const hA = try s.snapshotHistory("user-alpha", 10, alloc);
    defer alloc.free(hA);
    try std.testing.expectEqual(@as(usize, 1), hA.len);

    // snapshotHistory for beta shows only 1 entry.
    const hB = try s.snapshotHistory("user-beta", 10, alloc);
    defer alloc.free(hB);
    try std.testing.expectEqual(@as(usize, 1), hB.len);

    // Committing a second snapshot for alpha does not affect beta.
    const bA2 = try makeBlobTagged(alloc, 32, 0xCC);
    defer alloc.free(bA2);
    _ = try s.commitSnapshot("user-alpha", bA2);

    const lb2 = try s.loadCurrent("user-beta", alloc);
    defer if (lb2) |b| alloc.free(b);
    try std.testing.expect(lb2 != null);
    // Beta's current is still the original 0xBB blob.
    try std.testing.expectEqual(@as(u8, 0xBB), lb2.?[HEADER_SIZE]);
}

```
