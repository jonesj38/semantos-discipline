---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/policy_runtime.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.233482+00:00
---

# runtime/semantos-brain/src/policy_runtime.zig

```zig
// Zig PolicyRuntime — brain-side seam for kernel-enforced cell evaluation.
//
// Reference: docs/prd/UNIFICATION-ROADMAP.md §11.10 order 2b (kernel-enforcement
//            program keystone, reframed 2026-05-25);
//            docs/prd/PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md (design reference);
//            packages/policy-runtime/src/types.ts (canonical TS shape this
//            mirrors so a future real CDM or SCADA cartridge consuming the
//            brain plugs in via the same conceptual interface);
//            runtime/semantos-brain/src/kernel_zig.zig (the current syntactic-
//            shim backend this seam calls today).
//
// What this is: the single entry point cartridge handlers call to evaluate
// a policy / opcode-cell against the 2-PDA kernel.  Today the backend is the
// Phase-3 syntactic shim in `kernel_zig.executeOpcodeBytes` (frame validation
// only).  Per §11.10 order 2e (deferred), the backend swaps to the real
// `core/cell-engine/src/executor.zig` once the 14-module dep refactor lands.
// That swap is interface-preserving — cartridge call sites do not change.
//
// What this IS NOT (today): a full 2-PDA executor.  The shim does not enforce
// linearity (K1), domain flags (K3), type hashes, capabilities — it walks the
// pushdata frame for syntactic well-formedness and counts opcodes.  Cells that
// the real executor would reject for semantic reasons pass this shim; the
// cartridge-shaped enforcement remains at the schema-validator layer until
// order 2e lands.
//
// Cartridge consumers (per §11.10 orders 2c + 2d):
//   - intent_cells_handler.zig (oddjobz) — replace direct kernel_zig call
//   - cell_handler.zig (generic) — optional pre-write seam for opcode-bearing
//     payloads
//
// Shape mirror (TS canonical at packages/policy-runtime/src/types.ts):
//   PolicyContext     ↔  PolicyContext
//   PolicyResult      ↔  PolicyResult
//   HostCallRecord    ↔  HostCallRecord
//   PolicyRuntime     ↔  PolicyRuntime (class)
//   evaluate(...)     ↔  evaluate(...)

const std = @import("std");
const kernel_zig = @import("kernel_zig");
// §11.10 order 2e PR-2b — real-executor backend consumed by evaluateReal.
// Three modules from the 6-module chain shipped in PR #649: executor
// (ExecutionContext + execute + ExecuteError), pda (PDA struct +
// initInPlace + opcount field for gas extraction), and allocator
// (ScriptArena for script-temporary allocations).  Wright frame §0:
// these three together ARE the deterministic 2-PDA machine the
// PolicyRuntime seam exists to expose to cartridges.
const executor = @import("executor");
const pda_mod = @import("pda");
const allocator_mod = @import("allocator");

// Constants for the real-executor adapter (PR-2b implementation; PR-2a
// only locks them in so build.zig and policy_runtime.zig agree on the
// envelope).  See docs/prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md §2 D2.
//
// MAX_OPS_PER_EVAL = 500_000 matches executor.DEFAULT_MAX_OPS at
// core/cell-engine/src/executor.zig:25 — not arbitrary, the executor's
// own canonical default.  ARENA_SIZE = 64 KB matches the TS wrapper's
// IO_SCRIPT region.
pub const MAX_OPS_PER_EVAL: u32 = 500_000;
pub const ARENA_SIZE: usize = 64 * 1024;

// ─────────────────────────────────────────────────────────────────────
// Types — mirror packages/policy-runtime/src/types.ts
// ─────────────────────────────────────────────────────────────────────

/// Selects which backend PolicyRuntime.evaluate dispatches to.
///
/// `syntactic_shim` — the existing Phase-3 backend in
///                    `kernel_zig.executeOpcodeBytes`.  Walks pushdata
///                    frames, counts opcodes, no semantic enforcement.
///                    Behaviour-equivalent to the TS canonical shape's
///                    "frame-validate only" mode.  Default for all
///                    cartridge consumers as of PR-2a.
///
/// `real_executor`  — the §11.10 order 2e backend that swaps in the real
///                    `core/cell-engine/src/executor.zig` 2-PDA executor.
///                    Per-call PDA + arena, all-lock script load,
///                    `tx_context = null` (Phase 1 — see design doc §2 D3).
///                    STUB in PR-2a (returns rejection_code =
///                    "real_executor_not_wired_yet"); implementation
///                    lands in PR-2b.
///
/// See docs/prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md for the full design.
pub const PolicyRuntimeMode = enum {
    syntactic_shim,
    real_executor,
};

/// Identity hat performing an action.  Mirrors the TS `{ certId, capabilities }`
/// shape on `PolicyContext.actor` / `.coActor`.  Both fields are borrowed —
/// the caller owns the underlying memory and the lifetime extends through
/// the corresponding `evaluate` call.
pub const Actor = struct {
    /// 32-hex-char cert id (per `identity_certs.CERT_ID_HEX_LEN`).
    cert_id: []const u8,
    /// Capability ids this actor presents.  In the TS shape this is
    /// `number[]`; mirrored here as `[]const u32` since capability ids are
    /// non-negative integers (per `core/protocol-types/src/namespace.ts`).
    capabilities: []const u32,
};

/// Snapshot of runtime state for a single policy evaluation.  Frozen by
/// convention before evaluate() is called — host functions (when real
/// executor lands) read from this, not from mutable state.
///
/// `fields` mirrors the TS `Record<string, unknown>` as a string-keyed map
/// of serialized bytes.  Cartridges that need typed access serialize their
/// values at the call site; the kernel reads bytes through OP_LOADFIELD.
/// Today's syntactic-shim backend ignores `fields` entirely — it surfaces
/// as a no-op pass-through until order 2e wires real OP_LOADFIELD.
pub const PolicyContext = struct {
    /// Named fields the policy can reference via OP_LOADFIELD / OP_CALLHOST.
    /// Empty by default — callers populate as needed.  Borrowed.
    fields: std.StringHashMapUnmanaged([]const u8) = .{},
    /// Identity hat performing the action.  Required.
    actor: Actor,
    /// Optional second authorizer for dual-auth policies.
    co_actor: ?Actor = null,
};

/// One OP_CALLHOST invocation recorded during policy evaluation.
/// Empty in syntactic-shim mode (the shim doesn't dispatch OP_CALLHOST);
/// populated once order 2e wires the real executor + host-fn registry.
pub const HostCallRecord = struct {
    /// Host function name (e.g., "has-capability", "check-domain").  Borrowed
    /// from the policy bytes' string-pool; lifetime extends through the
    /// returned PolicyResult.
    name: []const u8,
    /// Numeric result returned by the host function.  i64 covers the TS
    /// `number` envelope for integer cases; if a future host function returns
    /// fractional values, the shape extends.
    result: i64,
    /// Microseconds since epoch when the call fired.
    timestamp_us: i64,
};

/// Structured outcome of a policy evaluation.  Never throws — all failures
/// (including infrastructure failures) are encoded as `ok: false` with a
/// `rejection_code`.  Mirrors the TS `PolicyResult` shape.
///
/// Lifecycle: in syntactic-shim mode `host_calls` is always the empty
/// sentinel slice, so no deinit is required.  When the backend grows real
/// OP_CALLHOST dispatch (order 2e), `host_calls` will be allocator-owned
/// and a `deinit(allocator)` method will land alongside that change.
pub const PolicyResult = struct {
    /// Did the 2-PDA reach VERIFY with a true top-of-stack?  In syntactic-
    /// shim mode this is "did the frame walker complete without rejecting?"
    ok: bool,
    /// Opcodes consumed (gas metering).  Widened to u64 vs the shim's u32
    /// to match the TS `number` envelope and give headroom for future
    /// long-running policies.
    gas: u64,
    /// Audit trail of every OP_CALLHOST that fired.  Empty under the
    /// syntactic shim — see lifecycle note above.
    host_calls: []const HostCallRecord = &.{},
    /// Opcode-level error code when `ok == false`.  Borrowed from the
    /// backend's static error-kind table (kernel_zig surfaces tokens like
    /// "invalid_pushdata", "script_too_large").  null when ok.
    rejection_code: ?[]const u8 = null,
    /// Optional human-readable detail when `ok == false`.  null in shim mode
    /// — the backend doesn't synthesise detail strings.
    rejection_detail: ?[]const u8 = null,
};

/// Error returned by `evaluate` when the backend itself fails (allocator
/// OOM, future FFI panic).  Distinct from a policy-level reject — mobile /
/// the dispatcher retries on this category but treats `PolicyResult{ ok=
/// false }` as a permanent reject.
pub const PolicyRuntimeError = error{
    /// Infrastructure failure in the brain-side backend.  Maps to the
    /// `kernel_local_exec_failed` token kernel_zig surfaces today, and to
    /// the same token any future real-executor backend would surface for
    /// out-of-arena / FFI conditions.
    backend_infrastructure_error,
};

// ─────────────────────────────────────────────────────────────────────
// PolicyRuntime
// ─────────────────────────────────────────────────────────────────────

/// The single entry point cartridge handlers call to evaluate a policy
/// against the 2-PDA kernel.  Stateless under `.syntactic_shim` (the shim
/// has no per-instance state) — an instance is essentially a typed handle
/// plus the backend selector.  When the backend swaps to `.real_executor`
/// mode (order 2e PR-2b), per-instance state (cell-engine handle,
/// host-fn registry) lands here.
pub const PolicyRuntime = struct {
    allocator: std.mem.Allocator,
    mode: PolicyRuntimeMode,

    /// Default constructor — returns a runtime in `.real_executor` mode
    /// (C10 PR-2e, 2026-05-28). Per `docs/design/REAL-EXECUTOR-WIRE.md`
    /// §2: with cell_handler (PR-2c) and cells_mint_handler (PR-2d) both
    /// explicitly on .real_executor via initWithMode, this flip catches
    /// any UNKNOWN call sites (REPL smokes, future cartridge handlers,
    /// test helpers) and makes "if you call `init`, you get real
    /// semantics."
    ///
    /// The `.syntactic_shim` backend stays callable via
    /// `initWithMode(allocator, .syntactic_shim)` as the fallback per
    /// POLICY-RUNTIME-EXECUTOR-ADAPTER.md §7 (kernel_zig.zig is
    /// explicitly NOT retired).
    pub fn init(allocator: std.mem.Allocator) PolicyRuntime {
        return .{ .allocator = allocator, .mode = .real_executor };
    }

    /// Mode-explicit constructor — used by PR-2b (and PR-2c) to flip
    /// individual consumers to `.real_executor` without touching the
    /// default-mode call sites.  Inline tests also use this form to
    /// exercise the stub path.
    pub fn initWithMode(
        allocator: std.mem.Allocator,
        mode: PolicyRuntimeMode,
    ) PolicyRuntime {
        return .{ .allocator = allocator, .mode = mode };
    }

    /// Evaluate `policy_bytes` against `context` and return a structured
    /// PolicyResult.  Never throws a policy-level reject — those are encoded
    /// as `PolicyResult{ ok = false, rejection_code = ... }`.  Throws only
    /// for infrastructure failures (out-of-arena, FFI panic in future real-
    /// executor mode).
    ///
    /// Dispatches on `self.mode`:
    ///   - `.syntactic_shim`  → existing kernel_zig.executeOpcodeBytes path
    ///   - `.real_executor`   → STUB in PR-2a; real adapter lands in PR-2b
    ///
    /// `context` is unused under `.syntactic_shim` and `.real_executor`
    /// PR-2a stub; PR-2b's evaluateReal will route `context.fields` /
    /// `actor` / `co_actor` into the executor's PDA via the Plexus
    /// OP_CHECK*TYPE family and OP_READPAYLOAD (Phase 2 — see design doc
    /// §2 D3).
    pub fn evaluate(
        self: *PolicyRuntime,
        policy_bytes: []const u8,
        context: PolicyContext,
    ) PolicyRuntimeError!PolicyResult {
        return switch (self.mode) {
            .syntactic_shim => self.evaluateShim(policy_bytes, context),
            .real_executor => self.evaluateReal(policy_bytes, context),
        };
    }

    fn evaluateShim(
        self: *PolicyRuntime,
        policy_bytes: []const u8,
        context: PolicyContext,
    ) PolicyRuntimeError!PolicyResult {
        // `context` is intentionally unused under the syntactic shim.
        // Once PR-2b lands, fields / actor / co_actor flow into the real
        // executor's PDA via OP_READPAYLOAD + OP_CHECKCAPABILITY.
        _ = context;

        const shim_result = kernel_zig.executeOpcodeBytes(
            self.allocator,
            policy_bytes,
        ) catch |err| switch (err) {
            kernel_zig.KernelError.kernel_local_exec_failed =>
                return PolicyRuntimeError.backend_infrastructure_error,
        };

        return .{
            .ok = shim_result.ok,
            .gas = @as(u64, shim_result.gas_used),
            .host_calls = &.{},
            .rejection_code = shim_result.error_kind,
            .rejection_detail = null,
        };
    }

    /// Real-executor adapter (PR-2b).  Implements design doc §3:
    ///   - heap-allocate pda_mod.PDA via initInPlace(MAX_OPS_PER_EVAL)
    ///   - alloc ARENA_SIZE-byte arena buffer, init ScriptArena
    ///   - executor.ExecutionContext.init(pda, &arena)
    ///   - ctx.loadScript(policy_bytes) — surface script_too_large as code
    ///   - executor.execute(&ctx) — map ExecuteError → rejection_code token
    ///   - read pda.opcount into PolicyResult.gas
    ///
    /// Phase 1 limitations (see design doc §2 D3 + §0 Wright frame #3):
    ///   - tx_context = null  → OP_CHECKSIG and other sighash-bearing
    ///                          opcodes fail at runtime.  No current
    ///                          intent_cells precondition invokes them.
    ///   - context.fields ignored → OP_READPAYLOAD references in the
    ///                              script fail at runtime.  Same trade.
    /// Phase 2 lands the synthetic-cell-payload translator + tx_context
    /// wiring when task #16 (real anchor backend) provides the spend-tx
    /// equivalent OP_CHECKSIG needs to verify against.
    fn evaluateReal(
        self: *PolicyRuntime,
        policy_bytes: []const u8,
        context: PolicyContext,
    ) PolicyRuntimeError!PolicyResult {
        // Phase 1: actor / co_actor / fields are not yet wired into the
        // executor's PDA.  They thread through unchanged so cartridge
        // call sites need no rewriting when Phase 2 lands.
        _ = context;

        // PDA is ~1.5 MB — too large for stack-resident init per
        // pda.PDA.initInPlace's contract.  Heap-allocate then mutate in
        // place; free on every code path via defer.
        const pda = self.allocator.create(pda_mod.PDA) catch
            return PolicyRuntimeError.backend_infrastructure_error;
        defer self.allocator.destroy(pda);
        pda.initInPlace(MAX_OPS_PER_EVAL);

        const arena_buf = self.allocator.alloc(u8, ARENA_SIZE) catch
            return PolicyRuntimeError.backend_infrastructure_error;
        defer self.allocator.free(arena_buf);
        var arena = allocator_mod.ScriptArena.init(arena_buf);

        var ctx = executor.ExecutionContext.init(pda, &arena);

        // loadScript fails with error.script_too_large when the input
        // exceeds executor.MAX_SCRIPT_SIZE (10_000 bytes).  Surface as a
        // structured reject — wire-compatible naming with executor's own
        // ExecuteError.script_too_large variant.
        ctx.loadScript(policy_bytes) catch {
            return .{
                .ok = false,
                .gas = 0,
                .host_calls = &.{},
                .rejection_code = "script_too_large",
                .rejection_detail = null,
            };
        };

        // execute() returns true iff top-of-stack is truthy at end of
        // the lock script.  Any ExecuteError variant becomes a structured
        // reject via @errorName — token names match executor's variants
        // verbatim, so consumers can pattern-match against the
        // documented set without policy_runtime.zig owning a per-variant
        // switch table that drifts when the executor grows new errors.
        const ok = executor.execute(&ctx) catch |err| {
            return .{
                .ok = false,
                .gas = @as(u64, pda.opcount),
                .host_calls = &.{},
                .rejection_code = @errorName(err),
                .rejection_detail = null,
            };
        };

        return .{
            .ok = ok,
            .gas = @as(u64, pda.opcount),
            // Phase 1: OP_CALLHOST audit trail not yet captured.  Phase 2
            // lands the Wright-style auditable-transition log (design
            // doc §0 #4 + §7).
            .host_calls = &.{},
            .rejection_code = if (!ok) "verify_failed" else null,
            .rejection_detail = null,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests — exercise the seam end-to-end against the syntactic shim.
// Behavioural envelope:
//   - well-formed pushdata frames → ok = true, gas = opcount
//   - malformed pushdata          → ok = false, rejection_code populated
//   - empty bytes                 → ok = true, gas = 0 (degenerate)
//   - context shape compiles      → smoke test for the mirror
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn mkContext() PolicyContext {
    return .{
        .actor = .{ .cert_id = "test-cert", .capabilities = &[_]u32{} },
    };
}

test "PolicyRuntime.evaluate: well-formed pushdata stream returns ok=true" {
    var rt = PolicyRuntime.init(testing.allocator);
    // 0x01 = push 1 byte; 'a' = the byte.  One opcode, one stack push.
    const bytes = [_]u8{ 0x01, 'a' };
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(result.ok);
    try testing.expectEqual(@as(u64, 1), result.gas);
    try testing.expect(result.host_calls.len == 0);
    try testing.expect(result.rejection_code == null);
}

test "PolicyRuntime.evaluate: empty policy bytes — degenerate but ok (syntactic shim path)" {
    // C10 PR-2e (2026-05-28): explicit .syntactic_shim mode — under
    // .real_executor an empty script means the stack is empty at exec
    // end, which the 2-PDA reads as false-top-of-stack → verify_failed.
    // The shim's "no bytes = nothing to invalidate = ok" semantic is the
    // backward-compat fallback this test asserts.
    var rt = PolicyRuntime.initWithMode(testing.allocator, .syntactic_shim);
    const result = try rt.evaluate(&.{}, mkContext());
    try testing.expect(result.ok);
    try testing.expectEqual(@as(u64, 0), result.gas);
    try testing.expect(result.host_calls.len == 0);
}

test "PolicyRuntime.evaluate: truncated pushdata returns ok=false with rejection_code" {
    var rt = PolicyRuntime.init(testing.allocator);
    // 0x05 promises 5 bytes; only 2 follow.
    const bytes = [_]u8{ 0x05, 'a', 'b' };
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("invalid_pushdata", result.rejection_code.?);
}

test "PolicyRuntime.evaluate: PUSHDATA1 truncated → invalid_pushdata" {
    var rt = PolicyRuntime.init(testing.allocator);
    // 0x4C = PUSHDATA1; 0x05 = length; only 2 bytes follow.
    const bytes = [_]u8{ 0x4C, 0x05, 'a', 'b' };
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("invalid_pushdata", result.rejection_code.?);
}

test "PolicyRuntime.evaluate: context with co_actor compiles + threads through (syntactic shim path)" {
    // C10 PR-2e (2026-05-28): explicit .syntactic_shim mode — under
    // .real_executor OP_0 (0x00) pushes an empty bytestring (=false) onto
    // the stack → verify_failed at exec end.  The shim's "as long as
    // bytes parse, ok=true" semantic is the structural-smoke this test
    // asserts (the co_actor field is the actual subject under test —
    // proving the context shape compiles + threads through unchanged).
    var rt = PolicyRuntime.initWithMode(testing.allocator, .syntactic_shim);
    const ctx = PolicyContext{
        .actor = .{ .cert_id = "primary-cert", .capabilities = &[_]u32{ 1, 2 } },
        .co_actor = .{ .cert_id = "co-cert", .capabilities = &[_]u32{3} },
    };
    const bytes = [_]u8{0x00}; // OP_0 push
    const result = try rt.evaluate(&bytes, ctx);
    try testing.expect(result.ok);
}

// ─────────────────────────────────────────────────────────────────────
// PR-2b real-executor tests — exercise the 2-PDA executor through the
// PolicyRuntime seam.  Design doc §4 listed six cases; one of them
// (execution_limit) is architecturally unreachable under the PR-2b
// adapter and is intentionally not tested:
//
//   executor.MAX_SCRIPT_SIZE = 10_000 bytes × ≥1 byte per opcode caps
//   opcount at ~10_000, well below MAX_OPS_PER_EVAL = 500_000.  The
//   script_too_large gate fires first.  execution_limit only becomes
//   reachable if a future evaluateWithBudget() overload (out of scope
//   per design doc §7) lowers MAX_OPS_PER_EVAL below the script-size
//   ceiling.  Testing it today would test dead code.
//
// Five tests landed:
//   - accept (well-formed push + truthy → ok=true, gas counts opcodes)
//   - reject (verify_failed: explicit OP_FALSE leaves false on stack)
//   - reject (invalid_pushdata: truncated PUSHDATA1 — wire-compat with
//     the syntactic shim's identical token, so PR #641 cell_handler
//     fixtures keep working through Phase 2)
//   - reject (script_too_large: payload > MAX_SCRIPT_SIZE)
//   - backend isolation: consecutive evaluate() calls don't share
//     PDA/arena state (each call mints fresh)
// ─────────────────────────────────────────────────────────────────────

test "PolicyRuntime.evaluate(.real_executor): accept — push + truthy top-of-stack" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // 0x51 = OP_1 — pushes a single 0x01 byte (truthy).  One opcode.
    const bytes = [_]u8{0x51};
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(result.ok);
    try testing.expect(result.gas >= 1);
    try testing.expect(result.host_calls.len == 0);
    try testing.expect(result.rejection_code == null);
}

test "PolicyRuntime.evaluate(.real_executor): reject — OP_FALSE → verify_failed" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // 0x00 = OP_FALSE.  Pushes empty/zero — top-of-stack untruthy at end.
    const bytes = [_]u8{0x00};
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime.evaluate(.real_executor): reject — truncated pushdata wire-compat" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // 0x05 = push 5 bytes; only 2 follow.  Same fixture the
    // .syntactic_shim test on line ~227 uses — token MUST match so
    // PR #641 cell_handler tests keep passing through any future flip.
    const bytes = [_]u8{ 0x05, 'a', 'b' };
    const result = try rt.evaluate(&bytes, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("invalid_pushdata", result.rejection_code.?);
}

test "PolicyRuntime.evaluate(.real_executor): reject — script_too_large beyond MAX_SCRIPT_SIZE" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // executor.MAX_SCRIPT_SIZE = 10_000; loadScript rejects > that.
    const oversize = try testing.allocator.alloc(u8, 10_001);
    defer testing.allocator.free(oversize);
    @memset(oversize, 0x00);
    const result = try rt.evaluate(oversize, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("script_too_large", result.rejection_code.?);
    try testing.expectEqual(@as(u64, 0), result.gas);
}

test "PolicyRuntime.evaluate(.real_executor): backend isolation across consecutive calls" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // First call: well-formed accept.  Second call: explicit reject.
    // If PDA/arena state leaked between calls (e.g. shared opcount),
    // the second call's gas or rejection_code would be polluted.
    const accept = [_]u8{0x51}; // OP_1
    const r1 = try rt.evaluate(&accept, mkContext());
    try testing.expect(r1.ok);

    const reject = [_]u8{0x00}; // OP_FALSE → verify_failed
    const r2 = try rt.evaluate(&reject, mkContext());
    try testing.expect(!r2.ok);
    try testing.expectEqualStrings("verify_failed", r2.rejection_code.?);

    // Third call: confirm we can still accept after a reject (PDA reset).
    const r3 = try rt.evaluate(&accept, mkContext());
    try testing.expect(r3.ok);
}

test "PolicyRuntime.init defaults to .real_executor (C10 PR-2e)" {
    // PR-2e (2026-05-28): the default backend is now the cell-engine
    // 2-PDA executor, not the syntactic shim.  cell_handler (PR-2c) and
    // cells_mint_handler (PR-2d) explicitly call initWithMode(.real_executor);
    // any UNKNOWN consumer that calls plain init() now gets real semantic
    // enforcement instead of frame-validation.  .syntactic_shim stays
    // callable via initWithMode for fallback per
    // POLICY-RUNTIME-EXECUTOR-ADAPTER.md §7.
    const rt = PolicyRuntime.init(testing.allocator);
    try testing.expectEqual(PolicyRuntimeMode.real_executor, rt.mode);
}

test "PolicyRuntime.initWithMode(.syntactic_shim) — fallback path preserved" {
    // Even with the default flipped, callers can still opt back to the
    // syntactic shim explicitly.  This guards the kernel_zig.zig
    // fallback per adapter §7.
    const rt = PolicyRuntime.initWithMode(testing.allocator, .syntactic_shim);
    try testing.expectEqual(PolicyRuntimeMode.syntactic_shim, rt.mode);
}

test "PolicyRuntime: types mirror TS shape (compile-only)" {
    // Compile-time smoke test that the public types match the documented
    // shape and are usable from a cartridge handler.  If this test compiles,
    // the seam is consumable.
    var rt = PolicyRuntime.init(testing.allocator);
    _ = &rt;
    const _ctx: PolicyContext = .{
        .actor = .{ .cert_id = "x", .capabilities = &[_]u32{} },
    };
    _ = _ctx;
    const _res: PolicyResult = .{ .ok = true, .gas = 0 };
    _ = _res;
    const _hc: HostCallRecord = .{
        .name = "has-capability",
        .result = 1,
        .timestamp_us = 0,
    };
    _ = _hc;
}

// ─────────────────────────────────────────────────────────────────────
// §11.10 order 4b-1 — Rúnar substrate smoke
//
// Proves the load-bearing claim of the RUNAR-ZIG-INTEGRATION-EVAL.md
// memo: bytes the Rúnar compiler emits are executable by
// PolicyRuntime.evaluateReal unchanged.
//
// The hex bytes are a GOLDEN — produced once via the Rúnar Go-tier
// compiler at upstream commit d4c3b6e (icellan/runar, 2026-05-25)
// from this source:
//
//   package contracts
//   import "github.com/icellan/runar/packages/runar-go/runar"
//   type Always struct { runar.SmartContract }
//   func (c *Always) Verify() { runar.Assert(1 == 1) }
//
// Compiled with:
//   runar-go -source Always.runar.go -hex
//   → "5151517777"
//
// Trace:
//   0x51 OP_1   → stack [1]
//   0x51 OP_1   → stack [1, 1]
//   0x51 OP_1   → stack [1, 1, 1]
//   0x77 OP_NIP → stack [1, 1]
//   0x77 OP_NIP → stack [1]
//   → top-of-stack truthy → evaluateReal returns ok=true
//
// PR-4b-1 deliberately ships the golden inline (not via b.addRunArtifact)
// because Rúnar's compilers/zig binary uses post-0.15.2 Zig nightly
// APIs (std.process.Init, b.graph.io) that fail to build on our pinned
// Zig 0.15.2 toolchain.  The Go tier compiles fine but adds a Go
// toolchain dep to the brain build — out of scope this PR.  PR-4b-2
// will land the actual build integration once we pick between
// (a) waiting for Rúnar's Zig tier to support 0.15.2 stable,
// (b) embedding the Go compiler binary as a build artifact,
// (c) pre-compiling hex offline + checking in goldens (this PR's
//     pattern, scaled to real cartridges).
//
// Whichever wins, this test pins the wire-format claim: Rúnar's
// output ⊆ what evaluateReal accepts.
// ─────────────────────────────────────────────────────────────────────

test "PolicyRuntime.evaluate(.real_executor): accepts Rúnar-compiled `Always` predicate" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // Golden from runar-go -source Always.runar.go -hex
    // (see block comment above for provenance).
    const runar_hex_5151517777 = [_]u8{ 0x51, 0x51, 0x51, 0x77, 0x77 };
    const result = try rt.evaluate(&runar_hex_5151517777, mkContext());
    try testing.expect(result.ok);
    try testing.expectEqual(@as(u64, 5), result.gas);
    try testing.expect(result.rejection_code == null);
}

test "PolicyRuntime.evaluate(.real_executor): accepts Rúnar `value+1==42` arithmetic shape" {
    // Second golden from Rúnar Go tier, same commit d4c3b6e:
    //
    //   type HelloLit struct { runar.SmartContract }
    //   func (c *HelloLit) Verify(value runar.Int) {
    //       runar.Assert(value+1 == 42)
    //   }
    //
    // Compiled: runar-go -source HelloLit.runar.go -hex
    //   → "8b012a9c"
    //
    // Trace (with `value` pre-pushed):
    //   0x8B OP_1ADD            → increment value
    //   0x01 0x2A push 1 byte   → push 42 (0x2A)
    //   0x9C OP_NUMEQUAL        → 1 if equal else 0
    //
    // To exercise it through PolicyRuntime (which loads the predicate as
    // the lock_script with no unlock), we prepend an OP_PUSH of value=41
    // so the predicate has the input it expects.  In a real cartridge
    // the value would come from the unlock-script path or the cell
    // payload via OP_READPAYLOAD (Phase 2 — see design doc §2 D3).
    const runar_hex_8b012a9c = [_]u8{ 0x8B, 0x01, 0x2A, 0x9C };
    const push_41_then_runar = [_]u8{ 0x01, 41 } ++ runar_hex_8b012a9c;
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const result = try rt.evaluate(&push_41_then_runar, mkContext());
    try testing.expect(result.ok);
    try testing.expect(result.rejection_code == null);
}

test "PolicyRuntime.evaluate(.real_executor): Rúnar `value+1==42` rejects when value≠41" {
    // Negative-path counterpart — same Rúnar-emitted predicate, wrong
    // value.  Proves the predicate actually enforces the constraint
    // (not just that pushing+dropping happened to leave truthy).
    const runar_hex_8b012a9c = [_]u8{ 0x8B, 0x01, 0x2A, 0x9C };
    const push_99_then_runar = [_]u8{ 0x01, 99 } ++ runar_hex_8b012a9c;
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const result = try rt.evaluate(&push_99_then_runar, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

// ─────────────────────────────────────────────────────────────────────
// §11.10 order 4b-2 — Rúnar cartridge-author workflow smoke
//
// PR-4b-1 (#664) proved Rúnar-compiled hex bytes execute through
// evaluateReal when pasted inline.  These tests prove the *workflow*
// works end-to-end via the convention documented in
// docs/cartridge-author-guide-runar.md:
//
//   1. Author writes .runar.go source (offline, on their dev box)
//   2. Author runs `runar-go -source X -hex` (offline, Go tier)
//   3. Author commits BOTH source + .expected.hex into the tree
//   4. Brain @embedFiles the .expected.hex and runs it through
//      PolicyRuntime.evaluateReal — zero Rúnar/Go in the brain build
//
// Per Todd 2026-05-25: option (c) — "no need for go" — the brain
// stays toolchain-independent of Rúnar.  Diff review catches drift.
//
// The example used here is the range-check predicate at
// docs/examples/runar-policies/range_check.runar.go:
//
//   runar.Assert(amount > 0)
//   runar.Assert(amount <= 100)
//
// Compiled hex: 7600a0690164a1
//   76    OP_DUP                duplicate amount
//   00    OP_0                  push 0
//   a0    OP_GREATERTHAN        amount > 0 ? push 1 : 0
//   69    OP_VERIFY             abort if 0
//   0164  push(1 byte) 100
//   a1    OP_LESSTHANOREQUAL    amount <= 100 ? push 1 : 0
//
// The .hex + .runar.go pair lives at policies-demo/range_check.* (sibling
// to this file).  Per cartridge-author-guide-runar.md §4: when real
// cartridges author Rúnar policies, their .hex lives under their own
// cartridge tree, NOT under brain-core.  The policies-demo dir here is
// the canonical worked-example referenced by the author guide; it lives
// inside the brain because Zig 0.15's @embedFile rejects paths that
// cross the package boundary (proven by an earlier draft of this PR
// that put the example under docs/examples/ and failed to compile).
// ─────────────────────────────────────────────────────────────────────

const range_check_hex_blob = @embedFile("policies-demo/range_check.expected.hex");

fn decodeRangeCheckHex(allocator: std.mem.Allocator) ![]u8 {
    // Strip trailing newlines + any incidental whitespace, then
    // hex-decode.  Matches the documented author guide §2.5.
    const trimmed = std.mem.trim(u8, range_check_hex_blob, &std.ascii.whitespace);
    const out = try allocator.alloc(u8, trimmed.len / 2);
    errdefer allocator.free(out);
    _ = try std.fmt.hexToBytes(out, trimmed);
    return out;
}

/// Build `OP_PUSH(value) || policy_bytes` so the predicate has its
/// input.  In a real cartridge the value would arrive via the
/// unlock-script path (Phase 2; see POLICY-RUNTIME-EXECUTOR-ADAPTER.md
/// §2 D3) — for today's all-lock model we prepend the push.
fn buildRangeCheckScript(allocator: std.mem.Allocator, amount: u8) ![]u8 {
    const policy = try decodeRangeCheckHex(allocator);
    defer allocator.free(policy);
    var script = try allocator.alloc(u8, 2 + policy.len);
    script[0] = 0x01; // push next 1 byte
    script[1] = amount;
    @memcpy(script[2..], policy);
    return script;
}

test "PolicyRuntime: Rúnar range_check @embedFile golden — accepts amount in (0, 100]" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    // Three accepts spanning the range: 1 (lower bound), 50 (middle),
    // 100 (upper bound).
    for ([_]u8{ 1, 50, 100 }) |amount| {
        const script = try buildRangeCheckScript(testing.allocator, amount);
        defer testing.allocator.free(script);
        const result = try rt.evaluate(script, mkContext());
        try testing.expect(result.ok);
        try testing.expect(result.rejection_code == null);
    }
}

test "PolicyRuntime: Rúnar range_check rejects amount=0 with verify_failed (OP_VERIFY abort)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildRangeCheckScript(testing.allocator, 0);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(!result.ok);
    // amount=0 fails the first `amount > 0` check; OP_VERIFY pops the
    // resulting 0 and aborts mid-script with verify_failed.
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime: Rúnar range_check rejects amount=200 with trailing-false verify_failed" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildRangeCheckScript(testing.allocator, 200);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(!result.ok);
    // amount=200 passes `amount > 0` but fails `amount <= 100`;
    // top-of-stack at end is 0 → ok=false synthesised by evaluateReal
    // as verify_failed (the canonical "predicate said no" token).
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime: Rúnar range_check hex round-trip via @embedFile" {
    // Sanity: the embedded golden decodes to the documented 7-byte
    // sequence.  Catches an editor stripping the trailing newline
    // weirdly or a CRLF sneaking in.
    const bytes = try decodeRangeCheckHex(testing.allocator);
    defer testing.allocator.free(bytes);
    const expected = [_]u8{ 0x76, 0x00, 0xA0, 0x69, 0x01, 0x64, 0xA1 };
    try testing.expectEqualSlices(u8, &expected, bytes);
}

// ─────────────────────────────────────────────────────────────────────
// MNCA tile-tick monotonicity invariant — Rúnar + MNCA demo (2026-05-26)
//
// Closes Todd's "what can we do with Rúnar now and our MNCA?" question
// in something a third party can verify end-to-end:
//
//   policies-demo/mnca/tile_tick_advance.runar.go  ←  author writes
//     ↓  runar-go -source X -hex
//   policies-demo/mnca/tile_tick_advance.expected.hex  ←  Bitcoin Script
//     ↓  @embedFile
//   THIS TEST  ←  loads the bytes, runs through evaluateReal,
//                  asserts MNCA tile-step invariant
//
// The compiled hex is 3 bytes:
//   0x7c OP_SWAP    swap [prevTick, newTick] → [newTick, prevTick]
//   0x8b OP_1ADD    increment top → [newTick, prevTick + 1]
//   0x9c OP_NUMEQUAL pop 2, push 1 iff equal
//
// Invariant enforced: newTick == prevTick + 1 (strict-monotone tile
// step).  This is load-bearing for MNCA — skipping ticks orphans
// downstream snapshots; going backwards creates unmatched commitments.
//
// Once a cell carrying tile-tick fields is accepted by this predicate,
// it goes through cell_handler.handleCreate → AnchorEmitter →
// anchor_queue_writer → bun anchor-runner.ts → real BSV mainnet
// PushDrop tx committing the cell_hash + type_hash.  The full
// integration loop the anchor program (PRs #672/#673/#674) just closed.
// ─────────────────────────────────────────────────────────────────────

const tile_tick_advance_hex_blob = @embedFile("policies-demo/mnca/tile_tick_advance.expected.hex");

fn decodeTileTickAdvanceHex(allocator: std.mem.Allocator) ![]u8 {
    const trimmed = std.mem.trim(u8, tile_tick_advance_hex_blob, &std.ascii.whitespace);
    const out = try allocator.alloc(u8, trimmed.len / 2);
    errdefer allocator.free(out);
    _ = try std.fmt.hexToBytes(out, trimmed);
    return out;
}

/// Encode a Bitcoin Script integer push of a small unsigned value.
/// For the demo all our test inputs are 0..255 so a single byte +
/// `OP_PUSH(1)` prefix suffices.  Real tile ticks would need
/// CScriptNum encoding for values ≥ 128 (sign bit handling); leaving
/// that for the production runtime tick that wires this in.
fn pushSmallInt(buf: []u8, value: u8) usize {
    buf[0] = 0x01; // push next 1 byte
    buf[1] = value;
    return 2;
}

/// Build `OP_PUSH(prevTick) || OP_PUSH(newTick) || <tile_tick_advance>`
/// — the unlock-side pushes followed by the Rúnar-emitted predicate.
fn buildTileTickScript(
    allocator: std.mem.Allocator,
    prev_tick: u8,
    new_tick: u8,
) ![]u8 {
    const policy = try decodeTileTickAdvanceHex(allocator);
    defer allocator.free(policy);
    var script = try allocator.alloc(u8, 2 + 2 + policy.len);
    var off: usize = 0;
    off += pushSmallInt(script[off..], prev_tick);
    off += pushSmallInt(script[off..], new_tick);
    @memcpy(script[off..], policy);
    return script;
}

test "PolicyRuntime: MNCA tile-tick advance — accepts 5 → 6 (canonical happy path)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildTileTickScript(testing.allocator, 5, 6);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(result.ok);
    try testing.expect(result.rejection_code == null);
}

