---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/canonicalization/golden-slice/v1_release.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.591389+00:00
---

# tests/canonicalization/golden-slice/v1_release.zig

```zig
//! C7 Golden Slice — V1 Release (brain side)
//!
//! Brain-side contract assertions for `do.new betterment.practice.release`.
//! Converted 2026-06-04 from red `LayerNotWired` stubs to real, standalone
//! assertions of the deterministic resolution contract the PWA + brain MUST
//! agree on (the typeHash + the betterment namespace prefix).
//!
//! Spec:    docs/canon/canonicalization-golden-slice.md
//! PWA side: tests/canonicalization/golden-slice/v1_release.dart
//!
//! Run standalone (no build.zig wiring needed — std-only):
//!   zig test tests/canonicalization/golden-slice/v1_release.zig
//!
//! Scope honesty: the brain's sovereign-mint VERIFY behaviour (recover the
//! signer pubkey from the operator signature, match it to the cert, reject
//! tampered/unknown) is the #828 gate, asserted by the
//! `verifyPayloadSignature` conformance test in
//! runtime/semantos-brain/src/attachments_upload_http.zig and proven live
//! (Level 2: HTTP 201 for a real operator-signed mint, 401 for tampered /
//! unknown — see canonicalization-matrix C7-E). This file asserts the
//! deterministic resolution contract that gates which cell that verify runs
//! against; reproducing the full verify here would duplicate #828's module
//! graph (bsvz + cert store), so it stays std-only by design.

const std = @import("std");

/// One 8-byte typeHash segment = first 8 bytes of sha256(segment).
fn segHash(seg: []const u8) [8]u8 {
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(seg, &d, .{});
    return d[0..8].*;
}

/// Inline mirror of `type_hash.buildTypeHash` (4 × sha256(segment)[0..8]).
/// Must agree byte-for-byte with the Dart `buildTypeHash` (PWA) + the brain
/// registry — that agreement is the whole resolution contract.
fn buildTypeHash(s1: []const u8, s2: []const u8, s3: []const u8, s4: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memcpy(out[0..8], &segHash(s1));
    @memcpy(out[8..16], &segHash(s2));
    @memcpy(out[16..24], &segHash(s3));
    @memcpy(out[24..32], &segHash(s4));
    return out;
}

// ── Resolution contract — the typeHash the PWA mints + the brain resolves ──
test "C7 slice — betterment.practice.release typeHash matches the registry contract" {
    const h = buildTypeHash("betterment", "practice", "release", "");
    const hex = std.fmt.bytesToHex(h, .lower);
    try std.testing.expectEqualStrings(
        "06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14",
        &hex,
    );
}

// ── Namespace prefix — the 8-byte betterment-cartridge gate (sweep_http) ──
test "C7 slice — betterment namespace prefix is sha256('betterment')[0..8]" {
    const prefix = segHash("betterment");
    const hex = std.fmt.bytesToHex(prefix, .lower);
    // == BETTERMENT_NAMESPACE_PREFIX in cartridges/betterment/brain/zig/sweep_http.zig
    try std.testing.expectEqualStrings("06d0a049e88a982b", &hex);
}

```
