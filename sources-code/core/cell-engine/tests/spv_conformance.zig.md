---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/spv_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.968402+00:00
---

# core/cell-engine/tests/spv_conformance.zig

```zig
// Phase 5: SPV conformance tests
// BEEF version detection, parsing, BUMP verification.
// Tests structural validation including minimum-length checks (E-P5.6).

const std = @import("std");
const beef = @import("beef");

// ── Version detection tests ──

test "detectVersion: BEEF V1 magic with payload" {
    // 4-byte magic + at least 1 byte of structure (nBUMPs count)
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x01, 0x00 };
    try std.testing.expectEqual(beef.BeefVersion.v1, beef.detectVersion(&data));
}

test "detectVersion: BEEF V2 magic with payload" {
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x02, 0x00 };
    try std.testing.expectEqual(beef.BeefVersion.v2, beef.detectVersion(&data));
}

test "detectVersion: Atomic BEEF magic with payload" {
    const data = [_]u8{ 0x01, 0x01, 0x01, 0x01, 0x00 };
    try std.testing.expectEqual(beef.BeefVersion.atomic, beef.detectVersion(&data));
}

test "detectVersion: invalid magic" {
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0x00 };
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

test "detectVersion: too short" {
    const data = [_]u8{0xEF};
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

test "detectVersion: empty data" {
    const data = [_]u8{};
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

// ── E-P5.6: Magic-only data must be rejected (no structure after magic) ──

test "detectVersion: BEEF V1 magic-only (4 bytes) is invalid" {
    // Only magic bytes, no payload — must be rejected
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x01 };
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

test "detectVersion: BEEF V2 magic-only (4 bytes) is invalid" {
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x02 };
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

test "detectVersion: Atomic BEEF magic-only (4 bytes) is invalid" {
    const data = [_]u8{ 0x01, 0x01, 0x01, 0x01 };
    try std.testing.expectEqual(beef.BeefVersion.invalid, beef.detectVersion(&data));
}

// ── BEEF magic constant tests ──

test "BEEF V1 magic constant is correct" {
    try std.testing.expectEqual(@as(u32, 0x0100BEEF), beef.BEEF_V1_MAGIC);
}

test "BEEF V2 magic constant is correct" {
    try std.testing.expectEqual(@as(u32, 0x0200BEEF), beef.BEEF_V2_MAGIC);
}

test "Atomic BEEF magic constant is correct" {
    try std.testing.expectEqual(@as(u32, 0x01010101), beef.ATOMIC_BEEF_MAGIC);
}

```
