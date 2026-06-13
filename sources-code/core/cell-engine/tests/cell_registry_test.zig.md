---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/cell_registry_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.963697+00:00
---

# core/cell-engine/tests/cell_registry_test.zig

```zig
// M4.6 — CellRegistry dual-addressing conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the contract for CAS+location dual addressing.
//
// Contract:
//   - lookupByHash(type_hash) and lookupByLocation(addr) return consistent results.
//   - Idempotent registration: same (hash, addr) pair registered twice → no error, count == 1.
//   - HashCollision: same hash registered at a different location → error.HashCollision.
//   - SlotConflict: same location registered with a different hash → error.SlotConflict.
//   - Unregister: removes both index entries; count drops to 0.
//
// Test IDs:
//   M4.6-T-register-and-lookup-hash      — register then lookupByHash returns correct addr
//   M4.6-T-register-and-lookup-location  — register then lookupByLocation returns correct hash
//   M4.6-T-idempotent                    — double register same pair → no error; count == 1
//   M4.6-T-hash-collision                — same hash, different addr → error.HashCollision
//   M4.6-T-slot-conflict                 — same addr, different hash → error.SlotConflict
//   M4.6-T-unregister                    — register then unregister → count == 0; lookups null
//
// Run: zig build test-cell-registry

const std = @import("std");
const cell_registry = @import("cell_registry");
const CellRegistry = cell_registry.CellRegistry;
const octave = @import("octave");
const OctaveAddress = octave.OctaveAddress;
const Octave = octave.Octave;

// ── Helpers ───────────────────────────────────────────────────────────────

fn makeHash(byte: u8) [32]u8 {
    var h = [_]u8{0} ** 32;
    h[0] = byte;
    return h;
}

fn makeAddr(oct: Octave, slot: u16) OctaveAddress {
    return .{ .octave = oct, .slot = slot, .offset = 0 };
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "M4.6-T-register-and-lookup-hash" {
    // register (type_hash_A, addr_oct1_slot5); lookupByHash(type_hash_A) == addr_oct1_slot5
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0xAA);
    const addr = makeAddr(.kilo, 5);

    try reg.register(&hash_a, addr);

    const result = reg.lookupByHash(&hash_a);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(addr.octave, result.?.octave);
    try std.testing.expectEqual(addr.slot, result.?.slot);
}

test "M4.6-T-register-and-lookup-location" {
    // register (type_hash_A, addr_oct1_slot5); lookupByLocation(addr_oct1_slot5) == type_hash_A
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0xBB);
    const addr = makeAddr(.kilo, 5);

    try reg.register(&hash_a, addr);

    const result = reg.lookupByLocation(addr);
    try std.testing.expect(result != null);
    try std.testing.expectEqualSlices(u8, &hash_a, &result.?);
}

test "M4.6-T-idempotent" {
    // register same (hash, addr) twice → no error; count() == 1
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0xCC);
    const addr = makeAddr(.base, 42);

    try reg.register(&hash_a, addr);
    try reg.register(&hash_a, addr);

    try std.testing.expectEqual(@as(usize, 1), reg.count());
}

test "M4.6-T-hash-collision" {
    // register hash_A at addr1, then hash_A at different addr2 → error.HashCollision
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0xDD);
    const addr1 = makeAddr(.base, 10);
    const addr2 = makeAddr(.base, 20);

    try reg.register(&hash_a, addr1);
    const result = reg.register(&hash_a, addr2);
    try std.testing.expectError(error.HashCollision, result);
}

test "M4.6-T-slot-conflict" {
    // register hash_A at addr1, then hash_B at same addr1 → error.SlotConflict
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0xEE);
    const hash_b = makeHash(0xFF);
    const addr1 = makeAddr(.mega, 7);

    try reg.register(&hash_a, addr1);
    const result = reg.register(&hash_b, addr1);
    try std.testing.expectError(error.SlotConflict, result);
}

test "M4.6-T-unregister" {
    // register, unregister → count()==0; both lookups return null
    var reg = CellRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const hash_a = makeHash(0x11);
    const addr = makeAddr(.giga, 100);

    try reg.register(&hash_a, addr);
    try std.testing.expectEqual(@as(usize, 1), reg.count());

    const removed = reg.unregister(&hash_a);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 0), reg.count());

    try std.testing.expect(reg.lookupByHash(&hash_a) == null);
    try std.testing.expect(reg.lookupByLocation(addr) == null);
}

```
