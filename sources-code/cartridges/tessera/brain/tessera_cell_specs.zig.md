---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_cell_specs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.635869+00:00
---

# cartridges/tessera/brain/tessera_cell_specs.zig

```zig
// tessera_cell_specs — tessera's entity-type SPECs for the generic
// cell-mint path (P3b).
//
// Design: docs/design/UNIVERSAL-CARTRIDGE-BOOT.md §8.
//
// P3a made `substrate_entity.specByTag` registry-backed (built-in
// oddjobz switch first, then a boot-populated registry). This file is
// tessera's contribution: the 10 `EntityTypeSpec`s for the
// `tessera_cells` types, registered ONCE at brain boot via
// `cartridge_boot`'s registerCells pass (the same out-of-src loader
// that registers walkers). Once registered, a tessera cell can be
// minted through the existing `entity.encode` path (octave escalation
// for >768 B payloads is already the default — no kernel change).
//
// Greenfield: this lives under cartridges/tessera/ (never brain-core
// src/). It imports the substrate `EntityTypeSpec` type + the generic
// `registerSpec` — that is adapter consumption, exactly like
// tessera_walkers importing `verb_dispatcher`.
//
// CANON NOTE (reviewable): the per-type `tag`, `how_slug`, and
// `inst_path` below are the *proposed* tessera type-hash triple canon,
// following the oddjobz convention (`how` = the speech act,
// `inst.<domain>.<thing>.vN`) and TESSERA-CARTRIDGE.md §3 vocabulary.
// `domain_flag` is NOT authored — it is the content-addressed,
// sovereign-tier flag `tessera_cells.domainFlag` already computes and
// tests assert distinct. Tags are allocated on the reserved tessera
// page (constants.json `TESSERA_PAGE` = 0x00010400) at the +0x10 block
// (0x00010410..0x00010419) — above the hat byte range, mirroring the
// cartridge.json capability-flag allocation note; collision-free vs
// oddjobz's small built-in tags (0x01..0x09).

const std = @import("std");
const substrate_entity = @import("substrate_entity");
const tessera_cells = @import("tessera_cells");

pub const EntityTypeSpec = substrate_entity.EntityTypeSpec;

/// First tessera cell-type tag. Index i in `tessera_cells.ALL` →
/// TESSERA_CELL_TAG_BASE + i.
pub const TESSERA_CELL_TAG_BASE: u32 = 0x00010410;

/// The authored type-hash triple (how_slug, inst_path) per cell name.
/// type_path = the cell name itself; domain_flag is derived.
const Triple = struct {
    name: []const u8,
    how_slug: []const u8,
    inst_path: []const u8,
};

const TRIPLES = [_]Triple{
    .{ .name = "tessera.grape-lot", .how_slug = "harvest", .inst_path = "inst.origin.grape-lot.v1" },
    .{ .name = "tessera.barrel", .how_slug = "rack", .inst_path = "inst.vessel.barrel.v1" },
    .{ .name = "tessera.bottle", .how_slug = "bottle", .inst_path = "inst.unit.bottle.v1" },
    .{ .name = "tessera.case", .how_slug = "assemble", .inst_path = "inst.pack.case.v1" },
    .{ .name = "tessera.pallet", .how_slug = "palletize", .inst_path = "inst.pack.pallet.v1" },
    .{ .name = "tessera.shipment", .how_slug = "ship", .inst_path = "inst.transit.shipment.v1" },
    .{ .name = "tessera.care-event", .how_slug = "care-record", .inst_path = "inst.evidence.care-event.v1" },
    .{ .name = "tessera.scan-event", .how_slug = "scan", .inst_path = "inst.evidence.scan.v1" },
    .{ .name = "tessera.tamper-event", .how_slug = "tamper", .inst_path = "inst.seal.tamper.v1" },
    .{ .name = "tessera.tasting-note", .how_slug = "taste", .inst_path = "inst.note.tasting.v1" },
};

fn tripleFor(name: []const u8) ?Triple {
    for (TRIPLES) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

/// The EntityTypeSpec for cell-type index `i` in `tessera_cells.ALL`.
/// Pure/comptime-friendly: no allocation, slices are static.
pub fn specForIndex(i: usize) ?EntityTypeSpec {
    if (i >= tessera_cells.ALL.len) return null;
    const cell = tessera_cells.ALL[i];
    const tri = tripleFor(cell.name) orelse return null;
    return EntityTypeSpec{
        .tag = TESSERA_CELL_TAG_BASE + @as(u32, @intCast(i)),
        .type_path = cell.name,
        .how_slug = tri.how_slug,
        .inst_path = tri.inst_path,
        .domain_flag = tessera_cells.domainFlag(cell),
    };
}

/// Register every tessera cell-type SPEC into the substrate registry.
/// Idempotent (P3a `registerSpec` is idempotent for identical specs),
/// so a per-boot call is safe. Called by cartridge_boot's registerCells
/// pass under the same entitlement gate as walker registration.
pub fn registerAll() substrate_entity.SpecRegisterError!void {
    var i: usize = 0;
    while (i < tessera_cells.ALL.len) : (i += 1) {
        const spec = specForIndex(i) orelse return error.tag_collision;
        try substrate_entity.registerSpec(spec);
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "every tessera cell type has an authored triple + derived spec" {
    try testing.expectEqual(@as(usize, 10), tessera_cells.ALL.len);
    var i: usize = 0;
    while (i < tessera_cells.ALL.len) : (i += 1) {
        const s = specForIndex(i).?;
        try testing.expectEqual(TESSERA_CELL_TAG_BASE + @as(u32, @intCast(i)), s.tag);
        try testing.expectEqualStrings(tessera_cells.ALL[i].name, s.type_path);
        try testing.expect(s.how_slug.len > 0 and s.inst_path.len > 0);
        // domain_flag is the content-addressed sovereign flag, not 0.
        try testing.expectEqual(tessera_cells.domainFlag(tessera_cells.ALL[i]), s.domain_flag);
        try testing.expect(s.domain_flag >= 0x00010000);
    }
}

test "registerAll registers all 10 + specByTag resolves them; idempotent" {
    substrate_entity.resetRegisteredSpecsForTest();
    defer substrate_entity.resetRegisteredSpecsForTest();
    try registerAll();
    try registerAll(); // idempotent — identical re-register, no error
    var i: usize = 0;
    while (i < tessera_cells.ALL.len) : (i += 1) {
        const tag = TESSERA_CELL_TAG_BASE + @as(u32, @intCast(i));
        const got = substrate_entity.specByTag(tag).?;
        try testing.expectEqualStrings(tessera_cells.ALL[i].name, got.type_path);
    }
    // Built-in oddjobz tags still resolve via the switch (P3a invariant).
    try testing.expect(substrate_entity.specByTag(substrate_entity.TAG_JOB) != null);
}

test "tessera cell tags do not collide with oddjobz built-ins" {
    // oddjobz built-ins are 0x01..0x09; tessera is 0x000104xx — disjoint.
    var i: usize = 0;
    while (i < tessera_cells.ALL.len) : (i += 1) {
        const tag = TESSERA_CELL_TAG_BASE + @as(u32, @intCast(i));
        try testing.expect(tag > 0x0000FFFF);
    }
}

```
