---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/cursor_host_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.966721+00:00
---

# core/cell-engine/tests/cursor_host_conformance.zig

```zig
// M1.10 — Cursor host-import conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the kernel_cursor_scan contract and verify the
// peak-heap bound (one cell buffer in linear memory at a time).
//
// Test IDs:
//   M1.10-T-scan-empty   — cursor on empty store returns 0
//   M1.10-T-scan-three   — 3 cells → callback called 3 times, count=3
//   M1.10-T-close-mid    — open cursor, pull one cell, close → no crash,
//                           subsequent pull returns 0
//   M1.10-T-peak-heap    — scan 100 cells → only one cell buffer live at a time
//
// Run: zig build test-cursor-host

const std = @import("std");
const lmdb = @import("lmdb");
const cell_store = @import("cell_store");
const lmdb_cell_store = @import("lmdb_cell_store");
const cursor_host = @import("cursor_host");

// ── helpers ──────────────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-cursor-host-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn makeCell(fill: u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    return c;
}

// ── M1.10-T-scan-empty ───────────────────────────────────────────────────────
// Open a cursor on an empty store; kernel_cursor_scan should return 0 cells.

test "M1.10-T-scan-empty: cursor scan on empty store returns 0" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var lmdb_store = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer lmdb_store.deinit();
    const store = lmdb_store.store();

    var host = cursor_host.CursorHost.init(&store);
    const count = host.cursorScan(null, null, 0);
    try std.testing.expectEqual(@as(i32, 0), count);
}

// ── M1.10-T-scan-three ───────────────────────────────────────────────────────
// Put 3 cells, scan → callback called 3 times, count = 3.

const ScanCtx = struct {
    count: u32 = 0,
    last_fill: u8 = 0,
};

fn countingCallback(ctx_ptr: ?*anyopaque, cell_ptr: *const [cell_store.CELL_BYTES]u8) void {
    if (ctx_ptr == null) return;
    const ctx: *ScanCtx = @ptrCast(@alignCast(ctx_ptr));
    ctx.count += 1;
    ctx.last_fill = cell_ptr[0];
}

test "M1.10-T-scan-three: 3 cells → callback 3 times, count=3" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var lmdb_store = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer lmdb_store.deinit();
    const store = lmdb_store.store();

    // Put 3 distinct cells.
    for (0..3) |i| {
        const cell = makeCell(@intCast(i + 1));
        _ = try store.put(&cell);
    }

    var ctx = ScanCtx{};
    var host = cursor_host.CursorHost.init(&store);
    const count = host.cursorScan(countingCallback, &ctx, 0);
    try std.testing.expectEqual(@as(i32, 3), count);
    try std.testing.expectEqual(@as(u32, 3), ctx.count);
}

// ── M1.10-T-close-mid ────────────────────────────────────────────────────────
// Open a cursor, pull one cell, then close early. No crash. Subsequent pull
// on the closed cursor returns 0 (end-of-data sentinel).

test "M1.10-T-close-mid: open cursor, pull one, close → no crash; subsequent pull = 0" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var lmdb_store = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer lmdb_store.deinit();
    const store = lmdb_store.store();

    // Put 5 cells so there is something to pull.
    for (0..5) |i| {
        const cell = makeCell(@intCast(i + 10));
        _ = try store.put(&cell);
    }

    var host = cursor_host.CursorHost.init(&store);

    // Open cursor: slot index 1..MAX_CURSORS.
    const cursor_id = host.openCursor(null, 0);
    try std.testing.expect(cursor_id != 0); // 0 = error

    // Pull one cell.
    var scratch: [cell_store.CELL_BYTES]u8 = undefined;
    const pulled = host.pullCell(cursor_id, &scratch);
    try std.testing.expectEqual(@as(u32, 1), pulled);

    // Close early.
    host.closeCursor(cursor_id);

    // Subsequent pull on a closed/invalid cursor must return 0, not crash.
    const after = host.pullCell(cursor_id, &scratch);
    try std.testing.expectEqual(@as(u32, 0), after);
}

// ── M1.10-T-peak-heap ────────────────────────────────────────────────────────
// Scan 100 cells and verify that the CursorHost itself never allocates more
// than one cell buffer's worth of scratch space. We measure this by checking
// that the CursorHost struct's scratch field is exactly CELL_BYTES in size
// (compile-time property) and that it is reused across pulls (runtime
// property: the pointer to the scratch buffer is the same on every callback).

const PeakHeapCtx = struct {
    last_ptr: usize = 0,
    unique_ptrs: u32 = 0,
    total: u32 = 0,
};

fn peakHeapCallback(ctx_ptr: ?*anyopaque, cell_ptr: *const [cell_store.CELL_BYTES]u8) void {
    if (ctx_ptr == null) return;
    const ctx: *PeakHeapCtx = @ptrCast(@alignCast(ctx_ptr));
    const p: usize = @intFromPtr(cell_ptr);
    if (p != ctx.last_ptr) {
        ctx.unique_ptrs += 1;
        ctx.last_ptr = p;
    }
    ctx.total += 1;
}

test "M1.10-T-peak-heap: scan 100 cells → single scratch buffer reused (peak heap = 1 cell)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var lmdb_store = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer lmdb_store.deinit();
    const store = lmdb_store.store();

    // Put 100 distinct cells.
    for (0..100) |i| {
        var cell: [cell_store.CELL_BYTES]u8 = undefined;
        // Use i as a distinct seed so all 100 hashes differ.
        @memset(&cell, 0);
        std.mem.writeInt(u32, cell[0..4], @intCast(i), .little);
        _ = try store.put(&cell);
    }

    var ctx = PeakHeapCtx{};
    var host = cursor_host.CursorHost.init(&store);
    const count = host.cursorScan(peakHeapCallback, &ctx, 0);

    try std.testing.expectEqual(@as(i32, 100), count);
    try std.testing.expectEqual(@as(u32, 100), ctx.total);
    // The scratch buffer pointer must be the same on every call: exactly 1
    // unique address across 100 callbacks.
    try std.testing.expectEqual(@as(u32, 1), ctx.unique_ptrs);

    // Compile-time assertion: CursorHost.scratch is exactly CELL_BYTES.
    try std.testing.expectEqual(cell_store.CELL_BYTES, @sizeOf(@TypeOf(@as(cursor_host.CursorHost, undefined).scratch)));
}

```
