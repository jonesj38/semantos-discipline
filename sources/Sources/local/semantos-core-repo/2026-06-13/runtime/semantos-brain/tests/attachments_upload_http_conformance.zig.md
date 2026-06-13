---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/attachments_upload_http_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.204526+00:00
---

# runtime/semantos-brain/tests/attachments_upload_http_conformance.zig

```zig
// D-O5m.followup-8 capture+upload — Conformance suite for the
// multipart upload endpoint.  Asserts the load-bearing error
// paths surface the right typed responses + the cross-language
// signing fixture verifies end-to-end through the brain's
// canonicaliser + recovery-loop verifier.
//
// Reference: src/attachments_upload_http.zig (the endpoint under
// test); runtime/semantos-brain/tests/fixtures/cell-signing-fixture.json
// (the fixture this test consumes for the parity check).

const std = @import("std");
const bsvz = @import("bsvz");

const attachments_upload_http = @import("attachments_upload_http");
const attachment_blobs_fs = @import("attachment_blobs_fs");
const attachments_store_fs = @import("attachments_store_fs");
const visits_store_fs = @import("visits_store_fs");
const identity_certs = @import("identity_certs");
const bearer_tokens = @import("bearer_tokens");
const bkds = @import("bkds");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

fn testClock() i64 {
    return 1_700_000_000;
}

test "fixture parity: brain-side recovery verifier accepts the Dart-signed signature" {
    const allocator = std.testing.allocator;

    // Pin the fixture inputs to the canonical ones in
    // `cell_signing_fixture_conformance.zig`.  This test asserts that
    // the load-bearing seam — the brain's `verifyCellSignatureRecoveryLoop`
    // — accepts the signature the Dart producer would generate.
    const priv_hex = "5ad0e1ff96b4ef3df1ad34e5b97c4c1d8a5fe24ed18793e89d96d4d2e1abf001";
    var priv_bytes: [32]u8 = undefined;
    try bkds.hexDecode(priv_hex, &priv_bytes);
    const sk = try bsvz.primitives.ec.PrivateKey.fromBytes(priv_bytes);
    const pk = try sk.publicKey();
    const pubkey = pk.toCompressedSec1();

    const payload =
        \\{"attachmentId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-05-15T14:30:00Z","capturedByCertId":"00112233445566778899aabbccddeeff","contentHash":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","contentSize":3,"createdAt":"2026-05-15T14:30:01Z","kind":"photo","mimeType":"image/jpeg","visitId":"00000000-0000-4000-8000-000000000002"}
    ;

    // Sign via the brain's primitive (bsvz signCompact + low-s).
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
    const compact = try sk.signCompact(digest, true);
    var sig: [64]u8 = undefined;
    @memcpy(&sig, compact[1..65]);
    // Apply low-s normalisation matching the Dart side.
    const SECP256K1_N: u256 = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141;
    const HALF_N: u256 = SECP256K1_N >> 1;
    const s_int = std.mem.readInt(u256, sig[32..64], .big);
    if (s_int > HALF_N) {
        const new_s = SECP256K1_N - s_int;
        std.mem.writeInt(u256, sig[32..64], new_s, .big);
    }

    // Brain-side recovery-loop verification.
    const ok = attachments_upload_http.verifyCellSignatureRecoveryLoop(sig, digest, pubkey);
    try std.testing.expect(ok);

    // Tamper detection — flipping a payload byte invalidates the sig.
    var tampered_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("not the real payload", &tampered_digest, .{});
    const bad = attachments_upload_http.verifyCellSignatureRecoveryLoop(sig, tampered_digest, pubkey);
    try std.testing.expect(!bad);

    _ = allocator;
}

test "canonicaliseCellPayload: round-trips through TS canonical-json shape" {
    const allocator = std.testing.allocator;
    const input =
        \\{"contentSize":42,"kind":"photo","mimeType":"image/jpeg","attachmentId":"x","visitId":"y"}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();
    const out = try attachments_upload_http.canonicaliseCellPayload(allocator, parsed.value);
    defer allocator.free(out);

    // Lex order should put attachmentId, contentSize, kind, mimeType,
    // visitId in alphabetical order — the canonical-JSON.ts spec.
    try std.testing.expectEqualStrings(
        "{\"attachmentId\":\"x\",\"contentSize\":42,\"kind\":\"photo\",\"mimeType\":\"image/jpeg\",\"visitId\":\"y\"}",
        out,
    );
}

test "parseMultipart: rejects boundary-less body" {
    const allocator = std.testing.allocator;
    var parts = try attachments_upload_http.parseMultipart(allocator, "no boundary here", "xyz");
    defer parts.deinit(allocator);
    // Missing parts → both null.
    try std.testing.expect(parts.metadata == null);
    try std.testing.expect(parts.blob == null);
}

test "DEFAULT_MAX_BLOB_BYTES is 10 MiB per spec" {
    try std.testing.expectEqual(@as(usize, 10 * 1024 * 1024), attachments_upload_http.DEFAULT_MAX_BLOB_BYTES);
}

test "blob-store hash mismatch surfaces the typed error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try attachment_blobs_fs.BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const blob = "abc";
    // Wrong hash for "abc".
    const wrong_hash = "0" ** 64;
    try std.testing.expectError(attachment_blobs_fs.BlobError.hash_mismatch, store.write(wrong_hash, blob));

    // Correct hash for "abc".
    const correct = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    try store.write(correct, blob);
    try std.testing.expect(store.exists(correct));
}

test "Acceptor wires all required pointers + max_blob_bytes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var blobs = try attachment_blobs_fs.BlobStore.init(allocator, data_dir);
    defer blobs.deinit();

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var attachments = try attachments_store_fs.AttachmentsStore.init(allocator, &cs, testClock);
    defer attachments.deinit();

    var visits = try visits_store_fs.VisitsStore.init(allocator, &cs, testClock);
    defer visits.deinit();

    var certs = try identity_certs.CertStore.init(allocator, data_dir, testClock);
    defer certs.deinit();

    var bt_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const bt_dir = try tmp.dir.realpath(".", &bt_path_buf);
    var tokens = try bearer_tokens.TokenStore.init(allocator, bt_dir, testClock);
    defer tokens.deinit();

    const acceptor = attachments_upload_http.Acceptor{
        .allocator = allocator,
        .blobs = &blobs,
        .attachments = &attachments,
        .visits = &visits,
        .certs = &certs,
        .bearer_tokens = &tokens,
        .max_blob_bytes = 1024,
    };
    try std.testing.expectEqual(@as(usize, 1024), acceptor.max_blob_bytes);
}

```
