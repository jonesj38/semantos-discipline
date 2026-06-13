---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/tile_script_equivalence.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.964261+00:00
---

# core/cell-engine/tests/tile_script_equivalence.zig

```zig
// tile_script_equivalence — proves the TS `stepTile`-in-Script compiler
// (cartridges/wallet-headers/brain/src/tile-script.ts) is faithful to the
// native MNCA rule (src/mnca_tile.zig). It executes the EXACT bytecode the TS
// compiler emits through the cell-engine executor and asserts the result
// matches stepTilePayload — so the compute axis "rule-in-Script" provably
// equals the rule the engine runs natively.
//
// Three fragments are proven:
//   1. compileCellRule  — the per-cell update kernel (self, outer, inner → next)
//   2. compileAliveCount — threshold-popcount of the top k stack items
//   3. compileCellStep   — full interior step from raw neighbourhood VALUES,
//      checked end-to-end against stepTilePayload on a real 7×7 tile.
//
// KERNEL / ALIVECOUNT3 are the literal bytes emitted by the TS compiler for
// DEFAULT_RULE (pinned in test/tile-script.spec.ts). If the compiler output
// drifts, the TS spec fails; if the bytes stop matching the native rule, this
// test fails.

const std = @import("std");
const pda_mod = @import("pda");
const executor = @import("executor");
const allocator_mod = @import("allocator");
const mnca = @import("mnca_tile");
const host = @import("host");

// ── DEFAULT_RULE per-cell kernel, verbatim from the TS compiler ──
// stack in:  self  outerAlive  innerAlive   (innerAlive on top)
// stack out: next
const KERNEL = [_]u8{
    0x76, 0x52, 0x54, 0xa5, 0x7c, 0x53, 0x54, 0xa5, 0x53, 0x79,
    0x02, 0x80, 0x00, 0xa2, 0x6b, 0x6b, 0x6b, 0x6c, 0x6c, 0x76,
    0x6b, 0x94, 0x6c, 0x7c, 0x6c, 0x95, 0x93, 0x02, 0x80, 0x00,
    0x95, 0x01, 0x40, 0x94, 0x7c, 0x5c, 0xa2, 0x01, 0x40, 0x95,
    0x93, 0x93, 0x00, 0xa4, 0x02, 0xff, 0x00, 0xa3,
};

// compileAliveCount(128, 3) — pinned in the TS spec.
const ALIVECOUNT3 = [_]u8{
    0x02, 0x80, 0x00, 0xa2, 0x6b, 0x02, 0x80, 0x00, 0xa2, 0x6b,
    0x02, 0x80, 0x00, 0xa2, 0x6b, 0x00, 0x6c, 0x93, 0x6c, 0x93,
    0x6c, 0x93,
};

// ── helpers ──

/// Canonical minimal-ScriptNum push of `value` into `buf`; returns byte count.
fn emitPushInt(buf: []u8, value: i64) usize {
    if (value == 0) {
        buf[0] = 0x00;
        return 1;
    }
    if (value >= 1 and value <= 16) {
        buf[0] = @intCast(0x50 + value);
        return 1;
    }
    if (value == -1) {
        buf[0] = 0x4f;
        return 1;
    }
    const neg = value < 0;
    var v: u64 = if (neg) @intCast(-value) else @intCast(value);
    var mag: [10]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        mag[n] = @intCast(v & 0xff);
        v >>= 8;
        n += 1;
    }
    if (mag[n - 1] & 0x80 != 0) {
        mag[n] = if (neg) 0x80 else 0x00;
        n += 1;
    } else if (neg) {
        mag[n - 1] |= 0x80;
    }
    buf[0] = @intCast(n); // n <= 9 < 75, single-byte direct push
    for (0..n) |i| buf[1 + i] = mag[i];
    return n + 1;
}

/// Emit compileAliveCount(threshold, k) into `buf` (mirrors tile-script.ts).
fn emitAliveCount(buf: []u8, threshold: i64, k: u32) usize {
    var n: usize = 0;
    var i: u32 = 0;
    while (i < k) : (i += 1) {
        n += emitPushInt(buf[n..], threshold);
        buf[n] = 0xa2; // OP_GREATERTHANOREQUAL
        n += 1;
        buf[n] = 0x6b; // OP_TOALTSTACK
        n += 1;
    }
    n += emitPushInt(buf[n..], 0);
    i = 0;
    while (i < k) : (i += 1) {
        buf[n] = 0x6c; // OP_FROMALTSTACK
        n += 1;
        buf[n] = 0x93; // OP_ADD
        n += 1;
    }
    return n;
}

/// Run a script and return the top stack item as a ScriptNum.
fn runScript(script: []const u8) !i64 {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [32768]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = executor.ExecutionContext.init(&p, &arena);
    try ctx.loadScript(script);
    _ = try executor.execute(&ctx);
    const top = try p.speek();
    return pda_mod.cellToI64(top.data[0..top.len]);
}

/// Native per-cell rule (DEFAULT) — the same arithmetic stepTilePayload uses.
fn expectedRule(self: u8, inner: u32, outer: u32) u8 {
    const p = mnca.DEFAULT_MNCA_RULE;
    const is_alive = self >= p.alive_threshold;
    var delta: i32 = undefined;
    if (is_alive) {
        delta = if (inner >= p.survive_lo and inner <= p.survive_hi)
            @as(i32, p.grow_step)
        else
            -@as(i32, p.decay_step);
    } else {
        delta = if (inner >= p.birth_lo and inner <= p.birth_hi)
            @as(i32, p.grow_step)
        else
            -@as(i32, p.decay_step);
    }
    if (outer >= p.outer_boost) delta += @as(i32, p.grow_step);
    const v = @as(i32, self) + delta;
    return if (v < 0) 0 else if (v > 255) 255 else @intCast(v);
}

// ── 1. kernel == native rule over a grid of (self, inner, outer) ──

test "compileCellRule kernel == native MNCA rule (DEFAULT) across input grid" {
    const selfs = [_]u8{ 0, 1, 100, 127, 128, 200, 255 };
    var buf: [128]u8 = undefined;
    for (selfs) |s| {
        var inner: u32 = 0;
        while (inner <= 9) : (inner += 1) {
            var outer: u32 = 0;
            while (outer <= 14) : (outer += 1) {
                var n: usize = 0;
                n += emitPushInt(buf[n..], s); // self
                n += emitPushInt(buf[n..], @intCast(outer)); // outerAlive
                n += emitPushInt(buf[n..], @intCast(inner)); // innerAlive (top)
                @memcpy(buf[n .. n + KERNEL.len], &KERNEL);
                n += KERNEL.len;
                const got = try runScript(buf[0..n]);
                try std.testing.expectEqual(@as(i64, expectedRule(s, inner, outer)), got);
            }
        }
    }
}

// ── 2. aliveCount: TS bytes == Zig emitter, and counts correctly ──

test "compileAliveCount(128,3) bytes match the TS compiler output" {
    var buf: [64]u8 = undefined;
    const n = emitAliveCount(&buf, 128, 3);
    try std.testing.expectEqualSlices(u8, &ALIVECOUNT3, buf[0..n]);
}

test "compileAliveCount counts items >= threshold" {
    // 8 values; alive (>=128): 200, 255, 128, 130 → 4.
    const vals = [_]u8{ 200, 5, 255, 127, 128, 0, 130, 99 };
    var buf: [256]u8 = undefined;
    var n: usize = 0;
    for (vals) |v| n += emitPushInt(buf[n..], v);
    n += emitAliveCount(buf[n..], 128, vals.len);
    try std.testing.expectEqual(@as(i64, 4), try runScript(buf[0..n]));
}

// ── 3. compileCellStep end-to-end vs stepTilePayload on a real 7×7 tile ──

const W = 7;
const H = 7;
const CX = 3; // interior cell (margin = max(halo=1, inner=1, outer=3) = 3)
const CY = 3;

fn idx(x: usize, y: usize) usize {
    return mnca.OFF_STATE + y * W + x;
}

/// Build compileCellStep(DEFAULT, innerK, outerK) bytes into buf.
fn emitCellStep(buf: []u8, innerK: u32, outerK: u32) usize {
    var n: usize = 0;
    n += emitAliveCount(buf[n..], 128, outerK); // counts outer (top vals)
    buf[n] = 0x6b; // OP_TOALTSTACK (park outerAlive)
    n += 1;
    n += emitAliveCount(buf[n..], 128, innerK); // counts inner
    buf[n] = 0x6c; // OP_FROMALTSTACK
    n += 1;
    buf[n] = 0x7c; // OP_SWAP  → self outerAlive innerAlive
    n += 1;
    @memcpy(buf[n .. n + KERNEL.len], &KERNEL);
    n += KERNEL.len;
    return n;
}

fn checkCellStepOnTile(in: *const [mnca.PAYLOAD_SIZE]u8) !void {
    var out: [mnca.PAYLOAD_SIZE]u8 = undefined;
    mnca.stepTilePayload(in, &out, mnca.DEFAULT_MNCA_RULE);
    const want: u8 = out[idx(CX, CY)];

    var buf: [4096]u8 = undefined;
    var n: usize = 0;
    // self
    n += emitPushInt(buf[n..], in[idx(CX, CY)]);
    // inner neighbourhood values (Moore r=1, 8 cells, centre excluded)
    var dy: i64 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i64 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            const x: usize = @intCast(@as(i64, CX) + dx);
            const y: usize = @intCast(@as(i64, CY) + dy);
            n += emitPushInt(buf[n..], in[idx(x, y)]);
        }
    }
    // outer neighbourhood values (box r=3, 48 cells, centre excluded) — pushed
    // last so they sit on top, where compileCellStep counts them first.
    dy = -3;
    while (dy <= 3) : (dy += 1) {
        var dx: i64 = -3;
        while (dx <= 3) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            const x: usize = @intCast(@as(i64, CX) + dx);
            const y: usize = @intCast(@as(i64, CY) + dy);
            n += emitPushInt(buf[n..], in[idx(x, y)]);
        }
    }
    n += emitCellStep(buf[n..], 8, 48);
    const got = try runScript(buf[0..n]);
    try std.testing.expectEqual(@as(i64, want), got);
}

test "compileCellStep == stepTilePayload interior on real tiles" {
    // (a) a glider-ish seed
    var t1 = [_]u8{0} ** mnca.PAYLOAD_SIZE;
    mnca.writeHeader(&t1, 0, 0, 0, W, H, 1, 0);
    t1[idx(2, 3)] = 200;
    t1[idx(4, 3)] = 200;
    t1[idx(3, 2)] = 200;
    try checkCellStepOnTile(&t1);

    // (b) a dense seed that triggers the outer boost
    var t2 = [_]u8{0} ** mnca.PAYLOAD_SIZE;
    mnca.writeHeader(&t2, 0, 0, 0, W, H, 1, 0);
    var i: usize = 0;
    while (i < W * H) : (i += 1) t2[mnca.OFF_STATE + i] = @intCast((i * 53) & 0xFF);
    try checkCellStepOnTile(&t2);

    // (c) alive centre, sparse neighbourhood (survival/decay path)
    var t3 = [_]u8{0} ** mnca.PAYLOAD_SIZE;
    mnca.writeHeader(&t3, 0, 0, 0, W, H, 1, 0);
    t3[idx(3, 3)] = 200;
    t3[idx(2, 3)] = 130;
    t3[idx(4, 3)] = 130;
    try checkCellStepOnTile(&t3);
}

// ════════════════════════════════════════════════════════════════════════════
// COVENANT clauses (tile-covenant.ts): the TRANSITION clause + unsignedByte.
// These prove the part of the cell_N → cell_{N+1} covenant that runs in our
// engine; the OP_PUSH_TX auth + hashOutputs bind are the testnet boundary.
// ════════════════════════════════════════════════════════════════════════════

// unsignedByte() = <0x00> OP_CAT OP_BIN2NUM
const UNSIGNED_BYTE = [_]u8{ 0x01, 0x00, 0x7e, 0x81 };

/// Emit compileTransitionClause(DEFAULT, innerK, outerK):
///   OP_TOALTSTACK ‖ cellStep(innerK, outerK) ‖ OP_FROMALTSTACK ‖
///   OP_NUMEQUALVERIFY ‖ OP_1
fn emitTransition(buf: []u8, innerK: u32, outerK: u32) usize {
    var n: usize = 0;
    buf[n] = 0x6b; // OP_TOALTSTACK (park claimedNext)
    n += 1;
    n += emitCellStep(buf[n..], innerK, outerK);
    buf[n] = 0x6c; // OP_FROMALTSTACK (claimedNext)
    n += 1;
    buf[n] = 0x9d; // OP_NUMEQUALVERIFY
    n += 1;
    buf[n] = 0x51; // OP_1
    n += 1;
    return n;
}

test "unsignedByte: raw byte string → unsigned 0..255 (sign-pad clears high bit)" {
    const cases = [_]struct { b: u8, v: i64 }{
        .{ .b = 0x00, .v = 0 },
        .{ .b = 0x05, .v = 5 },
        .{ .b = 0x7f, .v = 127 },
        .{ .b = 0x80, .v = 128 },
        .{ .b = 0xc8, .v = 200 },
        .{ .b = 0xff, .v = 255 },
    };
    var buf: [16]u8 = undefined;
    for (cases) |c| {
        buf[0] = 0x01; // push 1 byte
        buf[1] = c.b;
        @memcpy(buf[2 .. 2 + UNSIGNED_BYTE.len], &UNSIGNED_BYTE);
        try std.testing.expectEqual(c.v, try runScript(buf[0 .. 2 + UNSIGNED_BYTE.len]));
    }
}

test "transition clause: TS bytecode length + head/tail match the compiler" {
    var buf: [256]u8 = undefined;
    const n = emitTransition(&buf, 8, 8);
    try std.testing.expectEqual(@as(usize, 169), n); // compileTransitionClause(8,8)
    try std.testing.expectEqual(@as(u8, 0x6b), buf[0]); // leading TOALTSTACK
    try std.testing.expectEqual(@as(u8, 0x51), buf[n - 1]); // trailing OP_1
    try std.testing.expectEqual(@as(u8, 0x9d), buf[n - 2]); // OP_NUMEQUALVERIFY
}

// Radius-1 rule (inner == outer neighbourhood) so a 3×3 tile has a 1×1
// interior; kernel constants stay DEFAULT, matching compileCellStep's bytes.
const R1: mnca.MncaRuleParams = .{ .inner_radius = 1, .outer_radius = 1 };

/// Drive the transition clause: push self, the 8 neighbour values (as both
/// inner and outer, radius-1), and a claimed next state, then the clause.
fn runTransition(self: u8, nbrs: [8]u8, claimed: i64) !i64 {
    var buf: [512]u8 = undefined;
    var n: usize = 0;
    n += emitPushInt(buf[n..], self); // self (deepest)
    for (nbrs) |v| n += emitPushInt(buf[n..], v); // inner ×8
    for (nbrs) |v| n += emitPushInt(buf[n..], v); // outer ×8
    n += emitPushInt(buf[n..], claimed); // claimedNext (top)
    n += emitTransition(buf[n..], 8, 8);
    return runScript(buf[0..n]);
}

fn aliveCountOf(nbrs: [8]u8) u32 {
    var c: u32 = 0;
    for (nbrs) |v| {
        if (v >= 128) c += 1;
    }
    return c;
}

test "transition clause accepts iff claimedNext == native rule" {
    const seeds = [_]struct { self: u8, nbrs: [8]u8 }{
        .{ .self = 0, .nbrs = .{ 200, 200, 200, 0, 0, 0, 0, 0 } }, // dead, 3 alive → birth
        .{ .self = 200, .nbrs = .{ 130, 130, 0, 0, 0, 0, 0, 0 } }, // alive, 2 alive → survive
        .{ .self = 200, .nbrs = .{ 0, 0, 0, 0, 0, 0, 0, 0 } }, // alive, 0 alive → decay
        .{ .self = 250, .nbrs = .{ 200, 200, 0, 0, 0, 0, 0, 0 } }, // saturates at 255
    };
    for (seeds) |s| {
        const cnt = aliveCountOf(s.nbrs);
        const want = expectedRule(s.self, cnt, cnt);
        // correct claim → success marker (1)
        try std.testing.expectEqual(@as(i64, 1), try runTransition(s.self, s.nbrs, want));
        // wrong claim → OP_NUMEQUALVERIFY aborts the script
        try std.testing.expectError(error.verify_failed, runTransition(s.self, s.nbrs, @as(i64, want) + 1));
    }
}

test "transition clause matches stepTilePayload on a real 3×3 tile (radius-1)" {
    const W3 = 3;
    var in = [_]u8{0} ** mnca.PAYLOAD_SIZE;
    mnca.writeHeader(&in, 0, 0, 0, W3, W3, 1, 0);
    // Seed the 3×3: centre alive + two alive neighbours (survival path).
    in[mnca.OFF_STATE + 1 * W3 + 1] = 200; // centre (1,1)
    in[mnca.OFF_STATE + 1 * W3 + 0] = 130; // (0,1)
    in[mnca.OFF_STATE + 1 * W3 + 2] = 130; // (2,1)

    var out: [mnca.PAYLOAD_SIZE]u8 = undefined;
    mnca.stepTilePayload(&in, &out, R1);
    const want_centre: u8 = out[mnca.OFF_STATE + 1 * W3 + 1];

    // Gather the 8 Moore neighbours of the centre (row-major, centre excluded).
    var nbrs: [8]u8 = undefined;
    var k: usize = 0;
    var dy: i64 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i64 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            const x: usize = @intCast(@as(i64, 1) + dx);
            const y: usize = @intCast(@as(i64, 1) + dy);
            nbrs[k] = in[mnca.OFF_STATE + y * W3 + x];
            k += 1;
        }
    }
    const self = in[mnca.OFF_STATE + 1 * W3 + 1];
    try std.testing.expectEqual(@as(i64, 1), try runTransition(self, nbrs, want_centre));
}

// ════════════════════════════════════════════════════════════════════════════
// OP_PUSH_TX — Brendogg's verbatim optimal-pushtx construction (the AUTH clause
// of the covenant). It hashes the preimage, derives the low-S signature with
// R = Gx (k = 1), DER-encodes it, appends the SIGHASH flag, and pushes his
// precomputed pubkey — leaving [sig, pubkey] for OP_CHECKSIG.
//
// FINDING — why this clause runs on a real BSV node (testnet), NOT our engine:
// the construction does modular arithmetic over the secp256k1 group order
// (OP_ADD/OP_DIV/OP_MOD on the ~256-bit `414136d0…ff00` constant). Post-Genesis
// BSV restored ARBITRARY-PRECISION ScriptNum, so a real node handles it. The
// cell-engine's `cellToI64` is i64-bounded (`<< 8*i` overflows past 8 bytes),
// so it cannot evaluate the AUTH clause — by design: our engine runs the
// i64-safe COMPUTE clause (stepTile, proven above), while AUTH + OP_CHECKSIG
// (which also needs real ECDSA + a live tx context) belong on-chain. This test
// therefore pins the assembled block's STRUCTURE (it is byte-for-byte the same
// fixture the TS spec emits), not its in-engine execution.
//
// Source: cartridges/wallet-headers/brain/src/push-tx.ts, assembled by fromAsm
// and pinned as tests/brendogg-pushtx.hex (the TS spec reads the same file).

const PUSHTX_HEX = @embedFile("brendogg-pushtx.hex");

const PUSHTX_PUBKEY = [_]u8{
    0x02, 0xb4, 0x05, 0xd7, 0xf0, 0x32, 0x2a, 0x89, 0xd0, 0xf9, 0xf3, 0xa9,
    0x8e, 0x6f, 0x93, 0x8f, 0xdc, 0x1c, 0x96, 0x9a, 0x8d, 0x13, 0x82, 0xa2,
    0xbf, 0x66, 0xa7, 0x1a, 0xe7, 0x4a, 0x1e, 0x83, 0xb0,
};

// secp256k1 group-order reduction constant (the bignum our i64 engine chokes on).
const N_CONST = [_]u8{
    0x41, 0x41, 0x36, 0xd0, 0x8c, 0x5e, 0xd2, 0xbf, 0x3b, 0xa0, 0x48, 0xaf,
    0xe6, 0xdc, 0xae, 0xba, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00,
};

fn hexVal(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0xff,
    };
}

/// Decode a hex string (ignoring any trailing whitespace) into `out`.
fn decodeHex(hex: []const u8, out: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i + 1 < hex.len) {
        const hi = hexVal(hex[i]);
        if (hi == 0xff) break;
        const lo = hexVal(hex[i + 1]);
        if (lo == 0xff) break;
        out[n] = (hi << 4) | lo;
        n += 1;
        i += 2;
    }
    return n;
}

fn containsSlice(hay: []const u8, needle: []const u8) bool {
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.mem.eql(u8, hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

test "Brendogg's OP_PUSH_TX block assembles to the expected structure" {
    var block: [512]u8 = undefined;
    const blen = decodeHex(PUSHTX_HEX, &block);
    const b = block[0..blen];
    try std.testing.expectEqual(@as(usize, 430), blen);
    try std.testing.expectEqual(@as(u8, 0xaa), b[0]); // leads with OP_HASH256
    // the verbatim constants are present, byte-exact
    try std.testing.expect(containsSlice(b, &N_CONST)); // group-order reduction
    try std.testing.expect(containsSlice(b, &PUSHTX_PUBKEY)); // pubkey
    // ends by pushing the 33-byte pubkey (0x21 = direct push of 33 bytes)
    try std.testing.expectEqual(@as(u8, 0x21), b[blen - 1 - 33]);
    try std.testing.expectEqualSlices(u8, &PUSHTX_PUBKEY, b[blen - 33 ..]);
}

// ════════════════════════════════════════════════════════════════════════════
// BIND / quine clause (tile-covenant.ts spliceCentreByte + compileBindClause).
// Byte-surgery only (i64-safe), so proven in-engine: rebuild the next output
// from the authenticated preimage and assert HASH256(nextOutput) == the
// preimage's hashOutputs. Pinned bytes match the TS compiler (tile-covenant.spec).
// ════════════════════════════════════════════════════════════════════════════

// spliceCentreByte(): region(9) nextCentre → nextRegion(9)
const SPLICE = [_]u8{ 0x52, 0x80, 0x51, 0x7f, 0x75, 0x7c, 0x54, 0x7f, 0x51, 0x7f, 0x77, 0x6b, 0x7c, 0x7e, 0x6c, 0x7e };
// compileBindClause(): preimage nextRegion → OP_1 (or abort)
const BIND = [_]u8{
    0x59, 0x7c, 0x7e, 0x6b, 0x01, 0x68, 0x7f, 0x77, 0x53, 0x7f, 0x7c, 0x6b,
    0x82, 0x01, 0x34, 0x94, 0x7f, 0x7c, 0x5a, 0x7f, 0x77, 0x6b, 0x58, 0x7f,
    0x7c, 0x6b, 0x54, 0x7f, 0x77, 0x01, 0x20, 0x7f, 0x75, 0x6c, 0x6c, 0x6c,
    0x6c, 0x52, 0x7a, 0x7e, 0x7e, 0x7e, 0xaa, 0x88, 0x51,
};

fn hash256(data: []const u8, out: *[32]u8) void {
    var first: [32]u8 = undefined;
    host.sha256(data, &first);
    host.sha256(&first, out);
}

/// Push `data` (any length) as a single stack item; returns bytes written.
fn emitPushBytes(buf: []u8, data: []const u8) usize {
    var n: usize = 0;
    if (data.len <= 75) {
        buf[0] = @intCast(data.len);
        n = 1;
    } else if (data.len <= 0xff) {
        buf[0] = 0x4c; // PUSHDATA1
        buf[1] = @intCast(data.len);
        n = 2;
    } else {
        buf[0] = 0x4d; // PUSHDATA2
        buf[1] = @intCast(data.len & 0xff);
        buf[2] = @intCast((data.len >> 8) & 0xff);
        n = 3;
    }
    @memcpy(buf[n .. n + data.len], data);
    return n + data.len;
}

test "spliceCentreByte replaces the 3×3 centre with the low byte of nextCentre" {
    const region = [_]u8{ 10, 20, 30, 40, 200, 60, 70, 80, 90 }; // centre (idx4) = 200
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    n += emitPushBytes(buf[n..], &region);
    n += emitPushInt(buf[n..], 137); // nextCentre = 137 (>127 → exercises the 2-byte path)
    @memcpy(buf[n .. n + SPLICE.len], &SPLICE);
    n += SPLICE.len;

    var p = pda_mod.PDA.init(500000);
    var arena_buf: [8192]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = executor.ExecutionContext.init(&p, &arena);
    try ctx.loadScript(buf[0..n]);
    _ = try executor.execute(&ctx);

    const out = try p.speek();
    const want = [_]u8{ 10, 20, 30, 40, 137, 60, 70, 80, 90 };
    try std.testing.expectEqualSlices(u8, &want, out.data[0..out.len]);
}

/// Build a synthetic BIP143 preimage whose hashOutputs commits to a single,
/// value-preserving covenant output carrying `next_region`. Returns preimage len.
fn buildCovenantPreimage(
    out: []u8,
    region: [9]u8,
    next_region: [9]u8,
    cov_code: []const u8, // ≥ 243 bytes so scriptCode > 252 ⇒ 3-byte varint
) usize {
    var sc: [512]u8 = undefined; // scriptCode = 0x09 ‖ region ‖ covCode
    sc[0] = 0x09;
    @memcpy(sc[1..10], &region);
    @memcpy(sc[10 .. 10 + cov_code.len], cov_code);
    const sc_len = 10 + cov_code.len;
    std.debug.assert(sc_len > 252 and sc_len <= 0xffff);
    const varint3 = [_]u8{ 0xfd, @intCast(sc_len & 0xff), @intCast((sc_len >> 8) & 0xff) };

    const value8 = [_]u8{ 0xa0, 0x86, 0x01, 0, 0, 0, 0, 0 }; // 100000 sats
    const nseq4 = [_]u8{ 0xff, 0xff, 0xff, 0xff };

    // next output = value8 ‖ varint3 ‖ (0x09 ‖ next_region ‖ covCode)
    var nout: [600]u8 = undefined;
    var m: usize = 0;
    @memcpy(nout[m .. m + 8], &value8);
    m += 8;
    @memcpy(nout[m .. m + 3], &varint3);
    m += 3;
    nout[m] = 0x09;
    m += 1;
    @memcpy(nout[m .. m + 9], &next_region);
    m += 9;
    @memcpy(nout[m .. m + cov_code.len], cov_code);
    m += cov_code.len;
    var hash_outputs: [32]u8 = undefined;
    hash256(nout[0..m], &hash_outputs);

    // preimage = head104 ‖ varint3 ‖ scriptCode ‖ value8 ‖ nseq4 ‖ hashOutputs ‖ nlock4 ‖ sighash4
    var n: usize = 0;
    var i: usize = 0;
    while (i < 104) : (i += 1) {
        out[n] = @intCast((i * 7) & 0xff);
        n += 1;
    } // arbitrary fixed 104-byte head
    @memcpy(out[n .. n + 3], &varint3);
    n += 3;
    @memcpy(out[n .. n + sc_len], sc[0..sc_len]);
    n += sc_len;
    @memcpy(out[n .. n + 8], &value8);
    n += 8;
    @memcpy(out[n .. n + 4], &nseq4);
    n += 4;
    @memcpy(out[n .. n + 32], &hash_outputs);
    n += 32;
    @memcpy(out[n .. n + 4], &[_]u8{ 0, 0, 0, 0 });
    n += 4; // nLockTime
    @memcpy(out[n .. n + 4], &[_]u8{ 0x41, 0, 0, 0 });
    n += 4; // sighashType
    return n;
}

fn runBind(preimage: []const u8, next_region: [9]u8) !i64 {
    var buf: [1024]u8 = undefined;
    var n: usize = 0;
    n += emitPushBytes(buf[n..], preimage);
    n += emitPushBytes(buf[n..], &next_region);
    @memcpy(buf[n .. n + BIND.len], &BIND);
    n += BIND.len;
    var p = pda_mod.PDA.init(2_000_000);
    var arena_buf: [65536]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = executor.ExecutionContext.init(&p, &arena);
    try ctx.loadScript(buf[0..n]);
    _ = try executor.execute(&ctx);
    const top = try p.speek();
    return pda_mod.cellToI64(top.data[0..top.len]);
}

test "compileBindClause rebuilds the next covenant output and checks hashOutputs" {
    var cov: [260]u8 = undefined; // ≥243 ⇒ scriptCode 270 ⇒ 3-byte varint
    for (0..cov.len) |i| cov[i] = @intCast((i * 31 + 5) & 0xff);

    // current region (survival path) and its one-tick evolution (radius-1 rule)
    const region = [_]u8{ 130, 0, 130, 0, 200, 0, 0, 0, 0 };
    const cnt: u32 = 2; // two neighbours ≥128
    const next_centre = expectedRule(200, cnt, cnt);
    var next_region = region;
    next_region[4] = next_centre;

    var pre: [1024]u8 = undefined;
    const plen = buildCovenantPreimage(&pre, region, next_region, &cov);

    // correct next output → BIND verifies, leaves OP_1
    try std.testing.expectEqual(@as(i64, 1), try runBind(pre[0..plen], next_region));

    // tampered next state → rebuilt output mismatches hashOutputs → abort
    var bad = next_region;
    bad[4] +%= 1;
    try std.testing.expectError(error.verify_failed, runBind(pre[0..plen], bad));
}

// ════════════════════════════════════════════════════════════════════════════
// COVENANT COMPOSITION (tile-covenant.ts compileRegionToNextCentre /
// compileCovenantBody). Proves the i64 data-flow: read the covenant's own 3×3
// region, evolve it (radius-1), splice, and bind to hashOutputs — all but the
// bignum AUTH clause. Bytes pinned in test/tile-covenant.spec.ts.
// ════════════════════════════════════════════════════════════════════════════

const REGION2CENTRE_HEX = "547f517f7c01007e816b7e517f517f517f517f517f517f517f01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b006c936c936c936c936c936c936c936c936c7c76765254a57c5354a55379028000a26b6b6b6c6c766b946c7c6c9593028000950140947c5ca2014095939300a402ff00a3";

const BODY_HEX = "76547f517f7c01007e816b7e517f517f517f517f517f517f517f01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b006c936c936c936c936c936c936c936c936c7c76765254a57c5354a55379028000a26b6b6b6c6c766b946c7c6c9593028000950140947c5ca2014095939300a402ff00a35280517f757c547f517f776b7c7e6c7e597c7e6b01687f77537f7c6b820134947f7c5a7f776b587f7c6b547f7701207f756c6c6c6c527a7e7e7eaa8851";

/// Radius-1 alive count of the 8 Moore neighbours of a 3×3 region.
fn nbrCount(region: [9]u8) u32 {
    var c: u32 = 0;
    for ([_]usize{ 0, 1, 2, 3, 5, 6, 7, 8 }) |i| {
        if (region[i] >= 128) c += 1;
    }
    return c;
}

test "compileRegionToNextCentre == native rule on the 3×3 centre" {
    var code: [256]u8 = undefined;
    const clen = decodeHex(REGION2CENTRE_HEX, &code);
    const regions = [_][9]u8{
        .{ 130, 0, 130, 0, 200, 0, 0, 0, 0 }, // alive centre, 2 alive nbrs → survive
        .{ 200, 200, 200, 0, 0, 0, 0, 0, 0 }, // dead centre, 3 alive nbrs → birth
        .{ 0, 0, 0, 0, 250, 0, 0, 0, 0 }, // alive centre, 0 nbrs → decay
        .{ 200, 200, 200, 200, 5, 200, 200, 200, 200 }, // dead-ish centre, 8 alive
    };
    for (regions) |region| {
        var buf: [512]u8 = undefined;
        var n: usize = 0;
        n += emitPushBytes(buf[n..], &region);
        @memcpy(buf[n .. n + clen], code[0..clen]);
        n += clen;
        const cnt = nbrCount(region);
        const want = expectedRule(region[4], cnt, cnt);
        try std.testing.expectEqual(@as(i64, want), try runScript(buf[0..n]));
    }
}

fn runBody(preimage: []const u8, region: [9]u8) !i64 {
    var code: [256]u8 = undefined;
    const clen = decodeHex(BODY_HEX, &code);
    var buf: [1024]u8 = undefined;
    var n: usize = 0;
    n += emitPushBytes(buf[n..], preimage);
    n += emitPushBytes(buf[n..], &region);
    @memcpy(buf[n .. n + clen], code[0..clen]);
    n += clen;
    var p = pda_mod.PDA.init(2_000_000);
    var arena_buf: [65536]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = executor.ExecutionContext.init(&p, &arena);
    try ctx.loadScript(buf[0..n]);
    _ = try executor.execute(&ctx);
    const top = try p.speek();
    return pda_mod.cellToI64(top.data[0..top.len]);
}

test "compileCovenantBody: evolve region + bind to hashOutputs, end-to-end" {
    var cov: [260]u8 = undefined;
    for (0..cov.len) |i| cov[i] = @intCast((i * 17 + 3) & 0xff);

    const region = [_]u8{ 130, 0, 130, 0, 200, 0, 0, 0, 0 };
    const cnt = nbrCount(region);
    var next_region = region;
    next_region[4] = expectedRule(region[4], cnt, cnt); // the body computes this itself

    // hashOutputs commits to the CORRECTLY-evolved covenant → body accepts
    var pre: [1024]u8 = undefined;
    const plen = buildCovenantPreimage(&pre, region, next_region, &cov);
    try std.testing.expectEqual(@as(i64, 1), try runBody(pre[0..plen], region));

    // hashOutputs commits to a WRONG next state → body computes the right one →
    // mismatch → abort.
    var wrong = next_region;
    wrong[4] +%= 1;
    var pre2: [1024]u8 = undefined;
    const plen2 = buildCovenantPreimage(&pre2, region, wrong, &cov);
    try std.testing.expectError(error.verify_failed, runBody(pre2[0..plen2], region));
}

// ════════════════════════════════════════════════════════════════════════════
// LOCAL covenant chain — the cell_N → cell_{N+1} covenant advancing the MNCA as
// a chain of spends VALIDATED BY OUR ENGINE (no OP_PUSH_TX, no bignum, no
// broadcast). This is the SPV-on-every-spend model: each tick is a transition
// our i64 engine enforces (compileCovenantBody = transition + bind). Runs
// identically on Mac / Pi / C6 — bignum is irrelevant to the automaton.
// ════════════════════════════════════════════════════════════════════════════

test "covenant chain advances the MNCA N ticks locally, engine-validated" {
    var cov: [260]u8 = undefined;
    for (0..cov.len) |i| cov[i] = @intCast((i * 13 + 7) & 0xff);

    // Seed: alive centre, NO alive neighbours → decays 64/tick to 0.
    var region = [_]u8{ 0, 0, 0, 0, 200, 0, 0, 0, 0 };
    const expect_centres = [_]u8{ 136, 72, 8, 0, 0 }; // 200 →136→72→8→0→0

    for (expect_centres) |want_centre| {
        const cnt = nbrCount(region);
        var next_region = region;
        next_region[4] = expectedRule(region[4], cnt, cnt);

        // Build the spend's preimage (committing to the evolved covenant) and let
        // the engine VALIDATE the transition — exactly what an SPV-checked spend does.
        var pre: [1024]u8 = undefined;
        const plen = buildCovenantPreimage(&pre, region, next_region, &cov);
        try std.testing.expectEqual(@as(i64, 1), try runBody(pre[0..plen], region));

        try std.testing.expectEqual(want_centre, next_region[4]); // CA evolved as expected
        region = next_region; // re-spend forward
    }
}

```
