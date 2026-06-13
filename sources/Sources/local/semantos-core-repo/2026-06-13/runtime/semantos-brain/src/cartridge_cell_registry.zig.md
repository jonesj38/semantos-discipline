---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cartridge_cell_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.232502+00:00
---

# runtime/semantos-brain/src/cartridge_cell_registry.zig

```zig
// BRAIN-GENERIC-MINT-VERB M1 — cartridge cellType registry.
//
// Maps the canonical 32-byte structured typeHash (|8|8|8|8|, per
// `core/cell-engine/src/type_hash.zig`) → cartridge cellType metadata
// the mint handler needs to gate, validate, persist, and fan out a cell:
//
//   - cartridgeId      → for capability lookup + NATS subject naming
//   - cellTypeName     → for audit/error surfaces
//   - linearity        → stamped into the cell header
//   - capabilityName   → checked against the caller's cert
//   - payloadSchemaRaw → opaque JSON; M2 parses for structural validation
//
// This is the Zig mirror of `cartridgeRegistry.cellTypeByHash` in
// `core/experience-cartridge/src/registry.ts` (T2.c).  Population happens
// once at brain boot via `register` (mirrors `substrate_entity.registerSpec`'s
// boot-time-only invariant; lookups after boot are read-only).
//
// Single-threaded brain reactor → file-scope bounded array, no mutex.
// Capacity sized for ~10 cartridges × ~30 cellTypes each.
//
// Why a separate registry from `substrate_entity.registered_specs`:
//   - substrate_entity is keyed by `tag` (u32) and `type_path` (legacy
//     dotted), using SHA256(`{type_path}:{how_slug}:{inst_path}`) for
//     typeHash. That is the PRE-typehash-canonical model.
//   - This registry is keyed by the STRUCTURED typeHash that
//     cartridge.json declares + `buildTypeHash` produces. The two
//     registries co-exist during the migration; legacy oddjobz cells
//     mint via cell_handler → substrate_entity, new cartridges
//     (betterment, future) mint via cells_mint_http → this registry.
//   - When the legacy substrate_entity specs are themselves expressed
//     as cartridge.json cellTypes[], the two registries merge into one.

const std = @import("std");

pub const TYPE_HASH_SIZE: usize = 32;

/// Max cartridges × cellTypes the brain can ever serve in one process.
/// 384 = 12 cartridges × 32 cellTypes — generous headroom over today's
/// 23 cellTypes in the betterment cartridge.
pub const MAX_REGISTERED_CELL_TYPES: usize = 384;

/// Per-cellType metadata the mint handler consults.
/// All `[]const u8` fields are static / boot-lifetime — populated from
/// strings that outlive the registry. No allocator owned here.
pub const CellTypeEntry = struct {
    /// 32-byte structured typeHash (key). Stamped into header offset 30.
    type_hash: [TYPE_HASH_SIZE]u8,
    /// Owning cartridge id, e.g. `"betterment"`, `"oddjobz"`.
    cartridge_id: []const u8,
    /// Cell type name (cartridge-local), e.g. `"practice.release"`.
    cell_type_name: []const u8,
    /// Linearity class stamped into the cell header.
    linearity: Linearity,
    /// Capability the caller's cert must hold to mint this cellType
    /// (Q-mint-3 = B: per-cartridge capability for v0.1.0; populated from
    /// the cartridge's declared `capabilities[0]` at boot). Empty string
    /// means "no capability check" (substrate cartridges only).
    capability_name: []const u8,
    /// Opaque cellType.payloadSchema JSON. Lifetime is the cartridge's
    /// loaded-manifest buffer. Parsed lazily by M2's structural validator.
    payload_schema_raw: ?[]const u8,
};

/// Mirror of `ManifestLinearity` in `core/experience-cartridge/src/types.ts`.
/// The enum integer values are NOT serialised; the linearity is encoded
/// elsewhere (cell header) by name resolution.
///
/// PR-C11-7e-2f — EPHEMERAL added. The TS `CellTypeLinearity` type has
/// always included EPHEMERAL (intent + result cell pairs are by
/// definition transient — they never persist as long-term state).
/// The Zig brain was rejecting EPHEMERAL cellTypes at boot, silently
/// dropping every operation-cell cartridge declared. Closing the
/// drift unblocks `bsv-anchor-bundle` (and every future operation-
/// cell cartridge).
///
/// Storage semantics: EPHEMERAL cells currently persist identically
/// to PERSISTENT cells (mapped to `LinearityClass.relevant` in the
/// cell-engine, which means multi-read + never consumed). True
/// ephemeral storage (e.g. auto-prune after caller reads the result)
/// is a substrate-side enhancement deferred to a separate PR.
pub const Linearity = enum {
    LINEAR,
    AFFINE,
    PERSISTENT,
    RELEVANT,
    DEBUG,
    EPHEMERAL,

    /// Parse from a manifest string. Returns null for unknown values
    /// (loader treats as fatal — typo in cartridge.json shouldn't
    /// silently flip linearity, same defensive posture as
    /// `substrate_entity.linearityFor`).
    pub fn fromManifestString(s: []const u8) ?Linearity {
        if (std.mem.eql(u8, s, "LINEAR")) return .LINEAR;
        if (std.mem.eql(u8, s, "AFFINE")) return .AFFINE;
        if (std.mem.eql(u8, s, "PERSISTENT")) return .PERSISTENT;
        if (std.mem.eql(u8, s, "RELEVANT")) return .RELEVANT;
        if (std.mem.eql(u8, s, "DEBUG")) return .DEBUG;
        if (std.mem.eql(u8, s, "EPHEMERAL")) return .EPHEMERAL;
        return null;
    }
};

pub const RegisterError = error{
    /// Same typeHash already registered with different metadata.  This
    /// is the cross-cartridge collision case the TS registry's
    /// `DUPLICATE_TYPE_HASH` error mirrors — never legitimate; signals
    /// either an accidental triple collision OR two cartridges
    /// declaring the same identity.
    type_hash_collision,
    /// Registry full — MAX_REGISTERED_CELL_TYPES would be exceeded.
    /// Bump the constant if a legitimately big deployment hits this.
    registry_full,
};

// ── File-scope bounded array — boot-write, runtime-read ──────────────

var entries: [MAX_REGISTERED_CELL_TYPES]CellTypeEntry = undefined;
var entry_count: usize = 0;

/// Register one cellType. Idempotent for an identical re-registration;
/// errors on collision or capacity overflow. Boot-only — calling after
/// the reactor serves a mint request risks data race with reads, even
/// though the simple bounded-array would not corrupt: lookups would
/// see partial state.
pub fn register(entry: CellTypeEntry) RegisterError!void {
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (std.mem.eql(u8, &entries[i].type_hash, &entry.type_hash)) {
            // Same hash — must match in EVERY field for idempotency.
            if (entryEql(entries[i], entry)) return;
            return error.type_hash_collision;
        }
    }
    if (entry_count >= MAX_REGISTERED_CELL_TYPES) return error.registry_full;
    entries[entry_count] = entry;
    entry_count += 1;
}

/// Look up a cellType by its 32-byte structured typeHash.
/// Linear scan — N is bounded by MAX_REGISTERED_CELL_TYPES, mint is not
/// hot-path enough to warrant a hash table at this scale.
pub fn lookup(type_hash: *const [TYPE_HASH_SIZE]u8) ?CellTypeEntry {
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (std.mem.eql(u8, &entries[i].type_hash, type_hash)) {
            return entries[i];
        }
    }
    return null;
}

/// Look up a cellType by `(cartridge_id, cell_type_name)`.
///
/// Used by the C11 PR4b cell-script handler dispatcher (`cells_mint_handler`)
/// to map handler `emits[]` cell-type name strings (e.g.
/// `"bsv.spv.verify.result"`) back to their canonical 32-byte typeHash so
/// it can enforce the emits allowlist when walking the post-execution
/// PDA stack.
///
/// Linear scan — same bound as `lookup`. Mint hot-path acceptable.
/// Returns null when no entry matches BOTH cartridge_id AND cell_type_name.
/// (cell_type_name alone isn't unique across the registry; two cartridges
/// can both declare e.g. `"intent"`.)
///
/// History: this helper first landed in PR-C11-7e-2e-2 for the WASM-handler
/// emits resolver, was removed in PR #760 PR1.5 when the WASM-handler stack
/// was excised and the function appeared dead, then re-introduced here when
/// the cell-script-handler dispatcher needed the same name→hash shape. The
/// lesson: dead-code claims need a "what about the replacement?" check
/// before deletion.
pub fn lookupByName(
    cartridge_id: []const u8,
    cell_type_name: []const u8,
) ?CellTypeEntry {
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (std.mem.eql(u8, entries[i].cartridge_id, cartridge_id) and
            std.mem.eql(u8, entries[i].cell_type_name, cell_type_name))
        {
            return entries[i];
        }
    }
    return null;
}

/// PR-8b-ix — global name lookup across ALL cartridges. Used by the
/// cell-script handler dispatcher's emits-allowlist walker as a
/// fall-through when `lookupByName(cartridge_id, ...)` misses. Handler
/// manifests can declare emits[] entries that name cellTypes from
/// OTHER cartridges (e.g. the MNCA handler in PR-8b-ii emits
/// `bsv.tx.sign.request`, which lives in the bsv-anchor-bundle
/// cartridge). Without this, cross-cartridge emits hit
/// `emit_outside_allowlist` even when the manifest declares them
/// correctly — the LOCKSCRIPT-CLEAVAGE.md design assumes substrate
/// cell types are universally addressable by their canonical name.
///
/// Linear scan — same bound as `lookup` / `lookupByName`. Returns the
/// first match; well-typed cartridges shouldn't reuse canonical names
/// across cartridges (the structured |8|8|8|8| typeHash on a triple
/// is the global identity, but the name is the human handle), so
/// ambiguity is a manifest bug worth surfacing in a follow-up
/// validator.
pub fn lookupByNameAnyCartridge(cell_type_name: []const u8) ?CellTypeEntry {
    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        if (std.mem.eql(u8, entries[i].cell_type_name, cell_type_name)) {
            return entries[i];
        }
    }
    return null;
}

/// Count of currently-registered cellTypes (introspection / boot logs).
pub fn count() usize {
    return entry_count;
}

/// Reset for tests. NEVER call in production.
pub fn resetForTest() void {
    entry_count = 0;
}

fn entryEql(a: CellTypeEntry, b: CellTypeEntry) bool {
    if (!std.mem.eql(u8, &a.type_hash, &b.type_hash)) return false;
    if (!std.mem.eql(u8, a.cartridge_id, b.cartridge_id)) return false;
    if (!std.mem.eql(u8, a.cell_type_name, b.cell_type_name)) return false;
    if (a.linearity != b.linearity) return false;
    if (!std.mem.eql(u8, a.capability_name, b.capability_name)) return false;
    const a_sch = a.payload_schema_raw orelse "";
    const b_sch = b.payload_schema_raw orelse "";
    if (!std.mem.eql(u8, a_sch, b_sch)) return false;
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure register/lookup semantics. Boot-wiring tests
// (reading cartridge.json + computing typeHash + populating registry)
// live with the boot module in a follow-up commit.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn fixture(byte: u8, cart: []const u8, name: []const u8) CellTypeEntry {
    var h: [TYPE_HASH_SIZE]u8 = undefined;
    @memset(&h, byte);
    return .{
        .type_hash = h,
        .cartridge_id = cart,
        .cell_type_name = name,
        .linearity = .LINEAR,
        .capability_name = "TEST_CAP",
        .payload_schema_raw = null,
    };
}

test "Linearity.fromManifestString accepts canonical values" {
    try testing.expectEqual(@as(?Linearity, .LINEAR), Linearity.fromManifestString("LINEAR"));
    try testing.expectEqual(@as(?Linearity, .AFFINE), Linearity.fromManifestString("AFFINE"));
    try testing.expectEqual(@as(?Linearity, .PERSISTENT), Linearity.fromManifestString("PERSISTENT"));
    try testing.expectEqual(@as(?Linearity, .RELEVANT), Linearity.fromManifestString("RELEVANT"));
    try testing.expectEqual(@as(?Linearity, .DEBUG), Linearity.fromManifestString("DEBUG"));
    try testing.expectEqual(@as(?Linearity, .EPHEMERAL), Linearity.fromManifestString("EPHEMERAL"));
}

test "Linearity.fromManifestString rejects junk" {
    try testing.expectEqual(@as(?Linearity, null), Linearity.fromManifestString("linear"));
    try testing.expectEqual(@as(?Linearity, null), Linearity.fromManifestString(""));
    try testing.expectEqual(@as(?Linearity, null), Linearity.fromManifestString("garbage"));
}

test "register + lookup round-trip" {
    resetForTest();
    const e = fixture(0xAA, "betterment", "practice.release");
    try register(e);
    try testing.expectEqual(@as(usize, 1), count());
    const found = lookup(&e.type_hash).?;
    try testing.expectEqualStrings("betterment", found.cartridge_id);
    try testing.expectEqualStrings("practice.release", found.cell_type_name);
    try testing.expectEqual(Linearity.LINEAR, found.linearity);
}

test "lookup returns null for unknown hash" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    var unknown: [TYPE_HASH_SIZE]u8 = undefined;
    @memset(&unknown, 0xBB);
    try testing.expectEqual(@as(?CellTypeEntry, null), lookup(&unknown));
}

test "register is idempotent for identical re-registration" {
    resetForTest();
    const e = fixture(0xAA, "betterment", "practice.release");
    try register(e);
    try register(e);
    try register(e);
    try testing.expectEqual(@as(usize, 1), count());
}

test "register collides on same hash + different cartridge" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    const clash = fixture(0xAA, "oddjobz", "practice.release");
    try testing.expectError(error.type_hash_collision, register(clash));
}

test "register collides on same hash + different cellType name" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    const clash = fixture(0xAA, "betterment", "practice.intention");
    try testing.expectError(error.type_hash_collision, register(clash));
}

test "register accepts distinct hashes in same cartridge" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    try register(fixture(0xBB, "betterment", "practice.intention"));
    try register(fixture(0xCC, "betterment", "practice.session"));
    try testing.expectEqual(@as(usize, 3), count());
}

test "lookupByName — finds by (cartridge_id, cell_type_name)" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    try register(fixture(0xBB, "betterment", "practice.intention"));

    const found = lookupByName("betterment", "practice.release").?;
    try testing.expectEqualStrings("betterment", found.cartridge_id);
    try testing.expectEqualStrings("practice.release", found.cell_type_name);
    try testing.expectEqual(@as(u8, 0xAA), found.type_hash[0]);
}

test "lookupByName — returns null when name missing" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    try testing.expectEqual(@as(?CellTypeEntry, null), lookupByName("betterment", "nonexistent"));
}

test "lookupByName — discriminates by cartridge_id" {
    resetForTest();
    try register(fixture(0xAA, "betterment", "practice.release"));
    try register(fixture(0xBB, "oddjobz", "practice.release"));
    // Both have the same cell_type_name but different cartridges
    // → lookupByName disambiguates.
    const a = lookupByName("betterment", "practice.release").?;
    const b = lookupByName("oddjobz", "practice.release").?;
    try testing.expectEqual(@as(u8, 0xAA), a.type_hash[0]);
    try testing.expectEqual(@as(u8, 0xBB), b.type_hash[0]);
}

test "register surfaces registry_full at capacity boundary" {
    resetForTest();
    var i: usize = 0;
    while (i < MAX_REGISTERED_CELL_TYPES) : (i += 1) {
        var h: [TYPE_HASH_SIZE]u8 = undefined;
        std.mem.writeInt(u64, h[0..8], i, .little);
        std.mem.writeInt(u64, h[8..16], 0, .little);
        std.mem.writeInt(u64, h[16..24], 0, .little);
        std.mem.writeInt(u64, h[24..32], 0, .little);
        try register(.{
            .type_hash = h,
            .cartridge_id = "fill",
            .cell_type_name = "f",
            .linearity = .LINEAR,
            .capability_name = "",
            .payload_schema_raw = null,
        });
    }
    var overflow: [TYPE_HASH_SIZE]u8 = undefined;
    std.mem.writeInt(u64, overflow[0..8], MAX_REGISTERED_CELL_TYPES, .little);
    std.mem.writeInt(u64, overflow[8..16], 0, .little);
    std.mem.writeInt(u64, overflow[16..24], 0, .little);
    std.mem.writeInt(u64, overflow[24..32], 0, .little);
    try testing.expectError(error.registry_full, register(.{
        .type_hash = overflow,
        .cartridge_id = "fill",
        .cell_type_name = "overflow",
        .linearity = .LINEAR,
        .capability_name = "",
        .payload_schema_raw = null,
    }));
}

```
