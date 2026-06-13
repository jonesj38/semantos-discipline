---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/gen_pair_vector.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.170391+00:00
---

# runtime/semantos-brain/tools/gen_pair_vector.zig

```zig
// D-O5p — Pair-vector generator.
//
// Emits `cartridges/oddjobz/brain/tests/vectors/device-pair/v2-fixture.json`
// containing a deterministic v2 pairing token + the reference BRC-42
// child pubkey + the BRC-42 invoice bytes — the cross-language parity
// fixture that the TS stub mobile client (cartridges/oddjobz/brain/tests/
// device-pair-roundtrip.test.ts) loads + asserts against.
//
// Run via: `cd runtime/semantos-brain && zig build gen-pair-vector`.
//
// Why this file is needed: the operator-side payload is signed by
// the operator's secp256k1 priv key.  TS-only fixtures can't
// reproduce the signature deterministically without a private key,
// and we don't want to leak a real key into the test surface.
// Instead, we pin a deterministic seed-derived priv on the Zig side
// (the same path the bkds_vectors fixture uses), generate the
// signed token + the expected child pubkey here, and the TS fixture
// asserts byte-for-byte parity.

const std = @import("std");
const bkds = @import("bkds");
const device_pair = @import("device_pair");

const OPERATOR_SEED = "operator-root-todd-2026";
const DEVICE_SEED = "device-iphone-2026";
const CONTEXT_TAG: u8 = 0x10; // carpenter
const LABEL = "Todd's iPhone";
const NONCE_HEX = "deadbeefcafef00d0011223344556677";
const EXPIRES_AT: i64 = 1_900_000_000; // far-future, well past 2026-05-01
const BRAIN_PAIR_ENDPOINT = "https://oddjobtodd.info/api/v1/device-pair";
const BRAIN_WSS_ENDPOINT = "wss://oddjobtodd.info/api/v1/wallet";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) {
        std.debug.print("usage: gen_pair_vector <out_path>\n", .{});
        return;
    }
    const out_path = args[1];

    // Operator keys.
    const op_priv = bkds.privFromSeed(OPERATOR_SEED);
    const op_pub = try bkds.pubFromSeed(OPERATOR_SEED);
    var op_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&op_pub, &op_pub_hex);
    var op_priv_hex: [bkds.PRIVKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&op_priv, &op_priv_hex);

    // Operator cert id = sha256(pubkey)[0..16] hex (mirroring
    // identity_certs.certIdFromPubkey).
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&op_pub, &hash, .{});
    var cert_id_hex: [32]u8 = undefined;
    bkds.hexEncode(hash[0..16], &cert_id_hex);

    // Device keys.
    const dev_priv = bkds.privFromSeed(DEVICE_SEED);
    const dev_pub = try bkds.pubFromSeed(DEVICE_SEED);
    var dev_priv_hex: [bkds.PRIVKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&dev_priv, &dev_priv_hex);
    var dev_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&dev_pub, &dev_pub_hex);

    // Build the BRC-42 invoice for this pairing.
    var invoice_buf: [bkds.MAX_INVOICE_LEN]u8 = undefined;
    const invoice_bytes = try bkds.buildInvoice(CONTEXT_TAG, LABEL, &invoice_buf);
    const invoice_hex = try allocator.alloc(u8, invoice_bytes.len * 2);
    defer allocator.free(invoice_hex);
    bkds.hexEncode(invoice_bytes, invoice_hex);

    // Compute the expected child pubkey — this is what the device
    // submits as `derivation_pubkey` in the accept request.
    const child_pub = try bkds.deriveChildPubkeyFromDevice(dev_priv, op_pub, CONTEXT_TAG, LABEL);
    var child_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&child_pub, &child_pub_hex);

    // Decode nonce hex into 16 bytes.
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    try bkds.hexDecode(NONCE_HEX, &nonce);

    // Build + sign the v2 payload.
    const caps = [_][]const u8{
        "cap.attach.photo",
        "cap.attach.gps",
        "cap.attach.voice",
    };
    const payload = device_pair.PairPayload{
        .operator_root_cert_id = cert_id_hex,
        .operator_root_pub = op_pub,
        .context_tag = CONTEXT_TAG,
        .label = LABEL,
        .capabilities = &caps,
        .expires_at = EXPIRES_AT,
        .nonce = nonce,
        .brain_pair_endpoint = BRAIN_PAIR_ENDPOINT,
        .brain_wss_endpoint = BRAIN_WSS_ENDPOINT,
        .brain_pin_cert_id = cert_id_hex,
        .brain_pin_pubkey = op_pub,
    };
    var token = try device_pair.signAndEncode(allocator, payload, op_priv);
    defer token.deinit(allocator);

    // Build cap-list JSON for the fixture (one item per line for
    // readability).
    var caps_json: std.ArrayList(u8) = .{};
    defer caps_json.deinit(allocator);
    try caps_json.append(allocator, '[');
    for (caps, 0..) |c, i| {
        if (i != 0) try caps_json.appendSlice(allocator, ",\n      ");
        try caps_json.append(allocator, '"');
        try caps_json.appendSlice(allocator, c);
        try caps_json.append(allocator, '"');
    }
    try caps_json.append(allocator, ']');

    // Emit fixture JSON.
    const out = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out.close();
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.print(allocator,
        \\{{
        \\  "notes": [
        \\    "D-O5p — cross-language pairing fixture",
        \\    "Regenerated via `cd runtime/semantos-brain && zig build gen-pair-vector`",
        \\    "Pinned seeds: operator='operator-root-todd-2026', device='device-iphone-2026'",
        \\    "Pinned nonce, expires_at — payload bytes deterministic across runs"
        \\  ],
        \\  "operator": {{
        \\    "seed": "{s}",
        \\    "privHex": "{s}",
        \\    "pubHex": "{s}",
        \\    "certIdHex": "{s}"
        \\  }},
        \\  "device": {{
        \\    "seed": "{s}",
        \\    "privHex": "{s}",
        \\    "pubHex": "{s}"
        \\  }},
        \\  "payload": {{
        \\    "contextTag": {d},
        \\    "label": "{s}",
        \\    "capabilities": {s},
        \\    "expiresAt": {d},
        \\    "nonceHex": "{s}",
        \\    "brainPairEndpoint": "{s}",
        \\    "brainWssEndpoint": "{s}"
        \\  }},
        \\  "tokenBase64Url": "{s}",
        \\  "invoiceHex": "{s}",
        \\  "childPubKeyHex": "{s}"
        \\}}
        \\
    , .{
        OPERATOR_SEED, op_priv_hex, op_pub_hex, cert_id_hex,
        DEVICE_SEED,   dev_priv_hex, dev_pub_hex,
        CONTEXT_TAG, LABEL, caps_json.items,
        EXPIRES_AT, NONCE_HEX,
        BRAIN_PAIR_ENDPOINT, BRAIN_WSS_ENDPOINT,
        token.base64url, invoice_hex, child_pub_hex,
    });
    try out.writeAll(buf.items);

    std.debug.print("wrote {s} ({d} bytes)\n", .{ out_path, buf.items.len });
}

```
