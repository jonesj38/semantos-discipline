---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/device_pair_claim_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.174573+00:00
---

# runtime/semantos-brain/tests/device_pair_claim_conformance.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (identity_certs row), §8 Phase 1 follow-up; ODDJOBZ-EXTENSION-PLAN.md
// §3 phase O5p (lines around 268-285), §11.
//
// Conformance suite for the `device_pair` module — the substrate the
// `brain device pair` and `brain device claim` CLI verbs ride on.  The
// CLI verbs themselves are exercised in `cli_conformance.zig`; this
// file covers the wire-protocol surface (payload build / sign / parse
// / verify), the one-shot nonce ledger, and the context-tag allocator.

const std = @import("std");
const bsvz = @import("bsvz");
const bkds = @import("bkds");
const device_pair = @import("device_pair");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

// ─────────────────────────────────────────────────────────────────────
// Test helpers — synth an operator root keypair, build a payload, sign.
// ─────────────────────────────────────────────────────────────────────

const TestRoot = struct {
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.KEY_LEN]u8,
    cert_id: [32]u8,
};

fn makeTestRoot(seed: []const u8) !TestRoot {
    const priv = bkds.privFromSeed(seed);
    const pub_key = try bkds.pubFromSeed(seed);
    // cert_id = sha256(pubkey)[0..16] in hex (mirroring the
    // identity_certs.certIdFromPubkey shape).
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&pub_key, &hash, .{});
    var id_hex: [32]u8 = undefined;
    bkds.hexEncode(hash[0..16], &id_hex);
    return .{ .privkey = priv, .pubkey = pub_key, .cert_id = id_hex };
}

fn buildAndSign(
    allocator: std.mem.Allocator,
    root: TestRoot,
    label: []const u8,
    context_tag: u8,
    caps: []const []const u8,
    nonce: [device_pair.NONCE_LEN]u8,
    expires_at: i64,
) !device_pair.SignedToken {
    const payload = device_pair.PairPayload{
        .operator_root_cert_id = root.cert_id,
        .operator_root_pub = root.pubkey,
        .context_tag = context_tag,
        .label = label,
        .capabilities = caps,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = "https://brain.test/api/v1/device-pair",
        .brain_wss_endpoint = "wss://brain.test/api/v1/wallet",
        .brain_pin_cert_id = root.cert_id,
        .brain_pin_pubkey = root.pubkey,
    };
    return device_pair.signAndEncode(allocator, payload, root.privkey);
}

// ─────────────────────────────────────────────────────────────────────
// Round-trip: build → emit URL/token → parse → fields match
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: build → parse round-trip preserves all fields" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-A");

    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x42);

    const caps = [_][]const u8{ "cap.attach.photo", "cap.attach.gps", "cap.attach.voice" };
    var token = try buildAndSign(allocator, root, "iPhone-test", 0x10, &caps, nonce, pinnedClock() + 300);
    defer token.deinit(allocator);

    var parsed = try device_pair.parseAndVerify(allocator, token.base64url, pinnedClock());
    defer parsed.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &root.cert_id, &parsed.operator_root_cert_id);
    try std.testing.expectEqualSlices(u8, &root.pubkey, &parsed.operator_root_pub);
    try std.testing.expectEqual(@as(u8, 0x10), parsed.context_tag);
    try std.testing.expectEqualStrings("iPhone-test", parsed.label);
    try std.testing.expectEqual(@as(usize, 3), parsed.capabilities.len);
    try std.testing.expectEqualStrings("cap.attach.photo", parsed.capabilities[0]);
    try std.testing.expectEqualSlices(u8, &nonce, &parsed.nonce);
    try std.testing.expectEqual(pinnedClock() + 300, parsed.expires_at);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5p — v2 wire format additions: brain_pair_endpoint,
// brain_wss_endpoint, brain_pin_cert_id, brain_pin_pubkey.
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair v2: brain endpoint + pin fields round-trip" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-D-O5p-v2");
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x77);

    const caps = [_][]const u8{"cap.attach.photo"};
    var token = try buildAndSign(allocator, root, "v2-test", 0x10, &caps, nonce, pinnedClock() + 300);
    defer token.deinit(allocator);

    var parsed = try device_pair.parseAndVerify(allocator, token.base64url, pinnedClock());
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("https://brain.test/api/v1/device-pair", parsed.brain_pair_endpoint);
    try std.testing.expectEqualStrings("wss://brain.test/api/v1/wallet", parsed.brain_wss_endpoint);
    try std.testing.expectEqualSlices(u8, &root.cert_id, &parsed.brain_pin_cert_id);
    try std.testing.expectEqualSlices(u8, &root.pubkey, &parsed.brain_pin_pubkey);
}

