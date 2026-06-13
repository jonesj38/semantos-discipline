---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/signed_bundle_canonical_fixture_gen.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.197904+00:00
---

# runtime/semantos-brain/tests/signed_bundle_canonical_fixture_gen.zig

```zig
// D-O5m.followup-6 Phase 1 — Cross-language SignedBundle canonical-
// preimage fixture generator + conformance test.
//
// Reference: runtime/semantos-brain/src/signed_bundle.zig (the canonical Zig
//            codec — struct shape, canonical preimage encoder, sign +
//            verify);
//            cartridges/oddjobz/brain/tools/send-bundle.ts (TS reference
//            implementation of the same wire shape; we already know
//            those two agree byte-for-byte);
//            apps/oddjobz-mobile/lib/src/mesh/signed_bundle.dart (the
//            new Dart port that consumes the fixture this test emits).
//
// What this test does:
//
//   1. Constructs three deterministic bundles spanning the realistic
//      shapes the mesh transport will see in production:
//        a. single-link cert chain (root cert; no parent)
//        b. multi-link cert chain (leaf + intermediate + root)
//        c. broadcast recipient (recipient_cert_id = null) — explicitly
//           wire-shape-supported even though receive seam currently
//           rejects it; the codec must round-trip cleanly either way
//   2. For each bundle, computes:
//        - canonical signature preimage bytes (hex) — the load-bearing
//          byte sequence the Dart side must reproduce
//        - SHA-256 digest of the preimage (hex)
//        - 64-byte compact (r||s) ECDSA signature (hex)
//        - the wire-encoded JSON bytes (hex)
//   3. Writes the fixture JSON to disk if absent (first-run bootstrap);
//      otherwise asserts byte-for-byte equality.
//
// The Dart side (apps/oddjobz-mobile/test/mesh/signed_bundle_test.dart)
// loads the same JSON and asserts:
//   - computeCanonicalPreimage(bundle) == expectedPreimageHex
//   - signBundle(unsigned, priv) produces signature == expectedSignatureHex
//   - verifyBundleSignature returns true on the canonical bytes,
//     false when fields are mutated
//
// Without this fixture parity passing, Phase 2's mesh transport
// would be broken at the wire layer — a Dart-built bundle would not
// round-trip through the Zig brain.

const std = @import("std");
const bsvz = @import("bsvz");
const signed_bundle = @import("signed_bundle");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");

/// Fixture path — relative to the Semantos Brain test cwd
/// (`runtime/semantos-brain/`).  Lives next to the existing vector trees.
const FIXTURE_REL_PATH = "tests/vectors/signed-bundle-canonical-fixture.json";

fn hexEncodeBuf(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
    return out;
}

fn hexEncodeFixed(comptime N: usize, bytes: [N]u8) [N * 2]u8 {
    var out: [N * 2]u8 = undefined;
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
    return out;
}

/// One fixture entry — captures everything the Dart side needs to
/// independently reproduce the byte sequences end-to-end.
const FixtureEntry = struct {
    label: []const u8,
    description: []const u8,
    priv_hex: [64]u8,
    bundle: signed_bundle.SignedBundle,
};

fn makePrivPub(seed: []const u8) struct { priv: [bkds.PRIVKEY_LEN]u8, pubkey: [bkds.KEY_LEN]u8 } {
    const priv = bkds.privFromSeed(seed);
    const pubkey = bkds.pubFromSeed(seed) catch unreachable;
    return .{ .priv = priv, .pubkey = pubkey };
}

/// Build a CertRef from a {pubkey, parent_cert_id, context_tag} tuple.
fn buildCertRef(pubkey: [bkds.KEY_LEN]u8, parent: ?[signed_bundle.CERT_ID_HEX_LEN]u8, context_tag: u8) signed_bundle.CertRef {
    return .{
        .cert_id = identity_certs.certIdFromPubkey(pubkey),
        .pubkey = pubkey,
        .context_tag = context_tag,
        .parent_cert_id = parent,
    };
}

/// Sign-and-emit one fixture entry to the writer.  The sole side effect
/// on `entry.bundle` is filling in the signature field via signBundle.
fn writeFixtureEntry(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    entry: *FixtureEntry,
) !void {
    var priv_bytes: [bkds.PRIVKEY_LEN]u8 = undefined;
    for (priv_bytes, 0..) |_, i| {
        const hi = try std.fmt.charToDigit(entry.priv_hex[i * 2], 16);
        const lo = try std.fmt.charToDigit(entry.priv_hex[i * 2 + 1], 16);
        priv_bytes[i] = @intCast(hi * 16 + lo);
    }

    // Compute preimage + digest BEFORE signing — the signature field is
    // excluded from its own preimage by construction, so the preimage is
    // identical pre/post sign.
    const preimage = try signed_bundle.canonicalSignaturePreimage(allocator, entry.bundle);
    defer allocator.free(preimage);
    const preimage_hex = try hexEncodeBuf(allocator, preimage);
    defer allocator.free(preimage_hex);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &digest, .{});
    const digest_hex = hexEncodeFixed(32, digest);

    // Sign — fills in entry.bundle.signature with the 64-byte compact (r||s).
    try signed_bundle.signBundle(allocator, &entry.bundle, priv_bytes);
    const sig_hex = hexEncodeFixed(signed_bundle.SIG_LEN, entry.bundle.signature);

    // Verify the signature recovers the leaf cert's pubkey end-to-end —
    // belt-and-braces against an accidental crypto regression.
    try signed_bundle.verifySignature(allocator, entry.bundle, entry.bundle.sender_cert_chain[0].pubkey);

    // Wire-encode the signed bundle to JSON.
    const wire_bytes = try signed_bundle.encode(allocator, entry.bundle);
    defer allocator.free(wire_bytes);
    const wire_hex = try hexEncodeBuf(allocator, wire_bytes);
    defer allocator.free(wire_hex);

    // Compute the leaf pubkey hex (used by the Dart side to instantiate
    // the SignedBundle without re-deriving from the priv).
    const leaf = entry.bundle.sender_cert_chain[0];
    const leaf_pub_hex = hexEncodeFixed(bkds.KEY_LEN, leaf.pubkey);

    // Emit one fixture entry as JSON.  Sorted keys; 2-space indent for
    // readability.  The cert chain is emitted as an array of cert
    // descriptors carrying enough info for the Dart side to rebuild
    // CertRef objects without consulting identity_certs.
    try out.print(allocator, "    {{\n", .{});
    try out.print(allocator, "      \"label\": ", .{});
    try writeJsonString(allocator, out, entry.label);
    try out.print(allocator, ",\n      \"description\": ", .{});
    try writeJsonString(allocator, out, entry.description);
    try out.print(allocator, ",\n      \"priv_hex\": \"{s}\",\n", .{entry.priv_hex[0..]});
    try out.print(allocator, "      \"leaf_pubkey_hex\": \"{s}\",\n", .{leaf_pub_hex[0..]});
    try out.print(allocator, "      \"bundle\": {{\n", .{});
    try out.print(allocator, "        \"v\": {d},\n", .{entry.bundle.v});
    try out.print(allocator, "        \"sender_cert_chain\": [\n", .{});
    for (entry.bundle.sender_cert_chain, 0..) |link, idx| {
        var pub_hex_buf: [bkds.KEY_LEN * 2]u8 = undefined;
        bkds.hexEncode(&link.pubkey, &pub_hex_buf);
        try out.print(allocator, "          {{\n", .{});
        try out.print(allocator, "            \"cert_id\": \"{s}\",\n", .{link.cert_id[0..]});
        try out.print(allocator, "            \"pubkey\": \"{s}\",\n", .{pub_hex_buf[0..]});
        try out.print(allocator, "            \"context_tag\": {d},\n", .{link.context_tag});
        if (link.parent_cert_id) |pid| {
            try out.print(allocator, "            \"parent_cert_id\": \"{s}\"\n", .{pid[0..]});
        } else {
            try out.print(allocator, "            \"parent_cert_id\": null\n", .{});
        }
        if (idx + 1 == entry.bundle.sender_cert_chain.len) {
            try out.print(allocator, "          }}\n", .{});
        } else {
            try out.print(allocator, "          }},\n", .{});
        }
    }
    try out.print(allocator, "        ],\n", .{});
    if (entry.bundle.recipient_cert_id) |rid| {
        try out.print(allocator, "        \"recipient_cert_id\": \"{s}\",\n", .{rid[0..]});
    } else {
        try out.print(allocator, "        \"recipient_cert_id\": null,\n", .{});
    }
    try out.print(allocator, "        \"payload_type\": ", .{});
    try writeJsonString(allocator, out, entry.bundle.payload_type);
    try out.print(allocator, ",\n        \"payload\": ", .{});
    try writeJsonString(allocator, out, entry.bundle.payload);
    try out.print(allocator, ",\n        \"signature_metadata\": {{\n", .{});
    try out.print(allocator, "          \"algorithm\": ", .{});
    try writeJsonString(allocator, out, entry.bundle.signature_metadata.algorithm);
    try out.print(allocator, ",\n          \"nonce_hex\": \"{s}\",\n", .{entry.bundle.signature_metadata.nonce_hex[0..]});
    try out.print(allocator, "          \"timestamp_unix\": {d}\n", .{entry.bundle.signature_metadata.timestamp_unix});
    try out.print(allocator, "        }}\n", .{});
    try out.print(allocator, "      }},\n", .{});
    try out.print(allocator, "      \"expected_preimage_hex\": \"{s}\",\n", .{preimage_hex});
    try out.print(allocator, "      \"expected_digest_hex\": \"{s}\",\n", .{digest_hex[0..]});
    try out.print(allocator, "      \"expected_signature_hex\": \"{s}\",\n", .{sig_hex[0..]});
    try out.print(allocator, "      \"expected_wire_hex\": \"{s}\"\n", .{wire_hex});
    try out.print(allocator, "    }}", .{});
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

test "signed-bundle canonical fixture: emit + parity" {
    const allocator = std.testing.allocator;

    // ── Entry A: single-link chain, addressed recipient ───────────────
    const a_kp = makePrivPub("d-o5m-followup-6a-fixture-leaf-2026");
    var a_chain = [_]signed_bundle.CertRef{
        buildCertRef(a_kp.pubkey, null, 0x10),
    };
    var a_nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&a_nonce, "11111111111111111111111111111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const a_recipient: [signed_bundle.CERT_ID_HEX_LEN]u8 = "abcdef00112233445566778899aabbcc".*;
    var a_priv_hex: [64]u8 = undefined;
    {
        const tmp = hexEncodeFixed(bkds.PRIVKEY_LEN, a_kp.priv);
        @memcpy(&a_priv_hex, tmp[0..]);
    }
    var entry_a = FixtureEntry{
        .label = "single-link-addressed",
        .description = "Leaf cert at root (no parent); addressed bundle to a brain root cert id.",
        .priv_hex = a_priv_hex,
        .bundle = .{
            .v = signed_bundle.ENVELOPE_VERSION,
            .sender_cert_chain = a_chain[0..],
            .recipient_cert_id = a_recipient,
            .payload_type = "dispatch.request",
            .payload = "{\"v\":1,\"resource\":\"bearer_tokens\",\"cmd\":\"list\",\"args\":null,\"request_id\":\"req-fixture-a\"}",
            .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
            .signature_metadata = .{
                .nonce_hex = a_nonce,
                .timestamp_unix = 1_730_000_000,
            },
        },
    };

    // ── Entry B: three-link chain (root → context-hat → device) ──────
    const b_root = makePrivPub("d-o5m-followup-6a-fixture-root");
    const b_mid = makePrivPub("d-o5m-followup-6a-fixture-context-hat");
    const b_leaf = makePrivPub("d-o5m-followup-6a-fixture-device");
    const b_root_id = identity_certs.certIdFromPubkey(b_root.pubkey);
    const b_mid_id = identity_certs.certIdFromPubkey(b_mid.pubkey);
    var b_chain = [_]signed_bundle.CertRef{
        buildCertRef(b_leaf.pubkey, b_mid_id, 0x11), // leaf, parent = context-hat
        buildCertRef(b_mid.pubkey, b_root_id, 0x10), // intermediate, parent = root
        buildCertRef(b_root.pubkey, null, 0x00), // root
    };
    var b_nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&b_nonce, "22222222222222222222222222222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    const b_recipient: [signed_bundle.CERT_ID_HEX_LEN]u8 = "deadbeef00000000feedface11223344".*;
    var b_priv_hex: [64]u8 = undefined;
    {
        const tmp = hexEncodeFixed(bkds.PRIVKEY_LEN, b_leaf.priv);
        @memcpy(&b_priv_hex, tmp[0..]);
    }
    var entry_b = FixtureEntry{
        .label = "three-link-chain",
        .description = "Leaf signs with a 3-link chain (device → context-hat → root); addressed recipient.",
        .priv_hex = b_priv_hex,
        .bundle = .{
            .v = signed_bundle.ENVELOPE_VERSION,
            .sender_cert_chain = b_chain[0..],
            .recipient_cert_id = b_recipient,
            .payload_type = "dispatch.request",
            .payload = "{\"v\":1,\"resource\":\"visits\",\"cmd\":\"create\",\"args\":{\"customer_id\":\"00112233445566778899aabbccddeeff\",\"summary\":\"x\"},\"request_id\":\"req-fixture-b\"}",
            .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
            .signature_metadata = .{
                .nonce_hex = b_nonce,
                .timestamp_unix = 1_730_000_001,
            },
        },
    };

    // ── Entry C: single-link chain, broadcast (null recipient) ───────
    const c_kp = makePrivPub("d-o5m-followup-6a-fixture-broadcast");
    var c_chain = [_]signed_bundle.CertRef{
        buildCertRef(c_kp.pubkey, null, 0x10),
    };
    var c_nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&c_nonce, "33333333333333333333333333333333cccccccccccccccccccccccccccccccc");
    var c_priv_hex: [64]u8 = undefined;
    {
        const tmp = hexEncodeFixed(bkds.PRIVKEY_LEN, c_kp.priv);
        @memcpy(&c_priv_hex, tmp[0..]);
    }
    var entry_c = FixtureEntry{
        .label = "single-link-broadcast",
        .description = "Single-link chain, broadcast bundle (recipient_cert_id null) — codec must round-trip even though the receive seam rejects.",
        .priv_hex = c_priv_hex,
        .bundle = .{
            .v = signed_bundle.ENVELOPE_VERSION,
            .sender_cert_chain = c_chain[0..],
            .recipient_cert_id = null,
            .payload_type = "mesh.discovery",
            .payload = "{\"v\":1,\"hello\":\"mesh\"}",
            .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
            .signature_metadata = .{
                .nonce_hex = c_nonce,
                .timestamp_unix = 1_730_000_002,
            },
        },
    };

    // Assemble the fixture document.
    var json_buf: std.ArrayList(u8) = .{};
    defer json_buf.deinit(allocator);

    try json_buf.print(allocator, "{{\n", .{});
    try json_buf.print(allocator,
        "  \"_comment\": \"Generated by runtime/semantos-brain/tests/signed_bundle_canonical_fixture_gen.zig — DO NOT EDIT BY HAND.\",\n", .{});
    try json_buf.print(allocator,
        "  \"sig_domain\": \"{s}\",\n", .{signed_bundle.SIG_DOMAIN});
    try json_buf.print(allocator, "  \"envelope_version\": {d},\n", .{signed_bundle.ENVELOPE_VERSION});
    try json_buf.print(allocator, "  \"bundles\": [\n", .{});
    try writeFixtureEntry(allocator, &json_buf, &entry_a);
    try json_buf.print(allocator, ",\n", .{});
    try writeFixtureEntry(allocator, &json_buf, &entry_b);
    try json_buf.print(allocator, ",\n", .{});
    try writeFixtureEntry(allocator, &json_buf, &entry_c);
    try json_buf.print(allocator, "\n  ]\n}}\n", .{});

    // Bootstrap-or-assert path identical to cell_signing_fixture.
    const cwd = std.fs.cwd();
    if (cwd.openFile(FIXTURE_REL_PATH, .{})) |f| {
        defer f.close();
        const existing = try f.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(existing);
        if (!std.mem.eql(u8, existing, json_buf.items)) {
            std.debug.print("\nFIXTURE DRIFT: {s} differs from canonical bytes.\n", .{FIXTURE_REL_PATH});
            std.debug.print("Expected (regen):\n{s}\n", .{json_buf.items});
            return error.FixtureDrift;
        }
    } else |err| switch (err) {
        error.FileNotFound => {
            const f = try cwd.createFile(FIXTURE_REL_PATH, .{ .truncate = true });
            defer f.close();
            try f.writeAll(json_buf.items);
        },
        else => return err,
    }
}

test "signed-bundle canonical preimage: domain prefix is present" {
    // Sanity: the preimage MUST start with the BRAIN-SIGNED-BUNDLE-v1
    // domain tag.  Without that prefix a sig over a bundle preimage
    // could collide with a sig over a cell-engine envelope or a
    // publish-tx digest.  The Dart port asserts the same property.
    const allocator = std.testing.allocator;
    const kp = makePrivPub("preimage-prefix-check");
    var chain = [_]signed_bundle.CertRef{
        buildCertRef(kp.pubkey, null, 0x10),
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'a');
    const b = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = 0,
        },
    };
    const preimage = try signed_bundle.canonicalSignaturePreimage(allocator, b);
    defer allocator.free(preimage);
    try std.testing.expect(preimage.len > signed_bundle.SIG_DOMAIN.len);
    try std.testing.expectEqualStrings(signed_bundle.SIG_DOMAIN, preimage[0..signed_bundle.SIG_DOMAIN.len]);
    // Following the prefix, the canonical JSON object opens with `{`.
    try std.testing.expectEqual(@as(u8, '{'), preimage[signed_bundle.SIG_DOMAIN.len]);
}

comptime {
    _ = bsvz;
}

```
