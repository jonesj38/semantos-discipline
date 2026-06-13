---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_derivation_state_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.960337+00:00
---

# core/cell-engine/tests/lmdb_derivation_state_conformance.zig

```zig
// M1.4 — LmdbDerivationStateStore conformance tests.
//
// TDD red phase: written before the implementation.
// Mirrors derivation_state.zig inline tests but wires to LmdbDerivationStateStore.
//
// Test IDs: M1.4-T-get-index, M1.4-T-next-monotone, M1.4-T-snapshot-replay,
//           M1.4-T-ceiling, M1.4-T-multi-context.
//
// Run: zig build test-lmdb-derivation-state

const std = @import("std");
const lmdb = @import("lmdb");
const derivation_state = @import("derivation_state");
const lmdb_derivation_state = @import("lmdb_derivation_state");

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-drv-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

const PROTO: [16]u8 = [_]u8{0xAA} ** 16;
const PARTY: [33]u8 = [_]u8{0x02} ** 33;
const PROTO2: [16]u8 = [_]u8{0xBB} ** 16;
const PARTY2: [33]u8 = [_]u8{0x03} ** 33;

// ── M1.4-T-get-index ─────────────────────────────────────────────────

test "M1.4: get_index returns null for unknown context" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_derivation_state.LmdbDerivationStateStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    try std.testing.expect(store.getIndex(&PROTO, &PARTY) == null);
}

// ── M1.4-T-next-monotone ─────────────────────────────────────────────

test "M1.4: next_index is strictly monotone" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_derivation_state.LmdbDerivationStateStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    const idx0 = try store.nextIndex(&PROTO, &PARTY);
    const idx1 = try store.nextIndex(&PROTO, &PARTY);
    const idx2 = try store.nextIndex(&PROTO, &PARTY);

    try std.testing.expectEqual(@as(u64, 0), idx0);
    try std.testing.expectEqual(@as(u64, 1), idx1);
    try std.testing.expectEqual(@as(u64, 2), idx2);

    // get_index reflects the last allocated index.
    const cur = store.getIndex(&PROTO, &PARTY) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 2), cur);
}

// ── M1.4-T-snapshot-replay ───────────────────────────────────────────

test "M1.4: snapshot → replay round-trip" {
    const allocator = std.testing.allocator;

    const path_src = try tmpDir(allocator);
    defer allocator.free(path_src);
    defer std.fs.cwd().deleteTree(path_src) catch {};
    const path_dst = try tmpDir(allocator);
    defer allocator.free(path_dst);
    defer std.fs.cwd().deleteTree(path_dst) catch {};

    var env_src = try lmdb.Env.open(path_src, .{});
    defer env_src.close();
    var env_dst = try lmdb.Env.open(path_dst, .{});
    defer env_dst.close();

    var src = try lmdb_derivation_state.LmdbDerivationStateStore.init(&env_src, allocator);
    defer src.deinit();
    const src_store = src.store();

    _ = try src_store.nextIndex(&PROTO, &PARTY);
    _ = try src_store.nextIndex(&PROTO, &PARTY);
    _ = try src_store.nextIndex(&PROTO2, &PARTY2);

    const snap = try src_store.snapshot(allocator);
    defer allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 2), snap.len);

    var dst = try lmdb_derivation_state.LmdbDerivationStateStore.init(&env_dst, allocator);
    defer dst.deinit();
    const dst_store = dst.store();
    try dst_store.replay(snap);

    // After replay, indices match.
    const idx_a = dst_store.getIndex(&PROTO, &PARTY) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 1), idx_a);
    const idx_b = dst_store.getIndex(&PROTO2, &PARTY2) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0), idx_b);
}

// ── M1.4-T-ceiling ───────────────────────────────────────────────────
// Ceiling enforcement: next_index must never exceed the ceiling even under
// sequential calls. Uses LMDB's single-writer model: each call is its own
// write txn, so we test that the ceiling is respected across txn boundaries.

test "M1.4: next_index respects ceiling" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    // Ceiling of 3: indices 0, 1, 2 are valid; index 3 must be rejected.
    var s = try lmdb_derivation_state.LmdbDerivationStateStore.initWithCeiling(
        &env,
        allocator,
        3,
    );
    defer s.deinit();
    const store = s.store();

    _ = try store.nextIndex(&PROTO, &PARTY); // 0
    _ = try store.nextIndex(&PROTO, &PARTY); // 1
    _ = try store.nextIndex(&PROTO, &PARTY); // 2

    // Index 3 would exceed ceiling — must fail.
    try std.testing.expectError(
        error.persistence_failed,
        store.nextIndex(&PROTO, &PARTY),
    );

    // The current index remains at 2 (the last successful allocation).
    const cur = store.getIndex(&PROTO, &PARTY) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 2), cur);
}

// ── M1.4-T-multi-context ─────────────────────────────────────────────

test "M1.4: independent contexts do not interfere" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_derivation_state.LmdbDerivationStateStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    _ = try store.nextIndex(&PROTO, &PARTY);
    _ = try store.nextIndex(&PROTO, &PARTY);
    _ = try store.nextIndex(&PROTO2, &PARTY2);

    const idx_a = store.getIndex(&PROTO, &PARTY) orelse return error.TestFailed;
    const idx_b = store.getIndex(&PROTO2, &PARTY2) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 1), idx_a);
    try std.testing.expectEqual(@as(u64, 0), idx_b);
}

```
