---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/jobs_store_lmdb_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.172268+00:00
---

# runtime/semantos-brain/tests/jobs_store_lmdb_conformance.zig

```zig
// W0.1 — jobs_store_lmdb_conformance.zig
//
// Conformance tests for the LMDB-backed jobs store (jobs_store_lmdb.zig).
// These tests use TDD: committed red (all tests fail / compile error) then
// implemented green (all pass).
//
// Test contract:
//   • put_job() writes a job cell into LmdbCellStore.
//   • JobCursor iterates over job-domain cells in LMDB key order
//     (lexicographic by SHA256 hash — deterministic within a session).
//   • Cursor filters: only cells with the Oddjobz job domain flag pass.
//   • Empty store: cursor returns null immediately.
//   • Multiple puts + cursor pull returns all job cells (count matches).
//   • Non-job cells in the same store are invisible to the cursor.

const std = @import("std");
const jobs_store_lmdb = @import("jobs_store_lmdb");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

const JobsStoreLmdb = jobs_store_lmdb.JobsStoreLmdb;
const CELL_BYTES = jobs_store_lmdb.CELL_BYTES;
const ODDJOBZ_JOB_DOMAIN_FLAG = jobs_store_lmdb.ODDJOBZ_JOB_DOMAIN_FLAG;

// ── helpers ──────────────────────────────────────────────────────────────

/// Build a minimal 1024-byte job cell with the Oddjobz domain flag at
/// offset 24 (little-endian) and a unique payload byte at offset 256.
fn makeJobCell(unique_byte: u8) [CELL_BYTES]u8 {
    var cell = [_]u8{0} ** CELL_BYTES;
    // Write the Oddjobz job domain flag at the flags offset (24).
    std.mem.writeInt(u32, cell[24..28], ODDJOBZ_JOB_DOMAIN_FLAG, .little);
    // Unique payload marker so two cells produce distinct SHA256 keys.
    cell[256] = unique_byte;
    return cell;
}

/// Build a 1024-byte cell with a NON-Oddjobz domain flag (0x00000001).
fn makeOtherCell(unique_byte: u8) [CELL_BYTES]u8 {
    var cell = [_]u8{0} ** CELL_BYTES;
    std.mem.writeInt(u32, cell[24..28], @as(u32, 0x00000001), .little);
    cell[256] = unique_byte;
    return cell;
}

fn openEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024, // 4 MiB is plenty for tests
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

// ── test: empty store cursor returns null immediately ─────────────────────

test "lmdb cursor: empty store returns null on first pull" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    const cursor = try store.cursorOpen();
    defer store.cursorClose(cursor);

    const first = try store.cursorPull(cursor);
    try std.testing.expect(first == null);
}

// ── test: put + cursor round-trip (single job cell) ───────────────────────

test "lmdb cursor: put one job cell, cursor returns it" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    const cell = makeJobCell(0xAA);
    _ = try store.putJob(&cell);

    const cursor = try store.cursorOpen();
    defer store.cursorClose(cursor);

    const got = try store.cursorPull(cursor);
    try std.testing.expect(got != null);

    // The cell bytes returned must carry the Oddjobz domain flag.
    const flag = std.mem.readInt(u32, got.?[24..28], .little);
    try std.testing.expectEqual(ODDJOBZ_JOB_DOMAIN_FLAG, flag);

    // Unique payload byte survives the round-trip.
    try std.testing.expectEqual(@as(u8, 0xAA), got.?[256]);

    // No more cells.
    const done = try store.cursorPull(cursor);
    try std.testing.expect(done == null);
}

// ── test: multiple job cells — cursor yields all of them ──────────────────

test "lmdb cursor: three job cells, cursor returns all three" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    const cells = [_][CELL_BYTES]u8{
        makeJobCell(0x01),
        makeJobCell(0x02),
        makeJobCell(0x03),
    };
    for (&cells) |*c| {
        _ = try store.putJob(c);
    }

    const cursor = try store.cursorOpen();
    defer store.cursorClose(cursor);

    var count: usize = 0;
    while (try store.cursorPull(cursor)) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

// ── test: non-job cells are invisible to the cursor ───────────────────────

test "lmdb cursor: non-job cells filtered out" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    // Insert two non-job cells directly via the underlying cell store.
    const other_a = makeOtherCell(0xF0);
    const other_b = makeOtherCell(0xF1);
    _ = try cell_store.put(&other_a);
    _ = try cell_store.put(&other_b);

    // Insert one job cell via the jobs store.
    const job = makeJobCell(0x10);
    _ = try store.putJob(&job);

    const cursor = try store.cursorOpen();
    defer store.cursorClose(cursor);

    // Only the single job cell should be visible.
    var count: usize = 0;
    while (try store.cursorPull(cursor)) |cell| {
        const flag = std.mem.readInt(u32, cell[24..28], .little);
        try std.testing.expectEqual(ODDJOBZ_JOB_DOMAIN_FLAG, flag);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

// ── test: idempotent put — same cell twice yields count == 1 ──────────────

test "lmdb cursor: idempotent put — same cell not duplicated" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    const cell = makeJobCell(0x55);
    _ = try store.putJob(&cell);
    _ = try store.putJob(&cell); // idempotent

    const cursor = try store.cursorOpen();
    defer store.cursorClose(cursor);

    var count: usize = 0;
    while (try store.cursorPull(cursor)) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

// ── test: cursor can be opened and closed sequentially ───────────────────
//
// Note: LMDB allows only one active read transaction per thread (without
// MDB_NOTLS).  Two cursors opened sequentially (close first, then open
// second) are the correct idiom.

test "lmdb cursor: sequential cursors each see all data" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openEnv(dir);
    defer env.close();

    var cell_store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cell_store = cell_store_impl.store();

    var store = JobsStoreLmdb.init(cell_store);

    const c1 = makeJobCell(0x11);
    const c2 = makeJobCell(0x22);
    _ = try store.putJob(&c1);
    _ = try store.putJob(&c2);

    // First scan.
    var count_a: usize = 0;
    {
        const cursor_a = try store.cursorOpen();
        while (try store.cursorPull(cursor_a)) |_| count_a += 1;
        store.cursorClose(cursor_a);
    }

    // Second scan — cursor opened after first is closed.
    var count_b: usize = 0;
    {
        const cursor_b = try store.cursorOpen();
        while (try store.cursorPull(cursor_b)) |_| count_b += 1;
        store.cursorClose(cursor_b);
    }

    try std.testing.expectEqual(@as(usize, 2), count_a);
    try std.testing.expectEqual(@as(usize, 2), count_b);
}

```
