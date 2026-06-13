---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/federated_output_store_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.193525+00:00
---

# runtime/semantos-brain/tests/federated_output_store_test.zig

```zig
// M7.2 — FederatedSemantosOutputStore conformance tests.
//
// TDD red phase: these tests are written against the interface contract
// before the implementation exists.  They will fail until the green commit
// lands `federated_output_store.zig` and `rpc_log.zig`.

const std = @import("std");
const output_store = @import("output_store");
const fed_output_store = @import("federated_output_store");
const rpc_log_mod = @import("rpc_log");
const slot_router_mod = @import("slot_router");

const OutputStore = output_store.OutputStore;
const OutputRecord = output_store.OutputRecord;
const Outpoint = output_store.Outpoint;
const LocalOutputStore = output_store.LocalOutputStore;
const FederatedSemantosOutputStore = fed_output_store.FederatedSemantosOutputStore;
const RpcLog = rpc_log_mod.RpcLog;
const SlotRouter = slot_router_mod.SlotRouter;

// ── Helper: build a minimal OutputRecord ──────────────────────────────────

fn makeRecord(txid: [32]u8, vout: u32, sat: u64) OutputRecord {
    return .{
        .outpoint = .{ .txid = txid, .vout = vout },
        .satoshis = sat,
        .locking_script = &[_]u8{ 0x76, 0xa9 },
        .derived_key_hash = [_]u8{0} ** 32,
        .derivation_protocol_hash = [_]u8{0} ** 16,
        .derivation_counterparty = [_]u8{0} ** 33,
        .derivation_index = 0,
        .beef = &[_]u8{},
        .basket = "default",
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 0,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
}

// Slot derivation mirrors the impl: bytes 0–3 of txid as u32 LE.
fn slotOf(txid: [32]u8) u32 {
    return std.mem.readInt(u32, txid[0..4], .little);
}

// ── Test helpers ──────────────────────────────────────────────────────────

/// Build a 2-peer router and return (peer_a, peer_b).
/// peer_a = [0x01**32], peer_b = [0x02**32].
fn makePeers() struct { a: [32]u8, b: [32]u8 } {
    return .{
        .a = [_]u8{0x01} ** 32,
        .b = [_]u8{0x02} ** 32,
    };
}

/// Build a txid whose slot maps to `want_peer` given a 2-peer router with
/// peers = {peer_a, peer_b}.  We scan txids until we find one with the
/// right routing.
fn txidForPeer(router: SlotRouter, want_peer: [32]u8) [32]u8 {
    var txid = [_]u8{0} ** 32;
    var n: u32 = 0;
    while (n < 0xFFFF) : (n += 1) {
        std.mem.writeInt(u32, txid[0..4], n, .little);
        const got = router.slotToPeer(slotOf(txid)) catch continue;
        if (std.mem.eql(u8, &got, &want_peer)) return txid;
    }
    unreachable; // should always find one within 65k slots for 2 peers
}

// ── M7.2-T-local-write ────────────────────────────────────────────────────
//
// Slot routes to local peer → addOutput delegates to local store; rpc_log empty.

test "M7.2-T-local-write" {
    const allocator = std.testing.allocator;

    const peers_data = makePeers();
    const peers = [_][32]u8{ peers_data.a, peers_data.b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosOutputStore.init(local.store(), &router, peers_data.a, &rpc_log);
    const s = fed.store();

    // Find a txid whose slot routes to local peer (peer_a).
    const txid = txidForPeer(router, peers_data.a);
    const rec = makeRecord(txid, 0, 1000);

    try s.addOutput(rec);

    // rpc_log must be empty — this was a local write.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);

    // The local store must hold the record.
    const got = local.store().getOutput(.{ .txid = txid, .vout = 0 });
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 1000), got.?.satoshis);
}

// ── M7.2-T-remote-write ───────────────────────────────────────────────────
//
// Slot routes to remote peer → rpc_log has one write_output entry with the
// correct peer_id; local store is empty.

test "M7.2-T-remote-write" {
    const allocator = std.testing.allocator;

    const peers_data = makePeers();
    const peers = [_][32]u8{ peers_data.a, peers_data.b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    // We are peer_a; write a record that routes to peer_b.
    var fed = FederatedSemantosOutputStore.init(local.store(), &router, peers_data.a, &rpc_log);
    const s = fed.store();

    const txid = txidForPeer(router, peers_data.b);
    const rec = makeRecord(txid, 0, 2000);

    try s.addOutput(rec);

    // rpc_log must have exactly one entry.
    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(rpc_log_mod.RpcEntry.Op.write_output, entries[0].op);
    try std.testing.expectEqualSlices(u8, &peers_data.b, &entries[0].peer_id);

    // Local store must be empty.
    const local_list = try local.store().listOutputs(null, null, allocator);
    defer allocator.free(local_list);
    try std.testing.expectEqual(@as(usize, 0), local_list.len);
}

// ── M7.2-T-local-read ─────────────────────────────────────────────────────
//
// addOutput locally; getOutput finds it via the federated store.

test "M7.2-T-local-read" {
    const allocator = std.testing.allocator;

    const peers_data = makePeers();
    const peers = [_][32]u8{ peers_data.a, peers_data.b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosOutputStore.init(local.store(), &router, peers_data.a, &rpc_log);
    const s = fed.store();

    const txid = txidForPeer(router, peers_data.a);
    const rec = makeRecord(txid, 0, 5000);

    try s.addOutput(rec);
    rpc_log.clear();

    // getOutput must return the record.
    const got = s.getOutput(.{ .txid = txid, .vout = 0 });
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 5000), got.?.satoshis);

    // No remote reads needed.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);
}

// ── M7.2-T-remote-read ────────────────────────────────────────────────────
//
// getOutput for remotely-owned slot → rpc_log has a read_output entry; returns null.

test "M7.2-T-remote-read" {
    const allocator = std.testing.allocator;

    const peers_data = makePeers();
    const peers = [_][32]u8{ peers_data.a, peers_data.b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosOutputStore.init(local.store(), &router, peers_data.a, &rpc_log);
    const s = fed.store();

    // Find a txid that routes to peer_b (remote).
    const txid = txidForPeer(router, peers_data.b);

    // Ask for a record that's not local.
    const got = s.getOutput(.{ .txid = txid, .vout = 0 });
    try std.testing.expect(got == null); // stub returns null

    // rpc_log must record a remote read.
    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(rpc_log_mod.RpcEntry.Op.read_output, entries[0].op);
    try std.testing.expectEqualSlices(u8, &peers_data.b, &entries[0].peer_id);
}

// ── M7.2-T-mark-spent ─────────────────────────────────────────────────────
//
// markSpent on locally-owned slot; local store reflects spent status.

test "M7.2-T-mark-spent" {
    const allocator = std.testing.allocator;

    const peers_data = makePeers();
    const peers = [_][32]u8{ peers_data.a, peers_data.b };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosOutputStore.init(local.store(), &router, peers_data.a, &rpc_log);
    const s = fed.store();

    const txid = txidForPeer(router, peers_data.a);
    const rec = makeRecord(txid, 0, 3000);
    try s.addOutput(rec);
    rpc_log.clear();

    const spending = [_]u8{0xAB} ** 32;
    try s.markSpent(.{ .txid = txid, .vout = 0 }, spending);

    // Local store must reflect spent.
    const after = local.store().getOutput(.{ .txid = txid, .vout = 0 });
    try std.testing.expect(after != null);
    try std.testing.expectEqual(output_store.OutputStatus.spent, after.?.status);
    try std.testing.expectEqualSlices(u8, &spending, &after.?.spending_txid);

    // No remote RPCs needed.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);
}

```
