---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/headers_sync_reorg_sink_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.206222+00:00
---

# runtime/semantos-brain/tests/headers_sync_reorg_sink_conformance.zig

```zig
// D-LC5 — cartridge-side conformance for `attemptReorgRecovery`'s
// `ReorgSink` callback.
//
// Pairs with `tests/headers_sync_reorg_conformance.zig` (which covers
// the rollback-count semantics in isolation). This file focuses on
// the NEW behaviour added by D-LC5: when a `ReorgSink` is attached,
// `attemptReorgRecovery` invokes it after a successful rollback with
// the `from_height` floor that matches `rollbackFrom`'s contract.
//
// Uses `StubReorgSink` from the cartridge's reorg_sink module to
// keep this test cartridge-pure (no LMDB, no brain imports).

const std = @import("std");
const headers_sync = @import("headers_sync");
const reorg_sink_mod = @import("reorg_sink");
const header_store_mod = @import("header_store");
const headers_mod = @import("headers");

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
        hdr.bits = 0x207fffff; // regtest difficulty
        hdr.nonce = 0;
        var safety: u32 = 0;
        while (!hdr.satisfiesProofOfWork() and safety < 1000) : (safety += 1) {
            hdr.nonce += 1;
        }
        try std.testing.expect(hdr.satisfiesProofOfWork());
        try store.appendValidated(hdr, i);
        prev_hash = hdr.computeHash();
    }
}

test "D-LC5 reorg-sink: sink receives the rollback floor matching tip.height - depth + 1" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50); // heights 0..49

    var stub: reorg_sink_mod.StubReorgSink = .{};
    stub.next_result = .{ .swept = 4, .kept = 2 };
    const sink = stub.sink();

    const report = try headers_sync.attemptReorgRecovery(&store, 3, &sink);

    // Rolled back 3 headers — tip dropped from 49 to 46.
    try std.testing.expectEqual(@as(u32, 3), report.rolled);
    // from_height = 49 + 1 - 3 = 47 (the first removed height).
    try std.testing.expectEqual(@as(?u32, 47), report.from_height);
    // Sink was invoked exactly once with the floor.
    try std.testing.expectEqual(@as(u32, 1), stub.call_count);
    try std.testing.expectEqual(@as(?u64, 47), stub.last_height);
    // Sweep report flowed back into the recovery report.
    try std.testing.expect(report.sweep != null);
    try std.testing.expectEqual(@as(u32, 4), report.sweep.?.swept);
    try std.testing.expectEqual(@as(u32, 2), report.sweep.?.kept);
    try std.testing.expect(report.sweep_error == null);
}

test "D-LC5 reorg-sink: depth=1 floor = tip.height" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 100); // heights 0..99

    var stub: reorg_sink_mod.StubReorgSink = .{};
    const sink = stub.sink();

    const report = try headers_sync.attemptReorgRecovery(&store, 1, &sink);

    try std.testing.expectEqual(@as(u32, 1), report.rolled);
    // from_height = 99 + 1 - 1 = 99. The single block at tip is gone.
    try std.testing.expectEqual(@as(?u32, 99), report.from_height);
    try std.testing.expectEqual(@as(?u64, 99), stub.last_height);
}

test "D-LC5 reorg-sink: depth exceeds chain clips floor to 0" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 5);

    var stub: reorg_sink_mod.StubReorgSink = .{};
    const sink = stub.sink();

    const report = try headers_sync.attemptReorgRecovery(&store, 1000, &sink);

    // All 5 headers gone; chain is empty.
    try std.testing.expectEqual(@as(u32, 5), report.rolled);
    try std.testing.expectEqual(@as(?u32, 0), report.from_height);
    try std.testing.expectEqual(@as(?u64, 0), stub.last_height);
}

test "D-LC5 reorg-sink: empty store skips the sink (no-op rollback)" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();

    var stub: reorg_sink_mod.StubReorgSink = .{};
    const sink = stub.sink();

    const report = try headers_sync.attemptReorgRecovery(&store, 1, &sink);
    try std.testing.expectEqual(@as(u32, 0), report.rolled);
    try std.testing.expectEqual(@as(?u32, null), report.from_height);
    try std.testing.expect(report.sweep == null);
    // Sink NOT invoked: no header was removed, projection state is
    // consistent with the chain. Calling the sink anyway would
    // generate a spurious write-txn on every empty poll.
    try std.testing.expectEqual(@as(u32, 0), stub.call_count);
}

test "D-LC5 reorg-sink: rollback_blocks=0 skips the sink (early-out)" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 50);

    var stub: reorg_sink_mod.StubReorgSink = .{};
    const sink = stub.sink();

    const report = try headers_sync.attemptReorgRecovery(&store, 0, &sink);
    try std.testing.expectEqual(@as(u32, 0), report.rolled);
    try std.testing.expectEqual(@as(?u32, null), report.from_height);
    try std.testing.expectEqual(@as(u32, 0), stub.call_count);
}

test "D-LC5 reorg-sink: null sink keeps existing semantics (rollback still happens)" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 20);

    const report = try headers_sync.attemptReorgRecovery(&store, 5, null);
    try std.testing.expectEqual(@as(u32, 5), report.rolled);
    try std.testing.expectEqual(@as(?u32, 15), report.from_height); // 19+1-5
    try std.testing.expect(report.sweep == null);
    try std.testing.expect(report.sweep_error == null);
    try std.testing.expectEqual(@as(u32, 14), store.tip().?.height);
}

test "D-LC5 reorg-sink: sweep errors do NOT fail the recovery; surfaced in sweep_error" {
    var local = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer local.deinit();
    const store = local.store();
    try populateSyntheticChain(&store, 20);

    var stub: reorg_sink_mod.StubReorgSink = .{};
    stub.next_error = error.persistence_failed;
    const sink = stub.sink();

    // The recovery itself must succeed even though the sink failed —
    // the chain rollback already committed and is consistent. The
    // caller (daemon log loop) inspects `sweep_error` to log the
    // sweep failure separately.
    const report = try headers_sync.attemptReorgRecovery(&store, 2, &sink);
    try std.testing.expectEqual(@as(u32, 2), report.rolled);
    try std.testing.expectEqual(@as(?u32, 18), report.from_height);
    try std.testing.expect(report.sweep == null);
    try std.testing.expectEqual(@as(?reorg_sink_mod.SweepError, error.persistence_failed), report.sweep_error);
    // Chain heights were 0..19; rollback 2 removed heights 18 and 19,
    // leaving tip=17. The rollback itself succeeded — only the sweep
    // call failed (and that failure surfaces in `sweep_error`).
    try std.testing.expectEqual(@as(u32, 17), store.tip().?.height);
}

```
