---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/budget_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.961983+00:00
---

# core/cell-engine/tests/budget_conformance.zig

```zig
// Phase W3: OP_DECREMENT_BUDGET (0xCE) + OP_REFILL_BUDGET (0xCF) conformance.
// Reference: docs/design/SEMANTOS-WALLET-TIERED-CUSTODY.md §5.1, §6.1, §9.1.
//
// Tests run only in the FULL profile (BSVZ linked) — refill verifies an
// ECDSA signature, which the embedded native build cannot do.

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");
const host = @import("host");
const bsvz = @import("bsvz");

const HOT_FLAG: u32 = 0x10000001;

fn makeBudgetCell(remaining: u64) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], constants.LINEARITY_AFFINE, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little); // version
    std.mem.writeInt(u32, cell[24..28], HOT_FLAG, .little);
    // payload bytes 0..32 = priv_key (zero-filled, fine for these tests)
    // payload byte 32..40 = remaining_satoshis
    const remain_offset = constants.HEADER_SIZE + plexus.BUDGET_OFFSET_REMAINING;
    std.mem.writeInt(u64, cell[remain_offset..][0..8], remaining, .little);
    return cell;
}

fn readRemaining(cell: *const pda_mod.Cell) u64 {
    const off = constants.HEADER_SIZE + plexus.BUDGET_OFFSET_REMAINING;
    return std.mem.readInt(u64, cell[off..][0..8], .little);
}

fn makePDA() pda_mod.PDA {
    return pda_mod.PDA.init(500000);
}

// Push a u64 amount as a script-number-encoded item.
fn pushAmount(p: *pda_mod.PDA, amount: u64) !void {
    var buf: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    const len = pda_mod.i64ToCell(@intCast(amount), &buf);
    try p.spush(buf[0..len]);
}

// ── OP_DECREMENT_BUDGET happy path ──

test "OP_DECREMENT_BUDGET: simple debit reduces remaining_satoshis" {
    var p = makePDA();
    const cell = makeBudgetCell(1_000_000);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 12_345);

    try plexus.executePlexus(&p, 0xCE);

    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(pda_mod.CELL_SIZE, @as(usize, top.len));
    try std.testing.expectEqual(@as(u64, 1_000_000 - 12_345), readRemaining(top.data));
}

test "OP_DECREMENT_BUDGET: exact-balance debit succeeds" {
    var p = makePDA();
    const cell = makeBudgetCell(500);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 500);

    try plexus.executePlexus(&p, 0xCE);
    const top = try p.speek();
    try std.testing.expectEqual(@as(u64, 0), readRemaining(top.data));
}

// ── OP_DECREMENT_BUDGET failure-atomic ──

test "OP_DECREMENT_BUDGET: insufficient budget rejected (stack unchanged)" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 200);

    try std.testing.expectError(error.insufficient_budget, plexus.executePlexus(&p, 0xCE));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_DECREMENT_BUDGET: LINEAR cell rejected (stack unchanged)" {
    var p = makePDA();
    var cell = makeBudgetCell(1_000);
    // Tweak linearity to LINEAR — must be rejected.
    std.mem.writeInt(u32, cell[16..20], constants.LINEARITY_LINEAR, .little);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 100);

    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xCE));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_DECREMENT_BUDGET: stack underflow when fewer than 2 items" {
    var p = makePDA();
    const cell = makeBudgetCell(1_000);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xCE));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

// ── OP_REFILL_BUDGET happy path ──

const PARENT_SK: [32]u8 = blk: {
    var k: [32]u8 = [_]u8{0} ** 32;
    k[31] = 0x99;
    break :blk k;
};

fn parentPubkeyCompressed() ![33]u8 {
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(PARENT_SK);
    const pk = try priv.publicKey();
    return pk.toCompressedSec1();
}

fn signRefill(cell: *const pda_mod.Cell, amount: u64) ![73]u8 {
    var msg: [constants.HEADER_SIZE + 8]u8 = undefined;
    @memcpy(msg[0..constants.HEADER_SIZE], cell[0..constants.HEADER_SIZE]);
    std.mem.writeInt(u64, msg[constants.HEADER_SIZE..][0..8], amount, .little);

    var digest: [32]u8 = undefined;
    host.hash256(&msg, &digest);

    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(PARENT_SK);
    const der = try priv.signDigest(digest);

    var out: [73]u8 = undefined;
    @memcpy(out[0..der.len], der.bytes[0..der.len]);
    out[der.len] = 0x41; // SIGHASH_ALL | FORKID
    return out;
}

test "OP_REFILL_BUDGET: valid sig credits remaining_satoshis" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    const refill_amount: u64 = 50_000;

    const pk = try parentPubkeyCompressed();
    const sig_buf = try signRefill(&cell, refill_amount);
    // Signature length is variable — find it by reading the DER ASN.1 length.
    // For our testing the DER is bytes 0..N-1, with N-1 bytes of DER + 1 sighash byte.
    // We can't recompute N here easily, so reproduce signRefill's der.len:
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(PARENT_SK);
    var msg: [constants.HEADER_SIZE + 8]u8 = undefined;
    @memcpy(msg[0..constants.HEADER_SIZE], cell[0..constants.HEADER_SIZE]);
    std.mem.writeInt(u64, msg[constants.HEADER_SIZE..][0..8], refill_amount, .little);
    var digest: [32]u8 = undefined;
    host.hash256(&msg, &digest);
    const der_sig = try priv.signDigest(digest);
    const sig_len: u32 = @intCast(der_sig.len + 1); // DER + sighash byte

    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, refill_amount);
    try p.spush(&pk);
    try p.spush(sig_buf[0..sig_len]);

    try plexus.executePlexus(&p, 0xCF);

    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(@as(u64, 100 + 50_000), readRemaining(top.data));
}

// ── OP_REFILL_BUDGET failure-atomic ──

test "OP_REFILL_BUDGET: bad sig rejected (stack unchanged)" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    const pk = try parentPubkeyCompressed();
    const bogus_sig = [_]u8{ 0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01, 0x41 };

    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 10_000);
    try p.spush(&pk);
    try p.spush(&bogus_sig);

    try std.testing.expectError(error.invalid_refill_signature, plexus.executePlexus(&p, 0xCF));
    try std.testing.expectEqual(@as(u32, 4), p.sdepth());
}

test "OP_REFILL_BUDGET: wrong pubkey rejected" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    const refill_amount: u64 = 7;

    // Sign with PARENT_SK, but verify against a DIFFERENT pubkey.
    const sig_buf = try signRefill(&cell, refill_amount);

    var wrong_sk: [32]u8 = [_]u8{0} ** 32;
    wrong_sk[31] = 0x33;
    const wrong_priv = try bsvz.primitives.ec.PrivateKey.fromBytes(wrong_sk);
    const wrong_pk = (try wrong_priv.publicKey()).toCompressedSec1();

    // Compute correct sig_len.
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(PARENT_SK);
    var msg: [constants.HEADER_SIZE + 8]u8 = undefined;
    @memcpy(msg[0..constants.HEADER_SIZE], cell[0..constants.HEADER_SIZE]);
    std.mem.writeInt(u64, msg[constants.HEADER_SIZE..][0..8], refill_amount, .little);
    var digest: [32]u8 = undefined;
    host.hash256(&msg, &digest);
    const der_sig = try priv.signDigest(digest);
    const sig_len: u32 = @intCast(der_sig.len + 1);

    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, refill_amount);
    try p.spush(&wrong_pk);
    try p.spush(sig_buf[0..sig_len]);

    try std.testing.expectError(error.invalid_refill_signature, plexus.executePlexus(&p, 0xCF));
    try std.testing.expectEqual(@as(u32, 4), p.sdepth());
}

test "OP_REFILL_BUDGET: stack underflow when fewer than 4 items" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 100);
    try p.spush(&[_]u8{0xAA}); // only 3 items
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xCF));
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

// ── K13 monotonicity differential ──

test "K13: OP_DECREMENT_BUDGET strictly decreases remaining" {
    var p = makePDA();
    const cell = makeBudgetCell(1_000);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, 1);

    try plexus.executePlexus(&p, 0xCE);
    const top = try p.speek();
    try std.testing.expect(readRemaining(top.data) < 1_000);
}

test "K13: OP_REFILL_BUDGET strictly increases remaining (with valid sig)" {
    var p = makePDA();
    const cell = makeBudgetCell(100);
    const refill_amount: u64 = 1;

    const pk = try parentPubkeyCompressed();
    const sig_buf = try signRefill(&cell, refill_amount);
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(PARENT_SK);
    var msg: [constants.HEADER_SIZE + 8]u8 = undefined;
    @memcpy(msg[0..constants.HEADER_SIZE], cell[0..constants.HEADER_SIZE]);
    std.mem.writeInt(u64, msg[constants.HEADER_SIZE..][0..8], refill_amount, .little);
    var digest: [32]u8 = undefined;
    host.hash256(&msg, &digest);
    const der_sig = try priv.signDigest(digest);
    const sig_len: u32 = @intCast(der_sig.len + 1);

    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try pushAmount(&p, refill_amount);
    try p.spush(&pk);
    try p.spush(sig_buf[0..sig_len]);

    try plexus.executePlexus(&p, 0xCF);
    const top = try p.speek();
    try std.testing.expect(readRemaining(top.data) > 100);
}

```
