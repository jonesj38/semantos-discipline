---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_assemble_tx.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.980371+00:00
---

# core/cell-engine/src/host_assemble_tx.zig

```zig
// PR-5b: host_assemble_tx — serialize a complete BSV transaction from
// (version, inputs[], outputs[], nLockTime) per LOCKSCRIPT-CLEAVAGE.md §8.2.
//
// This is the final hostcall in the cap.tx.build surface. After contribution
// signatures have been gathered (PR-5: host_verify_partial_sig) and lock /
// unlock scripts resolved from templates (PR-4: host_resolve_script_template),
// the assembler hostcall stitches the pieces into a wire-format tx ready for
// `host_broadcast_arc` (a later PR).
//
// Serialization shape (BSV consensus tx format, identical to pre-segwit
// Bitcoin):
//
//   version             4 bytes  LE
//   input_count         varint
//   inputs[]:
//     prev_txid         32 bytes (already in little-endian wire order)
//     prev_vout         4 bytes  LE
//     script_len        varint
//     unlockScript      bytes
//     sequence          4 bytes  LE
//   output_count        varint
//   outputs[]:
//     value             8 bytes  LE  (satoshis)
//     script_len        varint
//     lockScript        bytes
//   nLockTime           4 bytes  LE
//
// The hostcall does not interpret scripts — it accepts them as opaque byte
// slices. Scripts MUST already be consensus-subset (verified by the
// assembler / `host_resolve_script_template`). Validating script bytes here
// would duplicate the cleavage guard and conflate responsibilities; we trust
// the caller to have funnelled the bytes through the appropriate template
// resolution hostcall.
//
// Capability: `cap.tx.build` — same gate as `host_resolve_script_template`.
// The whole "build a candidate tx" surface shares one capability so a
// cartridge that's permitted to compose templates is also permitted to
// finalize them.

const std = @import("std");
const host = @import("host");

/// One transaction input. `prev_txid` is in wire (little-endian) order —
/// caller is responsible for byte reversal if they're working with a
/// big-endian human-readable txid string.
pub const Input = struct {
    prev_txid: [32]u8,
    prev_vout: u32,
    /// Already-resolved unlock script bytes. Caller must have validated
    /// consensus-subset upstream.
    unlock_script: []const u8,
    /// nSequence. 0xFFFFFFFF disables nLockTime semantics for the input.
    sequence: u32 = 0xFFFFFFFF,
};

/// One transaction output.
pub const Output = struct {
    /// Value in satoshis.
    value: u64,
    /// Already-resolved lock script bytes. Caller must have validated
    /// consensus-subset upstream.
    lock_script: []const u8,
};

/// Per-invocation context. Brain populates fields, invokes the hostcall,
/// then reads `output_buffer[0..output_len]` on success.
pub const Context = struct {
    /// Transaction version field. BSV consensus accepts versions 1 and 2;
    /// the field is informational at consensus level. Defaults to 1.
    version: u32 = 1,
    inputs: []const Input,
    outputs: []const Output,
    /// nLockTime field. Interpreted as block height if < 500_000_000,
    /// else unix timestamp. Per the cleavage invariant we treat it as an
    /// opaque u32; consensus-level enforcement is the network's job.
    n_lock_time: u32 = 0,

    /// Caller-owned buffer the handler writes the serialized tx into.
    /// Size MUST be at least the predicted serialized length (use
    /// `predictSize` to pre-compute). On RC_BUFFER_TOO_SMALL the buffer
    /// contents are undefined; on RC_OK, bytes 0..output_len are valid.
    output_buffer: []u8,
    output_len: usize = 0,
    output_valid: bool = false,
    last_error: u32 = 0,
};

/// Return codes.
pub const RC_OK: u32 = 0;
pub const RC_NO_INPUTS: u32 = 1; // inputs.len == 0 — every BSV tx needs ≥1 input
pub const RC_NO_OUTPUTS: u32 = 2; // outputs.len == 0 — every BSV tx needs ≥1 output
pub const RC_BUFFER_TOO_SMALL: u32 = 3; // output_buffer.len < predicted size
pub const RC_INTERNAL_ERROR: u32 = 4; // should never happen — keeps a stable code if it does

/// Predict the serialized tx length without actually writing bytes. Lets
/// callers size `output_buffer` exactly. Always succeeds (no error
/// paths) — empty inputs/outputs just produce small predictions; the
/// `RC_NO_*` checks live in the handler, not here.
pub fn predictSize(ctx: *const Context) usize {
    var n: usize = 4; // version
    n += varintLen(ctx.inputs.len);
    for (ctx.inputs) |inp| {
        n += 32; // prev_txid
        n += 4; // prev_vout
        n += varintLen(inp.unlock_script.len);
        n += inp.unlock_script.len;
        n += 4; // sequence
    }
    n += varintLen(ctx.outputs.len);
    for (ctx.outputs) |out| {
        n += 8; // value
        n += varintLen(out.lock_script.len);
        n += out.lock_script.len;
    }
    n += 4; // nLockTime
    return n;
}

/// Registered handler. Writes the serialized tx into ctx.output_buffer
/// and sets ctx.output_len + ctx.output_valid on success.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    if (ctx.inputs.len == 0) {
        ctx.output_valid = false;
        ctx.last_error = RC_NO_INPUTS;
        return RC_NO_INPUTS;
    }
    if (ctx.outputs.len == 0) {
        ctx.output_valid = false;
        ctx.last_error = RC_NO_OUTPUTS;
        return RC_NO_OUTPUTS;
    }

    const needed = predictSize(ctx);
    if (ctx.output_buffer.len < needed) {
        ctx.output_valid = false;
        ctx.last_error = RC_BUFFER_TOO_SMALL;
        return RC_BUFFER_TOO_SMALL;
    }

    var w: usize = 0;
    writeU32LE(ctx.output_buffer[w..], ctx.version);
    w += 4;

    w += writeVarint(ctx.output_buffer[w..], ctx.inputs.len);
    for (ctx.inputs) |inp| {
        @memcpy(ctx.output_buffer[w .. w + 32], &inp.prev_txid);
        w += 32;
        writeU32LE(ctx.output_buffer[w..], inp.prev_vout);
        w += 4;
        w += writeVarint(ctx.output_buffer[w..], inp.unlock_script.len);
        if (inp.unlock_script.len > 0) {
            @memcpy(ctx.output_buffer[w .. w + inp.unlock_script.len], inp.unlock_script);
            w += inp.unlock_script.len;
        }
        writeU32LE(ctx.output_buffer[w..], inp.sequence);
        w += 4;
    }

    w += writeVarint(ctx.output_buffer[w..], ctx.outputs.len);
    for (ctx.outputs) |out| {
        writeU64LE(ctx.output_buffer[w..], out.value);
        w += 8;
        w += writeVarint(ctx.output_buffer[w..], out.lock_script.len);
        if (out.lock_script.len > 0) {
            @memcpy(ctx.output_buffer[w .. w + out.lock_script.len], out.lock_script);
            w += out.lock_script.len;
        }
    }

    writeU32LE(ctx.output_buffer[w..], ctx.n_lock_time);
    w += 4;

    std.debug.assert(w == needed);

    ctx.output_len = w;
    ctx.output_valid = true;
    ctx.last_error = RC_OK;
    return RC_OK;
}

/// Register `host_assemble_tx` with the cell-engine host registry.
/// Brain calls this once at boot.
pub fn register() !void {
    try host.registerHostCall("host_assemble_tx", handle);
}

// ── Byte-level helpers ────────────────────────────────────────────────

inline fn writeU32LE(dst: []u8, v: u32) void {
    dst[0] = @intCast(v & 0xFF);
    dst[1] = @intCast((v >> 8) & 0xFF);
    dst[2] = @intCast((v >> 16) & 0xFF);
    dst[3] = @intCast((v >> 24) & 0xFF);
}

inline fn writeU64LE(dst: []u8, v: u64) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        dst[i] = @intCast((v >> @intCast(i * 8)) & 0xFF);
    }
}

/// Bitcoin/BSV varint encoding length for `n`.
fn varintLen(n: usize) usize {
    if (n < 0xFD) return 1;
    if (n <= 0xFFFF) return 3;
    if (n <= 0xFFFFFFFF) return 5;
    return 9;
}

/// Write a varint to `dst`; returns bytes written.
fn writeVarint(dst: []u8, n: usize) usize {
    if (n < 0xFD) {
        dst[0] = @intCast(n);
        return 1;
    }
    if (n <= 0xFFFF) {
        dst[0] = 0xFD;
        dst[1] = @intCast(n & 0xFF);
        dst[2] = @intCast((n >> 8) & 0xFF);
        return 3;
    }
    if (n <= 0xFFFFFFFF) {
        dst[0] = 0xFE;
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            dst[1 + i] = @intCast((n >> @intCast(i * 8)) & 0xFF);
        }
        return 5;
    }
    dst[0] = 0xFF;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        dst[1 + i] = @intCast((n >> @intCast(i * 8)) & 0xFF);
    }
    return 9;
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "varint: single byte" {
    var buf: [9]u8 = undefined;
    try testing.expectEqual(@as(usize, 1), writeVarint(&buf, 0));
    try testing.expectEqual(@as(u8, 0), buf[0]);
    try testing.expectEqual(@as(usize, 1), writeVarint(&buf, 0xFC));
    try testing.expectEqual(@as(u8, 0xFC), buf[0]);
}

test "varint: 3-byte" {
    var buf: [9]u8 = undefined;
    try testing.expectEqual(@as(usize, 3), writeVarint(&buf, 0xFD));
    try testing.expectEqual(@as(u8, 0xFD), buf[0]);
    try testing.expectEqual(@as(u8, 0xFD), buf[1]);
    try testing.expectEqual(@as(u8, 0x00), buf[2]);

    try testing.expectEqual(@as(usize, 3), writeVarint(&buf, 0xFFFF));
    try testing.expectEqual(@as(u8, 0xFD), buf[0]);
    try testing.expectEqual(@as(u8, 0xFF), buf[1]);
    try testing.expectEqual(@as(u8, 0xFF), buf[2]);
}

test "varint: 5-byte" {
    var buf: [9]u8 = undefined;
    try testing.expectEqual(@as(usize, 5), writeVarint(&buf, 0x10000));
    try testing.expectEqual(@as(u8, 0xFE), buf[0]);
    try testing.expectEqual(@as(u8, 0x00), buf[1]);
    try testing.expectEqual(@as(u8, 0x00), buf[2]);
    try testing.expectEqual(@as(u8, 0x01), buf[3]);
    try testing.expectEqual(@as(u8, 0x00), buf[4]);
}

test "handle: empty inputs → RC_NO_INPUTS" {
    host.resetRegistryForTest();
    try register();

    var buf: [256]u8 = undefined;
    const outputs = [_]Output{.{ .value = 100, .lock_script = &[_]u8{ 0x76, 0xA9 } }};
    var ctx: Context = .{
        .inputs = &[_]Input{},
        .outputs = &outputs,
        .output_buffer = &buf,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_NO_INPUTS, rc);
    try testing.expect(!ctx.output_valid);
}

test "handle: empty outputs → RC_NO_OUTPUTS" {
    host.resetRegistryForTest();
    try register();

    var buf: [256]u8 = undefined;
    const inputs = [_]Input{.{
        .prev_txid = [_]u8{0xAA} ** 32,
        .prev_vout = 0,
        .unlock_script = &[_]u8{},
    }};
    var ctx: Context = .{
        .inputs = &inputs,
        .outputs = &[_]Output{},
        .output_buffer = &buf,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_NO_OUTPUTS, rc);
    try testing.expect(!ctx.output_valid);
}

test "handle: undersized output buffer → RC_BUFFER_TOO_SMALL" {
    host.resetRegistryForTest();
    try register();

    var buf: [10]u8 = undefined; // too small
    const inputs = [_]Input{.{
        .prev_txid = [_]u8{0xAA} ** 32,
        .prev_vout = 0,
        .unlock_script = &[_]u8{},
    }};
    const outputs = [_]Output{.{ .value = 100, .lock_script = &[_]u8{ 0x76, 0xA9 } }};
    var ctx: Context = .{
        .inputs = &inputs,
        .outputs = &outputs,
        .output_buffer = &buf,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_BUFFER_TOO_SMALL, rc);
    try testing.expect(!ctx.output_valid);
}

test "handle: minimal 1-in 1-out tx serializes deterministically" {
    host.resetRegistryForTest();
    try register();

    var buf: [256]u8 = undefined;
    const inputs = [_]Input{.{
        .prev_txid = [_]u8{0xAB} ** 32,
        .prev_vout = 1,
        .unlock_script = &[_]u8{ 0x47, 0x30, 0x44 }, // 3 bogus sig bytes
        .sequence = 0xFFFFFFFE,
    }};
    const outputs = [_]Output{.{
        .value = 12345,
        .lock_script = &[_]u8{ 0x76, 0xA9, 0x14 }, // 3 bogus pkh prefix bytes
    }};
    var ctx: Context = .{
        .version = 2,
        .inputs = &inputs,
        .outputs = &outputs,
        .n_lock_time = 0,
        .output_buffer = &buf,
    };

    const needed = predictSize(&ctx);
    // 4 (version) + 1 (input_count) + 32 + 4 + 1 (script_len) + 3 + 4 (sequence)
    //   = 49
    // + 1 (output_count) + 8 + 1 (script_len) + 3
    //   = 13
    // + 4 (nLockTime)
    // = 4 + 1 + 32 + 4 + 1 + 3 + 4 + 1 + 8 + 1 + 3 + 4 = 66
    try testing.expectEqual(@as(usize, 66), needed);

    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_OK, rc);
    try testing.expect(ctx.output_valid);
    try testing.expectEqual(@as(usize, 66), ctx.output_len);

    // Spot-check the wire bytes.
    // version (LE u32 = 2): 02 00 00 00
    try testing.expectEqual(@as(u8, 0x02), buf[0]);
    try testing.expectEqual(@as(u8, 0x00), buf[1]);
    try testing.expectEqual(@as(u8, 0x00), buf[2]);
    try testing.expectEqual(@as(u8, 0x00), buf[3]);
    // input_count varint: 01
    try testing.expectEqual(@as(u8, 0x01), buf[4]);
    // prev_txid: 32× 0xAB
    var i: usize = 0;
    while (i < 32) : (i += 1) try testing.expectEqual(@as(u8, 0xAB), buf[5 + i]);
    // prev_vout (LE u32 = 1)
    try testing.expectEqual(@as(u8, 0x01), buf[37]);
    try testing.expectEqual(@as(u8, 0x00), buf[38]);
    try testing.expectEqual(@as(u8, 0x00), buf[39]);
    try testing.expectEqual(@as(u8, 0x00), buf[40]);
    // unlock_script length varint: 03
    try testing.expectEqual(@as(u8, 0x03), buf[41]);
    // unlock_script bytes
    try testing.expectEqual(@as(u8, 0x47), buf[42]);
    try testing.expectEqual(@as(u8, 0x30), buf[43]);
    try testing.expectEqual(@as(u8, 0x44), buf[44]);
    // sequence (LE u32 = 0xFFFFFFFE): FE FF FF FF
    try testing.expectEqual(@as(u8, 0xFE), buf[45]);
    try testing.expectEqual(@as(u8, 0xFF), buf[46]);
    try testing.expectEqual(@as(u8, 0xFF), buf[47]);
    try testing.expectEqual(@as(u8, 0xFF), buf[48]);
    // output_count varint: 01
    try testing.expectEqual(@as(u8, 0x01), buf[49]);
    // value (LE u64 = 12345 = 0x3039): 39 30 00 00 00 00 00 00
    try testing.expectEqual(@as(u8, 0x39), buf[50]);
    try testing.expectEqual(@as(u8, 0x30), buf[51]);
    try testing.expectEqual(@as(u8, 0x00), buf[52]);
    // lock_script length varint: 03
    try testing.expectEqual(@as(u8, 0x03), buf[58]);
    try testing.expectEqual(@as(u8, 0x76), buf[59]);
    try testing.expectEqual(@as(u8, 0xA9), buf[60]);
    try testing.expectEqual(@as(u8, 0x14), buf[61]);
    // nLockTime (LE u32 = 0): 00 00 00 00
    try testing.expectEqual(@as(u8, 0x00), buf[62]);
    try testing.expectEqual(@as(u8, 0x00), buf[63]);
    try testing.expectEqual(@as(u8, 0x00), buf[64]);
    try testing.expectEqual(@as(u8, 0x00), buf[65]);
}

test "handle: nLockTime preserved" {
    host.resetRegistryForTest();
    try register();

    var buf: [256]u8 = undefined;
    const inputs = [_]Input{.{
        .prev_txid = [_]u8{0} ** 32,
        .prev_vout = 0,
        .unlock_script = &[_]u8{},
    }};
    const outputs = [_]Output{.{ .value = 0, .lock_script = &[_]u8{} }};
    var ctx: Context = .{
        .inputs = &inputs,
        .outputs = &outputs,
        .n_lock_time = 0x12345678,
        .output_buffer = &buf,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_OK, rc);

    // Last 4 bytes: 78 56 34 12 (LE)
    const n = ctx.output_len;
    try testing.expectEqual(@as(u8, 0x78), buf[n - 4]);
    try testing.expectEqual(@as(u8, 0x56), buf[n - 3]);
    try testing.expectEqual(@as(u8, 0x34), buf[n - 2]);
    try testing.expectEqual(@as(u8, 0x12), buf[n - 1]);
}

test "handle: multi-input multi-output varint counts" {
    host.resetRegistryForTest();
    try register();

    // 3 inputs, 2 outputs — exercises varint single-byte path for counts
    // and validates predictSize sums per-element bytes correctly.
    var buf: [1024]u8 = undefined;
    const inputs = [_]Input{
        .{ .prev_txid = [_]u8{0x01} ** 32, .prev_vout = 0, .unlock_script = &[_]u8{0xAA} },
        .{ .prev_txid = [_]u8{0x02} ** 32, .prev_vout = 1, .unlock_script = &[_]u8{ 0xBB, 0xCC } },
        .{ .prev_txid = [_]u8{0x03} ** 32, .prev_vout = 2, .unlock_script = &[_]u8{} },
    };
    const outputs = [_]Output{
        .{ .value = 1000, .lock_script = &[_]u8{ 0x6A, 0x01, 0xFF } }, // OP_RETURN
        .{ .value = 2000, .lock_script = &[_]u8{0x76} },
    };
    var ctx: Context = .{
        .inputs = &inputs,
        .outputs = &outputs,
        .output_buffer = &buf,
    };

    const expected = 4 // version
    + 1 // input_count = 3
    + (32 + 4 + 1 + 1 + 4) // input 0
    + (32 + 4 + 1 + 2 + 4) // input 1
    + (32 + 4 + 1 + 0 + 4) // input 2
    + 1 // output_count = 2
    + (8 + 1 + 3) // output 0
    + (8 + 1 + 1) // output 1
    + 4; // nLockTime
    try testing.expectEqual(@as(usize, expected), predictSize(&ctx));

    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_OK, rc);
    try testing.expectEqual(@as(usize, expected), ctx.output_len);

    // input_count immediately after version
    try testing.expectEqual(@as(u8, 0x03), buf[4]);
}

test "handle: varint upgrade at 253-input boundary" {
    // Stress test: 253 inputs → input_count varint switches from 1 → 3 bytes.
    host.resetRegistryForTest();
    try register();

    const allocator = std.testing.allocator;
    const N: usize = 253;
    const inputs = try allocator.alloc(Input, N);
    defer allocator.free(inputs);
    for (inputs, 0..) |*inp, i| {
        inp.* = .{
            .prev_txid = [_]u8{@intCast(i & 0xFF)} ** 32,
            .prev_vout = @intCast(i),
            .unlock_script = &[_]u8{},
        };
    }
    const outputs = [_]Output{.{ .value = 1, .lock_script = &[_]u8{} }};

    var ctx: Context = .{
        .inputs = inputs,
        .outputs = &outputs,
        .output_buffer = &[_]u8{}, // probe with predictSize first
    };
    const needed = predictSize(&ctx);

    const buf = try allocator.alloc(u8, needed);
    defer allocator.free(buf);
    ctx.output_buffer = buf;

    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(RC_OK, rc);
    try testing.expectEqual(needed, ctx.output_len);

    // input_count at offset 4 is the 3-byte varint 0xFD 0xFD 0x00 (253 LE)
    try testing.expectEqual(@as(u8, 0xFD), buf[4]);
    try testing.expectEqual(@as(u8, 0xFD), buf[5]);
    try testing.expectEqual(@as(u8, 0x00), buf[6]);
}

```
