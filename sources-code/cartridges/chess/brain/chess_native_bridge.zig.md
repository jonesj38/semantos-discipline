---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_native_bridge.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.424994+00:00
---

# cartridges/chess/brain/chess_native_bridge.zig

```zig
// chess_native_bridge — V1 STUB. The brain's native binary does not
// link the cell-engine kernel exports directly; the kernel is reached
// only through the embedded WASM runtime. The on-chain replay guard
// (`semantos_linear_consume` at src/ffi/exports.zig:1711) therefore
// runs inside the **detached submitter binary** when it processes the
// payout intent queue (the submitter owns the cell-engine WASM
// instance and is the only side that broadcasts to ARC).
//
// The brain-side consume_fn is a no-op for V1:
//   • In-brain replay safety is already provided by `escrow.resolved`
//     (a second `chess.resolve` call returns `already_resolved`).
//   • The cross-process kernel replay-guard fires when the submitter
//     processes the intent — pay_fn already writes `source_outpoints`
//     into the intent JSON, so the submitter knows which anchors to
//     consume against the kernel.
//
// When the cell-engine WASM is embedded in the brain at a later phase,
// this stub gets replaced with a function that calls into that runtime.
// `chess_wallet_port.Port` is unchanged — only the function pointer
// the brain wires through `cartridge_boot.BootDeps.chess_consume_fn`
// changes.

const std = @import("std");
const port = @import("chess_wallet_port");

fn linearConsume(_: []const u8, _: []const u8) port.ConsumeError!void {
    // V1 stub. See header comment.
    return {};
}

pub fn nativeConsumeFn() port.KernelConsumeFn {
    return linearConsume;
}

```
