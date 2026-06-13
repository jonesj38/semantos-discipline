---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/state_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.176479+00:00
---

# runtime/semantos-brain/tests/state_store_fs_conformance.zig

```zig
// Phase Brain 2 — File-backed DerivationStateStore conformance.

const std = @import("std");
const derivation_state = @import("derivation_state");
const state_store_fs = @import("state_store_fs");

fn tempDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return allocator.dupe(u8, real);
}

const TEST_PROTO: [16]u8 = .{0xaa} ** 16;
const TEST_CP: [33]u8 = .{0xcc} ** 33;

test "Brain 2 state fs: nextIndex starts at 0 and is monotone" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try state_store_fs.FsStateStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const store = fs.store();

    const idx0 = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    const idx1 = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    const idx2 = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    try std.testing.expectEqual(@as(u64, 0), idx0);
    try std.testing.expectEqual(@as(u64, 1), idx1);
    try std.testing.expectEqual(@as(u64, 2), idx2);
}

test "Brain 2 state fs: persistence survives reopen" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);

    {
        var fs = try state_store_fs.FsStateStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        _ = try fs.store().nextIndex(&TEST_PROTO, &TEST_CP);
        _ = try fs.store().nextIndex(&TEST_PROTO, &TEST_CP);
        // expect the disk now has current_index = 1.
    }
    {
        var fs = try state_store_fs.FsStateStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const cur = fs.store().getIndex(&TEST_PROTO, &TEST_CP);
        try std.testing.expectEqual(@as(?u64, 1), cur);
        const next = try fs.store().nextIndex(&TEST_PROTO, &TEST_CP);
        try std.testing.expectEqual(@as(u64, 2), next);
    }
}

test "Brain 2 state fs: distinct contexts have independent counters" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try state_store_fs.FsStateStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const store = fs.store();

    const proto2: [16]u8 = .{0xbb} ** 16;
    const cp2: [33]u8 = .{0xdd} ** 33;

    _ = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    _ = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    const a_first = try store.nextIndex(&proto2, &cp2);
    try std.testing.expectEqual(@as(u64, 0), a_first);
    const back_to_a = try store.nextIndex(&TEST_PROTO, &TEST_CP);
    try std.testing.expectEqual(@as(u64, 2), back_to_a);
}

test "Brain 2 state fs: snapshot + replay round-trip" {
    const src_dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(src_dir);
    var src = try state_store_fs.FsStateStore.init(std.testing.allocator, src_dir);
    defer src.deinit();

    _ = try src.store().nextIndex(&TEST_PROTO, &TEST_CP); // 0
    _ = try src.store().nextIndex(&TEST_PROTO, &TEST_CP); // 1
    _ = try src.store().nextIndex(&TEST_PROTO, &TEST_CP); // 2

    const snap = try src.store().snapshot(std.testing.allocator);
    defer std.testing.allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 1), snap.len);
    try std.testing.expectEqual(@as(u64, 2), snap[0].current_index);

    const dst_dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dst_dir);
    var dst = try state_store_fs.FsStateStore.init(std.testing.allocator, dst_dir);
    defer dst.deinit();
    try dst.store().replay(snap);
    const cur = dst.store().getIndex(&TEST_PROTO, &TEST_CP);
    try std.testing.expectEqual(@as(?u64, 2), cur);
}

```
