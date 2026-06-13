---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/mnca_tile.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.979244+00:00
---

# core/cell-engine/src/mnca_tile.zig

```zig
// mnca_tile.zig — MNCA tile codec + reference rule, Zig port.
//
// Faithful mirror of the TypeScript reference oracle:
//   core/protocol-types/src/mnca/tile.ts
//
// Locked design (brief §15.1): tile = cell, 1 byte/grid-cell raw in the
// payload, INTEGER arithmetic (determinism across C6/Pi/Mac), baked-in halo.
// The 768-byte cell payload IS the tile — the same bytes the cell-engine
// reads in SRAM, that cross the wire, that become pushdrop UTXO data. No
// marshalling at any layer.
//
// This is the on-device MNCA compute kernel (Pi/C6); the TS rule is the
// determinism oracle. Allocation-free: stepTilePayload reads an input
// 768-byte payload and writes the next generation into an output payload
// (double-buffered — a CA must read old state while writing new). Self-
// contained (std only) so `zig test core/cell-engine/src/mnca_tile.zig`
// runs standalone.

const std = @import("std");

pub const PAYLOAD_SIZE: usize = 768;
pub const TILE_HEADER_SIZE: usize = 16;
pub const TILE_MAX_CELLS: usize = PAYLOAD_SIZE - TILE_HEADER_SIZE; // 752

// Payload field offsets (within the 768-byte payload region).
pub const OFF_TILE_X: usize = 0; // u16 LE
pub const OFF_TILE_Y: usize = 2; // u16 LE
pub const OFF_TICK: usize = 4; // u64 LE
pub const OFF_WIDTH: usize = 12; // u8 (incl. halo)
pub const OFF_HEIGHT: usize = 13; // u8 (incl. halo)
pub const OFF_HALO: usize = 14; // u8
pub const OFF_FLAGS: usize = 15; // u8
pub const OFF_STATE: usize = 16; // W*H state bytes

/// Largest square tile side (incl. halo) that fits the payload. floor(sqrt(752)) = 27.
pub fn maxSquareTileSide() usize {
    return std.math.sqrt(TILE_MAX_CELLS);
}

// ── Tile metadata accessors (the cells live raw at payload[16..16+W*H]) ──────
pub fn tileX(p: []const u8) u16 {
    return std.mem.readInt(u16, p[OFF_TILE_X..][0..2], .little);
}
pub fn tileY(p: []const u8) u16 {
    return std.mem.readInt(u16, p[OFF_TILE_Y..][0..2], .little);
}
pub fn tick(p: []const u8) u64 {
    return std.mem.readInt(u64, p[OFF_TICK..][0..8], .little);
}
pub fn width(p: []const u8) u8 {
    return p[OFF_WIDTH];
}
pub fn height(p: []const u8) u8 {
    return p[OFF_HEIGHT];
}
pub fn haloRadius(p: []const u8) u8 {
    return p[OFF_HALO];
}

/// Write the tile header fields into a payload buffer (state bytes untouched).
pub fn writeHeader(p: []u8, x: u16, y: u16, t: u64, w: u8, h: u8, r: u8, flags: u8) void {
    std.debug.assert(p.len >= PAYLOAD_SIZE);
    std.debug.assert(TILE_HEADER_SIZE + @as(usize, w) * @as(usize, h) <= PAYLOAD_SIZE);
    std.debug.assert(2 * @as(usize, r) < @min(w, h)); // interior must exist
    std.mem.writeInt(u16, p[OFF_TILE_X..][0..2], x, .little);
    std.mem.writeInt(u16, p[OFF_TILE_Y..][0..2], y, .little);
    std.mem.writeInt(u64, p[OFF_TICK..][0..8], t, .little);
    p[OFF_WIDTH] = w;
    p[OFF_HEIGHT] = h;
    p[OFF_HALO] = r;
    p[OFF_FLAGS] = flags;
}

/// Interior dimensions (the cells this tile owns, excluding the halo ring).
pub fn interiorWidth(p: []const u8) u8 {
    return width(p) - 2 * haloRadius(p);
}
pub fn interiorHeight(p: []const u8) u8 {
    return height(p) - 2 * haloRadius(p);
}

/// Reference MNCA rule parameters — a deterministic, integer, two-radius
/// totalistic rule (Larger-than-Life birth/survival on the inner
/// neighbourhood, nudged by the outer neighbourhood — the "multi" in MNCA).
/// SWAPPABLE reference, not final dynamics (Todd owns the aesthetics). All
/// arithmetic is integer.
pub const MncaRuleParams = struct {
    alive_threshold: u8 = 128,
    inner_radius: u8 = 1,
    outer_radius: u8 = 3,
    birth_lo: u8 = 3,
    birth_hi: u8 = 3,
    survive_lo: u8 = 2,
    survive_hi: u8 = 3,
    grow_step: u8 = 64,
    decay_step: u8 = 64,
    outer_boost: u8 = 12,
};

pub const DEFAULT_MNCA_RULE: MncaRuleParams = .{};

fn clampU8(v: i32) u8 {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return @intCast(v);
}

/// Count "alive" cells (state >= alive_threshold) in the box of `radius`
/// around (x,y), excluding the centre. Reads `cells` (row-major, width W).
fn neighbourhoodAliveCount(
    cells: []const u8,
    w: usize,
    x: usize,
    y: usize,
    radius: usize,
    alive_threshold: u8,
) u32 {
    var count: u32 = 0;
    var dy: i64 = -@as(i64, @intCast(radius));
    while (dy <= @as(i64, @intCast(radius))) : (dy += 1) {
        var dx: i64 = -@as(i64, @intCast(radius));
        while (dx <= @as(i64, @intCast(radius))) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            const ny: usize = @intCast(@as(i64, @intCast(y)) + dy);
            const nx: usize = @intCast(@as(i64, @intCast(x)) + dx);
            if (cells[ny * w + nx] >= alive_threshold) count += 1;
        }
    }
    return count;
}

/// Advance the tile interior one MNCA generation. Reads the full input tile
/// payload `in` (interior + halo), writes the next payload into `out`: header
/// copied with tick+1, halo ring carried over unchanged (neighbour gossip
/// refreshes it), interior recomputed. Double-buffered. `in` is not mutated.
pub fn stepTilePayload(in: *const [PAYLOAD_SIZE]u8, out: *[PAYLOAD_SIZE]u8, params: MncaRuleParams) void {
    @memcpy(out, in); // header + all cells (halo carried over)
    // tick + 1
    std.mem.writeInt(u64, out[OFF_TICK..][0..8], tick(in) + 1, .little);

    const w: usize = width(in);
    const h: usize = height(in);
    const r: usize = haloRadius(in);
    const cells_in = in[OFF_STATE .. OFF_STATE + w * h];
    const inner_r: usize = params.inner_radius;
    const outer_r: usize = params.outer_radius;
    const margin = @max(r, @max(inner_r, outer_r));
    if (h <= 2 * margin or w <= 2 * margin) return; // nothing to evolve

    var y: usize = margin;
    while (y < h - margin) : (y += 1) {
        var x: usize = margin;
        while (x < w - margin) : (x += 1) {
            const self: u8 = cells_in[y * w + x];
            const inner_alive = neighbourhoodAliveCount(cells_in, w, x, y, inner_r, params.alive_threshold);
            const outer_alive = neighbourhoodAliveCount(cells_in, w, x, y, outer_r, params.alive_threshold);
            const is_alive = self >= params.alive_threshold;

            var delta: i32 = undefined;
            if (is_alive) {
                delta = if (inner_alive >= params.survive_lo and inner_alive <= params.survive_hi)
                    @as(i32, params.grow_step)
                else
                    -@as(i32, params.decay_step);
            } else {
                delta = if (inner_alive >= params.birth_lo and inner_alive <= params.birth_hi)
                    @as(i32, params.grow_step)
                else
                    -@as(i32, params.decay_step);
            }
            // Second-neighbourhood nudge.
            if (outer_alive >= params.outer_boost) delta += @as(i32, params.grow_step);

            out[OFF_STATE + y * w + x] = clampU8(@as(i32, self) + delta);
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// Tests — scenarios mirror the TS oracle (tile.test.ts), hand-verifiable.
// Run: zig test core/cell-engine/src/mnca_tile.zig
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

const W = 7;
const H = 7;

fn idx(x: usize, y: usize) usize {
    return OFF_STATE + y * W + x;
}

fn zeroTile() [PAYLOAD_SIZE]u8 {
    var p = [_]u8{0} ** PAYLOAD_SIZE;
    writeHeader(&p, 0, 0, 0, W, H, 1, 0);
    return p;
}

// inner radius 1, outer radius 2, boost disabled (outer_boost huge).
const TR_NOBOOST: MncaRuleParams = .{
    .alive_threshold = 1,
    .inner_radius = 1,
    .outer_radius = 2,
    .birth_lo = 3,
    .birth_hi = 3,
    .survive_lo = 2,
    .survive_hi = 3,
    .grow_step = 10,
    .decay_step = 10,
    .outer_boost = 99,
};
const TR_BOOST: MncaRuleParams = blk: {
    var p = TR_NOBOOST;
    p.outer_boost = 3;
    break :blk p;
};

test "layout: header 16B, max cells 752, max square side 27" {
    try testing.expectEqual(@as(usize, 16), TILE_HEADER_SIZE);
    try testing.expectEqual(@as(usize, 752), TILE_MAX_CELLS);
    try testing.expectEqual(@as(usize, 27), maxSquareTileSide());
}

test "header round-trips + interior dims exclude the halo" {
    var p = [_]u8{0} ** PAYLOAD_SIZE;
    writeHeader(&p, 12, 34, 0xDEADBEEF, 26, 26, 1, 0);
    try testing.expectEqual(@as(u16, 12), tileX(&p));
    try testing.expectEqual(@as(u16, 34), tileY(&p));
    try testing.expectEqual(@as(u64, 0xDEADBEEF), tick(&p));
    try testing.expectEqual(@as(u8, 24), interiorWidth(&p));
    try testing.expectEqual(@as(u8, 24), interiorHeight(&p));
}

test "quiescent: all-zero tile stays all-zero" {
    const in = zeroTile();
    var out: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &out, TR_NOBOOST);
    var i: usize = OFF_STATE;
    while (i < OFF_STATE + W * H) : (i += 1) try testing.expectEqual(@as(u8, 0), out[i]);
}

test "birth: dead centre with exactly 3 alive Moore neighbours is born" {
    var in = zeroTile();
    in[idx(2, 2)] = 1;
    in[idx(2, 3)] = 1;
    in[idx(2, 4)] = 1;
    var out: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &out, TR_NOBOOST);
    try testing.expectEqual(@as(u8, 10), out[idx(3, 3)]);
}

test "survival: alive centre with 2 alive neighbours grows" {
    var in = zeroTile();
    in[idx(3, 3)] = 200;
    in[idx(2, 3)] = 1;
    in[idx(4, 3)] = 1;
    var out: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &out, TR_NOBOOST);
    try testing.expectEqual(@as(u8, 210), out[idx(3, 3)]);
}

test "death: alive centre with no alive neighbours decays" {
    var in = zeroTile();
    in[idx(3, 3)] = 200;
    var out: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &out, TR_NOBOOST);
    try testing.expectEqual(@as(u8, 190), out[idx(3, 3)]);
}

test "outer neighbourhood adds growth (the multi in MNCA)" {
    var in = zeroTile();
    in[idx(3, 3)] = 200;
    in[idx(2, 3)] = 1;
    in[idx(4, 3)] = 1;
    var out: [PAYLOAD_SIZE]u8 = undefined;
    // outerAlive = 2 < 3 → no boost → 210.
    stepTilePayload(&in, &out, TR_BOOST);
    try testing.expectEqual(@as(u8, 210), out[idx(3, 3)]);
    // Add a radius-2-only alive cell → outerAlive = 3 → boost → 220.
    in[idx(1, 3)] = 1;
    stepTilePayload(&in, &out, TR_BOOST);
    try testing.expectEqual(@as(u8, 220), out[idx(3, 3)]);
}

test "state saturates at 0 and 255" {
    var in = zeroTile();
    in[idx(3, 3)] = 250;
    in[idx(2, 3)] = 1;
    in[idx(4, 3)] = 1;
    var out: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &out, TR_NOBOOST);
    try testing.expectEqual(@as(u8, 255), out[idx(3, 3)]); // 250+10 saturates
    var in2 = zeroTile();
    in2[idx(3, 3)] = 5; // alive, 0 neighbours → -10 saturates at 0
    stepTilePayload(&in2, &out, TR_NOBOOST);
    try testing.expectEqual(@as(u8, 0), out[idx(3, 3)]);
}

test "deterministic + halo preserved + tick++ + input not mutated" {
    var in = zeroTile();
    var i: usize = 0;
    while (i < W * H) : (i += 1) in[OFF_STATE + i] = @intCast((i * 37) & 0xFF);
    writeHeader(&in, 9, 4, 5, W, H, 1, 0);
    in[idx(0, 0)] = 77; // corner — in the 2-wide frame, never evaluated
    in[idx(6, 6)] = 88;
    const before = in;

    var a: [PAYLOAD_SIZE]u8 = undefined;
    var b: [PAYLOAD_SIZE]u8 = undefined;
    stepTilePayload(&in, &a, TR_BOOST);
    stepTilePayload(&in, &b, TR_BOOST);
    try testing.expectEqualSlices(u8, &a, &b); // deterministic
    try testing.expect(std.mem.eql(u8, &before, &in)); // input untouched
    try testing.expectEqual(@as(u64, 6), tick(&a)); // tick incremented
    try testing.expectEqual(@as(u8, 77), a[idx(0, 0)]); // frame carried over
    try testing.expectEqual(@as(u8, 88), a[idx(6, 6)]);
}

```
