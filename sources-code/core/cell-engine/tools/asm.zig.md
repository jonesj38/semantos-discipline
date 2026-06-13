---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/asm.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.957088+00:00
---

# core/cell-engine/tools/asm.zig

```zig
//! Minimal cell-engine bytecode assembler.
//!
//! C11 PR5a — DX tool for hand-authoring cell-engine handler scripts
//! without typing raw hex. Replaces the "hand-encode then debug at
//! runtime via cryptic verify_failed / invalid_pushdata traps" pattern
//! that came up when scoping PR5 (bsv-spv-verify).
//!
//! Usage:
//!
//!   zig run tools/asm.zig -- <input.cs>
//!
//!   Reads `input.cs`, emits two lines to stdout:
//!     line 1: bytecode hex (lowercase, no spaces)
//!     line 2: sha256 of the bytecode (lowercase hex, 64 chars)
//!
//! Source format (.cs file):
//!
//!   # Comments start with #
//!   // Or with //
//!
//!   OP_<MNEMONIC>           # one opcode per line, looked up in the
//!                           # opcode table below
//!
//!   PUSH 0x<hex>            # pushdata — raw bytes, hex-encoded
//!   PUSH "literal string"   # pushdata — UTF-8 bytes of literal
//!   PUSH <integer>          # pushdata — minimal CScriptNum encoding
//!                           # (0 → OP_0; 1..16 → OP_1..OP_16; else CScriptNum)
//!
//! Pushdata length-prefixing follows BSV Script convention:
//!   • 1..75 bytes:   single length byte, no prefix opcode
//!   • 76..255 bytes: OP_PUSHDATA1 (0x4c) + 1-byte length
//!   • 256..65535:    OP_PUSHDATA2 (0x4d) + 2-byte LE length
//!   • >65535:        OP_PUSHDATA4 (0x4e) + 4-byte LE length
//!
//! Opcode table coverage:
//!   • Standard (0x00-0xAF): the subset documented in
//!     `core/cell-engine/src/opcodes/standard.zig` — push primitives,
//!     stack ops, control flow, comparison, arithmetic, hash, sig
//!   • Craig macros (0xB0-0xBF): XSWAP-N, XDROP-N, XROT-N, HASHCAT
//!   • Plexus (0xC0-0xCF): type / capability / identity / cell ops
//!   • OP_CALLHOST (0xD0)
//!   • OP_WRITEPAYLOAD (0xD1): Plexus-family payload-write carve-out
//!   • Routing (0xE0-0xEF): OP_BRANCHONOUTPUT
//!
//! Extending the table: add an entry to `OPCODES` below. Name lookup
//! is case-insensitive; the canonical names in the table use the
//! `OP_<NAME>` form even though source files can omit the `OP_` prefix.

const std = @import("std");

/// One entry in the opcode lookup table: canonical mnemonic + byte value.
const OpcodeEntry = struct { name: []const u8, byte: u8 };

/// Opcode table. Subset enough for first-handler authoring + every
/// Plexus + hostcall + routing op. Add entries as future scripts need
/// them.
const OPCODES = [_]OpcodeEntry{
    // ── Push primitives ──
    .{ .name = "OP_0", .byte = 0x00 },
    .{ .name = "OP_FALSE", .byte = 0x00 },
    .{ .name = "OP_1NEGATE", .byte = 0x4f },
    .{ .name = "OP_1", .byte = 0x51 },
    .{ .name = "OP_TRUE", .byte = 0x51 },
    .{ .name = "OP_2", .byte = 0x52 },
    .{ .name = "OP_3", .byte = 0x53 },
    .{ .name = "OP_4", .byte = 0x54 },
    .{ .name = "OP_5", .byte = 0x55 },
    .{ .name = "OP_6", .byte = 0x56 },
    .{ .name = "OP_7", .byte = 0x57 },
    .{ .name = "OP_8", .byte = 0x58 },
    .{ .name = "OP_9", .byte = 0x59 },
    .{ .name = "OP_10", .byte = 0x5a },
    .{ .name = "OP_11", .byte = 0x5b },
    .{ .name = "OP_12", .byte = 0x5c },
    .{ .name = "OP_13", .byte = 0x5d },
    .{ .name = "OP_14", .byte = 0x5e },
    .{ .name = "OP_15", .byte = 0x5f },
    .{ .name = "OP_16", .byte = 0x60 },
    // ── Control flow ──
    .{ .name = "OP_NOP", .byte = 0x61 },
    .{ .name = "OP_VER", .byte = 0x62 }, // BSV v1.2.0 "Chronicle" restored — pushes tx version
    .{ .name = "OP_IF", .byte = 0x63 },
    .{ .name = "OP_NOTIF", .byte = 0x64 },
    .{ .name = "OP_VERIF", .byte = 0x65 }, // BSV v1.2.0 "Chronicle" restored — version-conditional IF
    .{ .name = "OP_VERNOTIF", .byte = 0x66 }, // BSV v1.2.0 "Chronicle" restored — version-conditional NOTIF
    .{ .name = "OP_ELSE", .byte = 0x67 },
    .{ .name = "OP_ENDIF", .byte = 0x68 },
    .{ .name = "OP_VERIFY", .byte = 0x69 },
    .{ .name = "OP_RETURN", .byte = 0x6a },
    // ── Stack ops ──
    .{ .name = "OP_TOALTSTACK", .byte = 0x6b },
    .{ .name = "OP_FROMALTSTACK", .byte = 0x6c },
    .{ .name = "OP_2DROP", .byte = 0x6d },
    .{ .name = "OP_2DUP", .byte = 0x6e },
    .{ .name = "OP_3DUP", .byte = 0x6f },
    .{ .name = "OP_2OVER", .byte = 0x70 },
    .{ .name = "OP_2ROT", .byte = 0x71 },
    .{ .name = "OP_2SWAP", .byte = 0x72 },
    .{ .name = "OP_IFDUP", .byte = 0x73 },
    .{ .name = "OP_DEPTH", .byte = 0x74 },
    .{ .name = "OP_DROP", .byte = 0x75 },
    .{ .name = "OP_DUP", .byte = 0x76 },
    .{ .name = "OP_NIP", .byte = 0x77 },
    .{ .name = "OP_OVER", .byte = 0x78 },
    .{ .name = "OP_PICK", .byte = 0x79 },
    .{ .name = "OP_ROLL", .byte = 0x7a },
    .{ .name = "OP_ROT", .byte = 0x7b },
    .{ .name = "OP_SWAP", .byte = 0x7c },
    .{ .name = "OP_TUCK", .byte = 0x7d },
    // ── Splice / bitwise ──
    .{ .name = "OP_CAT", .byte = 0x7e },
    .{ .name = "OP_SUBSTR", .byte = 0x7f },
    .{ .name = "OP_LEFT", .byte = 0x80 },
    .{ .name = "OP_RIGHT", .byte = 0x81 },
    .{ .name = "OP_SIZE", .byte = 0x82 },
    .{ .name = "OP_INVERT", .byte = 0x83 },
    .{ .name = "OP_AND", .byte = 0x84 },
    .{ .name = "OP_OR", .byte = 0x85 },
    .{ .name = "OP_XOR", .byte = 0x86 },
    .{ .name = "OP_EQUAL", .byte = 0x87 },
    .{ .name = "OP_EQUALVERIFY", .byte = 0x88 },
    // ── Arithmetic ──
    .{ .name = "OP_1ADD", .byte = 0x8b },
    .{ .name = "OP_1SUB", .byte = 0x8c },
    .{ .name = "OP_2MUL", .byte = 0x8d }, // BSV v1.2.0 "Chronicle" restored — doubles top
    .{ .name = "OP_2DIV", .byte = 0x8e }, // BSV v1.2.0 "Chronicle" restored — halves top
    .{ .name = "OP_NEGATE", .byte = 0x8f },
    .{ .name = "OP_ABS", .byte = 0x90 },
    .{ .name = "OP_NOT", .byte = 0x91 },
    .{ .name = "OP_0NOTEQUAL", .byte = 0x92 },
    .{ .name = "OP_ADD", .byte = 0x93 },
    .{ .name = "OP_SUB", .byte = 0x94 },
    .{ .name = "OP_MUL", .byte = 0x95 },
    .{ .name = "OP_DIV", .byte = 0x96 },
    .{ .name = "OP_MOD", .byte = 0x97 },
    .{ .name = "OP_LSHIFT", .byte = 0x98 },
    .{ .name = "OP_RSHIFT", .byte = 0x99 },
    .{ .name = "OP_BOOLAND", .byte = 0x9a },
    .{ .name = "OP_BOOLOR", .byte = 0x9b },
    .{ .name = "OP_NUMEQUAL", .byte = 0x9c },
    .{ .name = "OP_NUMEQUALVERIFY", .byte = 0x9d },
    .{ .name = "OP_NUMNOTEQUAL", .byte = 0x9e },
    .{ .name = "OP_LESSTHAN", .byte = 0x9f },
    .{ .name = "OP_GREATERTHAN", .byte = 0xa0 },
    .{ .name = "OP_LESSTHANOREQUAL", .byte = 0xa1 },
    .{ .name = "OP_GREATERTHANOREQUAL", .byte = 0xa2 },
    .{ .name = "OP_MIN", .byte = 0xa3 },
    .{ .name = "OP_MAX", .byte = 0xa4 },
    .{ .name = "OP_WITHIN", .byte = 0xa5 },
    // ── Crypto ──
    .{ .name = "OP_RIPEMD160", .byte = 0xa6 },
    .{ .name = "OP_SHA1", .byte = 0xa7 },
    .{ .name = "OP_SHA256", .byte = 0xa8 },
    .{ .name = "OP_HASH160", .byte = 0xa9 },
    .{ .name = "OP_HASH256", .byte = 0xaa },
    .{ .name = "OP_CODESEPARATOR", .byte = 0xab },
    .{ .name = "OP_CHECKSIG", .byte = 0xac },
    .{ .name = "OP_CHECKSIGVERIFY", .byte = 0xad },
    .{ .name = "OP_CHECKMULTISIG", .byte = 0xae },
    .{ .name = "OP_CHECKMULTISIGVERIFY", .byte = 0xaf },
    // ── Craig macros (0xB0-0xBF) — cell-engine vocabulary ──
    //
    // CHRONICLE COLLISION (BSV v1.2.0, mainnet 2026-04-07):
    //   OP_XROT_3 (0xb6) collides with OP_LSHIFTNUM (Chronicle).
    //   OP_XROT_4 (0xb7) collides with OP_RSHIFTNUM (Chronicle).
    //
    // The cell-engine's macro.zig still dispatches 0xb6 → xrot(3), 0xb7
    // → xrot(4); BSV consensus now interprets these same bytes as the
    // Chronicle shift opcodes. The sectioned assembler refuses the
    // Craig mnemonics in .lockScript / .unlockScript (see
    // isCellEngineOnlyMacroByte below) so cartridge authors can't
    // emit a byte whose cell-engine semantics differ from its consensus
    // semantics. The mnemonics OP_LSHIFTNUM / OP_RSHIFTNUM declared
    // below are the consensus-context names for the same bytes.
    //
    // Open question (§13 of LOCKSCRIPT-CLEAVAGE.md): relocate XROT-3
    // and XROT-4 to 0xba/0xbb so the cell-engine dispatch table and
    // the BSV consensus opcode table no longer collide. Requires a
    // touch on macro.zig + any scripts using them.
    .{ .name = "OP_XSWAP_2", .byte = 0xb0 },
    .{ .name = "OP_XSWAP_3", .byte = 0xb1 },
    .{ .name = "OP_XSWAP_4", .byte = 0xb2 },
    .{ .name = "OP_XDROP_2", .byte = 0xb3 },
    .{ .name = "OP_XDROP_3", .byte = 0xb4 },
    .{ .name = "OP_XDROP_4", .byte = 0xb5 },
    .{ .name = "OP_XROT_3", .byte = 0xb6 }, // ⚠ collides with OP_LSHIFTNUM
    .{ .name = "OP_XROT_4", .byte = 0xb7 }, // ⚠ collides with OP_RSHIFTNUM
    .{ .name = "OP_HASHCAT", .byte = 0xb8 },

    // ── BSV v1.2.0 "Chronicle" — new shift opcodes (consensus) ──
    // Bytes shared with XROT-3/4 above; intent is disambiguated by
    // section context. Spec: bitcoin-sv-specs/protocol updates/chronicle-spec.md
    .{ .name = "OP_LSHIFTNUM", .byte = 0xb6 },
    .{ .name = "OP_RSHIFTNUM", .byte = 0xb7 },
    // ── Plexus (0xC0-0xCF) ──
    .{ .name = "OP_CHECKLINEARTYPE", .byte = 0xc0 },
    .{ .name = "OP_CHECKAFFINETYPE", .byte = 0xc1 },
    .{ .name = "OP_CHECKRELEVANTTYPE", .byte = 0xc2 },
    .{ .name = "OP_CHECKCAPABILITY", .byte = 0xc3 },
    .{ .name = "OP_CHECKIDENTITY", .byte = 0xc4 },
    .{ .name = "OP_ASSERTLINEAR", .byte = 0xc5 },
    .{ .name = "OP_CHECKDOMAINFLAG", .byte = 0xc6 },
    .{ .name = "OP_CHECKTYPEHASH", .byte = 0xc7 },
    .{ .name = "OP_DEREFPOINTER", .byte = 0xc8 },
    .{ .name = "OP_READHEADER", .byte = 0xc9 },
    .{ .name = "OP_CELLCREATE", .byte = 0xca },
    .{ .name = "OP_DEMOTE", .byte = 0xcb },
    .{ .name = "OP_READPAYLOAD", .byte = 0xcc },
    .{ .name = "OP_SIGN", .byte = 0xcd },
    .{ .name = "OP_DECREMENTBUDGET", .byte = 0xce },
    .{ .name = "OP_REFILLBUDGET", .byte = 0xcf },
    // ── Hostcall (0xD0) ──
    .{ .name = "OP_CALLHOST", .byte = 0xd0 },
    // ── Plexus-family cell-mutation op carved out of the hostcall
    //    reserved range — sibling to OP_READPAYLOAD (0xCC). See
    //    plexus.zig opWritePayload.
    .{ .name = "OP_WRITEPAYLOAD", .byte = 0xd1 },
    // ── Routing (0xE0-0xEF) ──
    .{ .name = "OP_BRANCHONOUTPUT", .byte = 0xe0 },
};

const AssembleError = error{
    unknown_mnemonic,
    invalid_push,
    invalid_hex,
    pushdata_too_large,
    out_of_memory,
    // Sectioned-assembly errors (PR-2 of LOCKSCRIPT-CLEAVAGE.md §8.1):
    malformed_section,              // missing `{` or `}` after `.<name>`
    duplicate_section,              // same section declared twice
    unknown_section,                // `.<name>` not one of lock/unlock/handler
    non_standard_in_lockscript,     // unrecognised non-consensus byte in .lockScript
    non_standard_in_unlockscript,   // unrecognised non-consensus byte in .unlockScript
    slot_in_non_slot_aware_path,    // <SIG>/<PUBKEY> seen in .lockScript or .handler
    // Chronicle (BSV v1.2.0) — bytes 0xB0-0xB8 are CONSENSUS valid as
    // NOPs/Chronicle ops but cell-engine ALSO claims them for Craig
    // macros. Source-level refuse Craig mnemonics in consensus
    // sections to prevent silent semantic divergence.
    cell_engine_macro_in_consensus_section,
};

/// Returns true if the normalised mnemonic name is a Craig macro that
/// the cell-engine's macro.zig dispatches, even though Bitcoin SV
/// consensus interprets the underlying byte differently (NOP, Chronicle
/// shift, or undefined). These mnemonics are refused at the source
/// level in .lockScript / .unlockScript to prevent silent divergence
/// between cell-engine and consensus semantics.
///
/// Disambiguates by MNEMONIC, not byte: OP_XROT_3 and OP_LSHIFTNUM
/// share byte 0xB6 in the OPCODES table; OP_XROT_3 is refused but
/// OP_LSHIFTNUM is permitted because the script author's chosen name
/// expresses intent.
fn isCellEngineOnlyMnemonic(normalised_name: []const u8) bool {
    const CELL_ENGINE_ONLY = [_][]const u8{
        "OP_XSWAP_2", "OP_XSWAP_3", "OP_XSWAP_4",
        "OP_XDROP_2", "OP_XDROP_3", "OP_XDROP_4",
        "OP_XROT_3",  "OP_XROT_4",
        "OP_HASHCAT",
    };
    for (CELL_ENGINE_ONLY) |n| {
        if (std.mem.eql(u8, normalised_name, n)) return true;
    }
    return false;
}

/// Consensus-context opcode lookup. Wraps `lookupOpcode` but refuses
/// Craig macro mnemonics (via `isCellEngineOnlyMnemonic`). Used by
/// the `.lockScript` / `.unlockScript` body assemblers to keep
/// cleavage-violating ambiguity out of broadcast scripts at the
/// source level.
fn lookupOpcodeConsensus(name: []const u8) ?u8 {
    // Normalise to uppercase + canonical OP_ prefix for the mnemonic check.
    var buf: [64]u8 = undefined;
    if (name.len > buf.len) return null;
    for (name, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    const upper = buf[0..name.len];

    // Form the OP_-prefixed canonical name if not already prefixed.
    var canon_buf: [64]u8 = undefined;
    const canonical: []const u8 = if (std.mem.startsWith(u8, upper, "OP_"))
        upper
    else blk: {
        if (upper.len + 3 > canon_buf.len) return null;
        @memcpy(canon_buf[0..3], "OP_");
        @memcpy(canon_buf[3 .. 3 + upper.len], upper);
        break :blk canon_buf[0 .. 3 + upper.len];
    };

    if (isCellEngineOnlyMnemonic(canonical)) return null;
    return lookupOpcode(name);
}

/// Look up an opcode by name. Case-insensitive; tolerates source-side
/// omission of the `OP_` prefix.
fn lookupOpcode(name: []const u8) ?u8 {
    var buf: [64]u8 = undefined;
    if (name.len > buf.len) return null;
    const normalized: []const u8 = blk: {
        for (name, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
        break :blk buf[0..name.len];
    };
    // Try with OP_ prefix first; if not found and the source omitted it, add.
    for (OPCODES) |op| {
        if (std.mem.eql(u8, op.name, normalized)) return op.byte;
    }
    if (!std.mem.startsWith(u8, normalized, "OP_")) {
        var with_prefix: [64]u8 = undefined;
        if (normalized.len + 3 > with_prefix.len) return null;
        @memcpy(with_prefix[0..3], "OP_");
        @memcpy(with_prefix[3 .. 3 + normalized.len], normalized);
        const prefixed = with_prefix[0 .. 3 + normalized.len];
        for (OPCODES) |op| {
            if (std.mem.eql(u8, op.name, prefixed)) return op.byte;
        }
    }
    return null;
}

/// Append `bytes` to `out` with BSV Script length-prefixing convention.
fn appendPushdata(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    if (bytes.len == 0) {
        try out.append(allocator, 0x00); // OP_0
        return;
    }
    if (bytes.len == 1 and bytes[0] >= 1 and bytes[0] <= 16) {
        // OP_1..OP_16 short form
        try out.append(allocator, 0x50 + bytes[0]);
        return;
    }
    if (bytes.len <= 75) {
        try out.append(allocator, @intCast(bytes.len));
        try out.appendSlice(allocator, bytes);
        return;
    }
    if (bytes.len <= 255) {
        try out.append(allocator, 0x4c); // OP_PUSHDATA1
        try out.append(allocator, @intCast(bytes.len));
        try out.appendSlice(allocator, bytes);
        return;
    }
    if (bytes.len <= 0xffff) {
        try out.append(allocator, 0x4d); // OP_PUSHDATA2
        var len_le: [2]u8 = undefined;
        std.mem.writeInt(u16, &len_le, @intCast(bytes.len), .little);
        try out.appendSlice(allocator, &len_le);
        try out.appendSlice(allocator, bytes);
        return;
    }
    if (bytes.len <= 0xffffffff) {
        try out.append(allocator, 0x4e); // OP_PUSHDATA4
        var len_le: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_le, @intCast(bytes.len), .little);
        try out.appendSlice(allocator, &len_le);
        try out.appendSlice(allocator, bytes);
        return;
    }
    return AssembleError.pushdata_too_large;
}

/// Decode lowercase hex to bytes. Leading "0x" stripped if present.
fn decodeHex(allocator: std.mem.Allocator, hex_in: []const u8) ![]u8 {
    var hex = hex_in;
    if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X")) {
        hex = hex[2..];
    }
    if (hex.len % 2 != 0) return AssembleError.invalid_hex;
    var out = try allocator.alloc(u8, hex.len / 2);
    errdefer allocator.free(out);
    for (0..out.len) |i| {
        const hi = std.fmt.charToDigit(hex[i * 2], 16) catch return AssembleError.invalid_hex;
        const lo = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return AssembleError.invalid_hex;
        out[i] = (@as(u8, hi) << 4) | @as(u8, lo);
    }
    return out;
}

/// Parse a `PUSH ...` directive's argument and append the appropriate
/// pushdata bytes to `out`. Argument forms: `0x<hex>`, `"string"`, or
/// `<integer>`.
fn handlePush(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    arg: []const u8,
) !void {
    if (arg.len == 0) return AssembleError.invalid_push;

    // String literal
    if (arg[0] == '"' and arg[arg.len - 1] == '"' and arg.len >= 2) {
        try appendPushdata(out, allocator, arg[1 .. arg.len - 1]);
        return;
    }
    // Hex literal
    if (std.mem.startsWith(u8, arg, "0x") or std.mem.startsWith(u8, arg, "0X")) {
        const bytes = try decodeHex(allocator, arg);
        defer allocator.free(bytes);
        try appendPushdata(out, allocator, bytes);
        return;
    }
    // Integer literal
    const n = std.fmt.parseInt(i64, arg, 10) catch return AssembleError.invalid_push;
    if (n == 0) {
        try out.append(allocator, 0x00); // OP_0
        return;
    }
    if (n == -1) {
        try out.append(allocator, 0x4f); // OP_1NEGATE
        return;
    }
    if (n >= 1 and n <= 16) {
        try out.append(allocator, 0x50 + @as(u8, @intCast(n)));
        return;
    }
    // Minimal CScriptNum encoding (sign-magnitude little-endian).
    var buf: [9]u8 = undefined;
    var len: usize = 0;
    const negative = n < 0;
    var abs: u64 = if (negative) @intCast(-n) else @intCast(n);
    while (abs > 0) : (len += 1) {
        buf[len] = @truncate(abs & 0xff);
        abs >>= 8;
    }
    if (buf[len - 1] & 0x80 != 0) {
        buf[len] = if (negative) 0x80 else 0x00;
        len += 1;
    } else if (negative) {
        buf[len - 1] |= 0x80;
    }
    try appendPushdata(out, allocator, buf[0..len]);
}

/// Assemble a cell-engine source string to bytecode.
///
/// Flat-source mode — equivalent to a single `.handler {}` section with
/// the full vocabulary available. The sectioned-source path goes through
/// `assembleSectioned` below.
pub fn assemble(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    return assembleBody(allocator, source, false, false);
}

/// Assemble the lines inside a section body.
///
/// `slot_aware` — when true, callers are responsible for handling
/// `PUSH <SIG>` / `PUSH <PUBKEY>` themselves (see
/// `assembleUnlockScriptBody`); this function rejects them as a guard.
///
/// `consensus_mode` — when true, source-level mnemonics are looked up
/// via `lookupOpcodeConsensus`, which refuses the Craig macro family
/// (XSWAP_N/XDROP_N/XROT_N/HASHCAT) whose bytes collide with consensus
/// NOPs or Chronicle shift ops. Used for `.lockScript` / `.unlockScript`
/// to prevent silent semantic divergence between cell-engine and
/// consensus interpretation.
fn assembleBody(
    allocator: std.mem.Allocator,
    source: []const u8,
    slot_aware: bool,
    consensus_mode: bool,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.tokenizeAny(u8, source, "\r\n");
    while (lines.next()) |raw_line| {
        // Strip comments + trim whitespace.
        var line = raw_line;
        if (std.mem.indexOf(u8, line, "#")) |i| line = line[0..i];
        if (std.mem.indexOf(u8, line, "//")) |i| line = line[0..i];
        line = std.mem.trim(u8, line, " \t");
        if (line.len == 0) continue;

        // PUSH directive?
        if (std.ascii.startsWithIgnoreCase(line, "PUSH")) {
            const rest = std.mem.trim(u8, line[4..], " \t");
            // Slot-aware paths handle <SIG> and <PUBKEY> in the caller.
            if (slot_aware and rest.len >= 2 and rest[0] == '<' and rest[rest.len - 1] == '>') {
                return AssembleError.slot_in_non_slot_aware_path;
            }
            try handlePush(&out, allocator, rest);
            continue;
        }

        // Plain opcode mnemonic. Consensus mode looks up via the
        // consensus-restricted table (refuses Craig macros at bytes
        // 0xB0-0xB5, 0xB8). Handler mode uses the full vocabulary.
        if (consensus_mode) {
            // Try consensus lookup first.
            if (lookupOpcodeConsensus(line)) |byte| {
                try out.append(allocator, byte);
                continue;
            }
            // If a cell-engine-only macro mnemonic appeared in a
            // consensus section, surface the specific error.
            if (lookupOpcode(line) != null) {
                return AssembleError.cell_engine_macro_in_consensus_section;
            }
            return AssembleError.unknown_mnemonic;
        }
        const byte = lookupOpcode(line) orelse return AssembleError.unknown_mnemonic;
        try out.append(allocator, byte);
    }

    return out.toOwnedSlice(allocator);
}

// ── Sectioned assembly (PR-2 of LOCKSCRIPT-CLEAVAGE.md §8.1) ──────────
//
// A `.cs` source file may carry three named sections:
//
//   .lockScript   { ... }   — bytes for the tx output scriptPubKey
//                              (must be consensus-subset)
//   .unlockScript { ... }   — template bytes for the spending tx scriptSig
//                              (must be consensus-subset; may contain
//                              `<SIG>` / `<PUBKEY>` slot placeholders)
//   .handler      { ... }   — bytes for cellTypes[i].handler.script
//                              (full vocabulary)
//
// Each section is optional. A source containing NO section markers is
// treated as a flat handler script (PR5a backward-compat).
//
// Output (via `assembleSectioned`):
//   - lockScript bytes (or empty if section absent)
//   - unlockScript template bytes (or empty if section absent)
//   - unlockScript slot positions (kind + offset + length)
//   - handler bytes + sha256
//
// The consensus-subset validator enforces no byte ≥ 0xB0 in
// .lockScript / .unlockScript — this is the assembler-side enforcement
// of the cleavage invariant from LOCKSCRIPT-CLEAVAGE.md §0.

/// Slot kinds — placeholders the broker fills in at sign-and-broadcast
/// time when constructing the spending tx's unlockScript.
pub const SlotKind = enum {
    sig,    // 72-byte DER signature + sighash flag
    pubkey, // 33-byte compressed secp256k1 pubkey
};

/// A single slot's position inside the unlockScript template.
pub const Slot = struct {
    kind: SlotKind,
    /// Byte offset of the FIRST data byte of the placeholder pushdata
    /// (i.e., one past the length-prefix byte). The broker overwrites
    /// `length` bytes starting at this offset.
    offset: usize,
    /// Length of the placeholder region in bytes (72 for sig, 33 for pubkey).
    length: usize,
};

/// Fixed placeholder sizes for the two slot kinds. Chosen to match the
/// typical encoded sizes of BSV ECDSA signatures + compressed pubkeys.
const SIG_PLACEHOLDER_LEN: usize = 72;
const PUBKEY_PLACEHOLDER_LEN: usize = 33;

/// The structured result of a sectioned assembly.
pub const SectionedOutput = struct {
    lockScript: []u8,
    unlockScriptTemplate: []u8,
    unlockScriptSlots: []Slot,
    handler: []u8,
    handlerSha256: [32]u8,

    pub fn deinit(self: *SectionedOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.lockScript);
        allocator.free(self.unlockScriptTemplate);
        allocator.free(self.unlockScriptSlots);
        allocator.free(self.handler);
    }
};

/// Detect whether a source string contains any section directives. Used
/// by `main()` to dispatch between flat and sectioned output formats.
pub fn isSectioned(source: []const u8) bool {
    return std.mem.indexOf(u8, source, ".lockScript") != null or
        std.mem.indexOf(u8, source, ".unlockScript") != null or
        std.mem.indexOf(u8, source, ".handler") != null;
}

/// Walk a script byte sequence and return the position of the first
/// OPCODE byte that's outside the consensus subset. Skips pushdata
/// PAYLOAD bytes — those can legitimately contain any value (e.g., a
/// SHA-256 hash pushed as data routinely has bytes ≥ 0xB0).
///
/// Walks the pushdata directives:
///   0x01..0x4B  → direct push of N bytes (N == opcode byte)
///   0x4C        → OP_PUSHDATA1: next 1 byte is length
///   0x4D        → OP_PUSHDATA2: next 2 bytes (LE) are length
///   0x4E        → OP_PUSHDATA4: next 4 bytes (LE) are length
///   else        → single-byte opcode; check against the consensus set
///
/// Consensus set (post-Chronicle, BSV v1.2.0, mainnet 2026-04-07):
///   0x00..0xAF  → standard Bitcoin Script (incl. Chronicle-restored
///                 OP_VER 0x62, OP_VERIF 0x65, OP_VERNOTIF 0x66,
///                 OP_2MUL 0x8d, OP_2DIV 0x8e)
///   0xB6        → OP_LSHIFTNUM (Chronicle)
///   0xB7        → OP_RSHIFTNUM (Chronicle)
///   else ≥ 0xB0 → cell-engine vocabulary (Craig macros, Plexus,
///                 OP_CALLHOST, routing) — cleavage violation
///
/// The source-level `lookupOpcodeConsensus` ensures consensus sections
/// reject Craig macro mnemonics; this walker is the defense-in-depth
/// check on the assembled bytes.
///
/// Returns null if all opcode bytes are consensus-valid.
/// Returns the offending byte's offset if a violation is found.
fn findFirstSemantosOpcode(bytes: []const u8) ?usize {
    var i: usize = 0;
    while (i < bytes.len) {
        const b = bytes[i];
        if (b >= 0x01 and b <= 0x4B) {
            // Direct push of b bytes (data).
            i += 1 + @as(usize, b);
            continue;
        }
        if (b == 0x4C) {
            if (i + 1 >= bytes.len) return i; // truncated; treat as malformed
            const len = bytes[i + 1];
            i += 2 + @as(usize, len);
            continue;
        }
        if (b == 0x4D) {
            if (i + 2 >= bytes.len) return i;
            const len = std.mem.readInt(u16, bytes[i + 1 ..][0..2], .little);
            i += 3 + @as(usize, len);
            continue;
        }
        if (b == 0x4E) {
            if (i + 4 >= bytes.len) return i;
            const len = std.mem.readInt(u32, bytes[i + 1 ..][0..4], .little);
            i += 5 + @as(usize, len);
            continue;
        }
        // Single-byte opcode. Bytes < 0xB0 are standard Bitcoin Script.
        // Bytes 0xB6 and 0xB7 are Chronicle (OP_LSHIFTNUM / OP_RSHIFTNUM).
        // Everything else >= 0xB0 is cell-engine vocabulary.
        if (b < 0xB0) {
            i += 1;
            continue;
        }
        if (b == 0xB6 or b == 0xB7) {
            i += 1;
            continue;
        }
        return i;
    }
    return null;
}

/// Parse the source into three section bodies. Empty bodies are returned
/// when a section is absent. Section nesting is not supported in v1.
const Sections = struct {
    lock: []const u8,
    unlock: []const u8,
    handler: []const u8,
};

fn parseSections(source: []const u8) !Sections {
    var lock: []const u8 = "";
    var unlock: []const u8 = "";
    var handler: []const u8 = "";

    var rest = source;
    while (rest.len > 0) {
        // Find the next `.<name> {` directive. Skips dots inside
        // comments (`#` and `//` to end-of-line) and dots inside
        // string literals — without this, a `#` comment mentioning
        // ".md" or ".handler" or anything punctuation-y trips the
        // section parser.
        const dot = findNextSectionDot(rest) orelse break;
        rest = rest[dot..];

        const open_brace = std.mem.indexOf(u8, rest, "{") orelse return AssembleError.malformed_section;
        const header = std.mem.trim(u8, rest[0..open_brace], " \t\r\n.");
        // Find matching close brace (no nesting in v1).
        const remainder = rest[open_brace + 1 ..];
        const close_brace = std.mem.indexOf(u8, remainder, "}") orelse return AssembleError.malformed_section;
        const body = remainder[0..close_brace];

        if (std.mem.eql(u8, header, "lockScript")) {
            if (lock.len != 0) return AssembleError.duplicate_section;
            lock = body;
        } else if (std.mem.eql(u8, header, "unlockScript")) {
            if (unlock.len != 0) return AssembleError.duplicate_section;
            unlock = body;
        } else if (std.mem.eql(u8, header, "handler")) {
            if (handler.len != 0) return AssembleError.duplicate_section;
            handler = body;
        } else {
            return AssembleError.unknown_section;
        }

        rest = remainder[close_brace + 1 ..];
    }

    return .{ .lock = lock, .unlock = unlock, .handler = handler };
}

