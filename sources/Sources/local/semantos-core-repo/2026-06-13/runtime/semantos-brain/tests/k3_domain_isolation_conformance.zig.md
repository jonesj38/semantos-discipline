---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/k3_domain_isolation_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.177315+00:00
---

# runtime/semantos-brain/tests/k3_domain_isolation_conformance.zig

```zig
// W7.12 — K3 domain-isolation conformance tests.
//
// Verifies that the op_pkh prefix scheme (W7.1) enforces strict operator
// boundary at the cell-storage layer.  These are the K3-level isolation
// invariants: no cross-operator read, no cross-operator cursor bleed.
//
// Test contract:
//   1. Point-lookup isolation: a cell written by operator A is invisible
//      to operator B even if B constructs the same SHA256 key.
//   2. Cursor isolation: operator B's cursor scan returns no entries from
//      the range written exclusively by operator A.
//   3. Interleaved storage: cells for two operators written in alternating
//      order; each cursor returns only its own cells.
//   4. deleteAllCells respects op_pkh: deleting all of A's cells does not
//      affect B's cells.
//   5. Zero op_pkh (single-tenant legacy): cells written with the zero
//      op_pkh store are not visible to a named-operator store and vice
//      versa.

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

const LmdbCellStore = lmdb_cell_store.LmdbCellStore;
const OP_PKH_BYTES = lmdb_cell_store.OP_PKH_BYTES;
const CELL_BYTES = 1024;

// ── helpers ──────────────────────────────────────────────────────────────

fn makeCell(seed: u8) [CELL_BYTES]u8 {
    var cell = [_]u8{seed} ** CELL_BYTES;
    cell[512] = seed ^ 0xFF; // make cells with the same seed content-distinct
    return cell;
}

fn openEnv(path: []const u8) !lmdb.Env {
    return lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
}

// ── tests ─────────────────────────────────────────────────────────────────

test "K3: point-lookup isolation — A's cell is invisible to B" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(path);
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = .{ 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA };
    const pkh_b: [OP_PKH_BYTES]u8 = .{ 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB };

    var impl_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var impl_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer impl_a.deinit();
    defer impl_b.deinit();

    const sa = impl_a.store();
    const sb = impl_b.store();

    var cell = makeCell(0x01);
    const hash = try sa.put(&cell);

    // A can find its own cell.
    try std.testing.expect(sa.exists(&hash));
    // B cannot find A's cell — same hash, different prefix.
    try std.testing.expect(!sb.exists(&hash));
}

test "K3: cursor isolation — B's cursor returns no cells written by A" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(path);
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = .{ 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const pkh_b: [OP_PKH_BYTES]u8 = .{ 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var impl_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var impl_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer impl_a.deinit();
    defer impl_b.deinit();

    const sa = impl_a.store();
    const sb = impl_b.store();

    // Write 3 cells for A.
    for (1..4) |i| {
        var cell = makeCell(@intCast(i));
        _ = try sa.put(&cell);
    }

    // B's cursor should return null immediately (no cells for B).
    const cur = try sb.cursorOpen();
    defer sb.cursorClose(cur);
    const entry = try sb.cursorPull(cur);
    try std.testing.expect(entry == null);
}

test "K3: interleaved storage — each operator sees only its own cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(path);
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = .{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const pkh_b: [OP_PKH_BYTES]u8 = .{ 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var impl_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var impl_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer impl_a.deinit();
    defer impl_b.deinit();

    const sa = impl_a.store();
    const sb = impl_b.store();

    // Interleave writes: A, B, A, B, A.
    const seeds = [_]u8{ 0x10, 0x20, 0x30, 0x40, 0x50 };
    var ca1 = makeCell(seeds[0]);
    var cb1 = makeCell(seeds[1]);
    var ca2 = makeCell(seeds[2]);
    var cb2 = makeCell(seeds[3]);
    var ca3 = makeCell(seeds[4]);

    _ = try sa.put(&ca1);
    _ = try sb.put(&cb1);
    _ = try sa.put(&ca2);
    _ = try sb.put(&cb2);
    _ = try sa.put(&ca3);

    // Count cells returned by each cursor.
    const cur_a = try sa.cursorOpen();
    defer sa.cursorClose(cur_a);
    var count_a: usize = 0;
    while (try sa.cursorPull(cur_a)) |_| count_a += 1;

    const cur_b = try sb.cursorOpen();
    defer sb.cursorClose(cur_b);
    var count_b: usize = 0;
    while (try sb.cursorPull(cur_b)) |_| count_b += 1;

    try std.testing.expectEqual(@as(usize, 3), count_a);
    try std.testing.expectEqual(@as(usize, 2), count_b);
}

test "K3: deleteAllCells does not affect other operator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(path);
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = .{ 0xA0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const pkh_b: [OP_PKH_BYTES]u8 = .{ 0xB0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var impl_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var impl_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer impl_a.deinit();
    defer impl_b.deinit();

    const sa = impl_a.store();
    const sb = impl_b.store();

    var cell_a = makeCell(0xA1);
    var cell_b = makeCell(0xB1);
    _ = try sa.put(&cell_a);
    const hash_b = try sb.put(&cell_b);

    // Delete all of A's cells.
    try impl_a.deleteAllCells();

    // A's store is now empty.
    const cur_a = try sa.cursorOpen();
    defer sa.cursorClose(cur_a);
    try std.testing.expect((try sa.cursorPull(cur_a)) == null);

    // B's cell is untouched.
    try std.testing.expect(sb.exists(&hash_b));
}

test "K3: zero op_pkh and named op_pkh are disjoint namespaces" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(path);
    defer env.close();

    const pkh_named: [OP_PKH_BYTES]u8 = .{ 0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x00, 0x00 };

    // Single-tenant store (zero op_pkh).
    var impl_0 = try LmdbCellStore.init(&env, std.testing.allocator);
    // Named operator store.
    var impl_n = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_named);
    defer impl_0.deinit();
    defer impl_n.deinit();

    const s0 = impl_0.store();
    const sn = impl_n.store();

    var cell_zero  = makeCell(0x00);
    var cell_named = makeCell(0xFF);
    const hash_zero  = try s0.put(&cell_zero);
    const hash_named = try sn.put(&cell_named);

    // Named store cannot see the zero-store cell.
    try std.testing.expect(!sn.exists(&hash_zero));
    // Zero store cannot see the named-operator cell.
    try std.testing.expect(!s0.exists(&hash_named));
}

```
