---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/action_cell_teachback_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.177035+00:00
---

# runtime/semantos-brain/tests/action_cell_teachback_test.zig

```zig
// M5.14 — Action-cell teachback tests.
//
// Test IDs:
//   M5.14-T-embed-extract-roundtrip : embedSirHash then extractSirHash → same bytes
//   M5.14-T-wrong-phase-error       : phase=0x01 → extractSirHash returns error.NotActionPhase
//   M5.14-T-has-sir-hash-true       : after embed, hasSirHash returns true
//   M5.14-T-has-sir-hash-false      : zeroed payload → hasSirHash returns false
//   M5.14-T-payload-too-short       : payload of 16 bytes → error.PayloadTooShort
//
// Run: zig build test-action-cell-teachback

const std = @import("std");
const teachback = @import("action_cell_teachback");

// ── M5.14-T-embed-extract-roundtrip ─────────────────────────────────────────
// embedSirHash followed by extractSirHash must return the exact same 32 bytes.

test "M5.14-T-embed-extract-roundtrip" {
    var payload = [_]u8{0} ** 768;

    const expected: [32]u8 = .{
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
    };

    try teachback.embedSirHash(teachback.PHASE_ACTION, &payload, &expected);
    const got = try teachback.extractSirHash(teachback.PHASE_ACTION, &payload);
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

// ── M5.14-T-wrong-phase-error ────────────────────────────────────────────────
// Passing a non-action phase (0x01) to extractSirHash must return NotActionPhase.

test "M5.14-T-wrong-phase-error" {
    const payload = [_]u8{0} ** 768;
    const result = teachback.extractSirHash(0x01, &payload);
    try std.testing.expectError(error.NotActionPhase, result);
}

// ── M5.14-T-has-sir-hash-true ────────────────────────────────────────────────
// After embedding a non-zero hash, hasSirHash must return true.

test "M5.14-T-has-sir-hash-true" {
    var payload = [_]u8{0} ** 768;

    const hash: [32]u8 = .{0xab} ** 32;
    try teachback.embedSirHash(teachback.PHASE_ACTION, &payload, &hash);

    const result = teachback.hasSirHash(teachback.PHASE_ACTION, &payload);
    try std.testing.expect(result == true);
}

// ── M5.14-T-has-sir-hash-false ───────────────────────────────────────────────
// A zeroed payload (all 32 hash bytes = 0x00) means no hash is present.

test "M5.14-T-has-sir-hash-false" {
    const payload = [_]u8{0} ** 768;
    const result = teachback.hasSirHash(teachback.PHASE_ACTION, &payload);
    try std.testing.expect(result == false);
}

// ── M5.14-T-payload-too-short ────────────────────────────────────────────────
// A payload shorter than 32 bytes must return PayloadTooShort.

test "M5.14-T-payload-too-short" {
    const payload = [_]u8{0} ** 16;
    const result = teachback.extractSirHash(teachback.PHASE_ACTION, &payload);
    try std.testing.expectError(error.PayloadTooShort, result);
}

```