/// Scan `s` for the next `.` that is a real section-directive lead
/// (not inside a `#`/`//` comment, not inside a "..." string literal).
/// Returns the byte offset of that dot, or null if none is found.
///
/// This is conservative: it doesn't validate that the dot is followed
/// by a known section name — the caller does that. The job here is
/// just to skip dots in comments + strings so they don't masquerade
/// as section markers.
fn findNextSectionDot(s: []const u8) ?usize {
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        // Line comment: `#` … to EOL.
        if (c == '#') {
            i = (std.mem.indexOfScalarPos(u8, s, i, '\n') orelse s.len);
            continue;
        }
        // Line comment: `//` … to EOL.
        if (c == '/' and i + 1 < s.len and s[i + 1] == '/') {
            i = (std.mem.indexOfScalarPos(u8, s, i + 2, '\n') orelse s.len);
            continue;
        }
        // String literal: `"..."` — skip to the matching close quote.
        // Doesn't handle escape sequences (the assembler doesn't either
        // — PUSH "literal" treats backslash as a literal byte). Good
        // enough to keep dots inside string contents out of the
        // section scan.
        if (c == '"') {
            i += 1;
            while (i < s.len and s[i] != '"') : (i += 1) {}
            if (i < s.len) i += 1; // consume the closing quote
            continue;
        }
        if (c == '.') return i;
        i += 1;
    }
    return null;
}

