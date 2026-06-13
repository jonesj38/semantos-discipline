---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/kernel_zig.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.247365+00:00
---

# runtime/semantos-brain/src/kernel_zig.zig

```zig
// Phase 3 — brain-side kernel re-execution shim for the
// `oddjobz.intent_cell.v1` envelope.
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md ("Kernel result
//            reconciliation" section);
//            core/cell-engine/src/executor.zig (the canonical kernel
//            this shim mirrors);
//            apps/oddjobz-mobile/lib/src/gradient/oir_to_bytes.dart
//            (the L2 → L3 emitter that produces the bytes this shim
//            re-validates).
//
// What this is: a thin "re-validate the opcode bytes the phone sent"
// surface, importable from `runtime/semantos-brain/src/resources/intent_cells_
// handler.zig` as `executeOpcodeBytes(allocator, opcode_bytes) →
// LocalKernelResult`.
//
// What this IS NOT: a full PDA-driven kernel execution.  Wiring the
// real `executor.zig` from `core/cell-engine/src/executor.zig` into
// the Semantos Brain build requires pulling in ~14 transitive cell-engine modules
// (constants, errors, linearity, allocator, pda, sighash, host,
// build_options, standard, macro, plexus, hostcall, pointer, octave),
// many of which depend on `host.zig` which itself wants build-time
// `embedded` flag plumbing + bsvz integration.  That's a substantial
// build-graph refactor that doesn't fit the Phase 3 scope here.
//
// Phase 3 ("lenient policy" per the spec):
// We perform a conservative SYNTACTIC validation pass — well-formed
// pushdata frames, opcodes within known ranges, total length ≤
// MAX_SCRIPT_SIZE.  This catches every byte-stream the executor would
// reject for malformed-pushdata / script_too_large reasons.  Bytecode
// that is syntactically well-formed but semantically rejected by the
// executor at run time (insufficient sighash context, type-hash
// mismatch, etc.) DOES pass this shim — the spec accepts that as a
// Phase-1 trade-off ("brain stores values from local result; phone
// claim recorded for drift analysis").
//
// Phase 4 (deferred): swap this body for a real `executor.execute`
// call once the build wiring lands.  The exported entry point shape
// (`executeOpcodeBytes` → `LocalKernelResult`) stays stable so the
// handler's call sites don't have to change.

const std = @import("std");

/// Per cell-engine `executor.MAX_SCRIPT_SIZE` (10000 bytes).  Must
/// stay in lock-step with that constant; the spec's "≤ 10 KiB" gate
/// rounds to the same envelope.
pub const MAX_SCRIPT_SIZE: usize = 10_000;

/// Fail-closed verdict mirroring the spec doc's `kernelResult` shape.
/// `error_kind` is null on `ok: true`; on rejection it carries a
/// short token the handler echoes into the response detail for
/// operator triage.
pub const LocalKernelResult = struct {
    ok: bool,
    opcount: u32,
    stack_depth: u32,
    gas_used: u32,
    /// Borrowed; lives in this module's static error-kind table.
    error_kind: ?[]const u8,
};

pub const KernelError = error{
    /// Infrastructure failure on the Semantos Brain side (allocator OOM,
    /// hypothetical FFI panic).  Maps to `kernel_local_exec_failed`
    /// in the handler — distinct from `kernel_rejected_locally`.
    /// Mobile retries on this category (network-error class).
    kernel_local_exec_failed,
};

