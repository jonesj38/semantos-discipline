---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/bca_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.964858+00:00
---

# core/cell-engine/tests/bca_conformance.zig

```zig
// BCA conformance tests — Phase 2
//
// Tests deriveBCA and verifyBCA against independently-generated test vectors
// (produced by generate-bca-vectors.ts using @bsv/sdk Hash.sha256).

const std = @import("std");
const bca = @import("bca");
const constants = @import("constants");

// ── Hex helper ──

fn hexToBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    @setEvalBranchQuota(10000);
    var result: [hex.len / 2]u8 = undefined;
    for (0..hex.len / 2) |i| {
        result[i] = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch unreachable;
    }
    return result;
}

// ── Test vectors from bca_basic.json ──

// Test key 1: privkey 0x01 → pubkey 0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
const PUBKEY_1 = hexToBytes("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798");
const PUBKEY_2 = hexToBytes("02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5");
const PUBKEY_3 = hexToBytes("02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9");
const PUBKEY_4 = hexToBytes("0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798");

const DEFAULT_PREFIX = hexToBytes("20010db800000001");
const DEFAULT_MODIFIER = hexToBytes("00112233445566778899aabbccddeeff");
const ALT_MODIFIER = hexToBytes("ffeeddccbbaa99887766554433221100");
const ALT_PREFIX = hexToBytes("fe80000000000000");

// Expected addresses from bca_basic.json
const EXPECTED_ADDR_1 = hexToBytes("20010db800000001186b2b5b8336ab60");
const EXPECTED_ADDR_2 = hexToBytes("20010db80000000108b1ebb18b109705");
const EXPECTED_ADDR_3 = hexToBytes("20010db80000000108e1cb63bcdf5e3e");
const EXPECTED_ADDR_4 = hexToBytes("20010db800000001009896dff15c722d");
const EXPECTED_ADDR_ALT = hexToBytes("fe80000000000000006e12cd9ed315a7");

// Expected addresses from bca_all_sec_params.json
const EXPECTED_ADDR_SEC0 = hexToBytes("20010db800000001186b2b5b8336ab60");
const EXPECTED_ADDR_SEC1 = hexToBytes("20010db800000001386b2b5b8336ab60");
const EXPECTED_ADDR_SEC2 = hexToBytes("20010db800000001586b2b5b8336ab60");

// ── Derivation tests ──

test "deriveBCA produces correct IPv6 for known pubkey (sec=0)" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_1, &result.address);
    try std.testing.expectEqual(@as(u8, 0), result.collision_count);
}

test "deriveBCA produces correct IPv6 for test key 2" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_2,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_2, &result.address);
}

test "deriveBCA produces correct IPv6 for test key 3" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_3,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_3, &result.address);
}

test "deriveBCA produces correct IPv6 for test key 4" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_4,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_4, &result.address);
}

test "deriveBCA with alt modifier and link-local prefix" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = ALT_PREFIX,
        .modifier = ALT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_ALT, &result.address);
}

// ── sec parameter tests ──

test "deriveBCA sec=0 produces correct address" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_SEC0, &result.address);
}

test "deriveBCA sec=1 produces correct address" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 1,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_SEC1, &result.address);
}

test "deriveBCA sec=2 produces correct address" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 2,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &EXPECTED_ADDR_SEC2, &result.address);
}

test "deriveBCA sec=3 returns invalid_sec_parameter error" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 3,
    };
    try std.testing.expectError(error.invalid_sec_parameter, bca.deriveBCA(&input));
}

// ── u-bit and g-bit tests ──

test "u-bit and g-bit are cleared in interface identifier" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    // Byte 8 of the address is byte 0 of the interface identifier
    const iid_byte0 = result.address[8];
    // u-bit = bit 1 from LSB (0x02), g-bit = bit 0 from LSB (0x01)
    try std.testing.expectEqual(@as(u8, 0), iid_byte0 & 0x03);
}

test "sec parameter is encoded in 3 MSBs of interface identifier byte 0" {
    // sec=0: MSBs should be 000
    {
        const input = bca.BCAInput{ .pubkey = PUBKEY_1, .subnet_prefix = DEFAULT_PREFIX, .modifier = DEFAULT_MODIFIER, .sec = 0 };
        const result = try bca.deriveBCA(&input);
        try std.testing.expectEqual(@as(u8, 0), (result.address[8] >> 5) & 0x07);
    }
    // sec=1: MSBs should be 001
    {
        const input = bca.BCAInput{ .pubkey = PUBKEY_1, .subnet_prefix = DEFAULT_PREFIX, .modifier = DEFAULT_MODIFIER, .sec = 1 };
        const result = try bca.deriveBCA(&input);
        try std.testing.expectEqual(@as(u8, 1), (result.address[8] >> 5) & 0x07);
    }
    // sec=2: MSBs should be 010
    {
        const input = bca.BCAInput{ .pubkey = PUBKEY_1, .subnet_prefix = DEFAULT_PREFIX, .modifier = DEFAULT_MODIFIER, .sec = 2 };
        const result = try bca.deriveBCA(&input);
        try std.testing.expectEqual(@as(u8, 2), (result.address[8] >> 5) & 0x07);
    }
}

// ── Determinism test ──

test "deriveBCA is deterministic — same input always same output" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result1 = try bca.deriveBCA(&input);
    const result2 = try bca.deriveBCA(&input);
    try std.testing.expectEqualSlices(u8, &result1.address, &result2.address);
    try std.testing.expectEqual(result1.collision_count, result2.collision_count);
}

// ── Verification tests ──

test "verifyBCA returns true for correctly derived address" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    const result = try bca.deriveBCA(&input);
    try std.testing.expect(bca.verifyBCA(&result.address, &input));
}

test "verifyBCA returns false for wrong public key" {
    const addr = EXPECTED_ADDR_1;
    const input = bca.BCAInput{
        .pubkey = PUBKEY_2,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    try std.testing.expect(!bca.verifyBCA(&addr, &input));
}

test "verifyBCA returns false for wrong modifier" {
    const addr = EXPECTED_ADDR_1;
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = ALT_MODIFIER,
        .sec = 0,
    };
    try std.testing.expect(!bca.verifyBCA(&addr, &input));
}

test "verifyBCA returns false for wrong subnet prefix" {
    const addr = EXPECTED_ADDR_1;
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = ALT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    try std.testing.expect(!bca.verifyBCA(&addr, &input));
}

test "verifyBCA returns false for corrupted address" {
    const addr = hexToBytes("20010db800000001186b2b5b8336ab9f"); // last byte flipped
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };
    try std.testing.expect(!bca.verifyBCA(&addr, &input));
}

test "verifyBCA handles sec parameter correctly" {
    // Derive with sec=2
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 2,
    };
    const result = try bca.deriveBCA(&input);

    // Verify should succeed (sec is read from the address)
    try std.testing.expect(bca.verifyBCA(&result.address, &input));
}

// ── Performance test ──

test "BCA derivation completes in under 1ms (1000 iterations)" {
    const input = bca.BCAInput{
        .pubkey = PUBKEY_1,
        .subnet_prefix = DEFAULT_PREFIX,
        .modifier = DEFAULT_MODIFIER,
        .sec = 0,
    };

    var timer = std.time.Timer.start() catch return; // skip if timer unavailable
    const iterations: u32 = 1000;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        _ = bca.deriveBCA(&input) catch unreachable;
    }
    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;
    // Under 1ms = under 1_000_000 ns
    try std.testing.expect(avg_ns < 1_000_000);
}

```