/// Assemble the unlockScript body with slot-aware PUSH handling +
/// consensus-mode opcode lookup. Walks the body line-by-line (same
/// scanner as `assembleBody`) but recognizes `PUSH <SIG>` /
/// `PUSH <PUBKEY>` and emits fixed-size placeholders, AND refuses Craig
/// macro mnemonics (the cleavage source-level guard).
fn assembleUnlockScriptBody(
    allocator: std.mem.Allocator,
    source: []const u8,
    slots: *std.ArrayList(Slot),
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.tokenizeAny(u8, source, "\r\n");
    while (lines.next()) |raw_line| {
        var line = raw_line;
        if (std.mem.indexOf(u8, line, "#")) |i| line = line[0..i];
        if (std.mem.indexOf(u8, line, "//")) |i| line = line[0..i];
        line = std.mem.trim(u8, line, " \t");
        if (line.len == 0) continue;

        if (std.ascii.startsWithIgnoreCase(line, "PUSH")) {
            const rest = std.mem.trim(u8, line[4..], " \t");
            // Detect <SIG> / <PUBKEY> slots.
            if (std.ascii.eqlIgnoreCase(rest, "<SIG>")) {
                try out.append(allocator, @intCast(SIG_PLACEHOLDER_LEN));
                const offset = out.items.len;
                try out.appendNTimes(allocator, 0, SIG_PLACEHOLDER_LEN);
                try slots.append(allocator, .{ .kind = .sig, .offset = offset, .length = SIG_PLACEHOLDER_LEN });
                continue;
            }
            if (std.ascii.eqlIgnoreCase(rest, "<PUBKEY>")) {
                try out.append(allocator, @intCast(PUBKEY_PLACEHOLDER_LEN));
                const offset = out.items.len;
                try out.appendNTimes(allocator, 0, PUBKEY_PLACEHOLDER_LEN);
                try slots.append(allocator, .{ .kind = .pubkey, .offset = offset, .length = PUBKEY_PLACEHOLDER_LEN });
                continue;
            }
            // Non-slot PUSH — handle normally.
            try handlePush(&out, allocator, rest);
            continue;
        }

        // unlockScript is a consensus section — refuse Craig macro
        // mnemonics at the source level. The matching byte-walker
        // check in `assembleSectioned` is defense-in-depth.
        if (lookupOpcodeConsensus(line)) |byte| {
            try out.append(allocator, byte);
            continue;
        }
        if (lookupOpcode(line) != null) {
            return AssembleError.cell_engine_macro_in_consensus_section;
        }
        return AssembleError.unknown_mnemonic;
    }

    return out.toOwnedSlice(allocator);
}

