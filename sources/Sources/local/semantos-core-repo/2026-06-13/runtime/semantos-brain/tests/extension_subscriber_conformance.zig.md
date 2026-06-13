---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_subscriber_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.178502+00:00
---

# runtime/semantos-brain/tests/extension_subscriber_conformance.zig

```zig
// Phase D-W2 Phase 2 — extension_subscriber conformance tests.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2.
//
// Two-mode coverage (mirrors extension_publish_conformance.zig):
//   • Stub mode (-Denable-wasmtime=false): exercises pure-Zig
//     primitives — frame decode, scope match, manifest lookup.
//     Signature verification cannot run (extension_publish stub
//     returns bsvz_unavailable).
//   • Real mode  (-Denable-wasmtime=true): full verifyFrame +
//     applyVerifiedFrame with a synthesised fixture.  Signs a
//     bundle with the operator priv (via extension_publish.
//     signOverBundle), feeds the sig into the SPV stub's lookup,
//     verifies + applies, asserts the apply outcome.
//
// Six rejection paths covered (each maps 1:1 to a §5.2 verification
// step):
//   - unknown_signer  — frame's pubkey isn't in [trusted_signers]
//   - scope_mismatch  — signer scoped to acme.* publishes oddjobz.foo
//   - hash_mismatch   — bundle bytes differ from publish-tx commitment
//   - signature_invalid — sig over wrong digest
//   - spv_verify_failed — SPV stub returns null (tx unknown)
//   - replay idempotence — second apply is a no-op

const std = @import("std");
const build_options = @import("build_options");
const subscriber = @import("extension_subscriber");
const tenant_manifest = @import("tenant_manifest");
const ext_pub = @import("extension_publish");

// ───────────────────────────────────────────────────────────────────
// SPV stub — used by every test that exercises verifyFrame.
// ───────────────────────────────────────────────────────────────────

const SpvFixture = struct {
    txid_display: [subscriber.TXID_LEN]u8,
    bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8,
    signature: [subscriber.SIG_LEN]u8,
    signer_pubkey: [subscriber.PUBKEY_LEN]u8,
    extension_name: []const u8,
    version: []const u8,
    depth: u32,
};

fn fixtureLookup(state: ?*anyopaque, txid: [subscriber.TXID_LEN]u8) ?subscriber.SpvLookup {
    const f: *const SpvFixture = @ptrCast(@alignCast(state.?));
    if (!std.mem.eql(u8, &f.txid_display, &txid)) return null;
    return .{
        .bundle_hash = f.bundle_hash,
        .signature = f.signature,
        .signer_pubkey = f.signer_pubkey,
        .extension_name = f.extension_name,
        .version = f.version,
        .depth = f.depth,
    };
}

fn nullLookup(state: ?*anyopaque, txid: [subscriber.TXID_LEN]u8) ?subscriber.SpvLookup {
    _ = state;
    _ = txid;
    return null;
}

// ───────────────────────────────────────────────────────────────────
// Frame builder — synthesises an extension-bundle-v1 BRC-12 frame.
// ───────────────────────────────────────────────────────────────────

fn buildSyntheticFrame(
    allocator: std.mem.Allocator,
    txid_internal: [subscriber.TXID_LEN]u8,
    bundle_bytes: []const u8,
    namespace: []const u8,
    version: []const u8,
    signer_pubkey: [subscriber.PUBKEY_LEN]u8,
) ![]u8 {
    const tag = subscriber.FRAME_TYPE_TAG;
    const inner_len: usize = 1 + tag.len + 4 + bundle_bytes.len + 1 + namespace.len + 1 + version.len + subscriber.PUBKEY_LEN;
    const inner = try allocator.alloc(u8, inner_len);
    defer allocator.free(inner);
    var off: usize = 0;
    inner[off] = @intCast(tag.len);
    off += 1;
    @memcpy(inner[off .. off + tag.len], tag);
    off += tag.len;
    inner[off] = @intCast(bundle_bytes.len >> 24);
    inner[off + 1] = @intCast((bundle_bytes.len >> 16) & 0xff);
    inner[off + 2] = @intCast((bundle_bytes.len >> 8) & 0xff);
    inner[off + 3] = @intCast(bundle_bytes.len & 0xff);
    off += 4;
    @memcpy(inner[off .. off + bundle_bytes.len], bundle_bytes);
    off += bundle_bytes.len;
    inner[off] = @intCast(namespace.len);
    off += 1;
    @memcpy(inner[off .. off + namespace.len], namespace);
    off += namespace.len;
    inner[off] = @intCast(version.len);
    off += 1;
    @memcpy(inner[off .. off + version.len], version);
    off += version.len;
    @memcpy(inner[off .. off + subscriber.PUBKEY_LEN], &signer_pubkey);

    const frame = try allocator.alloc(u8, subscriber.SHARD_FRAME_HEADER_SIZE + inner_len);
    frame[0] = 0xE3;
    frame[1] = 0xE1;
    frame[2] = 0xF3;
    frame[3] = 0xE8;
    frame[4] = 0x02;
    frame[5] = 0xBF;
    frame[6] = 0x01;
    frame[7] = 0x00;
    @memcpy(frame[8..40], &txid_internal);
    const pl: u32 = @intCast(inner_len);
    frame[40] = @intCast(pl >> 24);
    frame[41] = @intCast((pl >> 16) & 0xff);
    frame[42] = @intCast((pl >> 8) & 0xff);
    frame[43] = @intCast(pl & 0xff);
    @memcpy(frame[subscriber.SHARD_FRAME_HEADER_SIZE..], inner);
    return frame;
}

fn reverseTxid(in: [subscriber.TXID_LEN]u8) [subscriber.TXID_LEN]u8 {
    var out: [subscriber.TXID_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < subscriber.TXID_LEN) : (i += 1) out[i] = in[subscriber.TXID_LEN - 1 - i];
    return out;
}

fn hexEncode33(bytes: [33]u8, out: []u8) void {
    std.debug.assert(out.len >= 66);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ───────────────────────────────────────────────────────────────────
// Pure-logic tests (run in BOTH stub + real modes)
// ───────────────────────────────────────────────────────────────────

test "D-W2 P2 — decodeFrame: bad magic / protocol / version / size" {
    var frame = [_]u8{0} ** (subscriber.SHARD_FRAME_HEADER_SIZE + 1);
    frame[0] = 0xE3;
    frame[1] = 0xE1;
    frame[2] = 0xF3;
    frame[3] = 0xE8;
    frame[4] = 0x02;
    frame[5] = 0xBF;
    frame[6] = 0x01;

    var bad = frame;
    bad[0] = 0x00;
    try std.testing.expectError(error.frame_bad_magic, subscriber.decodeFrame(&bad));
    bad = frame;
    bad[6] = 0x99;
    try std.testing.expectError(error.frame_bad_version, subscriber.decodeFrame(&bad));
    try std.testing.expectError(error.frame_too_small, subscriber.decodeFrame(frame[0..10]));
}

test "D-W2 P2 — scopeMatches: wildcard, prefix, literal, multi-scope OR" {
    const star = [_][]const u8{"*"};
    try std.testing.expect(subscriber.signerScopeMatches(&star, "anything.foo"));
    const prefix = [_][]const u8{"acme.*"};
    try std.testing.expect(subscriber.signerScopeMatches(&prefix, "acme.invoicer"));
    try std.testing.expect(!subscriber.signerScopeMatches(&prefix, "oddjobz.foo"));
    const literal = [_][]const u8{"oddjobz.invoicer"};
    try std.testing.expect(subscriber.signerScopeMatches(&literal, "oddjobz.invoicer"));
    try std.testing.expect(!subscriber.signerScopeMatches(&literal, "oddjobz.thing"));
    const multi = [_][]const u8{ "acme.*", "shared.fonts" };
    try std.testing.expect(subscriber.signerScopeMatches(&multi, "shared.fonts"));
    try std.testing.expect(!subscriber.signerScopeMatches(&multi, "wallet.signing"));
}

// Helper — make a TrustedSigner with the given pubkey hex + scopes.
fn makeSigner(name: []const u8, pubkey_hex: []const u8, scopes: []const []const u8) tenant_manifest.TrustedSigner {
    return .{
        .name = name,
        .pubkey_hex = pubkey_hex,
        .plexus_identity_tx_hex = "00" ** 32,
        .scopes = scopes,
        .removable = false,
        .label = name,
        .shard_group = "deadbeef" ** 8,
        .recovery_enrolment_id = "",
    };
}

test "D-W2 P2 — findSignerByPubkey returns matching entry, null on miss" {
    var pubkey: [subscriber.PUBKEY_LEN]u8 = undefined;
    pubkey[0] = 0x02;
    @memset(pubkey[1..], 0xaa);
    var hex_buf: [66]u8 = undefined;
    hexEncode33(pubkey, &hex_buf);
    const scopes = [_][]const u8{"acme.*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", hex_buf[0..], &scopes),
    };
    try std.testing.expect(subscriber.findSignerByPubkey(&signers, pubkey) != null);

    var other: [subscriber.PUBKEY_LEN]u8 = undefined;
    other[0] = 0x03;
    @memset(other[1..], 0xbb);
    try std.testing.expectEqual(@as(?tenant_manifest.TrustedSigner, null), subscriber.findSignerByPubkey(&signers, other));
}

// ───────────────────────────────────────────────────────────────────
// Real-mode tests (signature crypto requires bsvz)
// ───────────────────────────────────────────────────────────────────

test "D-W2 P2 — happy path: verifyFrame + applyVerifiedFrame succeed" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    // Sign a synthetic bundle with a deterministic priv.
    const signer_priv: [32]u8 = .{0x42} ** 32;
    const bundle_bytes = "happy-path-bundle-bytes-fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});

    const namespace = "oddjobz.invoicer";
    const version = "0.1.0";

    // Derive pubkey from priv via extension_publish (same surface
    // the publish path uses).
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, version);

    // Use the bsvz primitive directly to derive the pubkey since
    // extension_publish doesn't expose it as a standalone helper.
    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    // SPV fixture — the publish-tx-side commitments.
    const txid_display: [subscriber.TXID_LEN]u8 = .{0xab} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = namespace,
        .version = version,
        .depth = 6,
    };
    const spv = subscriber.SpvClient{
        .state = @ptrCast(&fixture),
        .lookup_fn = fixtureLookup,
    };

    // Manifest signer set.
    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"oddjobz.*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("oddjobz", hex_buf[0..], &scopes),
    };

    // Build the frame (txid in internal byte order).
    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        namespace,
        version,
        signer_pubkey,
    );
    defer allocator.free(frame);

    const vf = try subscriber.verifyFrame(frame, &signers, spv, .{});
    try std.testing.expectEqualSlices(u8, namespace, vf.extension_name);
    try std.testing.expectEqualSlices(u8, version, vf.version);
    try std.testing.expectEqualSlices(u8, "oddjobz", vf.signer_name);
    try std.testing.expectEqualSlices(u8, &bundle_hash, &vf.bundle_hash);

    // Apply.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var outcome = try subscriber.applyVerifiedFrame(allocator, vf, data_dir, null, null);
    defer outcome.deinit(allocator);
    try std.testing.expect(!outcome.already_applied);
    try std.testing.expect(std.mem.endsWith(u8, outcome.bundle_path, "extensions/oddjobz.invoicer/0.1.0/bundle.bin"));

    // Replay: second apply is idempotent (no double-register).
    var outcome2 = try subscriber.applyVerifiedFrame(allocator, vf, data_dir, null, null);
    defer outcome2.deinit(allocator);
    try std.testing.expect(outcome2.already_applied);
    try std.testing.expect(!outcome2.registered);
}

test "D-W2 P2 — unknown_signer: signer pubkey not in manifest" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x77} ** 32;
    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x01} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "oddjobz.foo",
        .version = "0.1.0",
        .depth = 6,
    };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&fixture), .lookup_fn = fixtureLookup };

    // Manifest carries a DIFFERENT signer.
    const other_pubkey_hex = "02" ++ ("99" ** 32);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("other", other_pubkey_hex, &scopes),
    };

    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "oddjobz.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.unknown_signer,
        subscriber.verifyFrame(frame, &signers, spv, .{}),
    );
}

test "D-W2 P2 — scope_mismatch: acme.* signer publishes oddjobz.foo" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x55} ** 32;
    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x02} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "oddjobz.foo",
        .version = "0.1.0",
        .depth = 6,
    };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&fixture), .lookup_fn = fixtureLookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"acme.*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", hex_buf[0..], &scopes),
    };

    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "oddjobz.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.scope_mismatch,
        subscriber.verifyFrame(frame, &signers, spv, .{}),
    );
}

test "D-W2 P2 — hash_mismatch: bundle bytes differ from publish-tx commitment" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x33} ** 32;
    // Sign over the COMMITTED bundle hash (what the publish tx fixed).
    const committed_hash: [subscriber.BUNDLE_HASH_LEN]u8 = .{0xaa} ** 32;
    const sig = try ext_pub.signOverBundle(signer_priv, committed_hash, "0.1.0");

    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x03} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = committed_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 6,
    };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&fixture), .lookup_fn = fixtureLookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    // Frame carries DIFFERENT bytes — bundle hash won't match.
    const tampered_bundle = "different-bytes-than-the-committed-bundle";
    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        tampered_bundle,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.hash_mismatch,
        subscriber.verifyFrame(frame, &signers, spv, .{}),
    );
}

test "D-W2 P2 — signature_invalid: sig doesn't validate against pubkey + digest" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x44} ** 32;
    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    // Tamper: sig is over the WRONG version, then we present
    // version 0.1.0 — verifySignature will reject.
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.9.9");

    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x04} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 6,
    };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&fixture), .lookup_fn = fixtureLookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.signature_invalid,
        subscriber.verifyFrame(frame, &signers, spv, .{}),
    );
}

test "D-W2 P2 — spv_verify_failed: publish-tx unknown to SPV client" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const spv = subscriber.SpvClient{ .state = null, .lookup_fn = nullLookup };
    var pubkey: [subscriber.PUBKEY_LEN]u8 = undefined;
    pubkey[0] = 0x02;
    @memset(pubkey[1..], 0xaa);
    var hex_buf: [66]u8 = undefined;
    hexEncode33(pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("any", hex_buf[0..], &scopes) };

    const frame = try buildSyntheticFrame(
        allocator,
        .{0} ** subscriber.TXID_LEN,
        "x",
        "any.foo",
        "0.1.0",
        pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.spv_verify_failed,
        subscriber.verifyFrame(frame, &signers, spv, .{}),
    );
}

test "D-W2 P2 — spv_verify_failed: insufficient depth" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x66} ** 32;
    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(signer_priv);
    const pub_key = try priv.publicKey();
    const signer_pubkey: [subscriber.PUBKEY_LEN]u8 = pub_key.bytes;

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x05} ** 32;
    var fixture = SpvFixture{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 0, // mempool-only — fails depth=6 requirement.
    };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&fixture), .lookup_fn = fixtureLookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    const frame = try buildSyntheticFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    try std.testing.expectError(
        error.spv_verify_failed,
        subscriber.verifyFrame(frame, &signers, spv, .{ .required_spv_depth = 6 }),
    );
}

```
