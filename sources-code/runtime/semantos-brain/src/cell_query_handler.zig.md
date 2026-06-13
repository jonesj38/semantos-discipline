---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_query_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.214219+00:00
---

# runtime/semantos-brain/src/cell_query_handler.zig

```zig
//! Generic cell.query / cell.get primitive — typeHash-keyed projection over the
//! cell DAG. C4 (substrate-generalization): the brain's read surface is uniform
//! and names NO cartridge.
//!
//! cell.query enumerates cell hashes by typeHash via the cells_by_type index
//! (PR-J1) and hands each to a cartridge-registered DECODER
//! (cell_decoder_registry, PR-J2) that produces typed JSON + evaluates the
//! filter. The decoder also supplies the JSON envelope keys, so the wire shape
//! is preserved per cellType ({"jobs":[…]} / {"job":{…}}).
//!
//! Replaces the prior hardcoded `.oddjobz` wrap + TYPE_HASH_REGISTRY: the brain
//! no longer knows oddjobz cellTypes; the oddjobz cartridge registers its
//! decoders in registerInto. New cartridges register theirs the same way and are
//! cell.query-driveable for free.
//!
//! Wire shape (unchanged):
//!   cell.query  params { typeHash, filter?, … }  result { "<collection>":[…] }
//!   cell.get    params { typeHash, cellRef|<typeRef> }  result { "<singular>": {…}|null }
//!
//! `typeHash` accepts either a real 64-hex typeHash (matched against the cells'
//! [30:62] bytes) or a registered friendly alias (e.g. "oddjobz.job.v2") for
//! back-compat.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const cell_decoder_registry = @import("cell_decoder_registry");

pub const CellQueryError = error{
    invalid_params,
    unknown_type_hash,
    invalid_filter,
    invalid_cell_ref,
    store_unavailable,
    out_of_memory,
};

pub const Handler = struct {
    cell_store: *const cell_store_mod.CellStore,
    registry: *const cell_decoder_registry.CellDecoderRegistry,

    /// cell.query — list cells of `type_hash` (optionally filtered). Returns the
    /// JSON body `{"<collection_key>":[ …elements ]}` (newly-allocated).
    pub fn query(
        self: *const Handler,
        allocator: std.mem.Allocator,
        type_hash: []const u8,
        filter_json: ?[]const u8,
    ) CellQueryError![]u8 {
        const dec = self.registry.find(type_hash) orelse return CellQueryError.unknown_type_hash;

        // A filter against a cellType with no predicate support, or no filter
        // against a cellType that requires one, is a bad request.
        if (filter_json) |_| {
            if (dec.matches_filter == null) return CellQueryError.invalid_filter;
        } else {
            if (!dec.allow_unfiltered_list) return CellQueryError.invalid_filter;
        }

        // Candidate hash set: prefer the decoder's own enumerator (cells held
        // in a cartridge typed store, not mirrored into the generic index);
        // otherwise fall back to the generic cells_by_type index.
        const hashes = if (dec.enumerate) |enumerate_fn|
            (enumerate_fn(dec.ctx, allocator) catch return CellQueryError.store_unavailable)
        else
            (self.cell_store.cellsByType(allocator, &dec.type_hash) catch
                return CellQueryError.store_unavailable);
        defer allocator.free(hashes);

        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);
        buf.appendSlice(allocator, "{\"") catch return CellQueryError.out_of_memory;
        buf.appendSlice(allocator, dec.collection_key) catch return CellQueryError.out_of_memory;
        buf.appendSlice(allocator, "\":[") catch return CellQueryError.out_of_memory;

        var first = true;
        for (hashes) |h| {
            if (filter_json) |fj| {
                const matches = dec.matches_filter.?(dec.ctx, &h, fj, allocator) catch
                    return CellQueryError.invalid_filter;
                if (!matches) continue;
            }
            const elem = (dec.decode_one(dec.ctx, &h, allocator) catch
                return CellQueryError.store_unavailable) orelse continue;
            defer allocator.free(elem);
            if (!first) buf.append(allocator, ',') catch return CellQueryError.out_of_memory;
            first = false;
            buf.appendSlice(allocator, elem) catch return CellQueryError.out_of_memory;
        }

        buf.appendSlice(allocator, "]}") catch return CellQueryError.out_of_memory;
        return buf.toOwnedSlice(allocator) catch return CellQueryError.out_of_memory;
    }

    /// cell.get — single cell by ref. Returns `{"<singular_key>": {…}|null}`.
    /// The ref is the first 64-hex string value in the params object (matches
    /// the documented `cellRef` + the legacy per-type ref names like siteRef).
    pub fn get(
        self: *const Handler,
        allocator: std.mem.Allocator,
        type_hash: []const u8,
        cell_ref_params_json: []const u8,
    ) CellQueryError![]u8 {
        const dec = self.registry.find(type_hash) orelse return CellQueryError.unknown_type_hash;

        var ref: [32]u8 = undefined;
        if (!extractCellRef(allocator, cell_ref_params_json, &ref)) return CellQueryError.invalid_cell_ref;

        const elem_opt = dec.decode_one(dec.ctx, &ref, allocator) catch
            return CellQueryError.store_unavailable;

        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);
        buf.appendSlice(allocator, "{\"") catch return CellQueryError.out_of_memory;
        buf.appendSlice(allocator, dec.singular_key) catch return CellQueryError.out_of_memory;
        buf.appendSlice(allocator, "\":") catch return CellQueryError.out_of_memory;
        if (elem_opt) |elem| {
            defer allocator.free(elem);
            buf.appendSlice(allocator, elem) catch return CellQueryError.out_of_memory;
        } else {
            buf.appendSlice(allocator, "null") catch return CellQueryError.out_of_memory;
        }
        buf.append(allocator, '}') catch return CellQueryError.out_of_memory;
        return buf.toOwnedSlice(allocator) catch return CellQueryError.out_of_memory;
    }
};

/// Pull a 32-byte cell ref out of the params object: the first string value
/// that's 64 lowercase/upper hex chars (covers `cellRef`, `cellId`, and the
/// legacy per-type names siteRef/customerRef/jobRef/attachmentRef).
fn extractCellRef(allocator: std.mem.Allocator, params_json: []const u8, out: *[32]u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        if (v == .string and v.string.len == 64) {
            if (hexDecode(v.string, out)) return true;
        }
    }
    return false;
}

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

// ─── tests ───────────────────────────────────────────────────────────────

const TestEnumStore = struct {
    ids: []const [32]u8,
    fn enumerate(ctx: *anyopaque, alloc: std.mem.Allocator) anyerror![][32]u8 {
        const self: *const TestEnumStore = @ptrCast(@alignCast(ctx));
        const out = try alloc.alloc([32]u8, self.ids.len);
        @memcpy(out, self.ids);
        return out;
    }
    fn decodeOne(_: *anyopaque, hash: *const [32]u8, alloc: std.mem.Allocator) anyerror!?[]u8 {
        return try std.fmt.allocPrint(alloc, "{{\"b\":{d}}}", .{hash[0]});
    }
};

test "cell.query enumerate seam: enumerates the decoder's store, not the cells_by_type index" {
    const alloc = std.testing.allocator;
    const ids = [_][32]u8{ [_]u8{1} ** 32, [_]u8{2} ** 32, [_]u8{3} ** 32 };
    var ts = TestEnumStore{ .ids = &ids };
    var reg = cell_decoder_registry.CellDecoderRegistry{};
    reg.add(.{
        .type_hash = [_]u8{0} ** 32,
        .alias = "test.thing.v1",
        .collection_key = "things",
        .singular_key = "thing",
        .allow_unfiltered_list = true,
        .ctx = @ptrCast(&ts),
        .decode_one = TestEnumStore.decodeOne,
        .enumerate = TestEnumStore.enumerate,
    });
    // cell_store is never dereferenced when `enumerate` is set — proves the
    // query reaches the cartridge store, not the generic index.
    var fake_store: cell_store_mod.CellStore = undefined;
    const h = Handler{ .cell_store = &fake_store, .registry = &reg };
    const body = try h.query(alloc, "test.thing.v1", null);
    defer alloc.free(body);
    try std.testing.expectEqualStrings("{\"things\":[{\"b\":1},{\"b\":2},{\"b\":3}]}", body);
}

```
