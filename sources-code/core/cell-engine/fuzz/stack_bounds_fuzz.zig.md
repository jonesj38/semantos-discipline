---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/fuzz/stack_bounds_fuzz.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.971526+00:00
---

# core/cell-engine/fuzz/stack_bounds_fuzz.zig

```zig
// Phase 12: Stack bounds property-based fuzz harness
// Asserts K5 stack bounds: main ≤ 1024, aux ≤ 256, clean errors on overflow/underflow.
// Reference: proofs/lean/Semantos/Theorems/TerminationK5.lean

const std = @import("std");
const pda_mod = @import("pda");
const constants = @import("constants");

const ITERATIONS: u32 = 100_000;
const SEED: u64 = 0x1337_1337_4242_4242;

// ── Test 1: Random push/pop sequences respect main stack bounds ──

test "fuzz: main stack bounds never violated under random push/pop" {
    var rng = std.Random.Xoshiro256.init(SEED);
    var p = pda_mod.PDA.init(500_000);

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();

        // Random sequence of 1-200 push/pop operations
        const num_ops = rng.random().intRangeAtMost(u32, 1, 200);
        var o: u32 = 0;
        while (o < num_ops) : (o += 1) {
            const do_push = rng.random().boolean();
            if (do_push) {
                // Push random data
                var data: [4]u8 = undefined;
                rng.random().bytes(&data);
                const result = p.spush(&data);
                if (result) |_| {
                    // Push succeeded — sp must be ≤ 1024
                    if (p.main_sp > pda_mod.MAIN_STACK_DEPTH) {
                        std.debug.print("BOUNDS VIOLATION: main_sp={} > {}\n", .{ p.main_sp, pda_mod.MAIN_STACK_DEPTH });
                        return error.TestUnexpectedResult;
                    }
                } else |err| {
                    // Must be stack_overflow, not a crash
                    try std.testing.expectEqual(error.stack_overflow, err);
                }
            } else {
                const result = p.spop();
                if (result) |_| {
                    // Pop succeeded — fine
                } else |err| {
                    try std.testing.expectEqual(error.stack_underflow, err);
                }
            }
        }
    }
}

// ── Test 2: Random push/pop sequences respect aux stack bounds ──

test "fuzz: aux stack bounds never violated under random push/pop" {
    var rng = std.Random.Xoshiro256.init(SEED +% 1);
    var p = pda_mod.PDA.init(500_000);

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();

        const num_ops = rng.random().intRangeAtMost(u32, 1, 200);
        var o: u32 = 0;
        while (o < num_ops) : (o += 1) {
            const do_push = rng.random().boolean();
            if (do_push) {
                var data: [4]u8 = undefined;
                rng.random().bytes(&data);
                const result = p.apush(&data);
                if (result) |_| {
                    if (p.aux_sp > pda_mod.AUX_STACK_DEPTH) {
                        std.debug.print("BOUNDS VIOLATION: aux_sp={} > {}\n", .{ p.aux_sp, pda_mod.AUX_STACK_DEPTH });
                        return error.TestUnexpectedResult;
                    }
                } else |err| {
                    try std.testing.expectEqual(error.stack_overflow, err);
                }
            } else {
                const result = p.apop();
                if (result) |_| {} else |err| {
                    try std.testing.expectEqual(error.stack_underflow, err);
                }
            }
        }
    }
}

// ── Test 3: Interleaved main/aux + toalt/fromalt respects both bounds ──

test "fuzz: interleaved main/aux/toalt/fromalt respects both stack bounds" {
    var rng = std.Random.Xoshiro256.init(SEED +% 2);
    var p = pda_mod.PDA.init(500_000);

    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        p.reset();

        const num_ops = rng.random().intRangeAtMost(u32, 1, 100);
        var o: u32 = 0;
        while (o < num_ops) : (o += 1) {
            const choice = rng.random().intRangeLessThan(u32, 0, 6);
            switch (choice) {
                0 => {
                    var data: [4]u8 = undefined;
                    rng.random().bytes(&data);
                    _ = p.spush(&data) catch {};
                },
                1 => _ = p.spop() catch {},
                2 => {
                    var data: [4]u8 = undefined;
                    rng.random().bytes(&data);
                    _ = p.apush(&data) catch {};
                },
                3 => _ = p.apop() catch {},
                4 => _ = p.toalt() catch {},
                5 => _ = p.fromalt() catch {},
                else => {},
            }

            // Invariant: stack pointers always in bounds
            if (p.main_sp > pda_mod.MAIN_STACK_DEPTH) {
                std.debug.print("main_sp overflow: {}\n", .{p.main_sp});
                return error.TestUnexpectedResult;
            }
            if (p.aux_sp > pda_mod.AUX_STACK_DEPTH) {
                std.debug.print("aux_sp overflow: {}\n", .{p.aux_sp});
                return error.TestUnexpectedResult;
            }
        }
    }
}

// ── Test 4: Fill main stack to capacity, verify overflow ──

test "fuzz: main stack overflow at exactly MAIN_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500_000);
    var data = [_]u8{0x42} ** 4;

    // Fill to capacity
    var i: u32 = 0;
    while (i < pda_mod.MAIN_STACK_DEPTH) : (i += 1) {
        try p.spush(&data);
    }
    try std.testing.expectEqual(pda_mod.MAIN_STACK_DEPTH, p.main_sp);

    // Next push must overflow
    try std.testing.expectError(error.stack_overflow, p.spush(&data));
    try std.testing.expectEqual(pda_mod.MAIN_STACK_DEPTH, p.main_sp); // unchanged
}

// ── Test 5: Fill aux stack to capacity, verify overflow ──

test "fuzz: aux stack overflow at exactly AUX_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500_000);
    var data = [_]u8{0x42} ** 4;

    var i: u32 = 0;
    while (i < pda_mod.AUX_STACK_DEPTH) : (i += 1) {
        try p.apush(&data);
    }
    try std.testing.expectEqual(pda_mod.AUX_STACK_DEPTH, p.aux_sp);

    try std.testing.expectError(error.stack_overflow, p.apush(&data));
    try std.testing.expectEqual(pda_mod.AUX_STACK_DEPTH, p.aux_sp);
}

```
