---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/opcodes/routing.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.000203+00:00
---

# core/cell-engine/src/opcodes/routing.zig

```zig
// Routing opcodes (0xE0..0xEF) — Phase: OP_BRANCHONOUTPUT (2026-05-26)
//
// Exposes the current output index of the execution context to a script,
// enabling a single locking script to branch on which output is being
// claimed or validated.  Used by economically-weighted semantic segment
// routing to replace N×CHECKSIG with O(N) memcmp per spend.
//
// Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md
//
// Invariants enforced here:
//   I1 (determinism)         — pure function of (tx_context, stack state)
//   I2 (stack delta = +1)    — exactly one push, no pop
//   I3 (non-malleability)    — tx_context.current_output_index is read-only;
//                              no opcode in this module writes it.
//
// I4 (linear single-claim) is a meta-property over scripts; this module
// ensures the only way a script can observe current_output_index is via
// OP_BRANCHONOUTPUT — that closure is what makes I4 provable.

const std = @import("std");
const constants = @import("constants");
const pda_mod = @import("pda");
const sighash = @import("sighash");

pub const RoutingError = pda_mod.PDAError || error{
    no_tx_context,
    invalid_opcode,
};

/// Dispatch a routing opcode (0xE0..0xEF).
///
/// Caller (executor.zig) has already verified:
///   - opcode is in [OPCODE_ROUTING_MIN, OPCODE_ROUTING_MAX]
///   - ctx.executing is true
pub fn executeRouting(
    p: *pda_mod.PDA,
    opcode: u8,
    tx_ctx: ?*const sighash.TxContext,
) RoutingError!void {
    switch (opcode) {
        constants.OP_BRANCHONOUTPUT => {
            const tx = tx_ctx orelse return error.no_tx_context;
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &buf, tx.current_output_index, .little);
            try p.spush(&buf);
        },
        else => return error.invalid_opcode,
    }
}

```
