---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/opcodes/macro.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.000489+00:00
---

# core/cell-engine/src/opcodes/macro.zig

```zig
// Craig macros (0xB0-0xBF) — Phase 3
// Authoritative mapping from craig-macros.fs INIT-MACROS (lines 130-138):
//   0xB0 = XSWAP-2   (swap top with 2nd — equivalent to OP_SWAP)
//   0xB1 = XSWAP-3   (swap top with 3rd)
//   0xB2 = XSWAP-4   (swap top with 4th)
//   0xB3 = XDROP-2   (drop top 2 elements)
//   0xB4 = XDROP-3   (drop top 3 elements)
//   0xB5 = XDROP-4   (drop top 4 elements)
//   0xB6 = XROT-3    (rotate top 3, bringing 3rd to top — equivalent to OP_ROT)
//   0xB7 = XROT-4    (rotate top 4, bringing 4th to top)
//   0xB8 = HASHCAT   (pop 2, SHA256(a||b), push 32-byte result)
//   0xB9-0xBF = reserved

const pda_mod = @import("pda");
const host = @import("host");

pub const MacroError = error{
    stack_overflow,
    stack_underflow,
    unknown_macro,
};

pub fn executeMacro(p: *pda_mod.PDA, opcode: u8) MacroError!void {
    switch (opcode) {
        0xB0 => try xswap(p, 2), // XSWAP-2
        0xB1 => try xswap(p, 3), // XSWAP-3
        0xB2 => try xswap(p, 4), // XSWAP-4
        0xB3 => try xdrop(p, 2), // XDROP-2
        0xB4 => try xdrop(p, 3), // XDROP-3
        0xB5 => try xdrop(p, 4), // XDROP-4
        0xB6 => try xrot(p, 3), // XROT-3
        0xB7 => try xrot(p, 4), // XROT-4
        0xB8 => try hashcat(p), // HASHCAT
        else => return error.unknown_macro,
    }
}

/// XSWAP-N: swap top element with the Nth element (1-indexed from top).
/// XSWAP-2 swaps top with 2nd (= OP_SWAP).
/// XSWAP-3 swaps top with 3rd.
/// XSWAP-4 swaps top with 4th.
fn xswap(p: *pda_mod.PDA, n: u32) MacroError!void {
    if (p.sdepth() < n) return error.stack_underflow;
    const top_idx = p.main_sp - 1;
    const target_idx = p.main_sp - n;

    // Swap cell data
    var tmp: pda_mod.Cell = undefined;
    @memcpy(&tmp, &p.main_stack[top_idx]);
    @memcpy(&p.main_stack[top_idx], &p.main_stack[target_idx]);
    @memcpy(&p.main_stack[target_idx], &tmp);

    // Swap lengths
    const tmp_len = p.main_lengths[top_idx];
    p.main_lengths[top_idx] = p.main_lengths[target_idx];
    p.main_lengths[target_idx] = tmp_len;
}

/// XDROP-N: drop the top N elements.
/// Zeroes lengths of dropped slots for deterministic traces and stale data hygiene.
fn xdrop(p: *pda_mod.PDA, n: u32) MacroError!void {
    if (p.sdepth() < n) return error.stack_underflow;
    // Zero lengths of dropped slots before moving the pointer
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        p.main_lengths[p.main_sp - 1 - i] = 0;
    }
    p.main_sp -= n;
}

/// XROT-N: rotate top N elements, bringing the Nth element to top.
/// The other N-1 elements shift down by one position.
/// XROT-3: a b c → b c a (same as OP_ROT)
/// XROT-4: a b c d → b c d a
fn xrot(p: *pda_mod.PDA, n: u32) MacroError!void {
    if (p.sdepth() < n) return error.stack_underflow;
    const bottom_idx = p.main_sp - n;

    // Save the bottom element of the group
    var tmp: pda_mod.Cell = undefined;
    @memcpy(&tmp, &p.main_stack[bottom_idx]);
    const tmp_len = p.main_lengths[bottom_idx];

    // Shift everything down
    var i = bottom_idx;
    while (i < p.main_sp - 1) : (i += 1) {
        @memcpy(&p.main_stack[i], &p.main_stack[i + 1]);
        p.main_lengths[i] = p.main_lengths[i + 1];
    }

    // Place saved element at top
    @memcpy(&p.main_stack[p.main_sp - 1], &tmp);
    p.main_lengths[p.main_sp - 1] = tmp_len;
}

/// HASHCAT: pop two elements, concatenate, SHA256 hash, push 32-byte result.
/// Stack: [a, b] → [SHA256(a || b)]
/// Failure-atomic: stack unchanged on underflow.
fn hashcat(p: *pda_mod.PDA) MacroError!void {
    // Precheck: require exactly 2 elements before any mutation
    if (p.sdepth() < 2) return error.stack_underflow;

    // Safe to pop — depth validated above
    const b = p.spop() catch unreachable;
    var b_buf: pda_mod.Cell = undefined;
    const b_len = b.len;
    if (b_len > 0) @memcpy(b_buf[0..b_len], b.data[0..b_len]);

    const a = p.spop() catch unreachable;
    var a_buf: pda_mod.Cell = undefined;
    const a_len = a.len;
    if (a_len > 0) @memcpy(a_buf[0..a_len], a.data[0..a_len]);

    // Bounds check: concat must fit in buffer (2 * CELL_SIZE)
    const concat_buf_size = 2 * pda_mod.CELL_SIZE;
    if (a_len + b_len > concat_buf_size) return error.stack_overflow;

    // Concatenate into a temp buffer
    var concat_buf: [concat_buf_size]u8 = undefined;
    if (a_len > 0) @memcpy(concat_buf[0..a_len], a_buf[0..a_len]);
    if (b_len > 0) @memcpy(concat_buf[a_len .. a_len + b_len], b_buf[0..b_len]);

    // SHA256
    var hash: [32]u8 = undefined;
    host.sha256(concat_buf[0 .. a_len + b_len], &hash);

    p.spush(&hash) catch return error.stack_overflow;
}

```
