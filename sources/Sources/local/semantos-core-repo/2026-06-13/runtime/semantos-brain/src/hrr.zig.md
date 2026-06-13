---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/hrr.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.223752+00:00
---

# runtime/semantos-brain/src/hrr.zig

```zig
// hrr.zig — D-SRS-hrr-zig: Holographic Reduced Representation (Plate 1995)
//
// Zig port of core/hrr/src/role-vectors.ts, D=256 f32 variant.
//
// Provides:
//   seedVec(seed: []const u8, out: *Vec)    — SHA-256-seeded unit vector
//   bind(a, b, out: *Vec)                   — circular convolution (⊛)
//   unbind(a, b, out: *Vec)                 — circular correlation (≈ inverse of bind)
//   cosine(a, b) f32                        — cosine similarity ∈ [-1, 1]
//   typepathVec(path, out: *Vec)            — unit vector for a dotted type path
//   similarity(a_path, b_path) f32         — fast similarity for two type paths
//
// D=256 (not 1024) — 4× smaller than the TS oracle, fits comfortably in the
// H5's L1 cache (256 × 4 B = 1 KB per vector). Cosine similarity is still
// reliable for type-path neighbourhood detection at this dimension.
//
// Algorithm fidelity: same radix-2 DIT FFT, same conjugate IFFT, same
// circConv/circCorr formulas as the TS oracle. The seed expansion differs
// slightly (we emit 8 f32 floats per SHA-256 block by reading int32-BE / 2^31,
// matching the TS `h.readInt32BE(j*4) / 0x80000000` normalisation).

const std = @import("std");
const math = std.math;

// ── Dimensionality ────────────────────────────────────────────────────────────

/// Vector dimension. Must be a power of 2.
pub const D: usize = 256;

/// A D-dimensional real vector (f32 for Pi cache efficiency).
pub const Vec = [D]f32;

// ── Scratch buffers (module-level BSS; caller must not use concurrently) ──────

var g_re_a: [D]f32 = [_]f32{0} ** D;
var g_im_a: [D]f32 = [_]f32{0} ** D;
var g_re_b: [D]f32 = [_]f32{0} ** D;
var g_im_b: [D]f32 = [_]f32{0} ** D;

// ── Radix-2 DIT FFT (in-place, real → complex) ────────────────────────────────
//
// Direct port of role-vectors.ts fft():
//   bit-reversal permutation → butterfly stages (length 2 → D).
//
// Uses standard Cooley-Tukey conventions (negative-exponent forward FFT).

fn fftInPlace(re: []f32, im: []f32) void {
    const n = re.len;
    // Bit-reversal permutation.
    var j: usize = 0;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var bit: usize = n >> 1;
        while (j & bit != 0) : (bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            const tmp_r = re[i]; re[i] = re[j]; re[j] = tmp_r;
            const tmp_i = im[i]; im[i] = im[j]; im[j] = tmp_i;
        }
    }
    // Butterfly stages.
    var len: usize = 2;
    while (len <= n) : (len <<= 1) {
        const ang: f64 = (-2.0 * math.pi) / @as(f64, @floatFromInt(len));
        const w_re: f32 = @floatCast(math.cos(ang));
        const w_im: f32 = @floatCast(math.sin(ang));
        const half = len >> 1;
        var ii: usize = 0;
        while (ii < n) : (ii += len) {
            var cur_re: f32 = 1;
            var cur_im: f32 = 0;
            var k: usize = 0;
            while (k < half) : (k += 1) {
                const u_re = re[ii + k];
                const u_im = im[ii + k];
                const v_re = re[ii + k + half] * cur_re - im[ii + k + half] * cur_im;
                const v_im = re[ii + k + half] * cur_im + im[ii + k + half] * cur_re;
                re[ii + k] = u_re + v_re;
                im[ii + k] = u_im + v_im;
                re[ii + k + half] = u_re - v_re;
                im[ii + k + half] = u_im - v_im;
                const n_re = cur_re * w_re - cur_im * w_im;
                cur_im = cur_re * w_im + cur_im * w_re;
                cur_re = n_re;
            }
        }
    }
}

// IFFT via conjugate trick (TS: negate im, fft, then divide by n and negate im again).
fn ifftInPlace(re: []f32, im: []f32) void {
    const n = re.len;
    var i: usize = 0;
    while (i < n) : (i += 1) im[i] = -im[i];
    fftInPlace(re, im);
    const scale: f32 = 1.0 / @as(f32, @floatFromInt(n));
    i = 0;
    while (i < n) : (i += 1) { re[i] *= scale; im[i] = (-im[i]) * scale; }
}

// ── Circular convolution & correlation ────────────────────────────────────────

/// out = circConv(a, b)  — the HRR "bind" operation (a ⊛ b).
pub fn bind(a: *const Vec, b: *const Vec, out: *Vec) void {
    @memcpy(&g_re_a, a);
    @memset(&g_im_a, 0);
    @memcpy(&g_re_b, b);
    @memset(&g_im_b, 0);
    fftInPlace(&g_re_a, &g_im_a);
    fftInPlace(&g_re_b, &g_im_b);
    for (0..D) |k| {
        const ar = g_re_a[k]; const ai = g_im_a[k];
        const br = g_re_b[k]; const bi = g_im_b[k];
        g_re_a[k] = ar * br - ai * bi;
        g_im_a[k] = ar * bi + ai * br;
    }
    ifftInPlace(&g_re_a, &g_im_a);
    @memcpy(out, &g_re_a);
}

/// out = circCorr(a, b)  — approximate inverse of bind: unbind(bind(r,f), r) ≈ f.
pub fn unbind(a: *const Vec, b: *const Vec, out: *Vec) void {
    @memcpy(&g_re_a, a);
    @memset(&g_im_a, 0);
    @memcpy(&g_re_b, b);
    @memset(&g_im_b, 0);
    fftInPlace(&g_re_a, &g_im_a);
    fftInPlace(&g_re_b, &g_im_b);
    // correlation = conj(A) * B
    for (0..D) |k| {
        const ar = g_re_a[k]; const ai = g_im_a[k];
        const br = g_re_b[k]; const bi = g_im_b[k];
        g_re_a[k] = ar * br + ai * bi;   // conj(a).re * b.re - conj(a).im * b.im
        g_im_a[k] = ar * bi - ai * br;
    }
    ifftInPlace(&g_re_a, &g_im_a);
    @memcpy(out, &g_re_a);
}

// ── L2 norm + normalise ────────────────────────────────────────────────────────

pub fn l2norm(a: *const Vec) f32 {
    var s: f32 = 0;
    for (a) |v| s += v * v;
    return @sqrt(s);
}

pub fn l2normalize(a: *Vec) void {
    const n = l2norm(a);
    if (n < 1e-8) { @memset(a, 0); return; }
    for (a) |*v| v.* /= n;
}

// ── Cosine similarity ─────────────────────────────────────────────────────────

pub fn cosine(a: *const Vec, b: *const Vec) f32 {
    var s: f32 = 0;
    for (0..D) |i| s += a[i] * b[i];
    return @max(-1.0, @min(1.0, s));
}

// ── Seed vector ───────────────────────────────────────────────────────────────
//
// Deterministic L2-unit vector from `seed` string.
// Matches role-vectors.ts seedVec():
//   for block in 0..(D/8):
//     sha256_bytes = SHA-256(`${seed}:${block}`)
//     for j in 0..8:
//       v[block*8+j] = read_int32_be(sha256_bytes, j*4) / 2^31
//   L2-normalise v.
//
// D=256 needs 32 SHA-256 calls (32×8=256 components).

pub fn seedVec(seed: []const u8, out: *Vec) void {
    const blocks = D / 8; // 32 for D=256
    var block_label_buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < blocks) : (i += 1) {
        const label = std.fmt.bufPrint(&block_label_buf, "{s}:{d}", .{ seed, i }) catch {
            @memset(out, 0);
            return;
        };
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(label, &digest, .{});
        for (0..8) |j| {
            const int_val = std.mem.readInt(i32, digest[j * 4 ..][0..4], .big);
            out[i * 8 + j] = @as(f32, @floatFromInt(int_val)) / 0x80000000;
        }
    }
    l2normalize(out);
}

// ── Type-path vector ──────────────────────────────────────────────────────────
//
// A type path like "mnca.tile.tick" is encoded as the superposition of
// bigram bindings: bind(seg[0], seg[1]) + bind(seg[1], seg[2]) + ...
// Superposition is then L2-normalised to produce a unit vector.
//
// This matches the TypeScript hrrSimilarity in mesh-typepath-fuzzer.ts which
// uses Jaccard of bigrams, but the Zig version goes through actual HRR vectors
// for richer geometry (e.g. cosine similarity ≠ 0 for partially overlapping paths).
//
// For paths with 1 segment, seedVec(seg[0]) is used directly (no bigrams).
// For paths with 0 segments, the zero vector is returned.

var g_seg_vecs: [32]Vec = undefined; // up to 32 segments (D-SRS type paths are short)
var g_tmp_vec: Vec = undefined;

pub fn typepathVec(path: []const u8, out: *Vec) void {
    @memset(out, 0);

    // Split path on '.' and seed one Vec per segment.
    var seg_count: usize = 0;
    var it = std.mem.splitScalar(u8, path, '.');
    while (it.next()) |seg| {
        if (seg_count >= g_seg_vecs.len) break;
        seedVec(seg, &g_seg_vecs[seg_count]);
        seg_count += 1;
    }
    if (seg_count == 0) return;
    if (seg_count == 1) {
        @memcpy(out, &g_seg_vecs[0]);
        return;
    }

    // Superpose bigram bindings.
    for (0..seg_count - 1) |k| {
        bind(&g_seg_vecs[k], &g_seg_vecs[k + 1], &g_tmp_vec);
        for (0..D) |d| out[d] += g_tmp_vec[d];
    }
    l2normalize(out);
}

// ── Convenience: similarity between two type paths ────────────────────────────

var g_vec_a: Vec = undefined;
var g_vec_b: Vec = undefined;

/// Cosine similarity ∈ [-1, 1] between type paths `a` and `b`.
/// Not thread-safe (uses module-level scratch buffers).
pub fn similarity(path_a: []const u8, path_b: []const u8) f32 {
    typepathVec(path_a, &g_vec_a);
    typepathVec(path_b, &g_vec_b);
    return cosine(&g_vec_a, &g_vec_b);
}

// ── Inline tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "seedVec: unit norm" {
    var v: Vec = undefined;
    seedVec("mnca.tile.tick", &v);
    const n = l2norm(&v);
    try testing.expectApproxEqAbs(1.0, n, 0.001);
}

test "seedVec: distinct seeds → near-orthogonal" {
    var a: Vec = undefined;
    var b: Vec = undefined;
    seedVec("mnca.tile.tick", &a);
    seedVec("fuzz.tile.explore", &b);
    const c = cosine(&a, &b);
    // D=256 random unit vectors have |cosine| ≈ 1/√D ≈ 0.063 expected.
    // Allow up to 0.15 to be safe (passes empirically with very high probability).
    try testing.expect(@abs(c) < 0.15);
}

test "bind then unbind roundtrip ≈ filler" {
    var role: Vec = undefined;
    var filler: Vec = undefined;
    var bound: Vec = undefined;
    var recovered: Vec = undefined;
    seedVec("role:kind", &role);
    seedVec("filler:tile", &filler);
    bind(&role, &filler, &bound);
    unbind(&role, &bound, &recovered);
    // The recovered vector should be close to filler (cosine ≥ 0.9 for D=256).
    const sim = cosine(&filler, &recovered);
    try testing.expect(sim > 0.85);
}

test "typepathVec: same path → cosine 1" {
    var a: Vec = undefined;
    var b: Vec = undefined;
    typepathVec("mnca.tile.tick", &a);
    typepathVec("mnca.tile.tick", &b);
    const c = cosine(&a, &b);
    try testing.expectApproxEqAbs(1.0, c, 0.001);
}

test "typepathVec: similar paths → higher cosine than dissimilar" {
    const sim_related = similarity("mnca.tile.tick", "mnca.tile.tock");
    const sim_unrelated = similarity("mnca.tile.tick", "fuzz.x.y.z");
    // "mnca.tile.tick" vs "mnca.tile.tock" share bigram (mnca, tile) — should be more similar.
    try testing.expect(sim_related > sim_unrelated);
}

test "typepathVec: single-segment path" {
    var v: Vec = undefined;
    typepathVec("tick", &v);
    const n = l2norm(&v);
    try testing.expectApproxEqAbs(1.0, n, 0.001);
}

```
