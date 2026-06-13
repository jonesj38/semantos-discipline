---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/octave_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.965139+00:00
---

# core/cell-engine/tests/octave_conformance.zig

```zig
// Phase 6: Octave memory scaling conformance tests
// Tests T6.01-T6.06 (address space math), T6.20 (MFP cost scaling)
//
// Reference: PHASE-6-OCTAVE-MEMORY.md TDD Gate

const std = @import("std");
const octave = @import("octave");

// ── T6.01-T6.03: Cell size calculations ──

test "T6.01 cellSizeForOctave(.base) == 1024" {
    try std.testing.expectEqual(@as(u64, 1024), octave.cellSizeForOctave(.base));
}

test "T6.02 cellSizeForOctave(.kilo) == 1_048_576" {
    try std.testing.expectEqual(@as(u64, 1_048_576), octave.cellSizeForOctave(.kilo));
}

test "T6.03 cellSizeForOctave(.mega) == 1_073_741_824" {
    try std.testing.expectEqual(@as(u64, 1_073_741_824), octave.cellSizeForOctave(.mega));
}

// ── T6.04: Address space calculations ──

test "T6.04 addressSpaceForOctave(.base) == 1_048_576" {
    try std.testing.expectEqual(@as(u64, 1_048_576), octave.addressSpaceForOctave(.base));
}

// ── T6.05-T6.06: Bytes-to-cells conversion ──

test "T6.05 bytesToCellsAtOctave(10240, .base) == 10" {
    try std.testing.expectEqual(@as(u64, 10), octave.bytesToCellsAtOctave(10240, .base));
}

test "T6.06 bytesToCellsAtOctave(2_000_000, .kilo) == 2" {
    try std.testing.expectEqual(@as(u64, 2), octave.bytesToCellsAtOctave(2_000_000, .kilo));
}

// ── T6.20: MFP cost scaling ──

test "T6.20 MFP cost: octave 0 = 1 sat, octave 1 = 1000 sat, octave 2 = 1_000_000 sat" {
    try std.testing.expectEqual(@as(u64, 1), octave.costSatsPerCell(.base));
    try std.testing.expectEqual(@as(u64, 1000), octave.costSatsPerCell(.kilo));
    try std.testing.expectEqual(@as(u64, 1_000_000), octave.costSatsPerCell(.mega));
    try std.testing.expectEqual(@as(u64, 1_000_000_000), octave.costSatsPerCell(.giga));
}

// ── Additional coverage ──

test "cellSizeForOctave(.giga) == 1_099_511_627_776" {
    try std.testing.expectEqual(@as(u64, 1_099_511_627_776), octave.cellSizeForOctave(.giga));
}

test "bytesToCellsAtOctave rounds up" {
    // 1 byte at base = 1 cell
    try std.testing.expectEqual(@as(u64, 1), octave.bytesToCellsAtOctave(1, .base));
    // 1024 bytes at base = exactly 1 cell
    try std.testing.expectEqual(@as(u64, 1), octave.bytesToCellsAtOctave(1024, .base));
    // 1025 bytes at base = 2 cells
    try std.testing.expectEqual(@as(u64, 2), octave.bytesToCellsAtOctave(1025, .base));
}

test "minimumOctaveForSize routes correctly" {
    try std.testing.expectEqual(octave.Octave.base, octave.minimumOctaveForSize(768).?);
    try std.testing.expectEqual(octave.Octave.base, octave.minimumOctaveForSize(1024).?);
    try std.testing.expectEqual(octave.Octave.kilo, octave.minimumOctaveForSize(1025).?);
    try std.testing.expectEqual(octave.Octave.kilo, octave.minimumOctaveForSize(1_048_576).?);
    try std.testing.expectEqual(octave.Octave.mega, octave.minimumOctaveForSize(1_048_577).?);
}

test "OctaveAddress isValid" {
    const valid = octave.OctaveAddress{ .octave = .kilo, .slot = 42, .offset = 1024 };
    try std.testing.expect(valid.isValid());
    const invalid = octave.OctaveAddress{ .octave = .kilo, .slot = 1024, .offset = 0 };
    try std.testing.expect(!invalid.isValid());
}

test "SlotMeta init is zeroed" {
    const meta = octave.SlotMeta.init();
    try std.testing.expectEqual(octave.SlotState.free, meta.state);
    try std.testing.expectEqual(@as(u8, 0), meta.linearity);
    try std.testing.expectEqual(@as(u16, 0), meta.ref_count);
}

```
