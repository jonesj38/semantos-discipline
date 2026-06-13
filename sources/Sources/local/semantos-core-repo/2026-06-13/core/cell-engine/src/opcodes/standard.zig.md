---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/opcodes/standard.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.001387+00:00
---

# core/cell-engine/src/opcodes/standard.zig

```zig
// Standard Bitcoin Script opcodes (0x00-0xAF) — Phase 3
// Reference: CORE:EXECUTOR (script-executor.fs)
//
// Opcode values follow standard Bitcoin Script assignments.
// OP_ROT=0x7B, OP_ROLL=0x7A (opcodes.ts has these swapped — we use standard values).

const pda_mod = @import("pda");
const constants = @import("constants");
const host = @import("host");
const sighash = @import("sighash");
const allocator_mod = @import("allocator");

pub const OpcodeError = error{
    stack_overflow,
    stack_underflow,
    execution_limit,
    verify_failed,
    disabled_opcode,
    invalid_opcode,
    invalid_script,
    invalid_pushdata,
    nesting_depth_exceeded,
    invalid_sighash,
    no_tx_context,
    not_implemented,
    // Phase 4: linearity enforcement errors
    cannot_duplicate_linear,
    cannot_discard_linear,
    cannot_duplicate_affine,
    cannot_discard_relevant,
    invalid_linearity_type,
    linearity_check_failed,
    domain_flag_mismatch,
    type_hash_mismatch,
    owner_id_mismatch,
    capability_type_mismatch,
    cell_too_short,
};

// ── Opcode constants ──

// Data push
pub const OP_0: u8 = 0x00;
pub const OP_FALSE: u8 = 0x00;
pub const OP_PUSHDATA1: u8 = 0x4C;
pub const OP_PUSHDATA2: u8 = 0x4D;
pub const OP_PUSHDATA4: u8 = 0x4E;
pub const OP_1NEGATE: u8 = 0x4F;
pub const OP_1: u8 = 0x51;
pub const OP_2: u8 = 0x52;
pub const OP_16: u8 = 0x60;

// Flow control
pub const OP_NOP: u8 = 0x61;
pub const OP_IF: u8 = 0x63;
pub const OP_NOTIF: u8 = 0x64;
pub const OP_ELSE: u8 = 0x67;
pub const OP_ENDIF: u8 = 0x68;
pub const OP_VERIFY: u8 = 0x69;
pub const OP_RETURN: u8 = 0x6A;

// Stack
pub const OP_TOALTSTACK: u8 = 0x6B;
pub const OP_FROMALTSTACK: u8 = 0x6C;
pub const OP_2DROP: u8 = 0x6D;
pub const OP_2DUP: u8 = 0x6E;
pub const OP_3DUP: u8 = 0x6F;
pub const OP_2OVER: u8 = 0x70;
pub const OP_2ROT: u8 = 0x71;
pub const OP_2SWAP: u8 = 0x72;
pub const OP_IFDUP: u8 = 0x73;
pub const OP_DEPTH: u8 = 0x74;
pub const OP_DROP: u8 = 0x75;
pub const OP_DUP: u8 = 0x76;
pub const OP_NIP: u8 = 0x77;
pub const OP_OVER: u8 = 0x78;
pub const OP_PICK: u8 = 0x79;
pub const OP_ROLL: u8 = 0x7A;
pub const OP_ROT: u8 = 0x7B;
pub const OP_SWAP: u8 = 0x7C;
pub const OP_TUCK: u8 = 0x7D;

// String/splice (BSV-restored)
pub const OP_CAT: u8 = 0x7E;
pub const OP_SPLIT: u8 = 0x7F;
pub const OP_NUM2BIN: u8 = 0x80;
pub const OP_BIN2NUM: u8 = 0x81;
pub const OP_SIZE: u8 = 0x82;

// Logic
pub const OP_EQUAL: u8 = 0x87;
pub const OP_EQUALVERIFY: u8 = 0x88;

// Arithmetic
pub const OP_1ADD: u8 = 0x8B;
pub const OP_1SUB: u8 = 0x8C;
pub const OP_NEGATE: u8 = 0x8F;
pub const OP_ABS: u8 = 0x90;
pub const OP_NOT: u8 = 0x91;
pub const OP_0NOTEQUAL: u8 = 0x92;
pub const OP_ADD: u8 = 0x93;
pub const OP_SUB: u8 = 0x94;
pub const OP_MUL: u8 = 0x95;
pub const OP_BOOLAND: u8 = 0x9A;
pub const OP_BOOLOR: u8 = 0x9B;
pub const OP_NUMEQUAL: u8 = 0x9C;
pub const OP_NUMEQUALVERIFY: u8 = 0x9D;
pub const OP_NUMNOTEQUAL: u8 = 0x9E;
pub const OP_LESSTHAN: u8 = 0x9F;
pub const OP_GREATERTHAN: u8 = 0xA0;
pub const OP_LESSTHANOREQUAL: u8 = 0xA1;
pub const OP_GREATERTHANOREQUAL: u8 = 0xA2;
pub const OP_MIN: u8 = 0xA3;
pub const OP_MAX: u8 = 0xA4;
pub const OP_WITHIN: u8 = 0xA5;

// Crypto
pub const OP_SHA256: u8 = 0xA8;
pub const OP_HASH160: u8 = 0xA9;
pub const OP_HASH256: u8 = 0xAA;
pub const OP_CHECKSIG: u8 = 0xAC;
pub const OP_CHECKSIGVERIFY: u8 = 0xAD;
pub const OP_CHECKMULTISIG: u8 = 0xAE;
pub const OP_CHECKMULTISIGVERIFY: u8 = 0xAF;

// NOP range
pub const OP_NOP1: u8 = 0xB0;
pub const OP_NOP10: u8 = 0xB9;

// BSV-restored opcodes (all original opcodes now in effect)
pub const OP_RESERVED: u8 = 0x50;
pub const OP_VER: u8 = 0x62;
pub const OP_VERIF: u8 = 0x65;
pub const OP_VERNOTIF: u8 = 0x66;
pub const OP_INVERT: u8 = 0x83;
pub const OP_AND: u8 = 0x84;
pub const OP_OR: u8 = 0x85;
pub const OP_XOR: u8 = 0x86;
pub const OP_RESERVED1: u8 = 0x89;
pub const OP_RESERVED2: u8 = 0x8A;
pub const OP_2MUL: u8 = 0x8D;
pub const OP_2DIV: u8 = 0x8E;
pub const OP_DIV: u8 = 0x96;
pub const OP_MOD: u8 = 0x97;
pub const OP_LSHIFT: u8 = 0x98;
pub const OP_RSHIFT: u8 = 0x99;
pub const OP_RIPEMD160: u8 = 0xA6;
pub const OP_SHA1: u8 = 0xA7;
pub const OP_CODESEPARATOR: u8 = 0xAB;

const std = @import("std");

/// Execute a standard opcode. `pc` points past the opcode byte.
/// `executing` indicates whether we are in an executing branch (false = skipping for IF/ELSE).
pub fn execute(
    p: *pda_mod.PDA,
    opcode: u8,
    script: []const u8,
    pc: *usize,
    arena: *allocator_mod.ScriptArena,
    tx_ctx: ?*const sighash.TxContext,
    condition_stack: []bool,
    condition_depth: *u32,
    executing: *bool,
) OpcodeError!void {
    _ = arena;

    // Flow control opcodes must be processed even when not executing (to track nesting)
    if (opcode == OP_IF or opcode == OP_NOTIF) {
        return handleIf(p, opcode, condition_stack, condition_depth, executing);
    }
    if (opcode == OP_ELSE) {
        return handleElse(condition_stack, condition_depth, executing);
    }
    if (opcode == OP_ENDIF) {
        return handleEndif(condition_stack, condition_depth, executing);
    }

    // If we're not in an executing branch, skip everything else
    if (!executing.*) return;

    // ── Constants ──
    if (opcode == OP_0) {
        // Push empty (zero)
        try p.spush(&[_]u8{});
        return;
    }
    if (opcode == OP_1NEGATE) {
        try p.spush(&[_]u8{0x81}); // -1 in sign-magnitude
        return;
    }
    if (opcode >= OP_1 and opcode <= OP_16) {
        const n = opcode - OP_1 + 1;
        try p.spush(&[_]u8{n});
        return;
    }

    // ── Stack manipulation ──
    // Phase 4: when enforcement_enabled, use linearity-aware wrappers
    const enforced = p.enforcement_enabled;
    switch (opcode) {
        OP_TOALTSTACK => return p.toalt(),
        OP_FROMALTSTACK => return p.fromalt(),
        OP_2DROP => return if (enforced) p.s2drop_enforced() else p.s2drop(),
        OP_2DUP => return if (enforced) p.s2dup_enforced() else p.s2dup(),
        OP_3DUP => return if (enforced) p.s3dup_enforced() else p.s3dup(),
        OP_2OVER => return if (enforced) p.s2over_enforced() else p.s2over(),
        OP_2ROT => return if (enforced) p.s2rot_enforced() else p.s2rot(),
        OP_2SWAP => return if (enforced) p.s2swap_enforced() else p.s2swap(),
        OP_IFDUP => return if (enforced) p.sifdup_enforced() else p.sifdup(),
        OP_DEPTH => {
            var cell: pda_mod.Cell = undefined;
            const len = pda_mod.i64ToCell(@intCast(p.sdepth()), &cell);
            try p.spush(cell[0..len]);
            return;
        },
        OP_DROP => return if (enforced) p.sdrop_enforced() else p.sdrop(),
        OP_DUP => return if (enforced) p.sdup_enforced() else p.sdup(),
        OP_NIP => return if (enforced) p.snip_enforced() else p.snip(),
        OP_OVER => return if (enforced) p.sover_enforced() else p.sover(),
        OP_PICK => {
            const top = try p.spop();
            const n: u32 = @intCast(pda_mod.cellToI64(top.data[0..top.len]));
            return if (enforced) p.spick_enforced(n) else p.spick(n);
        },
        OP_ROLL => {
            const top = try p.spop();
            const n: u32 = @intCast(pda_mod.cellToI64(top.data[0..top.len]));
            return if (enforced) p.sroll_enforced(n) else p.sroll(n);
        },
        OP_ROT => return if (enforced) p.srot_enforced() else p.srot(),
        OP_SWAP => return if (enforced) p.sswap_enforced() else p.sswap(),
        OP_TUCK => return if (enforced) p.stuck_enforced() else p.stuck(),
        else => {},
    }

    // ── Flow control ──
    switch (opcode) {
        OP_NOP, OP_CODESEPARATOR => return,
        OP_VERIFY => {
            const top = try p.spop();
            if (!pda_mod.isTruthy(top.data, top.len)) {
                return error.verify_failed;
            }
            return;
        },
        OP_RETURN => return error.verify_failed, // OP_RETURN always fails
        else => {},
    }

    // ── Reserved opcodes (BSV-restored — always fail) ──
    switch (opcode) {
        OP_RESERVED, OP_VER, OP_VERIF, OP_VERNOTIF, OP_RESERVED1, OP_RESERVED2 => return error.verify_failed,
        else => {},
    }

    // ── String/splice (BSV-restored) ──
    switch (opcode) {
        OP_CAT => return opCat(p),
        OP_SPLIT => return opSplit(p),
        OP_NUM2BIN => return opNum2Bin(p),
        OP_BIN2NUM => return opBin2Num(p),
        OP_SIZE => return opSize(p),
        else => {},
    }

    // ── Bitwise (BSV-restored) ──
    switch (opcode) {
        OP_INVERT => return opInvert(p),
        OP_AND => return opBitwiseAnd(p),
        OP_OR => return opBitwiseOr(p),
        OP_XOR => return opBitwiseXor(p),
        else => {},
    }

    // ── Logic ──
    switch (opcode) {
        OP_EQUAL => return opEqual(p, false),
        OP_EQUALVERIFY => return opEqual(p, true),
        else => {},
    }

    // ── Arithmetic ──
    switch (opcode) {
        OP_1ADD, OP_1SUB, OP_NEGATE, OP_ABS, OP_NOT, OP_0NOTEQUAL, OP_2MUL, OP_2DIV => return opUnaryArith(p, opcode),
        OP_ADD, OP_SUB, OP_MUL,
        OP_DIV, OP_MOD, OP_LSHIFT, OP_RSHIFT,
        OP_BOOLAND, OP_BOOLOR,
        OP_NUMEQUAL, OP_NUMEQUALVERIFY, OP_NUMNOTEQUAL,
        OP_LESSTHAN, OP_GREATERTHAN,
        OP_LESSTHANOREQUAL, OP_GREATERTHANOREQUAL,
        OP_MIN, OP_MAX,
        => return opBinaryArith(p, opcode),
        OP_WITHIN => return opWithin(p),
        else => {},
    }

    // ── Crypto ──
    switch (opcode) {
        OP_SHA256 => return opSha256(p),
        OP_HASH160 => return opHash160(p),
        OP_HASH256 => return opHash256(p),
        OP_RIPEMD160 => return opRipemd160(p),
        OP_SHA1 => return opSha1(p),
        OP_CHECKSIG => return opCheckSig(p, tx_ctx, script, pc, false),
        OP_CHECKSIGVERIFY => return opCheckSig(p, tx_ctx, script, pc, true),
        OP_CHECKMULTISIG => return opCheckMultiSig(p, tx_ctx, script, pc, false),
        OP_CHECKMULTISIGVERIFY => return opCheckMultiSig(p, tx_ctx, script, pc, true),
        else => {},
    }

    // ── NOP range (0xB0-0xB9 are handled as Craig macros in the executor) ──
    // Disabled opcodes or truly unknown
    return error.invalid_opcode;
}

// ── IF/ELSE/ENDIF ──

fn handleIf(
    p: *pda_mod.PDA,
    opcode: u8,
    condition_stack: []bool,
    condition_depth: *u32,
    executing: *bool,
) OpcodeError!void {
    if (condition_depth.* >= condition_stack.len) return error.nesting_depth_exceeded;

    if (executing.*) {
        const top = try p.spop();
        var cond = pda_mod.isTruthy(top.data, top.len);
        if (opcode == OP_NOTIF) cond = !cond;

        condition_stack[condition_depth.*] = executing.*;
        condition_depth.* += 1;
        executing.* = cond;
    } else {
        // Already in a non-executing branch — just track nesting
        condition_stack[condition_depth.*] = false; // parent was not executing
        condition_depth.* += 1;
        // executing remains false
    }
}

fn handleElse(
    condition_stack: []bool,
    condition_depth: *u32,
    executing: *bool,
) OpcodeError!void {
    if (condition_depth.* == 0) return error.invalid_script;
    // Only flip if parent was executing
    const parent_executing = condition_stack[condition_depth.* - 1];
    if (parent_executing) {
        executing.* = !executing.*;
    }
}

fn handleEndif(
    condition_stack: []bool,
    condition_depth: *u32,
    executing: *bool,
) OpcodeError!void {
    if (condition_depth.* == 0) return error.invalid_script;
    condition_depth.* -= 1;
    executing.* = condition_stack[condition_depth.*];
}

// ── String/splice operations ──

fn opCat(p: *pda_mod.PDA) OpcodeError!void {
    // Copy to temp buffers first to avoid aliasing (pointers into stack)
    const b = try p.spop();
    var b_buf: pda_mod.Cell = undefined;
    const b_len = b.len;
    if (b_len > 0) @memcpy(b_buf[0..b_len], b.data[0..b_len]);

    const a = try p.spop();
    var a_buf: pda_mod.Cell = undefined;
    const a_len = a.len;
    if (a_len > 0) @memcpy(a_buf[0..a_len], a.data[0..a_len]);

    const total = a_len + b_len;
    if (total > pda_mod.CELL_SIZE) return error.invalid_script;
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    if (a_len > 0) @memcpy(result[0..a_len], a_buf[0..a_len]);
    if (b_len > 0) @memcpy(result[a_len..total], b_buf[0..b_len]);
    try p.spushCell(&result, total);
}

fn opSplit(p: *pda_mod.PDA) OpcodeError!void {
    const n_item = try p.spop();
    const n: u32 = @intCast(pda_mod.cellToI64(n_item.data[0..n_item.len]));
    const data = try p.spop();
    if (n > data.len) return error.invalid_script;

    // Copy to temp buffers to avoid aliasing (data.data points into the stack)
    var left_buf: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    var right_buf: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    const left_len = n;
    const right_len = data.len - n;
    if (left_len > 0) @memcpy(left_buf[0..left_len], data.data[0..n]);
    if (right_len > 0) @memcpy(right_buf[0..right_len], data.data[n..data.len]);

    try p.spush(left_buf[0..left_len]);
    try p.spush(right_buf[0..right_len]);
}

fn opNum2Bin(p: *pda_mod.PDA) OpcodeError!void {
    const size_item = try p.spop();
    const size: u32 = @intCast(pda_mod.cellToI64(size_item.data[0..size_item.len]));
    const num_item = try p.spop();
    if (size > pda_mod.CELL_SIZE) return error.invalid_script;

    // Zero-extend the number to the requested size, preserving sign
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    const num_len = num_item.len;
    if (num_len > 0) {
        if (size < num_len) return error.invalid_script;
        // Copy all but potentially sign-bearing last byte
        if (num_len > 1) @memcpy(result[0 .. num_len - 1], num_item.data[0 .. num_len - 1]);
        // Handle sign: clear sign bit from original last byte, place it on new last byte
        const last = num_item.data[num_len - 1];
        const sign_bit = last & 0x80;
        result[num_len - 1] = last & 0x7F;
        result[size - 1] |= sign_bit;
    }
    try p.spushCell(&result, size);
}

fn opBin2Num(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    // Minimize: remove trailing zeros (except sign byte)
    var len = item.len;
    while (len > 0) {
        if (len == 1) break;
        // If last byte is 0x00 (no sign bit set) and previous byte has no sign bit, trim
        if (item.data[len - 1] == 0x00) {
            if (item.data[len - 2] & 0x80 == 0) {
                len -= 1;
                continue;
            }
        }
        // If last byte is 0x80 (only sign bit) and previous byte has no sign bit, absorb
        if (item.data[len - 1] == 0x80) {
            if (item.data[len - 2] & 0x80 == 0) {
                // Move sign to previous byte
                var result: pda_mod.Cell = undefined;
                @memcpy(result[0..len], item.data[0..len]);
                result[len - 2] |= 0x80;
                len -= 1;
                try p.spush(result[0..len]);
                return;
            }
        }
        break;
    }
    // Copy to a temp buffer first: `item` points into the stack slot that
    // spush reuses, so spush(item.data) would alias source and destination.
    var result: pda_mod.Cell = undefined;
    if (len > 0) @memcpy(result[0..len], item.data[0..len]);
    try p.spush(result[0..len]);
}

fn opSize(p: *pda_mod.PDA) OpcodeError!void {
    // Push the size of top element WITHOUT popping it
    const top = try p.speek();
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(@intCast(top.len), &cell);
    try p.spush(cell[0..len]);
}

// ── Equality ──

fn opEqual(p: *pda_mod.PDA, verify: bool) OpcodeError!void {
    const b = try p.spop();
    const a = try p.spop();
    const equal = a.len == b.len and std.mem.eql(u8, a.data[0..a.len], b.data[0..b.len]);
    if (verify) {
        if (!equal) return error.verify_failed;
    } else {
        try p.spush(if (equal) &[_]u8{0x01} else &[_]u8{});
    }
}

// ── Unary arithmetic ──

fn opUnaryArith(p: *pda_mod.PDA, opcode: u8) OpcodeError!void {
    const item = try p.spop();
    const val = pda_mod.cellToI64(item.data[0..item.len]);

    const result: i64 = switch (opcode) {
        OP_1ADD => val + 1,
        OP_1SUB => val - 1,
        OP_NEGATE => -val,
        OP_ABS => if (val < 0) -val else val,
        OP_NOT => if (val == 0) @as(i64, 1) else 0,
        OP_0NOTEQUAL => if (val != 0) @as(i64, 1) else 0,
        OP_2MUL => val * 2,
        OP_2DIV => @divTrunc(val, 2),
        else => unreachable,
    };

    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(result, &cell);
    try p.spush(cell[0..len]);
}

// ── Binary arithmetic ──

fn opBinaryArith(p: *pda_mod.PDA, opcode: u8) OpcodeError!void {
    const b_item = try p.spop();
    const a_item = try p.spop();
    const a = pda_mod.cellToI64(a_item.data[0..a_item.len]);
    const b = pda_mod.cellToI64(b_item.data[0..b_item.len]);

    // Division and shift operations need special error handling
    switch (opcode) {
        OP_DIV => return opDiv(p, a, b),
        OP_MOD => return opMod(p, a, b),
        OP_LSHIFT => return opLshift(p, a, b),
        OP_RSHIFT => return opRshift(p, a, b),
        else => {},
    }

    const result: i64 = switch (opcode) {
        OP_ADD => a + b,
        OP_SUB => a - b,
        OP_MUL => a * b,
        OP_BOOLAND => if (a != 0 and b != 0) @as(i64, 1) else 0,
        OP_BOOLOR => if (a != 0 or b != 0) @as(i64, 1) else 0,
        OP_NUMEQUAL => if (a == b) @as(i64, 1) else 0,
        OP_NUMNOTEQUAL => if (a != b) @as(i64, 1) else 0,
        OP_LESSTHAN => if (a < b) @as(i64, 1) else 0,
        OP_GREATERTHAN => if (a > b) @as(i64, 1) else 0,
        OP_LESSTHANOREQUAL => if (a <= b) @as(i64, 1) else 0,
        OP_GREATERTHANOREQUAL => if (a >= b) @as(i64, 1) else 0,
        OP_MIN => @min(a, b),
        OP_MAX => @max(a, b),
        OP_NUMEQUALVERIFY => {
            if (a != b) return error.verify_failed;
            return; // Don't push result
        },
        else => unreachable,
    };

    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(result, &cell);
    try p.spush(cell[0..len]);
}

fn opWithin(p: *pda_mod.PDA) OpcodeError!void {
    const max_item = try p.spop();
    const min_item = try p.spop();
    const x_item = try p.spop();
    const x = pda_mod.cellToI64(x_item.data[0..x_item.len]);
    const min_val = pda_mod.cellToI64(min_item.data[0..min_item.len]);
    const max_val = pda_mod.cellToI64(max_item.data[0..max_item.len]);

    const result: i64 = if (x >= min_val and x < max_val) 1 else 0;
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(result, &cell);
    try p.spush(cell[0..len]);
}

// ── Crypto (via host functions) ──

fn opSha256(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var hash: [32]u8 = undefined;
    host.sha256(item.data[0..item.len], &hash);
    try p.spush(&hash);
}

fn opHash160(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var hash: [20]u8 = undefined;
    host.hash160(item.data[0..item.len], &hash);
    try p.spush(&hash);
}

fn opHash256(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var hash: [32]u8 = undefined;
    host.hash256(item.data[0..item.len], &hash);
    try p.spush(&hash);
}

fn opRipemd160(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var hash: [20]u8 = undefined;
    host.ripemd160(item.data[0..item.len], &hash);
    try p.spush(&hash);
}

fn opSha1(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var hash: [20]u8 = undefined;
    host.sha1(item.data[0..item.len], &hash);
    try p.spush(&hash);
}

// ── Bitwise operations (BSV-restored) ──

fn opInvert(p: *pda_mod.PDA) OpcodeError!void {
    const item = try p.spop();
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    var i: u32 = 0;
    while (i < item.len) : (i += 1) {
        result[i] = ~item.data[i];
    }
    try p.spushCell(&result, item.len);
}

fn opBitwiseAnd(p: *pda_mod.PDA) OpcodeError!void {
    const b = try p.spop();
    const a = try p.spop();
    if (a.len != b.len) return error.invalid_script;
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    var i: u32 = 0;
    while (i < a.len) : (i += 1) {
        result[i] = a.data[i] & b.data[i];
    }
    try p.spushCell(&result, a.len);
}

fn opBitwiseOr(p: *pda_mod.PDA) OpcodeError!void {
    const b = try p.spop();
    const a = try p.spop();
    if (a.len != b.len) return error.invalid_script;
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    var i: u32 = 0;
    while (i < a.len) : (i += 1) {
        result[i] = a.data[i] | b.data[i];
    }
    try p.spushCell(&result, a.len);
}

fn opBitwiseXor(p: *pda_mod.PDA) OpcodeError!void {
    const b = try p.spop();
    const a = try p.spop();
    if (a.len != b.len) return error.invalid_script;
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    var i: u32 = 0;
    while (i < a.len) : (i += 1) {
        result[i] = a.data[i] ^ b.data[i];
    }
    try p.spushCell(&result, a.len);
}

// ── Division, Modulo, and Shift (BSV-restored) ──

fn opDiv(p: *pda_mod.PDA, a: i64, b: i64) OpcodeError!void {
    if (b == 0) return error.verify_failed;
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(@divTrunc(a, b), &cell);
    try p.spush(cell[0..len]);
}

fn opMod(p: *pda_mod.PDA, a: i64, b: i64) OpcodeError!void {
    if (b == 0) return error.verify_failed;
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(@rem(a, b), &cell);
    try p.spush(cell[0..len]);
}

fn opLshift(p: *pda_mod.PDA, a: i64, b: i64) OpcodeError!void {
    if (b < 0) return error.verify_failed;
    const shift: u6 = if (b > 63) 63 else @intCast(@as(u64, @intCast(b)));
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(a << shift, &cell);
    try p.spush(cell[0..len]);
}

fn opRshift(p: *pda_mod.PDA, a: i64, b: i64) OpcodeError!void {
    if (b < 0) return error.verify_failed;
    const shift: u6 = if (b > 63) 63 else @intCast(@as(u64, @intCast(b)));
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(a >> shift, &cell);
    try p.spush(cell[0..len]);
}

fn opCheckSig(
    p: *pda_mod.PDA,
    tx_ctx: ?*const sighash.TxContext,
    script: []const u8,
    pc: *usize,
    verify: bool,
) OpcodeError!void {
    if (pc.* > 0) {} // suppress unused warning

    const pk_item = try p.spop();
    const sig_item = try p.spop();

    if (tx_ctx == null) return error.no_tx_context;
    if (sig_item.len == 0) {
        // Empty signature = failure
        if (verify) return error.verify_failed;
        try p.spush(&[_]u8{});
        return;
    }

    // Extract sighash type from last byte of signature
    const sighash_type = sig_item.data[sig_item.len - 1];

    // Verify FORKID bit is set
    if (sighash_type & sighash.SIGHASH_FORKID == 0) return error.invalid_sighash;

    // Compute BIP143 preimage hash
    const msg_hash = sighash.computeSigHash(
        tx_ctx.?,
        script, // subscript = current lock script
        sighash_type,
    ) catch return error.invalid_sighash;

    // Call host for ECDSA verification
    const sig_without_hashtype = sig_item.data[0 .. sig_item.len - 1];
    const result = host.checksig(
        pk_item.data[0..pk_item.len],
        &msg_hash,
        sig_without_hashtype,
    );

    if (verify) {
        if (!result) return error.verify_failed;
    } else {
        try p.spush(if (result) &[_]u8{0x01} else &[_]u8{});
    }
}

fn opCheckMultiSig(
    p: *pda_mod.PDA,
    tx_ctx: ?*const sighash.TxContext,
    script: []const u8,
    pc: *usize,
    verify: bool,
) OpcodeError!void {
    if (pc.* > 0) {} // suppress unused warning

    if (tx_ctx == null) return error.no_tx_context;

    // Pop number of pubkeys
    const n_keys_item = try p.spop();
    const n_keys: u32 = @intCast(pda_mod.cellToI64(n_keys_item.data[0..n_keys_item.len]));

    // Pop pubkeys
    var pubkeys: [20][33]u8 = undefined;
    var pubkey_lens: [20]u32 = undefined;
    var i: u32 = 0;
    while (i < n_keys) : (i += 1) {
        const pk = try p.spop();
        if (pk.len <= 33) {
            @memcpy(pubkeys[i][0..pk.len], pk.data[0..pk.len]);
            pubkey_lens[i] = pk.len;
        }
    }

    // Pop number of sigs
    const n_sigs_item = try p.spop();
    const n_sigs: u32 = @intCast(pda_mod.cellToI64(n_sigs_item.data[0..n_sigs_item.len]));

    // Pop signatures
    var sigs: [20][73]u8 = undefined;
    var sig_lens: [20]u32 = undefined;
    i = 0;
    while (i < n_sigs) : (i += 1) {
        const sig = try p.spop();
        if (sig.len <= 73) {
            @memcpy(sigs[i][0..sig.len], sig.data[0..sig.len]);
            sig_lens[i] = sig.len;
        }
    }

    // Pop the dummy element (off-by-one bug workaround)
    _ = try p.spop();

    // Verify signatures against pubkeys (greedy matching)
    var key_idx: u32 = 0;
    var sig_idx: u32 = 0;
    var success = true;

    while (sig_idx < n_sigs and key_idx < n_keys) {
        const sig_len = sig_lens[sig_idx];
        if (sig_len == 0) {
            sig_idx += 1;
            continue;
        }
        const sig_hashtype = sigs[sig_idx][sig_len - 1];
        if (sig_hashtype & sighash.SIGHASH_FORKID == 0) {
            success = false;
            break;
        }

        // Compute BIP143 preimage hash
        const msg_hash = sighash.computeSigHash(
            tx_ctx.?,
            script,
            sig_hashtype,
        ) catch {
            success = false;
            break;
        };

        const valid = host.checksig(
            pubkeys[key_idx][0..pubkey_lens[key_idx]],
            &msg_hash,
            sigs[sig_idx][0 .. sig_len - 1],
        );

        if (valid) {
            sig_idx += 1;
        }
        key_idx += 1;
    }

    if (sig_idx < n_sigs) success = false;

    if (verify) {
        if (!success) return error.verify_failed;
    } else {
        try p.spush(if (success) &[_]u8{0x01} else &[_]u8{});
    }
}

```
