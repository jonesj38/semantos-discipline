---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/sighash.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.979537+00:00
---

# core/cell-engine/src/sighash.zig

```zig
// SIGHASH dispatch and transaction context — Phase 3
// BIP143 preimage computation for OP_CHECKSIG/OP_CHECKMULTISIG.
// Reference: CASHLANES:PREIMAGE (TransactionSignature.format())

const constants = @import("constants");
const errors = @import("errors");
const host = @import("host");
const allocator_mod = @import("allocator");
const build_options = @import("build_options");
const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

/// SIGHASH type flags.
///
/// BSV historically required FORKID (BIP-143 path); BSV v1.2.0
/// "Chronicle" (mainnet 2026-04-07) reinstates the original pre-segwit
/// Satoshi digest algorithm (OTDA), selected by the new CHRONICLE bit.
/// Per the Chronicle spec, the two paths coexist — each signature in a
/// transaction picks independently via its sighashFlags byte.
///
/// Reference: https://github.com/bitcoin-sv-specs/protocol/blob/master/updates/chronicle-spec.md
pub const SIGHASH_ALL: u8 = 0x01;
pub const SIGHASH_NONE: u8 = 0x02;
pub const SIGHASH_SINGLE: u8 = 0x03;
pub const SIGHASH_CHRONICLE: u8 = 0x20; // BSV v1.2.0 — set → OTDA, clear → BIP-143
pub const SIGHASH_FORKID: u8 = 0x40; // BIP-143 fork-id bit; ignored under OTDA
pub const SIGHASH_ANYONECANPAY: u8 = 0x80;
pub const SIGHASH_MASK: u8 = 0x1F; // bottom 5 bits = base type

// Embedded targets shrink the transaction-context limits drastically.
// Desktop validates real BSV transactions (up to 256 in/out with 10KB
// output scripts). MCU demos verify a few signed cells at a time and
// never see large transactions. The 256-output × 10KB-script default
// burns ~2.56MB of static storage inside TxContext — the bulk of the
// cell-engine's remaining footprint after PDA shrinkage.
pub const MAX_INPUTS:             usize = if (build_options.embedded)  4 else 256;
pub const MAX_OUTPUTS:            usize = if (build_options.embedded)  4 else 256;
pub const MAX_OUTPUT_SCRIPT_SIZE: usize = if (build_options.embedded) 1024 else 10000;

pub const TxInput = struct {
    prev_txid: [32]u8,
    prev_vout: u32,
    script_len: u32,
    sequence: u32,
};

pub const TxOutput = struct {
    value: u64,
    script: [MAX_OUTPUT_SCRIPT_SIZE]u8,
    script_len: u32,
};

pub const TxContext = struct {
    version: u32,
    locktime: u32,
    current_input_index: u32,
    // Read-only output index exposed to scripts via OP_BRANCHONOUTPUT (0xE0).
    // Runtime-injected per script invocation; never written by any opcode.
    // Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md §3.
    current_output_index: u32,
    input_value: u64, // value of UTXO being spent (not in raw tx)

    inputs: [MAX_INPUTS]TxInput,
    input_count: u32,
    outputs: [MAX_OUTPUTS]TxOutput,
    output_count: u32,

    pub fn init() TxContext {
        return .{
            .version = 0,
            .locktime = 0,
            .current_input_index = 0,
            .current_output_index = 0,
            .input_value = 0,
            .inputs = undefined,
            .input_count = 0,
            .outputs = undefined,
            .output_count = 0,
        };
    }

    /// Initialize a TxContext in place.  Avoids the 2.45MB stack frame
    /// that newer Zig (≥0.15.2) materializes for the return-by-value
    /// path of `init()` — which underflows the 256KB WASM stack and
    /// produces "Out of bounds memory access" on `kernel_init`.
    ///
    /// Only the scalar metadata fields are zeroed; `inputs` and
    /// `outputs` (the huge ones) are left undefined and only touched
    /// when `parseTxContext` populates them.
    pub fn initInPlace(self: *TxContext) void {
        self.version = 0;
        self.locktime = 0;
        self.current_input_index = 0;
        self.current_output_index = 0;
        self.input_value = 0;
        self.input_count = 0;
        self.output_count = 0;
    }
};

pub const SigHashError = error{
    invalid_sighash,
    no_tx_context,
    invalid_script,
    /// Chronicle OTDA-specific: the SIGHASH_SINGLE bug. When
    /// current_input_index >= output_count under SIGHASH_SINGLE in
    /// OTDA, the legacy Bitcoin protocol returns the preimage hash of
    /// the value `1` — a footgun that's been exploited and is rejected
    /// here to force callers into either dropping SIGHASH_SINGLE or
    /// padding outputs. v1 surfaces this as an error rather than
    /// reproducing the legacy behaviour silently.
    sighash_single_bug,
};

/// Top-level SIGHASH digest computation. Dispatches between BIP-143
/// (existing `computeSigHash` below) and the Chronicle-reinstated OTDA
/// path on the basis of the SIGHASH_CHRONICLE (0x20) bit:
///
///   - CHRONICLE set    → OTDA (computeSigHashOTDA)
///   - CHRONICLE clear  → BIP-143 (computeSigHash; requires FORKID 0x40)
///
/// This is the single entrypoint script handlers (and the future
/// `host_compute_sighash` hostcall) should call. Per the Chronicle
/// spec each signature in a transaction may pick its algorithm
/// independently.
pub fn computeSigHashDispatch(
    tx: *const TxContext,
    subscript: []const u8,
    sighash_type: u8,
) SigHashError![32]u8 {
    if ((sighash_type & SIGHASH_CHRONICLE) != 0) {
        return computeSigHashOTDA(tx, subscript, sighash_type);
    }
    return computeSigHash(tx, subscript, sighash_type);
}

/// Compute BIP143 SIGHASH preimage hash.
/// Returns the 32-byte double-SHA256 of the preimage.
pub fn computeSigHash(
    tx: *const TxContext,
    subscript: []const u8,
    sighash_type: u8,
) SigHashError![32]u8 {
    // Verify FORKID is set (BSV requires it)
    if (sighash_type & SIGHASH_FORKID == 0) return error.invalid_sighash;

    const base_type = sighash_type & SIGHASH_MASK;
    const anyone_can_pay = (sighash_type & SIGHASH_ANYONECANPAY) != 0;

    // BIP143 preimage fields:
    // 1. nVersion (4B LE)
    // 2. hashPrevouts (32B)
    // 3. hashSequence (32B)
    // 4. outpoint of current input (36B: prev_txid + prev_vout LE)
    // 5. scriptCode (varint len + script bytes)
    // 6. value of output being spent (8B LE)
    // 7. nSequence of current input (4B LE)
    // 8. hashOutputs (32B)
    // 9. nLockTime (4B LE)
    // 10. nHashType (4B LE)

    // Build preimage in a local buffer.
    // Max size = 4 + 32 + 32 + 36 + 5 + MAX_OUTPUT_SCRIPT_SIZE + 8 + 4 + 32 + 4 + 4
    // Desktop:  10161 bytes (MAX_OUTPUT_SCRIPT_SIZE=10000)
    // Embedded: 1185 bytes (MAX_OUTPUT_SCRIPT_SIZE=1024) — sized down so it
    //   fits on the carved 16 KB WASM stack alongside other locals.
    const PREIMAGE_MAX: usize = 4 + 32 + 32 + 36 + 5 + MAX_OUTPUT_SCRIPT_SIZE + 8 + 4 + 32 + 4 + 4;
    var preimage: [PREIMAGE_MAX]u8 = undefined;
    var pos: usize = 0;

    // 1. nVersion
    std.mem.writeInt(u32, preimage[pos..][0..4], tx.version, .little);
    pos += 4;

    // 2. hashPrevouts — streaming to avoid large stack buffers
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
        // Double SHA256
        var hasher2 = Sha256.init(.{});
        hasher2.update(&first_hash);
        hasher2.final(preimage[pos..][0..32]);
    } else {
        @memset(preimage[pos..][0..32], 0);
    }
    pos += 32;

    // 3. hashSequence — streaming
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

    // 6. value (8B LE) — value of the UTXO being spent
    std.mem.writeInt(u64, preimage[pos..][0..8], tx.input_value, .little);
    pos += 8;

    // 7. nSequence of current input (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], cur_input.sequence, .little);
    pos += 4;

    // 8. hashOutputs — streaming to avoid 2.56MB stack allocation
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
        // Single output — small enough for a stack buffer
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
        // NONE or SINGLE with out-of-range index
        @memset(preimage[pos..][0..32], 0);
    }
    pos += 32;

    // 9. nLockTime (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], tx.locktime, .little);
    pos += 4;

    // 10. nHashType (4B LE)
    std.mem.writeInt(u32, preimage[pos..][0..4], @as(u32, sighash_type), .little);
    pos += 4;

    // Final: SHA256D(preimage)
    var result: [32]u8 = undefined;
    host.hash256(preimage[0..pos], &result);
    return result;
}

/// Compute OTDA (Original Transaction Digest Algorithm) sighash —
/// the pre-segwit Satoshi algorithm reinstated by BSV v1.2.0
/// "Chronicle". Returns the 32-byte double-SHA256 of the preimage.
///
/// Selection: set the SIGHASH_CHRONICLE (0x20) bit in `sighash_type`.
/// FORKID (0x40) is ignored on this path — the algorithm predates the
/// fork-id discipline. Use `computeSigHashDispatch` rather than calling
/// this directly so the bit-based selection happens once at the entry.
///
/// Preimage structure (per the original CTransactionSignatureSerializer
/// in Bitcoin Core circa 2010):
///
///   1. nVersion (4 LE)
///   2. varint(input_count_in_preimage)
///   3. for each input in the preimage:
///        - prev_txid (32B)
///        - prev_vout (4 LE)
///        - scriptSig: empty for non-current inputs; the subscript for
///          the current input
///        - sequence (4 LE) — zeroed for non-current inputs under
///          SIGHASH_NONE or SIGHASH_SINGLE
///   4. varint(output_count_in_preimage)
///   5. for each output in the preimage:
///        - value (8 LE) — set to 0xFFFFFFFFFFFFFFFF for outputs at
///          indices < current under SIGHASH_SINGLE
///        - scriptPubKey: empty for SINGLE-blanked outputs; full bytes
///          otherwise
///   6. nLockTime (4 LE)
///   7. sighash_type as u32 LE (includes CHRONICLE bit if set)
///
/// SIGHASH modifiers compose:
///   - SIGHASH_NONE:       output_count_in_preimage = 0
///   - SIGHASH_SINGLE:     output_count_in_preimage = current_input_index + 1
///                          (returns sighash_single_bug if current >= output_count)
///   - SIGHASH_ANYONECANPAY: input_count_in_preimage = 1 (just the current)
pub fn computeSigHashOTDA(
    tx: *const TxContext,
    subscript: []const u8,
    sighash_type: u8,
) SigHashError![32]u8 {
    const base_type = sighash_type & SIGHASH_MASK;
    const anyone_can_pay = (sighash_type & SIGHASH_ANYONECANPAY) != 0;

    // SIGHASH_SINGLE legacy bug: when current_input_index >= output_count
    // the original protocol returned the digest of the constant value 1.
    // We refuse rather than reproduce — see `sighash_single_bug` doc.
    if (base_type == SIGHASH_SINGLE and tx.current_input_index >= tx.output_count) {
        return error.sighash_single_bug;
    }

    // Stream the preimage through a single SHA-256 to avoid the 2.5 MB
    // peak buffer the BIP-143 path uses. The OTDA preimage is in
    // principle the entire serialized tx + sighash_type, but we never
    // materialize it — feed bytes to the hasher in order, then double-
    // hash at the end.
    var hasher = Sha256.init(.{});

    // 1. nVersion (4 LE)
    var ver_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &ver_buf, tx.version, .little);
    hasher.update(&ver_buf);

    // 2. varint(input_count_in_preimage)
    const input_count_in_preimage: u32 = if (anyone_can_pay) 1 else tx.input_count;
    var vi_buf: [9]u8 = undefined;
    var vi_len = writeVarInt(&vi_buf, input_count_in_preimage);
    hasher.update(vi_buf[0..vi_len]);

    // 3. inputs
    var i: u32 = 0;
    while (i < input_count_in_preimage) : (i += 1) {
        // When ANYONECANPAY, we only emit the current input.
        const src_i: u32 = if (anyone_can_pay) tx.current_input_index else i;
        const inp = &tx.inputs[src_i];
        const is_current = src_i == tx.current_input_index;

        // prev_txid (32B)
        hasher.update(&inp.prev_txid);

        // prev_vout (4 LE)
        var vout_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &vout_buf, inp.prev_vout, .little);
        hasher.update(&vout_buf);

        // scriptSig: empty for non-current inputs; subscript for current
        if (is_current) {
            vi_len = writeVarInt(&vi_buf, subscript.len);
            hasher.update(vi_buf[0..vi_len]);
            hasher.update(subscript);
        } else {
            hasher.update(&[_]u8{0x00}); // varint(0)
        }

        // sequence (4 LE) — zeroed for non-current under SINGLE/NONE
        var seq_buf: [4]u8 = undefined;
        const seq_val: u32 = if (!is_current and (base_type == SIGHASH_NONE or base_type == SIGHASH_SINGLE))
            0
        else
            inp.sequence;
        std.mem.writeInt(u32, &seq_buf, seq_val, .little);
        hasher.update(&seq_buf);
    }

    // 4. varint(output_count_in_preimage)
    const output_count_in_preimage: u32 = if (base_type == SIGHASH_NONE)
        0
    else if (base_type == SIGHASH_SINGLE)
        tx.current_input_index + 1
    else
        tx.output_count;

    vi_len = writeVarInt(&vi_buf, output_count_in_preimage);
    hasher.update(vi_buf[0..vi_len]);

    // 5. outputs
    var j: u32 = 0;
    while (j < output_count_in_preimage) : (j += 1) {
        const blank_for_single = base_type == SIGHASH_SINGLE and j < tx.current_input_index;

        var val_buf: [8]u8 = undefined;
        const value: u64 = if (blank_for_single) 0xFFFFFFFFFFFFFFFF else tx.outputs[j].value;
        std.mem.writeInt(u64, &val_buf, value, .little);
        hasher.update(&val_buf);

        if (blank_for_single) {
            hasher.update(&[_]u8{0x00}); // varint(0); empty scriptPubKey
        } else {
            const out = &tx.outputs[j];
            vi_len = writeVarInt(&vi_buf, out.script_len);
            hasher.update(vi_buf[0..vi_len]);
            hasher.update(out.script[0..out.script_len]);
        }
    }

    // 6. nLockTime (4 LE)
    var lt_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &lt_buf, tx.locktime, .little);
    hasher.update(&lt_buf);

    // 7. sighash_type as u32 LE (CHRONICLE bit retained — caller's intent)
    var ht_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &ht_buf, @as(u32, sighash_type), .little);
    hasher.update(&ht_buf);

    // Finalize first hash, then SHA-256 again for double-SHA256.
    var first_hash: [32]u8 = undefined;
    hasher.final(&first_hash);
    var second_hasher = Sha256.init(.{});
    second_hasher.update(&first_hash);
    var result: [32]u8 = undefined;
    second_hasher.final(&result);
    return result;
}

/// Parse raw Bitcoin transaction bytes into TxContext.
/// Format: version(4) + varint(input_count) + inputs + varint(output_count) + outputs + locktime(4)
pub fn parseTxContext(
    raw: []const u8,
    input_index: u32,
    input_value: u64,
    ctx: *TxContext,
) !void {
    if (raw.len < 10) return error.invalid_script;
    var pos: usize = 0;

    // Version
    ctx.version = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;

    // Input count
    const input_count_result = readVarInt(raw[pos..]);
    ctx.input_count = @intCast(input_count_result.value);
    pos += input_count_result.bytes;

    // Parse inputs
    var i: u32 = 0;
    while (i < ctx.input_count) : (i += 1) {
        if (pos + 36 > raw.len) return error.invalid_script;
        @memcpy(&ctx.inputs[i].prev_txid, raw[pos..][0..32]);
        pos += 32;
        ctx.inputs[i].prev_vout = std.mem.readInt(u32, raw[pos..][0..4], .little);
        pos += 4;

        // Script (varint length + bytes)
        const script_len_result = readVarInt(raw[pos..]);
        const script_len: u32 = @intCast(script_len_result.value);
        pos += script_len_result.bytes;
        ctx.inputs[i].script_len = script_len;
        pos += script_len; // skip script bytes

        // nSequence
        ctx.inputs[i].sequence = std.mem.readInt(u32, raw[pos..][0..4], .little);
        pos += 4;
    }

    // Output count
    const output_count_result = readVarInt(raw[pos..]);
    ctx.output_count = @intCast(output_count_result.value);
    pos += output_count_result.bytes;

    // Parse outputs
    i = 0;
    while (i < ctx.output_count) : (i += 1) {
        if (pos + 8 > raw.len) return error.invalid_script;
        ctx.outputs[i].value = std.mem.readInt(u64, raw[pos..][0..8], .little);
        pos += 8;

        const out_script_len_result = readVarInt(raw[pos..]);
        const out_script_len: u32 = @intCast(out_script_len_result.value);
        pos += out_script_len_result.bytes;

        if (out_script_len > 0) {
            @memcpy(ctx.outputs[i].script[0..out_script_len], raw[pos..][0..out_script_len]);
        }
        ctx.outputs[i].script_len = out_script_len;
        pos += out_script_len;
    }

    // Locktime
    ctx.locktime = std.mem.readInt(u32, raw[pos..][0..4], .little);

    ctx.current_input_index = input_index;
    ctx.input_value = input_value;
}

// ── Helpers ──

fn writeVarInt(buf: []u8, val: usize) usize {
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

const VarIntResult = struct { value: u64, bytes: usize };

fn readVarInt(data: []const u8) VarIntResult {
    if (data.len == 0) return .{ .value = 0, .bytes = 0 };
    const first = data[0];
    if (first < 0xFD) return .{ .value = first, .bytes = 1 };
    if (first == 0xFD) return .{ .value = std.mem.readInt(u16, data[1..][0..2], .little), .bytes = 3 };
    if (first == 0xFE) return .{ .value = std.mem.readInt(u32, data[1..][0..4], .little), .bytes = 5 };
    return .{ .value = std.mem.readInt(u64, data[1..][0..8], .little), .bytes = 9 };
}

// ── Inline tests (BIP-143 + OTDA + dispatch) ──────────────────────────
//
// These exercise the dual-algorithm path landed in PR-3 of
// LOCKSCRIPT-CLEAVAGE.md §11. They don't cross-check against external
// reference vectors — that's the role of cross-tool conformance fixtures
// in the follow-on PR (BSV testnet TX hashes + the Chronicle reference
// implementation). What these tests guarantee is internal consistency:
// determinism, dispatch routing, cross-algorithm digest divergence,
// SIGHASH-flag modifier effects.

const testing = std.testing;

/// Build a minimal TxContext with one input + one output for testing.
/// Caller can mutate fields to exercise specific paths.
fn fixtureTxContext() TxContext {
    var ctx = TxContext.init();
    ctx.version = 2;
    ctx.locktime = 0;
    ctx.current_input_index = 0;
    ctx.input_value = 50_000;
    ctx.input_count = 1;
    ctx.output_count = 1;

    // input 0
    @memset(&ctx.inputs[0].prev_txid, 0xAB);
    ctx.inputs[0].prev_vout = 0;
    ctx.inputs[0].script_len = 0;
    ctx.inputs[0].sequence = 0xFFFFFFFF;

    // output 0
    ctx.outputs[0].value = 49_500;
    ctx.outputs[0].script_len = 2;
    ctx.outputs[0].script[0] = 0x51; // OP_1
    ctx.outputs[0].script[1] = 0x69; // OP_VERIFY

    return ctx;
}

test "OTDA: SIGHASH_ALL produces a 32-byte deterministic digest" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const sh = SIGHASH_ALL | SIGHASH_CHRONICLE;
    const d1 = try computeSigHashOTDA(&ctx, subscript, sh);
    const d2 = try computeSigHashOTDA(&ctx, subscript, sh);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "OTDA: SIGHASH_NONE differs from SIGHASH_ALL for the same tx" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const d_all = try computeSigHashOTDA(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    const d_none = try computeSigHashOTDA(&ctx, subscript, SIGHASH_NONE | SIGHASH_CHRONICLE);
    try testing.expect(!std.mem.eql(u8, &d_all, &d_none));
}

test "OTDA: SIGHASH_ANYONECANPAY shrinks input set, changes digest" {
    var ctx = fixtureTxContext();
    // Add a second input to make the difference observable.
    ctx.input_count = 2;
    @memset(&ctx.inputs[1].prev_txid, 0xCD);
    ctx.inputs[1].prev_vout = 1;
    ctx.inputs[1].script_len = 0;
    ctx.inputs[1].sequence = 0xFFFFFFFF;

    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const d_all = try computeSigHashOTDA(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    const d_acp = try computeSigHashOTDA(&ctx, subscript, SIGHASH_ALL | SIGHASH_ANYONECANPAY | SIGHASH_CHRONICLE);
    try testing.expect(!std.mem.eql(u8, &d_all, &d_acp));
}

test "OTDA: SIGHASH_SINGLE bug surfaces error when index >= output_count" {
    var ctx = fixtureTxContext();
    // current_input_index = 0 but output_count = 1 — at boundary (NOT a bug).
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    _ = try computeSigHashOTDA(&ctx, subscript, SIGHASH_SINGLE | SIGHASH_CHRONICLE);
    // Now push current_input_index past output_count — triggers the bug.
    ctx.current_input_index = 1;
    ctx.input_count = 2;
    @memset(&ctx.inputs[1].prev_txid, 0xCD);
    ctx.inputs[1].prev_vout = 1;
    ctx.inputs[1].script_len = 0;
    ctx.inputs[1].sequence = 0xFFFFFFFF;
    try testing.expectError(
        error.sighash_single_bug,
        computeSigHashOTDA(&ctx, subscript, SIGHASH_SINGLE | SIGHASH_CHRONICLE),
    );
}

test "dispatch: CHRONICLE bit routes to OTDA path" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const d_dispatch = try computeSigHashDispatch(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    const d_direct = try computeSigHashOTDA(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    try testing.expectEqualSlices(u8, &d_dispatch, &d_direct);
}

test "dispatch: no CHRONICLE bit routes to BIP-143 path (requires FORKID)" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const d_dispatch = try computeSigHashDispatch(&ctx, subscript, SIGHASH_ALL | SIGHASH_FORKID);
    const d_direct = try computeSigHash(&ctx, subscript, SIGHASH_ALL | SIGHASH_FORKID);
    try testing.expectEqualSlices(u8, &d_dispatch, &d_direct);
}

test "cross-algorithm: BIP-143 and OTDA produce different digests for the same tx" {
    // Same tx + same subscript + same base SIGHASH flag — the algorithms
    // commit to different preimages, so the digests must differ. This is
    // the canonical "two algorithms coexist" invariant.
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    const d_bip143 = try computeSigHash(&ctx, subscript, SIGHASH_ALL | SIGHASH_FORKID);
    const d_otda = try computeSigHashOTDA(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    try testing.expect(!std.mem.eql(u8, &d_bip143, &d_otda));
}

test "dispatch: CHRONICLE bit without FORKID still routes to OTDA (FORKID ignored)" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    // CHRONICLE set, FORKID clear — should not error out (BIP-143 requires
    // FORKID, but the dispatcher routes to OTDA before that check).
    const d = try computeSigHashDispatch(&ctx, subscript, SIGHASH_ALL | SIGHASH_CHRONICLE);
    _ = d;
}

test "dispatch: no CHRONICLE no FORKID → BIP-143 errors with invalid_sighash" {
    var ctx = fixtureTxContext();
    const subscript = &[_]u8{ 0x51, 0x51, 0x69 };
    // Neither CHRONICLE nor FORKID — BIP-143 rejects (FORKID required by BSV).
    try testing.expectError(
        error.invalid_sighash,
        computeSigHashDispatch(&ctx, subscript, SIGHASH_ALL),
    );
}

```
