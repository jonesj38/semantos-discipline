---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/fuzz/linearity_fuzz.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.971253+00:00
---

# core/cell-engine/fuzz/linearity_fuzz.zig

```zig
// Phase 12: Linearity property-based fuzz harness
// Asserts K1 (linearity), K4 (failure atomicity) under random inputs.
// Reference: proofs/lean/Semantos/Theorems/LinearityK1.lean

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");

const ITERATIONS: u32 = 100_000;
const SEED: u64 = 0xDEAD_BEEF_1234_5678;

// ── Cell builder ──

fn makeTestCell(rng: *std.Random.Xoshiro256, lin: u32) pda_mod.Cell {
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
    // Random domain flag
    std.mem.writeInt(u32, cell[24..28], rng.random().int(u32), .little);
    // Random type hash
    rng.random().bytes(cell[30..62]);
    // Random owner ID
    rng.random().bytes(cell[62..78]);
    return cell;
}

fn randomLinearityValue(rng: *std.Random.Xoshiro256) u32 {
    return rng.random().intRangeAtMost(u32, 1, 4);
}

fn randomOperation(rng: *std.Random.Xoshiro256) linearity.LinearityOperation {
    const ops = [_]linearity.LinearityOperation{ .duplicate, .discard, .consume, .swap, .inspect };
    return ops[rng.random().intRangeLessThan(usize, 0, ops.len)];
}

// ── Known permission table (ground truth from Lean model) ──

fn expectedPermit(lin: linearity.LinearityType, op: linearity.LinearityOperation) bool {
    return switch (lin) {
        .linear => switch (op) {
            .duplicate => false,
            .discard => false,
            .consume, .swap, .inspect => true,
        },
        .affine => switch (op) {
            .duplicate => false,
            .discard, .consume, .swap, .inspect => true,
        },
        .relevant => switch (op) {
            .discard => false,
            .duplicate, .consume, .swap, .inspect => true,
        },
        .debug => true,
    };
}

// ── Test 1: Permission matrix holds for all random (type, op) pairs ──

test "fuzz: linearity permission matrix matches Lean model" {
    var rng = std.Random.Xoshiro256.init(SEED);

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        const lin_val = randomLinearityValue(&rng);
        const op = randomOperation(&rng);
        const lin = std.meta.intToEnum(linearity.LinearityType, lin_val) catch continue;

        const result = linearity.checkLinearity(lin, op);
        const permitted = expectedPermit(lin, op);

        if (permitted) {
            // Should succeed
            _ = result catch |err| {
                std.debug.print("FAIL: lin={} op={} should permit but got {}\n", .{ lin_val, @intFromEnum(op), err });
                return error.TestUnexpectedResult;
            };
        } else {
            // Should error
            if (result) |_| {
                std.debug.print("FAIL: lin={} op={} should deny but succeeded\n", .{ lin_val, @intFromEnum(op) });
                return error.TestUnexpectedResult;
            } else |_| {
                // Expected error — good
            }
        }
    }
}

// ── Test 2: LINEAR cell uniqueness across both stacks (K1c) ──

fn countLinearCells(p: *const pda_mod.PDA) u32 {
    var count: u32 = 0;
    // Scan main stack
    var i: u32 = 0;
    while (i < p.main_sp) : (i += 1) {
        const len = p.main_lengths[i];
        if (len >= 20) { // Minimum for linearity field
            const lin_val = std.mem.readInt(u32, p.main_stack[i][16..20], .little);
            if (lin_val == 1) count += 1; // LINEAR
        }
    }
    // Scan aux stack
    i = 0;
    while (i < p.aux_sp) : (i += 1) {
        const len = p.aux_lengths[i];
        if (len >= 20) {
            const lin_val = std.mem.readInt(u32, p.aux_stack[i][16..20], .little);
            if (lin_val == 1) count += 1;
        }
    }
    return count;
}

test "fuzz: LINEAR cell appears at most once across both stacks (K1c)" {
    var rng = std.Random.Xoshiro256.init(SEED +% 1);
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = true;

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        // Reset PDA each iteration
        p.reset();
        p.enforcement_enabled = true;

        // Push one LINEAR cell
        var cell = makeTestCell(&rng, 1); // LINEAR
        p.spushCell(&cell, pda_mod.CELL_SIZE) catch continue;

        // Push a few more non-LINEAR cells for context
        const extra = rng.random().intRangeAtMost(u32, 0, 3);
        var e: u32 = 0;
        while (e < extra) : (e += 1) {
            const lin = rng.random().intRangeAtMost(u32, 2, 4); // AFFINE, RELEVANT, or DEBUG
            var c = makeTestCell(&rng, lin);
            p.spushCell(&c, pda_mod.CELL_SIZE) catch break;
        }

        // Run a few random stack operations
        const ops = rng.random().intRangeAtMost(u32, 1, 8);
        var o: u32 = 0;
        while (o < ops) : (o += 1) {
            const op_choice = rng.random().intRangeLessThan(u32, 0, 8);
            switch (op_choice) {
                0 => _ = p.sdup_enforced() catch {},
                1 => _ = p.sdrop_enforced() catch {},
                2 => _ = p.sswap_enforced() catch {},
                3 => _ = p.sover_enforced() catch {},
                4 => _ = p.srot() catch {},
                5 => _ = p.toalt() catch {},
                6 => _ = p.fromalt() catch {},
                7 => _ = p.snip_enforced() catch {},
                else => {},
            }

            // K1c: LINEAR cell count ≤ 1 across BOTH stacks
            const linear_count = countLinearCells(&p);
            if (linear_count > 1) {
                std.debug.print("K1c VIOLATION: {} LINEAR cells on iteration {}, op {}\n", .{ linear_count, i, o });
                return error.TestUnexpectedResult;
            }
        }
    }
}

// ── Test 3: Rejected operations leave stack unchanged (K4) ──

test "fuzz: rejected linearity operations preserve stack state (K4)" {
    var rng = std.Random.Xoshiro256.init(SEED +% 2);
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = true;

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();
        p.enforcement_enabled = true;

        // Push a random cell
        const lin = randomLinearityValue(&rng);
        var cell = makeTestCell(&rng, lin);
        p.spushCell(&cell, pda_mod.CELL_SIZE) catch continue;

        // Maybe push a second for two-operand ops
        if (rng.random().boolean()) {
            const lin2 = randomLinearityValue(&rng);
            var cell2 = makeTestCell(&rng, lin2);
            p.spushCell(&cell2, pda_mod.CELL_SIZE) catch {};
        }

        // Snapshot stack pointers
        const main_sp_before = p.main_sp;
        const aux_sp_before = p.aux_sp;

        // Try a random enforced operation
        const op_choice = rng.random().intRangeLessThan(u32, 0, 6);
        const result: anyerror!void = switch (op_choice) {
            0 => p.sdup_enforced(),
            1 => p.sdrop_enforced(),
            2 => p.sover_enforced(),
            3 => p.s2dup_enforced(),
            4 => p.s2drop_enforced(),
            5 => p.snip_enforced(),
            else => {},
        };

        if (result) |_| {
            // Success — stack may have changed, that's fine
        } else |err| {
            // Error — verify stack is unchanged
            switch (err) {
                error.cannot_duplicate_linear,
                error.cannot_discard_linear,
                error.cannot_duplicate_affine,
                error.cannot_discard_relevant,
                => {
                    if (p.main_sp != main_sp_before or p.aux_sp != aux_sp_before) {
                        std.debug.print("K4 VIOLATION: stack changed on linearity error. main_sp: {} → {}, aux_sp: {} → {}\n", .{
                            main_sp_before, p.main_sp, aux_sp_before, p.aux_sp,
                        });
                        return error.TestUnexpectedResult;
                    }
                },
                else => {}, // stack_underflow etc. may legitimately not change stack
            }
        }
    }
}

```