/// Re-execute (Phase 3: re-validate) the OIR-emitted opcode stream.
/// Returns a verdict the handler reconciles against the phone's
/// claimed `kernelResult`.
///
/// `allocator` is reserved for the Phase-4 real-executor switch (the
/// PDA + script arena allocate per-call); the Phase 3 syntactic body
/// makes no allocations.
pub fn executeOpcodeBytes(
    allocator: std.mem.Allocator,
    opcode_bytes: []const u8,
) KernelError!LocalKernelResult {
    _ = allocator;

    // Empty script — degenerate but well-formed.  The phone's OIR
    // emitter always produces ≥ 1 binding for any non-trivial intent;
    // an empty stream is suspicious but not a syntactic error.  We
    // accept it with `ok: true, opcount: 0` so the handler can decide
    // whether an empty-program intent is worth persisting.  (The
    // current handler accepts any well-formed envelope; intent-cell
    // existence is the load-bearing signal, not the bytes' depth.)
    if (opcode_bytes.len == 0) {
        return .{
            .ok = true,
            .opcount = 0,
            .stack_depth = 0,
            .gas_used = 0,
            .error_kind = null,
        };
    }

    if (opcode_bytes.len > MAX_SCRIPT_SIZE) {
        return .{
            .ok = false,
            .opcount = 0,
            .stack_depth = 0,
            .gas_used = 0,
            .error_kind = "script_too_large",
        };
    }

    // Walk the byte stream as a sequence of (opcode, optional pushdata
    // payload) frames.  Mirrors the same dispatch shape executor.zig
    // uses in `executeOneOpcode`: 0x00 → push empty; 0x01..0x4B →
    // direct push N bytes; 0x4C/0x4D/0x4E → PUSHDATA1/2/4; 0x4F.. →
    // single-byte opcodes (which the syntactic pass treats as opaque
    // — the real executor would dispatch them, but the phone has
    // already verified the stream and we're just confirming framing
    // hasn't been tampered with in transit).
    var pc: usize = 0;
    var opcount: u32 = 0;
    var stack_depth: u32 = 0;

    while (pc < opcode_bytes.len) {
        const op = opcode_bytes[pc];
        pc += 1;
        opcount += 1;

        if (op == 0x00) {
            // OP_0: push empty
            stack_depth += 1;
            continue;
        }
        if (op >= 0x01 and op <= 0x4B) {
            // Direct push of N bytes.
            const n: usize = op;
            if (pc + n > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            pc += n;
            stack_depth += 1;
            continue;
        }
        if (op == 0x4C) {
            // PUSHDATA1: 1-byte length
            if (pc >= opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            const n: usize = opcode_bytes[pc];
            pc += 1;
            if (pc + n > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            pc += n;
            stack_depth += 1;
            continue;
        }
        if (op == 0x4D) {
            // PUSHDATA2: 2-byte little-endian length
            if (pc + 2 > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            const n: usize = @as(usize, opcode_bytes[pc]) |
                (@as(usize, opcode_bytes[pc + 1]) << 8);
            pc += 2;
            if (pc + n > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            pc += n;
            stack_depth += 1;
            continue;
        }
        if (op == 0x4E) {
            // PUSHDATA4: 4-byte little-endian length
            if (pc + 4 > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            const n: usize = @as(usize, opcode_bytes[pc]) |
                (@as(usize, opcode_bytes[pc + 1]) << 8) |
                (@as(usize, opcode_bytes[pc + 2]) << 16) |
                (@as(usize, opcode_bytes[pc + 3]) << 24);
            pc += 4;
            if (n > MAX_SCRIPT_SIZE or pc + n > opcode_bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = stack_depth,
                    .gas_used = opcount,
                    .error_kind = "invalid_pushdata",
                };
            }
            pc += n;
            stack_depth += 1;
            continue;
        }

        // Single-byte opcode (0x4F..0xFF): syntactic pass treats it
        // as opaque.  The real executor (when wired in Phase 4) will
        // dispatch — for now we just count it.  Any value in this
        // range is byte-stream-syntactically valid; the phone's
        // already-verified stream is the upstream guarantor.
        //
        // Note: stack-depth accounting for non-push opcodes is
        // approximate (we don't model OP_DROP / OP_DUP / OP_EQUAL
        // semantics).  The handler stores the brain's "approximate"
        // stack_depth; the spec explicitly says exact equality with
        // the phone's claim is NOT required Phase 1.
    }

    return .{
        .ok = true,
        .opcount = opcount,
        .stack_depth = stack_depth,
        .gas_used = opcount,
        .error_kind = null,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — the validator's pure-function shape lets us cover the
// full "well-formed / malformed / oversized / empty" matrix without
// any I/O.  The handler-side conformance tests in tests/intent_cells_
// handler_conformance.zig exercise the integrated pipeline.
// ─────────────────────────────────────────────────────────────────────

test "executeOpcodeBytes: empty stream is ok with zero counters" {
    const r = try executeOpcodeBytes(std.testing.allocator, &.{});
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 0), r.opcount);
    try std.testing.expectEqual(@as(u32, 0), r.stack_depth);
    try std.testing.expectEqual(@as(u32, 0), r.gas_used);
    try std.testing.expect(r.error_kind == null);
}

test "executeOpcodeBytes: single OP_0 push is well-formed" {
    const r = try executeOpcodeBytes(std.testing.allocator, &.{0x00});
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 1), r.opcount);
    try std.testing.expectEqual(@as(u32, 1), r.stack_depth);
}

test "executeOpcodeBytes: direct push of 3 bytes (0x03 'a' 'b' 'c')" {
    const bytes = [_]u8{ 0x03, 'a', 'b', 'c' };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 1), r.opcount);
    try std.testing.expectEqual(@as(u32, 1), r.stack_depth);
}

test "executeOpcodeBytes: direct push truncated → invalid_pushdata" {
    // 0x05 promises 5 bytes; only 3 follow.
    const bytes = [_]u8{ 0x05, 'a', 'b', 'c' };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(!r.ok);
    try std.testing.expectEqualStrings("invalid_pushdata", r.error_kind.?);
}

test "executeOpcodeBytes: PUSHDATA1 well-formed" {
    // 0x4C 0x02 'a' 'b' — push 2 bytes
    const bytes = [_]u8{ 0x4C, 0x02, 'a', 'b' };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 1), r.opcount);
}

