---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/header_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.965961+00:00
---

# core/cell-engine/tests/header_store_conformance.zig

```zig
// Phase WH2 — Trustless SPV: HeaderStore conformance tests.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH2).

const std = @import("std");
const headers = @import("headers");
const header_store = @import("header_store");

fn mkChain(allocator: std.mem.Allocator, n: u32) ![]headers.Header {
    const chain = try allocator.alloc(headers.Header, n);
    var prev_hash = [_]u8{0} ** 32;
    var ts: u32 = 1_700_000_000;
    for (0..n) |i| {
        var h = headers.Header{
            .version = 1,
            .prev_hash = prev_hash,
            .merkle_root = [_]u8{0xab} ** 32,
            .timestamp = ts,
            .bits = headers.REGTEST_BITS,
            .nonce = 0,
        };
        ts += 600;
        // Loose mine — powLimit is so easy nonce=0..few thousand always finds
        // something quickly.
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

test "WH2: append → get_by_height / get_by_hash round-trip" {
    var ls = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const chain = try mkChain(std.testing.allocator, 5);
    defer std.testing.allocator.free(chain);

    for (chain, 0..) |h, i| {
        try store.appendValidated(h, @intCast(i));
    }

    const got = store.getByHeight(2) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 2), got.height);

    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 4), tip.height);

    const by_hash = store.getByHash(&tip.hash) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 4), by_hash.height);
}

test "WH2: appendValidated rejects bad prev_hash" {
    var ls = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const chain = try mkChain(std.testing.allocator, 2);
    defer std.testing.allocator.free(chain);

    try store.appendValidated(chain[0], 0);

    var bad = chain[1];
    @memcpy(&bad.prev_hash, &([_]u8{0xff} ** 32));
    try std.testing.expectError(
        error.prev_hash_mismatch,
        store.appendValidated(bad, 1),
    );
}

test "WH2: snapshot → replay reconstructs state" {
    var src = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer src.deinit();
    const src_store = src.store();

    const chain = try mkChain(std.testing.allocator, 4);
    defer std.testing.allocator.free(chain);

    for (chain, 0..) |h, i| try src_store.appendValidated(h, @intCast(i));

    const snap = try src_store.snapshot(std.testing.allocator);
    defer std.testing.allocator.free(snap);

    var dst = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer dst.deinit();
    const dst_store = dst.store();
    try dst_store.replay(snap);

    const tip = dst_store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 3), tip.height);
}

test "WH2: rollback_from drops suffix" {
    var ls = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();
    const chain = try mkChain(std.testing.allocator, 6);
    defer std.testing.allocator.free(chain);
    for (chain, 0..) |h, i| try store.appendValidated(h, @intCast(i));

    const dropped = try store.rollbackFrom(4);
    try std.testing.expectEqual(@as(u32, 2), dropped);

    try std.testing.expect(store.getByHeight(4) == null);
    try std.testing.expect(store.getByHeight(3) != null);
    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 3), tip.height);
}

test "WH2: append rejects out-of-order height" {
    var ls = header_store.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();
    const chain = try mkChain(std.testing.allocator, 3);
    defer std.testing.allocator.free(chain);
    try store.appendValidated(chain[0], 0);
    try std.testing.expectError(
        error.height_out_of_order,
        store.appendValidated(chain[2], 5),
    );
}

test "WH2: PlexusHeaderStore stub returns persistence_failed" {
    var p = header_store.PlexusHeaderStore.init();
    const store = p.store();
    const empty_h = headers.Header{
        .version = 0,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = [_]u8{0} ** 32,
        .timestamp = 0,
        .bits = 0,
        .nonce = 0,
    };
    try std.testing.expectError(
        error.persistence_failed,
        store.appendValidated(empty_h, 0),
    );
}

```
