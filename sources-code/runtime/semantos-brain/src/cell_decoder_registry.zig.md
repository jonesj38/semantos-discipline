---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_decoder_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.264584+00:00
---

# runtime/semantos-brain/src/cell_decoder_registry.zig

```zig
//! Cell-decoder registry — C4 (substrate-generalization), the generic cell.query
//! seam.
//!
//! The brain's `cell.query(typeHash, filter)` primitive enumerates cell hashes
//! generically via the cells_by_type index (PR-J1) and materialises each cell —
//! but turning a cell into typed JSON, and evaluating a field filter against it,
//! is per-cellType SCHEMA knowledge a cartridge owns. This registry is that seam:
//! each cartridge registers, in registerInto, a decoder per cellType it serves.
//! `cell_query_handler` looks the decoder up by typeHash and dispatches — so the
//! brain's read surface is uniform and names no cartridge (replacing the old
//! hardcoded `.oddjobz` wrap + TYPE_HASH_REGISTRY).
//!
//! It is the read-side analog of route_registry / mint_context_registry /
//! store_registry: a substrate-owned table on CartridgeDeps the cartridge fills.
//!
//! Leaf deps: std only — so cartridge_seam can expose it on CartridgeDeps
//! without pulling in serve/reactor (#847 dep gate). Decoders carry an opaque
//! `ctx` (the cartridge's store pointer) + fn pointers; the registry never frees
//! them (the cartridge owns their lifetime, brain-lifetime).

const std = @import("std");

/// Decode one cell (by its 32-byte hash) into a typed JSON object, allocated
/// with `allocator` (the caller frees / arena reclaims). Returns null if the
/// cell can't be resolved/decoded (e.g. not in the cartridge's view) — the
/// query skips it. An error surfaces as a query failure.
pub const DecodeOneFn = *const fn (
    ctx: *anyopaque,
    cell_hash: *const [32]u8,
    allocator: std.mem.Allocator,
) anyerror!?[]u8;

/// Evaluate a filter predicate against one cell. `filter_json` is the caller's
/// filter object (e.g. {"siteRef":"<hex>"}); return true if the cell matches.
/// Null filter ⇒ the handler treats it as "match all" and won't call this.
pub const MatchesFilterFn = *const fn (
    ctx: *anyopaque,
    cell_hash: *const [32]u8,
    filter_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!bool;

/// Enumerate the 32-byte cell hashes this cellType's cartridge store holds.
/// When present on a decoder, cell.query uses THIS as its candidate set
/// instead of the generic `cells_by_type` index — required for cells that
/// live in a cartridge typed store but were never mirrored into the generic
/// index (e.g. oddjobz cells minted via the §6b cluster path). The handler
/// then applies `matches_filter` (if any) + `decode_one` to each hash. The
/// caller owns/frees the returned slice.
pub const EnumerateFn = *const fn (
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![][32]u8;

/// One registered cellType decoder.
pub const CellDecoder = struct {
    /// The real 32-byte typeHash these cells carry at cell bytes [30:62] — the
    /// value cell.query matches against (and cellsByType is keyed on).
    type_hash: [32]u8,
    /// Friendly alias the legacy cell.query param accepted (e.g.
    /// "oddjobz.job.v2"); kept for back-compat so existing callers still work.
    /// Borrowed (usually a literal).
    alias: []const u8,
    /// JSON envelope key for a list result (e.g. "jobs" → {"jobs":[…]}). Borrowed.
    collection_key: []const u8,
    /// JSON envelope key for a single get result (e.g. "job" → {"job":{…}}).
    singular_key: []const u8,
    /// Whether a list with no filter is allowed. site/customer = true; job/
    /// attachment historically required a filter (no list-all) = false.
    allow_unfiltered_list: bool = true,
    /// Caller-owned state threaded into the fns (the cartridge's store pointer).
    ctx: *anyopaque,
    decode_one: DecodeOneFn,
    /// Optional: only needed for cellTypes that support filtered queries.
    matches_filter: ?MatchesFilterFn = null,
    /// Optional: when set, cell.query enumerates the cartridge store via this
    /// instead of the generic `cells_by_type` index. Use for cells held only
    /// in a cartridge typed store (not mirrored into the generic index).
    enumerate: ?EnumerateFn = null,
};

/// Growable, bounded registry. Default-constructable (`.{}`); the cartridge
/// appends via `add`. cell_query_handler reads it via `find`.
pub const CellDecoderRegistry = struct {
    /// Ceiling — generous for the registered cellType set across cartridges.
    pub const MAX = 64;
    entries: [MAX]CellDecoder = undefined,
    len: usize = 0,

    pub fn add(self: *CellDecoderRegistry, decoder: CellDecoder) void {
        if (self.len >= MAX) {
            std.log.warn("cell_decoder_registry: MAX ({d}) reached; dropping decoder for alias {s}", .{ MAX, decoder.alias });
            return;
        }
        self.entries[self.len] = decoder;
        self.len += 1;
    }

    /// Resolve a cell.query `typeHash` param to a decoder: a 64-char lowercase
    /// hex string is matched against the real 32-byte type_hash; anything else
    /// is matched against the friendly `alias`. Returns null if unregistered.
    pub fn find(self: *const CellDecoderRegistry, type_hash_param: []const u8) ?*const CellDecoder {
        // Hex path: 64 lowercase-hex chars → compare to the raw type_hash.
        if (type_hash_param.len == 64) {
            var want: [32]u8 = undefined;
            if (hexDecode(type_hash_param, &want)) {
                for (self.entries[0..self.len]) |*d| {
                    if (std.mem.eql(u8, &d.type_hash, &want)) return d;
                }
                return null;
            }
        }
        // Alias path.
        for (self.entries[0..self.len]) |*d| {
            if (std.mem.eql(u8, d.alias, type_hash_param)) return d;
        }
        // Bare-noun path: the shell-native `query <noun>` primitive passes the
        // collection_key ("customers"/"jobs"/…) so cell-querying is ergonomic
        // and cartridge-agnostic (no need to know the alias or raw typeHash).
        for (self.entries[0..self.len]) |*d| {
            if (std.mem.eql(u8, d.collection_key, type_hash_param)) return d;
        }
        return null;
    }
};

/// Decode a 64-char lowercase-hex string into 32 bytes. Returns false on any
/// non-hex char or wrong length (caller falls back to the alias path).
fn hexDecode(hex: []const u8, out: *[32]u8) bool {
    if (hex.len != 64) return false;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const hi = hexNibble(hex[i * 2]) orelse return false;
        const lo = hexNibble(hex[i * 2 + 1]) orelse return false;
        out[i] = (hi << 4) | lo;
    }
    return true;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

fn dummyDecode(_: *anyopaque, _: *const [32]u8, _: std.mem.Allocator) anyerror!?[]u8 {
    return null;
}

test "registry: find by alias and by hex type_hash" {
    var reg: CellDecoderRegistry = .{};
    var dummy_ctx: u8 = 0;
    var th: [32]u8 = [_]u8{0} ** 32;
    th[0] = 0xAB;
    th[31] = 0xCD;
    reg.add(.{
        .type_hash = th,
        .alias = "oddjobz.job.v2",
        .collection_key = "jobs",
        .singular_key = "job",
        .ctx = &dummy_ctx,
        .decode_one = dummyDecode,
    });

    // Alias match.
    try testing.expect(reg.find("oddjobz.job.v2") != null);
    try testing.expect(reg.find("nope.v9") == null);

    // Bare-noun (collection_key) match — what `query <noun>` passes.
    try testing.expect(reg.find("jobs") != null);
    try testing.expectEqualStrings("oddjobz.job.v2", reg.find("jobs").?.alias);
    try testing.expect(reg.find("widgets") == null);

    // Hex match — build the 64-char hex of th.
    var hex: [64]u8 = undefined;
    const lut = "0123456789abcdef";
    for (th, 0..) |b, i| {
        hex[i * 2] = lut[b >> 4];
        hex[i * 2 + 1] = lut[b & 0x0f];
    }
    try testing.expect(reg.find(hex[0..]) != null);

    // A 64-char non-matching hex → null.
    var other_hex: [64]u8 = [_]u8{'0'} ** 64;
    other_hex[63] = '1';
    try testing.expect(reg.find(other_hex[0..]) == null);
}

```
