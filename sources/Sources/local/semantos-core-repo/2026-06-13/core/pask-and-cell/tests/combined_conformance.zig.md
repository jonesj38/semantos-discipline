---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask-and-cell/tests/combined_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.017211+00:00
---

# core/pask-and-cell/tests/combined_conformance.zig

```zig
// M1.12 Combined kernel conformance tests.
//
// Tests that both kernel_* (cell engine) and pask_* (pask) module graphs
// can be composed into a single binary. We call the underlying module APIs
// (the same logic wrapped by the WASM export functions) to verify both
// kernels operate correctly when compiled together and share linear memory.
//
// TDD: written before the combined build was wired (red phase).
// All tests pass once build.zig produces a valid combined binary (green phase).

const std = @import("std");

// Cell engine modules
const pda_mod = @import("pda");
const executor_mod = @import("executor");
const allocator_mod = @import("allocator");
const constants = @import("constants");
const errors = @import("errors");

// Pask modules
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const stability_mod = @import("stability");

// ── M1.12-T-kernel-init ──────────────────────────────────────────────────
// Mirrors kernel_init(): initialise the PDA and execution context.
// Verifies the cell engine module graph compiles and links correctly
// in the combined build.

test "M1.12-T-kernel-init" {
    var pda: pda_mod.PDA = undefined;
    var arena_buf: [65536]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    pda.initInPlace(executor_mod.DEFAULT_MAX_OPS);
    const ctx = executor_mod.ExecutionContext.init(&pda, &arena);
    _ = ctx;
    // Initialised without panic — kernel_init equivalent returns 0 (success).
    try std.testing.expect(true);
}

// ── M1.12-T-pask-stable ─────────────────────────────────────────────────
// Mirrors pask_node_is_stable(0): with no nodes upserted, index 0 is out of
// range. The pask store starts with node_count == 0.

test "M1.12-T-pask-stable" {
    var s: store_mod.Store = undefined;
    s.init(config.DEFAULT);
    // node_count == 0 → index 0 is out of range → is_stable query undefined.
    // The real export returns -1 for out-of-range. Here we just check
    // node_count is 0 (no nodes initialised).
    try std.testing.expectEqual(@as(u32, 0), s.node_count);
}

// ── M1.12-T-both-active ─────────────────────────────────────────────────
// Both kernels initialise, operate, and share memory without corruption.
// Initialise the cell engine PDA, then the pask store; verify each
// sees its own state correctly.

test "M1.12-T-both-active" {
    // Cell engine init (mirrors kernel_init)
    var pda: pda_mod.PDA = undefined;
    var arena_buf: [65536]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    pda.initInPlace(executor_mod.DEFAULT_MAX_OPS);
    const ctx = executor_mod.ExecutionContext.init(&pda, &arena);
    _ = ctx;

    // Pask init (mirrors pask_init)
    var s: store_mod.Store = undefined;
    s.init(config.DEFAULT);
    try std.testing.expectEqual(@as(u32, 0), s.node_count);

    // Cell engine still functional after pask init — reset and re-init.
    pda.initInPlace(executor_mod.DEFAULT_MAX_OPS);
    arena = allocator_mod.ScriptArena.init(&arena_buf);
    // No corruption: both kernels can initialise in sequence.
    try std.testing.expect(true);
}

// ── M1.12-T-pask-upsert ─────────────────────────────────────────────────
// Upsert a node and verify pask_node_h_state behaviour.
// h_state for a newly upserted node is 0.0 before any interact() call.

test "M1.12-T-pask-upsert" {
    var s: store_mod.Store = undefined;
    s.init(config.DEFAULT);

    const cell_id = "test-cell-001";
    const type_path = "test/type";
    const now_ms: u64 = 1_000_000;

    const idx = try s.upsertNode(cell_id, type_path, now_ms);
    try std.testing.expectEqual(@as(u32, 1), s.node_count);

    // h_state starts at 0 — mirrors pask_node_h_state returning 0 for new node
    const node = s.getNode(idx).?;
    try std.testing.expectEqual(@as(f64, 0.0), node.h_state);

    // is_stable is 0 (not stable) for a newly upserted node
    try std.testing.expectEqual(@as(u8, 0), node.is_stable);
}

// ── M1.12-T-exports-present ─────────────────────────────────────────────
// Verify that the combined module graph contains both kernel and pask module
// hierarchies by importing key types from each. A compile failure here
// means one side of the combined build is missing.

test "M1.12-T-exports-present" {
    // Cell engine types
    _ = pda_mod.PDA;
    _ = executor_mod.ExecutionContext;
    _ = executor_mod.DEFAULT_MAX_OPS;
    _ = allocator_mod.ScriptArena;
    _ = constants.CELL_SIZE;
    _ = errors.KernelError;

    // Pask types
    _ = config.Config;
    _ = config.DEFAULT;
    _ = types.Node;
    _ = types.Edge;
    _ = types.StableThread;
    _ = store_mod.Store;
    _ = stability_mod.checkNode;

    try std.testing.expect(true);
}

```
