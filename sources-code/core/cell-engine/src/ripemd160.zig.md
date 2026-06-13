---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/ripemd160.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.973822+00:00
---

# core/cell-engine/src/ripemd160.zig

```zig
// Pure Zig RIPEMD-160 implementation
// Used by embedded profile for real HASH160 (SHA256 + RIPEMD160)
// without requiring BSVZ dependency.
//
// Reference: https://homes.esat.kuleuven.be/~bosMDselaer/ripemd160.html

const std = @import("std");

/// Compute RIPEMD-160 hash of input data.
pub fn hash(data: []const u8, out: *[20]u8) void {
    var state = State.init();
    state.update(data);
    state.final(out);
}

const State = struct {
    h: [5]u32,
    buf: [64]u8,
    buf_len: usize,
    total_len: u64,

    fn init() State {
        return .{
            .h = .{
                0x67452301,
                0xEFCDAB89,
                0x98BADCFE,
                0x10325476,
                0xC3D2E1F0,
            },
            .buf = undefined,
            .buf_len = 0,
            .total_len = 0,
        };
    }

    fn update(self: *State, data: []const u8) void {
        var input = data;
        self.total_len += input.len;

        // Fill buffer first
        if (self.buf_len > 0) {
            const needed = 64 - self.buf_len;
            if (input.len < needed) {
                @memcpy(self.buf[self.buf_len..][0..input.len], input);
                self.buf_len += input.len;
                return;
            }
            @memcpy(self.buf[self.buf_len..][0..needed], input[0..needed]);
            self.processBlock(&self.buf);
            self.buf_len = 0;
            input = input[needed..];
        }

        // Process full blocks
        while (input.len >= 64) {
            self.processBlock(input[0..64]);
            input = input[64..];
        }

        // Buffer remainder
        if (input.len > 0) {
            @memcpy(self.buf[0..input.len], input);
            self.buf_len = input.len;
        }
    }

    fn final(self: *State, out: *[20]u8) void {
        const total_bits = self.total_len * 8;

        // Padding
        self.buf[self.buf_len] = 0x80;
        self.buf_len += 1;

        if (self.buf_len > 56) {
            @memset(self.buf[self.buf_len..64], 0);
            self.processBlock(&self.buf);
            self.buf_len = 0;
        }
        @memset(self.buf[self.buf_len..56], 0);

        // Append length in bits (little-endian)
        std.mem.writeInt(u64, self.buf[56..64], total_bits, .little);
        self.processBlock(&self.buf);

        // Output hash (little-endian)
        for (0..5) |i| {
            std.mem.writeInt(u32, out[i * 4 ..][0..4], self.h[i], .little);
        }
    }

    fn processBlock(self: *State, block: *const [64]u8) void {
        var x: [16]u32 = undefined;
        for (0..16) |i| {
            x[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .little);
        }

        var al = self.h[0];
        var bl = self.h[1];
        var cl = self.h[2];
        var dl = self.h[3];
        var el = self.h[4];

        var ar = self.h[0];
        var br = self.h[1];
        var cr = self.h[2];
        var dr = self.h[3];
        var er = self.h[4];

        // Left rounds
        inline for (0..80) |j| {
            const f_val = comptime f(j);
            const k_val = comptime kl(j);
            const r_idx = comptime rl(j);
            const s_val = comptime sl(j);

            var t = al +% ff(f_val, bl, cl, dl) +% x[r_idx] +% k_val;
            t = std.math.rotl(u32, t, s_val) +% el;
            al = el;
            el = dl;
            dl = std.math.rotl(u32, cl, 10);
            cl = bl;
            bl = t;
        }

        // Right rounds
        inline for (0..80) |j| {
            const f_val = comptime f(79 - j);
            const k_val = comptime kr(j);
            const r_idx = comptime rr(j);
            const s_val = comptime sr(j);

            var t = ar +% ff(f_val, br, cr, dr) +% x[r_idx] +% k_val;
            t = std.math.rotl(u32, t, s_val) +% er;
            ar = er;
            er = dr;
            dr = std.math.rotl(u32, cr, 10);
            cr = br;
            br = t;
        }

        const t = self.h[1] +% cl +% dr;
        self.h[1] = self.h[2] +% dl +% er;
        self.h[2] = self.h[3] +% el +% ar;
        self.h[3] = self.h[4] +% al +% br;
        self.h[4] = self.h[0] +% bl +% cr;
        self.h[0] = t;
    }
};

// Boolean functions
fn f(j: usize) u3 {
    if (j < 16) return 0;
    if (j < 32) return 1;
    if (j < 48) return 2;
    if (j < 64) return 3;
    return 4;
}

fn ff(sel: u3, x: u32, y: u32, z: u32) u32 {
    return switch (sel) {
        0 => x ^ y ^ z,
        1 => (x & y) | (~x & z),
        2 => (x | ~y) ^ z,
        3 => (x & z) | (y & ~z),
        4 => x ^ (y | ~z),
        else => unreachable,
    };
}

// Left round constants
fn kl(j: usize) u32 {
    if (j < 16) return 0x00000000;
    if (j < 32) return 0x5A827999;
    if (j < 48) return 0x6ED9EBA1;
    if (j < 64) return 0x8F1BBCDC;
    return 0xA953FD4E;
}

// Right round constants
fn kr(j: usize) u32 {
    if (j < 16) return 0x50A28BE6;
    if (j < 32) return 0x5C4DD124;
    if (j < 48) return 0x6D703EF3;
    if (j < 64) return 0x7A6D76E9;
    return 0x00000000;
}

// Left message word selection
fn rl(j: usize) u4 {
    const table = [80]u4{
        // Round 1
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        // Round 2
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        // Round 3
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        // Round 4
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        // Round 5
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    };
    return table[j];
}

// Right message word selection
fn rr(j: usize) u4 {
    const table = [80]u4{
        // Round 1
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        // Round 2
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        // Round 3
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        // Round 4
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        // Round 5
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    };
    return table[j];
}

// Left rotation amounts
fn sl(j: usize) u5 {
    const table = [80]u5{
        // Round 1
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        // Round 2
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        // Round 3
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        // Round 4
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        // Round 5
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    };
    return table[j];
}

// Right rotation amounts
fn sr(j: usize) u5 {
    const table = [80]u5{
        // Round 1
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        // Round 2
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        // Round 3
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        // Round 4
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        // Round 5
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    };
    return table[j];
}

// ── Tests ──

test "RIPEMD160 of empty string" {
    var out: [20]u8 = undefined;
    hash("", &out);
    const expected = [_]u8{
        0x9c, 0x11, 0x85, 0xa5, 0xc5, 0xe9, 0xfc, 0x54, 0x61, 0x28,
        0x08, 0x97, 0x7e, 0xe8, 0xf5, 0x48, 0xb2, 0x25, 0x8d, 0x31,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "RIPEMD160 of 'a'" {
    var out: [20]u8 = undefined;
    hash("a", &out);
    const expected = [_]u8{
        0x0b, 0xdc, 0x9d, 0x2d, 0x25, 0x6b, 0x3e, 0xe9, 0xda, 0xae,
        0x34, 0x7b, 0xe6, 0xf4, 0xdc, 0x83, 0x5a, 0x46, 0x7f, 0xfe,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "RIPEMD160 of 'abc'" {
    var out: [20]u8 = undefined;
    hash("abc", &out);
    const expected = [_]u8{
        0x8e, 0xb2, 0x08, 0xf7, 0xe0, 0x5d, 0x98, 0x7a, 0x9b, 0x04,
        0x4a, 0x8e, 0x98, 0xc6, 0xb0, 0x87, 0xf1, 0x5a, 0x0b, 0xfc,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "RIPEMD160 of 'message digest'" {
    var out: [20]u8 = undefined;
    hash("message digest", &out);
    const expected = [_]u8{
        0x5d, 0x06, 0x89, 0xef, 0x49, 0xd2, 0xfa, 0xe5, 0x72, 0xb8,
        0x81, 0xb1, 0x23, 0xa8, 0x5f, 0xfa, 0x21, 0x59, 0x5f, 0x36,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "RIPEMD160 of 'abcdefghijklmnopqrstuvwxyz'" {
    var out: [20]u8 = undefined;
    hash("abcdefghijklmnopqrstuvwxyz", &out);
    const expected = [_]u8{
        0xf7, 0x1c, 0x27, 0x10, 0x9c, 0x69, 0x2c, 0x1b, 0x56, 0xbb,
        0xdc, 0xeb, 0x5b, 0x9d, 0x28, 0x65, 0xb3, 0x70, 0x8d, 0xbc,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

```
