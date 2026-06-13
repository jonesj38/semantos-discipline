---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/wallet_op_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.448486+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/wallet_op_http.zig

```zig
// wallet_op_http.zig — POST /api/v1/wallet-op structured wallet action endpoint.
//
// Reference: docs/design/PLATFORM-WALLET-ARCHITECTURE.md §3.2 (wallet-op endpoint).
//
// Internal REST endpoint called by the oddjobz intent pipeline after
// contact resolution. Bearer-gated; Caddy must NOT proxy this path
// externally (localhost-only by design — the operator's brain process is
// the only caller in normal operation).
//
// Request:
//   POST /api/v1/wallet-op
//   Authorization: Bearer <hex64>
//   Content-Type: application/json
//
//   pay:
//     {"action":"pay","outputs":[{"lockScript":"<hex>","satoshis":1000}],"description":"..."}
//
//   anchorTransition:
//     {"action":"anchorTransition","typeHash":"<hex>","anchorIndex":0,"newStateHash":"<hex>"}
//
//   createAction:
//     {"action":"createAction","outputs":[...],"inputs":[{"txid":"<hex>","vout":N}],"description":"..."}
//
// Response 200:
//   {"txid":"<hex>"}
//
// Response 400/401/500:
//   {"error":"<reason>"}

const std = @import("std");
const bsvz = @import("bsvz");
const bearer_tokens = @import("bearer_tokens");
const output_store_mod = @import("output_store");

// Re-export bearer header parser from repl_http (inline duplicate to avoid
// circular dep — repl_http is a sibling module, not a dep of wallet_op_http).
const MAX_BODY = 65_536;

/// ARC endpoint used when Acceptor.arc_url is empty.
pub const DEFAULT_ARC_URL = "https://arc.taal.com/v1/tx";

/// Fee model: 50 sats/KB — ARC's recommended safe default for BSV.
const FEE_SATS_PER_KB: u64 = 50;

/// kdf-v3 (CW Lift L11.5) — UNILATERAL, DOMAIN-SEPARATED node derivation
/// (EP3259724B1 `deriveDomainSegment`, matching prof-faustus P2C `H(tag ‖ m)`):
///   child = parent + SHA-256( u32_be(domainFlag) ‖ segment ) mod n.
/// The 4-byte big-endian domainFlag binds the derived key to its declared
/// domain. The canonical, KAT-verified implementation lives at
/// runtime/semantos-brain/src/derive_segment.zig (proven byte-identical to the
/// Plexus TS SDK and the TS cell-anchor path). Inlined here because this
/// cartridge build graph cannot import the brain module. No counterparty — the
/// v0 self-ECDH (deriveChild with the operator's own pubkey) was a degenerate
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

pub const AcceptorError = error{
    out_of_memory,
    write_failed,
};

/// State the wallet-op endpoint needs. All pointer fields are borrowed;
/// caller (typically cmdServe) owns the lifetimes.
pub const Acceptor = struct {
    /// Bearer-token store shared with the REPL + wallet WSS endpoints.
    tokens: *bearer_tokens.TokenStore,
    /// Output store vtable — used for UTXO selection (pay/anchorTransition).
    outputs: output_store_mod.OutputStore,
    /// WIF-encoded operator private key.  When empty the pay + createAction
    /// actions return 503 "signing key not configured".
    signing_key_wif: []const u8,
    /// ARC endpoint URL.  Falls back to DEFAULT_ARC_URL when empty.
    arc_url: []const u8,
};

/// Plug into site_server.handleRequest.  Returns true iff matched + handled.
pub fn maybeHandle(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
) !bool {
    const target = request.head.target;
    if (!std.mem.eql(u8, target, "/api/v1/wallet-op")) return false;

    if (request.head.method != .POST) {
        try respondJson(request, .method_not_allowed, "{\"error\":\"POST required\"}");
        return true;
    }

    // ── Bearer auth ──────────────────────────────────────────────────────
    const auth_header = headerValue(request, "authorization") orelse {
        try respondJson(request, .unauthorized, "{\"error\":\"missing bearer token\"}");
        return true;
    };
    const bearer_hex = parseBearerHeader(auth_header) orelse {
        try respondJson(request, .unauthorized, "{\"error\":\"malformed Authorization header\"}");
        return true;
    };
    _ = acceptor.tokens.verifyHex(bearer_hex) catch |err| {
        const msg = switch (err) {
            error.expired => "{\"error\":\"bearer token expired\"}",
            error.bad_format => "{\"error\":\"bearer token must be 64 hex chars\"}",
            else => "{\"error\":\"bearer token not recognised\"}",
        };
        try respondJson(request, .unauthorized, msg);
        return true;
    };

    // ── Body parse ────────────────────────────────────────────────────────
    var body_buf: [MAX_BODY]u8 = undefined;
    const body = readBody(request, &body_buf) catch {
        try respondJson(request, .bad_request, "{\"error\":\"failed to read request body\"}");
        return true;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        try respondJson(request, .bad_request, "{\"error\":\"body must be valid JSON\"}");
        return true;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        try respondJson(request, .bad_request, "{\"error\":\"body must be a JSON object\"}");
        return true;
    }
    const obj = parsed.value.object;

    const action_val = obj.get("action") orelse {
        try respondJson(request, .bad_request, "{\"error\":\"missing required field: action\"}");
        return true;
    };
    if (action_val != .string) {
        try respondJson(request, .bad_request, "{\"error\":\"action must be a string\"}");
        return true;
    }
    const action = action_val.string;

    // ── Dispatch ─────────────────────────────────────────────────────────
    if (std.mem.eql(u8, action, "pay")) {
        dispatchPay(allocator, request, acceptor, obj) catch |err| {
            const msg = try std.fmt.allocPrint(
                allocator,
                "{{\"error\":\"pay failed: {s}\"}}",
                .{@errorName(err)},
            );
            defer allocator.free(msg);
            try respondJson(request, .internal_server_error, msg);
        };
        return true;
    }

    if (std.mem.eql(u8, action, "anchorTransition")) {
        dispatchAnchorTransition(allocator, request, acceptor, obj) catch |err| {
            const msg = try std.fmt.allocPrint(
                allocator,
                "{{\"error\":\"anchorTransition failed: {s}\"}}",
                .{@errorName(err)},
            );
            defer allocator.free(msg);
            try respondJson(request, .internal_server_error, msg);
        };
        return true;
    }

    if (std.mem.eql(u8, action, "createAction")) {
        dispatchCreateAction(allocator, request, acceptor, obj) catch |err| {
            const msg = try std.fmt.allocPrint(
                allocator,
                "{{\"error\":\"createAction failed: {s}\"}}",
                .{@errorName(err)},
            );
            defer allocator.free(msg);
            try respondJson(request, .internal_server_error, msg);
        };
        return true;
    }

    const msg = try std.fmt.allocPrint(
        allocator,
        "{{\"error\":\"unknown action: {s}\"}}",
        .{action},
    );
    defer allocator.free(msg);
    try respondJson(request, .bad_request, msg);
    return true;
}

// ── Action: pay ────────────────────────────────────────────────────────────
//
// Builds a transaction that pays the given outputs (lock scripts + satoshis)
// from the wallet's UTXO pool, adding change back to the operator's address.
// Broadcasts via ARC and returns { txid }.

fn dispatchPay(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
    obj: std.json.ObjectMap,
) !void {
    if (acceptor.signing_key_wif.len == 0) {
        try respondJson(request, .service_unavailable,
            "{\"error\":\"signing_key_wif not configured in site.json\"}");
        return;
    }

    // 1. Parse outputs array.
    const outputs_val = obj.get("outputs") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"pay requires 'outputs' array\"}");
        return;
    };
    if (outputs_val != .array) {
        try respondJson(request, .bad_request,
            "{\"error\":\"outputs must be an array\"}");
        return;
    }
    const outputs_arr = outputs_val.array.items;
    if (outputs_arr.len == 0) {
        try respondJson(request, .bad_request,
            "{\"error\":\"outputs must not be empty\"}");
        return;
    }

    // 2. Decode WIF → private key + public key → change address.
    const wif_decoded = bsvz.compat.wif.decode(allocator, acceptor.signing_key_wif) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"invalid signing_key_wif in site.json\"}");
        return;
    };
    const identity_priv = wif_decoded.private_key;
    const identity_pub = identity_priv.publicKey() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to derive public key from signing_key_wif\"}");
        return;
    };
    const change_addr = bsvz.compat.address.encodeP2pkhFromPublicKey(
        allocator, .mainnet, identity_pub,
    ) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to derive change address\"}");
        return;
    };
    defer allocator.free(change_addr);

    // 3. Parse desired outputs.
    const ParsedOutput = struct {
        lock_script_hex: []const u8,
        satoshis: u64,
    };
    var desired = std.ArrayList(ParsedOutput).init(allocator);
    defer desired.deinit();
    var total_out_sats: u64 = 0;
    for (outputs_arr) |out_val| {
        if (out_val != .object) {
            try respondJson(request, .bad_request,
                "{\"error\":\"each output must be an object {lockScript, satoshis}\"}");
            return;
        }
        const out_obj = out_val.object;
        const ls_val = out_obj.get("lockScript") orelse {
            try respondJson(request, .bad_request,
                "{\"error\":\"output missing lockScript\"}");
            return;
        };
        const sats_val = out_obj.get("satoshis") orelse {
            try respondJson(request, .bad_request,
                "{\"error\":\"output missing satoshis\"}");
            return;
        };
        if (ls_val != .string) {
            try respondJson(request, .bad_request,
                "{\"error\":\"lockScript must be a hex string\"}");
            return;
        }
        const sats: u64 = switch (sats_val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => {
                try respondJson(request, .bad_request,
                    "{\"error\":\"satoshis must be a number\"}");
                return;
            },
        };
        try desired.append(.{ .lock_script_hex = ls_val.string, .satoshis = sats });
        total_out_sats += sats;
    }

    // 4. Select UTXOs to cover total_out_sats + fee estimate.
    //    Use a simple greedy selection (largest first).
    const all_utxos = acceptor.outputs.listOutputs(null, null, allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to list UTXOs from output store\"}");
        return;
    };
    defer {
        for (all_utxos) |rec| {
            allocator.free(rec.locking_script);
            allocator.free(rec.beef);
            allocator.free(rec.basket);
            allocator.free(rec.tags);
            allocator.free(rec.custom_instructions);
        }
        allocator.free(all_utxos);
    }

    // Filter to unspent.
    var unspent = std.ArrayList(output_store_mod.OutputRecord).init(allocator);
    defer unspent.deinit();
    for (all_utxos) |rec| {
        if (rec.status == .unspent) try unspent.append(rec);
    }

    // Sort descending by satoshis (largest first → fewest inputs needed).
    std.sort.pdq(output_store_mod.OutputRecord, unspent.items, {}, struct {
        fn lessThan(_: void, a: output_store_mod.OutputRecord, b: output_store_mod.OutputRecord) bool {
            return a.satoshis > b.satoshis;
        }
    }.lessThan);

    // Estimate fee for a 2-output tx (desired + change) + N inputs.
    // BSV P2PKH input ≈ 148 bytes, output ≈ 34 bytes, overhead 10 bytes.
    const FEE_PER_INPUT: u64 = (148 * FEE_SATS_PER_KB + 999) / 1000;
    const FEE_BASE: u64 = (10 + 34 * (@as(u64, desired.items.len) + 1)) * FEE_SATS_PER_KB / 1000 + 1;
    var selected = std.ArrayList(output_store_mod.OutputRecord).init(allocator);
    defer selected.deinit();
    var total_in_sats: u64 = 0;
    for (unspent.items) |rec| {
        try selected.append(rec);
        total_in_sats += rec.satoshis;
        const fee_est = FEE_BASE + FEE_PER_INPUT * selected.items.len;
        if (total_in_sats >= total_out_sats + fee_est) break;
    }
    if (total_in_sats < total_out_sats + 1) {
        try respondJson(request, .unprocessable_entity,
            "{\"error\":\"insufficient funds in output store\"}");
        return;
    }

    // 5. Build tx.
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    for (selected.items) |rec| {
        const ls_bytes = bsvz.primitives.hex.decode(allocator, rec.locking_script) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"failed to hex-decode locking_script from output store\"}");
            return;
        };
        defer allocator.free(ls_bytes);

        var txid_display: [32]u8 = undefined;
        _ = bsvz.primitives.hex.decodeInto(
            &(std.fmt.bytesToHex(rec.outpoint.txid, .lower)),
            &txid_display,
        ) catch {};
        // Output store stores txid in internal order — use directly.
        const outpoint: bsvz.transaction.OutPoint = .{
            .txid = .{ .bytes = rec.outpoint.txid },
            .index = rec.outpoint.vout,
        };
        const source_out = bsvz.transaction.Output{
            .satoshis = @intCast(rec.satoshis),
            .locking_script = bsvz.script.Script.init(ls_bytes).clone(allocator) catch {
                try respondJson(request, .internal_server_error,
                    "{\"error\":\"out of memory building tx input\"}");
                return;
            },
        };
        const input = bsvz.transaction.Input{
            .previous_outpoint = outpoint,
            .unlocking_script = bsvz.script.Script.empty(),
            .sequence = 0xffff_ffff,
            .source_output = source_out,
            .source_transaction = null,
        };
        builder.addInput(input) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"out of memory adding tx input\"}");
            return;
        };
    }

    // Add desired outputs.
    for (desired.items) |out| {
        const ls_bytes = bsvz.primitives.hex.decode(allocator, out.lock_script_hex) catch {
            try respondJson(request, .bad_request,
                "{\"error\":\"lockScript is not valid hex\"}");
            return;
        };
        defer allocator.free(ls_bytes);
        const script = bsvz.script.Script.init(ls_bytes).clone(allocator) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"out of memory adding tx output\"}");
            return;
        };
        builder.addOutput(.{
            .satoshis = @intCast(out.satoshis),
            .locking_script = script,
        }) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"out of memory adding tx output\"}");
            return;
        };
    }

    // Add change output.
    const change_sats: u64 = total_in_sats - total_out_sats;
    if (change_sats > 546) { // dust threshold
        builder.payToAddress(change_addr, @intCast(change_sats)) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"failed to add change output\"}");
            return;
        };
        builder.outputs.items[builder.outputs.items.len - 1].change = true;
    }

    // Apply fee.
    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = FEE_SATS_PER_KB };
    builder.applyFee(fee_model, .equal) catch {
        try respondJson(request, .unprocessable_entity,
            "{\"error\":\"insufficient funds to cover fee\"}");
        return;
    };

    // Sign all P2PKH inputs.
    const identity_priv_ec = bsvz.primitives.ec.PrivateKey.fromBytes(identity_priv.toBytes()) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to load signing key\"}");
        return;
    };
    const keys = [_]bsvz.crypto.PrivateKey{identity_priv};
    _ = identity_priv_ec; // used via crypto.PrivateKey below
    builder.signAllP2pkh(&keys) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"signing failed\"}");
        return;
    };

    // Serialize + broadcast.
    var tx = builder.build() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to build transaction\"}");
        return;
    };
    defer tx.deinit(allocator);
    const raw = tx.serialize(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to serialize transaction\"}");
        return;
    };
    defer allocator.free(raw);

    const txid = tx.txid(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to compute txid\"}");
        return;
    };
    const txid_hex = std.fmt.bytesToHex(txid.bytes, .lower);

    const arc_url = if (acceptor.arc_url.len > 0) acceptor.arc_url else DEFAULT_ARC_URL;
    const outcome = broadcastViaArc(allocator, raw, arc_url) catch {
        try respondJson(request, .bad_gateway,
            "{\"error\":\"ARC broadcast failed\"}");
        return;
    };
    defer if (outcome.detail.len > 0) allocator.free(outcome.detail);

    if (!outcome.ok) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "{{\"error\":\"ARC rejected tx: {s}\"}}",
            .{outcome.detail},
        );
        defer allocator.free(msg);
        try respondJson(request, .bad_gateway, msg);
        return;
    }

    // Mark selected UTXOs as spent.
    for (selected.items) |rec| {
        acceptor.outputs.markSpent(rec.outpoint, txid.bytes) catch {};
    }

    const resp = try std.fmt.allocPrint(
        allocator, "{{\"txid\":\"{s}\"}}", .{txid_hex},
    );
    defer allocator.free(resp);
    try respondJson(request, .ok, resp);
}

// ── Action: anchorTransition ───────────────────────────────────────────────
//
// Spends the LINEAR cell anchor UTXO for the given (typeHash, anchorIndex)
// pair.  Derives the spending key via BRC-42 using self-ECDH against the
// operator's identity key and the cell type's protocol hash.

fn dispatchAnchorTransition(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
    obj: std.json.ObjectMap,
) !void {
    if (acceptor.signing_key_wif.len == 0) {
        try respondJson(request, .service_unavailable,
            "{\"error\":\"signing_key_wif not configured in site.json\"}");
        return;
    }

    // 1. Parse fields.
    const type_hash_hex_val = obj.get("typeHash") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"anchorTransition requires typeHash\"}");
        return;
    };
    if (type_hash_hex_val != .string) {
        try respondJson(request, .bad_request,
            "{\"error\":\"typeHash must be a hex string\"}");
        return;
    }
    const type_hash_hex = type_hash_hex_val.string;

    const anchor_index_val = obj.get("anchorIndex") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"anchorTransition requires anchorIndex\"}");
        return;
    };
    const anchor_index: u64 = switch (anchor_index_val) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        else => {
            try respondJson(request, .bad_request,
                "{\"error\":\"anchorIndex must be a number\"}");
            return;
        },
    };

    // Optional newStateHash for OP_RETURN output.
    const new_state_hash_hex: ?[]const u8 = if (obj.get("newStateHash")) |v|
        if (v == .string) v.string else null
    else
        null;

    // 2. Decode WIF → identity key pair.
    const wif_decoded = bsvz.compat.wif.decode(allocator, acceptor.signing_key_wif) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"invalid signing_key_wif in site.json\"}");
        return;
    };
    const identity_priv_crypto = wif_decoded.private_key;
    const identity_priv_ec = bsvz.primitives.ec.PrivateKey.fromBytes(
        identity_priv_crypto.toBytes(),
    ) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to load identity private key\"}");
        return;
    };
    // 3. Compute anchor protocol hash: SHA256(hex(typeHash))[0:16].
    const type_hash_bytes = bsvz.primitives.hex.decode(allocator, type_hash_hex) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"typeHash is not valid hex\"}");
        return;
    };
    defer allocator.free(type_hash_bytes);
    if (type_hash_bytes.len != 32) {
        try respondJson(request, .bad_request,
            "{\"error\":\"typeHash must be exactly 32 bytes (64 hex chars)\"}");
        return;
    }

    // anchorProtocolHash = SHA256(hex(typeHash))[0:16]
    // "hex(typeHash)" means the UTF-8 encoded lowercase hex string of typeHash bytes.
    var proto_hash_input: [64]u8 = undefined;
    _ = bsvz.primitives.hex.encodeLower(type_hash_bytes, &proto_hash_input) catch unreachable;
    var full_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&proto_hash_input, &full_sha, .{});
    const proto_hash_16: [16]u8 = full_sha[0..16].*;

    // 4. deriveDomainSegment segment: proto_hash(16) || anchorIndex_LE(8).
    // Byte-identical to the TS cell-anchor.ts invoice, so the PWA-derived and
    // brain-derived anchor keys MATCH (unilateral; no pubkey, no ECDH).
    var invoice: [16 + 8]u8 = undefined;
    @memcpy(invoice[0..16], &proto_hash_16);
    std.mem.writeInt(u64, invoice[16..24], anchor_index, .little);

    // 5. kdf-v3 (CW Lift L11.5): fold the sovereign per-cell-type domain flag
    // (domainFlagFromTypeHash) into the tweak so the anchor key is bound to the
    // cell's declared header domain. Byte-identical to TS deriveCellAnchorSk.
    const anchor_domain_flag = domainFlagFromTypeHash(type_hash_bytes);
    const anchor_child_priv = deriveDomainSegmentSelf(identity_priv_ec, anchor_domain_flag, &invoice) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"anchor key derivation failed\"}");
        return;
    };
    const anchor_child_pub = anchor_child_priv.publicKey() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to derive anchor child public key\"}");
        return;
    };
    const anchor_child_pub_sec1 = anchor_child_pub.toCompressedSec1();

    // 6. Compute the expected P2PKH locking script for the anchor UTXO.
    //    hash160 = RIPEMD160(SHA256(pubkey))
    var sha_of_pub: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&anchor_child_pub_sec1, &sha_of_pub, .{});
    var hash160: [20]u8 = undefined;
    std.crypto.hash.Ripemd160.hash(&sha_of_pub, &hash160, .{});
    // P2PKH locking script: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
    var anchor_lock: [25]u8 = undefined;
    anchor_lock[0] = 0x76; // OP_DUP
    anchor_lock[1] = 0xa9; // OP_HASH160
    anchor_lock[2] = 0x14; // push 20 bytes
    @memcpy(anchor_lock[3..23], &hash160);
    anchor_lock[23] = 0x88; // OP_EQUALVERIFY
    anchor_lock[24] = 0xac; // OP_CHECKSIG

    // 7. Find the anchor UTXO in the output store.
    const all_utxos = acceptor.outputs.listOutputs("cell-anchors", null, allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to list anchor UTXOs from output store\"}");
        return;
    };
    defer {
        for (all_utxos) |rec| {
            allocator.free(rec.locking_script);
            allocator.free(rec.beef);
            allocator.free(rec.basket);
            allocator.free(rec.tags);
            allocator.free(rec.custom_instructions);
        }
        allocator.free(all_utxos);
    }

    var anchor_rec: ?output_store_mod.OutputRecord = null;
    for (all_utxos) |rec| {
        if (rec.status != .unspent) continue;
        const ls_bytes = bsvz.primitives.hex.decode(allocator, rec.locking_script) catch continue;
        defer allocator.free(ls_bytes);
        if (std.mem.eql(u8, ls_bytes, &anchor_lock)) {
            anchor_rec = rec;
            break;
        }
    }

    const anchor = anchor_rec orelse {
        try respondJson(request, .not_found,
            "{\"error\":\"anchor UTXO not found in output store for given typeHash+anchorIndex\"}");
        return;
    };

    // 8. Build the anchor transition tx.
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    // Anchor input.
    const anchor_ls = bsvz.script.Script.init(&anchor_lock).clone(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"out of memory cloning anchor locking script\"}");
        return;
    };
    const anchor_source = bsvz.transaction.Output{
        .satoshis = @intCast(anchor.satoshis),
        .locking_script = anchor_ls,
    };
    builder.addInput(.{
        .previous_outpoint = .{
            .txid = .{ .bytes = anchor.outpoint.txid },
            .index = anchor.outpoint.vout,
        },
        .unlocking_script = bsvz.script.Script.empty(),
        .sequence = 0xffff_ffff,
        .source_output = anchor_source,
        .source_transaction = null,
    }) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"out of memory building anchor tx input\"}");
        return;
    };

    // Optional OP_RETURN with newStateHash (best-effort; skip on any error).
    if (new_state_hash_hex) |nsh_hex| op_ret: {
        const nsh = bsvz.primitives.hex.decode(allocator, nsh_hex) catch break :op_ret;
        defer allocator.free(nsh);
        // OP_FALSE OP_RETURN <len> <newStateHash>
        const op_ret_len = 3 + nsh.len;
        const buf = allocator.alloc(u8, op_ret_len) catch break :op_ret;
        defer allocator.free(buf);
        buf[0] = 0x00; // OP_FALSE
        buf[1] = 0x6a; // OP_RETURN
        buf[2] = @intCast(nsh.len);
        @memcpy(buf[3..], nsh);
        const script = bsvz.script.Script.init(buf).clone(allocator) catch break :op_ret;
        builder.addOutput(.{ .satoshis = 0, .locking_script = script }) catch {};
    }

    // Change back to operator address (fee from anchor satoshis).
    const identity_pub_crypto = identity_priv_crypto.publicKey() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to derive identity public key for change\"}");
        return;
    };
    const change_addr = bsvz.compat.address.encodeP2pkhFromPublicKey(
        allocator, .mainnet, identity_pub_crypto,
    ) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to derive change address\"}");
        return;
    };
    defer allocator.free(change_addr);

    builder.payToAddress(change_addr, @intCast(anchor.satoshis)) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to add change output to anchor tx\"}");
        return;
    };
    builder.outputs.items[builder.outputs.items.len - 1].change = true;

    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = FEE_SATS_PER_KB };
    builder.applyFee(fee_model, .equal) catch {
        try respondJson(request, .unprocessable_entity,
            "{\"error\":\"anchor UTXO has insufficient satoshis to cover fee\"}");
        return;
    };

    // Sign with anchor child key (wraps the ec key as a crypto key for Builder).
    const anchor_child_crypto = bsvz.crypto.PrivateKey.fromBytes(anchor_child_priv.toBytes()) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to wrap anchor child key for signing\"}");
        return;
    };
    const anchor_keys = [_]bsvz.crypto.PrivateKey{anchor_child_crypto};
    builder.signAllP2pkh(&anchor_keys) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"anchor transition signing failed\"}");
        return;
    };

    var tx = builder.build() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to build anchor transition tx\"}");
        return;
    };
    defer tx.deinit(allocator);
    const raw = tx.serialize(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to serialize anchor transition tx\"}");
        return;
    };
    defer allocator.free(raw);

    const txid = tx.txid(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to compute txid\"}");
        return;
    };
    const txid_hex = std.fmt.bytesToHex(txid.bytes, .lower);

    const arc_url = if (acceptor.arc_url.len > 0) acceptor.arc_url else DEFAULT_ARC_URL;
    const outcome = broadcastViaArc(allocator, raw, arc_url) catch {
        try respondJson(request, .bad_gateway,
            "{\"error\":\"ARC broadcast failed for anchor transition\"}");
        return;
    };
    defer if (outcome.detail.len > 0) allocator.free(outcome.detail);

    if (!outcome.ok) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "{{\"error\":\"ARC rejected anchor tx: {s}\"}}",
            .{outcome.detail},
        );
        defer allocator.free(msg);
        try respondJson(request, .bad_gateway, msg);
        return;
    }

    acceptor.outputs.markSpent(anchor.outpoint, txid.bytes) catch {};

    const resp = try std.fmt.allocPrint(
        allocator, "{{\"txid\":\"{s}\"}}", .{txid_hex},
    );
    defer allocator.free(resp);
    try respondJson(request, .ok, resp);
}

// ── Action: createAction ───────────────────────────────────────────────────
//
// General-purpose spend: caller provides explicit inputs + outputs.
// Inputs with no unlocking script are signed with the operator's identity key.

fn dispatchCreateAction(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
    obj: std.json.ObjectMap,
) !void {
    if (acceptor.signing_key_wif.len == 0) {
        try respondJson(request, .service_unavailable,
            "{\"error\":\"signing_key_wif not configured in site.json\"}");
        return;
    }

    const inputs_val = obj.get("inputs") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"createAction requires 'inputs' array\"}");
        return;
    };
    const outputs_val = obj.get("outputs") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"createAction requires 'outputs' array\"}");
        return;
    };
    if (inputs_val != .array or outputs_val != .array) {
        try respondJson(request, .bad_request,
            "{\"error\":\"inputs and outputs must be arrays\"}");
        return;
    }

    const wif_decoded = bsvz.compat.wif.decode(allocator, acceptor.signing_key_wif) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"invalid signing_key_wif in site.json\"}");
        return;
    };
    const identity_priv = wif_decoded.private_key;

    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    for (inputs_val.array.items) |inp_val| {
        if (inp_val != .object) {
            try respondJson(request, .bad_request,
                "{\"error\":\"each input must be {txid, vout, lockScript?, satoshis?}\"}");
            return;
        }
        const inp = inp_val.object;
        const txid_hex_val = inp.get("txid") orelse {
            try respondJson(request, .bad_request, "{\"error\":\"input missing txid\"}");
            return;
        };
        const vout_val = inp.get("vout") orelse {
            try respondJson(request, .bad_request, "{\"error\":\"input missing vout\"}");
            return;
        };
        if (txid_hex_val != .string) {
            try respondJson(request, .bad_request, "{\"error\":\"input txid must be a hex string\"}");
            return;
        }
        const vout: u32 = switch (vout_val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => {
                try respondJson(request, .bad_request, "{\"error\":\"input vout must be a number\"}");
                return;
            },
        };

        var txid_bytes: [32]u8 = undefined;
        _ = bsvz.primitives.hex.decodeInto(txid_hex_val.string, &txid_bytes) catch {
            try respondJson(request, .bad_request, "{\"error\":\"input txid is not valid 32-byte hex\"}");
            return;
        };

        // Source output for sigHash (required by bsvz signer).
        const ls_val = inp.get("lockScript");
        const sats_val = inp.get("satoshis");
        var source_out: bsvz.transaction.Output = undefined;
        if (ls_val != null and sats_val != null and ls_val.? == .string) {
            const ls_bytes = bsvz.primitives.hex.decode(allocator, ls_val.?.string) catch {
                try respondJson(request, .bad_request, "{\"error\":\"input lockScript is not valid hex\"}");
                return;
            };
            defer allocator.free(ls_bytes);
            const sats: u64 = switch (sats_val.?) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => 0,
            };
            source_out = .{
                .satoshis = @intCast(sats),
                .locking_script = bsvz.script.Script.init(ls_bytes).clone(allocator) catch {
                    try respondJson(request, .internal_server_error,
                        "{\"error\":\"out of memory cloning locking script\"}");
                    return;
                },
            };
        } else {
            // No source output provided — signing will fail for P2PKH inputs.
            // This is acceptable when the caller supplies a pre-signed unlocking script.
            source_out = .{
                .satoshis = 0,
                .locking_script = bsvz.script.Script.empty(),
            };
        }

        builder.addInput(.{
            .previous_outpoint = .{ .txid = .{ .bytes = txid_bytes }, .index = vout },
            .unlocking_script = bsvz.script.Script.empty(),
            .sequence = 0xffff_ffff,
            .source_output = source_out,
            .source_transaction = null,
        }) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"out of memory adding input\"}");
            return;
        };
    }

    for (outputs_val.array.items) |out_val| {
        if (out_val != .object) {
            try respondJson(request, .bad_request,
                "{\"error\":\"each output must be {lockScript, satoshis}\"}");
            return;
        }
        const out = out_val.object;
        const ls_val = out.get("lockScript") orelse {
            try respondJson(request, .bad_request, "{\"error\":\"output missing lockScript\"}");
            return;
        };
        const sats_val = out.get("satoshis") orelse {
            try respondJson(request, .bad_request, "{\"error\":\"output missing satoshis\"}");
            return;
        };
        if (ls_val != .string) {
            try respondJson(request, .bad_request, "{\"error\":\"output lockScript must be hex\"}");
            return;
        }
        const sats: u64 = switch (sats_val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => {
                try respondJson(request, .bad_request, "{\"error\":\"output satoshis must be a number\"}");
                return;
            },
        };
        const ls_bytes = bsvz.primitives.hex.decode(allocator, ls_val.string) catch {
            try respondJson(request, .bad_request, "{\"error\":\"output lockScript is not valid hex\"}");
            return;
        };
        defer allocator.free(ls_bytes);
        builder.addOutput(.{
            .satoshis = @intCast(sats),
            .locking_script = bsvz.script.Script.init(ls_bytes).clone(allocator) catch {
                try respondJson(request, .internal_server_error,
                    "{\"error\":\"out of memory adding output\"}");
                return;
            },
        }) catch {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"out of memory adding output\"}");
            return;
        };
    }

    const keys = [_]bsvz.crypto.PrivateKey{identity_priv};
    builder.signAllP2pkh(&keys) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"signing failed\"}");
        return;
    };

    var tx = builder.build() catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to build transaction\"}");
        return;
    };
    defer tx.deinit(allocator);
    const raw = tx.serialize(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to serialize transaction\"}");
        return;
    };
    defer allocator.free(raw);

    const txid = tx.txid(allocator) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"failed to compute txid\"}");
        return;
    };
    const txid_hex = std.fmt.bytesToHex(txid.bytes, .lower);

    const arc_url = if (acceptor.arc_url.len > 0) acceptor.arc_url else DEFAULT_ARC_URL;
    const outcome = broadcastViaArc(allocator, raw, arc_url) catch {
        try respondJson(request, .bad_gateway,
            "{\"error\":\"ARC broadcast failed\"}");
        return;
    };
    defer if (outcome.detail.len > 0) allocator.free(outcome.detail);

    if (!outcome.ok) {
        const msg = try std.fmt.allocPrint(
            allocator, "{{\"error\":\"ARC rejected tx: {s}\"}}", .{outcome.detail},
        );
        defer allocator.free(msg);
        try respondJson(request, .bad_gateway, msg);
        return;
    }

    const resp = try std.fmt.allocPrint(
        allocator, "{{\"txid\":\"{s}\"}}", .{txid_hex},
    );
    defer allocator.free(resp);
    try respondJson(request, .ok, resp);
}

// ── ARC broadcast (mirror of refund_tx.broadcastViaArc) ──────────────────

const BroadcastOutcome = struct {
    ok: bool,
    detail: []u8,
};

fn broadcastViaArc(
    allocator: std.mem.Allocator,
    raw_tx: []const u8,
    arc_url: []const u8,
) !BroadcastOutcome {
    var tx = bsvz.transaction.Transaction.parse(allocator, raw_tx) catch return error.broadcast_failed;
    defer tx.deinit(allocator);
    var arc: bsvz.broadcast.arc.Arc = .{ .api_url = arc_url };
    var result = arc.broadcast(allocator, &tx) catch return error.broadcast_failed;
    defer result.deinit(allocator);
    return switch (result) {
        .success => |s| blk: {
            const detail = try allocator.dupe(u8, s.txid);
            break :blk .{ .ok = true, .detail = detail };
        },
        .failure => |f| blk: {
            const detail = try std.fmt.allocPrint(
                allocator, "{s}", .{@tagName(f.status)},
            );
            break :blk .{ .ok = false, .detail = detail };
        },
    };
}

// ── HTTP helpers (inline — avoids circular dep on repl_http) ─────────────

fn respondJson(
    request: *std.http.Server.Request,
    status: std.http.Status,
    body: []const u8,
) !void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return error.write_failed;
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn parseBearerHeader(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t");
    if (!std.mem.startsWith(u8, trimmed, "Bearer ") and
        !std.mem.startsWith(u8, trimmed, "bearer ")) return null;
    const tok = std.mem.trim(u8, trimmed[7..], " \t");
    if (tok.len != 64) return null;
    for (tok) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return null;
    }
    return tok;
}

fn readBody(request: *std.http.Server.Request, out: []u8) ![]const u8 {
    const reader = request.readerExpectNone(out);
    const n = reader.readSliceShort(out) catch |err| switch (err) {
        else => return err,
    };
    return out[0..n];
}

```
