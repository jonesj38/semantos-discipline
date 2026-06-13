---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/sighash.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.403246+00:00
---

# src/ffi/sighash.zig

```zig
// Semantos FFI — Native SIGHASH computation
// Adapted from packages/cell-engine/src/sighash.zig for the C ABI layer.
// Uses native std.crypto.hash.sha2.Sha256 instead of host.hash256 WASM extern.
// Adds computeSigHashOriginal() for Chronicle-era pre-BIP143 algorithm.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ── SIGHASH type flags ──

pub const SIGHASH_ALL: u8 = 0x01;
pub const SIGHASH_NONE: u8 = 0x02;
pub const SIGHASH_SINGLE: u8 = 0x03;
pub const SIGHASH_ANYONECANPAY: u8 = 0x80;
pub const SIGHASH_FORKID: u8 = 0x40;
pub const SIGHASH_MASK: u8 = 0x1F;

pub const MAX_INPUTS: usize = 256;
pub const MAX_OUTPUTS: usize = 256;

pub const SighashAlgorithm = enum {
    bip143,
    original,
};

pub const SigHashError = error{
    invalid_sighash,
    no_tx_context,
    invalid_script,
    buffer_overflow,
};

pub const TxInput = struct {
    prev_txid: [32]u8,
    prev_vout: u32,
    script_sig: [1024]u8,
    script_sig_len: u32,
    sequence: u32,
};

pub const TxOutput = struct {
    value: u64,
    script: [10000]u8,
    script_len: u32,
};

pub const TxContext = struct {
    version: u32,
    locktime: u32,
    current_input_index: u32,
    input_value: u64,

    inputs: [MAX_INPUTS]TxInput,
    input_count: u32,
    outputs: [MAX_OUTPUTS]TxOutput,
    output_count: u32,

    pub fn init() TxContext {
        return .{
            .version = 0,
            .locktime = 0,
            .current_input_index = 0,
            .input_value = 0,
            .inputs = undefined,
            .input_count = 0,
            .outputs = undefined,
            .output_count = 0,
        };
    }
};

/// Native double-SHA256 (replaces host.hash256 WASM extern)
fn hash256(data: []const u8, out: *[32]u8) void {
    var first: [32]u8 = undefined;
    Sha256.hash(data, &first, .{});
    Sha256.hash(&first, out, .{});
}

/// Compute BIP143 SIGHASH preimage hash.
/// Returns the 32-byte double-SHA256 of the preimage.
pub fn computeSigHash(
    tx: *const TxContext,
    subscript: []const u8,
    sighash_type: u8,
) SigHashError![32]u8 {
    if (sighash_type & SIGHASH_FORKID == 0) return error.invalid_sighash;

    const base_type = sighash_type & SIGHASH_MASK;
    const anyone_can_pay = (sighash_type & SIGHASH_ANYONECANPAY) != 0;

    var preimage: [10200]u8 = undefined;
    var pos: usize = 0;

    // 1. nVersion
    std.mem.writeInt(u32, preimage[pos..][0..4], tx.version, .little);
    pos += 4;

    // 2. hashPrevouts
    if (!anyone_can_pay) {
        var hasher = Sha256.init(.{});
        var i: u32 = 0;
        while (i < tx.input_count) : (i += 1) {
            hasher.update(&tx.inputs[i].prev_txid);
            var vout_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &vout_buf, tx.inputs[i].prev_vout, .little);
            hasher.update(&vout_buf);
        }
        var first_hash: [32]u8 = undefined;
        hasher.final(&first_hash);
        var hasher2 = Sha256.init(.{});
        hasher2.update(&first_hash);
        hasher2.final(preimage[pos..][0..32]);
    } else {
        @memset(preimage[pos..][0..32], 0);
    }
    pos += 32;

    // 3. hashSequence
    if (!anyone_can_pay and base_type == SIGHASH_ALL) {
        var hasher = Sha256.init(.{});
        var i: u32 = 0;
        while (i < tx.input_count) : (i += 1) {
            var seq_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &seq_buf, tx.inputs[i].sequence, .little);
            hasher.update(&seq_buf);
        }
        var first_hash: [32]u8 = undefined;
        hasher.final(&first_hash);
        var hasher2 = Sha256.init(.{});
        hasher2.update(&first_hash);
        hasher2.final(preimage[pos..][0..32]);
    } else {
        @memset(preimage[pos..][0..32], 0);
    }
    pos += 32;

    // 4. outpoint of current input (36B)
    const cur_input = &tx.inputs[tx.current_input_index];
    @memcpy(preimage[pos..][0..32], &cur_input.prev_txid);
    pos += 32;
    std.mem.writeInt(u32, preimage[pos..][0..4], cur_input.prev_vout, .little);
    pos += 4;

    // 5. scriptCode (varint length + script bytes)
    pos += writeVarInt(preimage[pos..], subscript.len);
    @memcpy(preimage[pos..][0..subscript.len], subscript);
    pos += subscript.len;

    // 6. value (8B LE)
    std.mem.writeInt(u64, preimage[pos..][0..8], tx.input_value, .little);
    pos += 8;

    // 7. nSequence of current input (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], cur_input.sequence, .little);
    pos += 4;

    // 8. hashOutputs
    if (base_type == SIGHASH_ALL) {
        var hasher = Sha256.init(.{});
        var i: u32 = 0;
        while (i < tx.output_count) : (i += 1) {
            var val_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &val_buf, tx.outputs[i].value, .little);
            hasher.update(&val_buf);
            var vi_buf: [9]u8 = undefined;
            const vi_len = writeVarInt(&vi_buf, tx.outputs[i].script_len);
            hasher.update(vi_buf[0..vi_len]);
            hasher.update(tx.outputs[i].script[0..tx.outputs[i].script_len]);
        }
        var first_hash: [32]u8 = undefined;
        hasher.final(&first_hash);
        var hasher2 = Sha256.init(.{});
        hasher2.update(&first_hash);
        hasher2.final(preimage[pos..][0..32]);
    } else if (base_type == SIGHASH_SINGLE and tx.current_input_index < tx.output_count) {
        const out = &tx.outputs[tx.current_input_index];
        var hasher = Sha256.init(.{});
        var val_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &val_buf, out.value, .little);
        hasher.update(&val_buf);
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, out.script_len);
        hasher.update(vi_buf[0..vi_len]);
        hasher.update(out.script[0..out.script_len]);
        var first_hash: [32]u8 = undefined;
        hasher.final(&first_hash);
        var hasher2 = Sha256.init(.{});
        hasher2.update(&first_hash);
        hasher2.final(preimage[pos..][0..32]);
    } else {
        @memset(preimage[pos..][0..32], 0);
    }
    pos += 32;

    // 9. nLockTime (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], tx.locktime, .little);
    pos += 4;

    // 10. nHashType (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], @as(u32, sighash_type), .little);
    pos += 4;

    // Final: double-SHA256
    var result: [32]u8 = undefined;
    hash256(preimage[0..pos], &result);
    return result;
}

/// Compute original (pre-BIP143) SIGHASH hash.
/// Restored by Chronicle mandatory upgrade (April 7 2026).
/// MUST NOT be called with FORKID flag — FORKID is BIP143-specific.
///
/// Algorithm: serialize the full TX with modifications per SIGHASH type, then double-SHA256.
/// - Blank all input scripts except current input (which gets subscript)
/// - SIGHASH_ALL: keep all outputs
/// - SIGHASH_NONE: clear all outputs, set sequence=0 on all other inputs
/// - SIGHASH_SINGLE: keep only the output at current_input_index, blank others; set sequence=0 on other inputs
/// - ANYONECANPAY: keep only the current input
pub fn computeSigHashOriginal(
    tx: *const TxContext,
    subscript: []const u8,
    sighash_type: u8,
) SigHashError![32]u8 {
    // FORKID is BIP143-specific — reject
    if (sighash_type & SIGHASH_FORKID != 0) return error.invalid_sighash;

    const base_type = sighash_type & SIGHASH_MASK;
    const anyone_can_pay = (sighash_type & SIGHASH_ANYONECANPAY) != 0;

    // Validate base type
    if (base_type != SIGHASH_ALL and base_type != SIGHASH_NONE and base_type != SIGHASH_SINGLE)
        return error.invalid_sighash;

    // SIGHASH_SINGLE with input index >= output count is a special case in original Bitcoin:
    // it returns a hash of 0x0000...0001
    if (base_type == SIGHASH_SINGLE and tx.current_input_index >= tx.output_count) {
        var result: [32]u8 = .{0} ** 32;
        result[0] = 1;
        return result;
    }

    // Streaming hash to avoid massive buffer allocation
    var hasher = Sha256.init(.{});

    // version
    var ver_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &ver_buf, tx.version, .little);
    hasher.update(&ver_buf);

    // inputs
    if (anyone_can_pay) {
        // Only the current input
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, 1);
        hasher.update(vi_buf[0..vi_len]);

        hasher.update(&tx.inputs[tx.current_input_index].prev_txid);
        var vout_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &vout_buf, tx.inputs[tx.current_input_index].prev_vout, .little);
        hasher.update(&vout_buf);

        // subscript
        var ss_vi: [9]u8 = undefined;
        const ss_vi_len = writeVarInt(&ss_vi, subscript.len);
        hasher.update(ss_vi[0..ss_vi_len]);
        hasher.update(subscript);

        // sequence
        var seq_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &seq_buf, tx.inputs[tx.current_input_index].sequence, .little);
        hasher.update(&seq_buf);
    } else {
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, tx.input_count);
        hasher.update(vi_buf[0..vi_len]);

        var i: u32 = 0;
        while (i < tx.input_count) : (i += 1) {
            hasher.update(&tx.inputs[i].prev_txid);
            var vout_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &vout_buf, tx.inputs[i].prev_vout, .little);
            hasher.update(&vout_buf);

            if (i == tx.current_input_index) {
                // Current input gets subscript
                var ss_vi: [9]u8 = undefined;
                const ss_vi_len = writeVarInt(&ss_vi, subscript.len);
                hasher.update(ss_vi[0..ss_vi_len]);
                hasher.update(subscript);
            } else {
                // Other inputs get empty script
                hasher.update(&[_]u8{0x00});
            }

            // Sequence: for NONE and SINGLE, other inputs get 0
            if (i != tx.current_input_index and (base_type == SIGHASH_NONE or base_type == SIGHASH_SINGLE)) {
                hasher.update(&[_]u8{ 0, 0, 0, 0 });
            } else {
                var seq_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &seq_buf, tx.inputs[i].sequence, .little);
                hasher.update(&seq_buf);
            }
        }
    }

    // outputs
    if (base_type == SIGHASH_NONE) {
        hasher.update(&[_]u8{0x00}); // varint 0
    } else if (base_type == SIGHASH_SINGLE) {
        // Outputs 0..current_input_index: blank (value=-1, empty script) for indices < current
        const out_count = tx.current_input_index + 1;
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, out_count);
        hasher.update(vi_buf[0..vi_len]);

        var i: u32 = 0;
        while (i < out_count) : (i += 1) {
            if (i < tx.current_input_index) {
                // Blank output: value = -1 (0xffffffffffffffff), empty script
                hasher.update(&[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
                hasher.update(&[_]u8{0x00}); // varint 0 script
            } else {
                // The matching output
                var val_buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &val_buf, tx.outputs[i].value, .little);
                hasher.update(&val_buf);
                var s_vi: [9]u8 = undefined;
                const s_vi_len = writeVarInt(&s_vi, tx.outputs[i].script_len);
                hasher.update(s_vi[0..s_vi_len]);
                hasher.update(tx.outputs[i].script[0..tx.outputs[i].script_len]);
            }
        }
    } else {
        // SIGHASH_ALL: all outputs
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, tx.output_count);
        hasher.update(vi_buf[0..vi_len]);

        var i: u32 = 0;
        while (i < tx.output_count) : (i += 1) {
            var val_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &val_buf, tx.outputs[i].value, .little);
            hasher.update(&val_buf);
            var s_vi: [9]u8 = undefined;
            const s_vi_len = writeVarInt(&s_vi, tx.outputs[i].script_len);
            hasher.update(s_vi[0..s_vi_len]);
            hasher.update(tx.outputs[i].script[0..tx.outputs[i].script_len]);
        }
    }

    // locktime
    var lt_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &lt_buf, tx.locktime, .little);
    hasher.update(&lt_buf);

    // sighash type (4 bytes LE)
    var ht_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &ht_buf, @as(u32, sighash_type), .little);
    hasher.update(&ht_buf);

    // Double-SHA256
    var first: [32]u8 = undefined;
    hasher.final(&first);
    var result: [32]u8 = undefined;
    Sha256.hash(&first, &result, .{});
    return result;
}

/// Parse raw Bitcoin transaction bytes into TxContext.
pub fn parseTxContext(
    raw: []const u8,
    input_index: u32,
    input_value: u64,
    ctx: *TxContext,
) SigHashError!void {
    if (raw.len < 10) return error.invalid_script;
    var pos: usize = 0;

    // Version
    ctx.version = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;

    // Input count
    const input_count_result = readVarInt(raw[pos..]);
    if (input_count_result.bytes == 0) return error.invalid_script;
    ctx.input_count = @intCast(input_count_result.value);
    pos += input_count_result.bytes;

    if (ctx.input_count > MAX_INPUTS) return error.invalid_script;

    // Parse inputs
    var i: u32 = 0;
    while (i < ctx.input_count) : (i += 1) {
        if (pos + 36 > raw.len) return error.invalid_script;
        @memcpy(&ctx.inputs[i].prev_txid, raw[pos..][0..32]);
        pos += 32;
        ctx.inputs[i].prev_vout = std.mem.readInt(u32, raw[pos..][0..4], .little);
        pos += 4;

        const script_len_result = readVarInt(raw[pos..]);
        if (script_len_result.bytes == 0) return error.invalid_script;
        const script_len: u32 = @intCast(script_len_result.value);
        pos += script_len_result.bytes;
        ctx.inputs[i].script_sig_len = script_len;
        if (script_len > 0 and script_len <= 1024) {
            @memcpy(ctx.inputs[i].script_sig[0..script_len], raw[pos..][0..script_len]);
        }
        pos += script_len;

        if (pos + 4 > raw.len) return error.invalid_script;
        ctx.inputs[i].sequence = std.mem.readInt(u32, raw[pos..][0..4], .little);
        pos += 4;
    }

    // Output count
    const output_count_result = readVarInt(raw[pos..]);
    if (output_count_result.bytes == 0) return error.invalid_script;
    ctx.output_count = @intCast(output_count_result.value);
    pos += output_count_result.bytes;

    if (ctx.output_count > MAX_OUTPUTS) return error.invalid_script;

    // Parse outputs
    i = 0;
    while (i < ctx.output_count) : (i += 1) {
        if (pos + 8 > raw.len) return error.invalid_script;
        ctx.outputs[i].value = std.mem.readInt(u64, raw[pos..][0..8], .little);
        pos += 8;

        const out_script_len_result = readVarInt(raw[pos..]);
        if (out_script_len_result.bytes == 0) return error.invalid_script;
        const out_script_len: u32 = @intCast(out_script_len_result.value);
        pos += out_script_len_result.bytes;

        if (out_script_len > 10000) return error.invalid_script;
        if (out_script_len > 0) {
            @memcpy(ctx.outputs[i].script[0..out_script_len], raw[pos..][0..out_script_len]);
        }
        ctx.outputs[i].script_len = out_script_len;
        pos += out_script_len;
    }

    // Locktime
    if (pos + 4 > raw.len) return error.invalid_script;
    ctx.locktime = std.mem.readInt(u32, raw[pos..][0..4], .little);

    ctx.current_input_index = input_index;
    ctx.input_value = input_value;
}

/// Compute txid (double-SHA256 of raw TX bytes, in internal byte order)
pub fn computeTxId(raw_tx: []const u8) [32]u8 {
    var result: [32]u8 = undefined;
    hash256(raw_tx, &result);
    return result;
}

// ── Helpers (public for tx_builder) ──

pub fn writeVarInt(buf: []u8, val: usize) usize {
    if (val < 0xFD) {
        buf[0] = @truncate(val);
        return 1;
    } else if (val <= 0xFFFF) {
        buf[0] = 0xFD;
        std.mem.writeInt(u16, buf[1..][0..2], @intCast(val), .little);
        return 3;
    } else if (val <= 0xFFFFFFFF) {
        buf[0] = 0xFE;
        std.mem.writeInt(u32, buf[1..][0..4], @intCast(val), .little);
        return 5;
    } else {
        buf[0] = 0xFF;
        std.mem.writeInt(u64, buf[1..][0..8], @intCast(val), .little);
        return 9;
    }
}

pub const VarIntResult = struct { value: u64, bytes: usize };

pub fn readVarInt(data: []const u8) VarIntResult {
    if (data.len == 0) return .{ .value = 0, .bytes = 0 };
    const first = data[0];
    if (first < 0xFD) return .{ .value = first, .bytes = 1 };
    if (first == 0xFD and data.len >= 3) return .{ .value = std.mem.readInt(u16, data[1..][0..2], .little), .bytes = 3 };
    if (first == 0xFE and data.len >= 5) return .{ .value = std.mem.readInt(u32, data[1..][0..4], .little), .bytes = 5 };
    if (first == 0xFF and data.len >= 9) return .{ .value = std.mem.readInt(u64, data[1..][0..8], .little), .bytes = 9 };
    return .{ .value = 0, .bytes = 0 };
}

// ── Tests ──

test "BIP143 computeSigHash requires FORKID" {
    var ctx = TxContext.init();
    ctx.version = 1;
    ctx.input_count = 1;
    ctx.inputs[0] = .{
        .prev_txid = .{0} ** 32,
        .prev_vout = 0,
        .script_sig = .{0} ** 1024,
        .script_sig_len = 0,
        .sequence = 0xffffffff,
    };
    ctx.output_count = 1;
    ctx.outputs[0] = .{
        .value = 1000,
        .script = .{0} ** 10000,
        .script_len = 25,
    };
    ctx.locktime = 0;
    ctx.current_input_index = 0;
    ctx.input_value = 5000;

    // Without FORKID → error
    const result = computeSigHash(&ctx, &[_]u8{0x76}, SIGHASH_ALL);
    try std.testing.expectError(error.invalid_sighash, result);

    // With FORKID → success
    const hash = try computeSigHash(&ctx, &[_]u8{0x76}, SIGHASH_ALL | SIGHASH_FORKID);
    // Should produce a non-zero hash
    var all_zero = true;
    for (hash) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "computeSigHashOriginal rejects FORKID" {
    var ctx = TxContext.init();
    ctx.version = 1;
    ctx.input_count = 1;
    ctx.inputs[0] = .{
        .prev_txid = .{0} ** 32,
        .prev_vout = 0,
        .script_sig = .{0} ** 1024,
        .script_sig_len = 0,
        .sequence = 0xffffffff,
    };
    ctx.output_count = 1;
    ctx.outputs[0] = .{
        .value = 1000,
        .script = .{0} ** 10000,
        .script_len = 25,
    };

    const result = computeSigHashOriginal(&ctx, &[_]u8{0x76}, SIGHASH_ALL | SIGHASH_FORKID);
    try std.testing.expectError(error.invalid_sighash, result);
}

test "computeSigHashOriginal ALL produces non-zero hash" {
    var ctx = TxContext.init();
    ctx.version = 1;
    ctx.input_count = 1;
    ctx.inputs[0] = .{
        .prev_txid = .{0xaa} ** 32,
        .prev_vout = 0,
        .script_sig = .{0} ** 1024,
        .script_sig_len = 0,
        .sequence = 0xffffffff,
    };
    ctx.output_count = 1;
    ctx.outputs[0] = .{
        .value = 1000,
        .script = .{0} ** 10000,
        .script_len = 25,
    };
    ctx.current_input_index = 0;
    ctx.input_value = 5000;

    const hash = try computeSigHashOriginal(&ctx, &[_]u8{0x76}, SIGHASH_ALL);
    var all_zero = true;
    for (hash) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "writeVarInt/readVarInt round-trip" {
    var buf: [9]u8 = undefined;

    // Small value
    const len1 = writeVarInt(&buf, 42);
    try std.testing.expectEqual(@as(usize, 1), len1);
    const r1 = readVarInt(&buf);
    try std.testing.expectEqual(@as(u64, 42), r1.value);

    // 2-byte value
    const len2 = writeVarInt(&buf, 300);
    try std.testing.expectEqual(@as(usize, 3), len2);
    const r2 = readVarInt(&buf);
    try std.testing.expectEqual(@as(u64, 300), r2.value);

    // 4-byte value
    const len3 = writeVarInt(&buf, 70000);
    try std.testing.expectEqual(@as(usize, 5), len3);
    const r3 = readVarInt(&buf);
    try std.testing.expectEqual(@as(u64, 70000), r3.value);
}

test "parseTxContext round-trip minimal TX" {
    // Build a minimal TX: version=1, 1 input, 1 output, locktime=0
    var raw: [100]u8 = .{0} ** 100;
    var pos: usize = 0;

    // version
    std.mem.writeInt(u32, raw[pos..][0..4], 1, .little);
    pos += 4;

    // 1 input
    raw[pos] = 1;
    pos += 1;
    // prev_txid (32 bytes of 0xaa)
    @memset(raw[pos..][0..32], 0xaa);
    pos += 32;
    // prev_vout
    std.mem.writeInt(u32, raw[pos..][0..4], 0, .little);
    pos += 4;
    // script_sig length = 0
    raw[pos] = 0;
    pos += 1;
    // sequence
    std.mem.writeInt(u32, raw[pos..][0..4], 0xffffffff, .little);
    pos += 4;

    // 1 output
    raw[pos] = 1;
    pos += 1;
    // value
    std.mem.writeInt(u64, raw[pos..][0..8], 1000, .little);
    pos += 8;
    // script length = 1
    raw[pos] = 1;
    pos += 1;
    // script byte
    raw[pos] = 0x76;
    pos += 1;

    // locktime
    std.mem.writeInt(u32, raw[pos..][0..4], 0, .little);
    pos += 4;

    var ctx = TxContext.init();
    try parseTxContext(raw[0..pos], 0, 5000, &ctx);

    try std.testing.expectEqual(@as(u32, 1), ctx.version);
    try std.testing.expectEqual(@as(u32, 1), ctx.input_count);
    try std.testing.expectEqual(@as(u32, 1), ctx.output_count);
    try std.testing.expectEqual(@as(u32, 0), ctx.locktime);
    try std.testing.expectEqual(@as(u64, 1000), ctx.outputs[0].value);
}

```
