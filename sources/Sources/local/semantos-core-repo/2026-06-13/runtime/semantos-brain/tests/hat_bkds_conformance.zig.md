---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/hat_bkds_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.184292+00:00
---

# runtime/semantos-brain/tests/hat_bkds_conformance.zig

```zig
// D-DOG.1.0c Phase 4 row B.1/B.3 — hat_bkds + verifier conformance.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 4
//            rows B.1, B.3;
//            runtime/semantos-brain/src/hat_bkds.zig (signing primitive);
//            runtime/semantos-brain/src/hat_bkds_verifier.zig (verifier).
//
// What this closes:
//
//   • Sign/verify round-trip — sign a payload, then verify with both
//     paths (operator-side `verifyCell`, external `verifyCellExternal`)
//     and assert success.
//
//   • Idempotent re-sign — calling signCell twice with byte-identical
//     payload produces byte-identical (derived_pubkey, signature)
//     pairs.  This is what backs the `brain resign-pending` no-op
//     property.
//
//   • Recoverability from root + cellID alone — given only the
//     operator's root_priv + a cell's content_hash, the verifier
//     re-derives the expected pubkey without holding any per-cell
//     ephemeral state.  This is the §2 "Recoverable from root +
//     scope + cellContentHash" property.
//
//   • Tamper detection — modifying the payload, the signature, or
//     using the wrong root each surface a typed error.
//
//   • Unlinkability — two cells with distinct payloads produce
//     distinct derived pubkeys (the privacy property: third parties
//     can't cluster cells by signing key).

const std = @import("std");
const bkds = @import("bkds");
const hat_bkds = @import("hat_bkds");
const hat_bkds_verifier = @import("hat_bkds_verifier");

test "hat_bkds: sign + verifyCell round-trip succeeds" {
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-1");
    defer hat.deinit();

    const payload = "{\"cellId\":\"deadbeef\",\"data\":\"xyz\",\"createdAt\":\"2026-05-04T00:00:00Z\"}";
    const signed = try hat.signCell(payload, "");

    try hat_bkds_verifier.verifyCell(
        hat.root_priv,
        payload,
        signed.derived_pubkey,
        signed.signature,
    );
}

test "hat_bkds: sign + verifyCellExternal succeeds without root access" {
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-2");
    defer hat.deinit();

    const payload = "{\"x\":1}";
    const signed = try hat.signCell(payload, "");

    // External verifier — third party with no root access — still
    // can verify the (signed_by, signature) pair against the
    // canonical payload.
    try hat_bkds_verifier.verifyCellExternal(
        payload,
        signed.derived_pubkey,
        signed.signature,
    );
}

test "hat_bkds: idempotent re-sign yields byte-identical (pubkey, signature)" {
    // The `brain resign-pending` admin verb's safety property: re-
    // signing the same canonical payload always converges on the
    // same (derived_pubkey, signature) pair.  This test asserts that
    // property so the resign-pending path is genuinely a no-op when
    // run twice over the same corpus.
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-3");
    defer hat.deinit();

    const payload = "{\"cellId\":\"abc\",\"name\":\"jane\"}";
    const first = try hat.signCell(payload, "");
    const second = try hat.signCell(payload, "");

    try std.testing.expectEqualSlices(u8, &first.derived_pubkey, &second.derived_pubkey);
    try std.testing.expectEqualSlices(u8, &first.signature, &second.signature);
}

test "hat_bkds: recoverable from root + cellID alone (no per-cell state)" {
    // Matrix §2 property: given only (root_priv, content_hash), the
    // verifier re-derives the expected signing pubkey — no per-cell
    // ephemeral state was retained at signing time.  This is the
    // property that makes the BKDS scheme audit-friendly.
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-4");
    defer hat.deinit();

    const payload = "{\"cellId\":\"xyz\",\"timestamp\":1700000000}";
    const signed = try hat.signCell(payload, "");

    // Discard the SignedCell-side pubkey + signature; reconstruct
    // expectations purely from (root_priv, content_hash).
    const content_hash = hat_bkds.computeContentHash(payload);
    const expected_pubkey = try hat_bkds_verifier.rederiveExpectedPubkeyWithPriv(
        hat.root_priv,
        content_hash,
    );

    try std.testing.expectEqualSlices(u8, &signed.derived_pubkey, &expected_pubkey);
}

test "hat_bkds: tampered payload fails verification (derived_pubkey_mismatch)" {
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-5");
    defer hat.deinit();

    const orig_payload = "{\"cellId\":\"abc\",\"workOrderNumber\":\"WO-001\"}";
    const signed = try hat.signCell(orig_payload, "");

    // Modify the workOrderNumber, leaving the recorded (signed_by,
    // signature) pair unchanged.  The verifier re-derives under the
    // tampered content_hash → gets a different expected pubkey →
    // surfaces derived_pubkey_mismatch.
    const tampered_payload = "{\"cellId\":\"abc\",\"workOrderNumber\":\"WO-002\"}";
    try std.testing.expectError(
        hat_bkds_verifier.Error.derived_pubkey_mismatch,
        hat_bkds_verifier.verifyCell(
            hat.root_priv,
            tampered_payload,
            signed.derived_pubkey,
            signed.signature,
        ),
    );
}

test "hat_bkds: tampered signature fails verification (signature_mismatch)" {
    var hat = try hat_bkds.HatBkds.initFromSeed("conformance-root-6");
    defer hat.deinit();

    const payload = "{\"x\":1}";
    var signed = try hat.signCell(payload, "");

    // Flip a byte in the signature without touching the recorded
    // pubkey; step 1 (re-derivation match) passes, step 3 (ECDSA
    // verify) fails.  This catches "valid pubkey + corrupt signature"
    // — the post-derivation-match fault domain.
    signed.signature[7] ^= 0x01;

    try std.testing.expectError(
        hat_bkds_verifier.Error.signature_mismatch,
        hat_bkds_verifier.verifyCell(
            hat.root_priv,
            payload,
            signed.derived_pubkey,
            signed.signature,
        ),
    );
}

test "hat_bkds: wrong-root verification fails (cross-operator impersonation)" {
    var hat_a = try hat_bkds.HatBkds.initFromSeed("operator-a-root");
    defer hat_a.deinit();
    var hat_b = try hat_bkds.HatBkds.initFromSeed("operator-b-root");
    defer hat_b.deinit();

    const payload = "{\"shared\":\"data\"}";
    const signed_by_a = try hat_a.signCell(payload, "");

    // Operator B tries to verify operator A's signature under their
    // own root — the re-derivation produces a different expected
    // pubkey, so verification rejects with derived_pubkey_mismatch.
    try std.testing.expectError(
        hat_bkds_verifier.Error.derived_pubkey_mismatch,
        hat_bkds_verifier.verifyCell(
            hat_b.root_priv,
            payload,
            signed_by_a.derived_pubkey,
            signed_by_a.signature,
        ),
    );
}

test "hat_bkds: unlinkability — distinct payloads → distinct derived pubkeys" {
    // Privacy property: third parties verifying cells across a
    // corpus see a unique pubkey per cell, with no cross-cell
    // correlation possible without the root.  This test asserts
    // that distinct payloads produce structurally-distinct pubkeys.
    var hat = try hat_bkds.HatBkds.initFromSeed("unlinkability-root");
    defer hat.deinit();

    const a = try hat.signCell("{\"cellId\":\"aaa\"}", "");
    const b = try hat.signCell("{\"cellId\":\"bbb\"}", "");
    const c = try hat.signCell("{\"cellId\":\"ccc\"}", "");

    try std.testing.expect(!std.mem.eql(u8, &a.derived_pubkey, &b.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &b.derived_pubkey, &c.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &a.derived_pubkey, &c.derived_pubkey));

    // Each derived pubkey is also distinct from the root pubkey —
    // an outsider sees three unrelated pubkeys.
    const root = hat.rootPubkey();
    try std.testing.expect(!std.mem.eql(u8, &root, &a.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &root, &b.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &root, &c.derived_pubkey));
}

test "hat_bkds: cellId-as-payload signing path (the ratify handler's call site)" {
    // The ratify handler signs cells by passing &cellId as the
    // canonical payload (since cellId IS the SHA-256 of the cell's
    // load-bearing fields).  This test asserts that path round-trips
    // correctly: sign(&cellId) → verify(&cellId, signed_by, sig).
    var hat = try hat_bkds.HatBkds.initFromSeed("ratify-handler-root");
    defer hat.deinit();

    var cell_id: [32]u8 = undefined;
    @memset(&cell_id, 0x42);

    const signed = try hat.signCell(&cell_id, &cell_id);

    // Verify under the cellId-as-payload protocol.
    try hat_bkds_verifier.verifyCell(
        hat.root_priv,
        &cell_id,
        signed.derived_pubkey,
        signed.signature,
    );

    // External verification also works.
    try hat_bkds_verifier.verifyCellExternal(
        &cell_id,
        signed.derived_pubkey,
        signed.signature,
    );
}

test "hat_bkds: deinit zeroes the in-memory root scalar" {
    // Best-effort hygiene: after deinit, the in-memory root_priv
    // bytes should be zero.  This is a defence-in-depth guard
    // against post-deinit memory dumps; the compiler is free to
    // keep stack copies elsewhere, but the explicit zeroise covers
    // the common case.
    var hat = try hat_bkds.HatBkds.initFromSeed("deinit-zero-root");
    const orig = hat.root_priv;
    // Ensure the seed actually produced non-zero bytes (sanity).
    var any_nonzero: bool = false;
    for (orig) |b| {
        if (b != 0) {
            any_nonzero = true;
            break;
        }
    }
    try std.testing.expect(any_nonzero);

    hat.deinit();
    for (hat.root_priv) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

```
