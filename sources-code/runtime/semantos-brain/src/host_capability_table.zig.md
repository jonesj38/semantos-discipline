---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/host_capability_table.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.245644+00:00
---

# runtime/semantos-brain/src/host_capability_table.zig

```zig
// Host function ↔ capability table.
//
// The canonical seam between manifest capability *strings*
// (`module.capabilities: ["wallet.sign", "bsv.beef.verify"]`) and
// brain host-import function *names* (`host_sign`,
// `host_verify_beef_spv`). Every host function the substrate
// exposes to a script handler must appear here with its required
// capability string, OR with `""` if it's part of the always-
// present surface.
//
// A future capability gate (script-handler loader) will consume this
// table:
//
//   1. Parse the handler's import declarations.
//   2. For each `(env, field)`:
//        a. Look up `field` in this table.
//        b. If not in the table → `error.unknown_host_import` — the
//           substrate doesn't expose that function at all.
//        c. If table entry's required capability is `""` → allowed.
//        d. Otherwise, the manifest's `module.capabilities[]` MUST
//           include that capability string, else
//           `error.capability_not_declared`.
//   3. Imports with `module != "env"` → `error.unknown_import_module`
//      (we only expose host functions through the conventional `env`
//      namespace).
//
// Coverage today: the WSITE2.5 host imports actually wired in
// `wasmtime_runner_real.zig`. New entries land alongside the host
// functions they describe.

const std = @import("std");

/// One row of the table. `field_name` is the WASM-side import name;
/// `required_capability` is the manifest capability string the
/// module must declare in `module.capabilities[]` to bind this
/// import. `""` (empty) means the function is part of the always-
/// present substrate surface — no capability needed.
pub const Entry = struct {
    field_name: []const u8,
    required_capability: []const u8,
    /// Human-readable description, surfaced in audit / boot logs
    /// when the gate denies the binding.
    description: []const u8,
};

pub const ENTRIES = [_]Entry{
    // ── always-present substrate surface ─────────────────────────
    .{
        .field_name = "host_log",
        .required_capability = "",
        .description = "structured log line into the brain audit stream",
    },
    .{
        .field_name = "host_load_cell",
        .required_capability = "",
        .description = "load a substrate cell by typeHash + payload-hash",
    },
    .{
        .field_name = "host_persist_cell",
        .required_capability = "",
        .description = "persist a 1024-byte cell via the substrate store",
    },
    .{
        .field_name = "host_sha256",
        .required_capability = "",
        .description = "SHA-256 hash primitive",
    },
    .{
        .field_name = "host_sha1",
        .required_capability = "",
        .description = "SHA-1 hash primitive",
    },
    .{
        .field_name = "host_ripemd160",
        .required_capability = "",
        .description = "RIPEMD-160 hash primitive",
    },
    .{
        .field_name = "host_hash160",
        .required_capability = "",
        .description = "RIPEMD-160(SHA-256(x)) — BSV address hash",
    },
    .{
        .field_name = "host_hash256",
        .required_capability = "",
        .description = "SHA-256(SHA-256(x)) — BSV double-hash",
    },

    // ── wallet-engine surface (capability-gated) ─────────────────
    .{
        .field_name = "host_sign",
        .required_capability = "wallet.sign",
        .description = "sign a sighash with the wallet's key (BIP-143 ECDSA)",
    },
    .{
        .field_name = "host_derive_leaf",
        .required_capability = "wallet.derive",
        .description = "BRC-42 leaf-key derivation from a counterparty + invoice spec",
    },
    .{
        .field_name = "host_get_blocktime",
        .required_capability = "wallet.blocktime",
        .description = "read the wallet's locked-in blocktime view",
    },
    .{
        .field_name = "host_get_sequence",
        .required_capability = "wallet.sequence",
        .description = "read the wallet's current sequence index",
    },
    .{
        .field_name = "host_state_next_index",
        .required_capability = "wallet.sequence",
        .description = "advance the wallet's state-machine index for the next emit",
    },

    // ── BSV-specific surface (capability-gated) ──────────────────
    .{
        .field_name = "host_checksig",
        .required_capability = "bsv.checksig",
        .description = "OP_CHECKSIG primitive (sighash + sig + pubkey verify)",
    },
    .{
        .field_name = "host_verify_beef_spv",
        .required_capability = "bsv.beef.verify",
        .description = "verify a BEEF carries an SPV proof terminating at a trusted root",
    },
    // PR-3 of LOCKSCRIPT-CLEAVAGE.md §11 — dual-algorithm sighash
    // hostcall. Dispatches BIP-143 (FORKID) vs OTDA (CHRONICLE 0x20)
    // on the sighashFlags byte. Cell-engine handler is registered
    // in core/cell-engine/src/host_compute_sighash.zig; the brain
    // populates a Context (tx + subscript + sighash_type) via
    // host.setExecutionContext before invoking the script.
    .{
        .field_name = "host_compute_sighash",
        .required_capability = "cap.tx.sign",
        .description = "compute the BIP-143 or OTDA sighash digest for a transaction input (dispatch on SIGHASH_CHRONICLE 0x20)",
    },
    // PR-4 of LOCKSCRIPT-CLEAVAGE.md §11 — single hostcall covering
    // both lockScript and unlockScript template substitution. Same
    // mechanism for both regions (copy template + apply slot bindings);
    // same cap.tx.build gate.
    .{
        .field_name = "host_resolve_script_template",
        .required_capability = "cap.tx.build",
        .description = "substitute slot bindings into a lockScript or unlockScript template; emits resolved standard-only bytes",
    },
    // PR-5 of LOCKSCRIPT-CLEAVAGE.md §11 — partial-tx contribution
    // signature verifier. Thin wrapper around host.checksig; capability-
    // gated so the broker can audit partial-sig verification
    // independently of other CHECKSIG uses.
    .{
        .field_name = "host_verify_partial_sig",
        .required_capability = "cap.tx.sign",
        .description = "verify a partial-tx contribution's ECDSA signature against (pubkey, sighash digest) — returns 0=verified, 1=rejected",
    },
    // PR-5 — BIP-143 preimage hashing helpers. All three names share
    // a SHA256d implementation; intent-naming at the call site makes
    // handler scripts self-documenting. No capability gate (pure
    // CPU functions with no security-relevant outputs).
    .{
        .field_name = "host_compute_prevouts_hash",
        .required_capability = "",
        .description = "SHA256d of concatenated prev-outpoints — first BIP-143 preimage component",
    },
    .{
        .field_name = "host_compute_sequence_hash",
        .required_capability = "",
        .description = "SHA256d of concatenated nSequence values — second BIP-143 preimage component",
    },
    .{
        .field_name = "host_compute_outputs_hash",
        .required_capability = "",
        .description = "SHA256d of concatenated serialized outputs — third BIP-143 preimage component",
    },
    // PR-5b of LOCKSCRIPT-CLEAVAGE.md §11 — final tx serialization for
    // the cap.tx.build hostcall surface. Takes (version, inputs[],
    // outputs[], nLockTime), emits wire-format bytes ready for broadcast.
    // Shares cap.tx.build with host_resolve_script_template — composing
    // and finalizing tx parts is one capability surface.
    .{
        .field_name = "host_assemble_tx",
        .required_capability = "cap.tx.build",
        .description = "serialize a candidate BSV transaction from (version, inputs[], outputs[], nLockTime); emits wire-format bytes ready for host_broadcast_arc",
    },
    // PR-8b-i of LOCKSCRIPT-CLEAVAGE.md §7.2 — MNCA-transition
    // determinism oracle. Wraps mnca_tile.stepTilePayload: re-derives
    // the successor tile from a predecessor + compares the hash
    // against the script's claimed value. The MNCA anchor transition
    // handler invokes this to confirm the next snapshot was reached
    // deterministically before emitting a sign request.
    .{
        .field_name = "host_mnca_verify_transition",
        .required_capability = "cap.mnca.verify",
        .description = "re-derive an MNCA tile transition via stepTilePayload + verify hash matches the script's claim — returns packed (verdict, error_tag) rc",
    },
};

pub const LookupResult = struct {
    entry: Entry,
};

/// Look up a host function by its WASM-side import name. Returns
/// null when the name isn't in the table — caller surfaces as
/// `error.unknown_host_import`.
pub fn lookup(field_name: []const u8) ?Entry {
    for (ENTRIES) |e| {
        if (std.mem.eql(u8, e.field_name, field_name)) return e;
    }
    return null;
}

/// Returns true when the table entry for `field_name` is part of
/// the always-present surface (no capability gate). Convenience
/// wrapper; callers can also inspect `lookup(name).?.required_capability`
/// directly.
pub fn isAlwaysPresent(field_name: []const u8) bool {
    if (lookup(field_name)) |e| return e.required_capability.len == 0;
    return false;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "lookup — known always-present entry" {
    const e = lookup("host_log").?;
    try testing.expectEqualStrings("", e.required_capability);
    try testing.expect(isAlwaysPresent("host_log"));
}

test "lookup — known capability-gated entry" {
    const e = lookup("host_sign").?;
    try testing.expectEqualStrings("wallet.sign", e.required_capability);
    try testing.expect(!isAlwaysPresent("host_sign"));
}

test "lookup — known BSV-gated entry" {
    const e = lookup("host_verify_beef_spv").?;
    try testing.expectEqualStrings("bsv.beef.verify", e.required_capability);
}

test "lookup — host_assemble_tx is cap.tx.build" {
    const e = lookup("host_assemble_tx").?;
    try testing.expectEqualStrings("cap.tx.build", e.required_capability);
    try testing.expect(!isAlwaysPresent("host_assemble_tx"));
}

test "lookup — host_mnca_verify_transition is cap.mnca.verify (PR-8b-i)" {
    const e = lookup("host_mnca_verify_transition").?;
    try testing.expectEqualStrings("cap.mnca.verify", e.required_capability);
    try testing.expect(!isAlwaysPresent("host_mnca_verify_transition"));
}

test "lookup — unknown name returns null" {
    try testing.expectEqual(@as(?Entry, null), lookup("host_bogus_function"));
    try testing.expect(!isAlwaysPresent("host_bogus_function"));
}

test "table has no duplicate field names" {
    var i: usize = 0;
    while (i < ENTRIES.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < ENTRIES.len) : (j += 1) {
            try testing.expect(!std.mem.eql(u8, ENTRIES[i].field_name, ENTRIES[j].field_name));
        }
    }
}

test "every entry has a non-empty description" {
    for (ENTRIES) |e| try testing.expect(e.description.len > 0);
}

```
