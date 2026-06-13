---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_nullifier_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.175887+00:00
---

# runtime/semantos-brain/tests/extension_nullifier_e2e_conformance.zig

```zig
// Phase D-W2 Phase 3 — extension nullifier end-to-end conformance.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §4.2 (Nullifier Publication), §4.3 (Rotation Authority), §6
//   (frame_type = `nullifier`), §7 Phase 3.
//
// Scenarios covered (real-mode-only — signing needs bsvz):
//   • Pure revocation e2e — synthesise a nullifier frame for an
//     existing signer; POST to `/api/v1/bundle-frame`; verify+apply
//     succeeds; manifest's `[trusted_signers].<name>` entry is
//     removed; revoked-keys index has the entry; audit log shows the
//     revocation.
//   • Rotation e2e — synthesise a rotation nullifier with a
//     replacement key signed by the rotation authority; POST;
//     verify+apply succeeds; manifest's `pubkey` is the new key,
//     `previous_pubkey_chain` carries the old.
//   • Bad rotation authority signature — tamper the rotation
//     signature → reject with `bad_rotation_authority_signature` →
//     manifest unchanged.
//   • Unknown target — nullifier targets a pubkey not in the
//     manifest → reject with `unknown_target_signer`.
//   • Replay — same nullifier received twice → second apply is a
//     no-op (idempotent).
//   • Pure revocation on platform-tier — nullifier targets the
//     `[trusted_signers].platform` entry → for v0.1 ALLOW the
//     revocation but the audit log carries a CRITICAL warning line.

const std = @import("std");
const build_options = @import("build_options");
const subscriber = @import("extension_subscriber");
const subscribe_transport = @import("extension_subscribe");
const nullifier_mod = @import("extension_nullifier");
const tenant_manifest = @import("tenant_manifest");
const ext_pub = @import("extension_publish");
const audit_log_mod = @import("audit_log");

// ─────────────────────────────────────────────────────────────────────
// Frame helpers
// ─────────────────────────────────────────────────────────────────────

fn reverseTxid(in: [subscriber.TXID_LEN]u8) [subscriber.TXID_LEN]u8 {
    var out: [subscriber.TXID_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < subscriber.TXID_LEN) : (i += 1) out[i] = in[subscriber.TXID_LEN - 1 - i];
    return out;
}

fn hexEncode33(bytes: [33]u8, out: []u8) void {
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

fn pubkeyFromPriv(priv_bytes: [32]u8) ![nullifier_mod.PUBKEY_LEN]u8 {
    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(priv_bytes);
    const pub_key = try priv.publicKey();
    return pub_key.bytes;
}

/// Build a BRC-12 frame whose inner payload is a `nullifier-frame-v1`
/// envelope.  Layout matches the receive-pipeline frame_type
/// dispatch (extension_subscriber.decodeNullifierFrame) — same outer
/// BRC-12 magic / protocol / version, inner tag selects the frame
/// type.
///
///   Inner payload:
///     tag_len             u8                       (1 byte)
///     "nullifier-frame-v1"                         (18 bytes)
///     nullifier_payload_len  u32 BE                (4 bytes)
///     nullifier_payload                            (N bytes — produced by
///                                                   nullifier.encodeNullifierPayload)
fn buildNullifierFrame(
    allocator: std.mem.Allocator,
    txid_internal: [subscriber.TXID_LEN]u8,
    nullifier_payload: []const u8,
) ![]u8 {
    const tag = subscriber.NULLIFIER_FRAME_TYPE_TAG;
    const inner_len: usize = 1 + tag.len + 4 + nullifier_payload.len;
    const inner = try allocator.alloc(u8, inner_len);
    defer allocator.free(inner);
    var off: usize = 0;
    inner[off] = @intCast(tag.len);
    off += 1;
    @memcpy(inner[off .. off + tag.len], tag);
    off += tag.len;
    inner[off] = @intCast(nullifier_payload.len >> 24);
    inner[off + 1] = @intCast((nullifier_payload.len >> 16) & 0xff);
    inner[off + 2] = @intCast((nullifier_payload.len >> 8) & 0xff);
    inner[off + 3] = @intCast(nullifier_payload.len & 0xff);
    off += 4;
    @memcpy(inner[off .. off + nullifier_payload.len], nullifier_payload);

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

fn makeSigner(name: []const u8, pubkey_hex: []const u8, recovery_id: []const u8, removable: bool) tenant_manifest.TrustedSigner {
    return .{
        .name = name,
        .pubkey_hex = pubkey_hex,
        .plexus_identity_tx_hex = "00" ** 32,
        .scopes = &.{},
        .removable = removable,
        .label = name,
        .shard_group = "deadbeef" ** 8,
        .recovery_enrolment_id = recovery_id,
    };
}

const RecoveryItem = struct {
    recovery_enrolment_id: []const u8,
    pubkey: [nullifier_mod.PUBKEY_LEN]u8,
};

const RecoveryRegistry = struct {
    items: []const RecoveryItem,

    fn lookup(state: ?*anyopaque, recovery_enrolment_id: []const u8) ?[nullifier_mod.PUBKEY_LEN]u8 {
        const self: *const RecoveryRegistry = @ptrCast(@alignCast(state.?));
        for (self.items) |it| {
            if (std.mem.eql(u8, it.recovery_enrolment_id, recovery_enrolment_id)) {
                return it.pubkey;
            }
        }
        return null;
    }
};

const empty_recovery_lookup = nullifier_mod.RecoveryAuthorityLookup{
    .state = null,
    .lookup_fn = struct {
        fn lookup(state: ?*anyopaque, _: []const u8) ?[nullifier_mod.PUBKEY_LEN]u8 {
            _ = state;
            return null;
        }
    }.lookup,
};

const FIXTURE_MANIFEST_TEMPLATE =
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
    \\pubkey = "{s}"
    \\plexus_identity_tx = "00ff"
    \\scope = "*"
    \\removable = false
    \\label = "Platform"
    \\shard_group = "deadbeef"
    \\recovery_enrolment_id = "rec-platform-001"
    \\
    \\[trusted_signers.acme]
    \\pubkey = "{s}"
    \\plexus_identity_tx = "00ff"
    \\scope = "acme.*"
    \\removable = true
    \\label = "ACME"
    \\shard_group = "deadbeef"
    \\recovery_enrolment_id = "rec-acme-001"
    \\
;

fn writeFixtureManifest(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    platform_pubkey_hex: []const u8,
    acme_pubkey_hex: []const u8,
) !void {
    const text = try std.fmt.allocPrint(allocator, FIXTURE_MANIFEST_TEMPLATE, .{ platform_pubkey_hex, acme_pubkey_hex });
    defer allocator.free(text);
    const f = try dir.createFile(name, .{ .truncate = true });
    defer f.close();
    try f.writeAll(text);
}

// ─────────────────────────────────────────────────────────────────────
// Setup helper — common scaffolding shared across tests
// ─────────────────────────────────────────────────────────────────────

const E2eEnv = struct {
    allocator: std.mem.Allocator,
    tmp: *std.testing.TmpDir,
    data_dir: []const u8,
    manifest_path: []const u8,
    revoked_path: []const u8,
    audit_path: []const u8,
    audit: audit_log_mod.AuditLog,
    platform_priv: [32]u8,
    platform_pubkey: [nullifier_mod.PUBKEY_LEN]u8,
    acme_priv: [32]u8,
    acme_pubkey: [nullifier_mod.PUBKEY_LEN]u8,
    authority_priv: [32]u8,
    authority_pubkey: [nullifier_mod.PUBKEY_LEN]u8,
    platform_pubkey_hex: [66]u8,
    acme_pubkey_hex: [66]u8,
    signers: [2]tenant_manifest.TrustedSigner,
    recovery_items: [1]RecoveryItem,
    registry: RecoveryRegistry,

    fn deinit(self: *E2eEnv) void {
        self.audit.close();
        self.allocator.free(self.data_dir);
        self.allocator.free(self.manifest_path);
        self.allocator.free(self.revoked_path);
        self.allocator.free(self.audit_path);
    }

    fn lookup(self: *E2eEnv) nullifier_mod.RecoveryAuthorityLookup {
        return .{
            .state = @ptrCast(&self.registry),
            .lookup_fn = RecoveryRegistry.lookup,
        };
    }
};

fn setupE2eEnv(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) !*E2eEnv {
    const env = try allocator.create(E2eEnv);
    errdefer allocator.destroy(env);

    env.allocator = allocator;
    env.tmp = tmp;

    env.platform_priv = .{0x11} ** 32;
    env.acme_priv = .{0x22} ** 32;
    env.authority_priv = .{0x33} ** 32;
    env.platform_pubkey = try pubkeyFromPriv(env.platform_priv);
    env.acme_pubkey = try pubkeyFromPriv(env.acme_priv);
    env.authority_pubkey = try pubkeyFromPriv(env.authority_priv);
    hexEncode33(env.platform_pubkey, &env.platform_pubkey_hex);
    hexEncode33(env.acme_pubkey, &env.acme_pubkey_hex);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);
    env.data_dir = try allocator.dupe(u8, dir_path);
    env.manifest_path = try std.fs.path.join(allocator, &.{ env.data_dir, "manifest.toml" });
    env.revoked_path = try std.fs.path.join(allocator, &.{ env.data_dir, "extension-revoked-keys.json" });
    env.audit_path = try std.fs.path.join(allocator, &.{ env.data_dir, "audit.log" });

    try writeFixtureManifest(
        allocator,
        tmp.dir,
        "manifest.toml",
        env.platform_pubkey_hex[0..],
        env.acme_pubkey_hex[0..],
    );

    env.audit = audit_log_mod.AuditLog.init();
    try env.audit.open(env.audit_path);

    env.signers = .{
        makeSigner("platform", env.platform_pubkey_hex[0..], "rec-platform-001", false),
        makeSigner("acme", env.acme_pubkey_hex[0..], "rec-acme-001", true),
    };

    env.recovery_items = .{
        .{ .recovery_enrolment_id = "rec-acme-001", .pubkey = env.authority_pubkey },
    };
    env.registry = .{ .items = &env.recovery_items };

    return env;
}

// ─────────────────────────────────────────────────────────────────────
// e2e tests
// ─────────────────────────────────────────────────────────────────────

test "D-W2 P3 e2e — pure revocation: HTTP processFrame applies the nullifier" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = env.acme_pubkey,
        .reason_code = .voluntary,
        .timestamp = 1_725_000_000,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x55} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);

    const updated = try std.fs.cwd().readFileAlloc(allocator, env.manifest_path, 64 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, "[trusted_signers.acme]") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "[trusted_signers.platform]") != null);

    const ridx = try std.fs.cwd().readFileAlloc(allocator, env.revoked_path, 64 * 1024);
    defer allocator.free(ridx);
    try std.testing.expect(std.mem.indexOf(u8, ridx, "voluntary") != null);

    env.audit.close();
    const audit_bytes = try std.fs.cwd().readFileAlloc(allocator, env.audit_path, 64 * 1024);
    defer allocator.free(audit_bytes);
    try std.testing.expect(std.mem.indexOf(u8, audit_bytes, "extension.nullifier_apply") != null);
    try std.testing.expect(std.mem.indexOf(u8, audit_bytes, "phase=apply mode=revocation") != null);
}

test "D-W2 P3 e2e — rotation: replacement key promoted, chain captures old key" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const replacement_priv: [32]u8 = .{0x44} ** 32;
    const replacement_pubkey = try pubkeyFromPriv(replacement_priv);
    const ts: u64 = 1_725_000_000;
    const sig = try nullifier_mod.signRotationAuthority(env.authority_priv, env.acme_pubkey, replacement_pubkey, ts);

    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = env.acme_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x66} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);

    const updated = try std.fs.cwd().readFileAlloc(allocator, env.manifest_path, 64 * 1024);
    defer allocator.free(updated);
    var replacement_hex: [66]u8 = undefined;
    hexEncode33(replacement_pubkey, &replacement_hex);
    try std.testing.expect(std.mem.indexOf(u8, updated, replacement_hex[0..]) != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "previous_pubkey_chain") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, env.acme_pubkey_hex[0..]) != null);
}

test "D-W2 P3 e2e — bad rotation authority signature rejected, manifest unchanged" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const replacement_priv: [32]u8 = .{0x44} ** 32;
    const replacement_pubkey = try pubkeyFromPriv(replacement_priv);
    const ts: u64 = 1_725_000_000;
    var sig = try nullifier_mod.signRotationAuthority(env.authority_priv, env.acme_pubkey, replacement_pubkey, ts);
    sig[5] ^= 0xff;

    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = env.acme_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x77} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    const before = try std.fs.cwd().readFileAlloc(allocator, env.manifest_path, 64 * 1024);
    defer allocator.free(before);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.unauthorized, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "bad_rotation_authority_signature") != null);

    const after = try std.fs.cwd().readFileAlloc(allocator, env.manifest_path, 64 * 1024);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "D-W2 P3 e2e — unknown target signer rejected" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const stranger_priv: [32]u8 = .{0x55} ** 32;
    const stranger_pubkey = try pubkeyFromPriv(stranger_priv);
    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = stranger_pubkey,
        .reason_code = .compromised,
        .timestamp = 0,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x88} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "unknown_target_signer") != null);
}

test "D-W2 P3 e2e — replay is idempotent (already_applied) on same nullifier" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = env.acme_pubkey,
        .reason_code = .voluntary,
        .timestamp = 1_725_000_000,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0x99} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const o1 = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(o1.body);
    try std.testing.expectEqual(std.http.Status.ok, o1.http_status);
    try std.testing.expect(std.mem.indexOf(u8, o1.body, "\"applied\":true") != null);

    const o2 = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(o2.body);
    try std.testing.expectEqual(std.http.Status.ok, o2.http_status);
    try std.testing.expect(std.mem.indexOf(u8, o2.body, "\"already_applied\":true") != null);
}

test "D-W2 P3 e2e — pure revocation on platform tier ALLOWED, audit logs CRITICAL" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try setupE2eEnv(allocator, &tmp);
    defer {
        env.deinit();
        allocator.destroy(env);
    }

    const payload = nullifier_mod.NullifierPayload{
        .revoked_pubkey = env.platform_pubkey,
        .reason_code = .breach,
        .timestamp = 1_725_000_000,
    };
    const payload_bytes = try nullifier_mod.encodeNullifierPayload(allocator, payload);
    defer allocator.free(payload_bytes);

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xaa} ** 32;
    const frame = try buildNullifierFrame(allocator, reverseTxid(txid_display), payload_bytes);
    defer allocator.free(frame);

    var acceptor = subscribe_transport.FrameAcceptor.initFull(
        allocator,
        &env.signers,
        nullSpv(),
        null,
        &env.audit,
        env.data_dir,
        env.lookup(),
        env.manifest_path,
        env.revoked_path,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);

    const updated = try std.fs.cwd().readFileAlloc(allocator, env.manifest_path, 64 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, "[trusted_signers.platform]") == null);

    env.audit.close();
    const audit_bytes = try std.fs.cwd().readFileAlloc(allocator, env.audit_path, 64 * 1024);
    defer allocator.free(audit_bytes);
    try std.testing.expect(std.mem.indexOf(u8, audit_bytes, "extension.platform_tier_revoked") != null);
    try std.testing.expect(std.mem.indexOf(u8, audit_bytes, "phase=critical") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Null SPV — nullifier frames don't need SPV lookup; subscriber's
// switch checks frame_type before calling SPV for bundle frames.
// ─────────────────────────────────────────────────────────────────────

fn nullSpv() subscriber.SpvClient {
    return .{
        .state = null,
        .lookup_fn = struct {
            fn lookup(_: ?*anyopaque, _: [subscriber.TXID_LEN]u8) ?subscriber.SpvLookup {
                return null;
            }
        }.lookup,
    };
}

```