/// Assemble a sectioned source file. Returns the structured output;
/// caller owns the allocations and must call `deinit`.
pub fn assembleSectioned(allocator: std.mem.Allocator, source: []const u8) !SectionedOutput {
    const sections = try parseSections(source);

    // .lockScript — assemble in consensus mode (refuses Craig macros at
    // source level) + validate consensus subset (refuses semantos bytes
    // post-assembly as defense-in-depth).
    const lock_bytes = if (sections.lock.len > 0)
        try assembleBody(allocator, sections.lock, true, true)
    else
        try allocator.alloc(u8, 0);
    errdefer allocator.free(lock_bytes);

    if (findFirstSemantosOpcode(lock_bytes) != null) {
        return AssembleError.non_standard_in_lockscript;
    }

    // .unlockScript — assemble with slot-aware handling + consensus
    // mode (handled inside assembleUnlockScriptBody) + validate
    // consensus subset post-assembly.
    var slots: std.ArrayList(Slot) = .empty;
    errdefer slots.deinit(allocator);

    const unlock_bytes = if (sections.unlock.len > 0)
        try assembleUnlockScriptBody(allocator, sections.unlock, &slots)
    else
        try allocator.alloc(u8, 0);
    errdefer allocator.free(unlock_bytes);

    if (findFirstSemantosOpcode(unlock_bytes) != null) {
        return AssembleError.non_standard_in_unlockscript;
    }

    // .handler — full vocabulary (consensus_mode=false).
    const handler_bytes = if (sections.handler.len > 0)
        try assembleBody(allocator, sections.handler, false, false)
    else
        try allocator.alloc(u8, 0);
    errdefer allocator.free(handler_bytes);

    // sha256 of handler bytes — for manifest scriptHash pinning.
    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(handler_bytes, &sha, .{});

    const slot_slice = try slots.toOwnedSlice(allocator);

    return .{
        .lockScript = lock_bytes,
        .unlockScriptTemplate = unlock_bytes,
        .unlockScriptSlots = slot_slice,
        .handler = handler_bytes,
        .handlerSha256 = sha,
    };
}

