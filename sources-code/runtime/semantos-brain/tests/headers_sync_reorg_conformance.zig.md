---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/headers_sync_reorg_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.183307+00:00
---

# runtime/semantos-brain/tests/headers_sync_reorg_conformance.zig

```zig
// Phase WH-Producer + Zig Headers polish — reorg-recovery conformance.
//
// Covers `attemptReorgRecovery` in isolation. Synthesises a
// `LocalHeaderStore` populated with a synthetic chain, calls the
// helper at varying depths, and asserts the chain shape matches
// expectations.
//
// The wire-level reorg-detection path (peer sends headers whose
// prev_hash doesn't match our tip → fetchOneRound returns
// `error.reorg_detected`) is covered by the existing `appendValidated`
// tests in headers_sync.zig itself; this file focuses on what happens
// AFTER detection: the daemon-loop recovery.

const std = @import("std");
const headers_sync = @import("headers_sync");
const header_store_mod = @import("header_store");
const headers_mod = @import("headers");

/// Build a synthetic chain of `n` headers where each header is
/// PoW-valid (we set `bits` to the trivial limit) and prev_hash links
/// to its predecessor's hash. The first header is treated as genesis.
fn populateSyntheticChain(
    store: *const header_store_mod.HeaderStore,
    n: u32,
) !void {
    var prev_hash: [32]u8 = undefined;
    @memset(&prev_hash, 0);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var hdr: headers_mod.Header = undefined;
        hdr.version = 1;
        @memcpy(&hdr.prev_hash, &prev_hash);
        @memset(&hdr.merkle_root, 0);
        hdr.timestamp = 1_700_000_000 + i;
        hdr.bits = 0x207fffff; // regtest difficulty target — trivially satisfied
        hdr.nonce = 0;
        // Spin nonce until PoW satisfied (with regtest target this is a
        // single nibble of work).
        var safety: u32 = 0;
        while (!hdr.satisfiesProofOfWork() and safety < 1000) : (safety += 1) {
            hdr.nonce += 1;
        }
        try std.testing.expect(hdr.satisfiesProofOfWork());
        try store.appendValidated(hdr, i);
        prev_hash = hdr.computeHash();
    }
}

// ── attemptReorgRecovery ──

test "WH-headers reorg: rollback 0 on empty store is a clean no-op" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    const report = try headers_sync.attemptReorgRecovery(&store, 1, null);
    try std.testing.expectEqual(@as(u32, 0), report.rolled);
}

test "WH-headers reorg: rollback_blocks=0 returns 0 even on populated chain" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);
    try std.testing.expectEqual(@as(u32, 49), store.tip().?.height);

    const report = try headers_sync.attemptReorgRecovery(&store, 0, null);
    try std.testing.expectEqual(@as(u32, 0), report.rolled);
    try std.testing.expectEqual(@as(u32, 49), store.tip().?.height);
}

test "WH-headers reorg: rollback 1 drops exactly one header" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);

    const report = try headers_sync.attemptReorgRecovery(&store, 1, null);
    try std.testing.expectEqual(@as(u32, 1), report.rolled);
    try std.testing.expectEqual(@as(u32, 48), store.tip().?.height);
}

test "WH-headers reorg: rollback 10 drops ten headers" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);

    const report = try headers_sync.attemptReorgRecovery(&store, 10, null);
    try std.testing.expectEqual(@as(u32, 10), report.rolled);
    try std.testing.expectEqual(@as(u32, 39), store.tip().?.height);
}

test "WH-headers reorg: rollback exceeding chain length clears to empty" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 5);

    const report = try headers_sync.attemptReorgRecovery(&store, 100, null);
    try std.testing.expectEqual(@as(u32, 5), report.rolled);
    try std.testing.expect(store.tip() == null);
}

test "WH-headers reorg: rollback exact chain length clears to empty" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 5);

    const report = try headers_sync.attemptReorgRecovery(&store, 5, null);
    try std.testing.expectEqual(@as(u32, 5), report.rolled);
    try std.testing.expect(store.tip() == null);
}

test "WH-headers reorg: escalating-schedule rollback converges quickly" {
    // Simulate the daemon loop's escalation: try 1, then 10, then 100,
    // expecting the first non-zero rollback to be the smallest depth
    // sufficient to drop all post-fork headers.
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);

    var rolled_total: u32 = 0;
    for (headers_sync.DEFAULT_REORG_SCHEDULE) |depth| {
        const report = try headers_sync.attemptReorgRecovery(&store, depth, null);
        rolled_total += report.rolled;
        if (report.rolled > 0) break;
    }
    // First iteration (depth=1) succeeds and the loop stops.
    try std.testing.expectEqual(@as(u32, 1), rolled_total);
    try std.testing.expectEqual(@as(u32, 48), store.tip().?.height);
}

test "WH-headers reorg: chain-then-recover-then-extend is idempotent" {
    // After rollback, append more headers (simulating the post-recovery
    // sync round). Tip-height + chain integrity are preserved.
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);

    _ = try headers_sync.attemptReorgRecovery(&store, 5, null);
    try std.testing.expectEqual(@as(u32, 44), store.tip().?.height);

    // Re-extend by 10 headers from the new tip.
    var prev_hash = store.tip().?.hash;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var hdr: headers_mod.Header = undefined;
        hdr.version = 1;
        @memcpy(&hdr.prev_hash, &prev_hash);
        @memset(&hdr.merkle_root, 0);
        hdr.timestamp = 1_800_000_000 + i;
        hdr.bits = 0x207fffff;
        hdr.nonce = 0;
        var safety: u32 = 0;
        while (!hdr.satisfiesProofOfWork() and safety < 1000) : (safety += 1) {
            hdr.nonce += 1;
        }
        try store.appendValidated(hdr, 45 + i);
        prev_hash = hdr.computeHash();
    }
    try std.testing.expectEqual(@as(u32, 54), store.tip().?.height);
}

```
