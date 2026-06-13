---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/drift_detector_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.958961+00:00
---

# core/cell-engine/tests/drift_detector_conformance.zig

```zig
// M6.5 — DriftDetector conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the contract for drift-detection between the LMDB
// registry cache and the canonical Postgres snapshot.
//
// Test IDs:
//   M6.5-T-no-drift              — 3 entries, all match snapshot → drifted=0
//   M6.5-T-hash-mismatch         — 1 entry has wrong content_hash → drifted=1
//   M6.5-T-extra-lmdb            — LMDB entry absent from snapshot → drifted=1
//   M6.5-T-quarantine            — after applyQuarantine, re-fetch → state=3
//   M6.5-T-clean-after-quarantine — after applyQuarantine, cache_version incremented
//
// Run: zig build test-drift-detector

const std = @import("std");
const lmdb = @import("lmdb");
const registry_cache = @import("registry_cache");
const registry_cache_lmdb = @import("registry_cache_lmdb");
const drift_detector = @import("drift_detector");

const DriftDetector = drift_detector.DriftDetector;
const CanonicalEntry = drift_detector.CanonicalEntry;

// ── Helpers ───────────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [80]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/drift-detector-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

/// Build a [32]u8 filled with `byte`.
fn hash32(byte: u8) [32]u8 {
    var h: [32]u8 = undefined;
    @memset(&h, byte);
    return h;
}

/// Build a RegistryCacheEntry with controlled cell_id/domain_flag/content_hash.
fn makeEntry(
    cell_id_byte: u8,
    domain_flag: u32,
    content_hash_byte: u8,
    cache_version: u64,
) registry_cache.RegistryCacheEntry {
    return .{
        .cell_id = hash32(cell_id_byte),
        .domain_flag = domain_flag,
        .octave_level = 0,
        .content_hash = hash32(content_hash_byte),
        .linearity_type = 0,
        .state = 0, // unspent
        .cache_version = cache_version,
        .registered_at_ms = 1_700_000_000_000,
    };
}

/// Build a CanonicalEntry with controlled fields.
fn makeCanon(
    cell_id_byte: u8,
    domain_flag: u32,
    content_hash_byte: u8,
) CanonicalEntry {
    return .{
        .cell_id = hash32(cell_id_byte),
        .domain_flag = domain_flag,
        .content_hash = hash32(content_hash_byte),
    };
}

// ── M6.5-T-no-drift ──────────────────────────────────────────────────────

test "M6.5-T-no-drift: all 3 entries match snapshot → drifted=0" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    // Put 3 entries (cell_id_byte=1,2,3; domain_flag=0; content_hash matches canon).
    try store.put(makeEntry(0x01, 0, 0xA1, 1));
    try store.put(makeEntry(0x02, 0, 0xA2, 2));
    try store.put(makeEntry(0x03, 0, 0xA3, 3));

    // Snapshot mirrors all 3 with matching hashes (sorted by cell_id then domain_flag).
    const snapshot = [_]CanonicalEntry{
        makeCanon(0x01, 0, 0xA1),
        makeCanon(0x02, 0, 0xA2),
        makeCanon(0x03, 0, 0xA3),
    };

    var detector = DriftDetector{ .store = store };
    const report = try detector.runWalk(allocator, &snapshot);
    defer drift_detector.deinit(report, allocator);

    try std.testing.expectEqual(@as(u32, 3), report.total_scanned);
    try std.testing.expectEqual(@as(u32, 0), report.drifted);
    try std.testing.expectEqual(@as(u32, 0), report.errors);
    try std.testing.expectEqual(@as(usize, 0), report.drift_entries.len);
}

// ── M6.5-T-hash-mismatch ─────────────────────────────────────────────────

test "M6.5-T-hash-mismatch: one entry has wrong content_hash → drifted=1" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    // Entry 2 has content_hash_byte=0xFF in LMDB but 0xA2 in the snapshot.
    try store.put(makeEntry(0x01, 0, 0xA1, 1));
    try store.put(makeEntry(0x02, 0, 0xFF, 2)); // <- drifted
    try store.put(makeEntry(0x03, 0, 0xA3, 3));

    const snapshot = [_]CanonicalEntry{
        makeCanon(0x01, 0, 0xA1),
        makeCanon(0x02, 0, 0xA2), // canon says 0xA2
        makeCanon(0x03, 0, 0xA3),
    };

    var detector = DriftDetector{ .store = store };
    const report = try detector.runWalk(allocator, &snapshot);
    defer drift_detector.deinit(report, allocator);

    try std.testing.expectEqual(@as(u32, 3), report.total_scanned);
    try std.testing.expectEqual(@as(u32, 1), report.drifted);
    try std.testing.expectEqual(@as(usize, 1), report.drift_entries.len);

    const de = report.drift_entries[0];
    try std.testing.expectEqualSlices(u8, &hash32(0x02), &de.cell_id);
    try std.testing.expectEqual(@as(u32, 0), de.domain_flag);
    try std.testing.expectEqualSlices(u8, &hash32(0xFF), &de.lmdb_hash);
    try std.testing.expectEqualSlices(u8, &hash32(0xA2), &de.canon_hash);
}

// ── M6.5-T-extra-lmdb ────────────────────────────────────────────────────

test "M6.5-T-extra-lmdb: LMDB has entry absent from snapshot → drifted=1" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    // 3 LMDB entries; snapshot only knows about 2.
    try store.put(makeEntry(0x01, 0, 0xA1, 1));
    try store.put(makeEntry(0x02, 0, 0xA2, 2));
    try store.put(makeEntry(0x04, 0, 0xA4, 4)); // <- not in snapshot

    const snapshot = [_]CanonicalEntry{
        makeCanon(0x01, 0, 0xA1),
        makeCanon(0x02, 0, 0xA2),
        // 0x04 is absent
    };

    var detector = DriftDetector{ .store = store };
    const report = try detector.runWalk(allocator, &snapshot);
    defer drift_detector.deinit(report, allocator);

    try std.testing.expectEqual(@as(u32, 3), report.total_scanned);
    try std.testing.expectEqual(@as(u32, 1), report.drifted);
    try std.testing.expectEqual(@as(usize, 1), report.drift_entries.len);

    const de = report.drift_entries[0];
    try std.testing.expectEqualSlices(u8, &hash32(0x04), &de.cell_id);
    try std.testing.expectEqual(@as(u32, 0), de.domain_flag);
    // lmdb_hash is what LMDB had; canon_hash is all-zero (not in snapshot).
    try std.testing.expectEqualSlices(u8, &hash32(0xA4), &de.lmdb_hash);
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &de.canon_hash);
}

// ── M6.5-T-quarantine ────────────────────────────────────────────────────

test "M6.5-T-quarantine: after applyQuarantine, re-fetch drifted entry → state=3" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    // One drifted entry (hash mismatch).
    try store.put(makeEntry(0x10, 0, 0xBB, 5));

    const snapshot = [_]CanonicalEntry{
        makeCanon(0x10, 0, 0xCC), // canon says 0xCC, LMDB has 0xBB
    };

    var detector = DriftDetector{ .store = store };
    const report = try detector.runWalk(allocator, &snapshot);
    defer drift_detector.deinit(report, allocator);

    try std.testing.expectEqual(@as(u32, 1), report.drifted);

    try detector.applyQuarantine(allocator, report);

    // Re-fetch and verify state=3 (quarantined).
    const cell_id = hash32(0x10);
    var out: registry_cache.RegistryCacheEntry = undefined;
    const found = try store.get(&cell_id, 0, &out);
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(u8, 3), out.state);
}

// ── M6.5-T-clean-after-quarantine ────────────────────────────────────────

test "M6.5-T-clean-after-quarantine: cache_version incremented after quarantine" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    const original_version: u64 = 7;
    try store.put(makeEntry(0x20, 0, 0xDD, original_version));

    const snapshot = [_]CanonicalEntry{
        makeCanon(0x20, 0, 0xEE), // hash mismatch → drifted
    };

    var detector = DriftDetector{ .store = store };
    const report = try detector.runWalk(allocator, &snapshot);
    defer drift_detector.deinit(report, allocator);

    try std.testing.expectEqual(@as(u32, 1), report.drifted);

    try detector.applyQuarantine(allocator, report);

    const cell_id = hash32(0x20);
    var out: registry_cache.RegistryCacheEntry = undefined;
    const found = try store.get(&cell_id, 0, &out);
    try std.testing.expect(found);
    // cache_version must be strictly greater than the original.
    try std.testing.expect(out.cache_version > original_version);
}

```
