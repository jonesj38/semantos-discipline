---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/slot_router_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.190129+00:00
---

# runtime/semantos-brain/tests/slot_router_test.zig

```zig
const std = @import("std");
const slot_router = @import("slot_router");
const SlotRouter = slot_router.SlotRouter;

// M7.1-T-single-peer: router with one peer always returns that peer.
test "M7.1-T-single-peer" {
    const peer: [32]u8 = [_]u8{0xAB} ** 32;
    const peers = [_][32]u8{peer};
    const allocator = std.testing.allocator;
    const router = SlotRouter.init(allocator, &peers);

    for ([_]u32{ 0, 1, 100, 65535, 0xFFFFFFFF }) |slot| {
        const result = try router.slotToPeer(slot);
        try std.testing.expectEqualSlices(u8, &peer, &result);
    }
}

// M7.1-T-deterministic: same slot + same peer set → same result across two router instances.
test "M7.1-T-deterministic" {
    const peers = [_][32]u8{
        [_]u8{0x01} ** 32,
        [_]u8{0x02} ** 32,
        [_]u8{0x03} ** 32,
    };
    const allocator = std.testing.allocator;
    const r1 = SlotRouter.init(allocator, &peers);
    const r2 = SlotRouter.init(allocator, &peers);

    for (0..200) |i| {
        const slot: u32 = @intCast(i);
        const a = try r1.slotToPeer(slot);
        const b = try r2.slotToPeer(slot);
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}

// M7.1-T-distribution: with 5 peers and 1000 slots, each peer owns 150–250 slots.
test "M7.1-T-distribution" {
    const peers = [_][32]u8{
        [_]u8{0x11} ** 32,
        [_]u8{0x22} ** 32,
        [_]u8{0x33} ** 32,
        [_]u8{0x44} ** 32,
        [_]u8{0x55} ** 32,
    };
    const allocator = std.testing.allocator;
    const router = SlotRouter.init(allocator, &peers);

    var counts = [_]u32{0} ** 5;
    for (0..1000) |i| {
        const slot: u32 = @intCast(i);
        const idx = try router.slotToPeerIndex(slot);
        counts[idx] += 1;
    }

    for (counts) |c| {
        try std.testing.expect(c >= 150 and c <= 250);
    }
}

// M7.1-T-churn-minimal: add one peer to a 4-peer set; assert ≤30% of slots change owner.
test "M7.1-T-churn-minimal" {
    const peers4 = [_][32]u8{
        [_]u8{0xAA} ** 32,
        [_]u8{0xBB} ** 32,
        [_]u8{0xCC} ** 32,
        [_]u8{0xDD} ** 32,
    };
    const peers5 = [_][32]u8{
        [_]u8{0xAA} ** 32,
        [_]u8{0xBB} ** 32,
        [_]u8{0xCC} ** 32,
        [_]u8{0xDD} ** 32,
        [_]u8{0xEE} ** 32,
    };
    const allocator = std.testing.allocator;
    const r4 = SlotRouter.init(allocator, &peers4);
    const r5 = SlotRouter.init(allocator, &peers5);

    const n_slots = 1000;
    var changed: u32 = 0;
    for (0..n_slots) |i| {
        const slot: u32 = @intCast(i);
        const before = try r4.slotToPeer(slot);
        const after = try r5.slotToPeer(slot);
        if (!std.mem.eql(u8, &before, &after)) changed += 1;
    }

    // Theory: ~1/5 = 20% change; allow up to 30%
    try std.testing.expect(changed <= n_slots * 30 / 100);
}

// M7.1-T-remove-peer: remove one peer from 5-peer set; all displaced slots go to remaining peers.
test "M7.1-T-remove-peer" {
    const peers5 = [_][32]u8{
        [_]u8{0x11} ** 32,
        [_]u8{0x22} ** 32,
        [_]u8{0x33} ** 32,
        [_]u8{0x44} ** 32,
        [_]u8{0x55} ** 32,
    };
    // Remove peer[2] = 0x33**32
    const peers4 = [_][32]u8{
        [_]u8{0x11} ** 32,
        [_]u8{0x22} ** 32,
        [_]u8{0x44} ** 32,
        [_]u8{0x55} ** 32,
    };
    const allocator = std.testing.allocator;
    const r5 = SlotRouter.init(allocator, &peers5);
    const r4 = SlotRouter.init(allocator, &peers4);

    const removed_peer = [_]u8{0x33} ** 32;

    for (0..1000) |i| {
        const slot: u32 = @intCast(i);
        const after = try r4.slotToPeer(slot);
        // Slots must go to one of the 4 remaining peers, never to the removed one.
        try std.testing.expect(!std.mem.eql(u8, &after, &removed_peer));

        // Slots that weren't on the removed peer must stay put.
        const before = try r5.slotToPeer(slot);
        if (!std.mem.eql(u8, &before, &removed_peer)) {
            try std.testing.expectEqualSlices(u8, &before, &after);
        }
    }
}

// M7.1-T-no-peers: slotToPeer with empty peers → error.NoPeers.
test "M7.1-T-no-peers" {
    const peers = [_][32]u8{};
    const allocator = std.testing.allocator;
    const router = SlotRouter.init(allocator, &peers);
    const result = router.slotToPeer(42);
    try std.testing.expectError(error.NoPeers, result);
}

```
