---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/linearity_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.968130+00:00
---

# core/cell-engine/tests/linearity_conformance.zig

```zig
// Phase 4: Linearity enforcement conformance tests
// Reference: FORTH:LINEARITY, CORE:SEMOBJ, PHASE-4-PLEXUS-OPCODES.md

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");

// ── Test cell builder ──

fn makeTestCell(lin: u32, domain_flag: u32, type_hash: [32]u8, owner_id: [16]u8) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    // Magic
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    // Linearity
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    // Version
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    // Domain flag
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    // Type hash
    @memcpy(cell[30..62], &type_hash);
    // Owner ID
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

fn makeDebugCell() pda_mod.Cell {
    return makeTestCell(4, 0, [_]u8{0} ** 32, [_]u8{0} ** 16);
}

fn makePDA() pda_mod.PDA {
    return pda_mod.PDA.init(500000);
}

// ── checkLinearity: rule matrix ──

// LINEAR
test "LINEAR: DUP fails with cannot_duplicate_linear" {
    try std.testing.expectError(error.cannot_duplicate_linear, linearity.checkLinearity(.linear, .duplicate));
}

test "LINEAR: DROP fails with cannot_discard_linear" {
    try std.testing.expectError(error.cannot_discard_linear, linearity.checkLinearity(.linear, .discard));
}

test "LINEAR: consume succeeds" {
    try linearity.checkLinearity(.linear, .consume);
}

test "LINEAR: swap succeeds" {
    try linearity.checkLinearity(.linear, .swap);
}

test "LINEAR: inspect succeeds" {
    try linearity.checkLinearity(.linear, .inspect);
}

// AFFINE
test "AFFINE: DUP fails with cannot_duplicate_affine" {
    try std.testing.expectError(error.cannot_duplicate_affine, linearity.checkLinearity(.affine, .duplicate));
}

test "AFFINE: DROP succeeds" {
    try linearity.checkLinearity(.affine, .discard);
}

test "AFFINE: consume succeeds" {
    try linearity.checkLinearity(.affine, .consume);
}

test "AFFINE: swap succeeds" {
    try linearity.checkLinearity(.affine, .swap);
}

// RELEVANT
test "RELEVANT: DUP succeeds" {
    try linearity.checkLinearity(.relevant, .duplicate);
}

test "RELEVANT: DROP fails with cannot_discard_relevant" {
    try std.testing.expectError(error.cannot_discard_relevant, linearity.checkLinearity(.relevant, .discard));
}

test "RELEVANT: consume succeeds" {
    try linearity.checkLinearity(.relevant, .consume);
}

test "RELEVANT: OVER succeeds" {
    try linearity.checkLinearity(.relevant, .duplicate);
}

// DEBUG
test "DEBUG: all operations succeed" {
    try linearity.checkLinearity(.debug, .duplicate);
    try linearity.checkLinearity(.debug, .discard);
    try linearity.checkLinearity(.debug, .consume);
    try linearity.checkLinearity(.debug, .swap);
    try linearity.checkLinearity(.debug, .inspect);
}

// ── Header field extraction ──

test "getLinearity reads offset 16, 4 bytes LE" {
    var cell = makeLinearCell();
    const lin = try linearity.getLinearity(&cell);
    try std.testing.expectEqual(linearity.LinearityType.linear, lin);

    // Write AFFINE
    std.mem.writeInt(u32, cell[16..20], 2, .little);
    const lin2 = try linearity.getLinearity(&cell);
    try std.testing.expectEqual(linearity.LinearityType.affine, lin2);
}

test "getDomainFlag reads offset 24, 4 bytes LE" {
    const cell = makeLinearCell();
    const flag = try linearity.getDomainFlag(&cell);
    try std.testing.expectEqual(constants.DOMAIN_FLAG_EDGE_CREATION, flag);
}

test "getTypeHash reads offset 30, 32 bytes" {
    const cell = makeLinearCell();
    const hash = try linearity.getTypeHash(&cell);
    try std.testing.expectEqual([_]u8{0xAA} ** 32, hash);
}

test "getOwnerId reads offset 62, 16 bytes" {
    const cell = makeLinearCell();
    const id = try linearity.getOwnerId(&cell);
    try std.testing.expectEqual([_]u8{0xBB} ** 16, id);
}

test "getCapabilityType reads offset 256, 1 byte" {
    var cell = makeLinearCell();
    cell[256] = 4; // METERED_ACCESS
    const cap_type = try linearity.getCapabilityType(&cell);
    try std.testing.expectEqual(@as(u8, 4), cap_type);
}

test "invalid linearity value returns invalid_linearity_type" {
    var cell = makeLinearCell();
    std.mem.writeInt(u32, cell[16..20], 0, .little);
    try std.testing.expectError(error.invalid_linearity_type, linearity.getLinearity(&cell));

    std.mem.writeInt(u32, cell[16..20], 5, .little);
    try std.testing.expectError(error.invalid_linearity_type, linearity.getLinearity(&cell));
}

test "truncated cell data returns cell_too_short" {
    const short: [10]u8 = [_]u8{0} ** 10;
    try std.testing.expectError(error.cell_too_short, linearity.getLinearity(&short));
    try std.testing.expectError(error.cell_too_short, linearity.getDomainFlag(&short));
}

// ── classifyFlag ──

test "classifyFlag: well-known, extended, sovereign, reserved" {
    try std.testing.expectEqual(linearity.FlagTier.reserved, linearity.classifyFlag(0));
    try std.testing.expectEqual(linearity.FlagTier.well_known, linearity.classifyFlag(1));
    try std.testing.expectEqual(linearity.FlagTier.well_known, linearity.classifyFlag(255));
    try std.testing.expectEqual(linearity.FlagTier.extended, linearity.classifyFlag(256));
    try std.testing.expectEqual(linearity.FlagTier.extended, linearity.classifyFlag(65535));
    try std.testing.expectEqual(linearity.FlagTier.sovereign, linearity.classifyFlag(65536));
    try std.testing.expectEqual(linearity.FlagTier.sovereign, linearity.classifyFlag(0xFFFFFFFF));
}

// ── PDA enforcement toggle ──

test "enforcement disabled: DUP LINEAR cell succeeds" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    // Enforcement off by default
    try std.testing.expect(!p.enforcement_enabled);
    try p.sdup_enforced(); // Should succeed — enforcement is off
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "enforcement enabled: DUP LINEAR cell fails" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_duplicate_linear, p.sdup_enforced());
}

test "enforcement enabled: DROP LINEAR cell fails" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_discard_linear, p.sdrop_enforced());
}

test "enforcement enabled: SWAP LINEAR cell succeeds (reorder)" {
    var p = makePDA();
    var cell1 = makeLinearCell();
    var cell2 = makeAffineCell();
    try p.spushCell(&cell1, pda_mod.CELL_SIZE);
    try p.spushCell(&cell2, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try p.sswap_enforced(); // SWAP is always allowed
}

test "enforcement enabled: DUP AFFINE cell fails" {
    var p = makePDA();
    var cell = makeAffineCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_duplicate_affine, p.sdup_enforced());
}

test "enforcement enabled: DROP AFFINE cell succeeds" {
    var p = makePDA();
    var cell = makeAffineCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try p.sdrop_enforced();
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
}

test "enforcement enabled: DUP RELEVANT cell succeeds" {
    var p = makePDA();
    var cell = makeRelevantCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try p.sdup_enforced();
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "enforcement enabled: DROP RELEVANT cell fails" {
    var p = makePDA();
    var cell = makeRelevantCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_discard_relevant, p.sdrop_enforced());
}

test "enforcement enabled: DEBUG cell — all operations succeed" {
    var p = makePDA();
    var cell = makeDebugCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try p.sdup_enforced();
    try p.sdrop_enforced();
}

test "enforcement can be toggled mid-session" {
    var p = makePDA();
    var cell = makeLinearCell();
    try p.spushCell(&cell, pda_mod.CELL_SIZE);

    // Start disabled — DUP works
    try p.sdup_enforced();
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());

    // Enable — DUP fails
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_duplicate_linear, p.sdup_enforced());

    // Disable again — DUP works
    p.disableEnforcement();
    try p.sdup_enforced();
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

// ── OVER enforcement ──

test "enforcement enabled: OVER LINEAR cell fails (copies second)" {
    var p = makePDA();
    var cell_a = makeLinearCell(); // second on stack — the one being copied
    var cell_b = makeDebugCell(); // top
    try p.spushCell(&cell_a, pda_mod.CELL_SIZE);
    try p.spushCell(&cell_b, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try std.testing.expectError(error.cannot_duplicate_linear, p.sover_enforced());
}

test "enforcement enabled: OVER RELEVANT cell succeeds" {
    var p = makePDA();
    var cell_a = makeRelevantCell();
    var cell_b = makeDebugCell();
    try p.spushCell(&cell_a, pda_mod.CELL_SIZE);
    try p.spushCell(&cell_b, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try p.sover_enforced();
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

// ── 2DUP / 2DROP enforcement ──

test "enforcement enabled: 2DUP with LINEAR cell fails" {
    var p = makePDA();
    var cell_a = makeLinearCell();
    var cell_b = makeDebugCell();
    try p.spushCell(&cell_a, pda_mod.CELL_SIZE);
    try p.spushCell(&cell_b, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    // Top (debug) passes but second (linear) fails duplicate check
    // Actually both are checked — debug succeeds, linear fails
    try std.testing.expectError(error.cannot_duplicate_linear, p.s2dup_enforced());
}

test "enforcement enabled: 2DROP with RELEVANT cell fails" {
    var p = makePDA();
    var cell_a = makeRelevantCell();
    var cell_b = makeDebugCell();
    try p.spushCell(&cell_a, pda_mod.CELL_SIZE);
    try p.spushCell(&cell_b, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    // Top (debug) passes but second (relevant) fails discard check
    try std.testing.expectError(error.cannot_discard_relevant, p.s2drop_enforced());
}

// ── E-P4.2: short stack items rejected by length-bounded enforcement ──

test "enforcement enabled: DUP on short (non-cell) item fails with cell_too_short" {
    var p = makePDA();
    // Push a small value (1 byte) — not a valid semantic object
    try p.spush(&[_]u8{0x42});
    p.enableEnforcement();
    try std.testing.expectError(error.cell_too_short, p.sdup_enforced());
}

test "enforcement enabled: DROP on short item fails with cell_too_short" {
    var p = makePDA();
    try p.spush(&[_]u8{ 0x01, 0x02, 0x03 }); // 3 bytes — too short for header
    p.enableEnforcement();
    try std.testing.expectError(error.cell_too_short, p.sdrop_enforced());
}

```
