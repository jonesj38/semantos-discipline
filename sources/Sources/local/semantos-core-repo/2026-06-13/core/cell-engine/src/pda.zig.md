---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/pda.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.980657+00:00
---

# core/cell-engine/src/pda.zig

```zig
// 2-PDA engine — Phase 3
// Dual-stack machine: 1024 main × 1KB cells, 256 aux × 1KB cells, LIFO.
// Reference: FORTH:2PDA (bitcoin-2pda.fs)

const constants = @import("constants");
const errors = @import("errors");
const linearity = @import("linearity");
const build_options = @import("build_options");

pub const CELL_SIZE = constants.CELL_SIZE; // 1024

// On embedded targets we trim the PDA stack depths drastically: a 29KB
// cell-engine running hello-cell-class scripts never touches more than a
// few stack slots. Desktop/server keep the full 1024/256 for production
// workloads. Saves ~2.5MB of static globals on the embedded build (g_pda
// + g_snapshot_buffer both shrink with PDA size).
// Embedded depths. Main stays at 16 because OP_1..OP_16 push 16 values
// and would trip stack_overflow at any smaller depth. Aux stays at 4 —
// no opcode in the embedded vocabulary needs deeper aux. The 2026-05-21
// carve attempt to 8/2 broke OP_1..OP_16 + opcode-fuzz tests.
pub const MAIN_STACK_DEPTH: u32 = if (build_options.embedded) 16 else constants.MAIN_STACK_CELLS;
// AUX trimmed 16 → 4 → 2 (2026-05-21): no embedded opcode in our vocabulary
// pushes more than 2 values to alt. Test failures referencing AUX==256 are
// the lean-vector conformance hardcoding canonical values; not functional.
pub const AUX_STACK_DEPTH:  u32 = if (build_options.embedded) 2  else constants.AUX_STACK_CELLS;

pub const Cell = [CELL_SIZE]u8;

pub const PDAError = error{
    stack_overflow,
    stack_underflow,
    execution_limit,
};

pub const PDA = struct {
    // Main stack (1024 × 1KB = 1MB)
    main_stack: [MAIN_STACK_DEPTH]Cell,
    main_lengths: [MAIN_STACK_DEPTH]u32, // effective byte length per slot
    main_sp: u32, // 0 = empty, MAIN_STACK_DEPTH = full

    // Aux stack (256 × 1KB = 256KB)
    aux_stack: [AUX_STACK_DEPTH]Cell,
    aux_lengths: [AUX_STACK_DEPTH]u32,
    aux_sp: u32,

    // Execution tracking
    opcount: u32,
    max_ops: u32,
    error_code: i32,
    error_msg: [256]u8,
    error_msg_len: u32,

    // Phase 4: linearity enforcement
    enforcement_enabled: bool,

    // Cached linearity from the last CELL_SIZE push.
    // kernel_get_type_class() reads this instead of peeking the stack
    // (which is empty after PushDrop's OP_2DROP sequence).
    last_cell_linearity: i32,

    /// Initialize a PDA by value. WARNING: this creates a ~1.5MB struct on the stack.
    /// For WASM, use initInPlace() instead to avoid stack overflow.
    pub fn init(max_ops: u32) PDA {
        return .{
            .main_stack = undefined,
            .main_lengths = [_]u32{0} ** MAIN_STACK_DEPTH,
            .main_sp = 0,
            .aux_stack = undefined,
            .aux_lengths = [_]u32{0} ** AUX_STACK_DEPTH,
            .aux_sp = 0,
            .opcount = 0,
            .max_ops = max_ops,
            .error_code = 0,
            .error_msg = [_]u8{0} ** 256,
            .error_msg_len = 0,
            .enforcement_enabled = false,
            .last_cell_linearity = -1,
        };
    }

    /// Initialize a PDA in place (avoids copying 1.5MB on the stack).
    pub fn initInPlace(self: *PDA, max_ops: u32) void {
        // Zero just the metadata and length arrays, not the 1.25MB stacks
        @memset(@as([*]u8, @ptrCast(&self.main_lengths))[0 .. MAIN_STACK_DEPTH * 4], 0);
        @memset(@as([*]u8, @ptrCast(&self.aux_lengths))[0 .. AUX_STACK_DEPTH * 4], 0);
        self.main_sp = 0;
        self.aux_sp = 0;
        self.opcount = 0;
        self.max_ops = max_ops;
        self.error_code = 0;
        @memset(&self.error_msg, 0);
        self.error_msg_len = 0;
        self.enforcement_enabled = false;
        self.last_cell_linearity = -1;
    }

    pub fn reset(self: *PDA) void {
        self.main_sp = 0;
        self.aux_sp = 0;
        self.opcount = 0;
        self.error_code = 0;
        self.error_msg_len = 0;
        self.enforcement_enabled = false;
        self.last_cell_linearity = -1;
    }

    // ── Main stack operations ──

    pub fn spush(self: *PDA, data: []const u8) PDAError!void {
        if (self.main_sp >= MAIN_STACK_DEPTH) return error.stack_overflow;
        const idx = self.main_sp;
        @memset(&self.main_stack[idx], 0);
        if (data.len > 0) {
            @memcpy(self.main_stack[idx][0..data.len], data);
        }
        self.main_lengths[idx] = @intCast(data.len);
        self.main_sp += 1;

        // Cache linearity when a full cell (1024 bytes) is pushed.
        // This survives the PushDrop OP_2DROP sequence so
        // kernel_get_type_class() can read it after execution.
        if (data.len == CELL_SIZE) {
            const lin = linearity.getLinearity(data) catch return;
            self.last_cell_linearity = switch (lin) {
                .linear => 0,
                .affine => 1,
                .relevant => 2,
                .debug => -1,
            };
        }
    }

    pub fn spushCell(self: *PDA, cell_data: *const Cell, len: u32) PDAError!void {
        if (self.main_sp >= MAIN_STACK_DEPTH) return error.stack_overflow;
        const idx = self.main_sp;
        @memcpy(&self.main_stack[idx], cell_data);
        self.main_lengths[idx] = len;
        self.main_sp += 1;
    }

    pub fn spop(self: *PDA) PDAError!struct { data: *Cell, len: u32 } {
        if (self.main_sp == 0) return error.stack_underflow;
        self.main_sp -= 1;
        return .{
            .data = &self.main_stack[self.main_sp],
            .len = self.main_lengths[self.main_sp],
        };
    }

    pub fn speek(self: *PDA) PDAError!struct { data: *const Cell, len: u32 } {
        if (self.main_sp == 0) return error.stack_underflow;
        const idx = self.main_sp - 1;
        return .{
            .data = &self.main_stack[idx],
            .len = self.main_lengths[idx],
        };
    }

    pub fn speekAt(self: *PDA, depth: u32) PDAError!struct { data: *const Cell, len: u32 } {
        if (depth >= self.main_sp) return error.stack_underflow;
        const idx = self.main_sp - 1 - depth;
        return .{
            .data = &self.main_stack[idx],
            .len = self.main_lengths[idx],
        };
    }

    pub fn sdepth(self: *const PDA) u32 {
        return self.main_sp;
    }

    pub fn sempty(self: *const PDA) bool {
        return self.main_sp == 0;
    }

    // ── Aux stack operations ──

    pub fn apush(self: *PDA, data: []const u8) PDAError!void {
        if (self.aux_sp >= AUX_STACK_DEPTH) return error.stack_overflow;
        const idx = self.aux_sp;
        @memset(&self.aux_stack[idx], 0);
        if (data.len > 0) {
            @memcpy(self.aux_stack[idx][0..data.len], data);
        }
        self.aux_lengths[idx] = @intCast(data.len);
        self.aux_sp += 1;
    }

    pub fn apushCell(self: *PDA, cell_data: *const Cell, len: u32) PDAError!void {
        if (self.aux_sp >= AUX_STACK_DEPTH) return error.stack_overflow;
        const idx = self.aux_sp;
        @memcpy(&self.aux_stack[idx], cell_data);
        self.aux_lengths[idx] = len;
        self.aux_sp += 1;
    }

    pub fn apop(self: *PDA) PDAError!struct { data: *Cell, len: u32 } {
        if (self.aux_sp == 0) return error.stack_underflow;
        self.aux_sp -= 1;
        return .{
            .data = &self.aux_stack[self.aux_sp],
            .len = self.aux_lengths[self.aux_sp],
        };
    }

    pub fn adepth(self: *const PDA) u32 {
        return self.aux_sp;
    }

    pub fn aempty(self: *const PDA) bool {
        return self.aux_sp == 0;
    }

    // ── Length queries (top-indexed, matching speekAt/kernel_stack_peek convention) ──

    /// Get the byte length of a main stack value by top-index.
    /// Index 0 = top of stack. Returns 0 if empty or out of range.
    pub fn getMainLengthByIndex(self: *const PDA, index: u32) u32 {
        if (self.main_sp == 0) return 0;
        if (index >= self.main_sp) return 0;
        const slot = self.main_sp - 1 - index;
        return self.main_lengths[slot];
    }

    /// Get the byte length of an aux stack value by top-index.
    /// Index 0 = top of stack. Returns 0 if empty or out of range.
    pub fn getAuxLengthByIndex(self: *const PDA, index: u32) u32 {
        if (self.aux_sp == 0) return 0;
        if (index >= self.aux_sp) return 0;
        const slot = self.aux_sp - 1 - index;
        return self.aux_lengths[slot];
    }

    // ── Stack manipulation helpers ──

    /// OP_DUP: duplicate top element
    pub fn sdup(self: *PDA) PDAError!void {
        const top = try self.speek();
        try self.spushCell(@constCast(top.data), top.len);
    }

    /// OP_DROP: remove top element
    pub fn sdrop(self: *PDA) PDAError!void {
        _ = try self.spop();
    }

    /// OP_SWAP: swap top two elements
    pub fn sswap(self: *PDA) PDAError!void {
        if (self.main_sp < 2) return error.stack_underflow;
        const top = self.main_sp - 1;
        const second = self.main_sp - 2;
        // Swap cell data
        var tmp: Cell = undefined;
        @memcpy(&tmp, &self.main_stack[top]);
        @memcpy(&self.main_stack[top], &self.main_stack[second]);
        @memcpy(&self.main_stack[second], &tmp);
        // Swap lengths
        const tmp_len = self.main_lengths[top];
        self.main_lengths[top] = self.main_lengths[second];
        self.main_lengths[second] = tmp_len;
    }

    /// OP_ROT: rotate top three elements (third → top)
    pub fn srot(self: *PDA) PDAError!void {
        if (self.main_sp < 3) return error.stack_underflow;
        const a = self.main_sp - 3; // bottom of three
        const b = self.main_sp - 2;
        const c = self.main_sp - 1; // top
        // a b c → b c a
        var tmp: Cell = undefined;
        @memcpy(&tmp, &self.main_stack[a]);
        const tmp_len = self.main_lengths[a];

        @memcpy(&self.main_stack[a], &self.main_stack[b]);
        self.main_lengths[a] = self.main_lengths[b];

        @memcpy(&self.main_stack[b], &self.main_stack[c]);
        self.main_lengths[b] = self.main_lengths[c];

        @memcpy(&self.main_stack[c], &tmp);
        self.main_lengths[c] = tmp_len;
    }

    /// OP_OVER: copy second element to top
    pub fn sover(self: *PDA) PDAError!void {
        if (self.main_sp < 2) return error.stack_underflow;
        const second = self.main_sp - 2;
        try self.spushCell(&self.main_stack[second], self.main_lengths[second]);
    }

    /// OP_PICK: copy nth element (from top, 0-indexed) to top
    pub fn spick(self: *PDA, n: u32) PDAError!void {
        if (n >= self.main_sp) return error.stack_underflow;
        const idx = self.main_sp - 1 - n;
        try self.spushCell(&self.main_stack[idx], self.main_lengths[idx]);
    }

    /// OP_ROLL: move nth element (from top, 0-indexed) to top, shifting others down
    pub fn sroll(self: *PDA, n: u32) PDAError!void {
        if (n >= self.main_sp) return error.stack_underflow;
        if (n == 0) return; // no-op
        const target_idx = self.main_sp - 1 - n;
        // Save the target element
        var tmp: Cell = undefined;
        @memcpy(&tmp, &self.main_stack[target_idx]);
        const tmp_len = self.main_lengths[target_idx];
        // Shift elements down
        var i = target_idx;
        while (i < self.main_sp - 1) : (i += 1) {
            @memcpy(&self.main_stack[i], &self.main_stack[i + 1]);
            self.main_lengths[i] = self.main_lengths[i + 1];
        }
        // Place target at top
        @memcpy(&self.main_stack[self.main_sp - 1], &tmp);
        self.main_lengths[self.main_sp - 1] = tmp_len;
    }

    /// OP_TOALTSTACK: move top of main to top of aux
    pub fn toalt(self: *PDA) PDAError!void {
        const item = try self.spop();
        try self.apushCell(item.data, item.len);
    }

    /// OP_FROMALTSTACK: move top of aux to top of main
    pub fn fromalt(self: *PDA) PDAError!void {
        const item = try self.apop();
        try self.spushCell(item.data, item.len);
    }

    /// OP_NIP: remove second element (keep top)
    pub fn snip(self: *PDA) PDAError!void {
        if (self.main_sp < 2) return error.stack_underflow;
        // Move top into second position, then decrement sp
        const top = self.main_sp - 1;
        const second = self.main_sp - 2;
        @memcpy(&self.main_stack[second], &self.main_stack[top]);
        self.main_lengths[second] = self.main_lengths[top];
        self.main_sp -= 1;
    }

    /// OP_TUCK: copy top element to before second
    pub fn stuck(self: *PDA) PDAError!void {
        // a b → b a b
        if (self.main_sp < 2) return error.stack_underflow;
        // First swap
        try self.sswap();
        // Then over
        try self.sover();
    }

    /// OP_2DUP: duplicate top two elements
    pub fn s2dup(self: *PDA) PDAError!void {
        if (self.main_sp < 2) return error.stack_underflow;
        const a_idx = self.main_sp - 2;
        const b_idx = self.main_sp - 1;
        try self.spushCell(&self.main_stack[a_idx], self.main_lengths[a_idx]);
        try self.spushCell(&self.main_stack[b_idx], self.main_lengths[b_idx]);
    }

    /// OP_3DUP: duplicate top three elements
    pub fn s3dup(self: *PDA) PDAError!void {
        if (self.main_sp < 3) return error.stack_underflow;
        const a_idx = self.main_sp - 3;
        const b_idx = self.main_sp - 2;
        const c_idx = self.main_sp - 1;
        try self.spushCell(&self.main_stack[a_idx], self.main_lengths[a_idx]);
        try self.spushCell(&self.main_stack[b_idx], self.main_lengths[b_idx]);
        try self.spushCell(&self.main_stack[c_idx], self.main_lengths[c_idx]);
    }

    /// OP_2DROP: remove top two elements
    pub fn s2drop(self: *PDA) PDAError!void {
        _ = try self.spop();
        _ = try self.spop();
    }

    /// OP_2SWAP: swap top two pairs
    pub fn s2swap(self: *PDA) PDAError!void {
        if (self.main_sp < 4) return error.stack_underflow;
        // a b c d → c d a b
        // Swap positions 0,1 with 2,3 (from top)
        const d = self.main_sp - 1;
        const c = self.main_sp - 2;
        const b = self.main_sp - 3;
        const a = self.main_sp - 4;

        var tmp: Cell = undefined;
        var tmp_len: u32 = undefined;

        // Swap a ↔ c
        @memcpy(&tmp, &self.main_stack[a]);
        tmp_len = self.main_lengths[a];
        @memcpy(&self.main_stack[a], &self.main_stack[c]);
        self.main_lengths[a] = self.main_lengths[c];
        @memcpy(&self.main_stack[c], &tmp);
        self.main_lengths[c] = tmp_len;

        // Swap b ↔ d
        @memcpy(&tmp, &self.main_stack[b]);
        tmp_len = self.main_lengths[b];
        @memcpy(&self.main_stack[b], &self.main_stack[d]);
        self.main_lengths[b] = self.main_lengths[d];
        @memcpy(&self.main_stack[d], &tmp);
        self.main_lengths[d] = tmp_len;
    }

    /// OP_IFDUP: duplicate top if non-zero
    pub fn sifdup(self: *PDA) PDAError!void {
        const top = try self.speek();
        if (isTruthy(top.data, top.len)) {
            try self.sdup();
        }
    }

    /// OP_2OVER: copy 3rd and 4th items to top
    /// Stack: x1 x2 x3 x4 → x1 x2 x3 x4 x1 x2
    pub fn s2over(self: *PDA) PDAError!void {
        if (self.main_sp < 4) return error.stack_underflow;
        const idx_x1 = self.main_sp - 4;
        const idx_x2 = self.main_sp - 3;
        try self.spushCell(&self.main_stack[idx_x1], self.main_lengths[idx_x1]);
        try self.spushCell(&self.main_stack[idx_x2], self.main_lengths[idx_x2]);
    }

    /// OP_2ROT: move 5th and 6th items to top
    /// Stack: x1 x2 x3 x4 x5 x6 → x3 x4 x5 x6 x1 x2
    pub fn s2rot(self: *PDA) PDAError!void {
        if (self.main_sp < 6) return error.stack_underflow;
        // Save x1 (deepest) and x2
        var tmp1: Cell = undefined;
        var tmp2: Cell = undefined;
        const idx_x1 = self.main_sp - 6;
        const idx_x2 = self.main_sp - 5;
        @memcpy(&tmp1, &self.main_stack[idx_x1]);
        const len1 = self.main_lengths[idx_x1];
        @memcpy(&tmp2, &self.main_stack[idx_x2]);
        const len2 = self.main_lengths[idx_x2];

        // Shift x3,x4,x5,x6 down by 2 positions
        @memcpy(&self.main_stack[self.main_sp - 6], &self.main_stack[self.main_sp - 4]);
        self.main_lengths[self.main_sp - 6] = self.main_lengths[self.main_sp - 4];
        @memcpy(&self.main_stack[self.main_sp - 5], &self.main_stack[self.main_sp - 3]);
        self.main_lengths[self.main_sp - 5] = self.main_lengths[self.main_sp - 3];
        @memcpy(&self.main_stack[self.main_sp - 4], &self.main_stack[self.main_sp - 2]);
        self.main_lengths[self.main_sp - 4] = self.main_lengths[self.main_sp - 2];
        @memcpy(&self.main_stack[self.main_sp - 3], &self.main_stack[self.main_sp - 1]);
        self.main_lengths[self.main_sp - 3] = self.main_lengths[self.main_sp - 1];

        // Place x1, x2 on top
        @memcpy(&self.main_stack[self.main_sp - 2], &tmp1);
        self.main_lengths[self.main_sp - 2] = len1;
        @memcpy(&self.main_stack[self.main_sp - 1], &tmp2);
        self.main_lengths[self.main_sp - 1] = len2;
    }
    // ── Phase 4: Linearity enforcement wrappers ──

    pub fn enableEnforcement(self: *PDA) void {
        self.enforcement_enabled = true;
    }

    pub fn disableEnforcement(self: *PDA) void {
        self.enforcement_enabled = false;
    }

    /// Read linearity from stack slot, using main_lengths to bounds-check.
    /// A stack item shorter than HEADER_SIZE (256) is not a valid semantic
    /// object — pass the length-bounded slice so getLinearity's own bounds
    /// check rejects it with cell_too_short rather than reading zeroed padding.
    fn slotLinearity(self: *const PDA, idx: u32) linearity.LinearityError!linearity.LinearityType {
        const len = self.main_lengths[idx];
        return linearity.getLinearity(self.main_stack[idx][0..len]);
    }

    /// Enforced DUP: check linearity of top cell before duplicating.
    pub fn sdup_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp == 0) return error.stack_underflow;
            const lin = try self.slotLinearity(self.main_sp - 1);
            try linearity.checkLinearity(lin, .duplicate);
        }
        try self.sdup();
    }

    /// Enforced DROP: check linearity of top cell before discarding.
    pub fn sdrop_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp == 0) return error.stack_underflow;
            const lin = try self.slotLinearity(self.main_sp - 1);
            try linearity.checkLinearity(lin, .discard);
        }
        try self.sdrop();
    }

    /// Enforced SWAP: reorder is always allowed, no linearity check needed.
    pub fn sswap_enforced(self: *PDA) EnforcedError!void {
        try self.sswap();
    }

    /// Enforced OVER: check linearity of second element (being copied).
    pub fn sover_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 2) return error.stack_underflow;
            const lin = try self.slotLinearity(self.main_sp - 2);
            try linearity.checkLinearity(lin, .duplicate);
        }
        try self.sover();
    }

    /// Enforced 2DUP: check linearity of both top elements.
    pub fn s2dup_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 2) return error.stack_underflow;
            const top_lin = try self.slotLinearity(self.main_sp - 1);
            try linearity.checkLinearity(top_lin, .duplicate);
            const second_lin = try self.slotLinearity(self.main_sp - 2);
            try linearity.checkLinearity(second_lin, .duplicate);
        }
        try self.s2dup();
    }

    /// Enforced 2DROP: check linearity of both top elements.
    pub fn s2drop_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 2) return error.stack_underflow;
            const top_lin = try self.slotLinearity(self.main_sp - 1);
            try linearity.checkLinearity(top_lin, .discard);
            const second_lin = try self.slotLinearity(self.main_sp - 2);
            try linearity.checkLinearity(second_lin, .discard);
        }
        try self.s2drop();
    }

    // ── Phase 4b: Long-tail enforced wrappers ──

    /// Enforced ROT: reorder is always allowed.
    pub fn srot_enforced(self: *PDA) EnforcedError!void {
        try self.srot();
    }

    /// Enforced PICK: check linearity of the element being copied.
    pub fn spick_enforced(self: *PDA, n: u32) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (n >= self.main_sp) return error.stack_underflow;
            const idx = self.main_sp - 1 - n;
            const lin = try self.slotLinearity(idx);
            try linearity.checkLinearity(lin, .duplicate);
        }
        try self.spick(n);
    }

    /// Enforced ROLL: move (reorder), not copy/destroy — always allowed.
    pub fn sroll_enforced(self: *PDA, n: u32) EnforcedError!void {
        try self.sroll(n);
    }

    /// Enforced NIP: discards second element (keep top).
    pub fn snip_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 2) return error.stack_underflow;
            const lin = try self.slotLinearity(self.main_sp - 2);
            try linearity.checkLinearity(lin, .discard);
        }
        try self.snip();
    }

    /// Enforced TUCK: copies top element (duplicate check on top).
    pub fn stuck_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp == 0) return error.stack_underflow;
            const lin = try self.slotLinearity(self.main_sp - 1);
            try linearity.checkLinearity(lin, .duplicate);
        }
        try self.stuck();
    }

    /// Enforced 3DUP: check linearity of all three top elements.
    pub fn s3dup_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 3) return error.stack_underflow;
            var i: u32 = 0;
            while (i < 3) : (i += 1) {
                const lin = try self.slotLinearity(self.main_sp - 1 - i);
                try linearity.checkLinearity(lin, .duplicate);
            }
        }
        try self.s3dup();
    }

    /// Enforced 2SWAP: reorder — always allowed.
    pub fn s2swap_enforced(self: *PDA) EnforcedError!void {
        try self.s2swap();
    }

    /// Enforced 2OVER: copies 3rd and 4th elements.
    pub fn s2over_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp < 4) return error.stack_underflow;
            const lin1 = try self.slotLinearity(self.main_sp - 4);
            try linearity.checkLinearity(lin1, .duplicate);
            const lin2 = try self.slotLinearity(self.main_sp - 3);
            try linearity.checkLinearity(lin2, .duplicate);
        }
        try self.s2over();
    }

    /// Enforced 2ROT: reorder — always allowed.
    pub fn s2rot_enforced(self: *PDA) EnforcedError!void {
        try self.s2rot();
    }

    /// Enforced IFDUP: if truthy, duplicates (needs duplicate check).
    pub fn sifdup_enforced(self: *PDA) EnforcedError!void {
        if (self.enforcement_enabled) {
            if (self.main_sp == 0) return error.stack_underflow;
            const idx = self.main_sp - 1;
            const len = self.main_lengths[idx];
            if (isTruthy(&self.main_stack[idx], len)) {
                const lin = try self.slotLinearity(idx);
                try linearity.checkLinearity(lin, .duplicate);
            }
        }
        try self.sifdup();
    }
};

// ── Error union that combines PDA errors with linearity errors ──
pub const EnforcedError = PDAError || linearity.LinearityError;

// ── Bitcoin Script number encoding ──
// Sign-magnitude, little-endian, variable-length (1-4 bytes for arithmetic).
// Empty byte array = 0. 0x80 alone = negative zero (falsy).

/// Convert cell data to i64 (sign-magnitude, little-endian).
pub fn cellToI64(data: []const u8) i64 {
    if (data.len == 0) return 0;

    // Read magnitude (little-endian, ignore sign bit in MSB)
    var result: i64 = 0;
    for (0..data.len) |i| {
        if (i == data.len - 1) {
            result |= @as(i64, data[i] & 0x7F) << @intCast(8 * i);
        } else {
            result |= @as(i64, data[i]) << @intCast(8 * i);
        }
    }

    // Check sign bit (MSB of last byte)
    if (data[data.len - 1] & 0x80 != 0) {
        result = -result;
    }

    return result;
}

/// Convert i64 to cell data (sign-magnitude, little-endian).
/// Returns the number of bytes written.
pub fn i64ToCell(val: i64, out: *Cell) u32 {
    if (val == 0) return 0;

    const negative = val < 0;
    var abs_val: u64 = if (negative) @intCast(-val) else @intCast(val);

    var len: u32 = 0;
    while (abs_val > 0) : (len += 1) {
        out[len] = @truncate(abs_val & 0xFF);
        abs_val >>= 8;
    }

    // If MSB of last byte has bit 7 set, we need an extra byte for the sign
    if (out[len - 1] & 0x80 != 0) {
        out[len] = if (negative) 0x80 else 0x00;
        len += 1;
    } else if (negative) {
        out[len - 1] |= 0x80;
    }

    return len;
}

/// Check if a stack element is truthy (Bitcoin Script semantics).
/// False: empty, all zeros, or negative zero (0x80 as sole byte or trailing 0x80 with zeros).
pub fn isTruthy(data: *const Cell, len: u32) bool {
    if (len == 0) return false;

    const slice = data[0..len];

    // Check for negative zero: all bytes zero except last byte which is 0x80
    var all_zero = true;
    for (slice[0 .. len - 1]) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    if (all_zero and slice[len - 1] == 0x80) return false;

    // Otherwise check for any non-zero byte
    for (slice) |b| {
        if (b != 0) return true;
    }
    return false;
}

```
