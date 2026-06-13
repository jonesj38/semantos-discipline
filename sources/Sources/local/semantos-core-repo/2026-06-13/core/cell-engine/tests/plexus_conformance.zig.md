---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/plexus_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.962319+00:00
---

# core/cell-engine/tests/plexus_conformance.zig

```zig
// Phase 4: Plexus opcode conformance tests
// Reference: PHASE-4-PLEXUS-OPCODES.md, CORE:OPCODES (opcodes.ts)

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");

// ── Test cell builder ──

fn makeTestCell(lin: u32, domain_flag: u32, type_hash: [32]u8, owner_id: [16]u8) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    @memcpy(cell[30..62], &type_hash);
    @memcpy(cell[62..78], &owner_id);
    return cell;
}

fn makeLinearCell() pda_mod.Cell {
    return makeTestCell(1, constants.DOMAIN_FLAG_EDGE_CREATION, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16);
}

fn makeAffineCell() pda_mod.Cell {
    return makeTestCell(2, constants.DOMAIN_FLAG_SIGNING, [_]u8{0xCC} ** 32, [_]u8{0xDD} ** 16);
}

fn makeRelevantCell() pda_mod.Cell {
    return makeTestCell(3, constants.DOMAIN_FLAG_METERING, [_]u8{0xEE} ** 32, [_]u8{0xFF} ** 16);
}

fn makePDA() pda_mod.PDA {
    return pda_mod.PDA.init(500000);
}

// ── OP_CHECKLINEARTYPE (0xC0) ──

test "OP_CHECKLINEARTYPE (0xC0): passes on LINEAR cell" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC0);
    // Cell still on stack + TRUE pushed
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
}

test "OP_CHECKLINEARTYPE (0xC0): fails on AFFINE cell" {
    var p = makePDA();
    var cell = makeAffineCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xC0));
}

// ── OP_CHECKAFFINETYPE (0xC1) ──

test "OP_CHECKAFFINETYPE (0xC1): passes on AFFINE cell" {
    var p = makePDA();
    var cell = makeAffineCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC1);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKAFFINETYPE (0xC1): fails on LINEAR cell" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xC1));
}

// ── OP_CHECKRELEVANTTYPE (0xC2) ──

test "OP_CHECKRELEVANTTYPE (0xC2): passes on RELEVANT cell" {
    var p = makePDA();
    var cell = makeRelevantCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC2);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── OP_CHECKCAPABILITY (0xC3) ──

test "OP_CHECKCAPABILITY (0xC3): passes on LINEAR cell with matching cap type" {
    var p = makePDA();
    var cell = makeLinearCell();
    cell[256] = 4; // METERED_ACCESS at payload byte 0
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{4}); // Expected cap type
    try plexus.executePlexus(&p, 0xC3);
    // Cell still on stack + TRUE pushed
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKCAPABILITY (0xC3): fails on non-LINEAR cell" {
    var p = makePDA();
    var cell = makeAffineCell();
    cell[256] = 4;
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{4});
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
}

test "OP_CHECKCAPABILITY (0xC3): fails on mismatched capability type" {
    var p = makePDA();
    var cell = makeLinearCell();
    cell[256] = 4; // METERED_ACCESS
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{2}); // Expected DATA_ACCESS — mismatch
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
}

// ── OP_CHECKIDENTITY (0xC4) ──

test "OP_CHECKIDENTITY (0xC4): passes on matching owner_id" {
    var p = makePDA();
    var cell = makeLinearCell(); // owner_id = 0xBB * 16
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xBB} ** 16)); // Expected owner_id
    try plexus.executePlexus(&p, 0xC4);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKIDENTITY (0xC4): fails on mismatched owner_id" {
    var p = makePDA();
    var cell = makeLinearCell(); // owner_id = 0xBB * 16
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0x11} ** 16)); // Wrong owner_id
    try std.testing.expectError(error.owner_id_mismatch, plexus.executePlexus(&p, 0xC4));
}

test "OP_CHECKIDENTITY (0xC4): fails on short expected data" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{ 0xBB, 0xBB }); // Only 2 bytes, need 16
    try std.testing.expectError(error.owner_id_mismatch, plexus.executePlexus(&p, 0xC4));
}

// ── OP_ASSERTLINEAR (0xC5) ──

test "OP_ASSERTLINEAR (0xC5): passes on LINEAR cell (no stack push)" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC5);
    // No TRUE pushed — assertion only. Cell remains.
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "OP_ASSERTLINEAR (0xC5): fails on AFFINE cell" {
    var p = makePDA();
    var cell = makeAffineCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xC5));
}

// ── OP_CHECKDOMAINFLAG (0xC6) ──

test "OP_CHECKDOMAINFLAG (0xC6): passes on matching flag" {
    var p = makePDA();
    var cell = makeLinearCell(); // flag = EDGE_CREATION (1)
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{1}); // Expected flag = 1 (sign-magnitude LE)
    try plexus.executePlexus(&p, 0xC6);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKDOMAINFLAG (0xC6): fails on mismatched flag" {
    var p = makePDA();
    var cell = makeLinearCell(); // flag = EDGE_CREATION (1)
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{5}); // Expected ATTESTATION (5) — mismatch
    try std.testing.expectError(error.domain_flag_mismatch, plexus.executePlexus(&p, 0xC6));
}

test "OP_CHECKDOMAINFLAG (0xC6): works with METERING flag" {
    var p = makePDA();
    var cell = makeRelevantCell(); // flag = METERING (10)
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{10}); // Expected METERING
    try plexus.executePlexus(&p, 0xC6);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── OP_CHECKTYPEHASH (0xC7) ──

test "OP_CHECKTYPEHASH (0xC7): passes on matching 32-byte hash" {
    var p = makePDA();
    var cell = makeLinearCell(); // type_hash = 0xAA * 32
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xAA} ** 32)); // Expected hash
    try plexus.executePlexus(&p, 0xC7);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKTYPEHASH (0xC7): fails on mismatched hash" {
    var p = makePDA();
    var cell = makeLinearCell(); // type_hash = 0xAA * 32
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0x00} ** 32)); // Wrong hash
    try std.testing.expectError(error.type_hash_mismatch, plexus.executePlexus(&p, 0xC7));
}

test "OP_CHECKTYPEHASH (0xC7): fails on short expected data" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{ 0xAA, 0xAA }); // Only 2 bytes, need 32
    try std.testing.expectError(error.type_hash_mismatch, plexus.executePlexus(&p, 0xC7));
}

// ── Failure atomicity tests ──
// These ops must leave the stack UNCHANGED on failure.
// Before fix: the expected argument is consumed even when the check fails.

test "OP_CHECKCAPABILITY (0xC3): stack unchanged on cap type mismatch" {
    var p = makePDA();
    var cell = makeLinearCell();
    cell[256] = 4; // METERED_ACCESS
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{2}); // Expected DATA_ACCESS — mismatch
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
    // Stack must still have both elements
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKCAPABILITY (0xC3): stack unchanged on non-LINEAR cell" {
    var p = makePDA();
    var cell = makeAffineCell();
    cell[256] = 4;
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{4});
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKIDENTITY (0xC4): stack unchanged on owner mismatch" {
    var p = makePDA();
    var cell = makeLinearCell(); // owner_id = 0xBB * 16
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0x11} ** 16)); // Wrong owner_id
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    try std.testing.expectError(error.owner_id_mismatch, plexus.executePlexus(&p, 0xC4));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKDOMAINFLAG (0xC6): stack unchanged on flag mismatch" {
    var p = makePDA();
    var cell = makeLinearCell(); // flag = EDGE_CREATION (1)
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{5}); // Expected ATTESTATION (5) — mismatch
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    try std.testing.expectError(error.domain_flag_mismatch, plexus.executePlexus(&p, 0xC6));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKTYPEHASH (0xC7): stack unchanged on hash mismatch" {
    var p = makePDA();
    var cell = makeLinearCell(); // type_hash = 0xAA * 32
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0x00} ** 32)); // Wrong hash
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    try std.testing.expectError(error.type_hash_mismatch, plexus.executePlexus(&p, 0xC7));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_CHECKCAPABILITY (0xC3): insufficient stack depth returns underflow" {
    var p = makePDA();
    // Only 1 element — need 2 (cell + expected cap)
    try p.spush(&[_]u8{4});
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xC3));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "OP_CHECKIDENTITY (0xC4): insufficient stack depth returns underflow" {
    var p = makePDA();
    try p.spush(&([_]u8{0xBB} ** 16));
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xC4));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "OP_CHECKDOMAINFLAG (0xC6): insufficient stack depth returns underflow" {
    var p = makePDA();
    try p.spush(&[_]u8{1});
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xC6));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "OP_CHECKTYPEHASH (0xC7): insufficient stack depth returns underflow" {
    var p = makePDA();
    try p.spush(&([_]u8{0xAA} ** 32));
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xC7));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

// ── Plexus dispatcher coverage (post-W1+W3) ──

// After Phase W1 (OP_SIGN at 0xCD) and W3 (OP_DECREMENT_BUDGET at 0xCE,
// OP_REFILL_BUDGET at 0xCF), the entire 0xC0-0xCF range is dispatched.
// With only one cell on the stack, every opcode in 0xC9-0xCF requires
// more arguments than that, so each fails with stack_underflow.
test "Plexus opcodes 0xC9-0xCF need multi-arg setups (stack_underflow with 1 cell)" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);

    var op: u8 = 0xC9;
    while (op <= 0xCF) : (op += 1) {
        try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, op));
        // K4: stack unchanged on error
        try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    }
}

// ── OP_WRITEPAYLOAD (0xD1) ──
//
// Stack: [cell, bytes, offset] → [cell_with_payload_modified].
// Writes `bytes` into the cell's payload region starting at the given
// payload-relative offset. Header bytes 0..256 are preserved.

test "OP_WRITEPAYLOAD (0xD1): writes bytes at offset 0" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    const payload_bytes = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    try p.spush(&payload_bytes);
    try p.spush(&[_]u8{}); // offset = 0 (empty = OP_0)

    try plexus.executePlexus(&p, 0xD1);

    // bytes + offset consumed; cell replaced by modified copy.
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(@as(u32, pda_mod.CELL_SIZE), top.len);

    // Payload bytes 0..4 = the written data.
    try std.testing.expectEqualSlices(
        u8,
        &payload_bytes,
        top.data[constants.HEADER_SIZE .. constants.HEADER_SIZE + 4],
    );
    // Header bytes 0..256 preserved verbatim.
    try std.testing.expectEqualSlices(u8, cell[0..constants.HEADER_SIZE], top.data[0..constants.HEADER_SIZE]);
    // Rest of payload (4..768) unchanged (still zeros).
    for (top.data[constants.HEADER_SIZE + 4 .. constants.CELL_SIZE]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "OP_WRITEPAYLOAD (0xD1): boundary write at offset PAYLOAD_SIZE - len" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    const payload_bytes = [_]u8{ 0xAA, 0xBB, 0xCC };
    try p.spush(&payload_bytes);
    // offset = PAYLOAD_SIZE - 3 = 765 — exact last-three-bytes write.
    try p.spush(&[_]u8{ 0xFD, 0x02 }); // CScriptNum 765 = 0x02FD LE

    try plexus.executePlexus(&p, 0xD1);

    const top = try p.speek();
    try std.testing.expectEqual(@as(u32, pda_mod.CELL_SIZE), top.len);
    try std.testing.expectEqualSlices(
        u8,
        &payload_bytes,
        top.data[constants.CELL_SIZE - 3 .. constants.CELL_SIZE],
    );
}

test "OP_WRITEPAYLOAD (0xD1): bounds violation (offset + len > PAYLOAD_SIZE) returns invalid_payload_offset and leaves stack unchanged" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    const payload_bytes = [_]u8{ 0x11, 0x22 };
    try p.spush(&payload_bytes);
    // offset = 767 — 767+2 = 769 > 768, must be rejected.
    try p.spush(&[_]u8{ 0xFF, 0x02 }); // CScriptNum 767 = 0x02FF LE

    try std.testing.expectError(error.invalid_payload_offset, plexus.executePlexus(&p, 0xD1));
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

test "OP_WRITEPAYLOAD (0xD1): negative offset rejected, stack unchanged" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{0x42});
    // CScriptNum -1 = 0x81 (sign bit + magnitude 1).
    try p.spush(&[_]u8{0x81});

    try std.testing.expectError(error.invalid_payload_offset, plexus.executePlexus(&p, 0xD1));
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

test "OP_WRITEPAYLOAD (0xD1): empty bytes write is a no-op (stack mutates but cell unchanged)" {
    var p = makePDA();
    var cell = makeLinearCell();
    // Pre-populate one payload byte so we can confirm it survives.
    cell[constants.HEADER_SIZE + 10] = 0x99;
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{}); // empty bytes
    try p.spush(&[_]u8{}); // offset 0

    try plexus.executePlexus(&p, 0xD1);

    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqualSlices(u8, &cell, top.data[0..constants.CELL_SIZE]);
}

test "OP_WRITEPAYLOAD (0xD1): insufficient stack depth returns underflow" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{0x42});
    // Only 2 items; OP_WRITEPAYLOAD needs 3.
    try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, 0xD1));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

```
