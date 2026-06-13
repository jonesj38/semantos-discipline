---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/tests/brc100_vectors.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.300055+00:00
---

# runtime/node/tests/brc100_vectors.zig

```zig
// W7 cross-runtime BRC-100 digest interop test.
//
// Asserts that the W6 sovereign-node runtime computes the same canonical
// digest as the W5 browser bundle for the test vectors pinned in
// `docs/design/BRC100-CANONICAL-DIGEST.md` §8.
//
// The matching JS-side test lives in
// `cartridges/wallet-headers/brain/test/brc100-vectors.spec.ts`; together they form the
// cross-runtime interop guarantee promised in the BRC-100 reconciliation
// commit. If both pass on the same hex, the runtimes agree.

const std = @import("std");
const brc100 = @import("brc100");

fn hexDecode(comptime N: usize, hex: []const u8) [N]u8 {
    var out: [N]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
    return out;
}

// Vector 1 — empty body, sk=0x01 (the secp256k1 generator point).
const V1_IDENTITY_KEY: [33]u8 = hexDecode(33, "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798");
const V1_NONCE: [32]u8 = [_]u8{0} ** 32;
const V1_TIMESTAMP: u64 = 0;
const V1_BODY: []const u8 = "";
const V1_EXPECTED_DIGEST: [32]u8 = hexDecode(32, "9967659398ba69b0913a7d5eb65b58a9a390d2ab1584cb77bb4dbdd505a9eaed");

// Vector 2 — RPC body, all-ff nonce, ts = 0x66666666.
const V2_IDENTITY_KEY: [33]u8 = V1_IDENTITY_KEY;
const V2_NONCE: [32]u8 = [_]u8{0xff} ** 32;
const V2_TIMESTAMP: u64 = 0x66666666;
const V2_BODY: []const u8 = "{\"method\":\"getPublicKey\",\"params\":{},\"id\":\"req-1\"}";
const V2_EXPECTED_DIGEST: [32]u8 = hexDecode(32, "d8bb125589659f49df927ca2da6510ac8fb4d6bffa957ed5519253db59b653d5");

test "BRC-100 vector 1: empty body, all-zero nonce, ts=0" {
    var digest: [32]u8 = undefined;
    brc100.computeDigest(&V1_IDENTITY_KEY, &V1_NONCE, V1_TIMESTAMP, V1_BODY, &digest);
    try std.testing.expectEqualSlices(u8, &V1_EXPECTED_DIGEST, &digest);
}

test "BRC-100 vector 2: RPC body, all-ff nonce, ts=0x66666666" {
    var digest: [32]u8 = undefined;
    brc100.computeDigest(&V2_IDENTITY_KEY, &V2_NONCE, V2_TIMESTAMP, V2_BODY, &digest);
    try std.testing.expectEqualSlices(u8, &V2_EXPECTED_DIGEST, &digest);
}

```
