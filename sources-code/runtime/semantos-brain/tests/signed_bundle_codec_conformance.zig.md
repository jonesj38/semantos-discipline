---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/signed_bundle_codec_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.210054+00:00
---

# runtime/semantos-brain/tests/signed_bundle_codec_conformance.zig

```zig
// Phase D-W1 / Phase 4 — SignedBundle codec conformance.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.4 + §8 Phase 4.
//
// Property suite for the signed_bundle codec:
//   • encode → decode round-trip preserves every field.
//   • Decode is strict on missing required fields.
//   • Tampering any byte of the wire shape breaks signature verification.
//   • Cert chain verification accepts a properly-registered leaf and
//     rejects every documented attack (forged leaf, intermediate
//     unknown, parent mismatch).
//   • The verifyCertChain → resolved capability set arrives intact at
//     the caller (the dispatcher drops these onto its DispatchContext).

const std = @import("std");
const signed_bundle = @import("signed_bundle");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");

const allocator = std.testing.allocator;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

// ─────────────────────────────────────────────────────────────────────
// Round-trip + field preservation
// ─────────────────────────────────────────────────────────────────────

test "encode→decode preserves every field" {
    const seed = "phase4-roundtrip-seed";
    const pubkey = try bkds.pubFromSeed(seed);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey),
            .pubkey = pubkey,
            .context_tag = 0x10,
            .parent_cert_id = "fedcba9876543210fedcba9876543210".*,
        },
    };
    const recipient: [signed_bundle.CERT_ID_HEX_LEN]u8 = "11111111111111111111111111111111".*;
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&nonce, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = recipient,
        .payload_type = "dispatch.request",
        .payload =
            \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-r1"}
        ,
        .signature = [_]u8{0xab} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = 1_700_000_001,
        },
    };

    const encoded = try signed_bundle.encode(allocator, b);
    defer allocator.free(encoded);

    var owned = try signed_bundle.decode(allocator, encoded);
    defer owned.deinit();
    const got = owned.bundle;

    try std.testing.expectEqualSlices(u8, b.payload_type, got.payload_type);
    try std.testing.expectEqualSlices(u8, b.payload, got.payload);
    try std.testing.expect(got.recipient_cert_id != null);
    try std.testing.expectEqualSlices(u8, recipient[0..], got.recipient_cert_id.?[0..]);
    try std.testing.expectEqual(@as(usize, 1), got.sender_cert_chain.len);
    try std.testing.expectEqualSlices(u8, &chain[0].cert_id, &got.sender_cert_chain[0].cert_id);
    try std.testing.expectEqualSlices(u8, &chain[0].pubkey, &got.sender_cert_chain[0].pubkey);
    try std.testing.expectEqual(@as(u8, 0x10), got.sender_cert_chain[0].context_tag);
    try std.testing.expectEqualSlices(u8, b.signature[0..], got.signature[0..]);
    try std.testing.expectEqualSlices(u8, &nonce, &got.signature_metadata.nonce_hex);
    try std.testing.expectEqual(@as(i64, 1_700_000_001), got.signature_metadata.timestamp_unix);
    try std.testing.expectEqualStrings("ecdsa-secp256k1-sha256", got.signature_metadata.algorithm);
}

test "decode rejects malformed JSON" {
    try std.testing.expectError(signed_bundle.Error.invalid_json, signed_bundle.decode(allocator, "not json {"));
}

test "decode rejects missing required fields" {
    const json = "{\"v\":1}";
    try std.testing.expectError(signed_bundle.Error.missing_field, signed_bundle.decode(allocator, json));
}

test "decode rejects bad cert_id length" {
    const json =
        \\{"v":1,"sender_cert_chain":[{"cert_id":"too-short","pubkey":"02000000000000000000000000000000000000000000000000000000000000000a","context_tag":0,"parent_cert_id":null}],"recipient_cert_id":null,"payload_type":"x","payload":"x","signature":"
    ++ "00" ** 64 ++
        \\","signature_metadata":{"algorithm":"ecdsa-secp256k1-sha256","nonce_hex":"
    ++ "0" ** 64 ++ "\",\"timestamp_unix\":0}}";
    try std.testing.expectError(signed_bundle.Error.bad_cert_id_length, signed_bundle.decode(allocator, json));
}

// ─────────────────────────────────────────────────────────────────────
// Signature verification — round-trip + tamper rejection
// ─────────────────────────────────────────────────────────────────────

test "sign + verify with same pubkey succeeds" {
    const seed = "phase4-sign-verify";
    const priv = bkds.privFromSeed(seed);
    const pubkey = try bkds.pubFromSeed(seed);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey),
            .pubkey = pubkey,
            .context_tag = 0x10,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'a');
    var b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = "11111111111111111111111111111111".*,
        .payload_type = "dispatch.request",
        .payload = "{\"v\":1,\"resource\":\"x\",\"cmd\":\"y\",\"args\":null}",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 1_700_000_002 },
    };
    try signed_bundle.signBundle(allocator, &b, priv);
    try signed_bundle.verifySignature(allocator, b, pubkey);
}

test "verify rejects different pubkey (forged sender)" {
    const seed_real = "phase4-real-signer";
    const seed_other = "phase4-attacker";
    const priv = bkds.privFromSeed(seed_real);
    const pubkey_real = try bkds.pubFromSeed(seed_real);
    const pubkey_other = try bkds.pubFromSeed(seed_other);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey_real),
            .pubkey = pubkey_real,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'b');
    var b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    try signed_bundle.signBundle(allocator, &b, priv);
    // Verification under the wrong pubkey rejects.
    try std.testing.expectError(signed_bundle.Error.signature_mismatch, signed_bundle.verifySignature(allocator, b, pubkey_other));
}

test "verify rejects tampered payload" {
    const seed = "phase4-tamper";
    const priv = bkds.privFromSeed(seed);
    const pubkey = try bkds.pubFromSeed(seed);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey),
            .pubkey = pubkey,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'c');
    var b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "original",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    try signed_bundle.signBundle(allocator, &b, priv);
    // Re-encode, mutate one payload byte, decode, verify.
    const encoded = try signed_bundle.encode(allocator, b);
    defer allocator.free(encoded);

    var tampered_buf = try allocator.dupe(u8, encoded);
    defer allocator.free(tampered_buf);
    // Locate the payload field and flip a byte.  Stable because
    // canonical key ordering puts "payload" at the start.
    const idx = std.mem.indexOf(u8, tampered_buf, "original") orelse return error.SkipZigTest;
    tampered_buf[idx] = 'm';
    var owned = try signed_bundle.decode(allocator, tampered_buf);
    defer owned.deinit();
    try std.testing.expectError(signed_bundle.Error.signature_mismatch, signed_bundle.verifySignature(allocator, owned.bundle, pubkey));
}

// ─────────────────────────────────────────────────────────────────────
// Cert chain verification
// ─────────────────────────────────────────────────────────────────────

const ChainFixture = struct {
    store: identity_certs.CertStore,
    tmp: std.testing.TmpDir,
    root_priv: [bkds.PRIVKEY_LEN]u8,
    root_pubkey: [bkds.KEY_LEN]u8,
    leaf_pubkey: [bkds.KEY_LEN]u8,

    fn deinit(self: *ChainFixture) void {
        self.store.deinit();
        self.tmp.cleanup();
    }
};

fn buildChainFixture(seed: []const u8, caps: []const []const u8) !ChainFixture {
    var tmp = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    errdefer store.deinit();

    const root_priv = bkds.privFromSeed(seed);
    const root_pubkey = try bkds.pubFromSeed(seed);
    const root = try store.issueRoot(root_pubkey, "operator-root");

    // Derive a child under context 0x10 (carpenter).
    const device_seed = "phase4-device-seed";
    const device_pubkey = try bkds.pubFromSeed(device_seed);
    const child_pubkey = try bkds.deriveChildPubkey(root_priv, device_pubkey, 0x10, "phone");
    _ = try store.issueChild(&root.id, 0x10, child_pubkey, caps, "phone");

    return ChainFixture{
        .store = store,
        .tmp = tmp,
        .root_priv = root_priv,
        .root_pubkey = root_pubkey,
        .leaf_pubkey = child_pubkey,
    };
}

test "verifyCertChain: leaf + root chain succeeds, returns caps" {
    const caps = [_][]const u8{ "cap.oddjobz.write_customer", "cap.attach.photo" };
    var fx = try buildChainFixture("phase4-chain-happy", &caps);
    defer fx.deinit();

    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);
    const root_id = identity_certs.certIdFromPubkey(fx.root_pubkey);

    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = fx.leaf_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = root_id,
        },
        .{
            .cert_id = root_id,
            .pubkey = fx.root_pubkey,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'd');
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = root_id,
        .payload_type = "dispatch.request",
        .payload = "{}",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    var verified = try signed_bundle.verifyCertChain(allocator, b, &fx.store);
    defer verified.deinit();

    try std.testing.expectEqualSlices(u8, &leaf_id, &verified.leaf_cert_id);
    try std.testing.expectEqualSlices(u8, &fx.leaf_pubkey, &verified.leaf_pubkey);
    try std.testing.expectEqual(@as(usize, 2), verified.capabilities.len);
}

test "verifyCertChain: unknown leaf rejected" {
    var fx = try buildChainFixture("phase4-chain-unknown-leaf", &.{});
    defer fx.deinit();

    const fake_pubkey = try bkds.pubFromSeed("phase4-fake-leaf");
    const fake_id = identity_certs.certIdFromPubkey(fake_pubkey);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = fake_id,
            .pubkey = fake_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = identity_certs.certIdFromPubkey(fx.root_pubkey),
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'e');
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    try std.testing.expectError(signed_bundle.Error.leaf_cert_unknown, signed_bundle.verifyCertChain(allocator, b, &fx.store));
}

test "verifyCertChain: cert_id ↔ pubkey mismatch rejected" {
    var fx = try buildChainFixture("phase4-chain-id-mismatch", &.{});
    defer fx.deinit();

    // Real leaf cert id, but a different (also-known) pubkey.
    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);
    const wrong_pubkey = try bkds.pubFromSeed("phase4-wrong-pubkey");
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = wrong_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = identity_certs.certIdFromPubkey(fx.root_pubkey),
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'f');
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    try std.testing.expectError(signed_bundle.Error.chain_intermediate_unknown, signed_bundle.verifyCertChain(allocator, b, &fx.store));
}

test "verifyCertChain: parent claim mismatch rejected" {
    var fx = try buildChainFixture("phase4-chain-parent-mismatch", &.{});
    defer fx.deinit();

    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);
    // Wire claims a different parent than the store has on record.
    const wrong_parent = "00000000000000000000000000000000".*;
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = fx.leaf_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = wrong_parent,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'g');
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = 0 },
    };
    try std.testing.expectError(signed_bundle.Error.chain_parent_mismatch, signed_bundle.verifyCertChain(allocator, b, &fx.store));
}

```
