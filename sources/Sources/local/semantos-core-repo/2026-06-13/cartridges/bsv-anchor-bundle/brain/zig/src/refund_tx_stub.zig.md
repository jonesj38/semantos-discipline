---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/refund_tx_stub.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.449100+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/refund_tx_stub.zig

```zig
// Phase WSITE5.5 — refund_tx stub (built when bsvz is unavailable).
//
// Mirrors the public surface of `refund_tx.zig` so `cli.zig` can
// import `refund_tx` unconditionally.  Every entry returns
// `error.bsvz_unavailable`.

const std = @import("std");

pub const RefundError = error{
    bsvz_unavailable,
    bad_wif,
    bad_payer_pubkey,
    bad_locking_script,
    insufficient_funds,
    sign_failed,
    serialize_failed,
    out_of_memory,
    broadcast_failed,
};

pub const BuiltRefund = struct {
    raw_bytes: []u8 = &.{},
    txid_display: [32]u8 = [_]u8{0} ** 32,
    output_satoshis: u64 = 0,
    fee_satoshis: u64 = 0,
};

pub fn freeBuiltRefund(allocator: std.mem.Allocator, refund: BuiltRefund) void {
    if (refund.raw_bytes.len > 0) allocator.free(refund.raw_bytes);
}

pub fn buildRefund(
    allocator: std.mem.Allocator,
    wif: []const u8,
    utxo_txid: [32]u8,
    utxo_vout: u32,
    utxo_locking_script: []const u8,
    utxo_satoshis: u64,
    payer_pubkey: [33]u8,
    fee_sats_per_kb: u64,
) RefundError!BuiltRefund {
    _ = allocator;
    _ = wif;
    _ = utxo_txid;
    _ = utxo_vout;
    _ = utxo_locking_script;
    _ = utxo_satoshis;
    _ = payer_pubkey;
    _ = fee_sats_per_kb;
    return error.bsvz_unavailable;
}

pub const BroadcastOutcome = struct {
    ok: bool = false,
    detail: []u8 = &.{},
};

pub fn freeBroadcastOutcome(allocator: std.mem.Allocator, outcome: BroadcastOutcome) void {
    if (outcome.detail.len > 0) allocator.free(outcome.detail);
}

pub fn broadcastViaArc(
    allocator: std.mem.Allocator,
    raw_tx: []const u8,
    arc_url: []const u8,
    api_key: ?[]const u8,
) RefundError!BroadcastOutcome {
    _ = allocator;
    _ = raw_tx;
    _ = arc_url;
    _ = api_key;
    return error.bsvz_unavailable;
}

```
