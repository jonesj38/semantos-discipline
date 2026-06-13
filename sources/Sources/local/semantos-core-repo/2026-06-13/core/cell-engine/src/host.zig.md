---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.983504+00:00
---

# core/cell-engine/src/host.zig

```zig
// Host function imports — provided by the Bun/Node runtime (embedded profile)
// or handled natively via BSVZ (full profile).
//
// The `embedded` build option controls dispatch:
//   embedded=false (default): BSVZ native crypto for all targets
//   embedded=true: Phase 3/4 behavior — host externs for WASM, std lib / stubs for native

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const is_wasm = builtin.target.cpu.arch == .wasm32;
const embedded = build_options.embedded;

// BSVZ is only imported in the full profile
const bsvz = if (!embedded) @import("bsvz") else struct {};

const derivation_state_mod = @import("derivation_state");
const slot_store_mod = @import("slot_store");

// ── WASM extern declarations (only resolved at link time for embedded WASM builds) ──
// In full profile, crypto externs are dead code (BSVZ handles natively).
// In embedded profile, they're the primary crypto path for WASM builds.

pub extern "host" fn host_sha256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
pub extern "host" fn host_hash160(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
pub extern "host" fn host_hash256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
pub extern "host" fn host_ripemd160(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
pub extern "host" fn host_sha1(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
pub extern "host" fn host_checksig(pk_ptr: [*]const u8, pk_len: u32, msg_ptr: [*]const u8, msg_len: u32, sig_ptr: [*]const u8, sig_len: u32) u32;
pub extern "host" fn host_checkmultisig(pks_ptr: [*]const u8, pks_count: u32, sigs_ptr: [*]const u8, sigs_count: u32, msg_ptr: [*]const u8, msg_len: u32, threshold: u32) u32;
// Wallet tier-key signing (Phase W1). ECDSA secp256k1 over a 32-byte digest, low-S normalized.
// Output is BSV-format DER signature WITHOUT the trailing sighash byte (the cell engine
// appends that itself). Returns 1 on success and writes der length to out_len_ptr;
// returns 0 on failure (out buffer untouched).
pub extern "host" fn host_sign(sk_ptr: [*]const u8, sk_len: u32, msg_ptr: [*]const u8, msg_len: u32, out_ptr: [*]u8, out_buf_len: u32, out_len_ptr: *u32) u32;
// Runtime context — always host-provided in both profiles
pub extern "host" fn host_get_blocktime() u32;
pub extern "host" fn host_get_sequence() u32;
pub extern "host" fn host_log(msg_ptr: [*]const u8, msg_len: u32) void;

// Phase 25.5: Host function dispatch — call a named host function registered by the runtime.
// Returns result value (0/1 for predicates, numeric for values), or 0xFFFFFFFF for unknown function.
pub extern "host" fn host_call_by_name(name_ptr: [*]const u8, name_len: u32) u32;

// Phase 6: Octave memory — fetch a cell from a higher octave via host runtime.
// Returns 1 on success (1024 bytes written to out_ptr), 0 on failure.
// The host slices octave 1+ cells at the given offset and returns the relevant 1KB chunk.
// The WASM module never handles cells larger than 1KB.
pub extern "host" fn host_fetch_cell(octave: u8, slot: u32, offset: u32, out_ptr: [*]u8) u32;

// M1.10: Cursor host-imports — stream cells from the cell store without loading
// the entire store into linear memory. Peak heap is bounded at one cell (1024 bytes).
//
// hostDbOpenCursor: open a forward-only cursor over the cell store, optionally
//   filtered by `filter_ptr`/`filter_len` (reserved; pass 0 for unfiltered).
//   Returns cursor_id (1..N) on success, 0 on error (no free slots / store error).
pub extern "host" fn hostDbOpenCursor(filter_ptr: u32, filter_len: u32) u32;

// hostDbCursorPull: pull the next cell from the cursor into WASM linear memory
//   at `out_ptr` (must have at least 1024 bytes of capacity). Returns 1 if a
//   cell was written, 0 when the cursor is exhausted or on error.
pub extern "host" fn hostDbCursorPull(cursor_id: u32, out_ptr: u32) u32;

// hostDbCursorClose: close the cursor and release host-side resources. Safe to
//   call on an already-closed or invalid cursor_id (no-op).
pub extern "host" fn hostDbCursorClose(cursor_id: u32) void;

// Phase W3.5: BRC-42 leaf derivation. Pure function — no state. Produces a
// 32-byte child private key from a base + (protocol_hash, counterparty, index).
pub extern "host" fn host_derive_leaf(
    base_sk_ptr: [*]const u8,
    base_sk_len: u32,
    protocol_hash_ptr: [*]const u8,
    counterparty_ptr: [*]const u8,
    index: u64,
    out_leaf_ptr: [*]u8,
) u32;

// Phase W3.5: DerivationState atomic next-index allocation.
// Looks up the (protocol_hash, counterparty) context, increments by 1
// (or starts at 0), persists, and writes the allocated index to out_index_ptr.
// Returns 1 on success, 0 on persistence failure.
pub extern "host" fn host_state_next_index(
    protocol_hash_ptr: [*]const u8,
    counterparty_ptr: [*]const u8,
    out_index_ptr: *u64,
) u32;

// Phase W4: Tier unlock — derive a KEK from the user's factor (PIN /
// passphrase / WebAuthn assertion blob), AES-GCM-decrypt the at-rest blob
// at `slot_id`, and stage it into the engine memory at `out_cell_ptr`.
// Sets a session flag enabling subsequent `host_load_cell` calls for that
// tier. Returns 1 on success, 0 on factor-mismatch / not-found / decrypt
// failure. Tier 0 must NOT be unlocked through this path — its budget cell
// is reachable directly via `host_load_cell` under the session KEK.
pub extern "host" fn host_unlock_tier(
    tier: u32,
    factor_handle_ptr: [*]const u8,
    factor_len: u32,
    slot_id: u32,
    out_cell_ptr: [*]u8,
) u32;

// Phase W4: Persist a cell to the at-rest slot store. The host derives the
// blob's AES-GCM KEK from the cell's domain_flag (Tier 0 → session KEK,
// Tier N → KEK installed by `host_unlock_tier`). Returns 1 on success,
// 0 if no KEK is available for the cell's tier or storage is unwired.
pub extern "host" fn host_persist_cell(
    slot_id: u32,
    cell_ptr: [*]const u8,
    len: u32,
) u32;

// Phase W4: Load a previously-persisted cell. Tier-0 succeeds with only the
// session KEK; Tier-1+ requires `host_unlock_tier` to have run earlier in
// the same request scope. Writes the plaintext cell (1024 bytes) to
// `out_ptr`. Returns 1 on success, 0 on missing-KEK / not-found / auth-fail.
pub extern "host" fn host_load_cell(
    slot_id: u32,
    out_ptr: [*]u8,
) u32;

// ── Unified wrappers with compile-time dispatch ──

/// SHA256 hash
pub fn sha256(data: []const u8, out: *[32]u8) void {
    if (embedded) {
        // Embedded profile: Phase 3/4 behavior
        if (is_wasm) {
            host_sha256(data.ptr, @intCast(data.len), out);
        } else {
            const Sha256 = @import("std").crypto.hash.sha2.Sha256;
            Sha256.hash(data, out, .{});
        }
    } else {
        // Full profile: BSVZ native
        const hash = bsvz.crypto.hash.sha256(data);
        @memcpy(out, &hash.bytes);
    }
}

/// HASH160 (SHA256 + RIPEMD160)
pub fn hash160(data: []const u8, out: *[20]u8) void {
    if (embedded) {
        // Embedded profile: host extern for WASM, real RIPEMD160 for native
        if (is_wasm) {
            host_hash160(data.ptr, @intCast(data.len), out);
        } else {
            // Real HASH160: SHA256 then RIPEMD160 (pure Zig, no BSVZ)
            const Sha256 = @import("std").crypto.hash.sha2.Sha256;
            // Renamed to avoid shadowing the `pub fn ripemd160` below —
            // Zig 0.15 rejects local consts that shadow a same-named
            // declaration in the enclosing file.
            const ripemd160_mod = @import("ripemd160");
            var sha_out: [32]u8 = undefined;
            Sha256.hash(data, &sha_out, .{});
            ripemd160_mod.hash(&sha_out, out);
        }
    } else {
        // Full profile: BSVZ native (real RIPEMD160)
        const hash_result = bsvz.crypto.hash.hash160(data);
        @memcpy(out, &hash_result.bytes);
    }
}

/// HASH256 (double SHA256)
pub fn hash256(data: []const u8, out: *[32]u8) void {
    if (embedded) {
        if (is_wasm) {
            host_hash256(data.ptr, @intCast(data.len), out);
        } else {
            const Sha256 = @import("std").crypto.hash.sha2.Sha256;
            var first: [32]u8 = undefined;
            Sha256.hash(data, &first, .{});
            Sha256.hash(&first, out, .{});
        }
    } else {
        // Full profile: BSVZ native
        const hash = bsvz.crypto.hash.hash256(data);
        @memcpy(out, &hash.bytes);
    }
}

/// RIPEMD160 hash
pub fn ripemd160(data: []const u8, out: *[20]u8) void {
    if (embedded) {
        // Embedded profile: host extern for WASM, pure Zig for native
        if (is_wasm) {
            host_ripemd160(data.ptr, @intCast(data.len), out);
        } else {
            // Pure Zig RIPEMD160 (no BSVZ)
            const ripemd160_mod = @import("ripemd160");
            ripemd160_mod.hash(data, out);
        }
    } else {
        // Full profile: BSVZ native
        const hash = bsvz.crypto.hash.ripemd160(data);
        @memcpy(out, &hash.bytes);
    }
}

/// SHA1 hash
pub fn sha1(data: []const u8, out: *[20]u8) void {
    // Zig 0.15.2: Sha1 sits directly under std.crypto.hash (unlike Sha256
    // which lives in the .sha2 namespace). Older Zig used a .sha1
    // sub-namespace; updating both branches for consistency.
    if (embedded) {
        // Embedded profile: host extern for WASM, std lib for native.
        if (is_wasm) {
            host_sha1(data.ptr, @intCast(data.len), out);
        } else {
            const Sha1 = @import("std").crypto.hash.Sha1;
            var hasher = Sha1.init(.{});
            hasher.update(data);
            hasher.final(out);
        }
    } else {
        // Full profile: BSVZ doesn't expose sha1 in its `crypto.hash`
        // namespace, so fall back to the stdlib implementation.
        const Sha1 = @import("std").crypto.hash.Sha1;
        var hasher = Sha1.init(.{});
        hasher.update(data);
        hasher.final(out);
    }
}

/// ECDSA signature verification
/// sig includes SIGHASH type as last byte (BSV convention) — strip it before DER decode.
pub fn checksig(pubkey: []const u8, msg_hash: []const u8, sig: []const u8) bool {
    if (embedded) {
        // Embedded profile: WASM delegates to TS host (real ECDSA via @bsv/sdk).
        // Native has no secp256k1 — always returns false.
        // Real embedded CHECKSIG only works through the WASM→host path.
        if (is_wasm) {
            return host_checksig(
                pubkey.ptr,
                @intCast(pubkey.len),
                msg_hash.ptr,
                @intCast(msg_hash.len),
                sig.ptr,
                @intCast(sig.len),
            ) != 0;
        } else {
            // No secp256k1 in embedded native — cannot verify signatures.
            // Use full profile (BSVZ) for native tests requiring real ECDSA.
            return false;
        }
    } else {
        // Full profile: BSVZ native ECDSA verification
        if (sig.len < 2 or msg_hash.len != 32 or pubkey.len < 33) return false;

        // Strip sighash type byte (last byte of sig)
        const der_bytes = sig[0 .. sig.len - 1];

        // Parse the 32-byte digest
        const digest: [32]u8 = msg_hash[0..32].*;

        // Use BSVZ relaxed DER verification (handles non-canonical encodings from BSV)
        return bsvz.crypto.verifyDigest256RelaxedSec1(pubkey, digest, der_bytes) catch false;
    }
}

// ── Phase W3.5: DerivationStateStore registration (full profile only) ──
//
// In the full profile (native tests + sovereign-node target) the runtime
// installs a single DerivationStateStore via `setDerivationStateStore`.
// In the embedded profile (browser WASM bundle) the host.js side handles
// state — these natives are unused.

var current_state_store: ?*const derivation_state_mod.DerivationStateStore = null;

/// Install a DerivationStateStore for use by `host_state_next_index`.
/// Must be called before any wallet signing operation that derives leaves.
/// The pointer must outlive the engine.
pub fn setDerivationStateStore(store: *const derivation_state_mod.DerivationStateStore) void {
    current_state_store = store;
}

pub fn clearDerivationStateStore() void {
    current_state_store = null;
}

/// Atomically allocate and persist the next BRC-42 derivation index for a
/// (protocol_hash, counterparty) context. Returns true on success.
pub fn stateNextIndex(
    protocol_hash: *const [16]u8,
    counterparty: *const [33]u8,
    out_index: *u64,
) bool {
    if (embedded) {
        if (is_wasm) {
            return host_state_next_index(protocol_hash, counterparty, out_index) != 0;
        } else {
            return false;
        }
    } else {
        const store = current_state_store orelse return false;
        const idx = store.nextIndex(protocol_hash, counterparty) catch return false;
        out_index.* = idx;
        return true;
    }
}

/// BRC-42 leaf derivation: child = base + HMAC-SHA256(invoice, ECDH(base, counterparty)).
/// `invoice` is constructed as protocol_hash(16) || index_le(8) — a 24-byte
/// invariant the wallet uses to parameterize fresh-key-per-tx derivation.
pub fn deriveLeaf(
    base_sk: []const u8,
    protocol_hash: *const [16]u8,
    counterparty: *const [33]u8,
    index: u64,
    out_leaf: *[32]u8,
) bool {
    if (base_sk.len != 32) return false;
    if (embedded) {
        if (is_wasm) {
            return host_derive_leaf(
                base_sk.ptr,
                @intCast(base_sk.len),
                protocol_hash,
                counterparty,
                index,
                out_leaf,
            ) != 0;
        } else {
            return false;
        }
    } else {
        // Full profile: bsvz native BRC-42 derivation.
        var sk_bytes: [32]u8 = undefined;
        @memcpy(&sk_bytes, base_sk[0..32]);
        const ec_priv = bsvz.primitives.ec.PrivateKey.fromBytes(sk_bytes) catch return false;
        const ec_other = bsvz.primitives.ec.PublicKey.fromSec1(counterparty) catch return false;
        var invoice: [24]u8 = undefined;
        @memcpy(invoice[0..16], protocol_hash);
        std.mem.writeInt(u64, invoice[16..][0..8], index, .little);
        const child = ec_priv.deriveChild(ec_other, &invoice) catch return false;
        const child_bytes = child.toBytes();
        @memcpy(out_leaf, &child_bytes);
        return true;
    }
}

/// ECDSA signing over a 32-byte digest. Produces a DER signature, low-S normalized.
/// `sig_buf` must be at least 72 bytes (max DER signature length). The actual length
/// is written to `sig_len_out`. The caller is responsible for appending the sighash byte.
/// Returns true on success, false on any error (sig_buf untouched on failure).
pub fn sign(sk: []const u8, msg_hash: []const u8, sig_buf: []u8, sig_len_out: *u32) bool {
    if (sk.len != 32 or msg_hash.len != 32 or sig_buf.len == 0) return false;
    if (embedded) {
        // Embedded profile: WASM delegates to TS host (real ECDSA via @bsv/sdk).
        // Native has no secp256k1 — always returns false (use full profile for tests).
        if (is_wasm) {
            return host_sign(
                sk.ptr,
                @intCast(sk.len),
                msg_hash.ptr,
                @intCast(msg_hash.len),
                sig_buf.ptr,
                @intCast(sig_buf.len),
                sig_len_out,
            ) != 0;
        } else {
            return false;
        }
    } else {
        // Full profile: BSVZ native ECDSA signing via the primitives.ec wrapper —
        // matches the convention used by deriveLeaf() above (bsvz.primitives.ec
        // is the wallet-facing API; bsvz.crypto.PrivateKey is the lower-level
        // secp256k1 type and is reserved for free functions like verifyDigest256RelaxedSec1).
        var sk_bytes: [32]u8 = undefined;
        @memcpy(&sk_bytes, sk[0..32]);
        const priv = bsvz.primitives.ec.PrivateKey.fromBytes(sk_bytes) catch return false;
        var digest: [32]u8 = undefined;
        @memcpy(&digest, msg_hash[0..32]);
        const der_sig = priv.signDigest(digest) catch return false;
        const der_bytes = der_sig.bytes[0..der_sig.len];
        if (der_bytes.len > sig_buf.len) return false;
        @memcpy(sig_buf[0..der_bytes.len], der_bytes);
        sig_len_out.* = @intCast(der_bytes.len);
        return true;
    }
}

/// Multi-signature verification: m-of-n threshold check
pub fn checkmultisig(
    pubkeys: []const u8,
    pk_count: u32,
    sigs: []const u8,
    sig_count: u32,
    msg_hash: []const u8,
    threshold: u32,
) bool {
    if (embedded) {
        // Embedded profile: WASM delegates to TS host (real multisig via @bsv/sdk).
        // Native has no secp256k1 — always returns false.
        if (is_wasm) {
            return host_checkmultisig(
                pubkeys.ptr,
                pk_count,
                sigs.ptr,
                sig_count,
                msg_hash.ptr,
                @intCast(msg_hash.len),
                threshold,
            ) != 0;
        } else {
            // No secp256k1 in embedded native — cannot verify signatures.
            return false;
        }
    } else {
        // Full profile: BSVZ native sequential ECDSA per BSV consensus
        if (msg_hash.len != 32 or pk_count == 0 or sig_count == 0) return false;
        if (threshold > sig_count) return false;

        const digest: [32]u8 = msg_hash[0..32].*;
        var matches: u32 = 0;
        var pk_idx: u32 = 0;

        // Iterate signatures; for each sig, try remaining pubkeys in order (BSV consensus rule)
        var sig_offset: usize = 0;
        var sig_idx: u32 = 0;
        while (sig_idx < sig_count and pk_idx < pk_count) {
            // Read variable-length DER sig + sighash byte
            // In BSV CHECKMULTISIG, sigs and pubkeys are already separated
            // The caller packs them as: [sig1_len][sig1_bytes]...[sigN_len][sigN_bytes]
            // For now, assume fixed 33-byte pubkeys and variable sigs with length prefix
            if (sig_offset >= sigs.len) break;
            const sig_len = sigs[sig_offset];
            sig_offset += 1;
            if (sig_offset + sig_len > sigs.len) break;
            const current_sig = sigs[sig_offset .. sig_offset + sig_len];
            sig_offset += sig_len;

            // Strip sighash byte from sig
            if (current_sig.len < 2) {
                sig_idx += 1;
                continue;
            }
            const der_bytes = current_sig[0 .. current_sig.len - 1];

            // Try each remaining pubkey
            while (pk_idx < pk_count) {
                const pk_start = pk_idx * 33;
                if (pk_start + 33 > pubkeys.len) break;
                const current_pk = pubkeys[pk_start .. pk_start + 33];
                pk_idx += 1;

                if (bsvz.crypto.verifyDigest256RelaxedSec1(current_pk, digest, der_bytes) catch false) {
                    matches += 1;
                    break;
                }
            }
            sig_idx += 1;
        }

        return matches >= threshold;
    }
}

/// Get current block time: WASM calls host, native returns 0.
pub fn getBlocktime() u32 {
    if (is_wasm) {
        return host_get_blocktime();
    } else {
        return 0;
    }
}

/// Get nSequence of current input: WASM calls host, native returns 0xFFFFFFFF.
pub fn getSequence() u32 {
    if (is_wasm) {
        return host_get_sequence();
    } else {
        return 0xFFFFFFFF;
    }
}

/// Fetch a cell from a higher octave. WASM delegates to host runtime.
/// Native returns false — real octave fetch testing goes through WASM with TS host.
pub fn fetchCell(oct: u8, slot: u32, offset: u32, out: [*]u8) bool {
    if (comptime is_wasm) {
        return host_fetch_cell(oct, slot, offset, out) != 0;
    }
    // No octave storage in native test builds — always fails.
    // Real testing goes through the WASM→host path.
    _ = .{ oct, slot, offset, out };
    return false;
}

/// Log a message: WASM calls host, native uses debug print.
pub fn log(msg: []const u8) void {
    if (is_wasm) {
        host_log(msg.ptr, @intCast(msg.len));
    } else {
        // Native: no-op (avoid cluttering test output)
        if (msg.len > 0) {} // suppress unused warning
    }
}

/// Call a named host function. WASM delegates to the host runtime's
/// registry; native dispatches through the in-process registry below
/// (populated by `registerHostCall` at brain boot time).
///
/// Returns:
///   - `0..0x7FFFFFFE`     handler's success/value return
///   - `0xFFFFFFFF`        unknown function (not registered)
///   - `0xFFFFFFFE`        no execution context set
///   - other reserved      handler-specific errors
pub fn callByName(name: []const u8) u32 {
    if (comptime is_wasm) {
        return host_call_by_name(name.ptr, @intCast(name.len));
    }
    // Native: dispatch through the registry. Both pre-conditions must hold.
    const reg = lookupHostCall(name) orelse return 0xFFFFFFFF;
    const ctx = current_context orelse return 0xFFFFFFFE;
    return reg.handler(ctx);
}

// ── PR-3b: Native hostcall registry ───────────────────────────────────
//
// PolicyRuntime runs cell-engine scripts via `executor.execute()` in
// native (non-WASM) builds. Until PR-3b, `callByName` in that path
// returned 0xFFFFFFFF — meaning OP_CALLHOST could never reach any
// registered host function. This registry closes that gap.
//
// Shape:
//
//   1. Brain registers handlers at boot via `registerHostCall(name, fn)`.
//   2. Brain sets an execution context per script invocation via
//      `setExecutionContext(ctx)` — points at a `HostCallContext`
//      carrying inputs / outputs for whatever hostcalls the script
//      may use.
//   3. Script invokes OP_CALLHOST with the name on the stack; the
//      opcode pops the name + calls `callByName(name)` which dispatches
//      through the registry.
//   4. Handler casts `ctx` to the appropriate field-bearing type, reads
//      its inputs, writes its outputs into the context, returns u32
//      status.
//   5. OP_CALLHOST encodes the u32 as a script number and pushes it.
//
// The registry is file-scope (no allocator owned). Brain-process
// lifetime; reset via `resetRegistryForTest`.

/// Hostcall handler signature. Takes an opaque pointer to a context
/// the brain has set; returns a u32 status (0 = ok by convention).
pub const HostCallHandler = *const fn (context: *anyopaque) callconv(.c) u32;

pub const HostCallRegistration = struct {
    name: []const u8,
    handler: HostCallHandler,
};

pub const HostCallRegisterError = error{
    registry_full,
    duplicate_registration,
};

/// Maximum number of distinct hostcalls the substrate can register.
/// Generous headroom over the current C11 set (host_compute_sighash,
/// host_verify_beef_spv, host_request_sign, etc.) — bump if a real
/// deployment hits it.
pub const MAX_HOSTCALL_REGISTRATIONS: usize = 64;

var registrations: [MAX_HOSTCALL_REGISTRATIONS]HostCallRegistration = undefined;
var registration_count: usize = 0;

/// Pointer to the per-script-invocation execution context. The brain
/// sets this before invoking `executor.execute()` and clears it after.
/// Handlers reach through it to read inputs + write outputs.
var current_context: ?*anyopaque = null;

/// Register a hostcall handler. Boot-time only. Returns an error on
/// capacity overflow or duplicate name.
pub fn registerHostCall(name: []const u8, handler: HostCallHandler) HostCallRegisterError!void {
    if (lookupHostCall(name) != null) return error.duplicate_registration;
    if (registration_count >= MAX_HOSTCALL_REGISTRATIONS) return error.registry_full;
    registrations[registration_count] = .{ .name = name, .handler = handler };
    registration_count += 1;
}

/// Look up a hostcall by name. Linear scan — N is small and the call
/// site is hot per-script-opcode but bounded.
fn lookupHostCall(name: []const u8) ?*const HostCallRegistration {
    var i: usize = 0;
    while (i < registration_count) : (i += 1) {
        if (std.mem.eql(u8, registrations[i].name, name)) {
            return &registrations[i];
        }
    }
    return null;
}

/// Set the execution context. The brain calls this immediately before
/// `executor.execute()` and clears it (`setExecutionContext(null)`)
/// after.
pub fn setExecutionContext(ctx: ?*anyopaque) void {
    current_context = ctx;
}

/// Test-only: clear the registry + context. Production never calls.
pub fn resetRegistryForTest() void {
    registration_count = 0;
    current_context = null;
}

/// Test-only: report how many handlers are registered. Production may
/// log this at boot.
pub fn registryCountForTest() usize {
    return registration_count;
}

// ── Phase W4: SlotStore + per-tier KEK lifecycle (full profile only) ──
//
// In the full profile (native tests + sovereign-node target) the runtime
// installs a single SlotStore via `setSlotStore`, and unlocks each tier
// in turn by calling `unlockTier` (which derives a KEK from the user's
// factor and sets `current_keks[tier]`). Tier 0 has no KEK — Tier-0 cells
// use the session KEK installed via `setSessionKek` (or, for v0.1 tests,
// stay encrypted under a derived-from-zero default).
//
// In the embedded profile (browser WASM bundle) host.js handles all of
// this — these natives are unused.

const TIER_COUNT: usize = 4;

/// AES-GCM KEK width for the at-rest cell envelope. 32 bytes = AES-256-GCM.
pub const SLOT_KEK_BYTES: usize = 32;
// Layout constants are owned by `slot_store.zig` — re-export for callers
// that import host directly.
pub const SLOT_FORMAT_VERSION = slot_store_mod.SLOT_FORMAT_VERSION;
pub const SLOT_NONCE_BYTES = slot_store_mod.SLOT_NONCE_BYTES;
pub const SLOT_TAG_BYTES = slot_store_mod.SLOT_TAG_BYTES;
pub const SLOT_HEADER_BYTES = slot_store_mod.SLOT_HEADER_BYTES;

var current_slot_store: ?*const slot_store_mod.SlotStore = null;
var current_keks: [TIER_COUNT]?[SLOT_KEK_BYTES]u8 = .{ null, null, null, null };
var session_kek: ?[SLOT_KEK_BYTES]u8 = null;

/// Install a SlotStore for at-rest cell persistence. Pointer must outlive
/// the engine.
pub fn setSlotStore(store: *const slot_store_mod.SlotStore) void {
    current_slot_store = store;
}

/// Drop the slot-store reference. Does NOT clear active KEKs; call
/// `clearAllKeks` separately if locking the session.
pub fn clearSlotStore() void {
    current_slot_store = null;
}

/// Tests-only: install a Tier-0 session KEK directly (skips factor derivation).
/// In production the runtime sets this once per process, derived from a
/// per-install machine secret. Re-using this in tests avoids re-deriving for
/// every Tier-0 round-trip.
pub fn setSessionKek(kek: [SLOT_KEK_BYTES]u8) void {
    session_kek = kek;
}

pub fn clearSessionKek() void {
    if (session_kek) |*k| std.crypto.secureZero(u8, k);
    session_kek = null;
}

/// Zero and drop every per-tier KEK. Called when the session locks.
pub fn clearAllKeks() void {
    for (&current_keks) |*slot| {
        if (slot.*) |*k| std.crypto.secureZero(u8, k);
        slot.* = null;
    }
    clearSessionKek();
}

/// Returns true iff `tier` has been unlocked in this scope. Tier 0 is
/// considered unlocked when a session KEK is installed.
pub fn tierUnlocked(tier: u32) bool {
    if (tier == 0) return session_kek != null;
    if (tier >= TIER_COUNT) return false;
    return current_keks[@intCast(tier)] != null;
}

/// Derive a per-tier KEK from an opaque factor handle. v0.1 native uses
/// PBKDF2-HMAC-SHA256 with a tier-specific salt — Argon2id is the v0.2
/// upgrade (§4.1). The factor is treated as opaque bytes (PIN, passphrase,
/// or WebAuthn-assertion-derived secret).
fn deriveKek(tier: u32, factor: []const u8, out: *[SLOT_KEK_BYTES]u8) bool {
    const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
    var salt: [16]u8 = [_]u8{0} ** 16;
    // Domain-separate salt by literal "semantos:tier" prefix + tier number.
    const prefix = "semantos:tier=";
    @memcpy(salt[0..prefix.len], prefix);
    std.mem.writeInt(u16, salt[prefix.len..][0..2], @intCast(tier), .little);
    std.crypto.pwhash.pbkdf2(out, factor, &salt, 4096, Hmac) catch return false;
    return true;
}

/// Encode (nonce || tier || format_version) as the AES-GCM AAD so that
/// tampering with any envelope-prefix byte fails authentication.
fn buildAad(out: *[SLOT_HEADER_BYTES - SLOT_TAG_BYTES]u8, tier: u32, nonce: *const [SLOT_NONCE_BYTES]u8) void {
    std.mem.writeInt(u32, out[0..4], SLOT_FORMAT_VERSION, .little);
    std.mem.writeInt(u32, out[4..8], tier, .little);
    @memcpy(out[8..20], nonce);
}

/// Read the cell's tier from its 256-byte header (`domain_flag` lives at
/// offset 28, big-endian per §6.1). Tier-0 = 0x10000001, Tier-N base =
/// 0x10000002 + N. Returns null on a non-tier domain.
fn cellTierFromDomainFlag(cell: []const u8) ?u32 {
    if (cell.len < 32) return null;
    const flag = std.mem.readInt(u32, cell[28..32], .big);
    return switch (flag) {
        0x10000001 => 0, // HOT budget
        0x10000003 => 1, // base + 1
        0x10000004 => 2, // base + 2
        0x10000005 => 3, // base + 3
        else => null,
    };
}

/// Unlock tier N: derive KEK from factor, decrypt slot, write plaintext to
/// out_cell, install KEK for the duration of the session. Returns true on
/// success. Tier 0 is rejected — Tier-0 cells use the session KEK and are
/// reached via `loadCell` directly.
pub fn unlockTier(
    tier: u32,
    factor: []const u8,
    slot_id: u32,
    out_cell: []u8,
) bool {
    if (tier == 0 or tier >= TIER_COUNT) return false;
    if (embedded) {
        if (is_wasm) {
            return host_unlock_tier(
                tier,
                factor.ptr,
                @intCast(factor.len),
                slot_id,
                out_cell.ptr,
            ) != 0;
        } else {
            return false;
        }
    } else {
        const store = current_slot_store orelse return false;
        var kek: [SLOT_KEK_BYTES]u8 = undefined;
        if (!deriveKek(tier, factor, &kek)) return false;
        // Try to decrypt the slot. On failure, zero the candidate KEK and
        // leave `current_keks[tier]` untouched.
        if (!decryptSlot(store, slot_id, tier, &kek, out_cell)) {
            std.crypto.secureZero(u8, &kek);
            return false;
        }
        current_keks[@intCast(tier)] = kek;
        return true;
    }
}

/// Encrypt and persist a cell. The cell's tier is recovered from its
/// domain_flag; the KEK is the session KEK (Tier 0) or `current_keks[tier]`
/// (Tier 1+). Caller is responsible for ensuring the relevant tier has been
/// unlocked. Returns true on success.
pub fn persistCell(slot_id: u32, cell: []const u8) bool {
    if (embedded) {
        if (is_wasm) {
            return host_persist_cell(
                slot_id,
                cell.ptr,
                @intCast(cell.len),
            ) != 0;
        } else {
            return false;
        }
    } else {
        const store = current_slot_store orelse return false;
        const tier = cellTierFromDomainFlag(cell) orelse return false;
        const kek_ptr: *const [SLOT_KEK_BYTES]u8 = if (tier == 0) blk: {
            if (session_kek) |*k| break :blk k;
            return false;
        } else blk: {
            if (tier >= TIER_COUNT) return false;
            if (current_keks[@intCast(tier)]) |*k| break :blk k;
            return false;
        };
        return encryptSlot(store, slot_id, tier, kek_ptr, cell);
    }
}

/// Load a cell. Tier 0 requires only the session KEK; Tier 1+ requires
/// a prior `unlockTier` for that tier in this scope. The cell's tier is
/// inferred from the slot envelope header, not from the cell payload — the
/// envelope is authenticated under that tier's KEK, so a wrong-tier load
/// fails with auth-error.
pub fn loadCell(slot_id: u32, out_cell: []u8) bool {
    if (embedded) {
        if (is_wasm) {
            return host_load_cell(slot_id, out_cell.ptr) != 0;
        } else {
            return false;
        }
    } else {
        const store = current_slot_store orelse return false;
        // Peek at the envelope header to learn which tier the blob was
        // encrypted under, then dispatch to the right KEK.
        const blob = store.get(slot_id) catch return false;
        if (blob.len < SLOT_HEADER_BYTES) return false;
        const version = std.mem.readInt(u32, blob[0..4], .little);
        if (version != SLOT_FORMAT_VERSION) return false;
        const tier = std.mem.readInt(u32, blob[4..8], .little);
        if (tier >= TIER_COUNT) return false;
        const kek_ptr: *const [SLOT_KEK_BYTES]u8 = if (tier == 0) blk: {
            if (session_kek) |*k| break :blk k;
            return false;
        } else blk: {
            if (current_keks[@intCast(tier)]) |*k| break :blk k;
            return false;
        };
        return decryptSlot(store, slot_id, tier, kek_ptr, out_cell);
    }
}

/// Internal: encrypt `cell` under `kek`, fresh random 12-byte nonce, and
/// write the envelope to `slot_id`.
fn encryptSlot(
    store: *const slot_store_mod.SlotStore,
    slot_id: u32,
    tier: u32,
    kek: *const [SLOT_KEK_BYTES]u8,
    cell: []const u8,
) bool {
    if (embedded) return false;
    var nonce: [SLOT_NONCE_BYTES]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    var aad: [SLOT_HEADER_BYTES - SLOT_TAG_BYTES]u8 = undefined;
    buildAad(&aad, tier, &nonce);

    const allocator = std.heap.page_allocator;
    const enc = bsvz.primitives.aesgcm.aesGcmEncrypt(
        allocator,
        cell,
        kek,
        &nonce,
        &aad,
    ) catch return false;
    defer allocator.free(enc.ciphertext);

    const blob = allocator.alloc(u8, SLOT_HEADER_BYTES + enc.ciphertext.len) catch return false;
    defer allocator.free(blob);
    @memcpy(blob[0..20], &aad); // version || tier || nonce
    @memcpy(blob[20..36], &enc.tag);
    @memcpy(blob[36..], enc.ciphertext);

    store.put(slot_id, blob) catch return false;
    return true;
}

/// Internal: read envelope at `slot_id`, verify it was written under `tier`,
/// authenticate + decrypt the ciphertext into `out_cell`. Returns true on
/// success. On AES-GCM auth failure (tamper, wrong KEK, wrong tier) returns
/// false.
fn decryptSlot(
    store: *const slot_store_mod.SlotStore,
    slot_id: u32,
    tier: u32,
    kek: *const [SLOT_KEK_BYTES]u8,
    out_cell: []u8,
) bool {
    if (embedded) return false;
    const blob = store.get(slot_id) catch return false;
    if (blob.len < SLOT_HEADER_BYTES) return false;
    const stored_version = std.mem.readInt(u32, blob[0..4], .little);
    if (stored_version != SLOT_FORMAT_VERSION) return false;
    const stored_tier = std.mem.readInt(u32, blob[4..8], .little);
    if (stored_tier != tier) return false;

    const aad = blob[0..20];
    const tag: [SLOT_TAG_BYTES]u8 = blob[20..36][0..16].*;
    const ciphertext = blob[SLOT_HEADER_BYTES..];
    if (out_cell.len < ciphertext.len) return false;

    const allocator = std.heap.page_allocator;
    const plaintext = bsvz.primitives.aesgcm.aesGcmDecrypt(
        allocator,
        ciphertext,
        kek,
        blob[8..20], // nonce slice
        aad,
        tag,
    ) catch return false;
    defer allocator.free(plaintext);

    @memcpy(out_cell[0..plaintext.len], plaintext);
    return true;
}

```
