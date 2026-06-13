---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/capability_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.969521+00:00
---

# core/cell-engine/tests/capability_conformance.zig

```zig
// Phase 5: Capability conformance tests
// Tests capability token script evaluation through the 2-PDA executor.

const std = @import("std");
const constants = @import("constants");
const errors = @import("errors");
const pda_mod = @import("pda");
const executor_mod = @import("executor");
const allocator_mod = @import("allocator");

// ── Capability script evaluation tests ──

test "OP_TRUE capability script succeeds" {
    // A locking script that is just OP_TRUE (0x51) should always succeed
    var pda: pda_mod.PDA = undefined;
    pda.initInPlace(1000);

    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);

    var ctx = executor_mod.ExecutionContext.init(&pda, &arena);
    const lock_script = [_]u8{0x51}; // OP_TRUE
    ctx.loadScript(&lock_script) catch unreachable;
    ctx.pc = 0;
    ctx.current_phase = .lock;
    ctx.executing = true;

    const result = executor_mod.execute(&ctx) catch false;
    try std.testing.expect(result);
}

test "OP_FALSE capability script fails" {
    // A locking script that is just OP_FALSE (0x00) should fail
    var pda: pda_mod.PDA = undefined;
    pda.initInPlace(1000);

    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);

    var ctx = executor_mod.ExecutionContext.init(&pda, &arena);
    const lock_script = [_]u8{0x00}; // OP_FALSE
    ctx.loadScript(&lock_script) catch unreachable;
    ctx.pc = 0;
    ctx.current_phase = .lock;
    ctx.executing = true;

    const result = executor_mod.execute(&ctx) catch false;
    try std.testing.expect(!result);
}

test "capability error codes are defined" {
    try std.testing.expectEqual(@as(u8, 38), @intFromEnum(errors.KernelError.capability_script_failed));
    try std.testing.expectEqual(@as(u8, 39), @intFromEnum(errors.KernelError.capability_not_linear));
    try std.testing.expectEqual(@as(u8, 40), @intFromEnum(errors.KernelError.checksig_failed));
}

// ── E-P5.7: Capability context stack push order ──
// kernel_verify_capability pushes 4 values: current_time, domain_flag, cap_type, owner_pubkey
// (bottom to top). Verify scripts can access them in the correct order.

test "capability context values are pushed in correct order" {
    // Simulate the push order from kernel_verify_capability:
    // Push order (bottom→top): current_time, domain_flag, cap_type, owner_pubkey
    // So stack[0] = owner_pubkey (top), stack[1] = cap_type, stack[2] = domain_flag, stack[3] = current_time
    var pda: pda_mod.PDA = undefined;
    pda.initInPlace(1000);

    // Push values in same order as kernel_verify_capability (main.zig)
    // 1. current_time (4 bytes LE)
    var time_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &time_bytes, 1700000000, .little); // Unix timestamp
    pda.spush(&time_bytes) catch unreachable;

    // 2. domain_flag (4 bytes LE)
    var flag_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &flag_bytes, 42, .little);
    pda.spush(&flag_bytes) catch unreachable;

    // 3. cap_type (1 byte)
    const cap_byte = [_]u8{3}; // capability type 3
    pda.spush(&cap_byte) catch unreachable;

    // 4. owner_pubkey (33 bytes, compressed)
    var fake_pk: [33]u8 = undefined;
    fake_pk[0] = 0x02; // compressed prefix
    @memset(fake_pk[1..], 0xAB);
    pda.spush(&fake_pk) catch unreachable;

    // Verify stack depth = 4
    try std.testing.expectEqual(@as(u32, 4), pda.sdepth());

    // Top of stack (index 0) should be owner_pubkey (33 bytes)
    const top = pda.speekAt(0) catch unreachable;
    try std.testing.expectEqual(@as(u32, 33), top.len);
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);

    // Index 1 should be cap_type (1 byte)
    const cap = pda.speekAt(1) catch unreachable;
    try std.testing.expectEqual(@as(u32, 1), cap.len);
    try std.testing.expectEqual(@as(u8, 3), cap.data[0]);

    // Index 2 should be domain_flag (4 bytes)
    const flag = pda.speekAt(2) catch unreachable;
    try std.testing.expectEqual(@as(u32, 4), flag.len);
    const flag_val = std.mem.readInt(u32, flag.data[0..4], .little);
    try std.testing.expectEqual(@as(u32, 42), flag_val);

    // Index 3 should be current_time (4 bytes)
    const time_entry = pda.speekAt(3) catch unreachable;
    try std.testing.expectEqual(@as(u32, 4), time_entry.len);
    const time_val = std.mem.readInt(u32, time_entry.data[0..4], .little);
    try std.testing.expectEqual(@as(u32, 1700000000), time_val);
}

test "capability script can read context values via OP_PICK" {
    // Test that a locking script can read pushed context using OP_PICK
    // Stack before script runs: [current_time, domain_flag, cap_type, owner_pubkey]
    var pda: pda_mod.PDA = undefined;
    pda.initInPlace(1000);

    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);

    var ctx = executor_mod.ExecutionContext.init(&pda, &arena);

    // Push context values (same order as kernel_verify_capability)
    var time_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &time_bytes, 100, .little);
    pda.spush(&time_bytes) catch unreachable;

    var flag_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &flag_bytes, 1, .little);
    pda.spush(&flag_bytes) catch unreachable;

    const cap_byte = [_]u8{2};
    pda.spush(&cap_byte) catch unreachable;

    var fake_pk: [33]u8 = undefined;
    fake_pk[0] = 0x02;
    @memset(fake_pk[1..], 0xCC);
    pda.spush(&fake_pk) catch unreachable;

    // Script: pick cap_type (index 1), drop it, OP_TRUE
    // OP_1 (0x51) OP_PICK (0x79) OP_DROP (0x75) OP_TRUE (0x51)
    const lock_script = [_]u8{ 0x51, 0x79, 0x75, 0x51 };
    ctx.loadScript(&lock_script) catch unreachable;
    ctx.pc = 0;
    ctx.current_phase = .lock;
    ctx.executing = true;

    const result = executor_mod.execute(&ctx) catch false;
    try std.testing.expect(result);
}

```
