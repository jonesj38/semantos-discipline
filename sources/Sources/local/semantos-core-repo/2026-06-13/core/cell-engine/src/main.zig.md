---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.974685+00:00
---

# core/cell-engine/src/main.zig

```zig
// Semantos Cell Engine — WASM entry point
// Exports match PlexusKernelWasm from CORE:WASM.
// Phase 1: cell packing, Phase 2: BCA, Phase 3: 2-PDA executor
// Phase 5: BEEF/BUMP verification, capability token evaluation

const cell = @import("cell");
const multicell = @import("multicell");
const bca = @import("bca");
const constants = @import("constants");
const errors = @import("errors");
const linearity_mod = @import("linearity");
const host = @import("host");
const pda_mod = @import("pda");
const executor_mod = @import("executor");
const allocator_mod = @import("allocator");
const sighash_mod = @import("sighash");
const std = @import("std");
const build_options = @import("build_options");
const embedded = build_options.embedded;
// BEEF module only available in full profile
const beef_mod = if (!embedded) @import("beef") else struct {};
// Phase WH1 — pure-Zig BSV header verifier (works in both profiles).
const headers_mod = @import("headers");

// ── Global state ──
// Use undefined for large structs to avoid bloating the WASM data segment.
// kernel_init() must be called before any other export.

var g_pda: pda_mod.PDA = undefined;
// Script arena: 64KB on desktop, 2KB on embedded (carved 2026-05-21 from
// the prior 8KB for ESP32-C6 SRAM fit). Used for scratch allocations
// during script execution; demo scripts need very little here.
const ARENA_BUF_SIZE: usize = if (embedded) 2 * 1024 else 65536;
var g_arena_buf: [ARENA_BUF_SIZE]u8 = undefined;
var g_arena: allocator_mod.ScriptArena = undefined;
var g_ctx: executor_mod.ExecutionContext = undefined;
var g_tx_ctx: sighash_mod.TxContext = undefined;
var g_initialized: bool = false;

// M1.10: Single 1024-byte scratch buffer for cursor streaming.
// Peak heap is bounded at one cell — the buffer is reused on every pull.
var g_cursor_scratch: [constants.CELL_SIZE]u8 = undefined;

// ── Phase 3: Kernel exports ──

export fn kernel_init() callconv(.c) i32 {
    // Use initInPlace to avoid creating a 1.5MB struct on the WASM stack
    g_pda.initInPlace(executor_mod.DEFAULT_MAX_OPS);
    g_arena = allocator_mod.ScriptArena.init(&g_arena_buf);
    g_ctx = executor_mod.ExecutionContext.init(&g_pda, &g_arena);
    // Zig ≥0.15.2 stops eliding the return-by-value copy in
    // TxContext.init(), producing a ~2.45MB stack frame here.  The
    // 256KB WASM stack underflows and crashes on the first memory.fill
    // — observed as a runtime "Out of bounds memory access" on every
    // kernel_init call.  Use the in-place initialiser instead.
    g_tx_ctx.initInPlace();
    g_initialized = true;
    return 0;
}

export fn kernel_reset() callconv(.c) void {
    g_pda.reset();
    g_ctx.reset();
    g_arena.reset();
}

export fn kernel_load_script(script_ptr: [*]const u8, script_len: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;
    g_ctx.loadScript(script_ptr[0..script_len]) catch {
        return @intFromEnum(errors.KernelError.script_too_large);
    };
    return 0;
}

export fn kernel_load_unlock(unlock_ptr: [*]const u8, unlock_len: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;
    g_ctx.loadUnlock(unlock_ptr[0..unlock_len]) catch {
        return @intFromEnum(errors.KernelError.script_too_large);
    };
    return 0;
}

export fn kernel_execute() callconv(.c) i32 {
    if (!g_initialized) return -1;
    g_ctx.pc = 0;
    g_ctx.current_phase = .unlock;
    g_ctx.condition_depth = 0;
    g_ctx.executing = true;
    g_pda.opcount = 0;

    const result = executor_mod.execute(&g_ctx) catch |err| {
        g_pda.error_code = errorToCode(err);
        return g_pda.error_code;
    };

    return if (result) 0 else @intFromEnum(errors.KernelError.verify_failed);
}

export fn kernel_get_type_class() callconv(.c) i32 {
    // Returns: 0=LINEAR, 1=AFFINE, 2=RELEVANT, -1=UNCLASSIFIED
    // Matches TypeClassification enum in wasm-interface.ts
    //
    // Uses the cached linearity set during spush() when a CELL_SIZE (1024-byte)
    // item was pushed. This is necessary because PushDrop scripts drop the cell
    // off the stack via OP_2DROP before execution completes, so peeking the
    // stack post-execution would find it empty → UNCLASSIFIED.
    return g_pda.last_cell_linearity;
}

export fn kernel_set_enforcement(enabled: u32) callconv(.c) void {
    g_pda.enforcement_enabled = (enabled != 0);
}

export fn kernel_get_opcount() callconv(.c) u32 {
    return g_pda.opcount;
}

export fn kernel_get_error() callconv(.c) u32 {
    if (g_pda.error_msg_len == 0) return 0;
    return @intFromPtr(&g_pda.error_msg);
}

export fn kernel_stack_depth() callconv(.c) u32 {
    return g_pda.sdepth();
}

export fn kernel_stack_peek(index: u32) callconv(.c) u32 {
    const result = g_pda.speekAt(index) catch return 0;
    return @intFromPtr(result.data);
}

// ── Phase 3: Debug/stepping exports ──

export fn kernel_step() callconv(.c) i32 {
    if (!g_initialized) return -1;
    const result = executor_mod.step(&g_ctx) catch |err| {
        g_pda.error_code = errorToCode(err);
        return @intFromEnum(executor_mod.StepResult.done_error);
    };
    return @intFromEnum(result);
}

export fn kernel_get_pc() callconv(.c) u32 {
    return g_ctx.pc;
}

export fn kernel_get_current_op() callconv(.c) u8 {
    const script = g_ctx.currentScript();
    if (g_ctx.pc < g_ctx.currentScriptLen()) {
        return script[g_ctx.pc];
    }
    return 0;
}

export fn kernel_alt_stack_depth() callconv(.c) u32 {
    return g_pda.adepth();
}

export fn kernel_alt_stack_peek(index: u32) callconv(.c) u32 {
    if (index >= g_pda.aux_sp) return 0;
    const idx = g_pda.aux_sp - 1 - index;
    return @intFromPtr(&g_pda.aux_stack[idx]);
}

// ── Phase 7.5: Stack value length exports (top-indexed) ──

export fn kernel_stack_value_length(index: u32) callconv(.c) u32 {
    return g_pda.getMainLengthByIndex(index);
}

export fn kernel_alt_stack_value_length(index: u32) callconv(.c) u32 {
    return g_pda.getAuxLengthByIndex(index);
}

// ── Kernel state snapshot / restore ──
//
// Enables persistence and cross-node migration for OTP-hosted worlds
// (see apps/world-host + docs/prd/WORLD-PROTOCOL.md). The PDA struct is
// contiguous with no pointers (see pda.zig) so a straight @memcpy in and
// out is sufficient. The blob layout is:
//
//   [u32 magic   = 0x4E534543 ("CESN")]
//   [u32 version = 1]
//   [u32 length  = sizeof(PDA)]
//   [length bytes PDA image]
//
// The buffer is a process-static reservation large enough for one
// snapshot. Callers must copy the blob out before taking another snapshot
// if they intend to keep both.

const SNAPSHOT_MAGIC: u32 = 0x4E534543; // little-endian "CESN"
const SNAPSHOT_VERSION: u32 = 1;
const SNAPSHOT_HEADER_SIZE: usize = 12;

// On embedded targets, the snapshot buffer is sized for the (already-
// trimmed) PDA — but the snapshot feature itself is a debugger affordance
// that callers can opt out of. We keep the export so the surface stays
// stable, but the buffer is only the size of the header on embedded;
// kernel_snapshot_state then returns 0 (= "unavailable on this build").
// Saves ~20KB of static memory inside the 64KB linear-memory page.
const SNAPSHOT_MAX_SIZE: usize = if (embedded)
    SNAPSHOT_HEADER_SIZE
else
    @sizeOf(pda_mod.PDA) + SNAPSHOT_HEADER_SIZE;

var g_snapshot_buffer: [SNAPSHOT_MAX_SIZE]u8 align(8) = undefined;

/// Capture current PDA state into the snapshot buffer.
/// Returns the WASM pointer to the start of the blob, or 0 if the kernel
/// is not initialized OR if the snapshot feature was carved out (embedded).
export fn kernel_snapshot_state() callconv(.c) u32 {
    if (!g_initialized) return 0;
    if (embedded) return 0;   // snapshot buffer too small to hold a PDA

    const pda_size: u32 = @intCast(@sizeOf(pda_mod.PDA));

    std.mem.writeInt(u32, g_snapshot_buffer[0..4], SNAPSHOT_MAGIC, .little);
    std.mem.writeInt(u32, g_snapshot_buffer[4..8], SNAPSHOT_VERSION, .little);
    std.mem.writeInt(u32, g_snapshot_buffer[8..12], pda_size, .little);

    const pda_bytes = std.mem.asBytes(&g_pda);
    @memcpy(g_snapshot_buffer[SNAPSHOT_HEADER_SIZE..][0..pda_bytes.len], pda_bytes);

    return @intCast(@intFromPtr(&g_snapshot_buffer));
}

/// Restore PDA state from a snapshot blob previously returned by
/// `kernel_snapshot_state` (or one with an identical layout, potentially
/// passed in by a host embedder).
///
/// Return codes:
///   0  — restored
///  -1  — kernel not initialized
///  -2  — magic mismatch (blob not a snapshot or wrong endianness)
///  -3  — unsupported version
///  -4  — length mismatch (blob produced by a different PDA layout)
export fn kernel_restore_state(ptr: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;

    const header_ptr: [*]const u8 = @ptrFromInt(ptr);
    const magic = std.mem.readInt(u32, header_ptr[0..4], .little);
    const version = std.mem.readInt(u32, header_ptr[4..8], .little);
    const length = std.mem.readInt(u32, header_ptr[8..12], .little);

    if (magic != SNAPSHOT_MAGIC) return -2;
    if (version != SNAPSHOT_VERSION) return -3;
    if (length != @as(u32, @intCast(@sizeOf(pda_mod.PDA)))) return -4;

    const payload_ptr: [*]const u8 = @ptrFromInt(ptr + @as(u32, SNAPSHOT_HEADER_SIZE));
    const pda_bytes = std.mem.asBytes(&g_pda);
    @memcpy(pda_bytes, payload_ptr[0..pda_bytes.len]);

    return 0;
}

// ── Phase 3: Transaction context ──

export fn kernel_load_tx_context(
    tx_ptr: [*]const u8,
    tx_len: u32,
    input_index: u32,
    input_value: u64,
) callconv(.c) i32 {
    sighash_mod.parseTxContext(
        tx_ptr[0..tx_len],
        input_index,
        input_value,
        &g_tx_ctx,
    ) catch {
        return @intFromEnum(errors.KernelError.invalid_script);
    };
    g_ctx.tx_context = &g_tx_ctx;
    return 0;
}

// ── OP_BRANCHONOUTPUT (0xE0) support ──
// Set the current output index that OP_BRANCHONOUTPUT will push.
// Runtime-injected before each per-output script execution.
// Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md §3.
//
// Must be called AFTER kernel_load_tx_context (or after explicitly
// initializing g_tx_ctx) so the field has a valid TxContext to write
// into.  If called without a loaded context, initializes a default
// TxContext and binds g_ctx.tx_context to it.
export fn kernel_set_output_index(output_index: u32) callconv(.c) i32 {
    if (g_ctx.tx_context == null) {
        // initInPlace, not init() — see kernel_init comment.
        g_tx_ctx.initInPlace();
        g_ctx.tx_context = &g_tx_ctx;
    }
    g_tx_ctx.current_output_index = output_index;
    return 0;
}

// ── M1.10: Cursor-scan export ──
//
// Streams cells from the cell store via the three host-import cursor functions.
// The 1024-byte scratch buffer `g_cursor_scratch` lives in WASM linear memory
// and is reused on every pull — peak heap is exactly one cell.
//
// Parameters:
//   filter_ptr  — WASM linear-memory pointer to filter bytes (0 = no filter)
//   filter_len  — length of filter bytes (0 = no filter)
//   callback_ptr — WASM function table index of a callback(cell_ptr: u32) void;
//                  pass 0 to count without processing
//
// Returns: number of cells scanned (≥0), or negative error code:
//   -1 = hostDbOpenCursor returned 0 (store error / no free slots)
export fn kernel_cursor_scan(
    filter_ptr: u32,
    filter_len: u32,
    callback_ptr: u32,
) callconv(.c) i32 {
    const cursor_id = host.hostDbOpenCursor(filter_ptr, filter_len);
    if (cursor_id == 0) return -1;

    var count: i32 = 0;
    const scratch_ptr: u32 = @intCast(@intFromPtr(&g_cursor_scratch));

    while (host.hostDbCursorPull(cursor_id, scratch_ptr) == 1) {
        count += 1;
        if (callback_ptr != 0) {
            // Invoke the WASM function-pointer callback with the scratch address.
            // The callback receives a u32 pointer into linear memory.
            //
            // In a freestanding WASM build the host is responsible for setting
            // up the indirect call table. Here we use the `@call` builtin with
            // a typed function pointer cast from the table index. Because
            // wasm32-freestanding has no WASI, we model the callback as a
            // direct function pointer stored in the table.
            //
            // For the conformance test (native Zig target) this path is not
            // exercised — the test calls CursorHost.cursorScan() directly.
            // For WASM targets, the runtime must populate the function table.
            const cb: *const fn (u32) callconv(.c) void = @ptrFromInt(callback_ptr);
            cb(scratch_ptr);
        }
    }

    host.hostDbCursorClose(cursor_id);
    return count;
}

fn errorToCode(err: anyerror) i32 {
    return switch (err) {
        error.stack_overflow => @intFromEnum(errors.KernelError.stack_overflow),
        error.stack_underflow => @intFromEnum(errors.KernelError.stack_underflow),
        error.script_too_large => @intFromEnum(errors.KernelError.script_too_large),
        error.invalid_opcode => @intFromEnum(errors.KernelError.invalid_opcode),
        error.verify_failed => @intFromEnum(errors.KernelError.verify_failed),
        error.disabled_opcode => @intFromEnum(errors.KernelError.disabled_opcode),
        error.execution_limit => @intFromEnum(errors.KernelError.execution_limit),
        error.invalid_script => @intFromEnum(errors.KernelError.invalid_script),
        error.invalid_sighash => @intFromEnum(errors.KernelError.invalid_sighash),
        error.no_tx_context => @intFromEnum(errors.KernelError.no_tx_context),
        error.nesting_depth_exceeded => @intFromEnum(errors.KernelError.nesting_depth_exceeded),
        error.unknown_macro => @intFromEnum(errors.KernelError.unknown_macro),
        error.not_implemented => @intFromEnum(errors.KernelError.not_implemented),
        // Phase 4: linearity + plexus errors
        error.cannot_duplicate_linear => @intFromEnum(errors.KernelError.cannot_duplicate_linear),
        error.cannot_discard_linear => @intFromEnum(errors.KernelError.cannot_discard_linear),
        error.cannot_duplicate_affine => @intFromEnum(errors.KernelError.cannot_duplicate_affine),
        error.cannot_discard_relevant => @intFromEnum(errors.KernelError.cannot_discard_relevant),
        error.invalid_linearity_type => @intFromEnum(errors.KernelError.invalid_linearity_type),
        error.linearity_check_failed => @intFromEnum(errors.KernelError.linearity_check_failed),
        error.domain_flag_mismatch => @intFromEnum(errors.KernelError.domain_flag_mismatch),
        error.type_hash_mismatch => @intFromEnum(errors.KernelError.type_hash_mismatch),
        error.owner_id_mismatch => @intFromEnum(errors.KernelError.owner_id_mismatch),
        error.capability_type_mismatch => @intFromEnum(errors.KernelError.capability_type_mismatch),
        error.reserved_opcode => @intFromEnum(errors.KernelError.reserved_opcode),
        // Phase 5: BEEF/BUMP/SPV + capability errors
        error.beef_parse_error => @intFromEnum(errors.KernelError.beef_parse_error),
        error.beef_invalid_proof => @intFromEnum(errors.KernelError.beef_invalid_proof),
        error.beef_txid_not_found => @intFromEnum(errors.KernelError.beef_txid_not_found),
        error.bump_invalid_proof => @intFromEnum(errors.KernelError.bump_invalid_proof),
        error.bump_parse_error => @intFromEnum(errors.KernelError.bump_parse_error),
        error.capability_script_failed => @intFromEnum(errors.KernelError.capability_script_failed),
        error.capability_not_linear => @intFromEnum(errors.KernelError.capability_not_linear),
        error.checksig_failed => @intFromEnum(errors.KernelError.checksig_failed),
        // Phase 6: octave memory errors
        error.invalid_pointer_cell => @intFromEnum(errors.KernelError.invalid_pointer_cell),
        error.host_fetch_failed => @intFromEnum(errors.KernelError.host_fetch_failed),
        else => -1,
    };
}

// ── Phase 1: Cell packing exports ──

/// Pack a cell from header (256 bytes) + payload into WASM memory.
export fn cell_pack(
    header_ptr: [*]const u8,
    payload_ptr: [*]const u8,
    payload_len: u32,
    out_ptr: [*]u8,
) callconv(.c) i32 {
    var hdr = cell.CellHeader{
        .magic = undefined,
        .linearity = undefined,
        .version = undefined,
        .flags = undefined,
        .ref_count = undefined,
        .type_hash = undefined,
        .owner_id = undefined,
        .timestamp = undefined,
        .cell_count = undefined,
        .total_size = undefined,
        .reserved = undefined,
    };

    @memcpy(&hdr.magic, header_ptr[0..16]);
    hdr.linearity = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_LINEARITY..][0..4], .little);
    hdr.version = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_VERSION..][0..4], .little);
    hdr.flags = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_FLAGS..][0..4], .little);
    hdr.ref_count = std.mem.readInt(u16, header_ptr[constants.HEADER_OFFSET_REF_COUNT..][0..2], .little);
    @memcpy(&hdr.type_hash, header_ptr[constants.HEADER_OFFSET_TYPE_HASH..][0..32]);
    @memcpy(&hdr.owner_id, header_ptr[constants.HEADER_OFFSET_OWNER_ID..][0..16]);
    hdr.timestamp = std.mem.readInt(u64, header_ptr[constants.HEADER_OFFSET_TIMESTAMP..][0..8], .little);
    hdr.cell_count = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_CELL_COUNT..][0..4], .little);
    hdr.total_size = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_PAYLOAD_TOTAL..][0..4], .little);
    // RM-032b: HEADER_OFFSET_COMMERCE_PHASE was stripped; the reserved
    // block still starts at absolute header byte 94 per the CellHeader
    // struct.
    @memcpy(&hdr.reserved, header_ptr[94..][0..162]);

    const payload = payload_ptr[0..payload_len];
    const out: *[constants.CELL_SIZE]u8 = @ptrCast(out_ptr[0..constants.CELL_SIZE]);

    cell.packCell(&hdr, payload, out) catch {
        return 10;
    };

    return 0;
}

export fn cell_unpack(
    cell_ptr: [*]const u8,
    header_out_ptr: [*]u8,
    payload_out_ptr: [*]u8,
) callconv(.c) i32 {
    const cell_buf: *const [constants.CELL_SIZE]u8 = @ptrCast(cell_ptr[0..constants.CELL_SIZE]);

    const result = cell.unpackCell(cell_buf) catch {
        return -9;
    };

    @memcpy(header_out_ptr[0..constants.HEADER_SIZE], cell_ptr[0..constants.HEADER_SIZE]);
    @memcpy(payload_out_ptr[0..constants.PAYLOAD_SIZE], &result.payload);

    return @intCast(result.payload_len);
}

export fn cell_validate_magic(cell_ptr: [*]const u8) callconv(.c) i32 {
    const cell_buf: *const [constants.CELL_SIZE]u8 = @ptrCast(cell_ptr[0..constants.CELL_SIZE]);
    return if (cell.validateMagic(cell_buf)) 1 else 0;
}

// ── Phase 1: Multi-cell packing exports ──

export fn multicell_pack(
    header_ptr: [*]const u8,
    payload_ptr: [*]const u8,
    payload_len: u32,
    cont_types_ptr: [*]const u8,
    cont_offsets_ptr: [*]const u8,
    cont_sizes_ptr: [*]const u8,
    cont_data_ptr: [*]const u8,
    cont_count: u32,
    out_ptr: [*]u8,
) callconv(.c) i32 {
    if (cont_count > multicell.MAX_CONTINUATIONS) return -11;

    var hdr: cell.CellHeader = undefined;
    @memcpy(&hdr.magic, header_ptr[0..16]);
    hdr.linearity = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_LINEARITY..][0..4], .little);
    hdr.version = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_VERSION..][0..4], .little);
    hdr.flags = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_FLAGS..][0..4], .little);
    hdr.ref_count = std.mem.readInt(u16, header_ptr[constants.HEADER_OFFSET_REF_COUNT..][0..2], .little);
    @memcpy(&hdr.type_hash, header_ptr[constants.HEADER_OFFSET_TYPE_HASH..][0..32]);
    @memcpy(&hdr.owner_id, header_ptr[constants.HEADER_OFFSET_OWNER_ID..][0..16]);
    hdr.timestamp = std.mem.readInt(u64, header_ptr[constants.HEADER_OFFSET_TIMESTAMP..][0..8], .little);
    hdr.cell_count = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_CELL_COUNT..][0..4], .little);
    hdr.total_size = std.mem.readInt(u32, header_ptr[constants.HEADER_OFFSET_PAYLOAD_TOTAL..][0..4], .little);
    // RM-032b: HEADER_OFFSET_COMMERCE_PHASE was stripped; the reserved
    // block still starts at absolute header byte 94 per the CellHeader
    // struct.
    @memcpy(&hdr.reserved, header_ptr[94..][0..162]);

    var conts: [multicell.MAX_CONTINUATIONS]multicell.ContinuationInput = undefined;
    for (0..cont_count) |i| {
        const offset_bytes = cont_offsets_ptr[i * 4 ..][0..4];
        const size_bytes = cont_sizes_ptr[i * 4 ..][0..4];
        const data_offset: usize = std.mem.readInt(u32, offset_bytes, .little);
        const data_size: usize = std.mem.readInt(u32, size_bytes, .little);

        conts[i] = .{
            .cell_type = cont_types_ptr[i],
            .data = cont_data_ptr[data_offset..][0..data_size],
        };
    }

    const total_out_size = (1 + cont_count) * constants.CELL_SIZE;
    const out_slice = out_ptr[0..total_out_size];

    const written = multicell.packMultiCell(
        &hdr,
        payload_ptr[0..payload_len],
        conts[0..cont_count],
        out_slice,
    ) catch |e| {
        return switch (e) {
            error.payload_too_large => -10,
            error.buffer_too_small => -12,
            error.too_many_continuations => -11,
        };
    };

    return @intCast(written);
}

export fn multicell_unpack(
    buffer_ptr: [*]const u8,
    buffer_len: u32,
) callconv(.c) i32 {
    const buffer = buffer_ptr[0..buffer_len];
    const result = multicell.unpackMultiCell(buffer) catch |e| {
        return switch (e) {
            error.invalid_magic => -9,
            error.buffer_too_small => -12,
            error.invalid_buffer_size => -11,
            error.invalid_continuation_header => -13,
        };
    };

    return @intCast(1 + result.continuation_count);
}

// ── Phase 2: BCA exports ──

export fn bca_derive(
    pubkey_ptr: [*]const u8,
    prefix_ptr: [*]const u8,
    modifier_ptr: [*]const u8,
    sec: u8,
    out_ptr: [*]u8,
) callconv(.c) i32 {
    const input = bca.BCAInput{
        .pubkey = pubkey_ptr[0..33].*,
        .subnet_prefix = prefix_ptr[0..8].*,
        .modifier = modifier_ptr[0..16].*,
        .sec = sec,
    };

    const result = bca.deriveBCA(&input) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.invalid_sec_parameter));
    };

    @memcpy(out_ptr[0..16], &result.address);
    return @intCast(result.collision_count);
}

export fn bca_verify(
    addr_ptr: [*]const u8,
    pubkey_ptr: [*]const u8,
    prefix_ptr: [*]const u8,
    modifier_ptr: [*]const u8,
) callconv(.c) i32 {
    const input = bca.BCAInput{
        .pubkey = pubkey_ptr[0..33].*,
        .subnet_prefix = prefix_ptr[0..8].*,
        .modifier = modifier_ptr[0..16].*,
        .sec = 0,
    };

    const addr: *const [16]u8 = @ptrCast(addr_ptr[0..16]);
    return if (bca.verifyBCA(addr, &input)) 1 else 0;
}

// ── Phase 5: BEEF/BUMP verification exports (full profile only) ──

/// Detect BEEF version from raw binary data.
/// Returns: 1=BRC-62 V1, 2=BRC-96 V2, 3=BRC-95 Atomic, -1=invalid
export fn kernel_beef_version(data_ptr: [*]const u8, data_len: u32) callconv(.c) i32 {
    if (!embedded) {
        const data = data_ptr[0..data_len];
        const version = beef_mod.detectVersion(data);
        return @intFromEnum(version);
    } else {
        return @intFromEnum(errors.KernelError.not_implemented);
    }
}

/// Verify a BEEF envelope contains valid merkle proof for a transaction.
/// Returns: 0=valid, negative=error code
export fn kernel_verify_beef(beef_ptr: [*]const u8, beef_len: u32, txid_ptr: [*]const u8) callconv(.c) i32 {
    if (!embedded) {
        const beef_data = beef_ptr[0..beef_len];
        const txid: [32]u8 = txid_ptr[0..32].*;

        // Use a fixed buffer allocator over the global arena buffer for BEEF parsing
        g_arena.reset();
        var fba = std.heap.FixedBufferAllocator.init(&g_arena_buf);
        const ally = fba.allocator();

        const valid = beef_mod.verifyBeef(ally, beef_data, txid) catch |err| {
            return switch (err) {
                error.beef_parse_error => -@as(i32, @intFromEnum(errors.KernelError.beef_parse_error)),
                error.beef_invalid_proof => -@as(i32, @intFromEnum(errors.KernelError.beef_invalid_proof)),
                error.beef_txid_not_found => -@as(i32, @intFromEnum(errors.KernelError.beef_txid_not_found)),
                else => -1,
            };
        };
        return if (valid) 0 else -@as(i32, @intFromEnum(errors.KernelError.beef_invalid_proof));
    } else {
        return -@as(i32, @intFromEnum(errors.KernelError.not_implemented));
    }
}

/// Verify a BEEF envelope with real SPV: caller supplies trusted merkle roots.
/// This is the real SPV path — validates both structure AND that merkle roots
/// match the caller's trusted roots (from block headers).
/// Returns: 0=valid, negative=error code
export fn kernel_verify_beef_spv(
    beef_ptr: [*]const u8,
    beef_len: u32,
    txid_ptr: [*]const u8,
    roots_ptr: [*]const u8,
    roots_count: u32,
) callconv(.c) i32 {
    if (!embedded) {
        const beef_data = beef_ptr[0..beef_len];
        const txid: [32]u8 = txid_ptr[0..32].*;

        // Build trusted roots array from packed 32-byte entries
        var trusted_roots: [64][32]u8 = undefined; // max 64 roots
        const count = @min(roots_count, 64);
        for (0..count) |i| {
            const offset = i * 32;
            trusted_roots[i] = roots_ptr[offset..][0..32].*;
        }

        g_arena.reset();
        var fba = std.heap.FixedBufferAllocator.init(&g_arena_buf);
        const ally = fba.allocator();

        const valid = beef_mod.verifyBeefSpv(ally, beef_data, txid, trusted_roots[0..count]) catch |err| {
            return switch (err) {
                error.beef_parse_error => -@as(i32, @intFromEnum(errors.KernelError.beef_parse_error)),
                error.beef_invalid_proof => -@as(i32, @intFromEnum(errors.KernelError.beef_invalid_proof)),
                error.beef_txid_not_found => -@as(i32, @intFromEnum(errors.KernelError.beef_txid_not_found)),
                else => -1,
            };
        };
        return if (valid) 0 else -@as(i32, @intFromEnum(errors.KernelError.beef_invalid_proof));
    } else {
        return -@as(i32, @intFromEnum(errors.KernelError.not_implemented));
    }
}

/// Verify a BUMP merkle proof for a specific txid against an expected merkle root.
/// Returns: 0=valid, negative=error code
export fn kernel_verify_bump(
    bump_ptr: [*]const u8,
    bump_len: u32,
    txid_ptr: [*]const u8,
    merkle_root_ptr: [*]const u8,
) callconv(.c) i32 {
    if (!embedded) {
        const bump_data = bump_ptr[0..bump_len];
        const txid: [32]u8 = txid_ptr[0..32].*;
        const expected_root: [32]u8 = merkle_root_ptr[0..32].*;

        g_arena.reset();
        var fba = std.heap.FixedBufferAllocator.init(&g_arena_buf);
        const ally = fba.allocator();

        const valid = beef_mod.verifyBump(ally, bump_data, txid, expected_root) catch |err| {
            return switch (err) {
                error.bump_parse_error => -@as(i32, @intFromEnum(errors.KernelError.bump_parse_error)),
                error.bump_invalid_proof => -@as(i32, @intFromEnum(errors.KernelError.bump_invalid_proof)),
                else => -1,
            };
        };
        return if (valid) 0 else -@as(i32, @intFromEnum(errors.KernelError.bump_invalid_proof));
    } else {
        return -@as(i32, @intFromEnum(errors.KernelError.not_implemented));
    }
}

// ── Phase WH1: Trustless-SPV header verifier (both profiles) ──
//
// Pure-Zig PoW + chain validation.  The browser bundle calls these from
// `cartridges/wallet-headers/brain/src/header-validator.ts` to enforce that every header
// the WH3 fetcher accepts has been validated by code that's bit-identical
// across browser and sovereign-node deployments (WASM-MANIFEST property).
//
// Memory model: callers pass a pointer to an 80-byte header (LE wire form).
// No allocations, no globals touched — re-entrant.

/// Compute SHA256d(80-byte header) and write 32 bytes (internal byte order
/// — display order is reversed) to `out_ptr`. Returns 0 on success.
export fn kernel_header_compute_hash(
    header_ptr: [*]const u8,
    out_ptr: [*]u8,
) callconv(.c) i32 {
    const h = headers_mod.Header.parseRaw(header_ptr[0..80]);
    const hash = h.computeHash();
    @memcpy(out_ptr[0..32], &hash);
    return 0;
}

/// Returns 1 if SHA256d(header) < target_from(header.bits), 0 otherwise.
/// Negative on parse / encoding error.
export fn kernel_header_verify_pow(header_ptr: [*]const u8) callconv(.c) i32 {
    const h = headers_mod.Header.parseRaw(header_ptr[0..80]);
    return if (h.satisfiesProofOfWork()) 1 else 0;
}

/// Validate `candidate` against `parent` plus chain context.
///   parent_ptr:        80 bytes
///   candidate_ptr:     80 bytes
///   parent_height:     u32
///   prev_ts_ptr:       up to 11 u32 LE timestamps (medianTimePast input)
///   prev_ts_count:     0..11
///   pow_limit_bits:    consensus powLimit (0x1d00ffff for mainnet,
///                      0x207fffff for tests/regtest)
///   now_seconds:       optional clock cap; 0 disables
///
/// Returns 0 = valid, negative HeaderError code otherwise.
export fn kernel_header_validate(
    parent_ptr: [*]const u8,
    candidate_ptr: [*]const u8,
    parent_height: u32,
    prev_ts_ptr: [*]const u8,
    prev_ts_count: u32,
    pow_limit_bits: u32,
    now_seconds: u32,
) callconv(.c) i32 {
    const parent = headers_mod.Header.parseRaw(parent_ptr[0..80]);
    const candidate = headers_mod.Header.parseRaw(candidate_ptr[0..80]);

    // Decode prior timestamps (u32 LE × prev_ts_count). Cap at 11 for MTP.
    var prev_ts_buf: [11]u32 = undefined;
    const n = @min(prev_ts_count, 11);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const offset = i * 4;
        prev_ts_buf[i] = std.mem.readInt(u32, prev_ts_ptr[offset..][0..4], .little);
    }

    const inputs = headers_mod.ValidateInputs{
        .parent = &parent,
        .parent_height = parent_height,
        .prev_timestamps = prev_ts_buf[0..n],
        .pow_limit_bits = pow_limit_bits,
        .now_seconds = now_seconds,
    };
    headers_mod.validateHeader(&candidate, &inputs) catch |err| {
        // Map header errors to a stable negative-code surface for TS.
        return switch (err) {
            error.too_short => -101,
            error.too_long => -102,
            error.invalid_bits => -103,
            error.insufficient_pow => -104,
            error.prev_hash_mismatch => -105,
            error.timestamp_too_early => -106,
            error.timestamp_too_far_future => -107,
            error.wrong_difficulty => -108,
        };
    };
    return 0;
}

// ── Phase 5: Capability token evaluation (both profiles) ──

/// Evaluate a capability token locking script.
/// Pushes context onto the stack, enables enforcement, and executes the script.
/// Returns: 0=valid capability, negative=error code
export fn kernel_verify_capability(
    lock_script_ptr: [*]const u8,
    lock_script_len: u32,
    owner_pubkey_ptr: [*]const u8, // 33 bytes compressed
    cap_type: u8, // CapabilityType enum value (0-5)
    domain_flag: u32,
    current_time: u32,
) callconv(.c) i32 {
    if (!g_initialized) return -1;

    // Reset engine state for capability verification
    kernel_reset();

    const lock_script = lock_script_ptr[0..lock_script_len];

    // Push context values onto the stack in order (bottom to top):
    // current_time, domain_flag, cap_type, owner_pubkey

    // Push current_time as 4-byte LE
    var time_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &time_bytes, current_time, .little);
    g_pda.spush(&time_bytes) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.stack_overflow));
    };

    // Push domain_flag as 4-byte LE
    var flag_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &flag_bytes, domain_flag, .little);
    g_pda.spush(&flag_bytes) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.stack_overflow));
    };

    // Push cap_type as 1-byte
    const cap_byte = [_]u8{cap_type};
    g_pda.spush(&cap_byte) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.stack_overflow));
    };

    // Push owner pubkey (33 bytes)
    g_pda.spush(owner_pubkey_ptr[0..33]) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.stack_overflow));
    };

    // Enable linearity enforcement
    g_pda.enforcement_enabled = true;

    // Load and execute the locking script
    g_ctx.loadScript(lock_script) catch {
        return -@as(i32, @intFromEnum(errors.KernelError.script_too_large));
    };
    g_ctx.pc = 0;
    g_ctx.current_phase = .lock;
    g_ctx.executing = true;
    g_pda.opcount = 0;

    const result = executor_mod.execute(&g_ctx) catch |err| {
        g_pda.error_code = errorToCode(err);
        return -@as(i32, @intFromEnum(errors.KernelError.capability_script_failed));
    };

    if (!result) {
        return -@as(i32, @intFromEnum(errors.KernelError.capability_script_failed));
    }

    return 0;
}

```
