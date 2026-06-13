---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/executor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.974107+00:00
---

# core/cell-engine/src/executor.zig

```zig
// Script executor — Phase 3
// Dispatches opcodes to standard/macro handlers, enforces bounded execution.
// Bitcoin Script is loop-free: pc always advances, no backward jumps.

const constants = @import("constants");
const errors = @import("errors");
const pda_mod = @import("pda");
const standard = @import("standard");
const macro = @import("macro");
const plexus = @import("plexus");
const hostcall = @import("hostcall");
const routing = @import("routing");
const allocator_mod = @import("allocator");
const sighash = @import("sighash");
const std = @import("std");

pub const StepResult = enum(i32) {
    continue_execution = 0,
    done_true = 1,
    done_false = 2,
    done_error = -1,
};

pub const MAX_SCRIPT_SIZE: u32 = 10000;
pub const MAX_IF_NESTING: u32 = 100;
pub const DEFAULT_MAX_OPS: u32 = 500000;

pub const ExecuteError = error{
    stack_overflow,
    stack_underflow,
    execution_limit,
    verify_failed,
    disabled_opcode,
    invalid_opcode,
    invalid_script,
    invalid_pushdata,
    nesting_depth_exceeded,
    invalid_sighash,
    no_tx_context,
    not_implemented,
    unknown_macro,
    script_too_large,
    // Phase 4: linearity and plexus errors
    cannot_duplicate_linear,
    cannot_discard_linear,
    cannot_duplicate_affine,
    cannot_discard_relevant,
    invalid_linearity_type,
    linearity_check_failed,
    domain_flag_mismatch,
    type_hash_mismatch,
    owner_id_mismatch,
    capability_type_mismatch,
    cell_too_short,
    reserved_opcode,
    // Phase 6: octave memory errors
    invalid_pointer_cell,
    host_fetch_failed,
    // Phase 25.5: host function dispatch errors
    unknown_host_function,
    host_function_failed,
    invalid_function_name,
    // Plexus cell-construction errors (Phase 4 additions) — raised by
    // opcodes/plexus.zig but previously missing from the executor's error
    // set, which caused a compile error when plexus.executePlexus/2 was
    // called from executor.zig:345.
    invalid_header_offset,
    invalid_payload_offset,
    invalid_linearity_transition,
    invalid_cell_construction,
    // Phase W1: wallet tier-key signing
    sign_failed,
    // Phase W3: wallet budget opcodes
    insufficient_budget,
    invalid_refill_signature,
};

pub const ExecutionContext = struct {
    pda: *pda_mod.PDA,
    arena: *allocator_mod.ScriptArena,
    tx_context: ?*const sighash.TxContext,

    // Script buffers
    lock_script: [MAX_SCRIPT_SIZE]u8,
    lock_script_len: u32,
    unlock_script: [MAX_SCRIPT_SIZE]u8,
    unlock_script_len: u32,

    // Execution state
    pc: u32,
    current_phase: enum { unlock, lock, done },
    has_error: bool,

    // IF/ELSE/ENDIF nesting
    condition_stack: [MAX_IF_NESTING]bool,
    condition_depth: u32,
    executing: bool, // are we in an executing branch?

    pub fn init(p: *pda_mod.PDA, arena: *allocator_mod.ScriptArena) ExecutionContext {
        return .{
            .pda = p,
            .arena = arena,
            .tx_context = null,
            .lock_script = undefined,
            .lock_script_len = 0,
            .unlock_script = undefined,
            .unlock_script_len = 0,
            .pc = 0,
            .current_phase = .unlock,
            .has_error = false,
            .condition_stack = [_]bool{true} ** MAX_IF_NESTING,
            .condition_depth = 0,
            .executing = true,
        };
    }

    pub fn reset(self: *ExecutionContext) void {
        self.lock_script_len = 0;
        self.unlock_script_len = 0;
        self.pc = 0;
        self.current_phase = .unlock;
        self.has_error = false;
        self.condition_depth = 0;
        self.executing = true;
        self.tx_context = null;
        self.arena.reset();
    }

    pub fn loadScript(self: *ExecutionContext, script: []const u8) !void {
        if (script.len > MAX_SCRIPT_SIZE) return error.script_too_large;
        @memcpy(self.lock_script[0..script.len], script);
        self.lock_script_len = @intCast(script.len);
    }

    pub fn loadUnlock(self: *ExecutionContext, script: []const u8) !void {
        if (script.len > MAX_SCRIPT_SIZE) return error.script_too_large;
        @memcpy(self.unlock_script[0..script.len], script);
        self.unlock_script_len = @intCast(script.len);
    }

    pub fn currentScript(self: *const ExecutionContext) []const u8 {
        return switch (self.current_phase) {
            .unlock => self.unlock_script[0..self.unlock_script_len],
            .lock => self.lock_script[0..self.lock_script_len],
            .done => &[_]u8{},
        };
    }

    pub fn currentScriptLen(self: *const ExecutionContext) u32 {
        return switch (self.current_phase) {
            .unlock => self.unlock_script_len,
            .lock => self.lock_script_len,
            .done => 0,
        };
    }
};

/// Execute unlock + lock scripts. Returns true if top-of-stack is truthy.
pub fn execute(ctx: *ExecutionContext) ExecuteError!bool {
    ctx.pc = 0;
    ctx.current_phase = .unlock;
    ctx.condition_depth = 0;
    ctx.executing = true;

    // Run unlock script (if any)
    if (ctx.unlock_script_len > 0) {
        try executeScript(ctx);
    }

    // Transition to lock script
    ctx.pc = 0;
    ctx.current_phase = .lock;
    ctx.condition_depth = 0;
    ctx.executing = true;

    // Run lock script
    if (ctx.lock_script_len > 0) {
        try executeScript(ctx);
    }

    ctx.current_phase = .done;

    // Script succeeds if stack is non-empty and top is truthy
    if (ctx.pda.sdepth() == 0) return false;
    const top = ctx.pda.speek() catch return false;
    return pda_mod.isTruthy(top.data, top.len);
}

fn executeScript(ctx: *ExecutionContext) ExecuteError!void {
    const script = ctx.currentScript();
    while (ctx.pc < ctx.currentScriptLen()) {
        try executeOneOpcode(ctx, script);
    }
    // Verify all IF/ENDIF balanced
    if (ctx.condition_depth != 0) return error.invalid_script;
}

/// Execute a single opcode at the current pc. Returns step result.
pub fn step(ctx: *ExecutionContext) ExecuteError!StepResult {
    if (ctx.current_phase == .done) return .done_error;

    // Skip empty unlock phase
    if (ctx.current_phase == .unlock and ctx.unlock_script_len == 0) {
        ctx.pc = 0;
        ctx.current_phase = .lock;
    }

    const script_len = ctx.currentScriptLen();
    if (ctx.pc >= script_len) {
        // End of current script
        if (ctx.current_phase == .unlock) {
            ctx.pc = 0;
            ctx.current_phase = .lock;
            if (ctx.lock_script_len == 0) {
                ctx.current_phase = .done;
                return checkFinalResult(ctx);
            }
            return .continue_execution;
        } else {
            ctx.current_phase = .done;
            return checkFinalResult(ctx);
        }
    }

    const script = ctx.currentScript();
    executeOneOpcode(ctx, script) catch |err| {
        ctx.has_error = true;
        ctx.pda.error_code = switch (err) {
            error.stack_overflow => 1,
            error.stack_underflow => 2,
            error.script_too_large => 3,
            error.invalid_opcode => 4,
            error.verify_failed => 6,
            error.disabled_opcode => 7,
            error.execution_limit => 8,
            else => -1,
        };
        return .done_error;
    };

    // Check if we've finished the current script
    if (ctx.pc >= ctx.currentScriptLen()) {
        if (ctx.current_phase == .unlock) {
            ctx.pc = 0;
            ctx.current_phase = .lock;
            return .continue_execution;
        } else {
            ctx.current_phase = .done;
            return checkFinalResult(ctx);
        }
    }

    return .continue_execution;
}

fn checkFinalResult(ctx: *ExecutionContext) StepResult {
    if (ctx.pda.sdepth() == 0) return .done_false;
    const top = ctx.pda.speek() catch return .done_false;
    return if (pda_mod.isTruthy(top.data, top.len)) .done_true else .done_false;
}

fn executeOneOpcode(ctx: *ExecutionContext, script: []const u8) ExecuteError!void {
    // Check execution limit
    if (ctx.pda.opcount >= ctx.pda.max_ops) return error.execution_limit;

    const opcode = script[ctx.pc];
    ctx.pc += 1;
    ctx.pda.opcount += 1;

    // OP_0 (0x00): push empty
    if (opcode == 0x00) {
        if (!ctx.executing) return;
        try ctx.pda.spush(&[_]u8{});
        return;
    }

    // Direct push: 0x01-0x4B (push next N bytes)
    if (opcode >= 0x01 and opcode <= 0x4B) {
        const n: u32 = opcode;
        if (!ctx.executing) {
            ctx.pc += n; // skip past data bytes even in false branch
            return;
        }
        if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
        try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
        ctx.pc += n;
        return;
    }

    // PUSHDATA1/2/4
    if (opcode == standard.OP_PUSHDATA1) {
        if (ctx.pc >= ctx.currentScriptLen()) return error.invalid_pushdata;
        const n: u32 = script[ctx.pc];
        ctx.pc += 1;
        if (!ctx.executing) {
            ctx.pc += n; // skip past data bytes
            return;
        }
        if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
        try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
        ctx.pc += n;
        return;
    }
    if (opcode == standard.OP_PUSHDATA2) {
        if (ctx.pc + 2 > ctx.currentScriptLen()) return error.invalid_pushdata;
        const n: u32 = std.mem.readInt(u16, script[ctx.pc..][0..2], .little);
        ctx.pc += 2;
        if (!ctx.executing) {
            ctx.pc += n; // skip past data bytes
            return;
        }
        if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
        try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
        ctx.pc += n;
        return;
    }
    if (opcode == standard.OP_PUSHDATA4) {
        if (ctx.pc + 4 > ctx.currentScriptLen()) return error.invalid_pushdata;
        const n = std.mem.readInt(u32, script[ctx.pc..][0..4], .little);
        ctx.pc += 4;
        if (!ctx.executing) {
            ctx.pc += n; // skip past data bytes
            return;
        }
        if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
        try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
        ctx.pc += n;
        return;
    }

    // Standard opcodes (0x4F-0xAF)
    if (opcode >= 0x4F and opcode <= constants.OPCODE_STANDARD_MAX) {
        var pc_usize: usize = ctx.pc;
        try standard.execute(
            ctx.pda,
            opcode,
            script,
            &pc_usize,
            ctx.arena,
            ctx.tx_context,
            &ctx.condition_stack,
            &ctx.condition_depth,
            &ctx.executing,
        );
        ctx.pc = @intCast(pc_usize);
        return;
    }

    // Craig macros (0xB0-0xBF)
    if (opcode >= constants.OPCODE_CRAIG_MACRO_MIN and opcode <= constants.OPCODE_CRAIG_MACRO_MAX) {
        if (!ctx.executing) return;
        try macro.executeMacro(ctx.pda, opcode);
        return;
    }

    // Plexus opcodes (0xC0-0xCF) — Phase 4
    if (opcode >= constants.OPCODE_PLEXUS_MIN and opcode <= constants.OPCODE_PLEXUS_MAX) {
        if (!ctx.executing) return;
        try plexus.executePlexus(ctx.pda, opcode);
        return;
    }

    // Host function dispatch (0xD0) — Phase 25.5
    if (opcode == constants.OP_CALLHOST) {
        if (!ctx.executing) return;
        try hostcall.executeCallHost(ctx.pda);
        return;
    }

    // OP_WRITEPAYLOAD (0xD1) — Plexus-family cell-mutation op carved
    // out of the hostcall reserved range. Lives in plexus.zig; the
    // executor dispatches by re-entering executePlexus with 0xD1.
    if (opcode == 0xD1) {
        if (!ctx.executing) return;
        try plexus.executePlexus(ctx.pda, opcode);
        return;
    }

    // Routing opcodes (0xE0..0xEF) — OP_BRANCHONOUTPUT et al.
    // Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md
    if (opcode >= constants.OPCODE_ROUTING_MIN and opcode <= constants.OPCODE_ROUTING_MAX) {
        if (!ctx.executing) return;
        try routing.executeRouting(ctx.pda, opcode, ctx.tx_context);
        return;
    }

    return error.invalid_opcode;
}

```
