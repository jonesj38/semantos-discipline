---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/escalation_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.959242+00:00
---

# core/cell-engine/tests/escalation_test.zig

```zig
// M4.5 — storeWithEscalation conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the contract for octave routing based on payload size.
//
// Thresholds:
//   OCTAVE0_MAX = 768 bytes   → .cell result (no pointer, data packed inline)
//   OCTAVE1_MAX = 2_097_152   → .pointer_cell (writeSlot + pointer cell returned)
//   > OCTAVE1_MAX             → error.Octave2NotImplemented
//
// Test IDs:
//   M4.5-T-small-object       — 500 bytes → .cell; data at bytes 8-507
//   M4.5-T-large-object       — 2 MB → .pointer_cell; SHA-256 at [16..47]; total_size at [80..87]
//   M4.5-T-boundary-octave0   — exactly 768 bytes → .cell
//   M4.5-T-boundary-octave1   — exactly 769 bytes → .pointer_cell
//   M4.5-T-octave2-stub       — > OCTAVE1_MAX → error.Octave2NotImplemented
//
// Run: zig build test-escalation

const std = @import("std");
const escalation = @import("escalation");
const content_store_local_fs = @import("content_store_local_fs");
const ContentStoreLocalFs = content_store_local_fs.ContentStoreLocalFs;

// ── Helpers ───────────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [128]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/escalation-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

const zeroed_type_hash = [_]u8{0} ** 32;

// ── Tests ─────────────────────────────────────────────────────────────────

test "M4.5-T-small-object" {
    // 500 bytes → result is .cell; data present at bytes 8-507 of the cell.
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    const data_len = 500;
    var data: [data_len]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @truncate(i % 251);

    const result = try escalation.storeWithEscalation(&store, 0, &data, &zeroed_type_hash);

    switch (result) {
        .cell => |cell_bytes| {
            // Data must be at bytes 8..(8 + data_len)
            try std.testing.expectEqualSlices(u8, &data, cell_bytes[8 .. 8 + data_len]);
            // Bytes beyond the data must be zero
            for (cell_bytes[8 + data_len ..]) |b| {
                try std.testing.expectEqual(@as(u8, 0), b);
            }
        },
        .pointer_cell => return error.ExpectedCellNotPointer,
    }
}

test "M4.5-T-large-object" {
    // 2 MB → result is .pointer_cell; slot file exists;
    // content_hash at bytes 16-47 is SHA-256 of input; total_size at bytes 80-87 is 2MB LE.
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    const data_len = 2 * 1024 * 1024; // 2 MB
    const data = try alloc.alloc(u8, data_len);
    defer alloc.free(data);
    for (data, 0..) |*b, i| b.* = @truncate(i % 251);

    const slot: u32 = 7;
    const result = try escalation.storeWithEscalation(&store, slot, data, &zeroed_type_hash);

    switch (result) {
        .cell => return error.ExpectedPointerNotCell,
        .pointer_cell => |pc| {
            // Slot file must exist
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const slot_path = try std.fmt.bufPrint(
                &path_buf,
                "{s}/content/o1/{x:0>8}.slot",
                .{ dir, slot },
            );
            const stat = try std.fs.cwd().statFile(slot_path);
            try std.testing.expect(stat.size == data_len);

            // content_hash at cell bytes 16-47 must be SHA-256 of input
            var expected_hash: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(data, &expected_hash, .{});
            try std.testing.expectEqualSlices(u8, &expected_hash, pc.cell_bytes[16..48]);

            // total_size at cell bytes 80-87 must be data_len (LE u64)
            const total_size = std.mem.readInt(u64, pc.cell_bytes[80..88], .little);
            try std.testing.expectEqual(@as(u64, data_len), total_size);

            // octave field must be 1
            try std.testing.expectEqual(@as(u8, 1), pc.octave);
            // slot field must match
            try std.testing.expectEqual(slot, pc.slot);
        },
    }
}

test "M4.5-T-boundary-octave0" {
    // Exactly 768 bytes → .cell (edge of octave 0 threshold).
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    var data: [escalation.OCTAVE0_MAX]u8 = undefined;
    @memset(&data, 0xAB);

    const result = try escalation.storeWithEscalation(&store, 0, &data, &zeroed_type_hash);

    switch (result) {
        .cell => |cell_bytes| {
            try std.testing.expectEqualSlices(u8, &data, cell_bytes[8 .. 8 + escalation.OCTAVE0_MAX]);
        },
        .pointer_cell => return error.ExpectedCellNotPointer,
    }
}

test "M4.5-T-boundary-octave1" {
    // Exactly 769 bytes → .pointer_cell (just over octave 0 threshold).
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    var data: [escalation.OCTAVE0_MAX + 1]u8 = undefined;
    @memset(&data, 0xCD);

    const result = try escalation.storeWithEscalation(&store, 1, &data, &zeroed_type_hash);

    switch (result) {
        .cell => return error.ExpectedPointerNotCell,
        .pointer_cell => |pc| {
            try std.testing.expectEqual(@as(u8, 1), pc.octave);
        },
    }
}

test "M4.5-T-octave2-stub" {
    // data.len > OCTAVE1_MAX → error.Octave2NotImplemented.
    // We use a tiny backing buffer but slice it to a large length — the impl
    // must only inspect data.len, never dereference past OCTAVE1_MAX bytes.
    const alloc = std.testing.allocator;
    const dir = try tmpDir(alloc);
    defer alloc.free(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};

    var store = try ContentStoreLocalFs.init(alloc, dir);
    defer store.deinit();

    // Construct a slice with len > OCTAVE1_MAX from a small backing buffer.
    // The implementation must not read beyond OCTAVE1_MAX bytes.
    var tiny: [1]u8 = .{0};
    // Cast to a large slice — valid as long as the implementation only reads .len
    const big_len: usize = escalation.OCTAVE1_MAX + 1;
    const big_data: []const u8 = @as([*]const u8, @ptrCast(&tiny))[0..big_len];

    const result = escalation.storeWithEscalation(&store, 0, big_data, &zeroed_type_hash);
    try std.testing.expectError(error.Octave2NotImplemented, result);
}

```
