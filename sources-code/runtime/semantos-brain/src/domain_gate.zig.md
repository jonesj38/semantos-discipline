---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/domain_gate.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.240227+00:00
---

# runtime/semantos-brain/src/domain_gate.zig

```zig
//! SW3.0 — brain-side domain-isolation gate (Wave Cap-Substrate).
//!
//! Reference: docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md SW3.0 (keystone);
//! oracle docs/.../DomainIsolationK3.lean.
//!
//! This module routes a cell transition through the **real** cell-engine
//! `OP_CHECKDOMAINFLAG` (0xC6) opcode, executed from **inside the
//! semantos-brain link graph** — not the cell-engine test binary.  Before
//! SW3.0, K3 (DomainIsolationK3.lean) was discharged only against the
//! opcode as run by `core/cell-engine/tests/plexus_conformance.zig`; the
//! brain never executed it (PRD §0 headline gap).  This seam makes the
//! theorem load-bearing against the *brain-executed* opcode.
//!
//! Discipline (PRD §0.2): no functional stubbing of the opcode — we build
//! a real `pda_mod.PDA`, push the candidate cell + expected domain flag
//! using the canonical sign-magnitude LE encoding (`i64ToCell`, the exact
//! decode `cellToU32` in plexus.zig performs), and invoke the genuine
//! `plexus.executePlexus(&p, 0xC6)`.  Failure-atomicity is a property of
//! the opcode itself; this module observes and re-exposes it.

const std = @import("std");
const pda_mod = @import("pda");
const plexus = @import("plexus");

/// Errors surfaced by the brain domain gate.
pub const DomainGateError = error{
    /// offset-24 domain_flag of the cell != expected_flag (the K3a
    /// rejection path; the underlying opcode returns
    /// error.domain_flag_mismatch and leaves the VM stack unchanged).
    domain_flag_mismatch,
    /// The supplied cell buffer is shorter than a kernel cell.
    cell_too_small,
    /// PDA stack push failed (capacity/encoding) before the opcode ran.
    gate_setup_failed,
};

/// Observable outcome of running the real OP_CHECKDOMAINFLAG over a
/// transition.  `matched` is the K3 predicate; the depth/top fields let
/// a conformance test assert the opcode's stack postconditions
/// (TRUE-pushed on match; failure-atomic / stack-unchanged on mismatch)
/// against the brain-executed opcode.
pub const GateOutcome = struct {
    matched: bool,
    depth_before: u32,
    depth_after: u32,
    /// Truthiness of the new stack top after a *matched* run.  Undefined
    /// (false) when !matched, since the opcode is failure-atomic and
    /// pushes nothing.
    top_truthy: bool,
};

fn pushExpectedFlag(p: *pda_mod.PDA, expected_flag: u32) !void {
    // Encode exactly as cellToU32/cellToI64 in plexus.zig decodes:
    // minimal sign-magnitude little-endian Bitcoin-Script number.
    var fbuf: pda_mod.Cell = undefined;
    const n = pda_mod.i64ToCell(@as(i64, @intCast(expected_flag)), &fbuf);
    if (n == 0) {
        // expected_flag == 0 → empty stack item (cellToU32(&[_]u8{}) == 0).
        try p.spush(&[_]u8{});
    } else {
        try p.spush(fbuf[0..n]);
    }
}

/// Run the genuine brain-executed OP_CHECKDOMAINFLAG over `cell_bytes`
/// against `expected_flag`.  Never returns an error for a *domain
/// mismatch* — instead reports it via `GateOutcome.matched == false`
/// together with the observed stack state, so a conformance test can
/// assert K3's full statement (match ⇒ TRUE pushed; mismatch ⇒
/// stack-unchanged / failure-atomic) against the real opcode.
pub fn evaluate(cell_bytes: []const u8, expected_flag: u32) DomainGateError!GateOutcome {
    if (cell_bytes.len < pda_mod.CELL_SIZE) return error.cell_too_small;

    var p = pda_mod.PDA.init(500_000);

    var cell: pda_mod.Cell = undefined;
    @memcpy(cell[0..pda_mod.CELL_SIZE], cell_bytes[0..pda_mod.CELL_SIZE]);
    p.spushCell(&cell, pda_mod.CELL_SIZE) catch return error.gate_setup_failed;
    pushExpectedFlag(&p, expected_flag) catch return error.gate_setup_failed;

    const depth_before = p.sdepth();

    plexus.executePlexus(&p, 0xC6) catch |e| switch (e) {
        // K3a: mismatch ⇒ opcode errors, stack left unchanged
        // (failure-atomicity is the opcode's own invariant — we
        // observe depth_after to let the test prove it held).
        error.domain_flag_mismatch => return GateOutcome{
            .matched = false,
            .depth_before = depth_before,
            .depth_after = p.sdepth(),
            .top_truthy = false,
        },
        // Any other plexus failure ⇒ deny (fail-closed); also report
        // as a non-match with the observed depth.
        else => return GateOutcome{
            .matched = false,
            .depth_before = depth_before,
            .depth_after = p.sdepth(),
            .top_truthy = false,
        },
    };

    // K3b: match ⇒ opcode dropped expected flag and pushed TRUE.
    const depth_after = p.sdepth();
    var top_truthy = false;
    if (depth_after >= 1) {
        const top = p.speekAt(0) catch return error.gate_setup_failed;
        top_truthy = pda_mod.isTruthy(top.data, top.len);
    }
    return GateOutcome{
        .matched = true,
        .depth_before = depth_before,
        .depth_after = depth_after,
        .top_truthy = top_truthy,
    };
}

/// Production gate: authorize a transition iff the cell's offset-24
/// domain_flag matches `expected_flag`, by executing the real
/// brain-side OP_CHECKDOMAINFLAG.  Denies (returns
/// `error.domain_flag_mismatch`) on any non-match — the load-bearing
/// call site SW3.<cartridge> mint paths route through.
pub fn checkDomainFlag(cell_bytes: []const u8, expected_flag: u32) DomainGateError!void {
    const outcome = try evaluate(cell_bytes, expected_flag);
    if (!outcome.matched) return error.domain_flag_mismatch;
}

// ─────────────────────────────────────────────────────────────────────
// Inline unit tests — minimal smoke (full K3 conformance lives in
// tests/domain_gate_conformance.zig so it can be run as a named suite).
// ─────────────────────────────────────────────────────────────────────

fn makeCell(domain_flag: u32) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    // offset-24 domain_flag, fixed 4-byte LE — the kernel layout
    // linearity.getDomainFlag reads.
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    std.mem.writeInt(u32, cell[16..20], 1, .little); // linearity_class
    return cell;
}

test "domain_gate: matching flag ⇒ matched + TRUE pushed (brain-executed 0xC6)" {
    const cell = makeCell(257); // 0x000101 oddjobz
    const o = try evaluate(&cell, 257);
    try std.testing.expect(o.matched);
    try std.testing.expectEqual(o.depth_before, o.depth_after); // dropped flag, pushed TRUE
    try std.testing.expect(o.top_truthy);
}

test "domain_gate: mismatched flag ⇒ deny + failure-atomic (stack unchanged)" {
    const cell = makeCell(257);
    const o = try evaluate(&cell, 258); // 0x000102 carpenter — wrong
    try std.testing.expect(!o.matched);
    try std.testing.expectEqual(o.depth_before, o.depth_after); // failure-atomic
    try std.testing.expectError(error.domain_flag_mismatch, checkDomainFlag(&cell, 258));
}

```
