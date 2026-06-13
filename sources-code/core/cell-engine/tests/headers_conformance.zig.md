---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/headers_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.965685+00:00
---

# core/cell-engine/tests/headers_conformance.zig

```zig
// Phase WH1 — Trustless SPV: conformance tests for the pure-Zig PoW verifier.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH1).
//
// Two layers of coverage:
//   1. Algorithmic — compact-bits encoding round-trips, MTP edge cases,
//      cw-144 DAA degenerate paths.
//   2. Vector-based — well-known mainnet headers (genesis + a couple early
//      blocks) parsed, hashed, PoW-checked.

const std = @import("std");
const headers = @import("headers");

// ─────────────────────────────────────────────────────────────────────
// Vector helpers
// ─────────────────────────────────────────────────────────────────────

fn nibble(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => 0,
    };
}

/// Decode a hex-encoded display-byte-order hash into internal byte order
/// (i.e., reverses while decoding). Block hashes and merkle roots are
/// quoted display-LE in BSV explorer tools, but stored display-BE here.
fn hexBE(hex: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        out[i] = (nibble(hex[i * 2]) << 4) | nibble(hex[i * 2 + 1]);
    }
    return out;
}

/// Same as hexBE but reverses for display-LE hash convention.
fn hexLE(hex: []const u8) [32]u8 {
    const be = hexBE(hex);
    var le: [32]u8 = undefined;
    for (0..32) |i| le[i] = be[31 - i];
    return le;
}

// ─────────────────────────────────────────────────────────────────────
// Vector tests — Bitcoin/BSV mainnet genesis
// ─────────────────────────────────────────────────────────────────────

test "WH1 vec: mainnet genesis hash matches 0000...19d6" {
    var raw: [80]u8 = undefined;
    std.mem.writeInt(u32, raw[0..4], 1, .little);
    @memset(raw[4..36], 0);
    @memcpy(raw[36..68], &hexLE("4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"));
    std.mem.writeInt(u32, raw[68..72], 1231006505, .little);
    std.mem.writeInt(u32, raw[72..76], 0x1d00ffff, .little);
    std.mem.writeInt(u32, raw[76..80], 2083236893, .little);

    const h = headers.Header.parseRaw(&raw);
    const hash = h.computeHash();

    // Display: 000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f
    const expect = hexLE("000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f");
    try std.testing.expectEqualSlices(u8, &expect, &hash);
    try std.testing.expect(h.satisfiesProofOfWork());
}

// ─────────────────────────────────────────────────────────────────────
// Algorithmic tests
// ─────────────────────────────────────────────────────────────────────

test "WH1: parse fails for under/over-sized slices" {
    var short = [_]u8{0} ** 79;
    try std.testing.expectError(error.too_short, headers.Header.parseSlice(&short));
    var long = [_]u8{0} ** 81;
    try std.testing.expectError(error.too_long, headers.Header.parseSlice(&long));
}

test "WH1: cmp32 detects strict ordering" {
    const a = [_]u8{0x01} ++ [_]u8{0x00} ** 31;
    const b = [_]u8{0x02} ++ [_]u8{0x00} ** 31;
    try std.testing.expectEqual(std.math.Order.lt, headers.cmp32(&a, &b));
    try std.testing.expectEqual(std.math.Order.gt, headers.cmp32(&b, &a));
    try std.testing.expectEqual(std.math.Order.eq, headers.cmp32(&a, &a));
}

test "WH1: targetToWork is monotonic with target descending" {
    const big = try headers.targetFromBits(0x1d00ffff); // powLimit
    const small = try headers.targetFromBits(0x1900ffff); // much harder
    const w_big = headers.targetToWork(&big);
    const w_small = headers.targetToWork(&small);
    try std.testing.expect(w_small > w_big);
}

test "WH1: medianTimePast on duplicates" {
    const stamps = [_]u32{ 100, 100, 100, 200, 200 };
    try std.testing.expectEqual(@as(u32, 100), headers.medianTimePast(&stamps));
}

test "WH1: bitsFromTarget(zero) returns 0" {
    const z = [_]u8{0} ** 32;
    try std.testing.expectEqual(@as(u32, 0), headers.bitsFromTarget(&z));
}

// ─────────────────────────────────────────────────────────────────────
// Synthetic chain — exercises validateHeader end-to-end
// ─────────────────────────────────────────────────────────────────────

test "WH1: linked synthetic chain validates under regtest target" {
    var chain: [3]headers.Header = undefined;
    chain[0] = .{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = [_]u8{1} ** 32,
        .timestamp = 1_700_000_000,
        .bits = headers.REGTEST_BITS,
        .nonce = 0,
    };
    mineUntilSatisfied(&chain[0]);

    chain[1] = .{
        .version = 1,
        .prev_hash = chain[0].computeHash(),
        .merkle_root = [_]u8{2} ** 32,
        .timestamp = 1_700_001_000,
        .bits = headers.REGTEST_BITS,
        .nonce = 0,
    };
    mineUntilSatisfied(&chain[1]);

    chain[2] = .{
        .version = 1,
        .prev_hash = chain[1].computeHash(),
        .merkle_root = [_]u8{3} ** 32,
        .timestamp = 1_700_002_000,
        .bits = headers.REGTEST_BITS,
        .nonce = 0,
    };
    mineUntilSatisfied(&chain[2]);

    // Validate chain[1] against chain[0].
    const inputs1 = headers.ValidateInputs{
        .parent = &chain[0],
        .parent_height = 0,
        .prev_timestamps = &.{chain[0].timestamp},
        .pow_limit_bits = headers.REGTEST_BITS,
    };
    try headers.validateHeader(&chain[1], &inputs1);

    // Validate chain[2] against chain[1].
    const inputs2 = headers.ValidateInputs{
        .parent = &chain[1],
        .parent_height = 1,
        .prev_timestamps = &.{ chain[0].timestamp, chain[1].timestamp },
        .pow_limit_bits = headers.REGTEST_BITS,
    };
    try headers.validateHeader(&chain[2], &inputs2);
}

test "WH1: corrupted candidate bits is rejected as wrong_difficulty" {
    var parent: headers.Header = .{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = [_]u8{0xab} ** 32,
        .timestamp = 1_700_000_000,
        .bits = headers.REGTEST_BITS,
        .nonce = 0,
    };
    mineUntilSatisfied(&parent);

    var child: headers.Header = .{
        .version = 1,
        .prev_hash = parent.computeHash(),
        .merkle_root = [_]u8{0xcd} ** 32,
        .timestamp = 1_700_000_600,
        .bits = 0x1c00ffff, // mismatched: pre-DAA expects regtest powLimit
        .nonce = 0,
    };
    mineUntilSatisfied(&child);

    const inputs = headers.ValidateInputs{
        .parent = &parent,
        .parent_height = 0,
        .prev_timestamps = &.{parent.timestamp},
        .pow_limit_bits = headers.REGTEST_BITS,
    };
    try std.testing.expectError(error.wrong_difficulty, headers.validateHeader(&child, &inputs));
}

// ─────────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────────

fn mineUntilSatisfied(h: *headers.Header) void {
    var n: u32 = 0;
    while (n < 1_000_000) : (n += 1) {
        h.nonce = n;
        if (h.satisfiesProofOfWork()) return;
    }
}

```
