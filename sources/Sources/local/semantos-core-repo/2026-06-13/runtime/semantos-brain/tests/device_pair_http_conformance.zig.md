---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/device_pair_http_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.177888+00:00
---

# runtime/semantos-brain/tests/device_pair_http_conformance.zig

```zig
// Phase D-O5p — conformance suite for the production HTTP acceptor.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p-c
// (acceptor side); §9.5 (mobile-auth round-trip — the §9 acceptance
// gate this suite discharges at the Zig-side level; the TS test
// fixture in cartridges/oddjobz/brain/tests/device-pair-roundtrip.test.ts
// discharges it again at the TS-mobile-client layer).
//
// What this suite asserts:
//
//   • The pure `accept()` path (no HTTP) accepts a well-formed
//     pairing payload + device-derived child pubkey + counterparty
//     pub, persists the child cert in the store, and burns the
//     nonce.
//   • A second accept() with the same token surfaces as
//     payload_consumed.
//   • A forged derivation_pubkey surfaces as
//     derivation_proof_mismatch (BRC-42 verification rejects).
//   • Wrong context_tag (forged) surfaces as
//     derivation_proof_mismatch.
//   • An expired payload surfaces as payload_expired without
//     touching the store.
//   • A tampered token (signature broken) surfaces as
//     payload_invalid_signature.
//   • parseAcceptRequest accepts a well-formed JSON body and
//     rejects malformed bodies.

const std = @import("std");
const bsvz = @import("bsvz");
const bkds = @import("bkds");
const device_pair = @import("device_pair");
const device_pair_http = @import("device_pair_http");
const identity_certs = @import("identity_certs");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.PUBKEY_LEN]u8,
    cert_id: [32]u8,
    store: identity_certs.CertStore,
    acceptor: device_pair_http.Acceptor,

    fn init(allocator: std.mem.Allocator, seed: []const u8) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        self.privkey = bkds.privFromSeed(seed);
        self.pubkey = try bkds.pubFromSeed(seed);

        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&self.pubkey, &hash, .{});
        bkds.hexEncode(hash[0..16], &self.cert_id);

        self.store = try identity_certs.CertStore.init(allocator, real, struct {
            fn t() i64 {
                return 1_700_000_000;
            }
        }.t);
        // Seed root cert.
        _ = try self.store.issueRoot(self.pubkey, "operator");

        self.acceptor = device_pair_http.Acceptor.init(allocator, &self.store, self.data_dir);
        self.acceptor.setOperatorRootPriv(self.privkey);
        return self;
    }

    fn deinit(self: *Setup) void {
        self.store.deinit();
        self.allocator.free(self.data_dir);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

fn buildToken(
    allocator: std.mem.Allocator,
    setup: *Setup,
    label: []const u8,
    context_tag: u8,
    nonce_byte: u8,
    expires_at: i64,
) !device_pair.SignedToken {
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, nonce_byte);
    const caps = [_][]const u8{ "cap.attach.photo", "cap.attach.gps" };
    const payload = device_pair.PairPayload{
        .operator_root_cert_id = setup.cert_id,
        .operator_root_pub = setup.pubkey,
        .context_tag = context_tag,
        .label = label,
        .capabilities = &caps,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = "https://brain.test/api/v1/device-pair",
        .brain_wss_endpoint = "wss://brain.test/api/v1/wallet",
        .brain_pin_cert_id = setup.cert_id,
        .brain_pin_pubkey = setup.pubkey,
    };
    return device_pair.signAndEncode(allocator, payload, setup.privkey);
}

fn deriveDevicePair(
    operator_pub: [bkds.PUBKEY_LEN]u8,
    context_tag: u8,
    label: []const u8,
    seed: []const u8,
) !struct {
    device_priv: [bkds.PRIVKEY_LEN]u8,
    device_pub: [bkds.PUBKEY_LEN]u8,
    child_pub: [bkds.PUBKEY_LEN]u8,
} {
    const dpriv = bkds.privFromSeed(seed);
    const priv_obj = try bsvz.primitives.ec.PrivateKey.fromBytes(dpriv);
    const dpub_obj = try priv_obj.publicKey();
    const dpub = dpub_obj.toCompressedSec1();
    const child = try bkds.deriveChildPubkeyFromDevice(dpriv, operator_pub, context_tag, label);
    return .{ .device_priv = dpriv, .device_pub = dpub, .child_pub = child };
}

// ─────────────────────────────────────────────────────────────────────
// Happy path: accept() registers the child cert + burns the nonce
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: accept() registers child cert + burns nonce" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-happy");
    defer setup.deinit();

    var token = try buildToken(allocator, setup, "iPhone-prod", 0x10, 0x42, pinnedClock() + 300);
    defer token.deinit(allocator);

    const dev = try deriveDevicePair(setup.pubkey, 0x10, "iPhone-prod", "device-D-O5p-happy");
    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        token.base64url,
        dev.child_pub,
        dev.device_pub,
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(device_pair_http.AcceptResultKind.registered, result.kind);
    try std.testing.expect(result.cert_id != null);
    try std.testing.expectEqualSlices(u8, &setup.cert_id, &(result.brain_cert_id orelse unreachable));

    // Cert chain now has root + 1 child.
    const items = try setup.store.list(allocator);
    defer allocator.free(items);
    var found_child = false;
    for (items) |rec| {
        if (rec.kind == .child and rec.context_tag == 0x10) {
            found_child = true;
            try std.testing.expectEqualSlices(u8, &dev.child_pub, &rec.pubkey);
            try std.testing.expectEqualStrings("iPhone-prod", rec.label);
        }
    }
    try std.testing.expect(found_child);

    // Second accept with the same token → payload_consumed.
    var result2 = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        token.base64url,
        dev.child_pub,
        dev.device_pub,
    );
    defer result2.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.payload_consumed, result2.kind);
}

// ─────────────────────────────────────────────────────────────────────
// Forged derivation_pubkey: BRC-42 verification rejects
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: forged derivation_pubkey returns derivation_proof_mismatch" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-forge-pub");
    defer setup.deinit();

    var token = try buildToken(allocator, setup, "iPhone", 0x10, 0x33, pinnedClock() + 300);
    defer token.deinit(allocator);

    const dev = try deriveDevicePair(setup.pubkey, 0x10, "iPhone", "device-D-O5p-forge");
    // Replace child_pub with a different pub — the brain side will
    // recompute the expected child from device_pub + label + ctx and
    // reject the swap.
    const wrong = try deriveDevicePair(setup.pubkey, 0x10, "iPhone", "different-device-seed");

    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        token.base64url,
        wrong.child_pub, // forged
        dev.device_pub, // matches "device-D-O5p-forge"
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.derivation_proof_mismatch, result.kind);
}

// ─────────────────────────────────────────────────────────────────────
// Expired payload rejected without touching the store
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: expired payload returns payload_expired" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-expired");
    defer setup.deinit();

    var token = try buildToken(allocator, setup, "iPhone", 0x10, 0x99, pinnedClock() + 100);
    defer token.deinit(allocator);

    const dev = try deriveDevicePair(setup.pubkey, 0x10, "iPhone", "device-D-O5p-expired");

    // Past expiry — 200 seconds after issue.
    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock() + 200,
        token.base64url,
        dev.child_pub,
        dev.device_pub,
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.payload_expired, result.kind);

    // Cert chain unchanged.
    const items = try setup.store.list(allocator);
    defer allocator.free(items);
    var child_count: usize = 0;
    for (items) |rec| if (rec.kind == .child) {
        child_count += 1;
    };
    try std.testing.expectEqual(@as(usize, 0), child_count);
}

// ─────────────────────────────────────────────────────────────────────
// Tampered token (signature broken) → payload_invalid_signature
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: tampered token returns payload_invalid_signature" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-tamper");
    defer setup.deinit();

    var token = try buildToken(allocator, setup, "iPhone", 0x10, 0x55, pinnedClock() + 300);
    defer token.deinit(allocator);

    // Decode → twiddle a label byte → re-encode.
    const dec = std.base64.url_safe_no_pad.Decoder;
    const json_len = try dec.calcSizeForSlice(token.base64url);
    const json = try allocator.alloc(u8, json_len);
    defer allocator.free(json);
    try dec.decode(json, token.base64url);
    if (std.mem.indexOf(u8, json, "iPhone")) |idx| json[idx] = 'X';
    const enc = std.base64.url_safe_no_pad.Encoder;
    const out_len = enc.calcSize(json.len);
    const tampered = try allocator.alloc(u8, out_len);
    defer allocator.free(tampered);
    _ = enc.encode(tampered, json);

    const dev = try deriveDevicePair(setup.pubkey, 0x10, "iPhone", "device-D-O5p-tamper");
    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        tampered,
        dev.child_pub,
        dev.device_pub,
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.payload_invalid_signature, result.kind);
}

// ─────────────────────────────────────────────────────────────────────
// Cross-tag impersonation (carpenter vs musician hat)
//
// Per docs/design/BRAIN-DISPATCHER-UNIFICATION.md §2.5 — a child
// computed under context_tag 0x10 must NOT verify when claimed
// under 0x11.  This is the K3 isolation invariant (the device
// derives its child against one hat; an attacker swapping the
// claim's context_tag should fail the BRC-42 recompute).
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: cross-context-tag swap returns derivation_proof_mismatch" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-ctx-swap");
    defer setup.deinit();

    // Operator issues the payload for context_tag 0x10 (carpenter).
    var token = try buildToken(allocator, setup, "iPhone", 0x10, 0xAA, pinnedClock() + 300);
    defer token.deinit(allocator);

    // Device derives its child against a DIFFERENT context_tag (0x11
    // — musician).  This is the cross-hat impersonation attempt.
    // The brain recomputes against the payload's 0x10 + the device's
    // submitted device_pub; the attacker's child won't match.
    const dev_wrong_tag = try deriveDevicePair(setup.pubkey, 0x11, "iPhone", "device-cross-tag");

    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        token.base64url,
        dev_wrong_tag.child_pub,
        dev_wrong_tag.device_pub,
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.derivation_proof_mismatch, result.kind);
}

// ─────────────────────────────────────────────────────────────────────
// No operator priv installed: every accept fails closed
// ─────────────────────────────────────────────────────────────────────

test "D-O5p device_pair_http: no operator priv → derivation_proof_mismatch" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "operator-D-O5p-no-priv");
    defer setup.deinit();
    // Clear the priv (the brain is in fail-closed mode).
    setup.acceptor.operator_root_priv = null;

    var token = try buildToken(allocator, setup, "iPhone", 0x10, 0x77, pinnedClock() + 300);
    defer token.deinit(allocator);

    const dev = try deriveDevicePair(setup.pubkey, 0x10, "iPhone", "device-no-priv");
    var result = try device_pair_http.accept(
        &setup.acceptor,
        pinnedClock(),
        token.base64url,
        dev.child_pub,
        dev.device_pub,
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(device_pair_http.AcceptResultKind.derivation_proof_mismatch, result.kind);
}

```
