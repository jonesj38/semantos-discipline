---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/peer_registry_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.198201+00:00
---

# runtime/semantos-brain/tests/peer_registry_test.zig

```zig
// M7.5 — PeerRegistry reputation + onboarding conformance tests.
//
// TDD red phase: written against the interface contract before the
// implementation exists. They will fail until peer_registry.zig lands.

const std = @import("std");
const peer_registry_mod = @import("peer_registry");

const PeerRegistry = peer_registry_mod.PeerRegistry;
const PeerStatus = peer_registry_mod.PeerStatus;

const peer_x = [_]u8{0xAA} ** 32;
const peer_y = [_]u8{0xBB} ** 32;
const peer_z = [_]u8{0xCC} ** 32;

const now_ms: u64 = 1_700_000_000_000;

// ── M7.5-T-onboard ────────────────────────────────────────────────────────
//
// New peer joins → status=candidate, reputation=0.

test "M7.5-T-onboard" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);

    const rec = reg.getPeer(peer_x);
    try std.testing.expect(rec != null);
    try std.testing.expectEqual(PeerStatus.candidate, rec.?.status);
    try std.testing.expectEqual(@as(i32, 0), rec.?.reputation_score);
    try std.testing.expectEqual(now_ms, rec.?.joined_at_ms);
}

// ── M7.5-T-onboard-duplicate ──────────────────────────────────────────────
//
// Onboarding the same peer twice returns error.AlreadyRegistered.

test "M7.5-T-onboard-duplicate" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);
    const result = reg.onboard(peer_x, now_ms + 1000);
    try std.testing.expectError(error.AlreadyRegistered, result);
}

// ── M7.5-T-promote ────────────────────────────────────────────────────────
//
// 5 correct responses (+50 reputation) promotes candidate → active.

test "M7.5-T-promote" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);

    // 5 × +10 = +50 → promotes to active.
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try reg.recordCorrect(peer_x, now_ms + @as(u64, i) * 1000);
    }

    const rec = reg.getPeer(peer_x);
    try std.testing.expect(rec != null);
    try std.testing.expectEqual(PeerStatus.active, rec.?.status);
    try std.testing.expectEqual(@as(i32, 50), rec.?.reputation_score);
    try std.testing.expectEqual(@as(u32, 5), rec.?.correct_responses);
}

// ── M7.5-T-suspend ────────────────────────────────────────────────────────
//
// Enough wrong responses to reach ≤ −50 reputation → status=suspended.

test "M7.5-T-suspend" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);

    // 2 × -30 = -60 → suspended.
    try reg.recordWrong(peer_x, now_ms + 1000);
    try reg.recordWrong(peer_x, now_ms + 2000);

    const rec = reg.getPeer(peer_x);
    try std.testing.expect(rec != null);
    try std.testing.expectEqual(PeerStatus.suspended, rec.?.status);
    try std.testing.expect(rec.?.reputation_score <= -50);
    try std.testing.expectEqual(@as(u32, 2), rec.?.wrong_responses);
}

// ── M7.5-T-evict ──────────────────────────────────────────────────────────
//
// Enough wrong responses to reach ≤ −100 reputation → status=evicted.

test "M7.5-T-evict" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);

    // 4 × -30 = -120 → evicted.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try reg.recordWrong(peer_x, now_ms + @as(u64, i) * 1000);
    }

    const rec = reg.getPeer(peer_x);
    try std.testing.expect(rec != null);
    try std.testing.expectEqual(PeerStatus.evicted, rec.?.status);
    try std.testing.expect(rec.?.reputation_score <= -100);
}

// ── M7.5-T-list-active ────────────────────────────────────────────────────
//
// 3 peers: 1 active, 1 candidate, 1 evicted → listActive returns only 1.

test "M7.5-T-list-active" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    // peer_x → promote to active (+50).
    try reg.onboard(peer_x, now_ms);
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try reg.recordCorrect(peer_x, now_ms + @as(u64, i) * 1000);
    }

    // peer_y → stays candidate.
    try reg.onboard(peer_y, now_ms);

    // peer_z → evict (-120).
    try reg.onboard(peer_z, now_ms);
    var j: usize = 0;
    while (j < 4) : (j += 1) {
        try reg.recordWrong(peer_z, now_ms + @as(u64, j) * 1000);
    }

    const active = try reg.listActive(allocator);
    defer allocator.free(active);

    try std.testing.expectEqual(@as(usize, 1), active.len);
    try std.testing.expectEqualSlices(u8, &peer_x, &active[0]);
}

// ── M7.5-T-purge ──────────────────────────────────────────────────────────
//
// After eviction, purgeEvicted removes the peer entirely from the registry.

test "M7.5-T-purge" {
    const allocator = std.testing.allocator;
    var reg = PeerRegistry.init(allocator);
    defer reg.deinit();

    try reg.onboard(peer_x, now_ms);

    // Evict peer_x.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try reg.recordWrong(peer_x, now_ms + @as(u64, i) * 1000);
    }

    // purgeEvicted returns the count removed.
    const purged = reg.purgeEvicted();
    try std.testing.expectEqual(@as(usize, 1), purged);

    // Peer must no longer be in the registry.
    try std.testing.expect(reg.getPeer(peer_x) == null);
}

```
