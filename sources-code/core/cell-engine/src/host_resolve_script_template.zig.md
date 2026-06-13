---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_resolve_script_template.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.975522+00:00
---

# core/cell-engine/src/host_resolve_script_template.zig

```zig
// PR-4: host_resolve_script_template — the cell-engine-facing handler
// for lockScript and unlockScript template resolution per
// LOCKSCRIPT-CLEAVAGE.md §8.2.
//
// Design note — single hostcall vs. two
// =====================================
//
// The design doc names two hostcalls (host_resolve_lockscript_template
// and host_resolve_unlockscript_template) for narrative clarity, but
// the mechanism is identical: copy a template byte sequence, apply
// (slot_index, replacement_bytes) bindings at recorded positions,
// emit the resulting bytes. Both gate under cap.tx.build. Splitting
// into two named hostcalls would duplicate code without adding gating
// granularity, so PR-4 ships ONE hostcall, "host_resolve_script_template",
// that handles both regions.
//
// If a future use case needs differential capability gating (e.g.,
// distinct caps for tx-building vs. signing contexts), revisit the
// split — but only when there's a concrete justification.
//
// Lifecycle:
//
//   1. Brain boot calls `register()` once (idempotent; duplicate
//      registration treated as OK in cells_mint_handler).
//   2. Brain populates a `Context` per script invocation with:
//        - template_bytes: the unresolved bytes from the cartridge
//          manifest (PR-2 assembler's .lockScript.hex or
//          .unlockScript.template.hex output)
//        - slots: the slot metadata recorded at assembler-compile time
//          (kind + byte offset + byte length per slot)
//        - bindings: handler-or-brain-computed replacements
//        - output buffer (caller-owned; up to MAX_TEMPLATE_SIZE bytes)
//   3. Script invokes OP_CALLHOST "host_resolve_script_template".
//   4. Handler copies template to output, applies each binding, sets
//      `output_len`, returns 0 on success.
//   5. Brain reads the output bytes and either persists them as a cell
//      or feeds them to a follow-on hostcall (host_compute_sighash
//      with scriptCode argument, etc.).
//
// What this PR does NOT validate
// ===============================
//
// Consensus-subset bytes in the resolved output. The brain populates
// the bindings; if a malicious or buggy binding injects a >= 0xB0
// opcode byte into a region intended for .lockScript, the resolved
// bytes would be non-consensus. PR-5's host_assemble_tx + the
// pre-broadcast verifier will catch this; PR-4's hostcall is the
// substitution primitive only.

const std = @import("std");
const host = @import("host");

/// Maximum template size — mirrors core/cell-engine/src/executor.zig::
/// MAX_SCRIPT_SIZE. Templates larger than this can't be assembled by
/// the PR-2 sectioned assembler anyway.
pub const MAX_TEMPLATE_SIZE: usize = 10_000;

/// Maximum number of slots a single template may carry. Generous — the
/// typical lockScript/unlockScript has <= 2 slots (SIG + PUBKEY) and
/// pathological templates with many slots are unlikely.
pub const MAX_SLOTS: usize = 16;

/// Slot kinds — mirror `core/cell-engine/tools/asm.zig::SlotKind` so
/// the assembler's output and this handler's input agree on the
/// vocabulary. Adding a new kind: append here AND in asm.zig.
pub const SlotKind = enum(u8) {
    /// 72-byte DER signature + sighash flag (unlockScript)
    sig = 0,
    /// 33-byte compressed secp256k1 pubkey (unlockScript)
    pubkey = 1,
    /// 32-byte payload hash (lockScript, PushDrop commitment)
    payload_hash = 2,
    /// 16-byte owner identifier (lockScript)
    owner_id = 3,
    /// Generic — any byte length, declared at slot-recording time
    generic = 4,
};

/// One slot's position inside the template. Mirrors asm.zig's `Slot`.
pub const Slot = struct {
    kind: SlotKind,
    offset: usize,
    length: usize,
};

/// One binding: which slot to fill + the replacement bytes.
pub const SlotBinding = struct {
    slot_index: usize,
    /// Caller-owned bytes. Must equal `slots[slot_index].length`.
    bytes: []const u8,
};

/// Per-invocation context. Brain populates fields, invokes the
/// hostcall, then reads `output[0..output_len]` on success.
pub const Context = struct {
    template_bytes: []const u8,
    slots: []const Slot,
    bindings: []const SlotBinding,

    /// Output buffer — caller-owned. Must hold at least
    /// `template_bytes.len` bytes.
    output: []u8,
    /// Set by `handle` on success to the resolved byte length (always
    /// equals `template_bytes.len` since substitution is in-place;
    /// lengths must match).
    output_len: usize = 0,
    last_error: u32 = 0,
};

/// Return codes the handler emits. Must fit in u32 since that's the
/// return type of `host.callByName`.
pub const RC_OK: u32 = 0;
pub const RC_TEMPLATE_TOO_LARGE: u32 = 1;
pub const RC_OUTPUT_TOO_SMALL: u32 = 2;
pub const RC_UNKNOWN_SLOT_INDEX: u32 = 3;
pub const RC_BINDING_LENGTH_MISMATCH: u32 = 4;
pub const RC_SLOT_OUT_OF_BOUNDS: u32 = 5;

/// Registered handler. Copies the template into the output buffer
/// then overwrites each slot's bytes with the corresponding binding.
/// Bindings outside the slot vocabulary or with mismatched lengths
/// fail with a specific RC_* code.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    if (ctx.template_bytes.len > MAX_TEMPLATE_SIZE) {
        ctx.last_error = RC_TEMPLATE_TOO_LARGE;
        return RC_TEMPLATE_TOO_LARGE;
    }
    if (ctx.template_bytes.len > ctx.output.len) {
        ctx.last_error = RC_OUTPUT_TOO_SMALL;
        return RC_OUTPUT_TOO_SMALL;
    }

    // Copy the template verbatim — substitutions happen in place below.
    @memcpy(ctx.output[0..ctx.template_bytes.len], ctx.template_bytes);

    // Apply each binding. Validate slot index + binding length match
    // the recorded slot length BEFORE writing so a failure leaves only
    // the in-progress output partially written — caller reads
    // `output_len = 0` on failure and treats the buffer as garbage.
    for (ctx.bindings) |b| {
        if (b.slot_index >= ctx.slots.len) {
            ctx.last_error = RC_UNKNOWN_SLOT_INDEX;
            return RC_UNKNOWN_SLOT_INDEX;
        }
        const slot = ctx.slots[b.slot_index];
        if (slot.offset + slot.length > ctx.template_bytes.len) {
            ctx.last_error = RC_SLOT_OUT_OF_BOUNDS;
            return RC_SLOT_OUT_OF_BOUNDS;
        }
        if (b.bytes.len != slot.length) {
            ctx.last_error = RC_BINDING_LENGTH_MISMATCH;
            return RC_BINDING_LENGTH_MISMATCH;
        }
        @memcpy(ctx.output[slot.offset..][0..slot.length], b.bytes);
    }

    ctx.output_len = ctx.template_bytes.len;
    ctx.last_error = RC_OK;
    return RC_OK;
}

/// Register `host_resolve_script_template` with the cell-engine host
/// registry. Brain calls this once at boot (idempotent via
/// bootRegisterHostCalls in cells_mint_handler.zig).
pub fn register() !void {
    try host.registerHostCall("host_resolve_script_template", handle);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "handle: happy path — single SIG slot at offset 1" {
    host.resetRegistryForTest();
    try register();

    // Template: 0x48 + 72 zero bytes (the PR-2 SIG placeholder shape).
    var template: [73]u8 = [_]u8{0} ** 73;
    template[0] = 0x48;
    const slots = [_]Slot{
        .{ .kind = .sig, .offset = 1, .length = 72 },
    };
    var sig_bytes: [72]u8 = [_]u8{0xAB} ** 72;
    const bindings = [_]SlotBinding{
        .{ .slot_index = 0, .bytes = &sig_bytes },
    };
    var output: [128]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_OK, rc);
    try testing.expectEqual(@as(usize, 73), ctx.output_len);
    // Output's first byte is the length prefix (unchanged).
    try testing.expectEqual(@as(u8, 0x48), output[0]);
    // Slot bytes are now 0xAB.
    for (output[1..73]) |b| try testing.expectEqual(@as(u8, 0xAB), b);
}

test "handle: happy path — SIG + PUBKEY (PR-2's canonical pattern)" {
    host.resetRegistryForTest();
    try register();

    // Template: 0x48 + 72 zeros (SIG placeholder) + 0x21 + 33 zeros
    // (PUBKEY placeholder) = 107 bytes total.
    var template: [107]u8 = [_]u8{0} ** 107;
    template[0] = 0x48;
    template[73] = 0x21;
    const slots = [_]Slot{
        .{ .kind = .sig, .offset = 1, .length = 72 },
        .{ .kind = .pubkey, .offset = 74, .length = 33 },
    };
    var sig_bytes: [72]u8 = [_]u8{0xCD} ** 72;
    var pub_bytes: [33]u8 = [_]u8{0xEF} ** 33;
    const bindings = [_]SlotBinding{
        .{ .slot_index = 0, .bytes = &sig_bytes },
        .{ .slot_index = 1, .bytes = &pub_bytes },
    };
    var output: [128]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_OK, rc);
    try testing.expectEqual(@as(usize, 107), ctx.output_len);
    try testing.expectEqual(@as(u8, 0x48), output[0]); // length prefix preserved
    try testing.expectEqual(@as(u8, 0xCD), output[1]); // SIG byte 0
    try testing.expectEqual(@as(u8, 0xCD), output[72]); // SIG byte 71
    try testing.expectEqual(@as(u8, 0x21), output[73]); // PUBKEY length prefix preserved
    try testing.expectEqual(@as(u8, 0xEF), output[74]); // PUBKEY byte 0
    try testing.expectEqual(@as(u8, 0xEF), output[106]); // PUBKEY byte 32
}

test "handle: empty bindings → exact template copy" {
    host.resetRegistryForTest();
    try register();

    const template = [_]u8{ 0x51, 0x69, 0x77 };
    const slots = [_]Slot{};
    const bindings = [_]SlotBinding{};
    var output: [32]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_OK, rc);
    try testing.expectEqual(@as(usize, 3), ctx.output_len);
    try testing.expectEqualSlices(u8, &template, output[0..3]);
}

test "handle: unknown slot_index → RC_UNKNOWN_SLOT_INDEX" {
    host.resetRegistryForTest();
    try register();

    const template = [_]u8{ 0x51, 0x69 };
    const slots = [_]Slot{
        .{ .kind = .sig, .offset = 0, .length = 1 },
    };
    var bad_bytes = [_]u8{0xAA};
    const bindings = [_]SlotBinding{
        // slot_index = 5 but only 1 slot exists.
        .{ .slot_index = 5, .bytes = &bad_bytes },
    };
    var output: [32]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_UNKNOWN_SLOT_INDEX, rc);
    try testing.expectEqual(@as(usize, 0), ctx.output_len);
}

test "handle: binding length mismatch → RC_BINDING_LENGTH_MISMATCH" {
    host.resetRegistryForTest();
    try register();

    const template = [_]u8{ 0x48, 0x00, 0x00, 0x00 };
    const slots = [_]Slot{
        .{ .kind = .sig, .offset = 1, .length = 3 },
    };
    // Slot expects 3 bytes; binding provides 5.
    var wrong_len = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE };
    const bindings = [_]SlotBinding{
        .{ .slot_index = 0, .bytes = &wrong_len },
    };
    var output: [32]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_BINDING_LENGTH_MISMATCH, rc);
    try testing.expectEqual(@as(usize, 0), ctx.output_len);
}

test "handle: output buffer too small → RC_OUTPUT_TOO_SMALL" {
    host.resetRegistryForTest();
    try register();

    const template = [_]u8{ 0x51, 0x69, 0x77, 0x76, 0x75 };
    const slots = [_]Slot{};
    const bindings = [_]SlotBinding{};
    var output: [2]u8 = undefined; // smaller than template

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_OUTPUT_TOO_SMALL, rc);
}

test "handle: slot out of bounds → RC_SLOT_OUT_OF_BOUNDS" {
    host.resetRegistryForTest();
    try register();

    const template = [_]u8{ 0x51, 0x69 };
    // Slot extends past template length.
    const slots = [_]Slot{
        .{ .kind = .sig, .offset = 1, .length = 5 },
    };
    var bytes = [_]u8{ 1, 2, 3, 4, 5 };
    const bindings = [_]SlotBinding{
        .{ .slot_index = 0, .bytes = &bytes },
    };
    var output: [32]u8 = undefined;

    var ctx: Context = .{
        .template_bytes = &template,
        .slots = &slots,
        .bindings = &bindings,
        .output = &output,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(RC_SLOT_OUT_OF_BOUNDS, rc);
}

```
