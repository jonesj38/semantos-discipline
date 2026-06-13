---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/refund_tx.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.447272+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/refund_tx.zig

```zig
// Phase WSITE5.5 — refund transaction construction + broadcast.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE5
// deferred work / WSITE5.5 deliverables).
//
// Builds a 1-input → 1-output P2PKH transaction that refunds a
// previously-internalised payment back to the payer.  Inputs:
//
//   • The verified UTXO from the OutputStore — outpoint + locking
//     script + satoshis.
//   • The payer's compressed SEC1 pubkey, used to derive the P2PKH
//     address the refund pays to.
//   • The operator's signing key (WIF-encoded; sourced from
//     `site.json`'s `signing_key_wif`).
//
// Output: raw signed transaction bytes + computed txid.  Caller
// broadcasts via `broadcastViaArc`.
//
// Why a separate file rather than inline in `cli.zig`: the bsvz
// transaction surface is deep (Builder, Input, Output, fee models,
// p2pkh templates).  Encapsulating here keeps `cli.zig` focused on
// argv parsing + workflow orchestration.
//
// Build gating: same as payment_verifier — the real implementation
// links bsvz; the stub in `refund_tx_stub.zig` returns
// `error.bsvz_unavailable` so the disabled-build path stays compilable.

const std = @import("std");
const bsvz = @import("bsvz");

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
    /// Raw serialized transaction bytes.  Allocator-owned.
    raw_bytes: []u8,
    /// 32-byte txid in display order (block-explorer convention).
    txid_display: [32]u8,
    /// Net amount the payer receives, after fee.
    output_satoshis: u64,
    /// Computed fee in satoshis.
    fee_satoshis: u64,
};

pub fn freeBuiltRefund(allocator: std.mem.Allocator, refund: BuiltRefund) void {
    allocator.free(refund.raw_bytes);
}

/// Construct + sign a refund transaction.  Caller frees `BuiltRefund.raw_bytes`.
///
///   wif:                    WIF-encoded private key for the operator (signs the input)
///   utxo_txid:              32-byte txid (display/big-endian) of the input UTXO
///   utxo_vout:              vout of the input UTXO
///   utxo_locking_script:    raw locking script bytes from the OutputStore record
///   utxo_satoshis:          satoshis of the input UTXO
///   payer_pubkey:           33-byte compressed SEC1 pubkey to refund to
///   fee_sats_per_kb:        fee model (50 sats/KB is reasonable for BSV; ARC's recommended default)
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
    // 1. Decode the operator's WIF.
    const wif_decoded = bsvz.compat.wif.decode(allocator, wif) catch return error.bad_wif;
    const private_key = wif_decoded.private_key;

    // 2. Derive the payer's P2PKH address so we can build a payToAddress
    //    output.  bsvz's compat layer handles the SEC1 → hash160 →
    //    base58check encoding.
    const payer_pub = bsvz.crypto.PublicKey.fromSec1(&payer_pubkey) catch return error.bad_payer_pubkey;
    const payer_address_text = bsvz.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, payer_pub) catch return error.bad_payer_pubkey;
    defer allocator.free(payer_address_text);

    // 3. Build the tx.  The Input carries the UTXO's source_output so
    //    bsvz can sigHash the prevout correctly during sign.
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    // Bsvz expects txid as Hash256 (display order — matches our
    // OutputStore convention).
    const input_outpoint: bsvz.transaction.OutPoint = .{
        .txid = .{ .bytes = utxo_txid },
        .index = utxo_vout,
    };
    const source_output = bsvz.transaction.Output{
        .satoshis = @intCast(utxo_satoshis),
        .locking_script = bsvz.script.Script.init(utxo_locking_script).clone(allocator) catch return error.out_of_memory,
    };
    const input = bsvz.transaction.Input{
        .previous_outpoint = input_outpoint,
        .unlocking_script = bsvz.script.Script.empty(),
        .sequence = 0xffff_ffff,
        .source_output = source_output,
        .source_transaction = null,
    };
    builder.addInput(input) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };

    // 4. Output: pay everything back to the payer.  We start with the
    //    full input satoshis; `applyFee` deducts the fee from the
    //    change output.  Mark the output as `change=true` so applyFee
    //    knows where to take the fee from (we treat the refund
    //    itself as the change output since there's no other change
    //    destination).
    builder.payToAddress(payer_address_text, @intCast(utxo_satoshis)) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.serialize_failed,
    };
    // Mark it as change so the fee comes out of it (otherwise applyFee
    // requires a separate change output).
    builder.outputs.items[0].change = true;

    // 5. Apply fee using a sats/KB model.
    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = fee_sats_per_kb };
    builder.applyFee(fee_model, .equal) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        error.Overflow => return error.insufficient_funds,
        else => return error.serialize_failed,
    };

    // 6. Sign all P2PKH inputs with the operator's key.
    const keys = [_]bsvz.crypto.PrivateKey{private_key};
    builder.signAllP2pkh(&keys) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.sign_failed,
    };

    // 7. Build the final tx + serialize.
    var tx = builder.build() catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };
    defer tx.deinit(allocator);

    const raw = tx.serialize(allocator) catch return error.serialize_failed;
    errdefer allocator.free(raw);

    const txid_chain = tx.txid(allocator) catch return error.serialize_failed;
    const fee = bsvz.transaction.fees.getFee(&tx) catch utxo_satoshis;
    const out_sats = utxo_satoshis -| fee;

    return .{
        .raw_bytes = raw,
        .txid_display = txid_chain.bytes,
        .output_satoshis = out_sats,
        .fee_satoshis = fee,
    };
}

/// Broadcast raw transaction bytes to BSV via an ARC endpoint.
/// Default endpoint is Taal's public ARC at https://arc.taal.com/v1/tx
/// (free up to a quota; configurable via `arc_url`).  Returns an
/// allocator-owned status string (`txid` from `BroadcastSuccess` on
/// success, error code on failure).  `result_status` lets the caller
/// know which path; raw-bytes return so we don't expose bsvz types
/// to call sites.
pub const BroadcastOutcome = struct {
    ok: bool = false,
    /// Allocator-owned.  Either a hex txid (success) or an error code
    /// like "ARC_REJECTED" (failure).  Caller frees.
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
    // bsvz's Arc takes a *Transaction (not raw bytes), so re-parse.
    var tx = bsvz.transaction.Transaction.parse(allocator, raw_tx) catch return error.broadcast_failed;
    defer tx.deinit(allocator);

    var arc: bsvz.broadcast.arc.Arc = .{
        .api_url = arc_url,
        .api_key = api_key orelse "",
    };
    var result = arc.broadcast(allocator, &tx) catch return error.broadcast_failed;
    defer result.deinit(allocator);

    return switch (result) {
        .ok => |s| .{
            .ok = true,
            .detail = allocator.dupe(u8, s.txid) catch return error.out_of_memory,
        },
        .err => |e| .{
            .ok = false,
            .detail = allocator.dupe(u8, e.code) catch return error.out_of_memory,
        },
    };
}

```