/// CLI entry point. Reads input file, prints `<hex>\n<sha256>\n` to stdout.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("usage: asm <input.cs>", .{});
        std.process.exit(2);
    }

    const source = try std.fs.cwd().readFileAlloc(allocator, args[1], 1 << 20);
    defer allocator.free(source);

    // Zig 0.15 stdio pattern.
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    if (isSectioned(source)) {
        // Sectioned output: emit a structured multi-line record so
        // downstream tooling (the cartridge build pipeline) can parse
        // each section + slot offsets without re-running the assembler.
        var result = try assembleSectioned(allocator, source);
        defer result.deinit(allocator);

        try stdout.print("LOCKSCRIPT_HEX:", .{});
        try writeHex(stdout, result.lockScript);
        try stdout.print("\n", .{});

        try stdout.print("UNLOCKSCRIPT_TEMPLATE_HEX:", .{});
        try writeHex(stdout, result.unlockScriptTemplate);
        try stdout.print("\n", .{});

        try stdout.print("UNLOCKSCRIPT_SLOTS:{d}\n", .{result.unlockScriptSlots.len});
        for (result.unlockScriptSlots) |slot| {
            const kind_str = switch (slot.kind) {
                .sig => "SIG",
                .pubkey => "PUBKEY",
            };
            try stdout.print("SLOT:{s}@{d}:{d}\n", .{ kind_str, slot.offset, slot.length });
        }

        try stdout.print("HANDLER_HEX:", .{});
        try writeHex(stdout, result.handler);
        try stdout.print("\n", .{});

        try stdout.print("HANDLER_SHA256:", .{});
        try writeHex(stdout, &result.handlerSha256);
        try stdout.print("\n", .{});
        try stdout.flush();
        return;
    }

    // Flat-source backward-compat path (PR5a behaviour preserved).
    const bytecode = try assemble(allocator, source);
    defer allocator.free(bytecode);

    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytecode, &sha, .{});

    try writeHex(stdout, bytecode);
    try stdout.print("\n", .{});
    try writeHex(stdout, &sha);
    try stdout.print("\n", .{});
    try stdout.flush();
}

