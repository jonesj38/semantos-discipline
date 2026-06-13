---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/smoke_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.960866+00:00
---

# core/cell-engine/tests/smoke_test.zig

```zig
const std = @import("std");
const constants = @import("constants");

// From FORTH:SEMOBJ lines 73-75
test "CELL_SIZE is 1024" {
    try std.testing.expectEqual(@as(u32, 1024), constants.CELL_SIZE);
}
test "HEADER_SIZE is 256" {
    try std.testing.expectEqual(@as(u32, 256), constants.HEADER_SIZE);
}
test "PAYLOAD_SIZE is 768" {
    try std.testing.expectEqual(@as(u32, 768), constants.PAYLOAD_SIZE);
}
test "CELL_SIZE = HEADER_SIZE + PAYLOAD_SIZE" {
    try std.testing.expectEqual(constants.CELL_SIZE, constants.HEADER_SIZE + constants.PAYLOAD_SIZE);
}

// From FORTH:SEMOBJ lines 78-81
test "MAGIC_1 is 0xDEADBEEF" {
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), constants.MAGIC_1);
}
test "MAGIC_4 is 0x42424242" {
    try std.testing.expectEqual(@as(u32, 0x42424242), constants.MAGIC_4);
}

// From FORTH:SEMOBJ lines 23-26
test "LINEARITY_LINEAR is 1" {
    try std.testing.expectEqual(@as(u8, 1), constants.LINEARITY_LINEAR);
}

// From PACKER:TYPE-REGISTRY — typeHash at offset 30
test "HEADER_OFFSET_TYPE_HASH is 30" {
    try std.testing.expectEqual(@as(u16, 30), constants.HEADER_OFFSET_TYPE_HASH);
}

// From FORTH:2PDA lines 16-18
test "MAIN_STACK_CELLS is 1024" {
    try std.testing.expectEqual(@as(u32, 1024), constants.MAIN_STACK_CELLS);
}
test "AUX_STACK_CELLS is 256" {
    try std.testing.expectEqual(@as(u32, 256), constants.AUX_STACK_CELLS);
}

// From FORTH:MACROS opcode ranges
test "Craig macro range 0xB0-0xBF" {
    try std.testing.expectEqual(@as(u8, 0xB0), constants.OPCODE_CRAIG_MACRO_MIN);
    try std.testing.expectEqual(@as(u8, 0xBF), constants.OPCODE_CRAIG_MACRO_MAX);
}
test "Plexus opcode range 0xC0-0xCF" {
    try std.testing.expectEqual(@as(u8, 0xC0), constants.OPCODE_PLEXUS_MIN);
    try std.testing.expectEqual(@as(u8, 0xCF), constants.OPCODE_PLEXUS_MAX);
}

```
