---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/allocator_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.958425+00:00
---

# core/cell-engine/tests/allocator_conformance.zig

```zig
const std = @import("std");
const allocator_mod = @import("allocator");

test "arena alloc returns correct slice" {
    var buf: [1024]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    const slice = arena.alloc(32).?;
    try std.testing.expectEqual(@as(usize, 32), slice.len);
}

test "arena alloc advances offset" {
    var buf: [1024]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    _ = arena.alloc(100).?;
    _ = arena.alloc(200).?;
    try std.testing.expectEqual(@as(usize, 724), arena.remaining());
}

test "arena alloc returns null on exhaustion" {
    var buf: [64]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    _ = arena.alloc(60).?;
    try std.testing.expect(arena.alloc(10) == null);
}

test "arena alloc exact fit succeeds" {
    var buf: [64]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    const slice = arena.alloc(64).?;
    try std.testing.expectEqual(@as(usize, 64), slice.len);
    try std.testing.expectEqual(@as(usize, 0), arena.remaining());
}

test "arena reset frees all allocations" {
    var buf: [128]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    _ = arena.alloc(100).?;
    try std.testing.expectEqual(@as(usize, 28), arena.remaining());

    arena.reset();
    try std.testing.expectEqual(@as(usize, 128), arena.remaining());

    // Can allocate again after reset
    const slice = arena.alloc(128).?;
    try std.testing.expectEqual(@as(usize, 128), slice.len);
}

test "arena zero-size alloc succeeds" {
    var buf: [64]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    const slice = arena.alloc(0).?;
    try std.testing.expectEqual(@as(usize, 0), slice.len);
    try std.testing.expectEqual(@as(usize, 64), arena.remaining());
}

test "arena multiple allocs are contiguous" {
    var buf: [256]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&buf);

    const a = arena.alloc(32).?;
    const b = arena.alloc(32).?;

    // b should start right after a
    try std.testing.expectEqual(@intFromPtr(a.ptr) + 32, @intFromPtr(b.ptr));
}

```
