---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/sign_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.963971+00:00
---

# core/cell-engine/tests/sign_conformance.zig

```zig
// Phase W1: OP_SIGN (0xCD) conformance + differential against bsvz primitives.ecdsa.
// Reference: docs/design/SEMANTOS-WALLET-TIERED-CUSTODY.md §5.1, §9.3
//
// These tests run only in the FULL profile (BSVZ linked) — embedded native has no
// secp256k1 implementation. Run via: `zig build test-sign`.

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");
const host = @import("host");
const bsvz = @import("bsvz");

// ── Test cell builder ──

fn makeKeyCell(lin: u32, sk_bytes: [32]u8) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little); // version
    std.mem.writeInt(u32, cell[24..28], 0x10000003, .little); // domain flag (TIER1 base)
    // priv_key in payload byte 0..32 (cell offset 256..288)
    @memcpy(cell[constants.HEADER_SIZE .. constants.HEADER_SIZE + 32], &sk_bytes);
    return cell;
}

fn makePDA() pda_mod.PDA {
    return pda_mod.PDA.init(500000);
}

// Deterministic test private key (low scalar — known good).
const TEST_SK: [32]u8 = blk: {
    var k: [32]u8 = [_]u8{0} ** 32;
    k[31] = 0x42;
    break :blk k;
};

const TEST_DIGEST: [32]u8 = blk: {
    var d: [32]u8 = undefined;
    for (&d, 0..) |*b, i| b.* = @intCast(i);
    break :blk d;
};

// ── K11a: OP_SIGN consumes LINEAR key cell ──

test "OP_SIGN: LINEAR key cell consumed on success" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_LINEAR, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&TEST_DIGEST);
    try p.spush(&[_]u8{0x41}); // SIGHASH_ALL | FORKID

    try plexus.executePlexus(&p, 0xCD);

    // Stack should now hold ONLY the signature
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expect(top.len >= 9 and top.len <= 73); // DER min ~8 + 1 sighash byte
    // Last byte is the sighash type
    try std.testing.expectEqual(@as(u8, 0x41), top.data[top.len - 1]);
}

// ── AFFINE key cell — Tier-0 budget fast path ──

test "OP_SIGN: AFFINE key cell stays on stack on success" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_AFFINE, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&TEST_DIGEST);
    try p.spush(&[_]u8{0x41});

    try plexus.executePlexus(&p, 0xCD);

    // Stack: [AFFINE key cell, sig]
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    const top = try p.speek();
    try std.testing.expect(top.len >= 9 and top.len <= 73);
    const second = try p.speekAt(1);
    try std.testing.expectEqual(pda_mod.CELL_SIZE, @as(usize, second.len));
    const lin = try linearity.getLinearity(second.data);
    try std.testing.expectEqual(linearity.LinearityType.affine, lin);
}

// ── K11c: failure-atomic — stack unchanged on error ──

test "OP_SIGN: RELEVANT key cell rejected (stack unchanged)" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_RELEVANT, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&TEST_DIGEST);
    try p.spush(&[_]u8{0x41});

    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xCD));
    // Stack unchanged: 3 items
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

test "OP_SIGN: bad msg digest length rejected (stack unchanged)" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_LINEAR, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{ 0x01, 0x02 }); // 2 bytes, not 32
    try p.spush(&[_]u8{0x41});

    try std.testing.expectError(error.cell_too_short, plexus.executePlexus(&p, 0xCD));
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

test "OP_SIGN: stack underflow when fewer than 3 items" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_LINEAR, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&TEST_DIGEST);
    // Only 2 items pushed — sighash_type missing.
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xCD));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── K11b: differential — OP_SIGN output verifies under bsvz ──

test "OP_SIGN: differential — output verifies under bsvz primitives.ecdsa" {
    var p = makePDA();
    const cell = makeKeyCell(constants.LINEARITY_LINEAR, TEST_SK);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&TEST_DIGEST);
    try p.spush(&[_]u8{0x41});

    try plexus.executePlexus(&p, 0xCD);

    const sig_item = try p.speek();
    // Strip sighash byte before verification (BSV convention).
    const der_bytes = sig_item.data[0 .. sig_item.len - 1];

    // Recover the corresponding public key from TEST_SK via bsvz.
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(TEST_SK);
    const pub_point = try priv.publicKey();
    const pub_sec1 = pub_point.toCompressedSec1();

    const verified = bsvz.crypto.verifyDigest256RelaxedSec1(&pub_sec1, TEST_DIGEST, der_bytes) catch false;
    try std.testing.expect(verified);
}

// ── Differential against bsvz signDigest256 directly ──

test "OP_SIGN: differential — bsvz signDigest256 standalone produces verifiable sig" {
    // Sanity-check that bsvz produces a sig that bsvz can verify, independent of
    // the cell engine. This anchors the differential — if this fails, the kernel
    // test above is meaningless.
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(TEST_SK);
    const der = try priv.signDigest(TEST_DIGEST);
    const pub_point = try priv.publicKey();
    const pub_sec1 = pub_point.toCompressedSec1();
    const verified = bsvz.crypto.verifyDigest256RelaxedSec1(&pub_sec1, TEST_DIGEST, der.bytes[0..der.len]) catch false;
    try std.testing.expect(verified);
}

// ── Atomicity — error path leaves stack untouched (parallels K2a) ──

test "OP_SIGN: empty key cell rejected as cell_too_short (stack unchanged)" {
    var p = makePDA();
    // Push a too-small cell (len < HEADER_SIZE + 32).
    var short_cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, short_cell[16..20], constants.LINEARITY_LINEAR, .little);
    try p.spushCell(&short_cell, 100); // length too short
    try p.spush(&TEST_DIGEST);
    try p.spush(&[_]u8{0x41});

    try std.testing.expectError(error.cell_too_short, plexus.executePlexus(&p, 0xCD));
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

```