fn writeHex(writer: anytype, bytes: []const u8) !void {
    for (bytes) |b| {
        try writer.print("{x:0>2}", .{b});
    }
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "assemble — basic opcode lookup OP_1 OP_VERIFY" {
    const bc = try assemble(testing.allocator, "OP_1\nOP_VERIFY\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x69 }, bc);
}

test "assemble — case insensitive + OP_ prefix optional" {
    const bc = try assemble(testing.allocator, "op_1\nverify\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x69 }, bc);
}

test "assemble — comments stripped" {
    const bc = try assemble(testing.allocator,
        \\# leading comment
        \\OP_1   # trailing comment
        \\// double-slash also works
        \\OP_VERIFY
    );
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x69 }, bc);
}

test "assemble — PUSH integer round-trips OP_1..OP_16 short form" {
    const bc = try assemble(testing.allocator, "PUSH 5\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{0x55}, bc);
}

test "assemble — PUSH hex pushes data with length prefix" {
    const bc = try assemble(testing.allocator, "PUSH 0xdeadbeef\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{ 0x04, 0xde, 0xad, 0xbe, 0xef }, bc);
}

test "assemble — PUSH string pushes UTF-8 bytes" {
    const bc = try assemble(testing.allocator,
        \\PUSH "host_verify_beef_spv"
    );
    defer testing.allocator.free(bc);
    // 20 chars, length prefix 0x14 + the bytes = 21 bytes total
    try testing.expectEqual(@as(usize, 21), bc.len);
    try testing.expectEqual(@as(u8, 0x14), bc[0]);
    try testing.expectEqualStrings("host_verify_beef_spv", bc[1..]);
}

test "assemble — PUSH 76-byte hex uses OP_PUSHDATA1" {
    var src: [256]u8 = undefined;
    var i: usize = 0;
    @memcpy(src[i .. i + 5], "PUSH ");
    i += 5;
    src[i] = '0';
    src[i + 1] = 'x';
    i += 2;
    var j: usize = 0;
    while (j < 76) : (j += 1) {
        src[i + j * 2] = 'a';
        src[i + j * 2 + 1] = 'b';
    }
    i += 76 * 2;
    src[i] = '\n';
    i += 1;

    const bc = try assemble(testing.allocator, src[0..i]);
    defer testing.allocator.free(bc);
    try testing.expectEqual(@as(u8, 0x4c), bc[0]); // OP_PUSHDATA1
    try testing.expectEqual(@as(u8, 76), bc[1]); // length
    try testing.expectEqual(@as(usize, 78), bc.len);
}

test "assemble — Plexus opcode OP_CELLCREATE → 0xCA" {
    const bc = try assemble(testing.allocator, "OP_CELLCREATE\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{0xca}, bc);
}

test "assemble — OP_CALLHOST → 0xD0" {
    const bc = try assemble(testing.allocator, "OP_CALLHOST\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{0xd0}, bc);
}

test "assemble — OP_WRITEPAYLOAD → 0xD1" {
    const bc = try assemble(testing.allocator, "OP_WRITEPAYLOAD\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{0xd1}, bc);
}

test "assemble — Craig macro OP_HASHCAT → 0xB8" {
    const bc = try assemble(testing.allocator, "OP_HASHCAT\n");
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{0xb8}, bc);
}

test "assemble — unknown mnemonic surfaces error" {
    try testing.expectError(AssembleError.unknown_mnemonic, assemble(testing.allocator, "OP_BOGUS\n"));
}

test "assemble — golden match against Rúnar-compiled `Always` predicate" {
    // Cross-tool validation: this script should produce byte-for-byte
    // the same hex (`5151517777`) that the external Rúnar Go compiler
    // emits for the canonical `func (c *Always) Verify() { runar.Assert(1 == 1) }`
    // smart contract — referenced as a golden fixture in
    // `runtime/semantos-brain/src/policy_runtime.zig` (§11.10 order
    // 4b-1, upstream icellan/runar @ d4c3b6e). If this test ever
    // diverges from `5151517777`, either the assembler regressed or
    // the Rúnar compiler changed its codegen — both worth catching.
    const bc = try assemble(testing.allocator,
        \\OP_1
        \\OP_1
        \\OP_1
        \\OP_NIP
        \\OP_NIP
    );
    defer testing.allocator.free(bc);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x51, 0x51, 0x77, 0x77 }, bc);
}

test "assemble — composite script: load name + CALLHOST + verify" {
    const bc = try assemble(testing.allocator,
        \\# Smoke pattern that the bsv-spv-verify script will use:
        \\PUSH "host_verify_beef_spv"
        \\OP_CALLHOST
        \\OP_0
        \\OP_EQUAL
        \\OP_VERIFY
        \\OP_1
    );
    defer testing.allocator.free(bc);
    // Expected: 0x14 + "host_verify_beef_spv"(20B) + 0xd0 + 0x00 + 0x87 + 0x69 + 0x51 = 26 bytes
    try testing.expectEqual(@as(usize, 26), bc.len);
    try testing.expectEqual(@as(u8, 0x14), bc[0]);
    try testing.expectEqual(@as(u8, 0xd0), bc[21]);
    try testing.expectEqual(@as(u8, 0x00), bc[22]);
    try testing.expectEqual(@as(u8, 0x87), bc[23]);
    try testing.expectEqual(@as(u8, 0x69), bc[24]);
    try testing.expectEqual(@as(u8, 0x51), bc[25]);
}

// ── PR-2 sectioned-assembly tests ─────────────────────────────────────

test "isSectioned: detects .handler directive" {
    try testing.expect(isSectioned(".handler { OP_1 }"));
    try testing.expect(isSectioned(".lockScript { OP_DUP }"));
    try testing.expect(isSectioned(".unlockScript { OP_NIP }"));
    try testing.expect(!isSectioned("OP_1\nOP_VERIFY\n"));
    try testing.expect(!isSectioned("# this script has no sections\nOP_1\n"));
}

test "assembleSectioned: handler-only source" {
    var result = try assembleSectioned(testing.allocator,
        \\.handler {
        \\  OP_1
        \\  OP_VERIFY
        \\}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), result.lockScript.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptSlots.len);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x69 }, result.handler);
    // sha256 of [0x51, 0x69] is a known value — just verify it's non-zero.
    var all_zero = true;
    for (result.handlerSha256) |b| if (b != 0) { all_zero = false; break; };
    try testing.expect(!all_zero);
}

test "assembleSectioned: lockScript + handler + sha256" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  PUSH 0xdeadbeef
        \\  OP_DROP
        \\}
        \\
        \\.handler {
        \\  OP_DUP
        \\  OP_READPAYLOAD
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);

    // lockScript: 0x04 + de ad be ef + 0x75 (OP_DROP) = 6 bytes
    try testing.expectEqual(@as(usize, 6), result.lockScript.len);
    try testing.expectEqual(@as(u8, 0x75), result.lockScript[5]);

    // handler: OP_DUP (0x76) + OP_READPAYLOAD (0xcc) + OP_1 (0x51)
    try testing.expectEqualSlices(u8, &.{ 0x76, 0xcc, 0x51 }, result.handler);
}

test "assembleSectioned: rejects Plexus byte in .lockScript" {
    const err = assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_CHECKCAPABILITY
        \\}
    );
    try testing.expectError(AssembleError.non_standard_in_lockscript, err);
}

test "assembleSectioned: rejects OP_CALLHOST in .unlockScript" {
    const err = assembleSectioned(testing.allocator,
        \\.unlockScript {
        \\  OP_CALLHOST
        \\}
    );
    try testing.expectError(AssembleError.non_standard_in_unlockscript, err);
}

test "assembleSectioned: full Plexus vocabulary allowed in .handler" {
    var result = try assembleSectioned(testing.allocator,
        \\.handler {
        \\  OP_CHECKCAPABILITY
        \\  OP_CHECKIDENTITY
        \\  OP_CELLCREATE
        \\  OP_CALLHOST
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0xc3, 0xc4, 0xca, 0xd0, 0x51 }, result.handler);
}

test "assembleSectioned: <SIG> slot in .unlockScript records position + length" {
    var result = try assembleSectioned(testing.allocator,
        \\.unlockScript {
        \\  PUSH <SIG>
        \\  PUSH <PUBKEY>
        \\}
    );
    defer result.deinit(testing.allocator);

    // Template: 0x48 + 72 zeros (SIG) + 0x21 + 33 zeros (PUBKEY)
    // = 1 + 72 + 1 + 33 = 107 bytes
    try testing.expectEqual(@as(usize, 107), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(u8, 0x48), result.unlockScriptTemplate[0]); // sig length prefix
    try testing.expectEqual(@as(u8, 0x21), result.unlockScriptTemplate[73]); // pubkey length prefix

    // Two slots recorded: SIG@1 length=72, PUBKEY@74 length=33
    try testing.expectEqual(@as(usize, 2), result.unlockScriptSlots.len);
    try testing.expectEqual(SlotKind.sig, result.unlockScriptSlots[0].kind);
    try testing.expectEqual(@as(usize, 1), result.unlockScriptSlots[0].offset);
    try testing.expectEqual(@as(usize, 72), result.unlockScriptSlots[0].length);
    try testing.expectEqual(SlotKind.pubkey, result.unlockScriptSlots[1].kind);
    try testing.expectEqual(@as(usize, 74), result.unlockScriptSlots[1].offset);
    try testing.expectEqual(@as(usize, 33), result.unlockScriptSlots[1].length);
}

test "assembleSectioned: rejects duplicate section" {
    const err = assembleSectioned(testing.allocator,
        \\.handler { OP_1 }
        \\.handler { OP_0 }
    );
    try testing.expectError(AssembleError.duplicate_section, err);
}

test "assembleSectioned: rejects unknown section" {
    const err = assembleSectioned(testing.allocator,
        \\.someBogusSection { OP_1 }
    );
    try testing.expectError(AssembleError.unknown_section, err);
}

