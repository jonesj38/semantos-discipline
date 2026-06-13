---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/federated_state_store_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.188098+00:00
---

# runtime/semantos-brain/tests/federated_state_store_test.zig

```zig
// M7.4 — FederatedSemantosStateStore conformance tests.
//
// TDD red phase: written against the interface contract before the
// implementation exists.  They will fail until the green commit lands
// `federated_state_store.zig`.
//
// Routing rule: bytes 0–3 of protocol_hash interpreted as u32 LE → slot.
// The same rule is used by the implementation and the tests so routing is
// deterministic and testable without a real network.

const std = @import("std");
const derivation_state = @import("derivation_state");
const fed_state_store = @import("federated_state_store");
const rpc_log_mod = @import("rpc_log");
const slot_router_mod = @import("slot_router");

const DerivationStateStore = derivation_state.DerivationStateStore;
const LocalStateStore = derivation_state.LocalStateStore;
const FederatedSemantosStateStore = fed_state_store.FederatedSemantosStateStore;
const RpcLog = rpc_log_mod.RpcLog;
const SlotRouter = slot_router_mod.SlotRouter;

// ── Helpers ───────────────────────────────────────────────────────────────

/// Build a protocol_hash whose bytes 0–3 (u32 LE) produce the given slot value.
fn protocolHashForSlot(slot: u32) [16]u8 {
    var h = [_]u8{0} ** 16;
    std.mem.writeInt(u32, h[0..4], slot, .little);
    return h;
}

/// Slot from protocol_hash: bytes 0–3 as u32 LE.
fn slotOf(protocol_hash: [16]u8) u32 {
    return std.mem.readInt(u32, protocol_hash[0..4], .little);
}

const peer_a = [_]u8{0x01} ** 32;
const peer_b = [_]u8{0x02} ** 32;
const dummy_counterparty = [_]u8{0xAB} ** 33;

/// Find a protocol_hash slot that routes to `want_peer` in a 2-peer router.
fn protocolHashForPeer(router: SlotRouter, want_peer: [32]u8) [16]u8 {
    var n: u32 = 0;
    while (n < 0xFFFF) : (n += 1) {
        const h = protocolHashForSlot(n);
        const got = router.slotToPeer(slotOf(h)) catch continue;
        if (std.mem.eql(u8, &got, &want_peer)) return h;
    }
    unreachable;
}

// ── M7.4-T-local-issue ────────────────────────────────────────────────────
//
// protocol_hash routes to local → delegates to local store; rpc_log empty.

test "M7.4-T-local-issue" {
    const allocator = std.testing.allocator;

    const peers = [_][32]u8{ peer_a, peer_b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalStateStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosStateStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    const ph = protocolHashForPeer(router, peer_a);
    const cp = dummy_counterparty;

    const idx = try s.nextIndex(&ph, &cp);

    // rpc_log must be empty — this was a local write.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);

    // Returned index must be 0 (first allocation).
    try std.testing.expectEqual(@as(u64, 0), idx);

    // The local store must hold the record.
    const got = local.store().getIndex(&ph, &cp);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 0), got.?);
}

// ── M7.4-T-remote-issue ───────────────────────────────────────────────────
//
// protocol_hash routes to remote → rpc_log has write_state entry; local store empty.

test "M7.4-T-remote-issue" {
    const allocator = std.testing.allocator;

    const peers = [_][32]u8{ peer_a, peer_b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalStateStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    // We are peer_a; issue a record that routes to peer_b.
    var fed = FederatedSemantosStateStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    const ph = protocolHashForPeer(router, peer_b);
    const cp = dummy_counterparty;

    _ = try s.nextIndex(&ph, &cp);

    // rpc_log must have exactly one entry with op=write_state.
    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(rpc_log_mod.RpcEntry.Op.write_state, entries[0].op);
    try std.testing.expectEqualSlices(u8, &peer_b, &entries[0].peer_id);

    // Local store must be empty (no index stored).
    const got = local.store().getIndex(&ph, &cp);
    try std.testing.expect(got == null);
}

// ── M7.4-T-local-get-index ────────────────────────────────────────────────
//
// Issue locally; getIndex returns the correct value.

test "M7.4-T-local-get-index" {
    const allocator = std.testing.allocator;

    const peers = [_][32]u8{ peer_a, peer_b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalStateStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosStateStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    const ph = protocolHashForPeer(router, peer_a);
    const cp = dummy_counterparty;

    _ = try s.nextIndex(&ph, &cp); // allocates index 0
    _ = try s.nextIndex(&ph, &cp); // allocates index 1
    rpc_log.clear();

    // getIndex must return 1 (last allocated).
    const got = s.getIndex(&ph, &cp);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 1), got.?);

    // No remote reads needed.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);
}

// ── M7.4-T-remote-get-index ───────────────────────────────────────────────
//
// getIndex for remotely-owned slot → rpc_log has read_state entry; returns null.

test "M7.4-T-remote-get-index" {
    const allocator = std.testing.allocator;

    const peers = [_][32]u8{ peer_a, peer_b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalStateStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosStateStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    // Use a protocol_hash that routes to peer_b (remote).
    const ph = protocolHashForPeer(router, peer_b);
    const cp = dummy_counterparty;

    const got = s.getIndex(&ph, &cp);
    try std.testing.expect(got == null); // stub returns null for remote

    // rpc_log must record a remote read.
    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(rpc_log_mod.RpcEntry.Op.read_state, entries[0].op);
    try std.testing.expectEqualSlices(u8, &peer_b, &entries[0].peer_id);
}

// ── M7.4-T-snapshot-replay ────────────────────────────────────────────────
//
// Snapshot local state; replay into a fresh local store; verify round-trip.

test "M7.4-T-snapshot-replay" {
    const allocator = std.testing.allocator;

    const peers = [_][32]u8{ peer_a, peer_b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalStateStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosStateStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    // Write two local entries.
    const ph1 = protocolHashForPeer(router, peer_a);
    var ph2 = protocolHashForPeer(router, peer_a);
    ph2[4] ^= 0xFF; // make it a different key but same slot (still local)
    const cp = dummy_counterparty;

    _ = try s.nextIndex(&ph1, &cp);
    _ = try s.nextIndex(&ph2, &cp);

    // Take a snapshot via the federated store.
    const snap = try s.snapshot(allocator);
    defer allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 2), snap.len);

    // Replay into a fresh local store via a second federated store.
    var local2 = LocalStateStore.init(allocator);
    defer local2.deinit();
    var rpc_log2 = RpcLog.init();
    var fed2 = FederatedSemantosStateStore.init(local2.store(), &router, peer_a, &rpc_log2);
    const s2 = fed2.store();

    try s2.replay(snap);

    // Both entries must be present in the replayed store.
    const v1 = s2.getIndex(&ph1, &cp);
    const v2 = s2.getIndex(&ph2, &cp);
    try std.testing.expect(v1 != null);
    try std.testing.expect(v2 != null);
    try std.testing.expectEqual(@as(u64, 0), v1.?);
    try std.testing.expectEqual(@as(u64, 0), v2.?);
}

```
