---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/opcodes/hostcall.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.001098+00:00
---

# core/cell-engine/src/opcodes/hostcall.zig

```zig
// Host function dispatch opcode (0xD0) — Phase 25.5
// OP_CALLHOST: pop function name (string) from main stack,
// dispatch to registered host function via host extern,
// push result (0 or 1) back onto main stack.
//
// Host functions read inputs from a pre-set evaluation context,
// NOT from the stack. The stack holds only the function name.
// Context is immutable during script evaluation.

const std = @import("std");
const pda_mod = @import("pda");
const host = @import("host");

pub const HostCallError = pda_mod.PDAError || error{
    unknown_host_function,
    host_function_failed,
    invalid_function_name,
};

/// OP_CALLHOST (0xD0): Pop function name (string) from main stack,
/// dispatch to registered host function, push result back.
pub fn executeCallHost(p: *pda_mod.PDA) HostCallError!void {
    // Pop function name as string from main stack
    const item = try p.spop();
    const name_len = item.len;

    if (name_len == 0) return error.invalid_function_name;

    // Dispatch to host environment via extern
    const result = host.callByName(item.data[0..name_len]);

    // 0xFFFFFFFF is the sentinel for "unknown host function"
    if (result == 0xFFFFFFFF) return error.unknown_host_function;

    // Push result as script number onto main stack
    var out: pda_mod.Cell = undefined;
    const out_len = pda_mod.i64ToCell(@intCast(result), &out);
    if (out_len == 0) {
        // Result is 0 — push empty (falsy)
        try p.spush(&[_]u8{});
    } else {
        try p.spush(out[0..out_len]);
    }
}

```
