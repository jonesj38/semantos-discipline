---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/oddjobz_domain_gate_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.181553+00:00
---

# runtime/semantos-brain/tests/oddjobz_domain_gate_conformance.zig

```zig
//! SW3.oddjobz (Wave Cap-Substrate) — K3 end-to-end for the oddjobz
//! cartridge, against the BRAIN-executed opcode + the REAL mint path.
//!
//! Oracle: proofs/lean/Semantos/Theorems/DomainIsolationK3.lean.
//! PRD: docs/prd/CAPABILITY-SUBSTRATE-WIREIN.md SW3.<cartridge>.
//! Ownership: docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md (RATIFIED) —
//!   oddjobz is first-party; owner sign-off = the key its (self-issued)
//!   license UTXO is P2PK-locked to, i.e. brain-core / Todd. Recorded
//!   in the SW3.oddjobz PR.
//!
//! SW3.<cartridge> acceptance, exercised here against the shipped impl:
//!   (a) a gated transition on a wrong-domain cell is rejected
//!       end-to-end with domain_flag_mismatch (failure-atomic);
//!   (b) that cartridge's minted cell carries its registered page flag.
//!
//! This is NOT a re-implementation: every cell below is produced by the
//! real `substrate_entity.encodeEntity` (the actual oddjobz store mint
//! path) and every gate decision is the real brain-side
//! `domain_gate.checkDomainFlag`, which executes the genuine
//! `plexus.executePlexus(&p, 0xC6)` inside the brain link graph
//! (wired by SW3.0). "Proven but unwired" would fail PRD §0.2 — this
//! exercises mint→brain-opcode end-to-end.

const std = @import("std");
const se = @import("substrate_entity");
const domain_gate = @import("domain_gate");

/// The 7 canonical oddjobz entity specs — all registered on the
/// ODDJOBZ capability page (0x000101xx, R-3 page-registry green).
/// (C4 PR-J6/J7: SPEC_LEAD removed — a lead is a job.v2 in state "lead".)
fn oddjobzSpecs() [7]se.EntityTypeSpec {
    return .{
        se.SPEC_CUSTOMER, se.SPEC_VISIT, se.SPEC_QUOTE,   se.SPEC_INVOICE,
        se.SPEC_ATTACHMENT, se.SPEC_JOB,  se.SPEC_SITE,
    };
}

fn mint(spec: se.EntityTypeSpec) ![se.CELL_BYTES]u8 {
    return se.encodeEntity(.{
        .spec = spec,
        .linearity = .linear,
        .owner_id = [_]u8{0xAB} ** 16,
        .payload_json = "{\"k\":\"v\"}",
        .timestamp_ns = 1_000_000_000, // deterministic
    });
}

// ── (b) minted cell carries its registered ODDJOBZ-page flag ─────────

test "SW3.oddjobz (b): every oddjobz spec mints a cell on the ODDJOBZ page" {
    for (oddjobzSpecs()) |spec| {
        const cell = try mint(spec);
        // offset-24 (the kernel domain_flag the opcode reads) == the
        // spec's registered flag, and it sits on the ODDJOBZ page.
        const flag = std.mem.readInt(u32, cell[24..28], .little);
        try std.testing.expectEqual(spec.domain_flag, flag);
        try std.testing.expect(flag >= 0x00010100 and flag <= 0x000101FF);
    }
}

// ── K3b / (a)-positive: brain opcode ACCEPTS the correctly-minted cell ─

test "SW3.oddjobz K3b: brain-executed 0xC6 accepts each real oddjobz cell" {
    for (oddjobzSpecs()) |spec| {
        const cell = try mint(spec);
        const o = try domain_gate.evaluate(&cell, spec.domain_flag);
        try std.testing.expect(o.matched);
        try std.testing.expect(o.top_truthy); // TRUE pushed
        try std.testing.expectEqual(o.depth_before, o.depth_after);
        // High-level production gate authorizes (no error).
        try domain_gate.checkDomainFlag(&cell, spec.domain_flag);
    }
}

// ── K3a / (a): wrong-domain oddjobz cell rejected end-to-end ─────────

test "SW3.oddjobz K3a: cross-oddjobz-tag domain is rejected (failure-atomic)" {
    const specs = oddjobzSpecs();
    for (specs, 0..) |spec, i| {
        const cell = try mint(spec);
        // Expect a *different* oddjobz spec's flag → mismatch.
        const other = specs[(i + 1) % specs.len];
        if (other.domain_flag == spec.domain_flag) continue;
        const o = try domain_gate.evaluate(&cell, other.domain_flag);
        try std.testing.expect(!o.matched);
        try std.testing.expectEqual(o.depth_before, o.depth_after); // failure-atomic
        try std.testing.expectError(
            error.domain_flag_mismatch,
            domain_gate.checkDomainFlag(&cell, other.domain_flag),
        );
    }
}

test "SW3.oddjobz K3a: a non-oddjobz page (carpenter/musician) is rejected" {
    const foreign = [_]u32{ 0x000102, 0x000103, 0x00010400, 0x0001FE01 };
    const cell = try mint(se.SPEC_JOB); // ODDJOBZ-page cell
    for (foreign) |bad| {
        const o = try domain_gate.evaluate(&cell, bad);
        try std.testing.expect(!o.matched);
        try std.testing.expectEqual(o.depth_before, o.depth_after);
        try std.testing.expectError(
            error.domain_flag_mismatch,
            domain_gate.checkDomainFlag(&cell, bad),
        );
    }
}

// ── K3c: totality over the full oddjobz spec × spec matrix ──────────

test "SW3.oddjobz K3c: every (minted, expected) pair yields exactly one outcome" {
    const specs = oddjobzSpecs();
    for (specs) |minted| {
        const cell = try mint(minted);
        for (specs) |expected| {
            const o = try domain_gate.evaluate(&cell, expected.domain_flag);
            if (minted.domain_flag == expected.domain_flag) {
                try std.testing.expect(o.matched);
                try std.testing.expect(o.top_truthy);
            } else {
                try std.testing.expect(!o.matched);
                try std.testing.expectEqual(o.depth_before, o.depth_after);
            }
        }
    }
}

```
