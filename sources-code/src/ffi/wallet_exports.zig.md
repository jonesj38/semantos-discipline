---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/wallet_exports.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.401158+00:00
---

# src/ffi/wallet_exports.zig

```zig
// wallet_exports.zig — Semantos FFI wallet C ABI exports.
//
// Implements the three wallet operations the mobile app calls via
// semantos_ffi (offline / embedded mode):
//
//   semantos_wallet_pay             — P2PKH payment tx
//   semantos_wallet_anchor_transition — spend a LINEAR cell anchor UTXO
//   semantos_wallet_identity_pubkey — return operator compressed pubkey hex
//
// These use bsvz for tx construction, BRC-42 key derivation, and ARC
// broadcast. The signing key is provided by the caller (stored in
// flutter_secure_storage; never embedded in the binary).
//
// Request + response shapes mirror POST /api/v1/wallet-op on brain
// (PLATFORM-WALLET-ARCHITECTURE.md §3.3) so the same call sites work
// against both the offline FFI and the online brain HTTP path.
//
// Error codes: SEMANTOS_OK (0), SEMANTOS_ERR_INVALID_JSON (-2),
// SEMANTOS_ERR_BUFFER_TOO_SMALL (-6), SEMANTOS_ERR_DENIED (-8).
//
// ARC URL used: https://arc.taal.com/v1/tx (same as brain default).

const std = @import("std");
const bsvz = @import("bsvz");

const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_INVALID_JSON: i32 = -2;
const SEMANTOS_ERR_BUFFER_TOO_SMALL: i32 = -6;
const SEMANTOS_ERR_DENIED: i32 = -8;

/// kdf-v3 (CW Lift L11.5) — UNILATERAL, DOMAIN-SEPARATED node derivation
/// (EP3259724B1 `deriveDomainSegment`, matching prof-faustus P2C `H(tag ‖ m)`):
///   child = parent + SHA-256( u32_be(domainFlag) ‖ segment ) mod n.
/// The 4-byte big-endian domainFlag binds the derived key to its declared
/// domain. The canonical, KAT-verified implementation lives at
/// runtime/semantos-brain/src/derive_segment.zig (proven byte-identical to the
/// Plexus TS SDK and the TS cell-anchor path). Inlined here because this FFI
/// build graph cannot import the brain module. No counterparty — the v0
/// self-ECDH (deriveChild with the operator's own pubkey) was a degenerate
/// BRC-42 misuse that this replaces; v2 omitted the flag.
fn deriveDomainSegmentSelf(
    parent: bsvz.primitives.ec.PrivateKey,
    domain_flag: u32,
    segment: []const u8,
) !bsvz.primitives.ec.PrivateKey {
    var tag: [4]u8 = undefined;
    std.mem.writeInt(u32, &tag, domain_flag, .big);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&tag);
    hasher.update(segment);
    var h: [32]u8 = undefined;
    hasher.final(&h);
    const n = @as(u512, std.mem.readInt(u256, &bsvz.primitives.ec.Secp256k1.params().n, .big));
    const a = @as(u512, std.mem.readInt(u256, &parent.toBytes(), .big));
    const b = @as(u512, std.mem.readInt(u256, &h, .big));
    const sum: u256 = @intCast((a + b) % n);
    var out: [32]u8 = undefined;
    std.mem.writeInt(u256, &out, sum, .big);
    return bsvz.primitives.ec.PrivateKey.fromBytes(out);
}

/// Sovereign per-cell-type domain flag (client-defined range) — byte-identical
/// to the TS `domainFlagFromTypeHash`: 0x00010000 | typeHash[0..2].
fn domainFlagFromTypeHash(type_hash: []const u8) u32 {
    return 0x00010000 |
        (@as(u32, type_hash[0]) << 16) |
        (@as(u32, type_hash[1]) << 8) |
        @as(u32, type_hash[2]);
}

const MAX_BODY: usize = 65_536;
const DEFAULT_ARC_URL = "https://arc.taal.com/v1/tx";
const FEE_SATS_PER_KB: u64 = 50;
const allocator = std.heap.c_allocator;

// ── semantos_wallet_identity_pubkey ────────────────────────────────────────
//
// Returns the operator's compressed public key as 66 lowercase hex chars.
//
// Parameters:
//   wif_ptr / wif_len — WIF-encoded signing key (UTF-8, no NUL terminator)
//   out_buf / out_cap — caller-owned buffer (must be >= 67 bytes for 66+NUL)
//   out_len           — written with number of bytes written (excl. NUL)
//
// Returns SEMANTOS_OK or SEMANTOS_ERR_DENIED (invalid WIF) /
//         SEMANTOS_ERR_BUFFER_TOO_SMALL.

pub export fn semantos_wallet_identity_pubkey(
    wif_ptr: [*]const u8,
    wif_len: usize,
    out_buf: [*]u8,
    out_cap: usize,
    out_len: *usize,
) callconv(.c) i32 {
    const wif = wif_ptr[0..wif_len];
    const wif_decoded = bsvz.compat.wif.decode(allocator, wif) catch return SEMANTOS_ERR_DENIED;
    const priv_ec = bsvz.primitives.ec.PrivateKey.fromBytes(wif_decoded.private_key.toBytes()) catch return SEMANTOS_ERR_DENIED;
    const pub_ec = priv_ec.publicKey() catch return SEMANTOS_ERR_DENIED;
    const pub_sec1 = pub_ec.toCompressedSec1();
    const hex = std.fmt.bytesToHex(pub_sec1, .lower);
    if (hex.len + 1 > out_cap) return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    @memcpy(out_buf[0..hex.len], &hex);
    out_buf[hex.len] = 0;
    out_len.* = hex.len;
    return SEMANTOS_OK;
}

// ── semantos_wallet_pay ────────────────────────────────────────────────────
//
// Builds a P2PKH payment tx from the given UTXO JSON + desired outputs JSON,
// signs, broadcasts via ARC, and writes the txid hex to out_txid.
//
// Parameters:
//   wif_ptr/len        — WIF signing key
//   utxos_json_ptr/len — JSON array of {txid, vout, satoshis, lockScript(hex)}
//   outputs_json_ptr/len — JSON array of {lockScript(hex), satoshis}
//   arc_url_ptr/len    — ARC endpoint (pass 0/0 for the default)
//   out_txid / cap     — 65-byte buffer (64 hex + NUL)
//   out_txid_len       — written with bytes written (excl. NUL)
//
// Returns SEMANTOS_OK or an error code.

pub export fn semantos_wallet_pay(
    wif_ptr: [*]const u8,
    wif_len: usize,
    utxos_json_ptr: [*]const u8,
    utxos_json_len: usize,
    outputs_json_ptr: [*]const u8,
    outputs_json_len: usize,
    arc_url_ptr: [*]const u8,
    arc_url_len: usize,
    out_txid: [*]u8,
    out_txid_cap: usize,
    out_txid_len: *usize,
) callconv(.c) i32 {
    const result = walletPay(
        wif_ptr[0..wif_len],
        utxos_json_ptr[0..utxos_json_len],
        outputs_json_ptr[0..outputs_json_len],
        if (arc_url_len > 0) arc_url_ptr[0..arc_url_len] else DEFAULT_ARC_URL,
        out_txid[0..out_txid_cap],
    ) catch return SEMANTOS_ERR_DENIED;
    if (result.len + 1 > out_txid_cap) return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    @memcpy(out_txid[0..result.len], result);
    out_txid[result.len] = 0;
    out_txid_len.* = result.len;
    return SEMANTOS_OK;
}

fn walletPay(
    wif: []const u8,
    utxos_json: []const u8,
    outputs_json: []const u8,
    arc_url: []const u8,
    _: []u8,
) ![]const u8 {
    const wif_decoded = try bsvz.compat.wif.decode(allocator, wif);
    const identity_priv = wif_decoded.private_key;
    const identity_priv_ec = try bsvz.primitives.ec.PrivateKey.fromBytes(identity_priv.toBytes());
    const identity_pub_ec = try identity_priv_ec.publicKey();
    const identity_pub_crypto = try identity_priv.publicKey();
    const change_addr = try bsvz.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, identity_pub_crypto);
    defer allocator.free(change_addr);
    _ = identity_pub_ec;

    const utxos_parsed = try std.json.parseFromSlice(std.json.Value, allocator, utxos_json, .{});
    defer utxos_parsed.deinit();
    const outputs_parsed = try std.json.parseFromSlice(std.json.Value, allocator, outputs_json, .{});
    defer outputs_parsed.deinit();

    if (utxos_parsed.value != .array or outputs_parsed.value != .array) return error.invalid_input;

    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    var total_in: u64 = 0;
    for (utxos_parsed.value.array.items) |utxo_val| {
        if (utxo_val != .object) return error.invalid_input;
        const u = utxo_val.object;
        const txid_hex = (u.get("txid") orelse return error.invalid_input).string;
        const vout: u32 = @intCast((u.get("vout") orelse return error.invalid_input).integer);
        const sats: u64 = @intCast((u.get("satoshis") orelse return error.invalid_input).integer);
        const ls_hex = (u.get("lockScript") orelse return error.invalid_input).string;
        var txid_bytes: [32]u8 = undefined;
        _ = try bsvz.primitives.hex.decodeInto(txid_hex, &txid_bytes);
        const ls_bytes = try bsvz.primitives.hex.decode(allocator, ls_hex);
        defer allocator.free(ls_bytes);
        const script = try bsvz.script.Script.init(ls_bytes).clone(allocator);
        try builder.addInput(.{
            .previous_outpoint = .{ .txid = .{ .bytes = txid_bytes }, .index = vout },
            .unlocking_script = bsvz.script.Script.empty(),
            .sequence = 0xffff_ffff,
            .source_output = .{ .satoshis = @intCast(sats), .locking_script = script },
            .source_transaction = null,
        });
        total_in += sats;
    }

    var total_out: u64 = 0;
    for (outputs_parsed.value.array.items) |out_val| {
        if (out_val != .object) return error.invalid_input;
        const o = out_val.object;
        const ls_hex = (o.get("lockScript") orelse return error.invalid_input).string;
        const sats: u64 = @intCast((o.get("satoshis") orelse return error.invalid_input).integer);
        const ls_bytes = try bsvz.primitives.hex.decode(allocator, ls_hex);
        defer allocator.free(ls_bytes);
        try builder.addOutput(.{
            .satoshis = @intCast(sats),
            .locking_script = try bsvz.script.Script.init(ls_bytes).clone(allocator),
        });
        total_out += sats;
    }

    if (total_in > total_out + 546) {
        try builder.payToAddress(change_addr, @intCast(total_in - total_out));
        builder.outputs.items[builder.outputs.items.len - 1].change = true;
    }

    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = FEE_SATS_PER_KB };
    try builder.applyFee(fee_model, .equal);

    const keys = [_]bsvz.crypto.PrivateKey{identity_priv};
    try builder.signAllP2pkh(&keys);

    var tx = try builder.build();
    defer tx.deinit(allocator);
    const raw = try tx.serialize(allocator);
    defer allocator.free(raw);
    const txid = try tx.txid(allocator);

    var arc: bsvz.broadcast.arc.Arc = .{ .api_url = arc_url };
    var tx2 = try bsvz.transaction.Transaction.parse(allocator, raw);
    defer tx2.deinit(allocator);
    var result = arc.broadcast(allocator, &tx2) catch return error.broadcast_failed;
    defer result.deinit(allocator);
    switch (result) {
        .ok => {},
        .err => return error.arc_rejected,
    }

    const txid_hex = std.fmt.bytesToHex(txid.bytes, .lower);
    const out = try allocator.dupe(u8, &txid_hex);
    return out;
}

// ── semantos_wallet_anchor_transition ─────────────────────────────────────
//
// Spends a LINEAR cell anchor UTXO. Derives the spending key via BRC-42
// self-ECDH, finds the anchor UTXO by matching the derived P2PKH script,
// builds + signs + broadcasts the transition tx.
//
// Parameters:
//   wif_ptr/len           — WIF signing key
//   type_hash_ptr/len     — 32-byte cell type hash (raw bytes, not hex)
//   anchor_index          — anchor slot index (u64)
//   anchor_utxos_json_ptr/len — JSON array of {txid, vout, satoshis} for
//                               cell-anchors basket UTXOs
//   arc_url_ptr/len       — ARC endpoint (0/0 = default)
//   out_txid / cap / len  — 65-byte txid output buffer
//
// Returns SEMANTOS_OK or an error code.

pub export fn semantos_wallet_anchor_transition(
    wif_ptr: [*]const u8,
    wif_len: usize,
    type_hash_ptr: [*]const u8,
    type_hash_len: usize,
    anchor_index: u64,
    anchor_utxos_json_ptr: [*]const u8,
    anchor_utxos_json_len: usize,
    arc_url_ptr: [*]const u8,
    arc_url_len: usize,
    out_txid: [*]u8,
    out_txid_cap: usize,
    out_txid_len: *usize,
) callconv(.c) i32 {
    if (type_hash_len != 32) return SEMANTOS_ERR_INVALID_JSON;
    var type_hash: [32]u8 = undefined;
    @memcpy(&type_hash, type_hash_ptr[0..32]);
    const result = anchorTransition(
        wif_ptr[0..wif_len],
        type_hash,
        anchor_index,
        anchor_utxos_json_ptr[0..anchor_utxos_json_len],
        if (arc_url_len > 0) arc_url_ptr[0..arc_url_len] else DEFAULT_ARC_URL,
        out_txid[0..out_txid_cap],
    ) catch return SEMANTOS_ERR_DENIED;
    if (result.len + 1 > out_txid_cap) return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    @memcpy(out_txid[0..result.len], result);
    out_txid[result.len] = 0;
    out_txid_len.* = result.len;
    return SEMANTOS_OK;
}

fn anchorTransition(
    wif: []const u8,
    type_hash: [32]u8,
    anchor_index: u64,
    anchor_utxos_json: []const u8,
    arc_url: []const u8,
    _: []u8,
) ![]const u8 {
    const wif_decoded = try bsvz.compat.wif.decode(allocator, wif);
    const identity_priv_crypto = wif_decoded.private_key;
    const identity_priv_ec = try bsvz.primitives.ec.PrivateKey.fromBytes(identity_priv_crypto.toBytes());
    // Anchor protocol hash: SHA256(hex(typeHash))[0:16]
    var proto_hash_input: [64]u8 = undefined;
    _ = try bsvz.primitives.hex.encodeLower(&type_hash, &proto_hash_input);
    var full_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&proto_hash_input, &full_sha, .{});
    const proto_hash_16: [16]u8 = full_sha[0..16].*;

    // deriveDomainSegment segment: protoHash(16) || anchorIndex_LE(8).
    // Byte-identical to the TS cell-anchor.ts invoice, so the PWA-derived and
    // FFI-derived anchor keys MATCH (unilateral; no pubkey, no ECDH).
    var invoice: [16 + 8]u8 = undefined;
    @memcpy(invoice[0..16], &proto_hash_16);
    std.mem.writeInt(u64, invoice[16..24], anchor_index, .little);

    // kdf-v3 (CW Lift L11.5): fold the sovereign per-cell-type domain flag into
    // the tweak so the anchor key is bound to the cell's declared header domain.
    // Byte-identical to TS deriveCellAnchorSk.
    const anchor_domain_flag = domainFlagFromTypeHash(&type_hash);
    const anchor_child_priv = try deriveDomainSegmentSelf(identity_priv_ec, anchor_domain_flag, &invoice);
    const anchor_child_pub = try anchor_child_priv.publicKey();
    const anchor_child_pub_sec1 = anchor_child_pub.toCompressedSec1();

    // Expected anchor P2PKH locking script
    const h160 = bsvz.crypto.hash.hash160(&anchor_child_pub_sec1);
    var anchor_lock: [25]u8 = undefined;
    anchor_lock[0] = 0x76;
    anchor_lock[1] = 0xa9;
    anchor_lock[2] = 0x14;
    @memcpy(anchor_lock[3..23], &h160.bytes);
    anchor_lock[23] = 0x88;
    anchor_lock[24] = 0xac;

    const utxos_parsed = try std.json.parseFromSlice(std.json.Value, allocator, anchor_utxos_json, .{});
    defer utxos_parsed.deinit();
    if (utxos_parsed.value != .array) return error.invalid_input;

    // Find matching anchor UTXO
    var anchor_txid: [32]u8 = undefined;
    var anchor_vout: u32 = 0;
    var anchor_sats: u64 = 0;
    var found = false;
    for (utxos_parsed.value.array.items) |utxo_val| {
        if (utxo_val != .object) continue;
        const u = utxo_val.object;
        const ls_hex = (u.get("lockScript") orelse continue).string;
        const ls_bytes = bsvz.primitives.hex.decode(allocator, ls_hex) catch continue;
        defer allocator.free(ls_bytes);
        if (!std.mem.eql(u8, ls_bytes, &anchor_lock)) continue;
        const txid_hex = (u.get("txid") orelse continue).string;
        _ = bsvz.primitives.hex.decodeInto(txid_hex, &anchor_txid) catch continue;
        anchor_vout = @intCast((u.get("vout") orelse continue).integer);
        anchor_sats = @intCast((u.get("satoshis") orelse continue).integer);
        found = true;
        break;
    }
    if (!found) return error.anchor_not_found;

    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    const anchor_ls = try bsvz.script.Script.init(&anchor_lock).clone(allocator);
    try builder.addInput(.{
        .previous_outpoint = .{ .txid = .{ .bytes = anchor_txid }, .index = anchor_vout },
        .unlocking_script = bsvz.script.Script.empty(),
        .sequence = 0xffff_ffff,
        .source_output = .{ .satoshis = @intCast(anchor_sats), .locking_script = anchor_ls },
        .source_transaction = null,
    });

    const identity_pub_crypto = try identity_priv_crypto.publicKey();
    const change_addr = try bsvz.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, identity_pub_crypto);
    defer allocator.free(change_addr);
    try builder.payToAddress(change_addr, @intCast(anchor_sats));
    builder.outputs.items[builder.outputs.items.len - 1].change = true;

    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = FEE_SATS_PER_KB };
    try builder.applyFee(fee_model, .equal);

    const anchor_child_crypto = try bsvz.crypto.PrivateKey.fromBytes(anchor_child_priv.toBytes());
    const anchor_keys = [_]bsvz.crypto.PrivateKey{anchor_child_crypto};
    try builder.signAllP2pkh(&anchor_keys);

    var tx = try builder.build();
    defer tx.deinit(allocator);
    const raw = try tx.serialize(allocator);
    defer allocator.free(raw);
    const txid = try tx.txid(allocator);

    var arc: bsvz.broadcast.arc.Arc = .{ .api_url = arc_url };
    var tx2 = try bsvz.transaction.Transaction.parse(allocator, raw);
    defer tx2.deinit(allocator);
    var result = arc.broadcast(allocator, &tx2) catch return error.broadcast_failed;
    defer result.deinit(allocator);
    switch (result) {
        .ok => {},
        .err => return error.arc_rejected,
    }

    const txid_hex = std.fmt.bytesToHex(txid.bytes, .lower);
    return try allocator.dupe(u8, &txid_hex);
}

```
