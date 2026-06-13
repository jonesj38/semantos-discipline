---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/cellsh.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.982370+00:00
---

# core/cell-engine/src/cellsh.zig

```zig
// cellsh — Semantos Plane native shell
// "Everything is a cell." The shell is a first-class citizen of the Plane.
//
// This is a native Zig REPL that operates directly on the 2-PDA kernel
// with no WASM boundary. Every object the shell touches — stack values,
// command history, shell state — is a 1024-byte cell.
//
// Build: zig build cellsh (see build.zig additions)
// Usage: ./cellsh              (interactive REPL)
//        ./cellsh push foo.bin (single command)

const std = @import("std");
const cell_mod = @import("cell");
const constants = @import("constants");
const errors = @import("errors");
const linearity_mod = @import("linearity");
const pda_mod = @import("pda");
const executor_mod = @import("executor");
const allocator_mod = @import("allocator");
const sighash_mod = @import("sighash");
const octave_mod = @import("octave");
const pointer_mod = @import("pointer");
const multicell_mod = @import("multicell");

// ── Shell state ──
// The shell's own state is a cell on the aux stack. History snapshots are
// cells that can be pushed, exported, and introspected like any other object.

const PROMPT = "cellsh> ";
const VERSION_STR = "cellsh 0.1.0 — Semantos Plane native shell";
const MAX_INPUT = 4096;
const MAX_HISTORY = 256;

/// Shell instance — owns the PDA and all execution state.
pub const Shell = struct {
    pda: pda_mod.PDA,
    arena_buf: [65536]u8,
    arena: allocator_mod.ScriptArena,
    ctx: executor_mod.ExecutionContext,
    tx_ctx: sighash_mod.TxContext,

    // History: each entry is a cell (command text in payload)
    history: [MAX_HISTORY][constants.CELL_SIZE]u8,
    history_count: u32,

    // File I/O allocator
    gpa: std.heap.GeneralPurposeAllocator(.{}),

    running: bool,

    pub fn init() Shell {
        var self: Shell = undefined;
        self.pda.initInPlace(executor_mod.DEFAULT_MAX_OPS);
        self.arena = allocator_mod.ScriptArena.init(&self.arena_buf);
        self.ctx = executor_mod.ExecutionContext.init(&self.pda, &self.arena);
        self.tx_ctx = sighash_mod.TxContext.init();
        self.history_count = 0;
        self.running = true;
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        return self;
    }

    pub fn deinit(self: *Shell) void {
        _ = self.gpa.deinit();
    }

    /// Record a command into history as a cell.
    fn recordHistory(self: *Shell, line: []const u8) void {
        if (self.history_count >= MAX_HISTORY) {
            // Shift history down (drop oldest)
            for (0..MAX_HISTORY - 1) |i| {
                @memcpy(&self.history[i], &self.history[i + 1]);
            }
            self.history_count = MAX_HISTORY - 1;
        }
        // Pack the command as a cell: DEBUG linearity, payload = command text
        var hdr = cell_mod.defaultHeader();
        hdr.linearity = constants.LINEARITY_DEBUG;
        const payload_len = @min(line.len, constants.PAYLOAD_SIZE);
        hdr.total_size = @intCast(payload_len);
        const out: *[constants.CELL_SIZE]u8 = &self.history[self.history_count];
        cell_mod.packCell(&hdr, line[0..payload_len], out) catch return;
        self.history_count += 1;
    }

    /// Dispatch a parsed command.
    pub fn dispatch(self: *Shell, line: []const u8, writer: anytype) !void {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) return;

        self.recordHistory(trimmed);

        // Tokenize
        var tokens: [64][]const u8 = undefined;
        var token_count: usize = 0;
        var iter = std.mem.tokenizeAny(u8, trimmed, &std.ascii.whitespace);
        while (iter.next()) |tok| {
            if (token_count >= 64) break;
            tokens[token_count] = tok;
            token_count += 1;
        }
        if (token_count == 0) return;

        const cmd = tokens[0];
        const args = tokens[1..token_count];

        if (std.mem.eql(u8, cmd, "push")) {
            try self.cmdPush(args, writer);
        } else if (std.mem.eql(u8, cmd, "push-cell")) {
            try self.cmdPushCell(args, writer);
        } else if (std.mem.eql(u8, cmd, "pop")) {
            try self.cmdPop(writer);
        } else if (std.mem.eql(u8, cmd, "dup")) {
            try self.cmdDup(writer);
        } else if (std.mem.eql(u8, cmd, "drop")) {
            try self.cmdDrop(writer);
        } else if (std.mem.eql(u8, cmd, "swap")) {
            try self.cmdSwap(writer);
        } else if (std.mem.eql(u8, cmd, "cat")) {
            try self.cmdCat(args, writer);
        } else if (std.mem.eql(u8, cmd, "ls")) {
            try self.cmdLs(args, writer);
        } else if (std.mem.eql(u8, cmd, "deref")) {
            try self.cmdDeref(writer);
        } else if (std.mem.eql(u8, cmd, "check-linear")) {
            try self.cmdCheckLinear(writer);
        } else if (std.mem.eql(u8, cmd, "check-identity")) {
            try self.cmdCheckIdentity(args, writer);
        } else if (std.mem.eql(u8, cmd, "check-typehash")) {
            try self.cmdCheckTypeHash(args, writer);
        } else if (std.mem.eql(u8, cmd, "step")) {
            try self.cmdStep(writer);
        } else if (std.mem.eql(u8, cmd, "execute")) {
            try self.cmdExecute(writer);
        } else if (std.mem.eql(u8, cmd, "load-script")) {
            try self.cmdLoadScript(args, writer);
        } else if (std.mem.eql(u8, cmd, "load-unlock")) {
            try self.cmdLoadUnlock(args, writer);
        } else if (std.mem.eql(u8, cmd, "history")) {
            try self.cmdHistory(writer);
        } else if (std.mem.eql(u8, cmd, "export-cell")) {
            try self.cmdExportCell(args, writer);
        } else if (std.mem.eql(u8, cmd, "import-cell")) {
            try self.cmdImportCell(args, writer);
        } else if (std.mem.eql(u8, cmd, "reset")) {
            try self.cmdReset(writer);
        } else if (std.mem.eql(u8, cmd, "depth")) {
            try self.cmdDepth(writer);
        } else if (std.mem.eql(u8, cmd, "octave-info")) {
            try self.cmdOctaveInfo(args, writer);
        } else if (std.mem.eql(u8, cmd, "enforcement")) {
            try self.cmdEnforcement(args, writer);
        } else if (std.mem.eql(u8, cmd, "help")) {
            try self.cmdHelp(writer);
        } else if (std.mem.eql(u8, cmd, "version")) {
            try writer.print("{s}\n", .{VERSION_STR});
        } else if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit")) {
            self.running = false;
        } else {
            try writer.print("unknown command: {s}\n", .{cmd});
            try writer.print("type 'help' for available commands\n", .{});
        }
    }

    // ──────────────────────────────────────────────
    // Stack commands
    // ──────────────────────────────────────────────

    /// push <hex|string> — push raw bytes onto main stack
    fn cmdPush(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            // Push empty (OP_0 equivalent)
            self.pda.spush(&[_]u8{}) catch |e| {
                try writer.print("error: {s}\n", .{@errorName(e)});
                return;
            };
            try writer.print("pushed empty cell\n", .{});
            return;
        }

        const arg = args[0];

        // If it starts with 0x, parse as hex
        if (arg.len >= 2 and arg[0] == '0' and arg[1] == 'x') {
            const hex = arg[2..];
            if (hex.len % 2 != 0 or hex.len > constants.CELL_SIZE * 2) {
                try writer.print("error: invalid hex (odd length or too large)\n", .{});
                return;
            }
            var buf: [constants.CELL_SIZE]u8 = undefined;
            const byte_len = hex.len / 2;
            for (0..byte_len) |i| {
                buf[i] = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch {
                    try writer.print("error: invalid hex at position {d}\n", .{i * 2});
                    return;
                };
            }
            self.pda.spush(buf[0..byte_len]) catch |e| {
                try writer.print("error: {s}\n", .{@errorName(e)});
                return;
            };
            try writer.print("pushed {d} bytes\n", .{byte_len});
        } else {
            // Push as raw string bytes
            self.pda.spush(arg) catch |e| {
                try writer.print("error: {s}\n", .{@errorName(e)});
                return;
            };
            try writer.print("pushed {d} bytes\n", .{arg.len});
        }
    }

    /// push-cell <file> — load a 1024-byte cell from disk and push it
    fn cmdPushCell(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: push-cell <file.bin>\n", .{});
            return;
        }
        const ally = self.gpa.allocator();
        const data = std.fs.cwd().readFileAlloc(ally, args[0], constants.CELL_SIZE + 1) catch |e| {
            try writer.print("error reading file: {s}\n", .{@errorName(e)});
            return;
        };
        defer ally.free(data);

        if (data.len != constants.CELL_SIZE) {
            try writer.print("error: file is {d} bytes, expected {d}\n", .{ data.len, constants.CELL_SIZE });
            return;
        }

        self.pda.spush(data) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };

        // Validate and report
        if (cell_mod.validateMagic(@ptrCast(data.ptr))) {
            try writer.print("pushed semantic cell (valid magic)\n", .{});
        } else if (pointer_mod.isPointerCell(@ptrCast(data.ptr))) {
            try writer.print("pushed pointer cell (type 0x06)\n", .{});
        } else {
            try writer.print("pushed raw 1024-byte cell\n", .{});
        }
    }

    /// pop — remove and discard top of stack
    fn cmdPop(self: *Shell, writer: anytype) !void {
        _ = self.pda.spop() catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("popped\n", .{});
    }

    /// dup — duplicate top of stack (linearity-enforced if enabled)
    fn cmdDup(self: *Shell, writer: anytype) !void {
        self.pda.sdup_enforced() catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("duplicated\n", .{});
    }

    /// drop — discard top of stack (linearity-enforced if enabled)
    fn cmdDrop(self: *Shell, writer: anytype) !void {
        self.pda.sdrop_enforced() catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("dropped\n", .{});
    }

    /// swap — swap top two elements
    fn cmdSwap(self: *Shell, writer: anytype) !void {
        self.pda.sswap() catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("swapped\n", .{});
    }

    // ──────────────────────────────────────────────
    // Inspection commands
    // ──────────────────────────────────────────────

    /// cat [@<index>] — pretty-print cell header at stack position (default: top)
    fn cmdCat(self: *Shell, args: []const []const u8, writer: anytype) !void {
        var index: u32 = 0; // top of stack
        if (args.len > 0 and args[0].len > 1 and args[0][0] == '@') {
            index = std.fmt.parseInt(u32, args[0][1..], 10) catch {
                try writer.print("error: invalid index\n", .{});
                return;
            };
        }

        const result = self.pda.speekAt(index) catch {
            try writer.print("error: stack underflow (depth={d}, index={d})\n", .{ self.pda.sdepth(), index });
            return;
        };

        const data = result.data;
        const len = result.len;

        try writer.print("── cell @{d} ({d} bytes) ──\n", .{ index, len });

        // Try as semantic cell (has magic bytes)
        if (len >= constants.HEADER_SIZE and cell_mod.validateMagic(data)) {
            try self.printSemanticHeader(data, writer);
            return;
        }

        // Try as pointer cell
        if (len >= constants.CELL_SIZE and pointer_mod.isPointerCell(data)) {
            try self.printPointerInfo(data, writer);
            return;
        }

        // Raw data: show hex dump (first 64 bytes)
        try writer.print("  type: raw data\n", .{});
        const show_len = @min(len, 64);
        try writer.print("  data: ", .{});
        for (0..show_len) |i| {
            try writer.print("{x:0>2}", .{data[i]});
            if (i % 16 == 15) {
                try writer.print("\n        ", .{});
            }
        }
        if (show_len < len) {
            try writer.print("... ({d} more bytes)", .{len - show_len});
        }
        try writer.print("\n", .{});

        // If it looks like ASCII, show text
        var is_ascii = true;
        for (data[0..show_len]) |b| {
            if (b != 0 and (b < 0x20 or b > 0x7E)) {
                is_ascii = false;
                break;
            }
        }
        if (is_ascii and show_len > 0) {
            // Find actual text length (trim trailing zeros)
            var text_len: usize = len;
            while (text_len > 0 and data[text_len - 1] == 0) text_len -= 1;
            if (text_len > 0) {
                try writer.print("  text: \"{s}\"\n", .{data[0..text_len]});
            }
        }
    }

    fn printSemanticHeader(self: *Shell, data: *const [constants.CELL_SIZE]u8, writer: anytype) !void {
        _ = self;
        const lin = linearity_mod.getLinearity(data) catch |e| {
            try writer.print("  linearity: error ({s})\n", .{@errorName(e)});
            return;
        };
        const flags = linearity_mod.getDomainFlag(data) catch 0;
        const type_hash = linearity_mod.getTypeHash(data) catch [_]u8{0} ** 32;
        const owner_id = linearity_mod.getOwnerId(data) catch [_]u8{0} ** 16;

        const version = std.mem.readInt(u32, data[constants.HEADER_OFFSET_VERSION..][0..4], .little);
        const ref_count = std.mem.readInt(u16, data[constants.HEADER_OFFSET_REF_COUNT..][0..2], .little);
        const timestamp = std.mem.readInt(u64, data[constants.HEADER_OFFSET_TIMESTAMP..][0..8], .little);
        const cell_count = std.mem.readInt(u32, data[constants.HEADER_OFFSET_CELL_COUNT..][0..4], .little);
        const total_size = std.mem.readInt(u32, data[constants.HEADER_OFFSET_PAYLOAD_TOTAL..][0..4], .little);

        try writer.print("  type: semantic cell\n", .{});
        try writer.print("  linearity: {s}\n", .{@tagName(lin)});
        try writer.print("  version: {d}\n", .{version});
        try writer.print("  domain flag: 0x{x:0>8} ({s})\n", .{ flags, @tagName(linearity_mod.classifyFlag(flags)) });
        try writer.print("  ref count: {d}\n", .{ref_count});

        try writer.print("  type hash: ", .{});
        for (type_hash[0..8]) |b| try writer.print("{x:0>2}", .{b});
        try writer.print("...\n", .{});

        try writer.print("  owner id:  ", .{});
        for (owner_id[0..8]) |b| try writer.print("{x:0>2}", .{b});
        try writer.print("...\n", .{});

        try writer.print("  timestamp: {d}\n", .{timestamp});
        try writer.print("  cells: {d}, payload: {d} bytes\n", .{ cell_count, total_size });

        // Show payload preview
        const payload_start = constants.HEADER_SIZE;
        const show_len = @min(total_size, 48);
        if (show_len > 0) {
            try writer.print("  payload: ", .{});
            for (0..show_len) |i| {
                try writer.print("{x:0>2}", .{data[payload_start + i]});
            }
            if (show_len < total_size) {
                try writer.print("...", .{});
            }
            try writer.print("\n", .{});
        }
    }

    fn printPointerInfo(self: *Shell, data: *const [constants.CELL_SIZE]u8, writer: anytype) !void {
        _ = self;
        const payload = pointer_mod.unpackPointerCell(data) catch |e| {
            try writer.print("  error unpacking pointer: {s}\n", .{@errorName(e)});
            return;
        };

        const oct: octave_mod.Octave = @enumFromInt(payload.octave);
        try writer.print("  type: pointer cell\n", .{});
        try writer.print("  target: octave {d} ({s}), slot {d}, offset {d}\n", .{
            payload.octave, @tagName(oct), payload.slot, payload.offset,
        });
        try writer.print("  content hash: ", .{});
        for (payload.content_hash[0..8]) |b| try writer.print("{x:0>2}", .{b});
        try writer.print("...\n", .{});
        try writer.print("  type hash:    ", .{});
        for (payload.type_hash[0..8]) |b| try writer.print("{x:0>2}", .{b});
        try writer.print("...\n", .{});
        try writer.print("  total size: {d} bytes\n", .{payload.total_size});
        try writer.print("  flags: 0x{x:0>2}", .{payload.flags});
        if (payload.flags & pointer_mod.PointerFlags.IMMUTABLE != 0) try writer.print(" IMMUTABLE", .{});
        if (payload.flags & pointer_mod.PointerFlags.ENCRYPTED != 0) try writer.print(" ENCRYPTED", .{});
        if (payload.flags & pointer_mod.PointerFlags.COMPRESSED != 0) try writer.print(" COMPRESSED", .{});
        try writer.print("\n", .{});
        try writer.print("  fragments: {d}\n", .{payload.fragment_count});

        const cell_size = octave_mod.cellSizeForOctave(oct);
        const cost = octave_mod.costSatsPerCell(oct);
        try writer.print("  cell size at octave: {d} bytes, cost: {d} sats\n", .{ cell_size, cost });
    }

    /// ls [main|aux] — list stack contents
    fn cmdLs(self: *Shell, args: []const []const u8, writer: anytype) !void {
        const show_aux = args.len > 0 and std.mem.eql(u8, args[0], "aux");

        if (show_aux) {
            const depth = self.pda.adepth();
            try writer.print("aux stack ({d} cells):\n", .{depth});
            for (0..depth) |i| {
                const idx: u32 = @intCast(i);
                const slot = depth - 1 - idx;
                const len = self.pda.getAuxLengthByIndex(idx);
                try writer.print("  [{d}] {d} bytes", .{ slot, len });
                try self.printCellSummary(&self.pda.aux_stack[slot], len, writer);
                try writer.print("\n", .{});
            }
        } else {
            const depth = self.pda.sdepth();
            try writer.print("main stack ({d} cells):\n", .{depth});
            for (0..depth) |i| {
                const idx: u32 = @intCast(i);
                const result = self.pda.speekAt(idx) catch break;
                const label = if (idx == 0) " ← top" else "";
                try writer.print("  @{d} {d} bytes", .{ idx, result.len });
                try self.printCellSummary(result.data, result.len, writer);
                try writer.print("{s}\n", .{label});
            }
        }
    }

    fn printCellSummary(self: *Shell, data: *const [constants.CELL_SIZE]u8, len: u32, writer: anytype) !void {
        _ = self;
        if (len >= constants.HEADER_SIZE and cell_mod.validateMagic(data)) {
            const lin = linearity_mod.getLinearity(data) catch {
                try writer.print(" [semantic?]", .{});
                return;
            };
            try writer.print(" [semantic {s}]", .{@tagName(lin)});
        } else if (len >= constants.CELL_SIZE and pointer_mod.isPointerCell(data)) {
            try writer.print(" [pointer]", .{});
        } else if (len > 0) {
            // Show first few bytes
            const show = @min(len, 8);
            try writer.print(" [", .{});
            for (0..show) |i| {
                try writer.print("{x:0>2}", .{data[i]});
            }
            if (show < len) try writer.print("..", .{});
            try writer.print("]", .{});
        } else {
            try writer.print(" [empty]", .{});
        }
    }

    /// depth — show stack depths
    fn cmdDepth(self: *Shell, writer: anytype) !void {
        try writer.print("main: {d}, aux: {d}\n", .{ self.pda.sdepth(), self.pda.adepth() });
    }

    // ──────────────────────────────────────────────
    // Verification commands
    // ──────────────────────────────────────────────

    /// check-linear — check linearity of top cell
    fn cmdCheckLinear(self: *Shell, writer: anytype) !void {
        const result = self.pda.speek() catch {
            try writer.print("error: stack empty\n", .{});
            return;
        };
        if (result.len < constants.HEADER_SIZE) {
            try writer.print("not a semantic cell ({d} bytes < {d} header)\n", .{ result.len, constants.HEADER_SIZE });
            return;
        }
        const lin = linearity_mod.getLinearity(result.data) catch |e| {
            try writer.print("linearity error: {s}\n", .{@errorName(e)});
            return;
        };
        const flag = linearity_mod.getDomainFlag(result.data) catch 0;
        const tier = linearity_mod.classifyFlag(flag);
        try writer.print("linearity: {s}\n", .{@tagName(lin)});
        try writer.print("domain flag: 0x{x:0>8} ({s})\n", .{ flag, @tagName(tier) });

        // Report what operations are allowed
        try writer.print("  DUP:  {s}\n", .{if (linearityAllows(lin, .duplicate)) "allowed" else "BLOCKED"});
        try writer.print("  DROP: {s}\n", .{if (linearityAllows(lin, .discard)) "allowed" else "BLOCKED"});
        try writer.print("  SWAP: allowed\n", .{});
    }

    fn linearityAllows(lin: linearity_mod.LinearityType, op: linearity_mod.LinearityOperation) bool {
        linearity_mod.checkLinearity(lin, op) catch return false;
        return true;
    }

    /// check-identity <hex-owner-id> — compare owner ID of top cell
    fn cmdCheckIdentity(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: check-identity <hex-owner-id-16-bytes>\n", .{});
            return;
        }
        const result = self.pda.speek() catch {
            try writer.print("error: stack empty\n", .{});
            return;
        };
        const cell_owner = linearity_mod.getOwnerId(result.data) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };

        // Parse expected owner ID from hex
        const hex = args[0];
        if (hex.len != 32) {
            try writer.print("error: owner ID must be 32 hex chars (16 bytes)\n", .{});
            return;
        }
        var expected: [16]u8 = undefined;
        for (0..16) |i| {
            expected[i] = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch {
                try writer.print("error: invalid hex at position {d}\n", .{i * 2});
                return;
            };
        }

        if (std.mem.eql(u8, &cell_owner, &expected)) {
            try writer.print("MATCH — owner identity verified\n", .{});
        } else {
            try writer.print("MISMATCH\n", .{});
            try writer.print("  cell:     ", .{});
            for (cell_owner) |b| try writer.print("{x:0>2}", .{b});
            try writer.print("\n  expected: ", .{});
            for (expected) |b| try writer.print("{x:0>2}", .{b});
            try writer.print("\n", .{});
        }
    }

    /// check-typehash <hex-hash> — compare type hash of top cell
    fn cmdCheckTypeHash(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: check-typehash <hex-hash-32-bytes>\n", .{});
            return;
        }
        const result = self.pda.speek() catch {
            try writer.print("error: stack empty\n", .{});
            return;
        };
        const cell_hash = linearity_mod.getTypeHash(result.data) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };

        const hex = args[0];
        if (hex.len != 64) {
            try writer.print("error: type hash must be 64 hex chars (32 bytes)\n", .{});
            return;
        }
        var expected: [32]u8 = undefined;
        for (0..32) |i| {
            expected[i] = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch {
                try writer.print("error: invalid hex at position {d}\n", .{i * 2});
                return;
            };
        }

        if (std.mem.eql(u8, &cell_hash, &expected)) {
            try writer.print("MATCH — type hash verified\n", .{});
        } else {
            try writer.print("MISMATCH\n", .{});
            try writer.print("  cell:     ", .{});
            for (cell_hash) |b| try writer.print("{x:0>2}", .{b});
            try writer.print("\n  expected: ", .{});
            for (expected) |b| try writer.print("{x:0>2}", .{b});
            try writer.print("\n", .{});
        }
    }

    /// deref — dereference top cell if it's a pointer
    fn cmdDeref(self: *Shell, writer: anytype) !void {
        const result = self.pda.speek() catch {
            try writer.print("error: stack empty\n", .{});
            return;
        };
        if (!pointer_mod.isPointerCell(result.data)) {
            try writer.print("error: top cell is not a pointer (type byte: 0x{x:0>2})\n", .{result.data[0]});
            return;
        }
        const addr = pointer_mod.getOctaveAddress(result.data) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("pointer target: octave {s}, slot {d}, offset {d}\n", .{
            @tagName(addr.octave), addr.slot, addr.offset,
        });
        try writer.print("deref requires host_fetch_cell (not available in standalone shell)\n", .{});
        try writer.print("when connected to a node, OP_DEREF_POINTER (0xC8) resolves this\n", .{});
    }

    // ──────────────────────────────────────────────
    // Execution commands
    // ──────────────────────────────────────────────

    /// load-script <hex|file> — load a locking script
    fn cmdLoadScript(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: load-script <hex-bytes | @file>\n", .{});
            return;
        }
        const script = try self.resolveScriptArg(args[0], writer) orelse return;
        defer if (args[0][0] == '@') self.gpa.allocator().free(script);

        self.ctx.loadScript(script) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("loaded {d}-byte locking script\n", .{script.len});
    }

    /// load-unlock <hex|file> — load an unlock script
    fn cmdLoadUnlock(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: load-unlock <hex-bytes | @file>\n", .{});
            return;
        }
        const script = try self.resolveScriptArg(args[0], writer) orelse return;
        defer if (args[0][0] == '@') self.gpa.allocator().free(script);

        self.ctx.loadUnlock(script) catch |e| {
            try writer.print("error: {s}\n", .{@errorName(e)});
            return;
        };
        try writer.print("loaded {d}-byte unlock script\n", .{script.len});
    }

    fn resolveScriptArg(self: *Shell, arg: []const u8, writer: anytype) !?[]const u8 {
        if (arg[0] == '@') {
            // Load from file
            const ally = self.gpa.allocator();
            const data = std.fs.cwd().readFileAlloc(ally, arg[1..], executor_mod.MAX_SCRIPT_SIZE) catch |e| {
                try writer.print("error reading file: {s}\n", .{@errorName(e)});
                return null;
            };
            return data;
        }

        // Parse hex inline
        if (arg.len % 2 != 0) {
            try writer.print("error: hex must be even length\n", .{});
            return null;
        }
        const byte_len = arg.len / 2;
        if (byte_len > executor_mod.MAX_SCRIPT_SIZE) {
            try writer.print("error: script too large\n", .{});
            return null;
        }
        // Use the arena for temp storage
        self.arena.reset();
        const buf = self.arena.alloc(byte_len) orelse {
            try writer.print("error: arena full\n", .{});
            return null;
        };
        for (0..byte_len) |i| {
            buf[i] = std.fmt.parseInt(u8, arg[i * 2 ..][0..2], 16) catch {
                try writer.print("error: invalid hex at position {d}\n", .{i * 2});
                return null;
            };
        }
        return buf;
    }

    /// step — execute one opcode
    fn cmdStep(self: *Shell, writer: anytype) !void {
        const result = executor_mod.step(&self.ctx) catch |e| {
            try writer.print("step error: {s}\n", .{@errorName(e)});
            return;
        };
        const phase_name = @tagName(self.ctx.current_phase);
        switch (result) {
            .continue_execution => {
                const pc = self.ctx.pc;
                const script = self.ctx.currentScript();
                if (pc < self.ctx.currentScriptLen()) {
                    try writer.print("[{s} pc={d}] next opcode: 0x{x:0>2}\n", .{
                        phase_name, pc, script[pc],
                    });
                } else {
                    try writer.print("[{s} pc={d}] end of script\n", .{ phase_name, pc });
                }
                try writer.print("  stack depth: {d}\n", .{self.pda.sdepth()});
            },
            .done_true => try writer.print("execution complete: TRUE (stack depth: {d})\n", .{self.pda.sdepth()}),
            .done_false => try writer.print("execution complete: FALSE (stack depth: {d})\n", .{self.pda.sdepth()}),
            .done_error => try writer.print("execution error (code: {d})\n", .{self.pda.error_code}),
        }
    }

    /// execute — run loaded scripts to completion
    fn cmdExecute(self: *Shell, writer: anytype) !void {
        self.ctx.pc = 0;
        self.ctx.current_phase = .unlock;
        self.ctx.condition_depth = 0;
        self.ctx.executing = true;
        self.pda.opcount = 0;

        const result = executor_mod.execute(&self.ctx) catch |e| {
            try writer.print("execution error: {s}\n", .{@errorName(e)});
            try writer.print("  opcount: {d}, pc: {d}\n", .{ self.pda.opcount, self.ctx.pc });
            return;
        };

        if (result) {
            try writer.print("TRUE — script succeeded\n", .{});
        } else {
            try writer.print("FALSE — script failed\n", .{});
        }
        try writer.print("  opcount: {d}, stack depth: {d}\n", .{ self.pda.opcount, self.pda.sdepth() });
    }

    // ──────────────────────────────────────────────
    // History & state
    // ──────────────────────────────────────────────

    /// history — show command history (each entry is a cell)
    fn cmdHistory(self: *Shell, writer: anytype) !void {
        if (self.history_count == 0) {
            try writer.print("(no history)\n", .{});
            return;
        }
        try writer.print("history ({d} cells):\n", .{self.history_count});
        for (0..self.history_count) |i| {
            const h_cell = &self.history[i];
            // Extract payload text from cell
            const result = cell_mod.unpackCell(h_cell) catch {
                try writer.print("  [{d}] (invalid cell)\n", .{i});
                continue;
            };
            var text_len: usize = result.payload_len;
            while (text_len > 0 and result.payload[text_len - 1] == 0) text_len -= 1;
            if (text_len > 0) {
                try writer.print("  [{d}] {s}\n", .{ i, result.payload[0..text_len] });
            }
        }
    }

    /// reset — reset PDA and execution state
    fn cmdReset(self: *Shell, writer: anytype) !void {
        self.pda.reset();
        self.ctx.reset();
        try writer.print("kernel reset\n", .{});
    }

    /// enforcement [on|off] — toggle linearity enforcement
    fn cmdEnforcement(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("enforcement: {s}\n", .{if (self.pda.enforcement_enabled) "on" else "off"});
            return;
        }
        if (std.mem.eql(u8, args[0], "on")) {
            self.pda.enableEnforcement();
            try writer.print("linearity enforcement enabled\n", .{});
        } else if (std.mem.eql(u8, args[0], "off")) {
            self.pda.disableEnforcement();
            try writer.print("linearity enforcement disabled\n", .{});
        } else {
            try writer.print("usage: enforcement [on|off]\n", .{});
        }
    }

    // ──────────────────────────────────────────────
    // I/O commands
    // ──────────────────────────────────────────────

    /// export-cell <file> [@<index>] — write a stack cell to disk
    fn cmdExportCell(self: *Shell, args: []const []const u8, writer: anytype) !void {
        if (args.len == 0) {
            try writer.print("usage: export-cell <file.bin> [@index]\n", .{});
            return;
        }

        var index: u32 = 0;
        if (args.len > 1 and args[1].len > 1 and args[1][0] == '@') {
            index = std.fmt.parseInt(u32, args[1][1..], 10) catch {
                try writer.print("error: invalid index\n", .{});
                return;
            };
        }

        const result = self.pda.speekAt(index) catch {
            try writer.print("error: stack underflow\n", .{});
            return;
        };

        const file = std.fs.cwd().createFile(args[0], .{}) catch |e| {
            try writer.print("error creating file: {s}\n", .{@errorName(e)});
            return;
        };
        defer file.close();

        // Write full 1024-byte cell
        file.writeAll(result.data) catch |e| {
            try writer.print("error writing file: {s}\n", .{@errorName(e)});
            return;
        };

        try writer.print("exported cell @{d} to {s} ({d} bytes)\n", .{ index, args[0], constants.CELL_SIZE });
    }

    /// import-cell <file> — read a 1024-byte cell from disk and push it
    fn cmdImportCell(self: *Shell, args: []const []const u8, writer: anytype) !void {
        // Alias for push-cell
        try self.cmdPushCell(args, writer);
    }

    /// octave-info [0-3] — show octave memory info
    fn cmdOctaveInfo(self: *Shell, args: []const []const u8, writer: anytype) !void {
        _ = self;
        if (args.len > 0) {
            const level = std.fmt.parseInt(u8, args[0], 10) catch {
                try writer.print("error: octave must be 0-3\n", .{});
                return;
            };
            if (level > octave_mod.MAX_OCTAVE) {
                try writer.print("error: max octave is {d}\n", .{octave_mod.MAX_OCTAVE});
                return;
            }
            const oct: octave_mod.Octave = @enumFromInt(level);
            try writer.print("octave {d} ({s}):\n", .{ level, @tagName(oct) });
            try writer.print("  cell size:     {d} bytes\n", .{octave_mod.cellSizeForOctave(oct)});
            try writer.print("  address space: {d} bytes\n", .{octave_mod.addressSpaceForOctave(oct)});
            try writer.print("  slots:         {d}\n", .{octave_mod.SLOTS_PER_OCTAVE});
            try writer.print("  cost:          {d} sats/cell\n", .{octave_mod.costSatsPerCell(oct)});
        } else {
            try writer.print("octave memory hierarchy:\n", .{});
            inline for ([_]octave_mod.Octave{ .base, .kilo, .mega, .giga }) |oct| {
                const level = @intFromEnum(oct);
                try writer.print("  {d} ({s}): cell={d}B, space={d}B, cost={d} sats\n", .{
                    level, @tagName(oct), octave_mod.cellSizeForOctave(oct), octave_mod.addressSpaceForOctave(oct), octave_mod.costSatsPerCell(oct),
                });
            }
        }
    }

    // ──────────────────────────────────────────────
    // Help
    // ──────────────────────────────────────────────

    fn cmdHelp(self: *Shell, writer: anytype) !void {
        _ = self;
        try writer.print(
            \\{s}
            \\
            \\Everything is a cell. The shell operates directly on the 2-PDA kernel.
            \\
            \\Stack:
            \\  push <hex|string>     Push raw bytes (prefix 0x for hex)
            \\  push-cell <file>      Load a 1024-byte cell from disk
            \\  pop                   Remove top of stack
            \\  dup                   Duplicate top (linearity-enforced)
            \\  drop                  Discard top (linearity-enforced)
            \\  swap                  Swap top two
            \\  depth                 Show stack depths
            \\
            \\Inspect:
            \\  cat [@N]              Pretty-print cell at stack position N
            \\  ls [main|aux]         List stack contents
            \\  deref                 Dereference pointer cell
            \\  octave-info [0-3]     Show octave memory info
            \\
            \\Verify:
            \\  check-linear          Check linearity of top cell
            \\  check-identity <hex>  Compare owner ID (16 bytes hex)
            \\  check-typehash <hex>  Compare type hash (32 bytes hex)
            \\  enforcement [on|off]  Toggle linearity enforcement
            \\
            \\Execute:
            \\  load-script <hex|@f>  Load locking script (hex or @file)
            \\  load-unlock <hex|@f>  Load unlock script
            \\  step                  Execute one opcode
            \\  execute               Run loaded scripts to completion
            \\
            \\State:
            \\  history               Show command history (as cells)
            \\  export-cell <f> [@N]  Write cell to disk
            \\  import-cell <file>    Read cell from disk (alias: push-cell)
            \\  reset                 Reset PDA and execution state
            \\
            \\  help                  This message
            \\  version               Show version
            \\  exit / quit           Exit shell
            \\
        , .{VERSION_STR});
    }
};

// ── Entry point ──

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();


    var shell = Shell.init();
    defer shell.deinit();

    // Check for single-command mode
    var args_iter = std.process.args();
    _ = args_iter.skip(); // skip program name

    // Collect remaining args
    var cmd_parts: [64][]const u8 = undefined;
    var cmd_count: usize = 0;
    var arg_buf: [4096]u8 = undefined;
    var arg_pos: usize = 0;

    while (args_iter.next()) |arg| {
        if (cmd_count >= 64) break;
        const len = arg.len;
        if (arg_pos + len > arg_buf.len) break;
        @memcpy(arg_buf[arg_pos..][0..len], arg);
        cmd_parts[cmd_count] = arg_buf[arg_pos..][0..len];
        arg_pos += len;
        cmd_count += 1;
    }

    if (cmd_count > 0) {
        // Single-command mode: join args and dispatch
        var line_buf: [MAX_INPUT]u8 = undefined;
        var pos: usize = 0;
        for (cmd_parts[0..cmd_count], 0..) |part, i| {
            if (i > 0 and pos < line_buf.len) {
                line_buf[pos] = ' ';
                pos += 1;
            }
            const copy_len = @min(part.len, line_buf.len - pos);
            @memcpy(line_buf[pos..][0..copy_len], part[0..copy_len]);
            pos += copy_len;
        }
        var buf_writer = std.io.bufferedWriter(stdout);
        try shell.dispatch(line_buf[0..pos], buf_writer.writer());
        try buf_writer.flush();
        return;
    }

    // Interactive REPL mode
    try stdout.print("{s}\n", .{VERSION_STR});
    try stdout.print("type 'help' for commands\n\n", .{});

    var buf: [MAX_INPUT]u8 = undefined;

    while (shell.running) {
        try stdout.writeAll(PROMPT);

        const line = stdin.reader().readUntilDelimiter(&buf, '\n') catch |e| {
            if (e == error.EndOfStream) break;
            return e;
        };

        var buf_writer = std.io.bufferedWriter(stdout);
        shell.dispatch(line, buf_writer.writer()) catch |e| {
            try stdout.print("internal error: {s}\n", .{@errorName(e)});
        };
        try buf_writer.flush();
    }
}

```