test "assembleSectioned: all three sections together — the canonical cell-type shape" {
    var result = try assembleSectioned(testing.allocator,
        \\# A complete on-chain-anchored cell type:
        \\.lockScript {
        \\  # PushDrop commitment + P2PK lock
        \\  PUSH 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
        \\  OP_DROP
        \\  PUSH 0x02deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
        \\  OP_CHECKSIG
        \\}
        \\
        \\.unlockScript {
        \\  PUSH <SIG>
        \\  PUSH <PUBKEY>
        \\}
        \\
        \\.handler {
        \\  # Validate intent via Plexus
        \\  OP_DUP
        \\  OP_CHECKLINEARTYPE
        \\  OP_DUP
        \\  OP_READPAYLOAD
        \\  PUSH "host_compute_sighash"
        \\  OP_CALLHOST
        \\  OP_CELLCREATE
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);

    try testing.expect(result.lockScript.len > 0);
    try testing.expect(result.unlockScriptTemplate.len == 107);
    try testing.expectEqual(@as(usize, 2), result.unlockScriptSlots.len);
    try testing.expect(result.handler.len > 0);
    // None of the lockScript or unlockScript bytes should be semantos.
    try testing.expect(findFirstSemantosOpcode(result.lockScript) == null);
    try testing.expect(findFirstSemantosOpcode(result.unlockScriptTemplate) == null);
    // The handler SHOULD contain semantos bytes (OP_CHECKLINEARTYPE = 0xc0,
    // OP_READPAYLOAD = 0xcc, OP_CALLHOST = 0xd0, OP_CELLCREATE = 0xca).
    try testing.expect(findFirstSemantosOpcode(result.handler) != null);
}

test "assembleSectioned: empty source produces empty everything" {
    var result = try assembleSectioned(testing.allocator, "");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), result.lockScript.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptSlots.len);
    try testing.expectEqual(@as(usize, 0), result.handler.len);
}

// ── Chronicle (BSV v1.2.0) tests ──────────────────────────────────────

test "Chronicle: restored OP_VER (0x62) in .lockScript permitted" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_VER
        \\  OP_DROP
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0x75 }, result.lockScript);
}

test "Chronicle: restored OP_VERIF + OP_VERNOTIF in .lockScript" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_VERIF
        \\  OP_VERNOTIF
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0x65, 0x66 }, result.lockScript);
}

test "Chronicle: OP_2MUL + OP_2DIV permitted in .lockScript" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_2MUL
        \\  OP_2DIV
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0x8d, 0x8e }, result.lockScript);
}

test "Chronicle: OP_LSHIFTNUM (0xb6) permitted in .lockScript" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_LSHIFTNUM
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{0xb6}, result.lockScript);
}

test "Chronicle: OP_RSHIFTNUM (0xb7) permitted in .lockScript" {
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_RSHIFTNUM
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{0xb7}, result.lockScript);
}

test "Chronicle: Craig OP_XROT_3 (same byte as OP_LSHIFTNUM) refused in .lockScript" {
    // Both mnemonics map to byte 0xB6 in the OPCODES table; the
    // source-level guard distinguishes intent. OP_XROT_3 is refused
    // in consensus sections because its cell-engine semantics
    // (rotate top 3) differ from BSV consensus (OP_LSHIFTNUM).
    const err = assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_XROT_3
        \\}
    );
    try testing.expectError(AssembleError.cell_engine_macro_in_consensus_section, err);
}

test "Chronicle: Craig OP_HASHCAT refused in .lockScript (semantos-only macro)" {
    const err = assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  OP_HASHCAT
        \\}
    );
    try testing.expectError(AssembleError.cell_engine_macro_in_consensus_section, err);
}

test "Chronicle: Craig OP_XSWAP_2 refused in .unlockScript" {
    const err = assembleSectioned(testing.allocator,
        \\.unlockScript {
        \\  OP_XSWAP_2
        \\}
    );
    try testing.expectError(AssembleError.cell_engine_macro_in_consensus_section, err);
}

test "Chronicle: Craig macros STILL permitted in .handler (full vocabulary)" {
    var result = try assembleSectioned(testing.allocator,
        \\.handler {
        \\  OP_XSWAP_2
        \\  OP_XROT_3
        \\  OP_HASHCAT
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0xb0, 0xb6, 0xb8, 0x51 }, result.handler);
}

test "Chronicle: findFirstSemantosOpcode exempts 0xB6 and 0xB7" {
    // Direct byte-level check (sans assembler): the walker should
    // treat 0xB6 (OP_LSHIFTNUM) and 0xB7 (OP_RSHIFTNUM) as
    // consensus-valid, but flag 0xB0..0xB5 and 0xB8+ as semantos.
    try testing.expect(findFirstSemantosOpcode(&[_]u8{ 0x51, 0xb6, 0x51 }) == null);
    try testing.expect(findFirstSemantosOpcode(&[_]u8{ 0x51, 0xb7, 0x51 }) == null);
    try testing.expectEqual(@as(?usize, 1), findFirstSemantosOpcode(&[_]u8{ 0x51, 0xb0, 0x51 })); // XSWAP_2
    try testing.expectEqual(@as(?usize, 1), findFirstSemantosOpcode(&[_]u8{ 0x51, 0xb8, 0x51 })); // HASHCAT
    try testing.expectEqual(@as(?usize, 1), findFirstSemantosOpcode(&[_]u8{ 0x51, 0xc3, 0x51 })); // OP_CHECKCAPABILITY
    try testing.expectEqual(@as(?usize, 1), findFirstSemantosOpcode(&[_]u8{ 0x51, 0xd0, 0x51 })); // OP_CALLHOST
}

test "Chronicle: composite Chronicle lockScript with shift + restored ops" {
    // A consensus-valid lockScript using ONLY Chronicle-era opcodes:
    // arithmetic shift + tx-version check + standard P2PK fall-through.
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\  PUSH 2
        \\  OP_LSHIFTNUM           # double the top of stack
        \\  OP_VER                 # push tx version
        \\  OP_EQUAL               # check equality
        \\  OP_VERIFY              # halt if not equal
        \\  PUSH 0x02deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
        \\  OP_CHECKSIG
        \\}
    );
    defer result.deinit(testing.allocator);
    // Every byte in the output should pass the consensus walker.
    try testing.expect(findFirstSemantosOpcode(result.lockScript) == null);
    // First few bytes: PUSH 2 (0x52) + OP_LSHIFTNUM (0xb6) + OP_VER (0x62) + OP_EQUAL (0x87) + OP_VERIFY (0x69)
    try testing.expectEqual(@as(u8, 0x52), result.lockScript[0]);
    try testing.expectEqual(@as(u8, 0xb6), result.lockScript[1]);
    try testing.expectEqual(@as(u8, 0x62), result.lockScript[2]);
    try testing.expectEqual(@as(u8, 0x87), result.lockScript[3]);
    try testing.expectEqual(@as(u8, 0x69), result.lockScript[4]);
}

// ── PR-7b: section parser dot-in-comment regression coverage ──────────

test "section parser: dotted `#` comments before .handler don't trip parseSections" {
    // Before PR-7b's findNextSectionDot fix, ANY `.` in a `#` comment
    // before the first section directive would cause parseSections to
    // grab the wrong byte range and fail with unknown_section / malformed.
    var result = try assembleSectioned(testing.allocator,
        \\# comment with a dot: bsv.spv.verify.intent
        \\# another dot: ../../foo.bar
        \\.handler {
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), result.handler.len);
    try testing.expectEqual(@as(u8, 0x51), result.handler[0]);
}

test "section parser: dotted `//` comments before .handler don't trip parseSections" {
    var result = try assembleSectioned(testing.allocator,
        \\// LOCKSCRIPT-CLEAVAGE.md §11 worked example
        \\.handler {
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), result.handler.len);
}

test "section parser: dots inside string literals don't trip parseSections" {
    // A handler body that happens to PUSH a string containing a dot
    // must not have its dot mistaken for a section marker. The PUSH
    // literal sits inside the .handler { ... } body, but the test
    // exercises the same skip path because the body is rescanned for
    // sections within parseSections only at the outer level — this
    // guards future refactors from regressing that boundary.
    var result = try assembleSectioned(testing.allocator,
        \\# pre-section comment with a "quoted.dot" inside it
        \\.handler {
        \\  PUSH "host.with.dots"
        \\  OP_DROP
        \\  OP_1
        \\}
    );
    defer result.deinit(testing.allocator);
    // length: 1 (pushdata len = 14) + 14 (string) + 1 (OP_DROP) + 1 (OP_1) = 17
    try testing.expectEqual(@as(usize, 17), result.handler.len);
    try testing.expectEqual(@as(u8, 0x0E), result.handler[0]); // 14-byte push
    try testing.expectEqual(@as(u8, 0x75), result.handler[15]); // OP_DROP
    try testing.expectEqual(@as(u8, 0x51), result.handler[16]); // OP_1
}

