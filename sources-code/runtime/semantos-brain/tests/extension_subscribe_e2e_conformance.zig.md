---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_subscribe_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.176749+00:00
---

# runtime/semantos-brain/tests/extension_subscribe_e2e_conformance.zig

```zig
// Phase D-W2 Phase 2 — extension subscribe end-to-end conformance.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2
//   (subscribing flow), §5.3 (late joiners), §7 Phase 2.
//
// Scenarios covered:
//   • Happy path: synthesise a frame matching Phase 1's published
//     shape; processFrame verifies + applies; the bundle file lands
//     under <data_dir>/extensions/<ns>/<v>/bundle.bin.
//   • Untrusted signer.
//   • Scope violation (acme.* publishes oddjobz.foo).
//   • Hash mismatch (frame bundle bytes differ from publish-tx
//     commitment).
//   • Replay idempotence (re-publish same frame; second apply is a
//     no-op).
//   • Late-joiner replay (replayHistorical processes 3 historical
//     frames in order, all 3 apply).
//
// Real-mode-only — signature verification needs bsvz.

const std = @import("std");
const build_options = @import("build_options");
const subscriber = @import("extension_subscriber");
const subscribe_transport = @import("extension_subscribe");
const tenant_manifest = @import("tenant_manifest");
const ext_pub = @import("extension_publish");
const audit_log_mod = @import("audit_log");

// ───────────────────────────────────────────────────────────────────
// Fixtures (multi-tx; the SPV stub holds a registry).
// ───────────────────────────────────────────────────────────────────

const Fixture = struct {
    txid_display: [subscriber.TXID_LEN]u8,
    bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8,
    signature: [subscriber.SIG_LEN]u8,
    signer_pubkey: [subscriber.PUBKEY_LEN]u8,
    extension_name: []const u8,
    version: []const u8,
    depth: u32,
};

const Registry = struct {
    items: []const Fixture,

    fn lookup(state: ?*anyopaque, txid: [subscriber.TXID_LEN]u8) ?subscriber.SpvLookup {
        const self: *const Registry = @ptrCast(@alignCast(state.?));
        for (self.items) |it| {
            if (std.mem.eql(u8, &it.txid_display, &txid)) {
                return .{
                    .bundle_hash = it.bundle_hash,
                    .signature = it.signature,
                    .signer_pubkey = it.signer_pubkey,
                    .extension_name = it.extension_name,
                    .version = it.version,
                    .depth = it.depth,
                };
            }
        }
        return null;
    }
};

// ───────────────────────────────────────────────────────────────────
// Frame helpers (duplicated from the conformance file so this test
// stays self-contained — Zig tests can't share helpers across files
// without an extra module).
// ───────────────────────────────────────────────────────────────────

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

fn buildFrame(
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

fn pubkeyFromPriv(priv_bytes: [32]u8) ![subscriber.PUBKEY_LEN]u8 {
    const bsvz = @import("bsvz");
    const priv = try bsvz.crypto.PrivateKey.fromBytes(priv_bytes);
    const pub_key = try priv.publicKey();
    return pub_key.bytes;
}

// ───────────────────────────────────────────────────────────────────
// e2e tests
// ───────────────────────────────────────────────────────────────────

test "D-W2 P2 e2e — happy path: HTTP processFrame applies a verified frame" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x21} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    const bundle_bytes = "the-bundle-bytes-for-e2e-happy-path";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xab} ** 32;
    const fixtures = [_]Fixture{.{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "oddjobz.invoicer",
        .version = "0.1.0",
        .depth = 6,
    }};
    var registry = Registry{ .items = &fixtures };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"oddjobz.*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("oddjobz", hex_buf[0..], &scopes),
    };

    const frame = try buildFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "oddjobz.invoicer",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    try audit.open(audit_path);

    var acceptor = subscribe_transport.FrameAcceptor.init(
        allocator,
        &signers,
        spv,
        null,
        &audit,
        data_dir,
    );

    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);

    // Bundle file landed at the expected path.
    const bundle_path = try std.fs.path.join(allocator, &.{ data_dir, "extensions", "oddjobz.invoicer", "0.1.0", "bundle.bin" });
    defer allocator.free(bundle_path);
    const f = try std.fs.cwd().openFile(bundle_path, .{});
    defer f.close();
    const stat = try f.stat();
    try std.testing.expectEqual(@as(u64, bundle_bytes.len), stat.size);

    // Audit log carries the apply line.
    audit.close();
    const audit_bytes = try std.fs.cwd().readFileAlloc(allocator, audit_path, 64 * 1024);
    defer allocator.free(audit_bytes);
    try std.testing.expect(std.mem.indexOf(u8, audit_bytes, "extension.apply") != null);
}

test "D-W2 P2 e2e — untrusted signer rejects with unknown_signer" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x22} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xcc} ** 32;
    const fixtures = [_]Fixture{.{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 6,
    }};
    var registry = Registry{ .items = &fixtures };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    // Manifest carries a DIFFERENT signer.
    const other_pubkey_hex = "02" ++ ("99" ** 32);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("other", other_pubkey_hex, &scopes),
    };

    const frame = try buildFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var acceptor = subscribe_transport.FrameAcceptor.init(allocator, &signers, spv, null, null, data_dir);
    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "unknown_signer") != null);
}

test "D-W2 P2 e2e — scope violation rejects with scope_mismatch" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x23} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    const bundle_bytes = "fixture";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xdd} ** 32;
    const fixtures = [_]Fixture{.{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "oddjobz.foo",
        .version = "0.1.0",
        .depth = 6,
    }};
    var registry = Registry{ .items = &fixtures };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"acme.*"};
    const signers = [_]tenant_manifest.TrustedSigner{
        makeSigner("acme", hex_buf[0..], &scopes),
    };

    const frame = try buildFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "oddjobz.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var acceptor = subscribe_transport.FrameAcceptor.init(allocator, &signers, spv, null, null, data_dir);
    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "scope_mismatch") != null);
}

test "D-W2 P2 e2e — hash mismatch: frame bundle differs from publish-tx commitment" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x24} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    const committed_hash: [subscriber.BUNDLE_HASH_LEN]u8 = .{0x11} ** 32;
    const sig = try ext_pub.signOverBundle(signer_priv, committed_hash, "0.1.0");

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xee} ** 32;
    const fixtures = [_]Fixture{.{
        .txid_display = txid_display,
        .bundle_hash = committed_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 6,
    }};
    var registry = Registry{ .items = &fixtures };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    // Frame bytes are tampered (don't match committed hash).
    const tampered = "this-isnt-the-bundle-the-publish-tx-committed";
    const frame = try buildFrame(
        allocator,
        reverseTxid(txid_display),
        tampered,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var acceptor = subscribe_transport.FrameAcceptor.init(allocator, &signers, spv, null, null, data_dir);
    const outcome = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "hash_mismatch") != null);
}

test "D-W2 P2 e2e — replay idempotence: re-publishing same frame is a no-op" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x25} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    const bundle_bytes = "replay-idempotence-bundle";
    var bundle_hash: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const sig = try ext_pub.signOverBundle(signer_priv, bundle_hash, "0.1.0");

    const txid_display: [subscriber.TXID_LEN]u8 = .{0xa1} ** 32;
    const fixtures = [_]Fixture{.{
        .txid_display = txid_display,
        .bundle_hash = bundle_hash,
        .signature = sig,
        .signer_pubkey = signer_pubkey,
        .extension_name = "x.foo",
        .version = "0.1.0",
        .depth = 6,
    }};
    var registry = Registry{ .items = &fixtures };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    const frame = try buildFrame(
        allocator,
        reverseTxid(txid_display),
        bundle_bytes,
        "x.foo",
        "0.1.0",
        signer_pubkey,
    );
    defer allocator.free(frame);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var acceptor = subscribe_transport.FrameAcceptor.init(allocator, &signers, spv, null, null, data_dir);

    const o1 = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(o1.body);
    try std.testing.expectEqual(std.http.Status.ok, o1.http_status);
    try std.testing.expect(std.mem.indexOf(u8, o1.body, "\"already_applied\":false") != null);

    const o2 = try subscribe_transport.processFrame(&acceptor, frame);
    defer allocator.free(o2.body);
    try std.testing.expectEqual(std.http.Status.ok, o2.http_status);
    try std.testing.expect(std.mem.indexOf(u8, o2.body, "\"already_applied\":true") != null);
}

// ───────────────────────────────────────────────────────────────────
// Late-joiner replay
// ───────────────────────────────────────────────────────────────────

const HistoricalReplay = struct {
    frames: [][]const u8,
    cursor: usize = 0,

    fn next(state: ?*anyopaque, signer_name: []const u8, since_block_height: u32) ?[]const u8 {
        _ = signer_name;
        _ = since_block_height;
        const self: *HistoricalReplay = @ptrCast(@alignCast(state.?));
        if (self.cursor >= self.frames.len) return null;
        const frame = self.frames[self.cursor];
        self.cursor += 1;
        return frame;
    }
    fn close(state: ?*anyopaque) void {
        const self: *HistoricalReplay = @ptrCast(@alignCast(state.?));
        self.cursor = 0;
    }
};

test "D-W2 P2 e2e — late-joiner replay applies 3 historical frames in order" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const signer_priv: [32]u8 = .{0x26} ** 32;
    const signer_pubkey = try pubkeyFromPriv(signer_priv);

    var hex_buf: [66]u8 = undefined;
    hexEncode33(signer_pubkey, &hex_buf);
    const scopes = [_][]const u8{"x.*"};
    const signers = [_]tenant_manifest.TrustedSigner{ makeSigner("x", hex_buf[0..], &scopes) };

    // Three historical frames — all under the same signer + scope,
    // different versions.
    const versions = [_][]const u8{ "0.1.0", "0.2.0", "0.3.0" };
    const namespaces = [_][]const u8{ "x.foo", "x.bar", "x.baz" };
    const txids = [_][subscriber.TXID_LEN]u8{
        .{0xb1} ** 32,
        .{0xb2} ** 32,
        .{0xb3} ** 32,
    };

    var fixtures_buf: [3]Fixture = undefined;
    var frames_buf: [3][]u8 = undefined;
    const bundle_bytes_buf: [3][]const u8 = .{ "frame-1-bytes", "frame-2-bytes-different", "frame-3-bytes-yet-another" };
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var bh: [subscriber.BUNDLE_HASH_LEN]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bundle_bytes_buf[i], &bh, .{});
        const sig = try ext_pub.signOverBundle(signer_priv, bh, versions[i]);
        fixtures_buf[i] = .{
            .txid_display = txids[i],
            .bundle_hash = bh,
            .signature = sig,
            .signer_pubkey = signer_pubkey,
            .extension_name = namespaces[i],
            .version = versions[i],
            .depth = 6,
        };
        frames_buf[i] = try buildFrame(
            allocator,
            reverseTxid(txids[i]),
            bundle_bytes_buf[i],
            namespaces[i],
            versions[i],
            signer_pubkey,
        );
    }
    defer for (frames_buf) |f| allocator.free(f);

    var registry = Registry{ .items = &fixtures_buf };
    const spv = subscriber.SpvClient{ .state = @ptrCast(&registry), .lookup_fn = Registry.lookup };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var slices_buf: [3][]const u8 = undefined;
    for (frames_buf, 0..) |f, j| slices_buf[j] = f;
    var replay_state = HistoricalReplay{ .frames = slices_buf[0..] };
    const source = subscriber.ReplaySource{
        .state = @ptrCast(&replay_state),
        .next_fn = HistoricalReplay.next,
        .close_fn = HistoricalReplay.close,
    };

    const applied = try subscriber.replayHistorical(
        allocator,
        signers[0],
        0,
        &signers,
        spv,
        source,
        data_dir,
        null,
        null,
        .{},
    );
    try std.testing.expectEqual(@as(u32, 3), applied);

    // Each frame's bundle landed at its own path.
    var k: usize = 0;
    while (k < 3) : (k += 1) {
        const p = try std.fs.path.join(allocator, &.{ data_dir, "extensions", namespaces[k], versions[k], "bundle.bin" });
        defer allocator.free(p);
        const f = try std.fs.cwd().openFile(p, .{});
        defer f.close();
    }
}

```
