---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_publish_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.182377+00:00
---

# runtime/semantos-brain/tests/extension_publish_conformance.zig

```zig
// Phase D-W2 Phase 1 — extension_publish conformance tests.
//
// Two-mode coverage (mirrors refund_tx_conformance.zig):
//   • Stub mode (-Denable-wasmtime=false): exercises
//     extension_publish_stub.zig.  Pure-Zig primitives (bundle hash,
//     payload assembly, shard-group derivation, sign-digest) ARE
//     reachable in the stub and are tested.  Tx construction +
//     signing + broadcast return error.bsvz_unavailable.
//   • Real mode  (-Denable-wasmtime=true): exercises
//     extension_publish.zig end-to-end:
//       - sign + verify round-trip with a deterministic priv key
//       - tx construction with a synthetic UTXO, sigHashed against a
//         P2PKH locking script derived from the same priv (so
//         signAllP2pkh succeeds)
//       - parses the result back via bsvz.transaction.Transaction.parse
//         and asserts:
//           - 1 input, 2 outputs
//           - output 0 is the OP_RETURN with our exact payload
//           - output 1 is a non-zero P2PKH change output
//           - shardGroupId derivation byte-stable for the produced txid
//
// We do NOT broadcast in tests — that's a manual smoke against ARC.

const std = @import("std");
const build_options = @import("build_options");
const ext_pub = @import("extension_publish");

// ───────────────────────────────────────────────────────────────────
// Pure-Zig invariants — exercised in BOTH modes
// ───────────────────────────────────────────────────────────────────

test "D-W2 Phase 1 — bundle hash byte-stable for a fixture file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    const data = "fixture-bundle-content-v0";
    try f.writeAll(data);
    f.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);

    const got = try ext_pub.computeBundleHash(allocator, path);
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "D-W2 Phase 1 — shardGroupId derivation byte-stable" {
    // Pinned txid -> pinned shardGroupId.  The bytes here are computed
    // by hand from the canonical formula: sha256("extension-publish:" ||
    // hex(txid)).  We recompute in-test instead of hard-coding a 32-byte
    // literal because the recompute also asserts the formula is stable
    // across Zig std versions.
    const txid: [32]u8 = .{
        0xde, 0xad, 0xbe, 0xef, 0xfe, 0xed, 0xfa, 0xce,
        0xca, 0xfe, 0xba, 0xbe, 0x12, 0x34, 0x56, 0x78,
        0x9a, 0xbc, 0xde, 0xf0, 0x11, 0x22, 0x33, 0x44,
        0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc,
    };
    const got = ext_pub.deriveShardGroupId(txid);

    // Independent reference implementation right here in the test.
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (txid, 0..) |b, i| {
        hex_buf[i * 2] = hex_chars[(b >> 4) & 0x0f];
        hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("extension-publish:");
    hasher.update(&hex_buf);
    var expected: [32]u8 = undefined;
    hasher.final(&expected);

    try std.testing.expectEqualSlices(u8, &expected, &got);
    // First byte differs from the reference txid — sanity check the
    // hash actually scrambled.
    try std.testing.expect(got[0] != txid[0]);
}

test "D-W2 Phase 1 — assemblePayload byte layout pinned" {
    const allocator = std.testing.allocator;
    const bundle_hash: [32]u8 = .{0x42} ** 32;
    const name = "oddjobz.invoicer";
    const version = "0.1.0";
    const signer_pub: [33]u8 = .{0x02} ++ [_]u8{0x99} ** 32;
    const sig: [64]u8 = .{0x77} ** 64;

    const payload = try ext_pub.assemblePayload(allocator, bundle_hash, name, version, signer_pub, sig);
    defer allocator.free(payload);

    // Byte-by-byte assertions — these are the canonical layout the
    // OP_RETURN spec pins.  Future changes to the layout MUST update
    // this test in lockstep with the spec doc.
    const tag_len = "extension-publish-v1".len;
    try std.testing.expectEqual(@as(usize, tag_len + 32 + 1 + name.len + 1 + version.len + 33 + 64), payload.len);
    try std.testing.expectEqualSlices(u8, "extension-publish-v1", payload[0..tag_len]);
    try std.testing.expectEqualSlices(u8, &bundle_hash, payload[tag_len .. tag_len + 32]);
    try std.testing.expectEqual(@as(u8, name.len), payload[tag_len + 32]);
    try std.testing.expectEqualSlices(u8, name, payload[tag_len + 32 + 1 .. tag_len + 32 + 1 + name.len]);
    const v_off = tag_len + 32 + 1 + name.len;
    try std.testing.expectEqual(@as(u8, version.len), payload[v_off]);
    try std.testing.expectEqualSlices(u8, version, payload[v_off + 1 .. v_off + 1 + version.len]);
    const pk_off = v_off + 1 + version.len;
    try std.testing.expectEqualSlices(u8, &signer_pub, payload[pk_off .. pk_off + 33]);
    try std.testing.expectEqualSlices(u8, &sig, payload[pk_off + 33 .. pk_off + 33 + 64]);
}

test "D-W2 Phase 1 — sign digest is sha256d(bundle_hash || version)" {
    const bundle_hash: [32]u8 = .{0x33} ** 32;
    const version = "1.2.3";
    const got = ext_pub.computeSignDigest(bundle_hash, version);

    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&bundle_hash);
        h.update(version);
        h.final(&first);
    }
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "D-W2 Phase 1 — assemblePayload rejects bad lengths" {
    const allocator = std.testing.allocator;
    const bh: [32]u8 = .{0} ** 32;
    const sp: [33]u8 = .{0} ** 33;
    const sg: [64]u8 = .{0} ** 64;

    try std.testing.expectError(error.name_empty, ext_pub.assemblePayload(allocator, bh, "", "0.1.0", sp, sg));
    try std.testing.expectError(error.version_empty, ext_pub.assemblePayload(allocator, bh, "n", "", sp, sg));
    const long_name = [_]u8{'x'} ** (ext_pub.MAX_NAME_LEN + 1);
    try std.testing.expectError(error.name_too_long, ext_pub.assemblePayload(allocator, bh, &long_name, "0.1.0", sp, sg));
    const long_ver = [_]u8{'1'} ** (ext_pub.MAX_VERSION_LEN + 1);
    try std.testing.expectError(error.version_too_long, ext_pub.assemblePayload(allocator, bh, "n", &long_ver, sp, sg));
}

// ───────────────────────────────────────────────────────────────────
// Stub-mode contract: bsvz_unavailable for tx + sign + broadcast
// ───────────────────────────────────────────────────────────────────

test "D-W2 Phase 1 — stub mode: signOverBundle returns bsvz_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    const priv: [32]u8 = .{0x11} ** 32;
    const bh: [32]u8 = .{0x22} ** 32;
    try std.testing.expectError(
        error.bsvz_unavailable,
        ext_pub.signOverBundle(priv, bh, "0.1.0"),
    );
}

test "D-W2 Phase 1 — stub mode: buildPublishTx returns bsvz_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    const manifest = ext_pub.BundleManifest{
        .extension_name = "x",
        .version = "0.1.0",
        .bundle_path = "irrelevant",
        .signer_priv = .{0x11} ** 32,
    };
    const utxo = ext_pub.FundingUtxo{
        .txid = .{0xab} ** 32,
        .vout = 0,
        .locking_script = &[_]u8{},
        .satoshis = 5_000,
    };
    const bh: [32]u8 = .{0x22} ** 32;
    try std.testing.expectError(
        error.bsvz_unavailable,
        ext_pub.buildPublishTx(std.testing.allocator, manifest, bh, utxo, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", 50),
    );
}

test "D-W2 Phase 1 — stub mode: broadcastViaArc returns bsvz_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    const tx_bytes = [_]u8{0x00};
    try std.testing.expectError(
        error.bsvz_unavailable,
        ext_pub.broadcastViaArc(std.testing.allocator, &tx_bytes, null, null),
    );
}

// ───────────────────────────────────────────────────────────────────
// Real mode: sign-then-verify round-trip + tx-build round-trip
// ───────────────────────────────────────────────────────────────────

test "D-W2 Phase 1 — real mode: sign + verify round-trip" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    const bsvz = @import("bsvz");

    // Deterministic priv from a seed — same approach as bkds_conformance.
    var seed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("d-w2-phase-1-test-priv-1", &seed, .{});
    const priv = try bsvz.crypto.PrivateKey.fromBytes(seed);
    const pub_key = try priv.publicKey();
    const signer_pubkey = pub_key.bytes;

    const bundle_hash: [32]u8 = .{0xab} ** 32;
    const version = "0.1.0";

    const sig = try ext_pub.signOverBundle(seed, bundle_hash, version);
    try ext_pub.verifySignature(signer_pubkey, bundle_hash, version, sig);

    // Negative path: a tampered version mismatches.
    try std.testing.expectError(
        error.proof_mismatch,
        ext_pub.verifySignature(signer_pubkey, bundle_hash, "0.2.0", sig),
    );
    // Negative path: a different signer mismatches.
    var other_seed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("d-w2-phase-1-test-priv-2", &other_seed, .{});
    const other_priv = try bsvz.crypto.PrivateKey.fromBytes(other_seed);
    const other_pub = (try other_priv.publicKey()).bytes;
    try std.testing.expectError(
        error.proof_mismatch,
        ext_pub.verifySignature(other_pub, bundle_hash, version, sig),
    );
}

test "D-W2 Phase 1 — real mode: tx OP_RETURN layout matches spec byte-for-byte" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const bsvz = @import("bsvz");

    // Build a deterministic operator priv + derive its P2PKH address;
    // the funding UTXO's locking script must hash to the same pubkey
    // hash160 the priv signs against, otherwise signAllP2pkh fails.
    var seed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("d-w2-phase-1-tx-build-priv", &seed, .{});
    // Use the secp256k1 surface directly here (matches what bsvz's
    // compat/address layer expects).  primitives.ec.PrivateKey is a
    // wrapper around the same scalar; the bytes round-trip cleanly.
    const priv = try bsvz.crypto.PrivateKey.fromBytes(seed);
    const pub_key = try priv.publicKey();
    const sec1 = pub_key.bytes;
    // P2PKH locking script: 0x76 0xa9 0x14 <hash160> 0x88 0xac
    const h160 = bsvz.crypto.hash.hash160(&sec1);
    var locking_script: [25]u8 = undefined;
    locking_script[0] = 0x76;
    locking_script[1] = 0xa9;
    locking_script[2] = 0x14;
    @memcpy(locking_script[3..23], &h160.bytes);
    locking_script[23] = 0x88;
    locking_script[24] = 0xac;

    // Address text for change output — same priv → same address → all
    // change goes back to the operator.
    const address_text = try bsvz.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, pub_key);
    defer allocator.free(address_text);

    // Create a small fixture bundle file.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.wasm", .{});
    const bundle_data = "fixture-wasm-bytes";
    try f.writeAll(bundle_data);
    f.close();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const bundle_path = try tmp.dir.realpath("bundle.wasm", &path_buf);

    const bundle_hash = try ext_pub.computeBundleHash(allocator, bundle_path);

    const manifest = ext_pub.BundleManifest{
        .extension_name = "oddjobz.invoicer",
        .version = "0.1.0",
        .bundle_path = bundle_path,
        .signer_priv = seed,
    };
    const utxo = ext_pub.FundingUtxo{
        .txid = .{0x55} ** 32,
        .vout = 0,
        .locking_script = &locking_script,
        .satoshis = 10_000,
    };

    const built = try ext_pub.buildPublishTx(allocator, manifest, bundle_hash, utxo, address_text, 50);
    defer ext_pub.freeBuiltTx(allocator, built);

    // Re-parse the produced tx.  Asserts:
    //   - 1 input, 2 outputs
    //   - output 0 satoshis = 0
    //   - output 0 locking_script starts with 0x6a 0x4c <len> ... = OP_RETURN PUSHDATA1
    //   - the OP_RETURN payload matches built.op_return_payload byte-for-byte
    //   - output 1 is non-zero (change went somewhere)
    var parsed = try bsvz.transaction.Transaction.parse(allocator, built.tx_bytes);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.inputs.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.outputs.len);

    const op_ret = parsed.outputs[0];
    try std.testing.expectEqual(@as(i64, 0), op_ret.satoshis);
    const ls = op_ret.locking_script.bytes;
    try std.testing.expect(ls.len >= 3);
    try std.testing.expectEqual(@as(u8, 0x6a), ls[0]); // OP_RETURN
    try std.testing.expectEqual(@as(u8, 0x4c), ls[1]); // OP_PUSHDATA1
    const payload_len: usize = ls[2];
    try std.testing.expectEqual(payload_len, built.op_return_payload.len);
    try std.testing.expectEqualSlices(u8, built.op_return_payload, ls[3 .. 3 + payload_len]);

    // Payload starts with the canonical tag.
    try std.testing.expectEqualSlices(u8, "extension-publish-v1", built.op_return_payload[0..20]);
    // Payload's bundle_hash slot matches what we computed.
    try std.testing.expectEqualSlices(u8, &bundle_hash, built.op_return_payload[20..52]);

    // Output 1 — change — has positive satoshis (we put 10_000 in,
    // fees come out, the rest is change to the operator).
    try std.testing.expect(parsed.outputs[1].satoshis > 0);

    // shardGroupId derivation against the produced txid is byte-stable
    // (recompute against the formula — same property as the pure test
    // above, but tied to a real produced txid this time).
    const sg = ext_pub.deriveShardGroupId(built.txid);
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (built.txid, 0..) |b, i| {
        hex_buf[i * 2] = hex_chars[(b >> 4) & 0x0f];
        hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("extension-publish:");
    hasher.update(&hex_buf);
    var expected_sg: [32]u8 = undefined;
    hasher.final(&expected_sg);
    try std.testing.expectEqualSlices(u8, &expected_sg, &sg);
}

test "D-W2 Phase 1 — real mode: bundle_hash → sign signature carries through to the on-chain payload" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const bsvz = @import("bsvz");

    var seed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("d-w2-phase-1-end-to-end-priv", &seed, .{});
    const priv = try bsvz.crypto.PrivateKey.fromBytes(seed);
    const pub_key = try priv.publicKey();
    const signer_pubkey = pub_key.bytes;

    const h160 = bsvz.crypto.hash.hash160(&signer_pubkey);
    var locking_script: [25]u8 = undefined;
    locking_script[0] = 0x76;
    locking_script[1] = 0xa9;
    locking_script[2] = 0x14;
    @memcpy(locking_script[3..23], &h160.bytes);
    locking_script[23] = 0x88;
    locking_script[24] = 0xac;

    const address_text = try bsvz.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, pub_key);
    defer allocator.free(address_text);

    const bundle_hash: [32]u8 = .{0xee} ** 32;
    const manifest = ext_pub.BundleManifest{
        .extension_name = "acme.bundle",
        .version = "1.0.0",
        .bundle_path = "ignored-by-buildPublishTx",
        .signer_priv = seed,
    };
    const utxo = ext_pub.FundingUtxo{
        .txid = .{0xaa} ** 32,
        .vout = 0,
        .locking_script = &locking_script,
        .satoshis = 5_000,
    };

    const built = try ext_pub.buildPublishTx(allocator, manifest, bundle_hash, utxo, address_text, 50);
    defer ext_pub.freeBuiltTx(allocator, built);

    // Pull the signature out of the OP_RETURN payload (last 64 bytes).
    const sig_bytes = built.op_return_payload[built.op_return_payload.len - 64 ..];
    var sig_arr: [64]u8 = undefined;
    @memcpy(&sig_arr, sig_bytes[0..64]);

    // Verify it matches signer_pubkey + (bundle_hash || version).
    try ext_pub.verifySignature(signer_pubkey, bundle_hash, "1.0.0", sig_arr);

    // The signer_pubkey slot in the payload is at offset 20 + 32 + 1 +
    // name.len + 1 + version.len.
    const name_off = 20 + 32; // tag + bundle_hash
    const name_len: usize = built.op_return_payload[name_off];
    const ver_off = name_off + 1 + name_len;
    const ver_len: usize = built.op_return_payload[ver_off];
    const pk_off = ver_off + 1 + ver_len;
    try std.testing.expectEqualSlices(u8, &signer_pubkey, built.op_return_payload[pk_off .. pk_off + 33]);
}

```
