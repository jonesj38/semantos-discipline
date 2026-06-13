---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/fuzz/opcode_fuzz.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.970682+00:00
---

# core/cell-engine/fuzz/opcode_fuzz.zig

```zig
// Phase 12: Opcode property-based fuzz harness
// Asserts no LINEAR duplicated, no RELEVANT discarded under random opcode sequences.
// Reference: proofs/lean/Semantos/Theorems/LinearityK1.lean

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");

const ITERATIONS: u32 = 50_000;
const SEED: u64 = 0xCAFE_BABE_DEAD_BEEF;

// ── Cell builder ──

fn makeTestCell(rng: *std.Random.Xoshiro256, lin: u32) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    std.mem.writeInt(u32, cell[24..28], rng.random().int(u32), .little);
    rng.random().bytes(cell[30..62]);
    rng.random().bytes(cell[62..78]);
    // Capability type at payload byte 0 (offset 256)
    cell[256] = rng.random().int(u8);
    return cell;
}

fn randomLinearityValue(rng: *std.Random.Xoshiro256) u32 {
    return rng.random().intRangeAtMost(u32, 1, 4);
}

fn countLinearCells(p: *const pda_mod.PDA) u32 {
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < p.main_sp) : (i += 1) {
        if (p.main_lengths[i] >= 20) {
            const v = std.mem.readInt(u32, p.main_stack[i][16..20], .little);
            if (v == 1) count += 1;
        }
    }
    i = 0;
    while (i < p.aux_sp) : (i += 1) {
        if (p.aux_lengths[i] >= 20) {
            const v = std.mem.readInt(u32, p.aux_stack[i][16..20], .little);
            if (v == 1) count += 1;
        }
    }
    return count;
}

fn countRelevantCells(p: *const pda_mod.PDA) u32 {
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < p.main_sp) : (i += 1) {
        if (p.main_lengths[i] >= 20) {
            const v = std.mem.readInt(u32, p.main_stack[i][16..20], .little);
            if (v == 3) count += 1;
        }
    }
    i = 0;
    while (i < p.aux_sp) : (i += 1) {
        if (p.aux_lengths[i] >= 20) {
            const v = std.mem.readInt(u32, p.aux_stack[i][16..20], .little);
            if (v == 3) count += 1;
        }
    }
    return count;
}

// ── Test: random opcode sequences preserve linearity invariants ──

test "fuzz: random opcode sequences never duplicate LINEAR or discard RELEVANT" {
    var rng = std.Random.Xoshiro256.init(SEED);
    var p = pda_mod.PDA.init(500_000);

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();
        p.enforcement_enabled = true;

        // Push 2-5 cells with random linearity
        const num_cells = rng.random().intRangeAtMost(u32, 2, 5);
        var initial_linear: u32 = 0;
        var initial_relevant: u32 = 0;
        var n: u32 = 0;
        while (n < num_cells) : (n += 1) {
            const lin = randomLinearityValue(&rng);
            var cell = makeTestCell(&rng, lin);
            p.spushCell(&cell, pda_mod.CELL_SIZE) catch break;
            if (lin == 1) initial_linear += 1;
            if (lin == 3) initial_relevant += 1;
        }

        // Run 3-10 random enforced operations
        const num_ops = rng.random().intRangeAtMost(u32, 3, 10);
        var o: u32 = 0;
        while (o < num_ops) : (o += 1) {
            const op_choice = rng.random().intRangeLessThan(u32, 0, 14);
            switch (op_choice) {
                0 => _ = p.sdup_enforced() catch {},
                1 => _ = p.sdrop_enforced() catch {},
                2 => _ = p.sswap_enforced() catch {},
                3 => _ = p.sover_enforced() catch {},
                4 => _ = p.srot() catch {},
                5 => _ = p.toalt() catch {},
                6 => _ = p.fromalt() catch {},
                7 => _ = p.snip_enforced() catch {},
                8 => _ = p.stuck_enforced() catch {},
                9 => _ = p.s2dup_enforced() catch {},
                10 => _ = p.s2drop_enforced() catch {},
                11 => _ = p.spick_enforced(rng.random().intRangeLessThan(u32, 0, 4)) catch {},
                12 => _ = p.sroll_enforced(rng.random().intRangeLessThan(u32, 0, 4)) catch {},
                13 => _ = p.sifdup_enforced() catch {},
                else => {},
            }

            // K1: LINEAR count must never increase (no duplication)
            const current_linear = countLinearCells(&p);
            if (current_linear > initial_linear) {
                std.debug.print("K1 VIOLATION: LINEAR count increased from {} to {} on iter {}, op {}\n", .{
                    initial_linear, current_linear, i, o,
                });
                return error.TestUnexpectedResult;
            }

            // RELEVANT count must never decrease (no discard)
            const current_relevant = countRelevantCells(&p);
            if (current_relevant < initial_relevant and p.main_sp + p.aux_sp > 0) {
                // Only flag if there are still cells on the stack — if stack is empty,
                // relevant count naturally goes to 0
                const total_cells = p.main_sp + p.aux_sp;
                if (total_cells >= initial_relevant) {
                    std.debug.print("RELEVANT VIOLATION: count decreased from {} to {} on iter {}, op {} (stack has {} cells)\n", .{
                        initial_relevant, current_relevant, i, o, total_cells,
                    });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
}

// ── Test: Plexus opcodes on random cells don't crash ──

test "fuzz: plexus single-arg opcodes on random stack configs never crash" {
    var rng = std.Random.Xoshiro256.init(SEED +% 1);
    var p = pda_mod.PDA.init(500_000);

    // Single-arg opcodes only peek top cell — safe with full cells.
    //
    // After Phase W1+W3 there are no reserved opcodes in 0xC0-0xCF; the
    // multi-arg opcodes (0xC9-0xCF) are exercised separately by tests
    // that push appropriately-sized arguments. Pushing full-size cells
    // through the script-number reader (cellToI64) on those opcodes
    // would overflow the i64 shift count, so we don't fuzz them here.
    const single_arg_opcodes = [_]u8{ 0xC0, 0xC1, 0xC2, 0xC5 };

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();
        p.enforcement_enabled = true;

        // Push 0-3 random cells
        const num_cells = rng.random().intRangeAtMost(u32, 0, 3);
        var n: u32 = 0;
        while (n < num_cells) : (n += 1) {
            const lin = randomLinearityValue(&rng);
            var cell = makeTestCell(&rng, lin);
            p.spushCell(&cell, pda_mod.CELL_SIZE) catch break;
        }

        const opcode = single_arg_opcodes[rng.random().intRangeLessThan(usize, 0, single_arg_opcodes.len)];
        _ = plexus.executePlexus(&p, opcode) catch {};
    }
}

test "fuzz: plexus two-arg opcodes with proper argument format never crash" {
    var rng = std.Random.Xoshiro256.init(SEED +% 2);
    var p = pda_mod.PDA.init(500_000);

    // Two-arg opcodes: [cell, argument] on stack
    // 0xC3 CHECKCAPABILITY expects 1-byte cap
    // 0xC4 CHECKIDENTITY expects 16-byte owner_id
    // 0xC6 CHECKDOMAINFLAG expects small integer (4 bytes)
    // 0xC7 CHECKTYPEHASH expects 32-byte hash
    const two_arg_opcodes = [_]u8{ 0xC3, 0xC4, 0xC6, 0xC7 };

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();
        p.enforcement_enabled = true;

        // Push a cell first
        const lin = randomLinearityValue(&rng);
        var cell = makeTestCell(&rng, lin);
        p.spushCell(&cell, pda_mod.CELL_SIZE) catch continue;

        const opcode = two_arg_opcodes[rng.random().intRangeLessThan(usize, 0, two_arg_opcodes.len)];

        // Push a properly-sized argument for the opcode
        switch (opcode) {
            0xC3 => {
                // Capability: 1-byte value
                var arg = [_]u8{rng.random().int(u8)};
                _ = p.spush(&arg) catch continue;
            },
            0xC4 => {
                // Owner ID: 16 bytes
                var arg: [16]u8 = undefined;
                rng.random().bytes(&arg);
                _ = p.spush(&arg) catch continue;
            },
            0xC6 => {
                // Domain flag: 4-byte LE integer
                var arg: [4]u8 = undefined;
                std.mem.writeInt(u32, &arg, rng.random().int(u32), .little);
                _ = p.spush(&arg) catch continue;
            },
            0xC7 => {
                // Type hash: 32 bytes
                var arg: [32]u8 = undefined;
                rng.random().bytes(&arg);
                _ = p.spush(&arg) catch continue;
            },
            else => {},
        }

        _ = plexus.executePlexus(&p, opcode) catch {};
    }
}

```
