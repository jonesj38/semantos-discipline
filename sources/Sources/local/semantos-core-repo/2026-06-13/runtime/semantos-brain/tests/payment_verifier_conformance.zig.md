---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/payment_verifier_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.194083+00:00
---

# runtime/semantos-brain/tests/payment_verifier_conformance.zig

```zig
// Phase WSITE4.5 — payment_verifier conformance tests.
//
// Two-mode coverage strategy:
//
//   • Stub mode (-Denable-wasmtime=false): exercises payment_verifier_stub.zig.
//     Verify always returns `error.bsvz_unavailable`.  We assert that
//     surface so the disabled-build path doesn't bit-rot.
//
//   • Real mode (-Denable-wasmtime=true): exercises payment_verifier.zig.
//     A full BEEF + chain_tracker + script roundtrip lives in the
//     site_server integration tests (where the helpers are already wired);
//     here we focus on the public-surface pre-checks that don't depend
//     on bsvz internals: hex-length validation + the always-true error
//     contract.
//
// We avoid hand-building a synthetic BEEF here: bsvz already has
// extensive BEEF parser tests, and constructing one in Zig that passes
// PoW + merkle path validation is fragile.  Once `bsvz.transaction.beef`
// exposes a builder we can write a fixture-based round-trip; for v0.1
// we trust bsvz's tests for that path and assert our wrapper's own
// invariants.

const std = @import("std");
const verifier = @import("payment_verifier");
const build_options = @import("build_options");

// A 33-byte compressed SEC1 pubkey — content doesn't matter for the
// surface-level tests below (none of them reach the script-matcher).
const RECIPIENT_SEC1: [33]u8 = blk: {
    var out: [33]u8 = undefined;
    out[0] = 0x02;
    for (1..33) |i| out[i] = @intCast(i);
    break :blk out;
};

const NULL_TRACKER = struct {
    pub fn isValidRootForHeight(_: @This(), _: anytype, _: u32) !bool {
        return false;
    }
}{};

test "WSITE4.5 verifier: VerifyResult default is all-false" {
    const r = verifier.VerifyResult{};
    try std.testing.expect(!r.spv_ok);
    try std.testing.expect(!r.output_ok);
    try std.testing.expect(!r.verified);
    try std.testing.expectEqual(@as(u64, 0), r.matched_satoshis);
}

test "WSITE4.5 verifier: stub mode returns bsvz_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;

    const dummy_beef: [4]u8 = .{ 0x01, 0x02, 0x03, 0x04 };
    const txid_hex = "abababababababababababababababababababababababababababababababab";
    try std.testing.expectError(
        error.bsvz_unavailable,
        verifier.verify(
            std.testing.allocator,
            &dummy_beef,
            txid_hex,
            RECIPIENT_SEC1,
            5_000,
            NULL_TRACKER,
            null,
        ),
    );
}

test "WSITE4.5 verifier: real mode rejects bad-length txid hex" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    const dummy_beef: [4]u8 = .{ 0x01, 0x02, 0x03, 0x04 };
    try std.testing.expectError(
        error.parse_failed,
        verifier.verify(
            std.testing.allocator,
            &dummy_beef,
            "tooshort",
            RECIPIENT_SEC1,
            5_000,
            NULL_TRACKER,
            null,
        ),
    );
}

test "WSITE4.5 verifier: real mode rejects malformed BEEF bytes" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    // Random bytes that don't parse as a BEEF v1/v2/atomic envelope.
    const garbage = [_]u8{0xff} ** 64;
    const txid_hex = "abababababababababababababababababababababababababababababababab";
    try std.testing.expectError(
        error.parse_failed,
        verifier.verify(
            std.testing.allocator,
            &garbage,
            txid_hex,
            RECIPIENT_SEC1,
            5_000,
            NULL_TRACKER,
            null,
        ),
    );
}

```
