---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/short_ops.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.996044+00:00
---

# core/cell-engine/tools/sx/src/short_ops.zig

```zig
//! shortOps — verbatim port of bitcoinsx's `src/sx/src/lib/utils.ts::shortOps`.
//!
//! Each entry maps a camelCase mnemonic (the `.sx` source-level form) to the
//! Bitcoin Script opcode byte. The lexer uses this table to:
//!
//!   1. Recognise opcode tokens (longest-match, case-insensitive)
//!   2. Populate `Node.asm_str` with the upper-cased `OP_<NAME>` form
//!   3. Populate `Node.num` with the byte value
//!
//! Layout matches his array order so any future upstream addition diffs
//! cleanly against this file.

const std = @import("std");

pub const ShortOp = struct {
    value: []const u8, // his camelCase form, e.g. "checkSig"
    int: u8, // the opcode byte
};

/// Table is `pub const` rather than computed at runtime — the lexer's
/// hot path looks ops up by case-insensitive prefix match.
pub const TABLE = [_]ShortOp{
    .{ .value = "false", .int = 0 },
    .{ .value = "1negate", .int = 79 },
    .{ .value = "true", .int = 81 },
    .{ .value = "nop", .int = 97 },
    .{ .value = "if", .int = 99 },
    .{ .value = "notIf", .int = 100 },
    .{ .value = "else", .int = 103 },
    .{ .value = "endIf", .int = 104 },
    .{ .value = "verify", .int = 105 },
    .{ .value = "return", .int = 106 },
    .{ .value = "toAltStack", .int = 107 },
    .{ .value = "fromAltStack", .int = 108 },
    .{ .value = "2drop", .int = 109 },
    .{ .value = "2dup", .int = 110 },
    .{ .value = "3dup", .int = 111 },
    .{ .value = "2over", .int = 112 },
    .{ .value = "2rot", .int = 113 },
    .{ .value = "2swap", .int = 114 },
    .{ .value = "ifDup", .int = 115 },
    .{ .value = "depth", .int = 116 },
    .{ .value = "drop", .int = 117 },
    .{ .value = "dup", .int = 118 },
    .{ .value = "nip", .int = 119 },
    .{ .value = "over", .int = 120 },
    .{ .value = "pick", .int = 121 },
    .{ .value = "roll", .int = 122 },
    .{ .value = "rot", .int = 123 },
    .{ .value = "swap", .int = 124 },
    .{ .value = "tuck", .int = 125 },
    .{ .value = "cat", .int = 126 },
    .{ .value = "split", .int = 127 },
    .{ .value = "num2bin", .int = 128 },
    .{ .value = "bin2num", .int = 129 },
    .{ .value = "size", .int = 130 },
    .{ .value = "invert", .int = 131 },
    .{ .value = "and", .int = 132 },
    .{ .value = "or", .int = 133 },
    .{ .value = "xor", .int = 134 },
    .{ .value = "equal", .int = 135 },
    .{ .value = "equalVerify", .int = 136 },
    .{ .value = "1add", .int = 139 },
    .{ .value = "1sub", .int = 140 },
    .{ .value = "2mul", .int = 141 },
    .{ .value = "2div", .int = 142 },
    .{ .value = "negate", .int = 143 },
    .{ .value = "abs", .int = 144 },
    .{ .value = "not", .int = 145 },
    .{ .value = "0notEqual", .int = 146 },
    .{ .value = "add", .int = 147 },
    .{ .value = "sub", .int = 148 },
    .{ .value = "mul", .int = 149 },
    .{ .value = "div", .int = 150 },
    .{ .value = "mod", .int = 151 },
    .{ .value = "lShift", .int = 152 },
    .{ .value = "rShift", .int = 153 },
    .{ .value = "boolAnd", .int = 154 },
    .{ .value = "boolOr", .int = 155 },
    .{ .value = "numEqual", .int = 156 },
    .{ .value = "numEqualVerify", .int = 157 },
    .{ .value = "numNotEqual", .int = 158 },
    .{ .value = "lessThan", .int = 159 },
    .{ .value = "greaterThan", .int = 160 },
    .{ .value = "lessThanOrEqual", .int = 161 },
    .{ .value = "greaterThanOrEqual", .int = 162 },
    .{ .value = "min", .int = 163 },
    .{ .value = "max", .int = 164 },
    .{ .value = "within", .int = 165 },
    .{ .value = "ripemd160", .int = 166 },
    .{ .value = "sha1", .int = 167 },
    .{ .value = "sha256", .int = 168 },
    .{ .value = "hash160", .int = 169 },
    .{ .value = "hash256", .int = 170 },
    .{ .value = "codeSeparator", .int = 171 },
    .{ .value = "checkSig", .int = 172 },
    .{ .value = "checkSigVerify", .int = 173 },
    .{ .value = "checkMultiSig", .int = 174 },
    .{ .value = "checkMultiSigVerify", .int = 175 },
};

pub const PrefixMatch = struct { op: ShortOp, len: usize };

/// Case-insensitive longest-prefix lookup over `TABLE`, starting at the
/// beginning of `input`. Returns the longest matching ShortOp + how many
/// bytes it consumed, or null if no prefix matches.
///
/// Mirrors the JS regex `^(<op1>|<op2>|...)\b` with `i` flag from his
/// `nodeRegexes.opcode`. The `\b` requirement is enforced by the caller
/// (lexer checks the byte after the match is whitespace / EOF / non-word).
pub fn lookupPrefix(input: []const u8) ?PrefixMatch {
    var best: ?PrefixMatch = null;
    for (TABLE) |op| {
        if (input.len < op.value.len) continue;
        if (std.ascii.eqlIgnoreCase(input[0..op.value.len], op.value)) {
            if (best == null or op.value.len > best.?.len) {
                best = .{ .op = op, .len = op.value.len };
            }
        }
    }
    return best;
}

test "lookupPrefix matches nop case-insensitively" {
    const m = lookupPrefix("nop") orelse return error.NoMatch;
    try std.testing.expectEqualStrings("nop", m.op.value);
    try std.testing.expectEqual(@as(u8, 97), m.op.int);
    try std.testing.expectEqual(@as(usize, 3), m.len);
}

test "lookupPrefix matches checkSig (longer over shorter)" {
    const m = lookupPrefix("checkSig something else") orelse return error.NoMatch;
    try std.testing.expectEqualStrings("checkSig", m.op.value);
    try std.testing.expectEqual(@as(u8, 172), m.op.int);
}

test "lookupPrefix prefers checkSigVerify over checkSig when both match" {
    const m = lookupPrefix("checkSigVerify rest") orelse return error.NoMatch;
    try std.testing.expectEqualStrings("checkSigVerify", m.op.value);
}

test "lookupPrefix returns null for unknown mnemonic" {
    try std.testing.expect(lookupPrefix("zzzz") == null);
}

```
