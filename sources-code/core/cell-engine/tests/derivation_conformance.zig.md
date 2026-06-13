---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/derivation_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.959791+00:00
---

# core/cell-engine/tests/derivation_conformance.zig

```zig
// Phase W3.5: DerivationStateStore + host_derive_leaf + host_state_next_index
// conformance tests. Reference: docs/design/SEMANTOS-WALLET-TIERED-CUSTODY.md
// §3.5, §6.4.
//
// Runs in the FULL profile (BSVZ linked). The embedded native build cannot
// derive without the host extern (TS runtime supplies it).

const std = @import("std");
const host = @import("host");
const derivation_state = @import("derivation_state");
const bsvz = @import("bsvz");

// ── DerivationStateStore: monotonic next_index per context ──

test "LocalStateStore: next_index starts at 0 and increments per context" {
    var store_impl = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const protocol_a: [16]u8 = [_]u8{0xAA} ** 16;
    const counterparty_x: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x02;
        b[32] = 0x42;
        break :blk b;
    };

    try std.testing.expectEqual(@as(u64, 0), try store.nextIndex(&protocol_a, &counterparty_x));
    try std.testing.expectEqual(@as(u64, 1), try store.nextIndex(&protocol_a, &counterparty_x));
    try std.testing.expectEqual(@as(u64, 2), try store.nextIndex(&protocol_a, &counterparty_x));
}

test "LocalStateStore: contexts are independent — separate counters" {
    var store_impl = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const protocol_a: [16]u8 = [_]u8{0xAA} ** 16;
    const protocol_b: [16]u8 = [_]u8{0xBB} ** 16;
    const counterparty_x: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x02;
        b[32] = 0x42;
        break :blk b;
    };

    _ = try store.nextIndex(&protocol_a, &counterparty_x);
    _ = try store.nextIndex(&protocol_a, &counterparty_x);
    _ = try store.nextIndex(&protocol_a, &counterparty_x);

    // Different protocol — new counter starting at 0.
    try std.testing.expectEqual(@as(u64, 0), try store.nextIndex(&protocol_b, &counterparty_x));
    // Original protocol — picks up at 3.
    try std.testing.expectEqual(@as(u64, 3), try store.nextIndex(&protocol_a, &counterparty_x));
}

test "LocalStateStore: get_index returns null until first allocation" {
    var store_impl = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const protocol: [16]u8 = [_]u8{0xCC} ** 16;
    const counterparty: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x03;
        break :blk b;
    };

    try std.testing.expectEqual(@as(?u64, null), store.getIndex(&protocol, &counterparty));
    _ = try store.nextIndex(&protocol, &counterparty);
    try std.testing.expectEqual(@as(?u64, 0), store.getIndex(&protocol, &counterparty));
}

test "LocalStateStore: snapshot + replay round-trip preserves all records" {
    var store_a = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_a.deinit();
    const store_a_dyn = store_a.store();

    const proto1: [16]u8 = [_]u8{0x11} ** 16;
    const proto2: [16]u8 = [_]u8{0x22} ** 16;
    const cp1: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x02;
        b[1] = 0xAB;
        break :blk b;
    };
    const cp2: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x03;
        b[1] = 0xCD;
        break :blk b;
    };

    _ = try store_a_dyn.nextIndex(&proto1, &cp1); // proto1/cp1 → 0
    _ = try store_a_dyn.nextIndex(&proto1, &cp1); // → 1
    _ = try store_a_dyn.nextIndex(&proto2, &cp2); // proto2/cp2 → 0

    const snapshot = try store_a_dyn.snapshot(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);

    var store_b = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_b.deinit();
    const store_b_dyn = store_b.store();
    try store_b_dyn.replay(snapshot);

    // After replay, b's counters should be identical to a's.
    try std.testing.expectEqual(@as(?u64, 1), store_b_dyn.getIndex(&proto1, &cp1));
    try std.testing.expectEqual(@as(?u64, 0), store_b_dyn.getIndex(&proto2, &cp2));
}

// ── host_derive_leaf: deterministic + matches bsvz directly ──

test "host.deriveLeaf: deterministic — same inputs produce same leaf" {
    const base_sk: [32]u8 = blk: {
        var k: [32]u8 = [_]u8{0} ** 32;
        k[31] = 0x55;
        break :blk k;
    };
    const protocol: [16]u8 = [_]u8{0xEE} ** 16;
    const counterparty: [33]u8 = blk: {
        const cp_priv = try bsvz.primitives.ec.PrivateKey.fromBytes([_]u8{0x77} ** 32);
        const cp_pub = try cp_priv.publicKey();
        break :blk cp_pub.toCompressedSec1();
    };

    var leaf_a: [32]u8 = undefined;
    var leaf_b: [32]u8 = undefined;
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, 0, &leaf_a));
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, 0, &leaf_b));
    try std.testing.expectEqualSlices(u8, &leaf_a, &leaf_b);
}

test "host.deriveLeaf: different indices produce different leaves" {
    const base_sk: [32]u8 = blk: {
        var k: [32]u8 = [_]u8{0} ** 32;
        k[31] = 0x55;
        break :blk k;
    };
    const protocol: [16]u8 = [_]u8{0xEE} ** 16;
    const counterparty: [33]u8 = blk: {
        const cp_priv = try bsvz.primitives.ec.PrivateKey.fromBytes([_]u8{0x77} ** 32);
        const cp_pub = try cp_priv.publicKey();
        break :blk cp_pub.toCompressedSec1();
    };

    var leaf_0: [32]u8 = undefined;
    var leaf_1: [32]u8 = undefined;
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, 0, &leaf_0));
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, 1, &leaf_1));
    try std.testing.expect(!std.mem.eql(u8, &leaf_0, &leaf_1));
}

test "host.deriveLeaf: leaf differs from base" {
    const base_sk: [32]u8 = blk: {
        var k: [32]u8 = [_]u8{0} ** 32;
        k[31] = 0x55;
        break :blk k;
    };
    const protocol: [16]u8 = [_]u8{0xEE} ** 16;
    const counterparty: [33]u8 = blk: {
        const cp_priv = try bsvz.primitives.ec.PrivateKey.fromBytes([_]u8{0x77} ** 32);
        const cp_pub = try cp_priv.publicKey();
        break :blk cp_pub.toCompressedSec1();
    };

    var leaf: [32]u8 = undefined;
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, 7, &leaf));
    try std.testing.expect(!std.mem.eql(u8, &base_sk, &leaf));
}

// ── host.stateNextIndex: integrates with installed store ──

test "host.stateNextIndex: returns false when no store installed" {
    host.clearDerivationStateStore();
    var idx: u64 = 0;
    const proto: [16]u8 = [_]u8{0} ** 16;
    const cp: [33]u8 = [_]u8{0} ** 33;
    try std.testing.expect(!host.stateNextIndex(&proto, &cp, &idx));
}

test "host.stateNextIndex: with installed store, allocates monotonic indices" {
    var store_impl = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_impl.deinit();
    const store = store_impl.store();
    host.setDerivationStateStore(&store);
    defer host.clearDerivationStateStore();

    var idx: u64 = 999;
    const proto: [16]u8 = [_]u8{0xAB} ** 16;
    const cp: [33]u8 = blk: {
        var b: [33]u8 = [_]u8{0} ** 33;
        b[0] = 0x02;
        break :blk b;
    };
    try std.testing.expect(host.stateNextIndex(&proto, &cp, &idx));
    try std.testing.expectEqual(@as(u64, 0), idx);
    try std.testing.expect(host.stateNextIndex(&proto, &cp, &idx));
    try std.testing.expectEqual(@as(u64, 1), idx);
    try std.testing.expect(host.stateNextIndex(&proto, &cp, &idx));
    try std.testing.expectEqual(@as(u64, 2), idx);
}

// ── DerivationState cell pack/unpack round-trip ──

test "DerivationState cell: pack then unpack round-trips records" {
    const records = [_]derivation_state.Record{
        .{
            .protocol_hash = [_]u8{0x01} ** 16,
            .counterparty = blk: {
                var b: [33]u8 = [_]u8{0} ** 33;
                b[0] = 0x02;
                b[32] = 0x10;
                break :blk b;
            },
            .current_index = 7,
        },
        .{
            .protocol_hash = [_]u8{0x02} ** 16,
            .counterparty = blk: {
                var b: [33]u8 = [_]u8{0} ** 33;
                b[0] = 0x03;
                b[32] = 0x20;
                break :blk b;
            },
            .current_index = 99,
        },
    };

    var payload: [768]u8 = [_]u8{0} ** 768;
    const written = try derivation_state.packPayload(&records, &payload);
    try std.testing.expect(written > 0);

    const decoded = try derivation_state.unpackPayload(payload[0..written], std.testing.allocator);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqual(records.len, decoded.len);
    for (records, decoded) |orig, got| {
        try std.testing.expectEqualSlices(u8, &orig.protocol_hash, &got.protocol_hash);
        try std.testing.expectEqualSlices(u8, &orig.counterparty, &got.counterparty);
        try std.testing.expectEqual(orig.current_index, got.current_index);
    }
}

test "DerivationState cell: pack rejects records that exceed buffer" {
    var many: [20]derivation_state.Record = undefined;
    for (&many, 0..) |*r, i| {
        r.protocol_hash = [_]u8{@intCast(i)} ** 16;
        r.counterparty = [_]u8{0} ** 33;
        r.current_index = @intCast(i);
    }
    // 20 records × 57 bytes + 16 header = 1156 > 768 payload
    var payload: [768]u8 = undefined;
    try std.testing.expectError(error.out_of_memory, derivation_state.packPayload(&many, &payload));
}

// ── End-to-end: store + derive + sign + verify ──

test "end-to-end: stateNextIndex + deriveLeaf produce a key whose pubkey verifies a signature" {
    var store_impl = derivation_state.LocalStateStore.init(std.testing.allocator);
    defer store_impl.deinit();
    const store = store_impl.store();
    host.setDerivationStateStore(&store);
    defer host.clearDerivationStateStore();

    const base_sk: [32]u8 = blk: {
        var k: [32]u8 = [_]u8{0} ** 32;
        k[31] = 0x88;
        break :blk k;
    };
    const protocol: [16]u8 = [_]u8{0x12} ** 16;
    const counterparty: [33]u8 = blk: {
        const cp_priv = try bsvz.primitives.ec.PrivateKey.fromBytes([_]u8{0x34} ** 32);
        const cp_pub = try cp_priv.publicKey();
        break :blk cp_pub.toCompressedSec1();
    };

    var idx: u64 = 0;
    try std.testing.expect(host.stateNextIndex(&protocol, &counterparty, &idx));

    var leaf: [32]u8 = undefined;
    try std.testing.expect(host.deriveLeaf(&base_sk, &protocol, &counterparty, idx, &leaf));

    // Sign a digest with the leaf.
    const digest: [32]u8 = [_]u8{0xDD} ** 32;
    var sig_buf: [72]u8 = undefined;
    var sig_len: u32 = 0;
    try std.testing.expect(host.sign(&leaf, &digest, &sig_buf, &sig_len));

    // Verify against the leaf's pubkey.
    const leaf_priv = try bsvz.primitives.ec.PrivateKey.fromBytes(leaf);
    const leaf_pub_sec1 = (try leaf_priv.publicKey()).toCompressedSec1();
    const verified = bsvz.crypto.verifyDigest256RelaxedSec1(&leaf_pub_sec1, digest, sig_buf[0..sig_len]) catch false;
    try std.testing.expect(verified);
}

```
