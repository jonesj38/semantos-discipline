---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/header_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.181287+00:00
---

# runtime/semantos-brain/tests/header_store_fs_conformance.zig

```zig
// Phase Brain 2 — File-backed HeaderStore conformance.

const std = @import("std");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");
const header_store_fs = @import("header_store_fs");

fn tempDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return allocator.dupe(u8, real);
}

/// Mine a regtest-difficulty chain of N headers.
fn mkChain(allocator: std.mem.Allocator, n: u32) ![]headers_mod.Header {
    const chain = try allocator.alloc(headers_mod.Header, n);
    var prev_hash = [_]u8{0} ** 32;
    var ts: u32 = 1_700_000_000;
    for (0..n) |i| {
        var h = headers_mod.Header{
            .version = 1,
            .prev_hash = prev_hash,
            .merkle_root = [_]u8{@intCast((i % 250) + 1)} ** 32,
            .timestamp = ts,
            .bits = headers_mod.REGTEST_BITS,
            .nonce = 0,
        };
        ts += 600;
        var n_try: u32 = 0;
        while (n_try < 200_000) : (n_try += 1) {
            h.nonce = n_try;
            if (h.satisfiesProofOfWork()) break;
        }
        prev_hash = h.computeHash();
        chain[i] = h;
    }
    return chain;
}

test "Brain 2 header fs: append + getByHeight round-trip" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try header_store_fs.FsHeaderStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const store = fs.store();

    const chain = try mkChain(std.testing.allocator, 3);
    defer std.testing.allocator.free(chain);
    for (chain, 0..) |h, i| try store.appendValidated(h, @intCast(i));

    const got = store.getByHeight(1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 1), got.height);

    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 2), tip.height);

    const by_hash = store.getByHash(&tip.hash) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 2), by_hash.height);
}

test "Brain 2 header fs: persistence survives reopen" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    const chain = try mkChain(std.testing.allocator, 4);
    defer std.testing.allocator.free(chain);

    {
        var fs = try header_store_fs.FsHeaderStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        for (chain, 0..) |h, i| try fs.store().appendValidated(h, @intCast(i));
    }
    {
        var fs = try header_store_fs.FsHeaderStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const tip = fs.store().tip() orelse return error.TestFailed;
        try std.testing.expectEqual(@as(u32, 3), tip.height);
        const by_hash = fs.store().getByHash(&tip.hash) orelse return error.TestFailed;
        try std.testing.expectEqual(@as(u32, 3), by_hash.height);
    }
}

test "Brain 2 header fs: append rejects bad prev_hash" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try header_store_fs.FsHeaderStore.init(std.testing.allocator, dir);
    defer fs.deinit();

    const chain = try mkChain(std.testing.allocator, 2);
    defer std.testing.allocator.free(chain);
    try fs.store().appendValidated(chain[0], 0);

    var bad = chain[1];
    @memcpy(&bad.prev_hash, &([_]u8{0xff} ** 32));
    try std.testing.expectError(
        error.prev_hash_mismatch,
        fs.store().appendValidated(bad, 1),
    );
}

test "Brain 2 header fs: rollback truncates suffix" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    var fs = try header_store_fs.FsHeaderStore.init(std.testing.allocator, dir);
    defer fs.deinit();

    const chain = try mkChain(std.testing.allocator, 5);
    defer std.testing.allocator.free(chain);
    for (chain, 0..) |h, i| try fs.store().appendValidated(h, @intCast(i));

    const dropped = try fs.store().rollbackFrom(3);
    try std.testing.expectEqual(@as(u32, 2), dropped);

    try std.testing.expect(fs.store().getByHeight(3) == null);
    const tip = fs.store().tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 2), tip.height);
}

```
