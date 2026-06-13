---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/content_store_local_fs_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.968948+00:00
---

# core/cell-engine/tests/content_store_local_fs_test.zig

```zig
// M4.1 — ContentStoreLocalFs conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the contract for fetching 1024-byte windows from
// octave-1 slot files stored on the local filesystem.
//
// Test IDs:
//   M4.1-T-window-at-offset     — cycling pattern, window at offset 0 and 4096
//   M4.1-T-window-end           — window at last valid offset; EndOfStream past end
//   M4.1-T-missing-slot         — fetch on non-existent slot → error.FileNotFound
//   M4.1-T-slot-naming          — slot 0x00000001 → file "00000001.slot"
//   M4.1-T-write-then-read-roundtrip — writeSlot then fetchWindow at multiple offsets
//
// Run: zig build test-content-store-local-fs

const std = @import("std");
const content_store_local_fs = @import("content_store_local_fs");
const ContentStoreLocalFs = content_store_local_fs.ContentStoreLocalFs;

// ── Helpers ───────────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [128]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/content-store-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

/// Build 1 MB of cycling byte pattern: byte[i] = @truncate(i % 251).
/// 251 is prime so the pattern has period 251, giving non-trivial windows.
fn makeCyclingData(alloc: std.mem.Allocator, size: usize) ![]u8 {
    const buf = try alloc.alloc(u8, size);
    for (buf, 0..) |*b, i| b.* = @truncate(i % 251);
    return buf;
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "M4.1-T-window-at-offset" {
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    const data_size = 1024 * 1024; // 1 MB
    const data = try makeCyclingData(alloc, data_size);
    defer alloc.free(data);

    try store.writeSlot(42, data);

    // Window at offset 0
    var out0: [1024]u8 = undefined;
    try store.fetchWindow(42, 0, &out0);
    try std.testing.expectEqualSlices(u8, data[0..1024], &out0);

    // Window at offset 4096
    var out1: [1024]u8 = undefined;
    try store.fetchWindow(42, 4096, &out1);
    try std.testing.expectEqualSlices(u8, data[4096..5120], &out1);
}

test "M4.1-T-window-end" {
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    const data_size = 1024 * 1024; // 1 MB
    const data = try makeCyclingData(alloc, data_size);
    defer alloc.free(data);

    try store.writeSlot(7, data);

    // Last valid offset: 1MB - 1024
    const last_valid_offset = data_size - 1024;
    var out_end: [1024]u8 = undefined;
    try store.fetchWindow(7, last_valid_offset, &out_end);
    try std.testing.expectEqualSlices(u8, data[last_valid_offset..], &out_end);

    // One byte past last valid window (offset 1MB - 512) → EndOfStream
    const past_end_offset = data_size - 512;
    var out_past: [1024]u8 = undefined;
    const result = store.fetchWindow(7, past_end_offset, &out_past);
    try std.testing.expectError(error.EndOfStream, result);
}

test "M4.1-T-missing-slot" {
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    var out: [1024]u8 = undefined;
    const result = store.fetchWindow(0xDEADBEEF, 0, &out);
    try std.testing.expectError(error.FileNotFound, result);
}

test "M4.1-T-slot-naming" {
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    // Write 2048 bytes so we can actually fetchWindow at offset 0
    var data: [2048]u8 = undefined;
    @memset(&data, 0xAB);
    try store.writeSlot(0x00000001, &data);

    // Verify the file is named "00000001.slot" inside <dir>/content/o1/
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const expected_path = try std.fmt.bufPrint(
        &path_buf,
        "{s}/content/o1/00000001.slot",
        .{dir},
    );
    const stat = try std.fs.cwd().statFile(expected_path);
    try std.testing.expect(stat.size == 2048);
}

test "M4.1-T-write-then-read-roundtrip" {
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    // Use a 3-window file: 3 * 1024 = 3072 bytes
    const data_size = 3 * 1024;
    const data = try makeCyclingData(alloc, data_size);
    defer alloc.free(data);

    try store.writeSlot(0xFF, data);

    // Read all three non-overlapping windows
    var win0: [1024]u8 = undefined;
    var win1: [1024]u8 = undefined;
    var win2: [1024]u8 = undefined;

    try store.fetchWindow(0xFF, 0, &win0);
    try store.fetchWindow(0xFF, 1024, &win1);
    try store.fetchWindow(0xFF, 2048, &win2);

    try std.testing.expectEqualSlices(u8, data[0..1024], &win0);
    try std.testing.expectEqualSlices(u8, data[1024..2048], &win1);
    try std.testing.expectEqualSlices(u8, data[2048..3072], &win2);
}

```
