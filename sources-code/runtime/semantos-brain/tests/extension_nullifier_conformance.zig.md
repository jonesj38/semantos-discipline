---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_nullifier_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.199093+00:00
---

# runtime/semantos-brain/tests/extension_nullifier_conformance.zig

```zig
// Phase D-W2 Phase 3 — extension_nullifier conformance.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §4.2 (Nullifier Publication), §4.3 (Rotation Authority), §7
//   Phase 3.
//
// Pure-Zig invariants run in BOTH stub + real modes:
//   • encode/decode round-trip (pure revocation)
//   • encode/decode round-trip (rotation)
//   • bad-tag rejection
//   • bad-reason-code rejection
//   • truncated rotation rejection
//   • verifyNullifier rejects unknown_target_signer
//   • applyNullifier — pure revocation removes the entry
//   • applyNullifier — rotation rewrites the pubkey + appends chain
//   • applyNullifier — replay idempotence
//
// Real-mode only (gated on build_options.enable_wasmtime):
//   • verifyNullifier accepts a valid rotation signature
//   • verifyNullifier rejects a tampered rotation signature
//   • verifyNullifier rejects rotation when recovery_enrolment_id
//     unknown to the lookup
//   • verifyNullifier rejects when the rotation flag is set without
//     a replacement (caller-side malformed input → codec catches; the
//     verify-layer also has a defensive check)

const std = @import("std");
const build_options = @import("build_options");
const nullifier = @import("extension_nullifier");
const tenant_manifest = @import("tenant_manifest");

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn makeSigner(name: []const u8, pubkey_hex: []const u8, recovery_id: []const u8) tenant_manifest.TrustedSigner {
    return .{
        .name = name,
        .pubkey_hex = pubkey_hex,
        .plexus_identity_tx_hex = "00" ** 32,
        .scopes = &.{},
        .removable = true,
        .label = name,
        .shard_group = "deadbeef" ** 8,
        .recovery_enrolment_id = recovery_id,
    };
}

const RecoveryItem = struct {
    recovery_enrolment_id: []const u8,
    pubkey: [nullifier.PUBKEY_LEN]u8,
};

const RecoveryRegistry = struct {
    items: []const RecoveryItem,

    fn lookup(state: ?*anyopaque, recovery_enrolment_id: []const u8) ?[nullifier.PUBKEY_LEN]u8 {
        const self: *const RecoveryRegistry = @ptrCast(@alignCast(state.?));
        for (self.items) |it| {
            if (std.mem.eql(u8, it.recovery_enrolment_id, recovery_enrolment_id)) {
                return it.pubkey;
            }
        }
        return null;
    }
};

const empty_recovery_lookup = nullifier.RecoveryAuthorityLookup{
    .state = null,
    .lookup_fn = struct {
        fn lookup(state: ?*anyopaque, _: []const u8) ?[nullifier.PUBKEY_LEN]u8 {
            _ = state;
            return null;
        }
    }.lookup,
};

fn pubkeyFromPriv(priv_bytes: [32]u8) ![nullifier.PUBKEY_LEN]u8 {
    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(priv_bytes);
    const pub_key = try priv.publicKey();
    return pub_key.bytes;
}

fn hexEncode33(bytes: [nullifier.PUBKEY_LEN]u8, out: []u8) void {
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Codec round-trips
// ─────────────────────────────────────────────────────────────────────

test "D-W2 P3 codec — pure revocation round-trip" {
    const allocator = std.testing.allocator;
    const p = nullifier.NullifierPayload{
        .revoked_pubkey = .{0x02} ++ [_]u8{0x11} ** 32,
        .reason_code = .compromised,
        .timestamp = 1_725_000_000,
    };
    const bytes = try nullifier.encodeNullifierPayload(allocator, p);
    defer allocator.free(bytes);
    try std.testing.expectEqual(nullifier.MIN_PAYLOAD_LEN, bytes.len);

    const decoded = try nullifier.decodeNullifierPayload(allocator, bytes);
    try std.testing.expectEqualSlices(u8, &p.revoked_pubkey, &decoded.revoked_pubkey);
    try std.testing.expectEqual(p.reason_code, decoded.reason_code);
    try std.testing.expectEqual(p.timestamp, decoded.timestamp);
    try std.testing.expect(decoded.replacement_pubkey == null);
    try std.testing.expect(decoded.rotation_authority_signature == null);
}

test "D-W2 P3 codec — rotation round-trip" {
    const allocator = std.testing.allocator;
    const p = nullifier.NullifierPayload{
        .revoked_pubkey = .{0x02} ++ [_]u8{0x11} ** 32,
        .reason_code = .superseded,
        .timestamp = 1_725_000_000,
        .replacement_pubkey = .{0x03} ++ [_]u8{0x22} ** 32,
        .rotation_authority_signature = .{0x33} ** 64,
    };
    const bytes = try nullifier.encodeNullifierPayload(allocator, p);
    defer allocator.free(bytes);
    try std.testing.expectEqual(nullifier.MAX_PAYLOAD_LEN, bytes.len);

    const decoded = try nullifier.decodeNullifierPayload(allocator, bytes);
    try std.testing.expect(decoded.replacement_pubkey != null);
    try std.testing.expect(decoded.rotation_authority_signature != null);
    try std.testing.expectEqualSlices(u8, &p.replacement_pubkey.?, &decoded.replacement_pubkey.?);
    try std.testing.expectEqualSlices(u8, &p.rotation_authority_signature.?, &decoded.rotation_authority_signature.?);
}

test "D-W2 P3 codec — bad tag rejected" {
    const allocator = std.testing.allocator;
    var bytes: [nullifier.MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..nullifier.PAYLOAD_VERSION_TAG.len], nullifier.PAYLOAD_VERSION_TAG);
    @memset(bytes[nullifier.PAYLOAD_VERSION_TAG.len..], 0);
    bytes[0] = 'X';
    try std.testing.expectError(error.payload_bad_tag, nullifier.decodeNullifierPayload(allocator, &bytes));
}

test "D-W2 P3 codec — bad reason code rejected" {
    const allocator = std.testing.allocator;
    var bytes: [nullifier.MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..nullifier.PAYLOAD_VERSION_TAG.len], nullifier.PAYLOAD_VERSION_TAG);
    @memset(bytes[nullifier.PAYLOAD_VERSION_TAG.len..], 0);
    bytes[nullifier.PAYLOAD_VERSION_TAG.len + nullifier.PUBKEY_LEN] = 99;
    try std.testing.expectError(error.payload_bad_reason_code, nullifier.decodeNullifierPayload(allocator, &bytes));
}

test "D-W2 P3 codec — truncated rotation payload rejected" {
    const allocator = std.testing.allocator;
    var bytes: [nullifier.MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..nullifier.PAYLOAD_VERSION_TAG.len], nullifier.PAYLOAD_VERSION_TAG);
    @memset(bytes[nullifier.PAYLOAD_VERSION_TAG.len..], 0);
    bytes[nullifier.MIN_PAYLOAD_LEN - 1] = 1; // has_replacement = 1 — but slice is min-length
    try std.testing.expectError(error.payload_truncated, nullifier.decodeNullifierPayload(allocator, &bytes));
}

// ─────────────────────────────────────────────────────────────────────
// verifyNullifier — invariants checkable in both modes
// ─────────────────────────────────────────────────────────────────────

test "D-W2 P3 verify — unknown_target_signer when revoked pubkey not in manifest" {
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", "02" ++ ("99" ** 32), ""),
    };
    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = .{0x02} ++ [_]u8{0x11} ** 32,
        .reason_code = .compromised,
        .timestamp = 0,
    };
    try std.testing.expectError(
        error.unknown_target_signer,
        nullifier.verifyNullifier(payload, &signers, empty_recovery_lookup),
    );
}

test "D-W2 P3 verify — pure revocation accepted when target known" {
    const target_priv: [32]u8 = .{0x42} ** 32;
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const target_pubkey = try pubkeyFromPriv(target_priv);
    var pubkey_hex: [66]u8 = undefined;
    hexEncode33(target_pubkey, &pubkey_hex);
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", pubkey_hex[0..], ""),
    };
    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = target_pubkey,
        .reason_code = .voluntary,
        .timestamp = 1_725_000_000,
    };
    const verified = try nullifier.verifyNullifier(payload, &signers, empty_recovery_lookup);
    try std.testing.expectEqualStrings("acme", verified.target_signer_name);
}

// ─────────────────────────────────────────────────────────────────────
// verifyNullifier — rotation (real-mode only — needs bsvz signing)
// ─────────────────────────────────────────────────────────────────────

test "D-W2 P3 verify — rotation accepted with valid authority signature" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const target_priv: [32]u8 = .{0x42} ** 32;
    const replacement_priv: [32]u8 = .{0x43} ** 32;
    const authority_priv: [32]u8 = .{0x44} ** 32;
    const target_pubkey = try pubkeyFromPriv(target_priv);
    const replacement_pubkey = try pubkeyFromPriv(replacement_priv);
    const authority_pubkey = try pubkeyFromPriv(authority_priv);

    var pubkey_hex: [66]u8 = undefined;
    hexEncode33(target_pubkey, &pubkey_hex);
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", pubkey_hex[0..], "rec-acme-001"),
    };

    const ts: u64 = 1_725_000_000;
    const sig = try nullifier.signRotationAuthority(authority_priv, target_pubkey, replacement_pubkey, ts);

    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = target_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };

    const items = [_]RecoveryItem{
        .{ .recovery_enrolment_id = "rec-acme-001", .pubkey = authority_pubkey },
    };
    var registry = RecoveryRegistry{ .items = &items };
    const lookup = nullifier.RecoveryAuthorityLookup{
        .state = @ptrCast(&registry),
        .lookup_fn = RecoveryRegistry.lookup,
    };

    const verified = try nullifier.verifyNullifier(payload, &signers, lookup);
    try std.testing.expectEqualStrings("acme", verified.target_signer_name);
    try std.testing.expectEqualStrings("rec-acme-001", verified.rotation_authority_label);
}

test "D-W2 P3 verify — bad_rotation_authority_signature when sig tampered" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const target_priv: [32]u8 = .{0x42} ** 32;
    const replacement_priv: [32]u8 = .{0x43} ** 32;
    const authority_priv: [32]u8 = .{0x44} ** 32;
    const target_pubkey = try pubkeyFromPriv(target_priv);
    const replacement_pubkey = try pubkeyFromPriv(replacement_priv);
    const authority_pubkey = try pubkeyFromPriv(authority_priv);

    var pubkey_hex: [66]u8 = undefined;
    hexEncode33(target_pubkey, &pubkey_hex);
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", pubkey_hex[0..], "rec-acme-001"),
    };

    const ts: u64 = 1_725_000_000;
    var sig = try nullifier.signRotationAuthority(authority_priv, target_pubkey, replacement_pubkey, ts);
    sig[7] ^= 0xff; // tamper

    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = target_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };

    const items = [_]RecoveryItem{
        .{ .recovery_enrolment_id = "rec-acme-001", .pubkey = authority_pubkey },
    };
    var registry = RecoveryRegistry{ .items = &items };
    const lookup = nullifier.RecoveryAuthorityLookup{
        .state = @ptrCast(&registry),
        .lookup_fn = RecoveryRegistry.lookup,
    };

    try std.testing.expectError(
        error.bad_rotation_authority_signature,
        nullifier.verifyNullifier(payload, &signers, lookup),
    );
}

test "D-W2 P3 verify — missing_rotation_authority when lookup returns null" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const target_priv: [32]u8 = .{0x42} ** 32;
    const replacement_priv: [32]u8 = .{0x43} ** 32;
    const authority_priv: [32]u8 = .{0x44} ** 32;
    const target_pubkey = try pubkeyFromPriv(target_priv);
    const replacement_pubkey = try pubkeyFromPriv(replacement_priv);

    var pubkey_hex: [66]u8 = undefined;
    hexEncode33(target_pubkey, &pubkey_hex);
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", pubkey_hex[0..], "rec-acme-MISSING"),
    };

    const ts: u64 = 1_725_000_000;
    const sig = try nullifier.signRotationAuthority(authority_priv, target_pubkey, replacement_pubkey, ts);
    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = target_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };

    try std.testing.expectError(
        error.missing_rotation_authority,
        nullifier.verifyNullifier(payload, &signers, empty_recovery_lookup),
    );
}

test "D-W2 P3 verify — missing_replacement_for_rotation when sig present without replacement" {
    const target_priv: [32]u8 = .{0x42} ** 32;
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const target_pubkey = try pubkeyFromPriv(target_priv);
    var pubkey_hex: [66]u8 = undefined;
    hexEncode33(target_pubkey, &pubkey_hex);
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", pubkey_hex[0..], "rec-acme-001"),
    };

    // Construct a malformed payload directly (the codec rejects this
    // shape on encode; we hand-build it for the verifier-layer
    // defence-in-depth check).
    const payload = nullifier.NullifierPayload{
        .revoked_pubkey = target_pubkey,
        .reason_code = .compromised,
        .timestamp = 0,
        .replacement_pubkey = null,
        .rotation_authority_signature = .{0x77} ** 64,
    };
    try std.testing.expectError(
        error.missing_replacement_for_rotation,
        nullifier.verifyNullifier(payload, &signers, empty_recovery_lookup),
    );
}

// ─────────────────────────────────────────────────────────────────────
// applyNullifier — pure-text rewrite + idempotence
// ─────────────────────────────────────────────────────────────────────

const FIXTURE_MANIFEST_TEXT =
    \\[tenant]
    \\domain = "x.example"
    \\display_name = "X Example"
    \\owner_cert_path = "owner.cert"
    \\recovery_enrolment_id = "rec-tenant-001"
    \\
    \\[trusted_signers]
    \\require_spv = true
    \\
    \\[trusted_signers.platform]
    \\pubkey = "02platformplatformplatformplatformplatformplatformplatformplatfor"
    \\plexus_identity_tx = "00ff"
    \\scope = "*"
    \\removable = false
    \\label = "Platform"
    \\shard_group = "deadbeef"
    \\recovery_enrolment_id = "rec-platform-001"
    \\
    \\[trusted_signers.acme]
    \\pubkey = "02acmeacmeacmeacmeacmeacmeacmeacmeacmeacmeacmeacmeacmeacmeacmeac"
    \\plexus_identity_tx = "00ff"
    \\scope = "acme.*"
    \\removable = true
    \\label = "ACME"
    \\shard_group = "deadbeef"
    \\recovery_enrolment_id = "rec-acme-001"
    \\
;

fn writeFixtureManifest(dir: std.fs.Dir, name: []const u8) !void {
    const f = try dir.createFile(name, .{ .truncate = true });
    defer f.close();
    try f.writeAll(FIXTURE_MANIFEST_TEXT);
}

test "D-W2 P3 apply — pure revocation removes the entry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFixtureManifest(tmp.dir, "manifest.toml");

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    const manifest_path = try std.fs.path.join(allocator, &.{ dir_path, "manifest.toml" });
    defer allocator.free(manifest_path);
    const revoked_path = try std.fs.path.join(allocator, &.{ dir_path, "extension-revoked-keys.json" });
    defer allocator.free(revoked_path);

    const vn = nullifier.VerifiedNullifier{
        .payload = .{
            .revoked_pubkey = .{0x02} ++ [_]u8{0xab} ** 32,
            .reason_code = .voluntary,
            .timestamp = 1_725_000_000,
        },
        .target_signer_name = "acme",
    };
    var outcome = try nullifier.applyNullifier(allocator, vn, manifest_path, revoked_path, null);
    defer outcome.deinit(allocator);
    try std.testing.expectEqual(nullifier.ApplyMode.applied, outcome.mode);
    try std.testing.expect(!outcome.promoted_replacement);

    const updated = try std.fs.cwd().readFileAlloc(allocator, manifest_path, 64 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, "[trusted_signers.acme]") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "[trusted_signers.platform]") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "nullifier-applied: revoked trusted_signers.acme") != null);

    // revoked-keys index has the entry.
    const ridx = try std.fs.cwd().readFileAlloc(allocator, revoked_path, 64 * 1024);
    defer allocator.free(ridx);
    try std.testing.expect(std.mem.indexOf(u8, ridx, "voluntary") != null);
    try std.testing.expect(std.mem.indexOf(u8, ridx, "\"signer\":\"acme\"") != null);
}

test "D-W2 P3 apply — rotation rewrites pubkey + appends previous_pubkey_chain" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFixtureManifest(tmp.dir, "manifest.toml");

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    const manifest_path = try std.fs.path.join(allocator, &.{ dir_path, "manifest.toml" });
    defer allocator.free(manifest_path);
    const revoked_path = try std.fs.path.join(allocator, &.{ dir_path, "extension-revoked-keys.json" });
    defer allocator.free(revoked_path);

    const replacement: [nullifier.PUBKEY_LEN]u8 = .{0x03} ++ [_]u8{0xcd} ** 32;
    const vn = nullifier.VerifiedNullifier{
        .payload = .{
            .revoked_pubkey = .{0x02} ++ [_]u8{0xab} ** 32,
            .reason_code = .superseded,
            .timestamp = 1_725_000_000,
            .replacement_pubkey = replacement,
            .rotation_authority_signature = .{0xee} ** 64,
        },
        .target_signer_name = "acme",
    };
    var outcome = try nullifier.applyNullifier(allocator, vn, manifest_path, revoked_path, null);
    defer outcome.deinit(allocator);
    try std.testing.expectEqual(nullifier.ApplyMode.applied, outcome.mode);
    try std.testing.expect(outcome.promoted_replacement);

    const updated = try std.fs.cwd().readFileAlloc(allocator, manifest_path, 64 * 1024);
    defer allocator.free(updated);

    // New pubkey present (lowercase hex of replacement).
    const want_new = "03cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd";
    try std.testing.expect(std.mem.indexOf(u8, updated, want_new) != null);
    // Previous-pubkey-chain field present + carries the old pubkey
    // string (taken literally from the fixture).
    try std.testing.expect(std.mem.indexOf(u8, updated, "previous_pubkey_chain") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "02acmeacme") != null);
}

test "D-W2 P3 apply — replay is idempotent (already_applied)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFixtureManifest(tmp.dir, "manifest.toml");

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    const manifest_path = try std.fs.path.join(allocator, &.{ dir_path, "manifest.toml" });
    defer allocator.free(manifest_path);
    const revoked_path = try std.fs.path.join(allocator, &.{ dir_path, "extension-revoked-keys.json" });
    defer allocator.free(revoked_path);

    const vn = nullifier.VerifiedNullifier{
        .payload = .{
            .revoked_pubkey = .{0x02} ++ [_]u8{0xab} ** 32,
            .reason_code = .voluntary,
            .timestamp = 1_725_000_000,
        },
        .target_signer_name = "acme",
    };
    var first = try nullifier.applyNullifier(allocator, vn, manifest_path, revoked_path, null);
    defer first.deinit(allocator);
    try std.testing.expectEqual(nullifier.ApplyMode.applied, first.mode);

    var second = try nullifier.applyNullifier(allocator, vn, manifest_path, revoked_path, null);
    defer second.deinit(allocator);
    try std.testing.expectEqual(nullifier.ApplyMode.already_applied, second.mode);
    try std.testing.expectEqual(@as(usize, 0), second.new_manifest_text.len);
}

```