test "D-O5p device_pair v2: malformed brain_pair_endpoint rejected" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-D-O5p-v2-bad-url");
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x12);

    const caps = [_][]const u8{"cap.attach.photo"};
    const payload = device_pair.PairPayload{
        .operator_root_cert_id = root.cert_id,
        .operator_root_pub = root.pubkey,
        .context_tag = 0x10,
        .label = "bad-url",
        .capabilities = &caps,
        .expires_at = pinnedClock() + 300,
        .nonce = nonce,
        // Malformed: ftp:// is not http(s) and parseAndVerify must
        // reject it.
        .brain_pair_endpoint = "ftp://nope.example/pair",
        .brain_wss_endpoint = "wss://brain.test/api/v1/wallet",
        .brain_pin_cert_id = root.cert_id,
        .brain_pin_pubkey = root.pubkey,
    };
    var token = try device_pair.signAndEncode(allocator, payload, root.privkey);
    defer token.deinit(allocator);
    try std.testing.expectError(
        device_pair.Error.pairing_payload_invalid_format,
        device_pair.parseAndVerify(allocator, token.base64url, pinnedClock()),
    );
}

// ─────────────────────────────────────────────────────────────────────
// pairUrl wraps the token correctly
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: pairUrl emits semantos-pair scheme" {
    const allocator = std.testing.allocator;
    const url = try device_pair.pairUrl(allocator, "brain.example", "abc123");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("semantos-pair://brain.example/pair?token=abc123", url);

    // extractToken strips it back.
    try std.testing.expectEqualStrings("abc123", device_pair.extractToken(url));
}

// ─────────────────────────────────────────────────────────────────────
// caps minimal resolves to the documented 3 attach caps
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: --caps minimal resolves to attach photo/gps/voice" {
    const allocator = std.testing.allocator;
    const c = try device_pair.resolveCaps(allocator, "minimal");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), c.items.len);
    try std.testing.expectEqualStrings("cap.attach.photo", c.items[0]);
    try std.testing.expectEqualStrings("cap.attach.gps", c.items[1]);
    try std.testing.expectEqualStrings("cap.attach.voice", c.items[2]);
}

test "D-W1 P1.followup device_pair: --caps full adds the oddjobz operator caps" {
    const allocator = std.testing.allocator;
    const c = try device_pair.resolveCaps(allocator, "full");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), c.items.len);
    var has_write_customer = false;
    var has_chat_serve = false;
    for (c.items) |cap| {
        if (std.mem.eql(u8, cap, "cap.oddjobz.write_customer")) has_write_customer = true;
        if (std.mem.eql(u8, cap, "cap.oddjobz.public_chat_serve")) has_chat_serve = true;
    }
    try std.testing.expect(has_write_customer);
    try std.testing.expect(has_chat_serve);
}

test "D-W1 P1.followup device_pair: --caps custom comma list accepts well-formed names" {
    const allocator = std.testing.allocator;
    const c = try device_pair.resolveCaps(allocator, "cap.foo.bar,cap.baz.qux");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), c.items.len);
}

test "D-W1 P1.followup device_pair: --caps custom rejects malformed (no `cap.` prefix)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        device_pair.Error.pairing_payload_invalid_capability,
        device_pair.resolveCaps(allocator, "notcap.X,cap.Y"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Expired payload rejected
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: payload past expires_at returns pairing_payload_expired" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-B");

    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x01);

    const caps = [_][]const u8{"cap.attach.photo"};
    var token = try buildAndSign(allocator, root, "expired", 0x10, &caps, nonce, pinnedClock() + 300);
    defer token.deinit(allocator);

    // 5 minutes after issue + 1 second.
    const past_expiry = pinnedClock() + 301;
    try std.testing.expectError(
        device_pair.Error.pairing_payload_expired,
        device_pair.parseAndVerify(allocator, token.base64url, past_expiry),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Tampered payload rejected
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: tampered payload returns pairing_payload_invalid_signature" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-C");
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x02);
    const caps = [_][]const u8{"cap.attach.photo"};
    var token = try buildAndSign(allocator, root, "test", 0x10, &caps, nonce, pinnedClock() + 300);
    defer token.deinit(allocator);

    // Decode → tamper → re-encode.  Twiddle a label byte; signature
    // no longer matches.
    const dec = std.base64.url_safe_no_pad.Decoder;
    const json_len = try dec.calcSizeForSlice(token.base64url);
    const json = try allocator.alloc(u8, json_len);
    defer allocator.free(json);
    try dec.decode(json, token.base64url);
    // Find the label substring "test" and mutate it.
    if (std.mem.indexOf(u8, json, "test")) |idx| json[idx] = 'X';
    const enc = std.base64.url_safe_no_pad.Encoder;
    const out_len = enc.calcSize(json.len);
    const tampered = try allocator.alloc(u8, out_len);
    defer allocator.free(tampered);
    _ = enc.encode(tampered, json);

    try std.testing.expectError(
        device_pair.Error.pairing_payload_invalid_signature,
        device_pair.parseAndVerify(allocator, tampered, pinnedClock()),
    );
}

