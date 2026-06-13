---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/slot_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.180196+00:00
---

# runtime/semantos-brain/tests/slot_store_fs_conformance.zig

```zig
// Phase Brain 2 — File-backed SlotStore conformance.

const std = @import("std");
const slot_store = @import("slot_store");
const slot_store_fs = @import("slot_store_fs");

fn tempDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return allocator.dupe(u8, real);
}

test "Brain 2 slot fs: put → get round-trips" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const store = fs.store();

    const blob = [_]u8{ 0xab, 0xcd, 0xef, 0x01, 0x02, 0x03, 0x04, 0x05 };
    try store.put(7, &blob);
    const got = try store.get(7);
    try std.testing.expectEqualSlices(u8, &blob, got);
}

test "Brain 2 slot fs: persistence survives reopen" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);

    {
        var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        try fs.store().put(99, "persist-me");
    }
    {
        var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const got = try fs.store().get(99);
        try std.testing.expectEqualStrings("persist-me", got);
    }
}

test "Brain 2 slot fs: get returns not_found for missing slot" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    try std.testing.expectError(error.not_found, fs.store().get(123));
}

test "Brain 2 slot fs: delete clears both file + cache" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    try fs.store().put(5, "to-delete");
    _ = try fs.store().get(5); // populate cache
    try fs.store().delete(5);
    try std.testing.expectError(error.not_found, fs.store().get(5));
    try std.testing.expectError(error.not_found, fs.store().delete(5));
}

test "Brain 2 slot fs: overwrite refreshes cached bytes" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try slot_store_fs.FsSlotStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    try fs.store().put(1, "before");
    _ = try fs.store().get(1); // cache fill
    try fs.store().put(1, "after");
    const got = try fs.store().get(1);
    try std.testing.expectEqualStrings("after", got);
}

```
