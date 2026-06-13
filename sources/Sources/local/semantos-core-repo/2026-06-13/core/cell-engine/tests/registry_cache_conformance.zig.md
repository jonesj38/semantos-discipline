---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/registry_cache_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.959517+00:00
---

# core/cell-engine/tests/registry_cache_conformance.zig

```zig
// M6.2 — RegistryCacheStore conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the LMDB-backed registry cache contract for octave_registry.
//
// Test IDs:
//   M6.2-T-put-get          — put entry → get returns same fields
//   M6.2-T-not-found        — get non-existent key → returns false
//   M6.2-T-invalidate       — put entry → invalidate → get returns false
//   M6.2-T-latest-version   — put 3 entries with versions 10, 20, 5 → latestVersion() = 20
//   M6.2-T-stale-detection  — entry.cache_version=5 vs postgres_version=10 → isStale=true;
//                             cache_version=15 → isStale=false
//   M6.2-T-overwrite        — put version 10 → put same key version 11 → get returns version 11
//
// Run: zig build test-registry-cache

const std = @import("std");
const lmdb = @import("lmdb");
const registry_cache = @import("registry_cache");
const registry_cache_lmdb = @import("registry_cache_lmdb");

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/reg-cache-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn makeEntry(seed: u8, version: u64) registry_cache.RegistryCacheEntry {
    var cell_id: [32]u8 = undefined;
    @memset(&cell_id, seed);
    var content_hash: [32]u8 = undefined;
    @memset(&content_hash, seed +% 1);
    return .{
        .cell_id = cell_id,
        .domain_flag = @as(u32, seed),
        .octave_level = seed % 3,
        .content_hash = content_hash,
        .linearity_type = seed % 4,
        .state = seed % 4,
        .cache_version = version,
        .registered_at_ms = 1_700_000_000_000,
    };
}

// ── M6.2-T-put-get ───────────────────────────────────────────────────

test "M6.2-T-put-get: put entry → get returns same fields" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    const entry = makeEntry(0xAA, 42);
    try store.put(entry);

    var out: registry_cache.RegistryCacheEntry = undefined;
    const found = try store.get(&entry.cell_id, entry.domain_flag, &out);
    try std.testing.expect(found);
    try std.testing.expectEqualSlices(u8, &entry.cell_id, &out.cell_id);
    try std.testing.expectEqual(entry.domain_flag, out.domain_flag);
    try std.testing.expectEqual(entry.octave_level, out.octave_level);
    try std.testing.expectEqualSlices(u8, &entry.content_hash, &out.content_hash);
    try std.testing.expectEqual(entry.linearity_type, out.linearity_type);
    try std.testing.expectEqual(entry.state, out.state);
    try std.testing.expectEqual(entry.cache_version, out.cache_version);
    try std.testing.expectEqual(entry.registered_at_ms, out.registered_at_ms);
}

// ── M6.2-T-not-found ─────────────────────────────────────────────────

test "M6.2-T-not-found: get non-existent key → returns false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    var cell_id: [32]u8 = undefined;
    @memset(&cell_id, 0xBB);

    var out: registry_cache.RegistryCacheEntry = undefined;
    const found = try store.get(&cell_id, 99, &out);
    try std.testing.expect(!found);
}

// ── M6.2-T-invalidate ────────────────────────────────────────────────

test "M6.2-T-invalidate: put entry → invalidate → get returns false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    const entry = makeEntry(0xCC, 7);
    try store.put(entry);

    // Confirm it exists.
    var out: registry_cache.RegistryCacheEntry = undefined;
    const before = try store.get(&entry.cell_id, entry.domain_flag, &out);
    try std.testing.expect(before);

    // Invalidate.
    try store.invalidate(&entry.cell_id, entry.domain_flag);

    // Now get must return false.
    const after = try store.get(&entry.cell_id, entry.domain_flag, &out);
    try std.testing.expect(!after);
}

// ── M6.2-T-latest-version ────────────────────────────────────────────

test "M6.2-T-latest-version: put 3 entries with versions 10, 20, 5 → latestVersion() = 20" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    try store.put(makeEntry(0x01, 10));
    try store.put(makeEntry(0x02, 20));
    try store.put(makeEntry(0x03, 5));

    const latest = try store.latestVersion();
    try std.testing.expectEqual(@as(u64, 20), latest);
}

// ── M6.2-T-stale-detection ───────────────────────────────────────────

test "M6.2-T-stale-detection: isStale compares cache_version vs postgres_version" {
    const stale_entry = makeEntry(0xDD, 5);
    try std.testing.expect(registry_cache_lmdb.isStale(stale_entry, 10));

    const fresh_entry = makeEntry(0xDD, 15);
    try std.testing.expect(!registry_cache_lmdb.isStale(fresh_entry, 10));

    // Equal version is NOT stale.
    const equal_entry = makeEntry(0xDD, 10);
    try std.testing.expect(!registry_cache_lmdb.isStale(equal_entry, 10));
}

// ── M6.2-T-overwrite ─────────────────────────────────────────────────

test "M6.2-T-overwrite: put version 10 → put same key version 11 → get returns version 11" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var impl = try registry_cache_lmdb.LmdbRegistryCacheStore.init(&env, allocator);
    defer impl.deinit();
    const store = impl.store();

    // First write at version 10.
    const e1 = makeEntry(0xEE, 10);
    try store.put(e1);

    // Second write — same key (same cell_id + domain_flag), version 11.
    var e2 = makeEntry(0xEE, 11);
    e2.state = 1; // mutate a field so we can verify the overwrite.
    try store.put(e2);

    var out: registry_cache.RegistryCacheEntry = undefined;
    const found = try store.get(&e2.cell_id, e2.domain_flag, &out);
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(u64, 11), out.cache_version);
    try std.testing.expectEqual(@as(u8, 1), out.state);
}

```