test "executeOpcodeBytes: PUSHDATA1 truncated → invalid_pushdata" {
    const bytes = [_]u8{ 0x4C, 0x05, 'a', 'b' };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(!r.ok);
    try std.testing.expectEqualStrings("invalid_pushdata", r.error_kind.?);
}

test "executeOpcodeBytes: PUSHDATA1 missing length byte → invalid_pushdata" {
    const bytes = [_]u8{0x4C};
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(!r.ok);
    try std.testing.expectEqualStrings("invalid_pushdata", r.error_kind.?);
}

test "executeOpcodeBytes: PUSHDATA2 well-formed (2-byte LE length)" {
    // 0x4D 0x02 0x00 'a' 'b' — push 2 bytes
    const bytes = [_]u8{ 0x4D, 0x02, 0x00, 'a', 'b' };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(r.ok);
}

test "executeOpcodeBytes: oversized script → script_too_large" {
    var huge: [MAX_SCRIPT_SIZE + 1]u8 = undefined;
    @memset(&huge, 0x00);
    const r = try executeOpcodeBytes(std.testing.allocator, &huge);
    try std.testing.expect(!r.ok);
    try std.testing.expectEqualStrings("script_too_large", r.error_kind.?);
}

test "executeOpcodeBytes: opaque single-byte opcodes count without rejecting" {
    // 0x87 = OP_EQUAL, 0xC3 = OP_CHECK_CAPABILITY (typed by OIR emitter).
    // The syntactic pass treats them as opaque — well-formed framing.
    const bytes = [_]u8{ 0x01, 0xAA, 0x01, 0xBB, 0x87 };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 3), r.opcount);
}

test "executeOpcodeBytes: realistic OIR-shaped stream (push + load_field + comparison)" {
    // Mirrors what oir_to_bytes.dart emits for a `summary = "X"` binding:
    //   pushString("X"), pushString("summary"), OP_LOAD_FIELD (0xB0),
    //   OP_EQUAL (0x87)
    const bytes = [_]u8{
        0x01, 'X', // push "X"
        0x07, 's', 'u', 'm', 'm', 'a', 'r', 'y', // push "summary"
        0xB0, // OP_LOAD_FIELD
        0x87, // OP_EQUAL
    };
    const r = try executeOpcodeBytes(std.testing.allocator, &bytes);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u32, 4), r.opcount);
}

```
