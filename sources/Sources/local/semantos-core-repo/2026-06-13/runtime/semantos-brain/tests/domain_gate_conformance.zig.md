---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/domain_gate_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.199706+00:00
---

# runtime/semantos-brain/tests/domain_gate_conformance.zig

```zig
//! SW3.0 — brain-level K3 conformance (Wave Cap-Substrate).
//!
//! Oracle: proofs/lean/Semantos/Theorems/DomainIsolationK3.lean.
//!
//! These tests discharge K3 **against the brain-executed opcode**: every
//! assertion below runs through `domain_gate.evaluate` /
//! `domain_gate.checkDomainFlag`, which builds a real `pda_mod.PDA` and
//! invokes the genuine `plexus.executePlexus(&p, 0xC6)` from inside the
//! semantos-brain link graph (not the cell-engine test binary).
//!
//! K3 statement, as DomainIsolationK3.lean proves it:
//!   K3a  actual ≠ expected ⇒ error.domain_flag_mismatch, stack unchanged
//!        (failure-atomic).
//!   K3b  actual = expected ⇒ TRUE pushed (expected flag dropped, TRUE on
//!        top — net depth unchanged, top truthy).
//!   K3c  totality: the opcode terminates with exactly one of the two
//!        outcomes for every input (no stuck states); also covers the
//!        stack-underflow guard.
//!
//! "Proven but unwired" fails the PRD §0.2 gate — this suite is the
//! executable that proves the brain executes the opcode the theorem
//! describes.

const std = @import("std");
const domain_gate = @import("domain_gate");
const pda_mod = @import("pda");

/// Build a kernel cell with offset-24 `domain_flag` (fixed 4-byte LE,
/// the layout linearity.getDomainFlag reads) + a valid linearity_class.
fn makeCell(domain_flag: u32) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[16..20], 1, .little); // linearity_class = LINEAR
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    return cell;
}

// ── K3b: match ⇒ TRUE pushed ──────────────────────────────────────────

test "K3b: brain-executed 0xC6 — matching domain_flag pushes TRUE" {
    const cell = makeCell(0x000101); // oddjobz
    const o = try domain_gate.evaluate(&cell, 0x000101);
    try std.testing.expect(o.matched);
    // expected flag dropped, TRUE pushed ⇒ net stack depth unchanged.
    try std.testing.expectEqual(o.depth_before, o.depth_after);
    try std.testing.expect(o.top_truthy);
    // High-level gate authorizes (no error).
    try domain_gate.checkDomainFlag(&cell, 0x000101);
}

test "K3b: brain-executed 0xC6 — match holds for an extended-range flag" {
    // 0x0001FE01 — exercises a >1-byte sign-magnitude LE encoding path
    // (the SUBSTRATE_SCHEMA-relocated range from B-1), proving the
    // brain seam's flag encoding matches cellToU32's decode.
    const cell = makeCell(0x0001FE01);
    const o = try domain_gate.evaluate(&cell, 0x0001FE01);
    try std.testing.expect(o.matched);
    try std.testing.expect(o.top_truthy);
}

// ── K3a: mismatch ⇒ domain_flag_mismatch, failure-atomic ──────────────

test "K3a: brain-executed 0xC6 — wrong domain_flag is rejected" {
    const cell = makeCell(0x000101); // oddjobz cell
    const o = try domain_gate.evaluate(&cell, 0x000102); // carpenter expected
    try std.testing.expect(!o.matched);
    try std.testing.expectError(
        error.domain_flag_mismatch,
        domain_gate.checkDomainFlag(&cell, 0x000102),
    );
}

test "K3a: brain-executed 0xC6 — mismatch is failure-atomic (stack unchanged)" {
    const cell = makeCell(0x000103); // musician cell
    const o = try domain_gate.evaluate(&cell, 0x000101); // wrong
    try std.testing.expect(!o.matched);
    // The opcode mutated nothing before erroring: depth identical.
    try std.testing.expectEqual(o.depth_before, o.depth_after);
    try std.testing.expect(!o.top_truthy);
}

// ── K3c: totality / no stuck states ───────────────────────────────────

test "K3c: brain-executed 0xC6 — every flag pair yields exactly one outcome" {
    const flags = [_]u32{ 0x000101, 0x000102, 0x000103, 1, 10, 0x0001FE01 };
    for (flags) |actual| {
        const cell = makeCell(actual);
        for (flags) |expected| {
            const o = try domain_gate.evaluate(&cell, expected);
            if (actual == expected) {
                try std.testing.expect(o.matched);
                try std.testing.expect(o.top_truthy);
            } else {
                try std.testing.expect(!o.matched);
                try std.testing.expectEqual(o.depth_before, o.depth_after);
            }
        }
    }
}

test "K3c: brain seam rejects an undersized (non-kernel) cell buffer" {
    const tiny = [_]u8{0} ** 16;
    try std.testing.expectError(
        error.cell_too_small,
        domain_gate.evaluate(&tiny, 0x000101),
    );
}

```
