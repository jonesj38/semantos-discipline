---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/bench/bench_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.267402+00:00
---

# runtime/semantos-brain/bench/bench_lmdb.zig

```zig
// bench_lmdb.zig — LMDB throughput benchmark suite
//
// Measures raw LMDB performance using the cell-shape from M1.5:
//   key:   32-byte type_hash
//   value: 1024-byte cell body
//
// Run via: cd core/cell-engine && zig build bench-lmdb
//
// Prerequisites: brew install lmdb  (macOS)
//                apt-get install liblmdb-dev  (Debian/Ubuntu)

const std = @import("std");
const lmdb = @import("lmdb");

// ── Cell shape (M1.5 realistic) ───────────────────────────────────────────────

const KEY_BYTES = 32; // type_hash
const VAL_BYTES = 1024; // cell body
const HEADER_KEY_BYTES = 8; // u64 big-endian block height
const HEADER_VAL_BYTES = 64; // block hash

// ── PRNG: xorshift32 ─────────────────────────────────────────────────────────

fn xorshift32(state: *u32) u32 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state.* = x;
    return x;
}

// ── Key/value generation ─────────────────────────────────────────────────────

fn makeKey(i: usize) [KEY_BYTES]u8 {
    var buf: [KEY_BYTES]u8 = undefined;
    var state: u32 = @truncate(i *% 0x9e3779b9 +% 1);
    var j: usize = 0;
    while (j < KEY_BYTES / 4) : (j += 1) {
        const v = xorshift32(&state);
        buf[j * 4 + 0] = @truncate(v >> 24);
        buf[j * 4 + 1] = @truncate(v >> 16);
        buf[j * 4 + 2] = @truncate(v >> 8);
        buf[j * 4 + 3] = @truncate(v);
    }
    return buf;
}

fn makeVal(i: usize) [VAL_BYTES]u8 {
    var buf: [VAL_BYTES]u8 = undefined;
    var state: u32 = @truncate(i *% 0x6c62272e +% 7);
    var j: usize = 0;
    while (j < VAL_BYTES / 4) : (j += 1) {
        const v = xorshift32(&state);
        buf[j * 4 + 0] = @truncate(v >> 24);
        buf[j * 4 + 1] = @truncate(v >> 16);
        buf[j * 4 + 2] = @truncate(v >> 8);
        buf[j * 4 + 3] = @truncate(v);
    }
    return buf;
}

fn makeHeaderKey(height: u64) [HEADER_KEY_BYTES]u8 {
    // big-endian so LMDB lexicographic order matches numeric order
    var buf: [HEADER_KEY_BYTES]u8 = undefined;
    buf[0] = @truncate(height >> 56);
    buf[1] = @truncate(height >> 48);
    buf[2] = @truncate(height >> 40);
    buf[3] = @truncate(height >> 32);
    buf[4] = @truncate(height >> 24);
    buf[5] = @truncate(height >> 16);
    buf[6] = @truncate(height >> 8);
    buf[7] = @truncate(height);
    return buf;
}

fn makeHeaderVal(height: u64) [HEADER_VAL_BYTES]u8 {
    var buf: [HEADER_VAL_BYTES]u8 = undefined;
    var state: u32 = @truncate(height *% 0xdeadbeef +% 3);
    var j: usize = 0;
    while (j < HEADER_VAL_BYTES / 4) : (j += 1) {
        const v = xorshift32(&state);
        buf[j * 4 + 0] = @truncate(v >> 24);
        buf[j * 4 + 1] = @truncate(v >> 16);
        buf[j * 4 + 2] = @truncate(v >> 8);
        buf[j * 4 + 3] = @truncate(v);
    }
    return buf;
}

// ── Shuffle (Fisher-Yates, xorshift32 PRNG) ───────────────────────────────────

fn shuffle(indices: []usize, seed: u32) void {
    var state: u32 = seed;
    var i = indices.len;
    while (i > 1) {
        i -= 1;
        const j = xorshift32(&state) % @as(u32, @truncate(i + 1));
        const tmp = indices[i];
        indices[i] = indices[j];
        indices[j] = tmp;
    }
}

// ── Rate computation ─────────────────────────────────────────────────────────

fn cellsPerSec(count: u64, elapsed_ns: u64) u64 {
    if (elapsed_ns == 0) return 0;
    return count * 1_000_000_000 / elapsed_ns;
}

// ── Formatted output helpers ──────────────────────────────────────────────────

fn fmtRate(buf: []u8, v: u64) []const u8 {
    if (v >= 1_000_000) {
        return std.fmt.bufPrint(buf, "{d:.1}M/s", .{@as(f64, @floatFromInt(v)) / 1_000_000.0}) catch "?";
    } else if (v >= 1_000) {
        return std.fmt.bufPrint(buf, "{d:.1}K/s", .{@as(f64, @floatFromInt(v)) / 1_000.0}) catch "?";
    } else {
        return std.fmt.bufPrint(buf, "{d}/s", .{v}) catch "?";
    }
}

fn fmtMs(buf: []u8, ns: u64, count: u64) []const u8 {
    if (count == 0) return "?";
    const ms = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(count)) / 1_000_000.0;
    return std.fmt.bufPrint(buf, "{d:.3}ms", .{ms}) catch "?";
}

// ── Table layout ─────────────────────────────────────────────────────────────
//
// Zig 0.15 io: std.Io.Writer (accessed via File.writer(&buf).interface) provides
// writeAll / print / writeByte / flush. writeByteNTimes is NOT available on
// std.Io.Writer — we build the box-drawing lines manually using a local buffer.

const COL_NAME = 45;
const COL_VAL = 10;

fn horzLine(w: *std.Io.Writer, left: []const u8, mid: []const u8, right: []const u8) !void {
    const single_dash: []const u8 = "─";
    var buf: [256]u8 = undefined;
    var pos: usize = 0;

    try w.writeAll(left);

    // name column
    pos = 0;
    for (0..COL_NAME + 2) |_| {
        @memcpy(buf[pos..pos+3], single_dash);
        pos += 3;
    }
    try w.writeAll(buf[0..pos]);
    try w.writeAll(mid);

    // 3 value columns + separator
    for (0..3) |_| {
        pos = 0;
        for (0..COL_VAL + 2) |_| {
            @memcpy(buf[pos..pos+3], single_dash);
            pos += 3;
        }
        try w.writeAll(buf[0..pos]);
        try w.writeAll(mid);
    }

    // last value column
    pos = 0;
    for (0..COL_VAL + 2) |_| {
        @memcpy(buf[pos..pos+3], single_dash);
        pos += 3;
    }
    try w.writeAll(buf[0..pos]);
    try w.writeAll(right);
}

fn tableHeader(w: *std.Io.Writer) !void {
    try w.print("│ {s:<" ++ std.fmt.comptimePrint("{d}", .{COL_NAME}) ++ "} │", .{"Benchmark"});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{"10K"});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{"100K"});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{"1M"});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │\n", .{"Target"});
}

fn tableRow(
    w: *std.Io.Writer,
    name: []const u8,
    v10k: []const u8,
    v100k: []const u8,
    v1m: []const u8,
    target: []const u8,
) !void {
    try w.print("│ {s:<" ++ std.fmt.comptimePrint("{d}", .{COL_NAME}) ++ "} │", .{name});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{v10k});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{v100k});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │", .{v1m});
    try w.print(" {s:^" ++ std.fmt.comptimePrint("{d}", .{COL_VAL}) ++ "} │\n", .{target});
}

// ── LMDB env open ─────────────────────────────────────────────────────────────

fn openEnv(dir_path: []const u8, nosync: bool) !lmdb.Env {
    const flags: c_uint = if (nosync) lmdb.EnvFlags.NOSYNC else 0;
    return lmdb.Env.open(dir_path, .{
        .max_dbs = 8,
        // 8 GiB map — LMDB copy-on-write can use 2–3× raw data size during
        // heavy write workloads; 1M × (32+1024) ≈ 1.05 GiB raw, so 8 GiB
        // gives comfortable headroom for dirty pages and B-tree overhead.
        .map_size = 8 * 1024 * 1024 * 1024,
        .open_flags = flags,
    });
}

// ── Drop + recreate named DB ──────────────────────────────────────────────────

fn clearDb(env: *lmdb.Env, name: [*:0]const u8) !lmdb.Dbi {
    var txn = try env.beginTxn(.read_write);
    const dbi = try txn.openDb(name, .{ .create = true });
    try txn.clear(dbi);
    try txn.commit();
    return dbi;
}

// ── Benchmark: sequential write with configurable batch size ─────────────────

fn benchWrite(env: *lmdb.Env, dbi: lmdb.Dbi, count: usize, batch_size: usize) !u64 {
    var timer = try std.time.Timer.start();
    var written: usize = 0;
    while (written < count) {
        var txn = try env.beginTxn(.read_write);
        const end = @min(written + batch_size, count);
        var i = written;
        while (i < end) : (i += 1) {
            const k = makeKey(i);
            const v = makeVal(i);
            try txn.put(dbi, &k, &v, .{});
        }
        try txn.commit();
        written = end;
    }
    return timer.read();
}

// ── Benchmark: sequential read ────────────────────────────────────────────────

fn benchSeqRead(env: *lmdb.Env, dbi: lmdb.Dbi, count: usize) !u64 {
    var timer = try std.time.Timer.start();
    var txn = try env.beginTxn(.read_only);
    defer txn.abort();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const k = makeKey(i);
        _ = try txn.get(dbi, &k);
    }
    return timer.read();
}

// ── Benchmark: random read ────────────────────────────────────────────────────

fn benchRandRead(env: *lmdb.Env, dbi: lmdb.Dbi, count: usize, alloc: std.mem.Allocator) !u64 {
    const indices = try alloc.alloc(usize, count);
    defer alloc.free(indices);
    for (indices, 0..) |*idx, i| idx.* = i;
    shuffle(indices, 0xdeadbeef);

    var timer = try std.time.Timer.start();
    var txn = try env.beginTxn(.read_only);
    defer txn.abort();
    for (indices) |idx| {
        const k = makeKey(idx);
        _ = try txn.get(dbi, &k);
    }
    return timer.read();
}

// ── Benchmark: cursor full scan ───────────────────────────────────────────────

fn benchCursorScan(env: *lmdb.Env, dbi: lmdb.Dbi) !struct { elapsed_ns: u64, count: u64 } {
    var timer = try std.time.Timer.start();
    var txn = try env.beginTxn(.read_only);
    defer txn.abort();
    var cur = try txn.openCursor(dbi);
    defer cur.close();
    var n: u64 = 0;
    while (try cur.next()) |_| n += 1;
    return .{ .elapsed_ns = timer.read(), .count = n };
}

// ── Benchmark: reorg rollback ─────────────────────────────────────────────────

fn benchReorgRollback(env: *lmdb.Env, header_count: usize, rollback_count: usize) !u64 {
    // Write headers
    {
        var setup = try env.beginTxn(.read_write);
        const hdbi = try setup.openDb("headers", .{ .create = true });
        try setup.clear(hdbi);
        try setup.commit();
    }
    {
        var write_txn = try env.beginTxn(.read_write);
        const hdbi = try write_txn.openDb("headers", .{ .create = false });
        var i: usize = 0;
        while (i < header_count) : (i += 1) {
            const k = makeHeaderKey(@as(u64, i));
            const v = makeHeaderVal(@as(u64, i));
            try write_txn.put(hdbi, &k, &v, .{});
        }
        try write_txn.commit();
    }

    // Measure: delete the last `rollback_count` heights
    var del_txn = try env.beginTxn(.read_write);
    const hdbi = try del_txn.openDb("headers", .{ .create = false });

    var timer = try std.time.Timer.start();
    var j: usize = header_count - rollback_count;
    while (j < header_count) : (j += 1) {
        const k = makeHeaderKey(@as(u64, j));
        try del_txn.del(hdbi, &k, null);
    }
    try del_txn.commit();
    return timer.read();
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Zig 0.15: File.writer() returns File.Writer; access the Io.Writer via .interface
    var io_buf: [131072]u8 = undefined;
    var fw = std.fs.File.stdout().writer(&io_buf);
    const out = &fw.interface;

    // ── Header ────────────────────────────────────────────────────────────────

    try out.writeAll("\n=== LMDB Benchmark Suite ===\n");
    try out.writeAll("Zig 0.15 | macOS/Linux | liblmdb system\n\n");
    try out.writeAll("Target (M1-T torture test):\n");
    try out.writeAll("  Write: 50,000 cells/sec sustained\n");
    try out.writeAll("  Read:  200,000 cells/sec random\n\n");
    try out.writeAll("Running benchmarks (this may take a few minutes for 1M)...\n");
    try out.flush();

    const counts = [3]usize{ 10_000, 100_000, 1_000_000 };

    // Result storage pool
    const BUF_COUNT = 64;
    var pool: [BUF_COUNT][32]u8 = undefined;
    var pool_idx: usize = 0;

    var seq_write: [3][]const u8 = undefined;
    var seq_read_r: [3][]const u8 = undefined;
    var rand_read_r: [3][]const u8 = undefined;
    var cursor_scan_r: [3][]const u8 = undefined;
    var reorg_r: [3][]const u8 = undefined;
    var batch1_r: [3][]const u8 = undefined;
    var batch100_r: [3][]const u8 = undefined;
    var batch1000_r: [3][]const u8 = undefined;
    var nosync_r: [3][]const u8 = undefined;

    for (counts, 0..) |n, ci| {
        try out.print("  [{d}/{d}] N={d}...\n", .{ ci + 1, counts.len, n });
        try out.flush();

        // Fresh temp directory for each N
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp_path = try tmp.dir.realpath(".", &path_buf);

        // Open env; detect missing liblmdb with a clear error message
        var env = openEnv(tmp_path, false) catch |err| {
            try out.print(
                "\nERROR: Could not open LMDB environment: {s}\n\nMake sure liblmdb is installed:\n  macOS:          brew install lmdb\n  Debian/Ubuntu:  apt-get install liblmdb-dev\n  Arch Linux:     pacman -S lmdb\n  Alpine:         apk add lmdb-dev\n",
                .{@errorName(err)},
            );
            try out.flush();
            std.process.exit(1);
        };
        defer env.close();

        // ── Sequential write (batch=1000, sustained throughput) ──────────────
        // Writing N cells in batches of 1000 reflects real ingestion patterns
        // and keeps per-commit memory pressure bounded regardless of N.
        {
            const dbi = try clearDb(&env, "cells");
            const elapsed = try benchWrite(&env, dbi, n, 1000);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            seq_write[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
        }

        // ── Sequential read ───────────────────────────────────────────────────
        {
            var ro = try env.beginTxn(.read_write);
            const dbi = try ro.openDb("cells", .{ .create = false });
            try ro.commit();
            const elapsed = try benchSeqRead(&env, dbi, n);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            seq_read_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
        }

        // ── Random read ───────────────────────────────────────────────────────
        {
            var ro = try env.beginTxn(.read_write);
            const dbi = try ro.openDb("cells", .{ .create = false });
            try ro.commit();
            const elapsed = try benchRandRead(&env, dbi, n, alloc);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            rand_read_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
        }

        // ── Cursor scan ───────────────────────────────────────────────────────
        {
            var ro = try env.beginTxn(.read_write);
            const dbi = try ro.openDb("cells", .{ .create = false });
            try ro.commit();
            const res = try benchCursorScan(&env, dbi);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            cursor_scan_r[ci] = fmtRate(buf, cellsPerSec(res.count, res.elapsed_ns));
        }

        // ── Reorg rollback ────────────────────────────────────────────────────
        {
            const header_n: usize = @min(n, 10_000);
            const rollback_n: usize = 10;
            const elapsed = try benchReorgRollback(&env, header_n, rollback_n);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            reorg_r[ci] = fmtMs(buf, elapsed, rollback_n);
        }

        // ── Batch size 1 ──────────────────────────────────────────────────────
        // One txn/cell = one fsync per write (~50ms on macOS SSD).
        // Use MDB_NOSYNC env for this sub-benchmark to get a throughput number
        // that reflects transaction overhead rather than storage latency.
        {
            const sample: usize = 1_000;
            // Reopen with NOSYNC so this completes in ms not minutes
            env.close();
            var b1_env = try openEnv(tmp_path, true);
            const dbi = try clearDb(&b1_env, "batch1");
            const elapsed = try benchWrite(&b1_env, dbi, sample, 1);
            b1_env.close();
            env = try openEnv(tmp_path, false);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            batch1_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, sample), elapsed));
        }

        // ── Batch size 100 ────────────────────────────────────────────────────
        {
            const dbi = try clearDb(&env, "cells");
            const elapsed = try benchWrite(&env, dbi, n, 100);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            batch100_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
        }

        // ── Batch size 1000 ───────────────────────────────────────────────────
        {
            const dbi = try clearDb(&env, "cells");
            const elapsed = try benchWrite(&env, dbi, n, 1000);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            batch1000_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
        }

        // ── NOSYNC sequential write ───────────────────────────────────────────
        // Close and reopen with NOSYNC flag.
        {
            env.close();
            var ns_env = openEnv(tmp_path, true) catch |err| {
                try out.print("  NOSYNC env open failed: {s}\n", .{@errorName(err)});
                nosync_r[ci] = "err";
                env = try openEnv(tmp_path, false);
                continue;
            };
            const ns_dbi = try clearDb(&ns_env, "cells_nosync");
            const elapsed = try benchWrite(&ns_env, ns_dbi, n, 1000);
            const buf = &pool[pool_idx];
            pool_idx += 1;
            nosync_r[ci] = fmtRate(buf, cellsPerSec(@as(u64, n), elapsed));
            ns_env.close();
            // Reopen env with sync (for any subsequent iteration use)
            env = try openEnv(tmp_path, false);
        }

        try out.writeAll("    done\n");
        try out.flush();
    }

    // ── Print results table ───────────────────────────────────────────────────

    try out.writeAll("\n");
    try horzLine(out, "┌", "┬", "┐\n");
    try tableHeader(out);
    try horzLine(out, "├", "┼", "┤\n");

    try tableRow(out, "Sequential write (cells/sec)",
        seq_write[0], seq_write[1], seq_write[2], "50K/s");
    try tableRow(out, "Sequential read (cells/sec)",
        seq_read_r[0], seq_read_r[1], seq_read_r[2], "200K/s");
    try tableRow(out, "Random read (cells/sec)",
        rand_read_r[0], rand_read_r[1], rand_read_r[2], "200K/s");
    try tableRow(out, "Cursor scan full table (cells/sec)",
        cursor_scan_r[0], cursor_scan_r[1], cursor_scan_r[2], "—");
    try tableRow(out, "Reorg rollback (ms/rollback, 10 heights)",
        reorg_r[0], reorg_r[1], reorg_r[2], "—");
    try tableRow(out, "Txn batch size 1 (cells/sec)",
        batch1_r[0], batch1_r[1], batch1_r[2], "—");
    try tableRow(out, "Txn batch size 100 (cells/sec)",
        batch100_r[0], batch100_r[1], batch100_r[2], "—");
    try tableRow(out, "Txn batch size 1000 (cells/sec)",
        batch1000_r[0], batch1000_r[1], batch1000_r[2], "—");
    try tableRow(out, "Sequential write NOSYNC (cells/sec)",
        nosync_r[0], nosync_r[1], nosync_r[2], "—");

    try horzLine(out, "└", "┴", "┘\n");

    try out.writeAll(
        \\
        \\Notes:
        \\  * Key: 32-byte type_hash | Value: 1024-byte cell body (M1.5 shape)
        \\  * Sequential write uses batch=1000 (bounded memory, realistic throughput)
        \\  * Reorg rollback: 10 heights deleted from a 10K-height header DB
        \\  * Batch size 1: 1K sample, NOSYNC mode (one fsync/txn = ~50ms on macOS)
        \\  * NOSYNC: all fsyncs disabled -- data loss risk on power failure
        \\  * Target is M1-T torture test requirement
        \\
    );
    try out.flush();
}

```
