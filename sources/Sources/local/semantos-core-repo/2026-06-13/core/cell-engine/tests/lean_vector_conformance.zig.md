---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lean_vector_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.966999+00:00
---

# core/cell-engine/tests/lean_vector_conformance.zig

```zig
// D-LC2 — JSON-load Lean test vectors and run them against the PDA / linearity
// / plexus modules. Today differential_conformance.zig hand-codes vectors that
// mirror what proofs/vectors/*.json says; this test makes the JSON files the
// literal source of truth — change the Lean model, regenerate the JSON, and
// the conformance check follows.
//
// Coverage:
//   * proofs/vectors/plexus-vectors.json   — operation.type = "plexus"
//     → dispatched via `plexus.executePlexus`
//   * proofs/vectors/linearity-vectors.json — operation.type ∈
//     {"linearity_check","stack_op"}
//     → linearity_check dispatched via `linearity.checkLinearity`;
//       stack_op (dup/drop) dispatched via PDA's sdup/sdrop (enforced or
//       not, per setup.enforcement_enabled).
//   * proofs/vectors/stack-vectors.json    — operation.type ∈
//     {"bounds_check","stack_op","roundtrip_check"}
//     → bounds_check asserts depth constants / forces overflow; stack_op
//       (pop) exercises spop underflow; roundtrip_check is push→pop byte
//       equality (K7 push_preserves_cell, no kernel snapshot ABI required).
//
// Schema (per `proofs/vectors/generate-vectors.ts`):
//
//   {
//     "test_id": "K2_CHECKLINEARTYPE_LINEAR_PASS",
//     "setup": {
//       "main_stack": [{ "linearity": N, "domain_flag": N,
//                        "type_hash": "<64 hex>", "owner_id": "<32 hex>",
//                        "capability_type": N }, ...],
//       "aux_stack": [...],
//       "enforcement_enabled": bool
//     },
//     "operation": { "type": "plexus", "opcode": N },
//     "expected": { "result": "ok" | "error",
//                   "error_code": "<symbol>"?,
//                   "main_sp_after": N }
//   }

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");

// ─── Helpers (mirrored from differential_conformance.zig) ───────────────────

fn hexToBytes(comptime N: usize, hex: []const u8) [N]u8 {
    var result: [N]u8 = [_]u8{0} ** N;
    const len = @min(hex.len / 2, N);
    for (0..len) |i| {
        result[i] = std.fmt.parseInt(u8, hex[2 * i ..][0..2], 16) catch 0;
    }
    return result;
}

fn makeTestCell(
    lin: u32,
    domain_flag: u32,
    type_hash: [32]u8,
    owner_id: [16]u8,
    cap_type: u8,
    priv_key: ?[32]u8,
    budget_remaining: ?u64,
) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    @memcpy(cell[30..62], &type_hash);
    @memcpy(cell[62..78], &owner_id);
    cell[256] = cap_type;
    // Optional payload writes — OP_SIGN reads priv_key at payload byte 0..32,
    // OP_DECREMENT_BUDGET / OP_REFILL_BUDGET read remaining_satoshis at payload
    // byte 32..40 (BUDGET_OFFSET_REMAINING). priv_key overwrites cap_type at
    // payload byte 0; this is by design for sign/budget cells per WALLET-TIER
    // §6.1 — they identify by linearity+domain_flag, not cap-byte.
    if (priv_key) |pk| {
        @memcpy(cell[constants.HEADER_SIZE .. constants.HEADER_SIZE + 32], &pk);
    }
    if (budget_remaining) |remaining| {
        const off = constants.HEADER_SIZE + 32; // BUDGET_OFFSET_REMAINING
        std.mem.writeInt(u64, cell[off..][0..8], remaining, .little);
    }
    return cell;
}

// ─── JSON shape ────────────────────────────────────────────────────────────

const VectorCell = struct {
    linearity: u32,
    domain_flag: u32,
    type_hash: []const u8,
    owner_id: []const u8,
    capability_type: u32,
    // Optional payload fields used by OP_SIGN (priv_key at payload byte 0..32)
    // and OP_DECREMENT_BUDGET / OP_REFILL_BUDGET (remaining_satoshis at payload
    // byte 32..40). Both default to absent for back-compat with existing
    // K1/K2/K3 vectors that never touched the payload.
    priv_key: ?[]const u8 = null,
    budget_remaining: ?u64 = null,
};

const VectorSetup = struct {
    main_stack: []const VectorCell,
    aux_stack: []const VectorCell,
    enforcement_enabled: bool,
};

const VectorArg = struct {
    type: []const u8,
    value: std.json.Value,
};

const VectorOp = struct {
    type: []const u8,
    opcode: ?u32 = null,
    op: ?[]const u8 = null,
    target: ?[]const u8 = null,
    argument: ?VectorArg = null,
    // Multi-arg form for opcodes that pop more than one stack item beyond the
    // cell setup (OP_READHEADER offset+size, OP_CELLCREATE 4-tuple, OP_SIGN
    // digest+sighash, OP_REFILL_BUDGET amount+pubkey+sig). Pushed in order
    // after the main_stack cells. Supported `type` values are listed in
    // `pushArg` below; back-compat with `argument` is preserved.
    args: ?[]const VectorArg = null,
};

const VectorExpected = struct {
    result: []const u8,
    error_code: ?[]const u8 = null,
    main_sp_after: ?u32 = null,
    aux_sp_after: ?u32 = null,
};

const Vector = struct {
    test_id: []const u8,
    description: []const u8 = "",
    kernel_invariant: []const u8 = "",
    lean_theorem: []const u8 = "",
    setup: VectorSetup,
    operation: VectorOp,
    expected: VectorExpected,
};

// ─── Vector runner ────────────────────────────────────────────────────────

/// Push a single VectorArg onto the PDA main stack using the encoding
/// implied by its `type` field. Returns null on success, an owned diagnostic
/// string on unknown type (caller must free).
fn pushArg(
    allocator: std.mem.Allocator,
    p: *pda_mod.PDA,
    test_id: []const u8,
    arg: VectorArg,
) !?[]u8 {
    if (std.mem.eql(u8, arg.type, "capability")) {
        // Single u8 byte (matches CHECKCAPABILITY's payload byte 0 read).
        const n: u32 = @intCast(arg.value.integer);
        try p.spush(&[_]u8{@intCast(n & 0xFF)});
    } else if (std.mem.eql(u8, arg.type, "domain_flag")) {
        // 4-byte u32 LE.
        const n: u32 = @intCast(arg.value.integer);
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, n, .little);
        try p.spush(&bytes);
    } else if (std.mem.eql(u8, arg.type, "owner_id")) {
        const bytes = hexToBytes(16, arg.value.string);
        try p.spush(&bytes);
    } else if (std.mem.eql(u8, arg.type, "type_hash")) {
        const bytes = hexToBytes(32, arg.value.string);
        try p.spush(&bytes);
    } else if (std.mem.eql(u8, arg.type, "i64")) {
        // Script-number-encoded (sign-magnitude LE) via pda_mod.i64ToCell.
        const val: i64 = @intCast(arg.value.integer);
        var buf: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
        const len = pda_mod.i64ToCell(val, &buf);
        try p.spush(buf[0..len]);
    } else if (std.mem.eql(u8, arg.type, "hex")) {
        // Raw bytes from hex string (variable length — used for OP_SIGN
        // 32-byte digests and OP_REFILL_BUDGET pubkeys / sigs).
        const hex = arg.value.string;
        const byte_len = hex.len / 2;
        var buf: [256]u8 = undefined;
        if (byte_len > buf.len) {
            return try std.fmt.allocPrint(allocator,
                "{s}: hex arg longer than 256 bytes ({d})", .{ test_id, byte_len });
        }
        for (0..byte_len) |i| {
            buf[i] = std.fmt.parseInt(u8, hex[2 * i ..][0..2], 16) catch 0;
        }
        try p.spush(buf[0..byte_len]);
    } else {
        return try std.fmt.allocPrint(allocator,
            "{s}: unknown argument.type '{s}'", .{ test_id, arg.type });
    }
    return null;
}

/// Run a single plexus-typed vector against the PDA. Returns null on pass,
/// returns an owned diagnostic string on mismatch (caller must free).
fn runPlexusVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = v.setup.enforcement_enabled;

    for (v.setup.main_stack) |vc| {
        const type_hash = hexToBytes(32, vc.type_hash);
        const owner_id = hexToBytes(16, vc.owner_id);
        const priv_key_opt: ?[32]u8 = if (vc.priv_key) |pk_hex| hexToBytes(32, pk_hex) else null;
        var cell = makeTestCell(
            vc.linearity,
            vc.domain_flag,
            type_hash,
            owner_id,
            @intCast(vc.capability_type),
            priv_key_opt,
            vc.budget_remaining,
        );
        try p.spushCell(&cell, pda_mod.CELL_SIZE);
    }

    if (v.setup.aux_stack.len != 0) {
        return try std.fmt.allocPrint(allocator, "{s}: aux_stack setup not yet supported", .{v.test_id});
    }

    const opcode_u32 = v.operation.opcode orelse {
        return try std.fmt.allocPrint(allocator, "{s}: plexus vector missing opcode", .{v.test_id});
    };
    const opcode: u8 = @intCast(opcode_u32);

    // Push arguments onto the stack BEFORE running the opcode, matching the
    // generator schema. Today's plexus opcodes pop their argument off the main
    // stack (see plexus.zig: CHECKCAPABILITY pops cap_type, CHECKIDENTITY pops
    // owner_id, OP_READHEADER pops offset+size, OP_CELLCREATE pops 4 args, etc.).
    // The argument `type` field tells us how to encode the bytes.
    if (v.operation.argument) |arg| {
        if (try pushArg(allocator, &p, v.test_id, arg)) |diag| return diag;
    }
    if (v.operation.args) |args_list| {
        for (args_list) |arg| {
            if (try pushArg(allocator, &p, v.test_id, arg)) |diag| return diag;
        }
    }

    const result = plexus.executePlexus(&p, opcode);

    const expect_ok = std.mem.eql(u8, v.expected.result, "ok");
    if (expect_ok) {
        if (result) |_| {
            // pass — fall through to sp check
        } else |err| {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected ok, got error.{s}", .{ v.test_id, @errorName(err) });
        }
    } else {
        const expected_err = v.expected.error_code orelse {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected error but vector missing error_code", .{v.test_id});
        };
        if (result) |_| {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected error.{s}, got ok", .{ v.test_id, expected_err });
        } else |err| {
            const got = @errorName(err);
            if (!std.mem.eql(u8, got, expected_err)) {
                return try std.fmt.allocPrint(allocator,
                    "{s}: expected error.{s}, got error.{s}", .{ v.test_id, expected_err, got });
            }
        }
    }

    if (v.expected.main_sp_after) |want| {
        const got = p.sdepth();
        if (got != want) {
            return try std.fmt.allocPrint(allocator,
                "{s}: main_sp_after expected {d}, got {d}", .{ v.test_id, want, got });
        }
    }

    return null;
}

// ─── Linearity / stack / bounds / roundtrip runners ──────────────────────

/// Populate the PDA main+aux stacks from the vector setup. Returns null on
/// success, an owned diagnostic on failure (caller frees).
fn populateStacks(
    allocator: std.mem.Allocator,
    p: *pda_mod.PDA,
    v: Vector,
) !?[]u8 {
    p.enforcement_enabled = v.setup.enforcement_enabled;
    for (v.setup.main_stack) |vc| {
        const type_hash = hexToBytes(32, vc.type_hash);
        const owner_id = hexToBytes(16, vc.owner_id);
        const priv_key_opt: ?[32]u8 = if (vc.priv_key) |pk_hex| hexToBytes(32, pk_hex) else null;
        var cell = makeTestCell(
            vc.linearity,
            vc.domain_flag,
            type_hash,
            owner_id,
            @intCast(vc.capability_type),
            priv_key_opt,
            vc.budget_remaining,
        );
        p.spushCell(&cell, pda_mod.CELL_SIZE) catch |err| {
            return try std.fmt.allocPrint(allocator,
                "{s}: spushCell(main) failed: {s}", .{ v.test_id, @errorName(err) });
        };
    }
    for (v.setup.aux_stack) |vc| {
        const type_hash = hexToBytes(32, vc.type_hash);
        const owner_id = hexToBytes(16, vc.owner_id);
        const priv_key_opt: ?[32]u8 = if (vc.priv_key) |pk_hex| hexToBytes(32, pk_hex) else null;
        var cell = makeTestCell(
            vc.linearity,
            vc.domain_flag,
            type_hash,
            owner_id,
            @intCast(vc.capability_type),
            priv_key_opt,
            vc.budget_remaining,
        );
        p.apushCell(&cell, pda_mod.CELL_SIZE) catch |err| {
            return try std.fmt.allocPrint(allocator,
                "{s}: apushCell(aux) failed: {s}", .{ v.test_id, @errorName(err) });
        };
    }
    return null;
}

/// Compare result + error_code + sp expectations and return diagnostic on
/// mismatch, null on pass. `result_err` is null on ok, the @errorName on err.
fn checkExpected(
    allocator: std.mem.Allocator,
    v: Vector,
    result_err: ?[]const u8,
    main_sp: u32,
    aux_sp: u32,
) !?[]u8 {
    const expect_ok = std.mem.eql(u8, v.expected.result, "ok");
    if (expect_ok) {
        if (result_err) |got| {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected ok, got error.{s}", .{ v.test_id, got });
        }
    } else {
        const expected_err = v.expected.error_code orelse {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected error but vector missing error_code", .{v.test_id});
        };
        if (result_err) |got| {
            if (!std.mem.eql(u8, got, expected_err)) {
                return try std.fmt.allocPrint(allocator,
                    "{s}: expected error.{s}, got error.{s}", .{ v.test_id, expected_err, got });
            }
        } else {
            return try std.fmt.allocPrint(allocator,
                "{s}: expected error.{s}, got ok", .{ v.test_id, expected_err });
        }
    }

    if (v.expected.main_sp_after) |want| {
        if (main_sp != want) {
            return try std.fmt.allocPrint(allocator,
                "{s}: main_sp_after expected {d}, got {d}", .{ v.test_id, want, main_sp });
        }
    }
    if (v.expected.aux_sp_after) |want| {
        if (aux_sp != want) {
            return try std.fmt.allocPrint(allocator,
                "{s}: aux_sp_after expected {d}, got {d}", .{ v.test_id, want, aux_sp });
        }
    }
    return null;
}

/// Parse a JSON `op` string into a `linearity.LinearityOperation` enum. Returns
/// null on unknown op (caller surfaces as a diagnostic).
fn parseLinearityOp(op: []const u8) ?linearity.LinearityOperation {
    if (std.mem.eql(u8, op, "duplicate")) return .duplicate;
    if (std.mem.eql(u8, op, "discard")) return .discard;
    if (std.mem.eql(u8, op, "consume")) return .consume;
    if (std.mem.eql(u8, op, "swap")) return .swap;
    if (std.mem.eql(u8, op, "inspect")) return .inspect;
    return null;
}

/// Run a linearity_check vector. Reads the top main_stack cell, calls
/// `linearity.checkLinearity` with the parsed op, compares to expected.
fn runLinearityCheckVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    var p = pda_mod.PDA.init(500_000);
    if (try populateStacks(allocator, &p, v)) |diag| return diag;

    const op_str = v.operation.op orelse {
        return try std.fmt.allocPrint(allocator,
            "{s}: linearity_check vector missing op", .{v.test_id});
    };
    const op = parseLinearityOp(op_str) orelse {
        return try std.fmt.allocPrint(allocator,
            "{s}: unknown linearity op '{s}'", .{ v.test_id, op_str });
    };

    if (p.sdepth() == 0) {
        return try std.fmt.allocPrint(allocator,
            "{s}: linearity_check requires a top cell but main_stack is empty", .{v.test_id});
    }
    const top = try p.speek();
    const lin_type = linearity.getLinearity(top.data[0..top.len]) catch |err| {
        return try std.fmt.allocPrint(allocator,
            "{s}: getLinearity failed: {s}", .{ v.test_id, @errorName(err) });
    };

    var err_name: ?[]const u8 = null;
    linearity.checkLinearity(lin_type, op) catch |err| {
        err_name = @errorName(err);
    };
    return try checkExpected(allocator, v, err_name, p.sdepth(), p.adepth());
}

/// Run a stack_op vector. `op` ∈ {"dup","drop","pop"}; enforcement_enabled
/// in setup picks the enforced vs unenforced variant for dup/drop. `pop`
/// is plain `spop` (used by stack-vectors K5_EMPTY_POP).
fn runStackOpVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    var p = pda_mod.PDA.init(500_000);
    if (try populateStacks(allocator, &p, v)) |diag| return diag;

    const op_str = v.operation.op orelse {
        return try std.fmt.allocPrint(allocator,
            "{s}: stack_op vector missing op", .{v.test_id});
    };

    var err_name: ?[]const u8 = null;
    if (std.mem.eql(u8, op_str, "dup")) {
        if (v.setup.enforcement_enabled) {
            p.sdup_enforced() catch |err| {
                err_name = @errorName(err);
            };
        } else {
            p.sdup() catch |err| {
                err_name = @errorName(err);
            };
        }
    } else if (std.mem.eql(u8, op_str, "drop")) {
        if (v.setup.enforcement_enabled) {
            p.sdrop_enforced() catch |err| {
                err_name = @errorName(err);
            };
        } else {
            p.sdrop() catch |err| {
                err_name = @errorName(err);
            };
        }
    } else if (std.mem.eql(u8, op_str, "pop")) {
        _ = p.spop() catch |err| {
            err_name = @errorName(err);
        };
    } else {
        return try std.fmt.allocPrint(allocator,
            "{s}: unsupported stack_op op '{s}'", .{ v.test_id, op_str });
    }

    return try checkExpected(allocator, v, err_name, p.sdepth(), p.adepth());
}

/// Run a bounds_check vector. Targets:
///   * main_stack_depth / aux_stack_depth — assert the PDA constant equals
///     the canonical depth (1024 / 256). Pure structural check.
///   * main_overflow — push minimal 1-byte payloads until spush returns
///     stack_overflow; expect main_sp_after = MAIN_STACK_DEPTH.
///   * aux_overflow — same on aux stack.
fn runBoundsCheckVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    var p = pda_mod.PDA.init(500_000);
    if (try populateStacks(allocator, &p, v)) |diag| return diag;

    const target = v.operation.target orelse {
        return try std.fmt.allocPrint(allocator,
            "{s}: bounds_check vector missing target", .{v.test_id});
    };

    var err_name: ?[]const u8 = null;
    if (std.mem.eql(u8, target, "main_stack_depth")) {
        if (pda_mod.MAIN_STACK_DEPTH != 1024) {
            return try std.fmt.allocPrint(allocator,
                "{s}: MAIN_STACK_DEPTH expected 1024, got {d}",
                .{ v.test_id, pda_mod.MAIN_STACK_DEPTH });
        }
    } else if (std.mem.eql(u8, target, "aux_stack_depth")) {
        if (pda_mod.AUX_STACK_DEPTH != 256) {
            return try std.fmt.allocPrint(allocator,
                "{s}: AUX_STACK_DEPTH expected 256, got {d}",
                .{ v.test_id, pda_mod.AUX_STACK_DEPTH });
        }
    } else if (std.mem.eql(u8, target, "main_overflow")) {
        var i: u32 = 0;
        while (i < pda_mod.MAIN_STACK_DEPTH + 1) : (i += 1) {
            p.spush(&[_]u8{0}) catch |err| {
                err_name = @errorName(err);
                break;
            };
        }
    } else if (std.mem.eql(u8, target, "aux_overflow")) {
        var i: u32 = 0;
        while (i < pda_mod.AUX_STACK_DEPTH + 1) : (i += 1) {
            p.apush(&[_]u8{0}) catch |err| {
                err_name = @errorName(err);
                break;
            };
        }
    } else {
        return try std.fmt.allocPrint(allocator,
            "{s}: unsupported bounds_check target '{s}'", .{ v.test_id, target });
    }

    return try checkExpected(allocator, v, err_name, p.sdepth(), p.adepth());
}

/// Run a roundtrip_check vector. Per K7 (k7a_push_preserves_cell): push a
/// cell, pop it back, assert the bytes are identical. The cell-engine PDA
/// does not expose a public Zig snapshot/restore (that ABI lives in
/// main.zig as `kernel_snapshot_state` / `kernel_restore_state` for the
/// wasm host), but K7 is push→pop equality — no snapshot needed.
fn runRoundtripCheckVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    var p = pda_mod.PDA.init(500_000);
    if (try populateStacks(allocator, &p, v)) |diag| return diag;

    // Build a fully-populated reference cell that exercises every byte we
    // care about preserving — magic, linearity, domain_flag, type_hash,
    // owner_id, capability byte. (LinearityType=affine to avoid running
    // afoul of any future enforcement on the spushCell/spop pair.)
    const type_hash = hexToBytes(32, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const owner_id = hexToBytes(16, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    var ref_cell = makeTestCell(2, 1, type_hash, owner_id, 0, null, null);

    var err_name: ?[]const u8 = null;
    p.spushCell(&ref_cell, pda_mod.CELL_SIZE) catch |err| {
        err_name = @errorName(err);
    };
    if (err_name == null) {
        const popped = p.spop() catch |err| blk: {
            err_name = @errorName(err);
            break :blk null;
        };
        if (popped) |slot| {
            if (slot.len != pda_mod.CELL_SIZE) {
                return try std.fmt.allocPrint(allocator,
                    "{s}: roundtrip popped len {d}, expected {d}",
                    .{ v.test_id, slot.len, pda_mod.CELL_SIZE });
            }
            if (!std.mem.eql(u8, slot.data, &ref_cell)) {
                return try std.fmt.allocPrint(allocator,
                    "{s}: roundtrip popped bytes differ from pushed bytes",
                    .{v.test_id});
            }
        }
    }

    return try checkExpected(allocator, v, err_name, p.sdepth(), p.adepth());
}

/// Top-level dispatcher: route a vector to the appropriate runner by
/// operation.type. Returns null on pass, owned diagnostic on mismatch.
fn runVector(allocator: std.mem.Allocator, v: Vector) !?[]u8 {
    const t = v.operation.type;
    if (std.mem.eql(u8, t, "plexus")) {
        return runPlexusVector(allocator, v);
    } else if (std.mem.eql(u8, t, "linearity_check")) {
        return runLinearityCheckVector(allocator, v);
    } else if (std.mem.eql(u8, t, "stack_op")) {
        return runStackOpVector(allocator, v);
    } else if (std.mem.eql(u8, t, "bounds_check")) {
        return runBoundsCheckVector(allocator, v);
    } else if (std.mem.eql(u8, t, "roundtrip_check")) {
        return runRoundtripCheckVector(allocator, v);
    } else {
        return try std.fmt.allocPrint(allocator,
            "{s}: unknown operation.type '{s}'", .{ v.test_id, t });
    }
}

// ─── Test harness ─────────────────────────────────────────────────────────

/// Load `json_path` from the cell-engine cwd, parse as `[]Vector`, dispatch
/// each through `runVector`, and fail the test if any vector mismatches.
fn runVectorFile(json_path: []const u8) !void {
    const allocator = std.testing.allocator;

    const file = std.fs.cwd().openFile(json_path, .{}) catch |err| {
        std.debug.print("\n[D-LC2] could not open {s} from cwd: {s}\n", .{ json_path, @errorName(err) });
        return error.VectorFileNotFound;
    };
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice([]Vector, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var failures: usize = 0;
    var total: usize = 0;
    for (parsed.value) |v| {
        total += 1;
        const diag_opt = runVector(allocator, v) catch |err| {
            std.debug.print("\n[D-LC2] {s}: runner errored: {s}\n", .{ v.test_id, @errorName(err) });
            failures += 1;
            continue;
        };
        if (diag_opt) |diag| {
            std.debug.print("\n[D-LC2] {s}\n", .{diag});
            allocator.free(diag);
            failures += 1;
        }
    }

    if (failures != 0) {
        std.debug.print("\n[D-LC2] {d}/{d} vectors in {s} failed\n",
            .{ failures, total, json_path });
        return error.VectorMismatch;
    }
    // Sanity: at least one vector ran (catches accidental empty JSON / wrong path).
    try std.testing.expect(total > 0);
}

// ─── Tests ────────────────────────────────────────────────────────────────

test "lean vectors: plexus-vectors.json round-trips through PDA" {
    try runVectorFile("../../proofs/vectors/plexus-vectors.json");
}

test "lean vectors: linearity-vectors.json round-trips through linearity + PDA" {
    try runVectorFile("../../proofs/vectors/linearity-vectors.json");
}

test "lean vectors: stack-vectors.json round-trips through PDA" {
    try runVectorFile("../../proofs/vectors/stack-vectors.json");
}

```