// ── PR-7b: bsv-spv-verify-intent.cs reproducibility check ─────────────

test "bsv-spv-verify-intent handler: source assembles to the manifest's declared hex/hash" {
    // This is the PR-7b worked-example pin. The .cs source lives at
    // cartridges/bsv-anchor-bundle/scripts/bsv-spv-verify-intent.cs and
    // the cartridge.json declares (script, scriptHash) for the
    // `bsv.spv.verify.intent` cellType's `handler` field. If anything
    // drifts — the source, the assembler's lookup table, the
    // pushdata encoding, OP_WRITEPAYLOAD's byte assignment — this test
    // catches it before the brain's manifest-hash check rejects the
    // cartridge at load time.
    //
    // We embed the .cs source inline here rather than reading from
    // disk because the assembler's tests are pure-Zig + don't have a
    // file-IO setup. The source body matches the on-disk file modulo
    // line-leading whitespace.
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\}
        \\.unlockScript {
        \\}
        \\.handler {
        \\  PUSH 1
        \\  PUSH 32
        \\  OP_READPAYLOAD
        \\  OP_TOALTSTACK
        \\  PUSH "host_verify_beef_spv"
        \\  OP_CALLHOST
        \\  OP_DUP
        \\  PUSH 256
        \\  OP_MOD
        \\  OP_SWAP
        \\  PUSH 256
        \\  OP_DIV
        \\  OP_TOALTSTACK
        \\  OP_TOALTSTACK
        \\  PUSH 3
        \\  PUSH 0
        \\  PUSH 0x136523b9fea2b732db1b9104389b7cc6a12dd3a7fd3203a4f6a214f7a5fcda0c
        \\  PUSH 0x00000000000000000000000000000000
        \\  OP_CELLCREATE
        \\  PUSH 0x01
        \\  PUSH 0
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 1
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 34
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 2
        \\  OP_WRITEPAYLOAD
        \\}
    );
    defer result.deinit(testing.allocator);

    // Empty lock/unlock sections produce empty bytes.
    try testing.expectEqual(@as(usize, 0), result.lockScript.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptSlots.len);

    // Handler bytecode: pinned to the manifest. PR-7d updated:
    //  - rc → (outcome, error_tag) unpack via OP_DUP + DIV/MOD by 256
    //  - 4× OP_WRITEPAYLOAD instead of 3× — now writes error_tag at
    //    payload offset 34 (the SpvVerifyResult wire layout's tag slot)
    //  - VERSION/OUTCOME/txid writes unchanged from PR-7c
    const expected_hex = "510120cc6b14686f73745f7665726966795f626565665f737076d076020001977c020001966b6b530020136523b9fea2b732db1b9104389b7cc6a12dd3a7fd3203a4f6a214f7a5fcda0c1000000000000000000000000000000000ca5100d16c51d16c0122d16c52d1";
    var expected_bytes: [expected_hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_bytes, expected_hex);
    try testing.expectEqualSlices(u8, &expected_bytes, result.handler);

    // SHA-256 of those bytes — pinned to the manifest's declared
    // scriptHash. Brain refuses to load a handler whose computed hash
    // doesn't match the manifest field, so this lock-in catches manifest
    // drift before the brain does.
    const expected_sha_hex = "21f832c1923558780c85a1608d14a025a9b46f7bca2ab1facf0bf7a6d42232fc";
    var expected_sha: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_sha, expected_sha_hex);
    try testing.expectEqualSlices(u8, &expected_sha, &result.handlerSha256);
}

// ── PR-8b-ii: mnca-anchor-create-intent.cs reproducibility check ──────

test "mnca-anchor-create-intent handler: source assembles to the manifest's declared hex/hash" {
    // PR-8b-ii worked-example pin. The .cs source lives at
    // cartridges/mnca/scripts/mnca-anchor-create-intent.cs and the
    // cartridge.json declares (script, scriptHash) for the
    // `mnca.anchor.create.intent` cellType's `handler` field. Drift
    // between source and manifest fails this test before the brain's
    // hash-check rejects the cartridge at load time.
    //
    // Source body matches the on-disk .cs file modulo leading whitespace.
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\}
        \\.unlockScript {
        \\}
        \\.handler {
        \\  PUSH 1
        \\  PUSH 32
        \\  OP_READPAYLOAD
        \\  OP_TOALTSTACK
        \\  PUSH 33
        \\  PUSH 33
        \\  OP_READPAYLOAD
        \\  OP_TOALTSTACK
        \\  PUSH 1
        \\  PUSH 0
        \\  PUSH 0x09e9fe981010c9b479bfb0e2ba76b9d4e3b0c44298fc1c14e3b0c44298fc1c14
        \\  PUSH 0x00000000000000000000000000000000
        \\  OP_CELLCREATE
        \\  PUSH 0x01
        \\  PUSH 0
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 69
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 1
        \\  OP_WRITEPAYLOAD
        \\}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), result.lockScript.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptSlots.len);

    // Handler bytecode: pinned to the manifest. Reads the intent's
    // initial_snapshot_hash (offset 1, 32B) + initiator_pubkey
    // (offset 33, 33B), then OP_CELLCREATE builds the mnca.anchor
    // typeHash-stamped LINEAR cell, 3× OP_WRITEPAYLOAD fill the
    // payload (VERSION + initiator_pubkey + snapshot_hash).
    const expected_hex = "510120cc6b01210121cc6b51002009e9fe981010c9b479bfb0e2ba76b9d4e3b0c44298fc1c14e3b0c44298fc1c141000000000000000000000000000000000ca5100d16c0145d16c51d1";
    var expected_bytes: [expected_hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_bytes, expected_hex);
    try testing.expectEqualSlices(u8, &expected_bytes, result.handler);

    const expected_sha_hex = "69136a75a8a168e7d9b6b2b05086e8389b5a2f88cfc847a9ef95775a98969b19";
    var expected_sha: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_sha, expected_sha_hex);
    try testing.expectEqualSlices(u8, &expected_sha, &result.handlerSha256);
}

// ── PR-8b-iii: mnca-anchor-transition-intent.cs reproducibility check ──

test "mnca-anchor-transition-intent handler: source assembles to the manifest's declared hex/hash" {
    // PR-8b-iii worked-example pin. The .cs source lives at
    // cartridges/mnca/scripts/mnca-anchor-transition-intent.cs and the
    // cartridge.json declares (script, scriptHash) for the
    // `mnca.anchor.transition.intent` cellType's `handler` field.
    // Verify-only scope: invokes host_mnca_verify_transition + emits
    // a mnca.anchor.transition.result cell. Successor anchor + sign
    // request defer to PR-8b-v.
    var result = try assembleSectioned(testing.allocator,
        \\.lockScript {
        \\}
        \\.unlockScript {
        \\}
        \\.handler {
        \\  PUSH 65
        \\  PUSH 4
        \\  OP_READPAYLOAD
        \\  OP_TOALTSTACK
        \\  PUSH "host_mnca_verify_transition"
        \\  OP_CALLHOST
        \\  OP_DUP
        \\  PUSH 256
        \\  OP_MOD
        \\  OP_SWAP
        \\  PUSH 256
        \\  OP_DIV
        \\  OP_TOALTSTACK
        \\  PUSH 1
        \\  OP_EQUAL
        \\  OP_IF
        \\      PUSH 0
        \\  OP_ELSE
        \\      PUSH 2
        \\  OP_ENDIF
        \\  OP_TOALTSTACK
        \\  PUSH 3
        \\  PUSH 0
        \\  PUSH 0x09e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5f6a214f7a5fcda0c
        \\  PUSH 0x00000000000000000000000000000000
        \\  OP_CELLCREATE
        \\  PUSH 0x01
        \\  PUSH 0
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 1
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 34
        \\  OP_WRITEPAYLOAD
        \\  OP_FROMALTSTACK
        \\  PUSH 35
        \\  OP_WRITEPAYLOAD
        \\}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), result.lockScript.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptTemplate.len);
    try testing.expectEqual(@as(usize, 0), result.unlockScriptSlots.len);

    const expected_hex = "014154cc6b1b686f73745f6d6e63615f7665726966795f7472616e736974696f6ed076020001977c020001966b518763006752686b53002009e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5f6a214f7a5fcda0c1000000000000000000000000000000000ca5100d16c51d16c0122d16c0123d1";
    var expected_bytes: [expected_hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_bytes, expected_hex);
    try testing.expectEqualSlices(u8, &expected_bytes, result.handler);

    const expected_sha_hex = "66c51a67729932d4046d0a15fcba5c02f5b78cc89ec1d0a71797b7473ef67b86";
    var expected_sha: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_sha, expected_sha_hex);
    try testing.expectEqualSlices(u8, &expected_sha, &result.handlerSha256);
}

```
