---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tx_builder.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.402605+00:00
---

# src/ffi/tx_builder.zig

```zig
// Semantos FFI — TxBuilder
// Constructs valid BSV wire-format transactions with multi-object output maps,
// overflow PushDrop continuations, OP_RETURN proof carriage, and dual SIGHASH.

const std = @import("std");
const sighash = @import("sighash");

// ── Constants ──

const MAX_INPUTS = sighash.MAX_INPUTS;
const MAX_OUTPUTS = sighash.MAX_OUTPUTS;
// PushDrop scripts: header(256) + payload(768) + path(~64) + hash(32) + output_map(2) + opcodes(~10) + pubkey(33) ≈ 1165
// With PUSHDATA overhead, 1500 is generous. Use 2048 to be safe.
const MAX_SCRIPT_SIZE = 2048;
const MAX_SERIALIZE_SIZE = 4 * 1024 * 1024; // 4MB

// ── Bitcoin Script opcodes ──

const OP_FALSE: u8 = 0x00;
const OP_RETURN: u8 = 0x6a;
const OP_DROP: u8 = 0x75;
const OP_2DROP: u8 = 0x6d;
const OP_CHECKSIG: u8 = 0xac;
const OP_PUSHDATA1: u8 = 0x4c;
const OP_PUSHDATA2: u8 = 0x4d;
const OP_PUSHDATA4: u8 = 0x4e;

// ── Cell constants (match packages/cell-engine/src/constants.zig) ──

pub const HEADER_SIZE: usize = 256;
pub const PAYLOAD_SIZE: usize = 768;
pub const CONTINUATION_HEADER_SIZE: usize = 8;
pub const CONTINUATION_PAYLOAD_SIZE: usize = 1016;

// ── Proof types (match multicell.zig cell types) ──

pub const PROOF_TYPE_BUMP: u8 = 1;
pub const PROOF_TYPE_ATOMIC_BEEF: u8 = 2;
pub const PROOF_TYPE_ENVELOPE: u8 = 3;

// ── Types ──

pub const OutputType = enum(u8) {
    primary = 0,
    overflow = 1,
    proof = 2,
    payment = 3,
};

pub const TxBuildInput = struct {
    prev_txid: [32]u8,
    prev_vout: u32,
    script_sig: [1024]u8,
    script_sig_len: u32,
    sequence: u32,
};

pub const TxBuildOutput = struct {
    value: u64,
    script_pubkey: [MAX_SCRIPT_SIZE]u8,
    script_pubkey_len: u32,
    output_type: OutputType,
    // For primary outputs: embedded in the script, but also cached here for fast walking
    overflow_count: u8,
    proof_count: u8,
};

pub const OutputSpan = struct {
    primary_index: u32,
    overflow_start: u32,
    overflow_count: u8,
    proof_start: u32,
    proof_count: u8,
};

pub const ContinuationHeader = struct {
    cell_type: u8, // BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3, DATA=4, STATE=5
    cell_index: u16, // 1-based (LE)
    total_cells: u16, // count of continuation cells (LE)
    payload_size: u16, // actual bytes (LE)
    reserved: u8, // always 0
};

pub const TxBuilderError = error{
    too_many_inputs,
    too_many_outputs,
    script_too_large,
    buffer_too_small,
    invalid_index,
    invalid_output_map,
    serialize_overflow,
};

pub const PrimaryIterator = struct {
    builder: *const TxBuilder,
    index: u32,

    pub fn next(self: *PrimaryIterator) ?u32 {
        while (self.index < self.builder.output_count) {
            const idx = self.index;
            const out = &self.builder.outputs[idx];
            if (out.output_type == .primary) {
                // Skip past this primary's overflow and proof outputs
                self.index = idx + 1 + @as(u32, out.overflow_count) + @as(u32, out.proof_count);
                return idx;
            }
            self.index += 1;
        }
        return null;
    }
};

// ── TxBuilder ──

pub const TxBuilder = struct {
    inputs: [MAX_INPUTS]TxBuildInput,
    input_count: u32,
    outputs: [MAX_OUTPUTS]TxBuildOutput,
    output_count: u32,
    version: u32,
    locktime: u32,

    pub fn init() TxBuilder {
        return .{
            .inputs = undefined,
            .input_count = 0,
            .outputs = undefined,
            .output_count = 0,
            .version = 1,
            .locktime = 0,
        };
    }

    pub fn addInput(self: *TxBuilder, prev_txid: [32]u8, prev_vout: u32, sequence: u32) TxBuilderError!u32 {
        if (self.input_count >= MAX_INPUTS) return error.too_many_inputs;
        const idx = self.input_count;
        self.inputs[idx] = .{
            .prev_txid = prev_txid,
            .prev_vout = prev_vout,
            .script_sig = .{0} ** 1024,
            .script_sig_len = 0,
            .sequence = sequence,
        };
        self.input_count += 1;
        return idx;
    }

    /// Add a CellToken PushDrop primary output with embedded output_map.
    /// Layout: PUSH(header) PUSH(payload) PUSH(path) PUSH(hash) PUSH(output_map)
    ///         OP_DROP OP_2DROP OP_2DROP PUSH(pubkey) OP_CHECKSIG
    pub fn addCellTokenOutput(
        self: *TxBuilder,
        cell_header: []const u8,
        cell_payload: []const u8,
        semantic_path: []const u8,
        content_hash: [32]u8,
        owner_pubkey: [33]u8,
        value: u64,
        overflow_count: u8,
        proof_count: u8,
    ) TxBuilderError!u32 {
        if (self.output_count >= MAX_OUTPUTS) return error.too_many_outputs;

        var script: [MAX_SCRIPT_SIZE]u8 = .{0} ** MAX_SCRIPT_SIZE;
        var pos: usize = 0;

        // PUSH(cell_header)
        pos += pushData(script[pos..], cell_header);
        // PUSH(cell_payload)
        pos += pushData(script[pos..], cell_payload);
        // PUSH(semantic_path)
        pos += pushData(script[pos..], semantic_path);
        // PUSH(content_hash)
        pos += pushData(script[pos..], &content_hash);
        // PUSH(output_map [overflow_count, proof_count])
        pos += pushData(script[pos..], &[_]u8{ overflow_count, proof_count });
        // OP_DROP OP_2DROP OP_2DROP
        script[pos] = OP_DROP;
        pos += 1;
        script[pos] = OP_2DROP;
        pos += 1;
        script[pos] = OP_2DROP;
        pos += 1;
        // PUSH(owner_pubkey)
        pos += pushData(script[pos..], &owner_pubkey);
        // OP_CHECKSIG
        script[pos] = OP_CHECKSIG;
        pos += 1;

        if (pos > MAX_SCRIPT_SIZE) return error.script_too_large;

        const idx = self.output_count;
        self.outputs[idx] = .{
            .value = value,
            .script_pubkey = script,
            .script_pubkey_len = @intCast(pos),
            .output_type = .primary,
            .overflow_count = overflow_count,
            .proof_count = proof_count,
        };
        self.output_count += 1;
        return idx;
    }

    /// Add a PushDrop overflow continuation output matching multicell.zig format.
    /// Layout: PUSH(continuation_header_8) PUSH(continuation_payload) OP_DROP OP_DROP
    ///         PUSH(owner_pubkey) OP_CHECKSIG
    pub fn addOverflowOutput(
        self: *TxBuilder,
        cont_header: ContinuationHeader,
        continuation_payload: []const u8,
        owner_pubkey: [33]u8,
        value: u64,
    ) TxBuilderError!u32 {
        if (self.output_count >= MAX_OUTPUTS) return error.too_many_outputs;

        var script: [MAX_SCRIPT_SIZE]u8 = .{0} ** MAX_SCRIPT_SIZE;
        var pos: usize = 0;

        // Serialize ContinuationHeader to 8 bytes
        var header_bytes: [CONTINUATION_HEADER_SIZE]u8 = undefined;
        header_bytes[0] = cont_header.cell_type;
        std.mem.writeInt(u16, header_bytes[1..][0..2], cont_header.cell_index, .little);
        std.mem.writeInt(u16, header_bytes[3..][0..2], cont_header.total_cells, .little);
        std.mem.writeInt(u16, header_bytes[5..][0..2], cont_header.payload_size, .little);
        header_bytes[7] = cont_header.reserved;

        // PUSH(continuation_header)
        pos += pushData(script[pos..], &header_bytes);
        // PUSH(continuation_payload)
        pos += pushData(script[pos..], continuation_payload);
        // OP_DROP OP_DROP
        script[pos] = OP_DROP;
        pos += 1;
        script[pos] = OP_DROP;
        pos += 1;
        // PUSH(owner_pubkey)
        pos += pushData(script[pos..], &owner_pubkey);
        // OP_CHECKSIG
        script[pos] = OP_CHECKSIG;
        pos += 1;

        if (pos > MAX_SCRIPT_SIZE) return error.script_too_large;

        const idx = self.output_count;
        self.outputs[idx] = .{
            .value = value,
            .script_pubkey = script,
            .script_pubkey_len = @intCast(pos),
            .output_type = .overflow,
            .overflow_count = 0,
            .proof_count = 0,
        };
        self.output_count += 1;
        return idx;
    }

    /// Add OP_RETURN proof output.
    /// Layout: OP_FALSE OP_RETURN PUSH(proof_type) PUSH(proof_payload)
    pub fn addProofOutput(
        self: *TxBuilder,
        proof_type: u8,
        proof_payload: []const u8,
    ) TxBuilderError!u32 {
        if (self.output_count >= MAX_OUTPUTS) return error.too_many_outputs;

        var script: [MAX_SCRIPT_SIZE]u8 = .{0} ** MAX_SCRIPT_SIZE;
        var pos: usize = 0;

        script[pos] = OP_FALSE;
        pos += 1;
        script[pos] = OP_RETURN;
        pos += 1;
        pos += pushData(script[pos..], &[_]u8{proof_type});
        pos += pushData(script[pos..], proof_payload);

        if (pos > MAX_SCRIPT_SIZE) return error.script_too_large;

        const idx = self.output_count;
        self.outputs[idx] = .{
            .value = 0, // OP_RETURN outputs are unspendable
            .script_pubkey = script,
            .script_pubkey_len = @intCast(pos),
            .output_type = .proof,
            .overflow_count = 0,
            .proof_count = 0,
        };
        self.output_count += 1;
        return idx;
    }

    /// Add a generic payment output (P2PKH or any script).
    pub fn addPaymentOutput(
        self: *TxBuilder,
        value: u64,
        script_pubkey: []const u8,
    ) TxBuilderError!u32 {
        if (self.output_count >= MAX_OUTPUTS) return error.too_many_outputs;
        if (script_pubkey.len > MAX_SCRIPT_SIZE) return error.script_too_large;

        const idx = self.output_count;
        self.outputs[idx] = .{
            .value = value,
            .script_pubkey = .{0} ** MAX_SCRIPT_SIZE,
            .script_pubkey_len = @intCast(script_pubkey.len),
            .output_type = .payment,
            .overflow_count = 0,
            .proof_count = 0,
        };
        @memcpy(self.outputs[idx].script_pubkey[0..script_pubkey.len], script_pubkey);
        self.output_count += 1;
        return idx;
    }

    /// Serialize to BSV wire format.
    /// Returns number of bytes written into out_buf.
    pub fn serialize(self: *const TxBuilder, out_buf: []u8) TxBuilderError!usize {
        var pos: usize = 0;

        // version (4 LE)
        if (pos + 4 > out_buf.len) return error.buffer_too_small;
        std.mem.writeInt(u32, out_buf[pos..][0..4], self.version, .little);
        pos += 4;

        // varint(input_count)
        if (pos + 9 > out_buf.len) return error.buffer_too_small;
        pos += sighash.writeVarInt(out_buf[pos..], self.input_count);

        // inputs
        var i: u32 = 0;
        while (i < self.input_count) : (i += 1) {
            const inp = &self.inputs[i];
            const needed = 32 + 4 + 9 + inp.script_sig_len + 4;
            if (pos + needed > out_buf.len) return error.buffer_too_small;

            @memcpy(out_buf[pos..][0..32], &inp.prev_txid);
            pos += 32;
            std.mem.writeInt(u32, out_buf[pos..][0..4], inp.prev_vout, .little);
            pos += 4;
            pos += sighash.writeVarInt(out_buf[pos..], inp.script_sig_len);
            if (inp.script_sig_len > 0) {
                @memcpy(out_buf[pos..][0..inp.script_sig_len], inp.script_sig[0..inp.script_sig_len]);
                pos += inp.script_sig_len;
            }
            std.mem.writeInt(u32, out_buf[pos..][0..4], inp.sequence, .little);
            pos += 4;
        }

        // varint(output_count)
        if (pos + 9 > out_buf.len) return error.buffer_too_small;
        pos += sighash.writeVarInt(out_buf[pos..], self.output_count);

        // outputs
        i = 0;
        while (i < self.output_count) : (i += 1) {
            const out = &self.outputs[i];
            const needed = 8 + 9 + out.script_pubkey_len;
            if (pos + needed > out_buf.len) return error.buffer_too_small;

            std.mem.writeInt(u64, out_buf[pos..][0..8], out.value, .little);
            pos += 8;
            pos += sighash.writeVarInt(out_buf[pos..], out.script_pubkey_len);
            if (out.script_pubkey_len > 0) {
                @memcpy(out_buf[pos..][0..out.script_pubkey_len], out.script_pubkey[0..out.script_pubkey_len]);
                pos += out.script_pubkey_len;
            }
        }

        // locktime (4 LE)
        if (pos + 4 > out_buf.len) return error.buffer_too_small;
        std.mem.writeInt(u32, out_buf[pos..][0..4], self.locktime, .little);
        pos += 4;

        return pos;
    }

    /// Iterator over primary CellToken output indices.
    pub fn walkPrimaryOutputs(self: *const TxBuilder) PrimaryIterator {
        return .{ .builder = self, .index = 0 };
    }

    /// Get the output span (overflow/proof ranges) for a primary output.
    pub fn getObjectOutputSpan(self: *const TxBuilder, primary_index: u32) TxBuilderError!OutputSpan {
        if (primary_index >= self.output_count) return error.invalid_index;
        const out = &self.outputs[primary_index];
        if (out.output_type != .primary) return error.invalid_index;

        return .{
            .primary_index = primary_index,
            .overflow_start = primary_index + 1,
            .overflow_count = out.overflow_count,
            .proof_start = primary_index + 1 + @as(u32, out.overflow_count),
            .proof_count = out.proof_count,
        };
    }

    /// Convert builder state to a TxContext for SIGHASH computation.
    /// NOTE: Caller must ensure ctx lives long enough. Uses heap allocator to avoid stack overflow.
    pub fn fillTxContext(self: *const TxBuilder, input_index: u32, input_value: u64, ctx: *sighash.TxContext) void {
        ctx.version = self.version;
        ctx.locktime = self.locktime;
        ctx.current_input_index = input_index;
        ctx.input_value = input_value;
        ctx.input_count = self.input_count;
        ctx.output_count = self.output_count;

        var i: u32 = 0;
        while (i < self.input_count) : (i += 1) {
            ctx.inputs[i].prev_txid = self.inputs[i].prev_txid;
            ctx.inputs[i].prev_vout = self.inputs[i].prev_vout;
            @memcpy(ctx.inputs[i].script_sig[0..self.inputs[i].script_sig_len], self.inputs[i].script_sig[0..self.inputs[i].script_sig_len]);
            ctx.inputs[i].script_sig_len = self.inputs[i].script_sig_len;
            ctx.inputs[i].sequence = self.inputs[i].sequence;
        }
        i = 0;
        while (i < self.output_count) : (i += 1) {
            ctx.outputs[i].value = self.outputs[i].value;
            @memcpy(ctx.outputs[i].script[0..self.outputs[i].script_pubkey_len], self.outputs[i].script_pubkey[0..self.outputs[i].script_pubkey_len]);
            ctx.outputs[i].script_len = self.outputs[i].script_pubkey_len;
        }
    }

    /// Compute SIGHASH preimage for an input.
    /// Requires a pre-allocated TxContext to avoid stack overflow.
    pub fn computePreimage(
        self: *const TxBuilder,
        input_index: u32,
        subscript: []const u8,
        sighash_flags: u8,
        algorithm: sighash.SighashAlgorithm,
        input_value: u64,
        ctx: *sighash.TxContext,
    ) sighash.SigHashError![32]u8 {
        self.fillTxContext(input_index, input_value, ctx);
        return switch (algorithm) {
            .bip143 => sighash.computeSigHash(ctx, subscript, sighash_flags),
            .original => sighash.computeSigHashOriginal(ctx, subscript, sighash_flags),
        };
    }

    /// Insert P2PKH signature into an input.
    /// script_sig = PUSH(sig_der + sighash_byte) PUSH(pubkey)
    pub fn insertSignature(
        self: *TxBuilder,
        input_index: u32,
        sig_der: []const u8,
        sighash_byte: u8,
        pubkey: [33]u8,
    ) TxBuilderError!void {
        if (input_index >= self.input_count) return error.invalid_index;

        var script: [1024]u8 = .{0} ** 1024;
        var pos: usize = 0;

        // PUSH(sig_der + sighash_byte)
        const sig_total_len = sig_der.len + 1;
        pos += pushData(script[pos..], sig_der); // This pushes just sig_der
        // We need to include the sighash byte in the push. Redo:
        pos = 0;

        // Build sig+hashtype buffer
        var sig_with_hashtype: [128]u8 = undefined;
        @memcpy(sig_with_hashtype[0..sig_der.len], sig_der);
        sig_with_hashtype[sig_der.len] = sighash_byte;

        pos += pushData(script[pos..], sig_with_hashtype[0..sig_total_len]);
        pos += pushData(script[pos..], &pubkey);

        if (pos > 1024) return error.script_too_large;

        @memcpy(self.inputs[input_index].script_sig[0..pos], script[0..pos]);
        self.inputs[input_index].script_sig_len = @intCast(pos);
    }

    /// Insert arbitrary unlock script bytes (Chronicle-era scripted unlocks).
    pub fn insertUnlockScript(
        self: *TxBuilder,
        input_index: u32,
        script_bytes: []const u8,
    ) TxBuilderError!void {
        if (input_index >= self.input_count) return error.invalid_index;
        if (script_bytes.len > 1024) return error.script_too_large;
        @memcpy(self.inputs[input_index].script_sig[0..script_bytes.len], script_bytes);
        self.inputs[input_index].script_sig_len = @intCast(script_bytes.len);
    }

    /// Extract the output_map from a primary output's script.
    /// Parses the PushDrop script to find the 2-byte output_map push before OP_DROP sequence.
    pub fn extractOutputMap(script: []const u8) ?struct { overflow_count: u8, proof_count: u8 } {
        // PushDrop layout: PUSH(header) PUSH(payload) PUSH(path) PUSH(hash) PUSH(output_map)
        //                  OP_DROP OP_2DROP OP_2DROP PUSH(pubkey) OP_CHECKSIG
        // We need to skip 4 pushes, then read the 5th push (2 bytes).
        var pos: usize = 0;
        var push_count: usize = 0;

        while (pos < script.len and push_count < 5) {
            const skip_result = skipPush(script[pos..]);
            if (skip_result.data_len == 0 and skip_result.total_len == 0) break;

            push_count += 1;
            if (push_count == 5) {
                // This is the output_map push — should be 2 bytes
                if (skip_result.data_len == 2) {
                    const data_start = pos + skip_result.total_len - skip_result.data_len;
                    return .{
                        .overflow_count = script[data_start],
                        .proof_count = script[data_start + 1],
                    };
                }
                return null;
            }
            pos += skip_result.total_len;
        }
        return null;
    }
};

// ── Script push helpers ──

/// Encode a data push. Returns number of bytes written.
fn pushData(buf: []u8, data: []const u8) usize {
    var pos: usize = 0;
    if (data.len <= 75) {
        buf[pos] = @intCast(data.len);
        pos += 1;
    } else if (data.len <= 255) {
        buf[pos] = OP_PUSHDATA1;
        pos += 1;
        buf[pos] = @intCast(data.len);
        pos += 1;
    } else if (data.len <= 65535) {
        buf[pos] = OP_PUSHDATA2;
        pos += 1;
        std.mem.writeInt(u16, buf[pos..][0..2], @intCast(data.len), .little);
        pos += 2;
    } else {
        buf[pos] = OP_PUSHDATA4;
        pos += 1;
        std.mem.writeInt(u32, buf[pos..][0..4], @intCast(data.len), .little);
        pos += 4;
    }
    @memcpy(buf[pos..][0..data.len], data);
    pos += data.len;
    return pos;
}

/// Skip a push operation in script bytes. Returns total bytes consumed and data length.
fn skipPush(script: []const u8) struct { total_len: usize, data_len: usize } {
    if (script.len == 0) return .{ .total_len = 0, .data_len = 0 };
    const op = script[0];

    if (op == 0) return .{ .total_len = 1, .data_len = 0 };

    if (op >= 1 and op <= 75) {
        if (script.len < 1 + op) return .{ .total_len = 0, .data_len = 0 };
        return .{ .total_len = 1 + @as(usize, op), .data_len = @as(usize, op) };
    }
    if (op == OP_PUSHDATA1) {
        if (script.len < 2) return .{ .total_len = 0, .data_len = 0 };
        const len: usize = script[1];
        if (script.len < 2 + len) return .{ .total_len = 0, .data_len = 0 };
        return .{ .total_len = 2 + len, .data_len = len };
    }
    if (op == OP_PUSHDATA2) {
        if (script.len < 3) return .{ .total_len = 0, .data_len = 0 };
        const len: usize = std.mem.readInt(u16, script[1..][0..2], .little);
        if (script.len < 3 + len) return .{ .total_len = 0, .data_len = 0 };
        return .{ .total_len = 3 + len, .data_len = len };
    }
    if (op == OP_PUSHDATA4) {
        if (script.len < 5) return .{ .total_len = 0, .data_len = 0 };
        const len: usize = std.mem.readInt(u32, script[1..][0..4], .little);
        if (script.len < 5 + len) return .{ .total_len = 0, .data_len = 0 };
        return .{ .total_len = 5 + len, .data_len = len };
    }
    // Not a push opcode
    return .{ .total_len = 0, .data_len = 0 };
}

// ── Tests ──

const p2pkh_script = [_]u8{ 0x76, 0xa9, 0x14 } ++ [_]u8{0} ** 20 ++ [_]u8{ 0x88, 0xac };

test "T1: genesis TX with output_map [0,0] serialize/deserialize round-trip" {
    var builder = TxBuilder.init();

    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF; // magic
    var payload: [PAYLOAD_SIZE]u8 = .{0} ** PAYLOAD_SIZE;
    payload[0] = 0x42;
    const path = "test/genesis";
    const content_hash: [32]u8 = .{0xaa} ** 32;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02; // compressed pubkey prefix

    _ = try builder.addCellTokenOutput(&header, &payload, path, content_hash, pubkey, 1, 0, 0);

    // Serialize
    var buf: [64000]u8 = undefined;
    const len = try builder.serialize(&buf);
    try std.testing.expect(len > 0);

    // Deserialize via parseTxContext
    var ctx = sighash.TxContext.init();
    try sighash.parseTxContext(buf[0..len], 0, 0, &ctx);

    try std.testing.expectEqual(@as(u32, 1), ctx.version);
    try std.testing.expectEqual(@as(u32, 0), ctx.input_count);
    try std.testing.expectEqual(@as(u32, 1), ctx.output_count);
    try std.testing.expectEqual(@as(u64, 1), ctx.outputs[0].value);

    // Verify output_map is parseable from the script
    const script = ctx.outputs[0].script[0..ctx.outputs[0].script_len];
    const omap = TxBuilder.extractOutputMap(script);
    try std.testing.expect(omap != null);
    try std.testing.expectEqual(@as(u8, 0), omap.?.overflow_count);
    try std.testing.expectEqual(@as(u8, 0), omap.?.proof_count);
}

test "T2: spending TX wire format round-trip" {
    // Build genesis TX, serialize, get txid — then let builder go out of scope
    var genesis_buf: [64000]u8 = undefined;
    var genesis_len: usize = 0;
    var genesis_txid: [32]u8 = undefined;
    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF;
    var payload: [PAYLOAD_SIZE]u8 = .{0} ** PAYLOAD_SIZE;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    {
        var genesis = TxBuilder.init();
        _ = try genesis.addCellTokenOutput(&header, &payload, "test/path", .{0xbb} ** 32, pubkey, 1, 0, 0);
        genesis_len = try genesis.serialize(&genesis_buf);
        genesis_txid = sighash.computeTxId(genesis_buf[0..genesis_len]);
    }

    // Build spending TX (genesis builder is now out of scope)
    var spending = TxBuilder.init();
    _ = try spending.addInput(genesis_txid, 0, 0xffffffff);
    _ = try spending.addCellTokenOutput(&header, &payload, "test/path", .{0xcc} ** 32, pubkey, 1, 0, 0);

    var spend_buf: [64000]u8 = undefined;
    const spend_len = try spending.serialize(&spend_buf);

    // Deserialize and verify input references genesis
    var ctx = sighash.TxContext.init();
    try sighash.parseTxContext(spend_buf[0..spend_len], 0, 1, &ctx);
    try std.testing.expectEqual(@as(u32, 1), ctx.input_count);
    try std.testing.expectEqual(@as(u32, 1), ctx.output_count);
    try std.testing.expect(std.mem.eql(u8, &ctx.inputs[0].prev_txid, &genesis_txid));
    try std.testing.expectEqual(@as(u32, 0), ctx.inputs[0].prev_vout);
}

test "T3: TX with MAX_INPUTS serialises without overflow" {
    var builder = TxBuilder.init();
    var i: u32 = 0;
    while (i < MAX_INPUTS) : (i += 1) {
        var txid: [32]u8 = .{0} ** 32;
        txid[0] = @truncate(i);
        txid[1] = @truncate(i >> 8);
        _ = try builder.addInput(txid, 0, 0xffffffff);
    }

    // Add one output
    _ = try builder.addPaymentOutput(1000, &p2pkh_script);

    var buf: [64000]u8 = undefined;
    const len = try builder.serialize(&buf);
    try std.testing.expect(len > 0);

    var ctx = sighash.TxContext.init();
    try sighash.parseTxContext(buf[0..len], 0, 0, &ctx);
    try std.testing.expectEqual(@as(u32, 256), ctx.input_count);
}

test "T4: PushDrop output script layout with output_map" {
    var builder = TxBuilder.init();
    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF;
    var payload: [PAYLOAD_SIZE]u8 = .{0} ** PAYLOAD_SIZE;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    _ = try builder.addCellTokenOutput(&header, &payload, "test/path", .{0xaa} ** 32, pubkey, 1, 3, 2);

    const out = &builder.outputs[0];
    const script = out.script_pubkey[0..out.script_pubkey_len];

    // Verify script structure: push push push push push OP_DROP OP_2DROP OP_2DROP push OP_CHECKSIG
    const omap = TxBuilder.extractOutputMap(script);
    try std.testing.expect(omap != null);
    try std.testing.expectEqual(@as(u8, 3), omap.?.overflow_count);
    try std.testing.expectEqual(@as(u8, 2), omap.?.proof_count);

    // Script should end with OP_CHECKSIG
    try std.testing.expectEqual(OP_CHECKSIG, script[script.len - 1]);
}

test "T30: TX with primary [overflow:2, proof:1] — walkPrimaryOutputs correct" {
    var builder = TxBuilder.init();
    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF;
    var payload: [PAYLOAD_SIZE]u8 = .{0} ** PAYLOAD_SIZE;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    // Primary with 2 overflow, 1 proof
    _ = try builder.addCellTokenOutput(&header, &payload, "test/a", .{0xaa} ** 32, pubkey, 1, 2, 1);
    // 2 overflow outputs
    _ = try builder.addOverflowOutput(.{
        .cell_type = 4,
        .cell_index = 1,
        .total_cells = 2,
        .payload_size = 100,
        .reserved = 0,
    }, &(.{0x11} ** 100), pubkey, 1);
    _ = try builder.addOverflowOutput(.{
        .cell_type = 5,
        .cell_index = 2,
        .total_cells = 2,
        .payload_size = 50,
        .reserved = 0,
    }, &(.{0x22} ** 50), pubkey, 1);
    // 1 proof output
    _ = try builder.addProofOutput(PROOF_TYPE_ATOMIC_BEEF, &(.{0xff} ** 64));

    // Walk primaries — should yield index 0 only
    var iter = builder.walkPrimaryOutputs();
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqual(@as(u32, 0), first.?);
    try std.testing.expect(iter.next() == null);

    // Verify span
    const span = try builder.getObjectOutputSpan(0);
    try std.testing.expectEqual(@as(u8, 2), span.overflow_count);
    try std.testing.expectEqual(@as(u8, 1), span.proof_count);
    try std.testing.expectEqual(@as(u32, 1), span.overflow_start);
    try std.testing.expectEqual(@as(u32, 3), span.proof_start);
}

test "T31: two primary objects + payment — walk yields correct indices" {
    var builder = TxBuilder.init();
    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF;
    var payload: [PAYLOAD_SIZE]u8 = .{0} ** PAYLOAD_SIZE;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    // Object A [overflow:1, proof:1]
    _ = try builder.addCellTokenOutput(&header, &payload, "a", .{0xaa} ** 32, pubkey, 1, 1, 1);
    _ = try builder.addOverflowOutput(.{ .cell_type = 4, .cell_index = 1, .total_cells = 1, .payload_size = 100, .reserved = 0 }, &(.{0} ** 100), pubkey, 1);
    _ = try builder.addProofOutput(PROOF_TYPE_BUMP, &(.{0} ** 32));

    // Object B [overflow:0, proof:0]
    _ = try builder.addCellTokenOutput(&header, &payload, "b", .{0xbb} ** 32, pubkey, 1, 0, 0);

    // Payment output
    _ = try builder.addPaymentOutput(5000, &p2pkh_script);

    // Walk: should yield 0, then 3
    var iter = builder.walkPrimaryOutputs();
    try std.testing.expectEqual(@as(u32, 0), iter.next().?);
    try std.testing.expectEqual(@as(u32, 3), iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "T32: OP_RETURN proof output round-trips" {
    var builder = TxBuilder.init();
    const proof_data = "test proof payload for BEEF";
    _ = try builder.addProofOutput(PROOF_TYPE_ATOMIC_BEEF, proof_data);

    var buf: [64000]u8 = undefined;
    const len = try builder.serialize(&buf);

    var ctx = sighash.TxContext.init();
    try sighash.parseTxContext(buf[0..len], 0, 0, &ctx);

    // Verify the output script starts with OP_FALSE OP_RETURN
    const script = ctx.outputs[0].script[0..ctx.outputs[0].script_len];
    try std.testing.expectEqual(OP_FALSE, script[0]);
    try std.testing.expectEqual(OP_RETURN, script[1]);
    // Value should be 0
    try std.testing.expectEqual(@as(u64, 0), ctx.outputs[0].value);
}

test "T33: PushDrop overflow output contains valid ContinuationHeader" {
    var builder = TxBuilder.init();
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    _ = try builder.addOverflowOutput(.{
        .cell_type = 4, // DATA
        .cell_index = 1,
        .total_cells = 3,
        .payload_size = 500,
        .reserved = 0,
    }, &(.{0xab} ** 500), pubkey, 1);

    var buf: [64000]u8 = undefined;
    const len = try builder.serialize(&buf);

    var ctx = sighash.TxContext.init();
    try sighash.parseTxContext(buf[0..len], 0, 0, &ctx);

    const script = ctx.outputs[0].script[0..ctx.outputs[0].script_len];
    // First push should be 8 bytes (ContinuationHeader)
    try std.testing.expectEqual(@as(u8, 8), script[0]); // push opcode for 8 bytes
    const hdr_data = script[1..9];
    try std.testing.expectEqual(@as(u8, 4), hdr_data[0]); // cell_type = DATA
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, hdr_data[1..3], .little)); // cell_index
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, hdr_data[3..5], .little)); // total_cells
    try std.testing.expectEqual(@as(u16, 500), std.mem.readInt(u16, hdr_data[5..7], .little)); // payload_size
    try std.testing.expectEqual(@as(u8, 0), hdr_data[7]); // reserved
}

test "T34: state >768 bytes produces correct overflow_count" {
    // This tests the conceptual flow: if payload > 768 bytes, you need overflow outputs.
    // The caller determines overflow_count; TxBuilder just records it faithfully.
    var builder = TxBuilder.init();
    var header: [HEADER_SIZE]u8 = .{0} ** HEADER_SIZE;
    header[0] = 0xDE;
    header[1] = 0xAD;
    header[2] = 0xBE;
    header[3] = 0xEF;
    var payload: [PAYLOAD_SIZE]u8 = .{0xaa} ** PAYLOAD_SIZE;
    var pubkey: [33]u8 = .{0} ** 33;
    pubkey[0] = 0x02;

    // Total state = 768 + 2 * 1016 = 2800 bytes. Needs 2 overflow outputs.
    const overflow_count: u8 = 2;

    _ = try builder.addCellTokenOutput(&header, &payload, "big/state", .{0xcc} ** 32, pubkey, 1, overflow_count, 0);
    // Add matching overflow outputs
    _ = try builder.addOverflowOutput(.{ .cell_type = 4, .cell_index = 1, .total_cells = 2, .payload_size = 1016, .reserved = 0 }, &(.{0xbb} ** 1016), pubkey, 1);
    _ = try builder.addOverflowOutput(.{ .cell_type = 4, .cell_index = 2, .total_cells = 2, .payload_size = 1016, .reserved = 0 }, &(.{0xcc} ** 1016), pubkey, 1);

    // Verify output_map declares 2 overflow
    const omap = TxBuilder.extractOutputMap(builder.outputs[0].script_pubkey[0..builder.outputs[0].script_pubkey_len]);
    try std.testing.expect(omap != null);
    try std.testing.expectEqual(@as(u8, 2), omap.?.overflow_count);
    try std.testing.expectEqual(@as(u8, 0), omap.?.proof_count);

    // Walk should yield only the primary
    var iter = builder.walkPrimaryOutputs();
    try std.testing.expectEqual(@as(u32, 0), iter.next().?);
    try std.testing.expect(iter.next() == null);
}

```