test "PolicyRuntime: MNCA tile-tick advance — accepts 0 → 1 (boundary)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildTileTickScript(testing.allocator, 0, 1);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(result.ok);
}

test "PolicyRuntime: MNCA tile-tick advance — rejects 5 → 5 (no-op, must advance)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildTileTickScript(testing.allocator, 5, 5);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime: MNCA tile-tick advance — rejects 5 → 7 (skip not allowed; must be +1)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildTileTickScript(testing.allocator, 5, 7);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime: MNCA tile-tick advance — rejects 5 → 4 (backward orphans downstream)" {
    var rt = PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const script = try buildTileTickScript(testing.allocator, 5, 4);
    defer testing.allocator.free(script);
    const result = try rt.evaluate(script, mkContext());
    try testing.expect(!result.ok);
    try testing.expectEqualStrings("verify_failed", result.rejection_code.?);
}

test "PolicyRuntime: MNCA tile-tick advance — embedded hex round-trip" {
    // Catches editor mangling (trailing newline / CRLF) of the
    // committed golden.  The Rúnar-emitted 3-byte minimal form is:
    const bytes = try decodeTileTickAdvanceHex(testing.allocator);
    defer testing.allocator.free(bytes);
    const expected = [_]u8{ 0x7C, 0x8B, 0x9C }; // OP_SWAP OP_1ADD OP_NUMEQUAL
    try testing.expectEqualSlices(u8, &expected, bytes);
}

```
