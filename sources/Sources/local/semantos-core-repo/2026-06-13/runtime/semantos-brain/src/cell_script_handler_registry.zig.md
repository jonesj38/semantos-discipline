---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_script_handler_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.243864+00:00
---

# runtime/semantos-brain/src/cell_script_handler_registry.zig

```zig
// C11 PR4a — cell-script handler registry.
//
// Maps the canonical 32-byte structured typeHash → HandlerEntry,
// populated by `cell_script_handler_loader` from each cartridge's
// `cellTypes[i].handler` entries.
//
// Companion to `cartridge_cell_registry`. Co-existence rationale:
//
//   - `cartridge_cell_registry` is keyed by typeHash and holds the
//     cell type's substrate metadata (cartridge_id, linearity,
//     capability_name, payload_schema_raw). EVERY declared cellType
//     lands there.
//
//   - This registry is also keyed by typeHash but holds the verified
//     cell-engine script bytes + capability lists + opcount budget.
//     Only the SUBSET of cellTypes whose manifest entries carry a
//     `handler` field land here. Substrate state records (e.g.
//     `bsv.linear.anchor`) have no handler and never appear here.
//
// What this registry exposes:
//
//   - Lookup by typeHash → returns the HandlerEntry (script bytes,
//     script hash, capability list, opcount budget, emits list).
//
//   - No wasmtime / compile cache. The cell-engine 2-PDA is a
//     stack-based interpreter over plain Zig bytes; the dispatcher
//     (PR4b) hands `script_bytes` straight to the executor.
//
// PR4a scope ENDS at the registry: 4a does NOT dispatch any script.
// The mint-pipeline wiring (typeHash → look up → execute → drain
// emits) lands in PR4b. For now `cells_mint_handler` only LOGS the
// lookup so operators can see which typeHashes will route through
// script-handler dispatch once execution wiring lands.
//
// Lifetime contract:
//   - `script_bytes` + `capabilities[i]` + `emits[i]` are
//     `[]const u8` references with no embedded length-prefix or
//     refcount; they must outlive every mint request. In practice
//     they're allocated by the loader from the same boot-lifetime
//     ArenaAllocator that `cartridge_cell_boot` owns.
//
// Single-threaded brain reactor → file-scope bounded array, no mutex.

const std = @import("std");

/// 32-byte structured typeHash.
pub const TYPE_HASH_SIZE: usize = 32;

/// Max handlers the brain can ever serve in one process. 256 = well
/// over MAX_REGISTERED_CELL_TYPES of practical interest; handlers are
/// a strict subset of cellTypes (most cellTypes are substrate
/// records), so this is a generous ceiling.
pub const MAX_HANDLERS: usize = 256;

/// Per-handler metadata + verified script bytes. All `[]const u8`
/// fields are boot-lifetime — populated from arena-allocated buffers
/// by the loader. No allocator owned here.
pub const HandlerEntry = struct {
    /// Verified cell-engine bytecode (sha256 matched `scriptHash` at
    /// load time). The PR4b dispatcher hands these straight to the
    /// 2-PDA executor; no copy required.
    script_bytes: []const u8,

    /// Raw sha256 of `script_bytes`. Kept for audit / debug — same
    /// value the manifest's `scriptHash` decodes to.
    script_hash: [32]u8,

    /// Hostcall capability tags the handler may invoke. Each tag is
    /// the manifest `cap.…` string, e.g. `cap.bsv.beef.verify`. PR4b
    /// gates per-call against this list before each hostcall.
    capabilities: []const []const u8,

    /// Max executor opcodes per dispatch. Mirrors the cell-engine
    /// executor's `max_ops` knob; defaults to 500_000 in the loader
    /// when the manifest omits `opcountBudget`.
    opcount_budget: u32,

    /// Explicit emit allowlist — cellType-name strings the handler
    /// may emit via OP_CELLCREATE. PR4b resolves these to typeHashes
    /// against `cartridge_cell_registry` at dispatch time.
    emits: []const []const u8,
};

pub const RegisterError = error{
    /// Same typeHash already registered.
    type_hash_collision,
    /// Registry full — MAX_HANDLERS would be exceeded.
    registry_full,
};

/// Slot in the bounded array. `null` for unused tail slots.
const Slot = struct {
    type_hash: [TYPE_HASH_SIZE]u8,
    entry: HandlerEntry,
};

var slots: [MAX_HANDLERS]?Slot = .{null} ** MAX_HANDLERS;
var slot_count: usize = 0;

/// Register one handler keyed by its 32-byte structured typeHash.
/// Boot-only; caller (the loader) MUST have allocated every
/// `[]const u8` field on `entry` out of a boot-lifetime arena.
pub fn register(type_hash: [TYPE_HASH_SIZE]u8, entry: HandlerEntry) RegisterError!void {
    // Lookup-then-register: collision is any pre-existing entry for
    // this typeHash.
    if (lookup(&type_hash) != null) return error.type_hash_collision;
    if (slot_count >= MAX_HANDLERS) return error.registry_full;
    slots[slot_count] = .{ .type_hash = type_hash, .entry = entry };
    slot_count += 1;
}

/// Look up a handler by its 32-byte structured typeHash. Returns
/// null when the cellType has no handler (substrate state record) OR
/// when the typeHash isn't a known cellType at all — callers
/// distinguish via the parallel `cartridge_cell_registry` lookup.
pub fn lookup(type_hash: *const [TYPE_HASH_SIZE]u8) ?HandlerEntry {
    var i: usize = 0;
    while (i < slot_count) : (i += 1) {
        if (slots[i]) |s| {
            if (std.mem.eql(u8, &s.type_hash, type_hash)) return s.entry;
        }
    }
    return null;
}

/// Reset for tests. NEVER call in production.
pub fn resetRegistryForTest() void {
    var i: usize = 0;
    while (i < slot_count) : (i += 1) slots[i] = null;
    slot_count = 0;
}

/// Count of currently-registered handlers (introspection / boot
/// logs).
pub fn registryCountForTest() usize {
    return slot_count;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure register/lookup semantics. Loader-integration
// tests live in cell_script_handler_loader.zig.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn fixtureHash(byte: u8) [TYPE_HASH_SIZE]u8 {
    var h: [TYPE_HASH_SIZE]u8 = undefined;
    @memset(&h, byte);
    return h;
}

fn fixtureEntry(script_byte: u8) HandlerEntry {
    var sh: [32]u8 = undefined;
    @memset(&sh, script_byte ^ 0x55);
    return .{
        .script_bytes = &[_]u8{ 0x51, 0x76, 0xa9 }, // OP_1 OP_DUP OP_HASH160
        .script_hash = sh,
        .capabilities = &.{},
        .opcount_budget = 500_000,
        .emits = &.{},
    };
}

test "register + lookup round-trip on distinct typeHashes" {
    resetRegistryForTest();
    const a = fixtureHash(0xAA);
    const b = fixtureHash(0xBB);
    try register(a, fixtureEntry(0xAA));
    try register(b, fixtureEntry(0xBB));
    try testing.expectEqual(@as(usize, 2), registryCountForTest());

    const got_a = lookup(&a).?;
    try testing.expectEqual(@as(u32, 500_000), got_a.opcount_budget);
    try testing.expectEqual(@as(usize, 3), got_a.script_bytes.len);

    const got_b = lookup(&b).?;
    try testing.expectEqual(@as(usize, 3), got_b.script_bytes.len);
}

test "lookup returns null for unknown typeHash" {
    resetRegistryForTest();
    try register(fixtureHash(0xAA), fixtureEntry(0xAA));
    const unknown = fixtureHash(0xFF);
    try testing.expectEqual(@as(?HandlerEntry, null), lookup(&unknown));
}

test "register rejects collision on same typeHash" {
    resetRegistryForTest();
    const h = fixtureHash(0xAA);
    try register(h, fixtureEntry(0xAA));
    try testing.expectError(error.type_hash_collision, register(h, fixtureEntry(0xBB)));
    try testing.expectEqual(@as(usize, 1), registryCountForTest());
}

test "resetRegistryForTest clears the count back to 0" {
    resetRegistryForTest();
    try register(fixtureHash(0xAA), fixtureEntry(0xAA));
    try register(fixtureHash(0xBB), fixtureEntry(0xBB));
    try testing.expectEqual(@as(usize, 2), registryCountForTest());
    resetRegistryForTest();
    try testing.expectEqual(@as(usize, 0), registryCountForTest());
    const a = fixtureHash(0xAA);
    try testing.expectEqual(@as(?HandlerEntry, null), lookup(&a));
}

test "register surfaces registry_full at capacity boundary" {
    resetRegistryForTest();
    var i: usize = 0;
    while (i < MAX_HANDLERS) : (i += 1) {
        var t: [TYPE_HASH_SIZE]u8 = undefined;
        std.mem.writeInt(u64, t[0..8], i, .little);
        std.mem.writeInt(u64, t[8..16], 0, .little);
        std.mem.writeInt(u64, t[16..24], 0, .little);
        std.mem.writeInt(u64, t[24..32], 0, .little);
        try register(t, fixtureEntry(@intCast(i & 0xff)));
    }
    var overflow_t: [TYPE_HASH_SIZE]u8 = undefined;
    std.mem.writeInt(u64, overflow_t[0..8], MAX_HANDLERS, .little);
    std.mem.writeInt(u64, overflow_t[8..16], 0, .little);
    std.mem.writeInt(u64, overflow_t[16..24], 0, .little);
    std.mem.writeInt(u64, overflow_t[24..32], 0, .little);
    try testing.expectError(error.registry_full, register(overflow_t, fixtureEntry(0xFF)));
}

```
