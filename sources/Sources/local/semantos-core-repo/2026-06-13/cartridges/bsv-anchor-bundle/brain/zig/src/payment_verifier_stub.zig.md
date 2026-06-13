---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/payment_verifier_stub.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.448810+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/payment_verifier_stub.zig

```zig
// Phase WSITE4.5 — payment verifier stub.
//
// Built when `-Denable-wasmtime=false`.  Mirrors the public surface of
// `payment_verifier.zig` so `site_server.zig` and `cli.zig` can import
// `payment_verifier` unconditionally.  Every entry returns
// `error.bsvz_unavailable` so the call site can degrade gracefully —
// "payment claim recorded; SPV verification needs the bsvz-linked
// binary; rebuild with -Denable-wasmtime=true".
//
// Tests run against this stub when wasmtime is off so the disabled
// build path stays compilable + exercised.

const std = @import("std");

pub const VerifyError = error{
    parse_failed,
    txid_not_found,
    spv_invalid,
    no_matching_output,
    out_of_memory,
    bsvz_unavailable,
};

pub const VerifyResult = struct {
    spv_ok: bool = false,
    output_ok: bool = false,
    verified: bool = false,
    matched_satoshis: u64 = 0,
    /// WSITE4.6 — kept on the stub surface so call sites compile in
    /// both modes.  Stub never fills these in (bsvz_unavailable
    /// short-circuits before the script walk).
    matched_vout: u32 = 0,
    matched_locking_script: []u8 = &.{},
    matched_output_satoshis: u64 = 0,
};

pub fn verify(
    allocator: std.mem.Allocator,
    beef_bytes: []const u8,
    txid_hex: []const u8,
    recipient_sec1: [33]u8,
    expected_satoshis: u64,
    chain_tracker: anytype,
    out_locking_script_allocator: ?std.mem.Allocator,
) VerifyError!VerifyResult {
    _ = allocator;
    _ = beef_bytes;
    _ = txid_hex;
    _ = recipient_sec1;
    _ = expected_satoshis;
    _ = chain_tracker;
    _ = out_locking_script_allocator;
    return error.bsvz_unavailable;
}

```
