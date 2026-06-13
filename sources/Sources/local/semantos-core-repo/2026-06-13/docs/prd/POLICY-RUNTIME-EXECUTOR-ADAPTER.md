---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.681359+00:00
---

# PolicyRuntime → cell-engine executor adapter design

**Version**: 0.2 (design — Todd-decision pass)
**Date**: 2026-05-25
**Status**: DESIGN — gates §11.10 order 2e PR-2 (real executor backend swap)
**Master document**: [`UNIFICATION-ROADMAP.md` §11.10 v0.12](UNIFICATION-ROADMAP.md)
**Origin**: tick 16 of autonomous loop blocked on this gap; tick 17 (this doc) resolves it
**Prerequisite**: [`PRE-FLIGHT-EXECUTOR-WIRING.md`](PRE-FLIGHT-EXECUTOR-WIRING.md) PR-1 substrate (✓ shipped #649)
**Theoretical frame**: Craig Wright, *Scripted Supply* — Bitcoin Script as deterministic 2-PDA, predicate-based state transitions, canonical-schema-as-precondition. See §0.

---

## Headline (TL;DR)

The pre-flight audit assumed `executor.execute` was a `(bytes, context) → result` function. Actual signature is `pub fn execute(ctx: *ExecutionContext) ExecuteError!bool` — a stateful Bitcoin-script-style two-phase execution model. The PolicyRuntime → executor swap is NOT a one-line substitution; it's an adapter layer with 5 design decisions.

Good news: each decision has a clear winner, and `ExecutionContext` already provides `loadScript` / `loadUnlock` / `reset` helpers that absorb most of the boilerplate. **Estimated effort once this doc is approved: half-day for PR-2a scaffold + 1-2 days for PR-2b implementation.**

---

## §0 Why this work matters (Wright frame)

Todd 2026-05-25: *"this is getting into the realm of script so we need to bring this article into context."*

Craig Wright's *Scripted Supply* lays out four points that bear directly on the swap we're about to land:

1. **Bitcoin Script is a deterministic 2-PDA** (main stack + alt stack, deterministic transitions, no halting problem). That IS the `pda.PDA` struct at `core/cell-engine/src/pda.zig` — 1.5 MB main+aux stacks, `opcount` budget, deterministic `execute(ctx)` loop. The PolicyRuntime is *already* this machine downstream of `evaluate`; today's syntactic-shim path just refuses to walk it.

2. **Canonical schemas as preconditions.** Wright's `init_message` / `state_transition` (Ch. 6–7) are predicates over a normalized payload — the same shape as a Plexus opcode sequence operating on a 256-byte canonical cell header (per memory `cell_is_the_wire_format`). PR-2's job is to start *executing* the predicate, not just frame-validate it. The schema spine (per memory `semantos_canonical_schema_spine`) is the precondition layer; the executor is the predicate layer.

3. **State transitions are proofs**, not RPC calls. A successful `evaluate → ok=true` IS the proof the write is admissible — same shape as a UTXO unlock proving spend authority. This is why `tx_context = null` is a Phase 1 limitation (§2 D3) and not a design choice: a real `OP_CHECKSIG` over the cell write needs the cell to BE the tx-equivalent of a spend, which is the §11.10 order 3a "anchor every cell" story (✓ seam shipped #643, real backend = task #16).

4. **Predicate composition over implementation polymorphism.** Wright's argument against EDI's "everyone codes their own validator" is exactly the case against per-cartridge brain primitives. The PolicyRuntime seam (one brain, many cartridges per Todd 2026-05-25) IS the composition surface — cartridges supply opcode-byte preconditions; the brain enforces them through one canonical 2-PDA. **This is why PR-2 is load-bearing for Bridget's "L2+L3 unwired" review item**: the kernel-enforcement gate stops being syntactic the moment `evaluateReal` runs predicates.

What this changes in the design:
- §2 D3's "Phase 1 ignores fields" stays — Wright's frame *reinforces* the discipline: don't half-wire the canonical-payload translator; ship the deterministic-2-PDA path first, layer payload-driven predicates in Phase 2 when a consumer (intent_cells with sigs) needs them.
- §3 sketch's `rejection_code = "verify_failed"` for `ok=false` is the canonical "state transition not admissible" return. Keep verbatim.
- Future work named in §7 ("HostCallRecord for OP_CALLHOST audit trail") is the Wright-style auditable-transition log — surface for cartridges to consume.

---

## §1 The gap (what tick 16 discovered)

Two surfaces that don't line up:

**PolicyRuntime.evaluate** (brain seam, TS-mirror shape):
```zig
pub fn evaluate(
    self: *PolicyRuntime,
    policy_bytes: []const u8,
    context: PolicyContext,
) PolicyRuntimeError!PolicyResult
```
Takes opaque opcode bytes + context (actor, co_actor, fields). Returns structured ok / gas / host_calls / rejection_code.

**executor.execute** (cell-engine native, Bitcoin-script shape):
```zig
pub fn execute(ctx: *ExecutionContext) ExecuteError!bool
```
Takes a stateful ExecutionContext containing pre-loaded unlock + lock scripts, a PDA (the 2-PDA stacks), an arena allocator, and an optional tx_context for sighash ops. Returns true iff top-of-stack is truthy.

`ExecutionContext` shape (from [`core/cell-engine/src/executor.zig:77`](../../core/cell-engine/src/executor.zig#L77)):

| Field | Type | Notes |
|---|---|---|
| `pda` | `*pda_mod.PDA` | 1.5 MB main+aux stacks; use `initInPlace` to avoid stack-overflow on alloc |
| `arena` | `*allocator_mod.ScriptArena` | bump allocator for script-temporary allocations |
| `tx_context` | `?*const sighash.TxContext` | optional; needed only for `OP_CHECKSIG` etc. |
| `lock_script` | `[MAX_SCRIPT_SIZE]u8` | pre-loaded via `loadScript(bytes)` |
| `unlock_script` | `[MAX_SCRIPT_SIZE]u8` | pre-loaded via `loadUnlock(bytes)`; default len 0 skips phase |
| `pc`, `current_phase`, `condition_stack` | various | execution state — `reset()` clears |

`ExecutionContext` provides `init(pda, arena)` + `loadScript` + `loadUnlock` + `reset` + `currentScript` helpers, so per-call wiring is light.

---

## §2 Five design decisions

### D1. Script split — how to load `policy_bytes` into executor's two-phase model

**Recommendation: (a) all-lock.** Treat the whole `policy_bytes` as the lock script; leave unlock empty.

Rationale: A policy precondition semantically IS the gate ("evaluate this script; if it ends with truthy top-of-stack, the cell write proceeds"). The unlock script in Bitcoin convention is the witness/proof side — a cell-write doesn't have a "witness" to push first; the cell content itself is what's being gated. Default `unlock_script_len = 0` skips the unlock phase entirely (per `execute`'s `if (ctx.unlock_script_len > 0)` guard at line 165), so all-lock is a clean fit.

The `loadScript` helper at line 128 already loads into lock_script. No transform needed.

**Future**: if a cartridge wants unlock+lock semantics (e.g., a cell that's both a commitment AND a proof — typical for capability UTXOs per BRC-108), extend `PolicyContext` with an optional `unlock_bytes: ?[]const u8` field. Defer until a real consumer demands it.

### D2. PDA + arena lifecycle — alloc per call or reuse

**Recommendation: per-call alloc (heap-resident via `initInPlace`).** Each `PolicyRuntime.evaluate` constructs fresh PDA + arena, executes, drops.

Rationale:
- PDA is 1.5 MB — too large for the stack (per `initInPlace`'s rationale). Heap-allocate via `allocator.create(PDA)` + `initInPlace(max_ops)`.
- Per-call freshness ensures no state leak between evaluations. Single-threaded reactor (per memory `semantos_brain_single_threaded_reactor`) means no concurrency penalty.
- Cost: ~1.5 MB heap allocation per evaluate. For cell.create + intent_cells.submit paths (low-frequency, single-cell writes), this is acceptable. If a hot-path consumer emerges (e.g., bulk re-evaluation), revisit with a per-PolicyRuntime PDA pool.
- ScriptArena: same pattern. Caller-supplied buffer (e.g., a 64 KB ArrayList from the per-call allocator).

```zig
// Sketch
const pda_buf = try allocator.create(pda_mod.PDA);
defer allocator.destroy(pda_buf);
pda_buf.initInPlace(MAX_OPS_PER_EVAL);  // e.g. 10_000

const arena_buf = try allocator.alloc(u8, ARENA_SIZE);
defer allocator.free(arena_buf);
var arena = allocator_mod.ScriptArena.init(arena_buf);

var ctx = executor.ExecutionContext.init(pda_buf, &arena);
try ctx.loadScript(policy_bytes);
const ok = executor.execute(&ctx) catch |err| ...;
```

**Constants (Todd-confirmed 2026-05-25)**:
- `MAX_OPS_PER_EVAL = 500_000` — matches `executor.DEFAULT_MAX_OPS` at `core/cell-engine/src/executor.zig:25`. Todd asked "is 10K enough or should it be 1m?" — the canonical answer is 500K (half-mil, the executor's own default). Not arbitrary; if a future cartridge needs more, raise it per-call via a future `PolicyRuntime.evaluateWithBudget` overload (out of scope this PR).
- `MAX_SCRIPT_SIZE = 10_000` — fixed by `executor.MAX_SCRIPT_SIZE`; `loadScript` rejects larger inputs with `error.script_too_large`. Adapter surfaces this as `rejection_code = "script_too_large"`.
- `ARENA_SIZE = 64 KB` — matches the TS wrapper's IO_SCRIPT region. Brain-side has no WASM memory constraint, but 64 KB is plenty for Phase 1 script-temporary allocations and keeps cross-language parity for debugging.

### D3. PolicyContext → cell-payload / tx-context translation

**Correction (Todd 2026-05-25)**: there is no `OP_LOADFIELD` in the cell-engine — I hallucinated that name. The real payload-reading opcode is **`OP_READPAYLOAD` (0xCC)** at `core/cell-engine/src/opcodes/plexus.zig:396`, which reads bytes from a CELL PAYLOAD region (not a key-value map). The Plexus precondition family is `OP_CHECKLINEARTYPE` (0xC0), `OP_CHECKAFFINETYPE` (0xC1), `OP_CHECKRELEVANTTYPE` (0xC2), `OP_CHECKCAPABILITY` (0xC3), `OP_CHECKIDENTITY` (0xC4), `OP_CHECKDOMAINFLAG` (0xC6), `OP_CHECKTYPEHASH` (0xC7).

**Recommendation: minimal first cut — pass `tx_context = null`, ignore `PolicyContext.fields`.** Document as "Phase 1 of real-executor wiring: no `OP_READPAYLOAD` / `OP_CHECKSIG` / `OP_CHECK*TYPE` host-context wiring."

Rationale: PolicyContext.fields exists in the TS shape (mirroring the canonical interface) but isn't wired into the syntactic shim today. Even with full implementation, the field-loading model would need translation (e.g., serialize PolicyContext.fields into a synthetic cell payload before evaluate, then expose it via the executor's payload-region pointer for `OP_READPAYLOAD` references).

For the FIRST consumer (Todd 2026-05-25: **`intent_cells_handler.zig`**, swapped from earlier `cell_handler` recommendation — "every intent trace has only shown one opcode in smokes" so the conformance surface is small and predictable), the existing scripts are minimal pushdata+OP_VERIFY shapes; `OP_READPAYLOAD` / `OP_CHECK*TYPE` references would fail at execution time, but no current test fixture exercises them. Acceptable Phase 1 limitation.

`tx_context = null` means `OP_CHECKSIG` and other sighash-requiring ops fail. Same Phase 1 trade — current intent_cells preconditions don't invoke them.

**Phase 2** (deferred follow-up, post-PR-2b): build the synthetic-cell-payload translator from `PolicyContext.fields` + supply `tx_context` for sighash ops. This is load-bearing for the §11.10 order 3a "real anchor backend" task (#16) because the cell-anchor tx IS what `OP_CHECKSIG` needs to verify against — Wright frame §0 #3.

### D4. ExecuteError → PolicyResult.rejection_code mapping

**Recommendation: static enum-name → token table.** One-to-one mapping; tokens stable across backend versions.

From `core/cell-engine/src/executor.zig:27` `ExecuteError`:
- `stack_overflow` → `"stack_overflow"`
- `stack_underflow` → `"stack_underflow"`
- `execution_limit` → `"execution_limit"`
- `verify_failed` → `"verify_failed"` (the canonical "policy said no" case)
- `disabled_opcode` → `"disabled_opcode"`
- `invalid_opcode` → `"invalid_opcode"`
- `invalid_script` → `"invalid_script"`
- `invalid_pushdata` → `"invalid_pushdata"` (matches syntactic shim's token — wire-compatible)
- `nesting_depth_exceeded` → `"nesting_depth_exceeded"`
- `invalid_sighash` → `"invalid_sighash"`

Plus PolicyRuntime-internal failures:
- Allocator OOM during PDA/arena setup → `PolicyRuntimeError.backend_infrastructure_error` (existing path)
- `script_too_large` from `loadScript` (>MAX_SCRIPT_SIZE) → `"script_too_large"` (new rejection_code)
- `ok=false` with no error thrown (executor returned `false` for "top of stack not truthy") → `"verify_failed"` (synthetic for the explicit-reject case)

Wire compat: `"invalid_pushdata"` is the only token both the syntactic shim and the real executor emit. Existing intent_cells conformance tests asserting `rejection_code = "invalid_pushdata"` keep working through the swap.

### D5. Gas extraction

**Recommendation: read `ctx.pda.opcount` after execution.** Map to `PolicyResult.gas` directly.

Per `core/cell-engine/src/pda.zig:71` the PDA tracks `opcount: u32`. Same semantic as the syntactic shim's `opcount` (number of opcodes consumed). `PolicyResult.gas` is u64; widen on assignment, no precision loss.

**Stack depth** (the dropped field from the syntactic shim era — see intent_cells_handler.zig stack_depth=0 sentinel) reappears: `ctx.pda.main_sp` final value is the main-stack depth at execution end. Available for diagnostics but not currently surfaced through PolicyResult. Future enhancement when intent_cells_handler swaps to real executor and drift analysis wants stack visibility back.

---

## §3 Adapter sketch (what PR-2b implements)

```zig
// runtime/semantos-brain/src/policy_runtime.zig

const executor = @import("executor");
const pda_mod = @import("pda");
const allocator_mod = @import("allocator");

pub const PolicyRuntimeMode = enum {
    /// Phase-3 syntactic shim (existing default).  Frame validation only.
    syntactic_shim,
    /// Real cell-engine 2-PDA executor (§11.10 order 2e).  Per-call PDA
    /// + arena, all-lock script load, no tx_context (Phase 1; see
    /// POLICY-RUNTIME-EXECUTOR-ADAPTER.md §2 D3).
    real_executor,
};

const MAX_OPS_PER_EVAL: u32 = 500_000;  // matches executor.DEFAULT_MAX_OPS
const ARENA_SIZE: usize = 64 * 1024;

pub const PolicyRuntime = struct {
    allocator: std.mem.Allocator,
    mode: PolicyRuntimeMode,

    pub fn init(allocator: std.mem.Allocator, mode: PolicyRuntimeMode) PolicyRuntime { ... }

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

    fn evaluateShim(...) { /* existing kernel_zig path unchanged */ }

    fn evaluateReal(
        self: *PolicyRuntime,
        policy_bytes: []const u8,
        context: PolicyContext,
    ) PolicyRuntimeError!PolicyResult {
        _ = context;  // Phase 1: tx_context = null, fields ignored (see D3)

        const pda = self.allocator.create(pda_mod.PDA) catch
            return PolicyRuntimeError.backend_infrastructure_error;
        defer self.allocator.destroy(pda);
        pda.initInPlace(MAX_OPS_PER_EVAL);

        const arena_buf = self.allocator.alloc(u8, ARENA_SIZE) catch
            return PolicyRuntimeError.backend_infrastructure_error;
        defer self.allocator.free(arena_buf);
        var arena = allocator_mod.ScriptArena.init(arena_buf);

        var ctx = executor.ExecutionContext.init(pda, &arena);
        ctx.loadScript(policy_bytes) catch {
            return .{
                .ok = false,
                .gas = 0,
                .host_calls = &.{},
                .rejection_code = "script_too_large",
                .rejection_detail = null,
            };
        };

        const ok = executor.execute(&ctx) catch |err|
            return .{
                .ok = false,
                .gas = pda.opcount,
                .host_calls = &.{},
                .rejection_code = errorTokenFor(err),
                .rejection_detail = null,
            };

        return .{
            .ok = ok,
            .gas = pda.opcount,
            .host_calls = &.{},  // Phase 1: no OP_CALLHOST audit trail
            .rejection_code = if (!ok) "verify_failed" else null,
            .rejection_detail = null,
        };
    }
};

fn errorTokenFor(err: executor.ExecuteError) []const u8 {
    return switch (err) {
        error.stack_overflow => "stack_overflow",
        error.stack_underflow => "stack_underflow",
        error.execution_limit => "execution_limit",
        error.verify_failed => "verify_failed",
        error.disabled_opcode => "disabled_opcode",
        error.invalid_opcode => "invalid_opcode",
        error.invalid_script => "invalid_script",
        error.invalid_pushdata => "invalid_pushdata",
        error.nesting_depth_exceeded => "nesting_depth_exceeded",
        error.invalid_sighash => "invalid_sighash",
    };
}
```

**First consumer (Todd-confirmed): `intent_cells_handler.zig`** — its existing PolicyRuntime construction stays `PolicyRuntime.init(allocator, .syntactic_shim)` until PR-2b flips it to `.real_executor`. `cell_handler.zig` stays on `.syntactic_shim` through PR-2b and gets the flip in deferred PR-2c (the order swap from v0.1 is intentional — intent_cells smoke fixtures are simpler and more predictable than cell_handler's opcode_bytes_b64 path).

---

## §4 Test strategy

**Existing test coverage that should keep passing through PR-2b:**
- `policy_runtime.zig` inline tests for the syntactic-shim path (7 tests from PR #639) — unchanged.
- `cell_handler.zig` inline tests for opcode_bytes_b64 reject path (PR #641) — stays on `.syntactic_shim` through PR-2b (Todd swap); unchanged.
- `intent_cells_handler` conformance tests — flips to `.real_executor` in PR-2b. Smoke fixtures use minimal pushdata+OP_VERIFY shapes; should pass against real executor IF malformed pushdata also fails real-executor frame validation. **Triage per-failure during PR-2b**.

**New tests to add in PR-2b:**
- Real-executor accept: well-formed push + true → ok=true, gas counts opcodes
- Real-executor reject (verify_failed): script ends with false top-of-stack → ok=false, rejection_code="verify_failed"
- Real-executor reject (invalid_pushdata): truncated pushdata → ok=false, rejection_code="invalid_pushdata" (wire-compatible with syntactic shim)
- Real-executor execution_limit: script exceeds MAX_OPS_PER_EVAL → ok=false, rejection_code="execution_limit"
- script_too_large: payload > MAX_SCRIPT_SIZE → ok=false, rejection_code="script_too_large"
- Backend isolation: two consecutive evaluate() calls don't share state (PDA was re-init'd)

**Audit §5 R3 risk acknowledged**: existing test fixtures that pass under the syntactic shim may fail under real executor (executor enforces semantics the shim didn't). Triage per-failure per Todd's confirmed policy: bias toward "fixture is buggy, fix fixture."

---

## §5 PR sequencing

**PR-2a (~half day, this is the next tick after this doc lands)**:
- Add `PolicyRuntimeMode` enum to `policy_runtime.zig`
- Add `evaluateReal` STUB returning `PolicyRuntimeError.backend_infrastructure_error` with `rejection_code = "real_executor_not_wired_yet"`
- Wire `ce_executor_mod` into `policy_runtime_mod` imports; remove `_ = ce_executor_mod;` discard from PR #649
- No consumer changes — all callers still use `.syntactic_shim` mode
- 1 inline test confirming `.real_executor` mode returns the stub token
- Lands the substrate without behavioral risk; reviewer can see the seam shape before the real swap

**PR-2b (~1-2 days)**:
- Implement `evaluateReal` per §3 sketch
- Flip **`intent_cells_handler.zig`**'s PolicyRuntime construction to `.real_executor` (Todd-confirmed first consumer)
- Add 6 new inline tests per §4
- Triage any test failures per audit §5 R3 policy
- Document Phase 1 limitations (no tx_context, no `OP_READPAYLOAD` payload-region wiring) inline

**PR-2c (deferred, optional follow-up)**:
- Switch `cell_handler.zig` to `.real_executor` mode
- Its opcode_bytes_b64 path is the more arbitrary surface — let intent_cells soak first
- Lands when PR-2b has soaked

---

## §6 Todd decisions (resolved 2026-05-25)

All gating questions answered. PR-2a is clear to land.

1. **D1-D5 confirmed** as written. D3 stays Phase 1 (no tx_context / no `OP_READPAYLOAD` payload-region wiring) — Wright frame §0 #3 reinforces the discipline (ship deterministic-2-PDA path first, layer payload predicates when a consumer demands them).

2. **`MAX_OPS_PER_EVAL = 500_000`** (matches `executor.DEFAULT_MAX_OPS`). Not arbitrary — the executor's canonical default. Future per-call overrides can land via a `evaluateWithBudget` overload if a cartridge needs a different ceiling.

3. **`ARENA_SIZE = 64 KB`** confirmed.

4. **First consumer = `intent_cells_handler`** (swapped from earlier cell_handler recommendation). Todd: "every intent trace has only shown one opcode in smokes" — small predictable conformance surface for the first real-executor flip. `cell_handler` moves to PR-2c.

5. **`OP_LOADFIELD` correction acknowledged** — that opcode doesn't exist; I hallucinated it. Real Plexus predicate family is `OP_CHECK*TYPE` (0xC0–0xC7); real payload-read opcode is `OP_READPAYLOAD` (0xCC). Inline references corrected in this revision.

**Wright frame integration (§0 added)** — `OP_CALLHOST` host-call audit-trail (HostCallRecord) is now explicitly named as the Wright-style auditable-transition log; surfaced as Phase 2 work in §7.

---

## §7 Out of scope (named so it doesn't scope-creep)

- Per-PolicyRuntime PDA pool for hot-path consumers — defer until a hot path emerges
- OP_LOADFIELD wiring from PolicyContext.fields — Phase 2 (when intent_cells_handler swaps)
- OP_CHECKSIG wiring via tx_context — Phase 2
- Stack-depth surfacing through PolicyResult — diagnostic enhancement, post-PR-2c
- HostCallRecord population (OP_CALLHOST audit trail) — Phase 2 when CDM/SCADA-equivalent cartridges land on the brain
- Retiring kernel_zig.zig — explicitly kept as fallback per pre-flight §7 #1 + Todd 2026-05-25