// ─────────────────────────────────────────────────────────────────────
// One-shot nonce ledger
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: nonce ledger marks consumed + survives reload" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0xAA);

    {
        var ledger = try device_pair.NonceLedger.init(allocator, real);
        defer ledger.deinit();
        try std.testing.expect(!ledger.isConsumed(nonce));
        try ledger.markConsumed(nonce);
        try std.testing.expect(ledger.isConsumed(nonce));
        // Idempotent re-mark.
        try ledger.markConsumed(nonce);
    }
    // Reopen + replay.
    {
        var ledger2 = try device_pair.NonceLedger.init(allocator, real);
        defer ledger2.deinit();
        try std.testing.expect(ledger2.isConsumed(nonce));
    }
}

// ─────────────────────────────────────────────────────────────────────
// Context-tag allocator: 0x10, 0x11, then skips taken slots
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: two devices paired sequentially get 0x10 and 0x11" {
    var taken: [256]bool = .{false} ** 256;

    const t1 = try device_pair.allocateContextTag(&[_]u8{});
    try std.testing.expectEqual(@as(u8, 0x10), t1);
    taken[t1] = true;

    var used: [1]u8 = .{t1};
    const t2 = try device_pair.allocateContextTag(&used);
    try std.testing.expectEqual(@as(u8, 0x11), t2);
}

test "D-W1 P1.followup device_pair: allocator skips intermediate gaps" {
    const used = [_]u8{ 0x10, 0x12 }; // 0x11 free
    try std.testing.expectEqual(@as(u8, 0x11), try device_pair.allocateContextTag(&used));
}

test "D-W1 P1.followup device_pair: allocator returns no_context_tag when 0x10..0xFF all taken" {
    var used: [240]u8 = undefined;
    var i: usize = 0;
    while (i < 240) : (i += 1) used[i] = @intCast(0x10 + i);
    try std.testing.expectError(
        device_pair.Error.pairing_payload_no_context_tag,
        device_pair.allocateContextTag(&used),
    );
}

// ─────────────────────────────────────────────────────────────────────
// End-to-end claim — produces matching child pubkey via BRC-42 ECDH
// symmetry.  The brain side (root_priv + device_pub) and the device
// side (device_priv + root_pub) compute the same child pubkey.
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup device_pair: claim derives a child pubkey that the brain can verify" {
    const allocator = std.testing.allocator;
    const root = try makeTestRoot("operator-root-D");

    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, 0x55);

    const caps = [_][]const u8{ "cap.attach.photo", "cap.attach.gps" };
    var token = try buildAndSign(allocator, root, "claim-test", 0x10, &caps, nonce, pinnedClock() + 300);
    defer token.deinit(allocator);

    var parsed = try device_pair.parseAndVerify(allocator, token.base64url, pinnedClock());
    defer parsed.deinit(allocator);

    // Mint a device priv + compute child pubkey via the device-side
    // BRC-42 path (what `brain device claim` runs).
    const device_priv = bkds.privFromSeed("device-claim-test");
    const child_via_device = try bkds.deriveChildPubkeyFromDevice(
        device_priv,
        parsed.operator_root_pub,
        parsed.context_tag,
        parsed.label,
    );

    // Brain re-derives via the operator-side BRC-42 path with the
    // same device pub.  Must match by ECDH symmetry.
    const device_priv_obj = try bsvz.primitives.ec.PrivateKey.fromBytes(device_priv);
    const device_pub_obj = try device_priv_obj.publicKey();
    const device_pub_sec1 = device_pub_obj.toCompressedSec1();
    const child_via_brain = try bkds.deriveChildPubkey(
        root.privkey,
        device_pub_sec1,
        parsed.context_tag,
        parsed.label,
    );

    try std.testing.expectEqualSlices(u8, &child_via_device, &child_via_brain);

    // And the BRC-42 verifier (what `identity_certs.issue_child`
    // calls) accepts the device-supplied child + proof tuple.
    try bkds.verifyDerivationProof(
        root.privkey,
        device_pub_sec1,
        parsed.context_tag,
        parsed.label,
        child_via_device,
    );
}

```
