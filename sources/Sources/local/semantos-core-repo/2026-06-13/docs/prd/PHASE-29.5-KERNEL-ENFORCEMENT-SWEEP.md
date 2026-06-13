---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.697664+00:00
---

# Phase 29.5 — Kernel Enforcement Sweep for Extension Grammars

**Version**: 0.1 (draft)
**Date**: April 2026
**Status**: TS-side substrate shipped (`packages/policy-runtime/` + CDM/SCADA prototype consumers). **Per Todd 2026-05-25: CDM/SCADA were prototypes exploring extension-grammar shape, NOT load-bearing.** Real implementation site reframed to the brain's Zig write path — see [UNIFICATION-ROADMAP.md §11.10](UNIFICATION-ROADMAP.md). This PRD is kept as the **design reference** for what a kernel-enforcement substrate looks like; the Zig analogue (`runtime/semantos-brain/src/policy_runtime.zig`, to-build) mirrors the TS shape so a future real CDM or SCADA cartridge consuming the brain substrate plugs in via the same conceptual interface.
**Duration**: 4 weeks (with 40% buffer: 5.6 weeks)
**Prerequisites**: Phase 17 complete (transfer). Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry). Phase 28 complete (CDM package shipped). Phase 29 complete (SCADA package shipped). Phase 14–17 Plexus adapter available.
**Blocks**: Phase 32 (Bills of Lading) and any future extension grammar that wants to claim opcode-level enforcement or anchor-tx emission.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md`
**Branch**: `phase-29.5-kernel-enforcement-sweep`
**Siblings in sweep family**: Phase 25.5 (OP_CALLHOST dispatch sweep) · Phase 25.6 (opcode surface sweep)

---

## Context

Phase 28 (CDM) and Phase 29 (SCADA) both landed with compression-gradient diagrams that read:

```
Lisp policy → bytecode → 2-PDA evaluation → Plexus anchor tx
```

Only the first two arrows are currently true. An honest walk through the code shows three concrete gaps, and all three are the same gaps for CDM, SCADA, and any future extension grammar:

### Gap 1 — Compiled policy bytecode never reaches the 2-PDA

`packages/cdm/src/lifecycle.ts` `executeEvent()` builds cell headers via `buildCellHeader`, packs cells via `packCell`, and returns the bytes. It does not call the WASM cell engine's `executeScript` export. State transitions are gated by the TypeScript `transitionTable`, not by opcode evaluation. The Lean K1–K5 / K7 kernel invariants therefore do not cover the lifecycle path — only the packing path.

`.claude/worktrees/friendly-kirch/packages/scada/src/policies/host-functions.ts` is explicit in its comment at line 57: *"In a full implementation, this would invoke the WASM cell engine's 2-PDA with the policy's compiled bytecode. Here we evaluate the policy constraints directly using the same semantics."* The actual evaluator is `evaluatePolicyScriptWords()`, which regex-parses the human-readable `scriptWords` field on an `InterlockPolicy` and interprets the constraints in TypeScript. The compiled `cellBytes` field is produced and then ignored at runtime.

Consequence: every "rejected at the opcode level" claim in the Phase 28 and Phase 29 docs is currently a claim about a TypeScript shim that mirrors the intended opcode semantics. The shim and the kernel are kept in sync by hand.

### Gap 2 — Host predicates live in two disconnected registries

Phase 25.5 shipped a real `HostFunctionRegistry` class (`packages/cell-engine/bindings/host-functions.ts`) whose entries are dispatched from the Zig `OP_CALLHOST` opcode (`packages/cell-engine/src/opcodes/hostcall.zig`). Predicates registered here are visible to the kernel.

CDM and SCADA each ship their own host-predicate layer:

- CDM: `counterparty-default-status`, `time-before?`, `has-capability` — referenced in `.policy` files but not registered with `HostFunctionRegistry`.
- SCADA: `sensor-reading`, `sensor-quality`, `dual-auth`, `has-capability` — surfaced as `TelemetryStateProvider` / `DualAuthProvider` TypeScript interfaces and consumed by the TypeScript evaluator, not registered with the kernel-facing registry.

Consequence: if a CDM or SCADA `.policy` were actually run through the 2-PDA today, `OP_CALLHOST` would fire against an unpopulated registry and the kernel would return `ERR_UNKNOWN_HOST_FN`.

### Gap 3 — Plexus adapter is not wired to terminal events

Phase 14–17 built the Plexus adapter (`packages/plexus-vendor-sdk/`). Phase 18 built the metering control plane. Neither CDM nor SCADA emits anchor transactions on terminal events. `executeEvent` returns the packed cell bytes and stops. There is no call site that hands those bytes to the Plexus adapter for signing, BEEF assembly, and broadcast. The "regulatory report emitted automatically" and "audit cell in historian DAG" arrows in the compression gradients are aspirational.

Consequence: a CDM trade settlement or a SCADA emergency shutdown produces an in-memory cell. Nothing is written to a tamper-evident external substrate, and nothing outside the process can verify that the event happened.

---

## Why This Must Be a Standalone Phase

These three gaps are not CDM-specific or SCADA-specific. Fixing them inside CDM or inside SCADA means fixing them twice, inconsistently, and then a third time for BoL (Phase 32), a fourth time for whatever domain grammar comes after that, and so on. The fix belongs in a shared sweep phase that closes the gap once at the boundary between extension grammars and the kernel, after which every existing and future grammar rides along for free.

This phase is therefore a prerequisite for:

- Any future claim that a grammar enforces at the opcode level.
- Any future claim that Lean K1–K5 / K7 cover the lifecycle path.
- Any future claim that a terminal event produces an anchor tx.
- Phase 32 (Bills of Lading). The BoL success criteria explicitly require opcode-level enforcement of `single-negotiable-instance` and `present-before-deliver`. Those criteria cannot be honestly asserted until this sweep lands.

### Generalisation targets beyond CDM/SCADA

**Reframed 2026-05-25 (status reconciliation header above).** The Zig brain has the same three gaps as the TS prototype consumers, but the resolution is a Zig-side analogue of `PolicyRuntime`, not a wired consumer of the TS package:

- **`runtime/semantos-brain/src/cell_handler.zig`** — the generic `cell.create` path. JSON payload → `entity_cell.encodeCell` → LMDB, zero kernel involvement. Linearity labels like `"LINEAR"` / `"RELEVANT"` are stored as JSON strings, not enforced.
- **`runtime/semantos-brain/src/resources/intent_cells_handler.zig`** (oddjobz). Step 6 calls `kernel_zig.executeOpcodeBytes`, a Phase-3 syntactic shim — frame validation only, not 2-PDA semantic execution.
- **Future `cartridges/oddjobz/brain/` after [D-LIFT-ODDJOBZ.md](D-LIFT-ODDJOBZ.md).** The carve relocates files; the Zig `PolicyRuntime` seam (order 2b in §11.10) is what closes the enforcement gap.

[UNIFICATION-ROADMAP.md §11.10](UNIFICATION-ROADMAP.md) tracks the Zig program's order. The argument from "Why This Must Be a Standalone Phase" applies unchanged: closing the gap once at the substrate boundary covers all of them.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `KERNEL:EXEC` | `packages/cell-engine/src/executor.zig` | `executeScript` entry point — the function we need to reach |
| `KERNEL:HOSTCALL` | `packages/cell-engine/src/opcodes/hostcall.zig` | `OP_CALLHOST` Zig implementation — the dispatch we need to land in |
| `BINDINGS:WASM` | `packages/cell-engine/bindings/` | Bun + browser WASM binding layer — where we call from |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | `HostFunctionRegistry` class — where predicates must land |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Reference implementation of correct registration |
| `CDM:LIFECYCLE` | `packages/cdm/src/lifecycle.ts` | Current TS-only lifecycle engine — call site to rewire |
| `CDM:POLICIES` | `packages/cdm/src/policies/compiler.ts` | Where CDM policies are compiled; host fn list is implicit in the .policy bodies |
| `SCADA:AUTH` | `packages/scada/src/authorization.ts` | Current TS-only command authorization engine — call site to rewire |
| `SCADA:INTERLOCKS` | `packages/scada/src/policies/interlocks.ts` | Where SCADA policies are compiled |
| `SCADA:HOSTFN` | `packages/scada/src/policies/host-functions.ts` | Current TS evaluator — the thing being replaced |
| `PLEXUS:ADAPTER` | `packages/plexus-vendor-sdk/` | Plexus signing / broadcast surface |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Transfer primitive — already integrated with the kernel, a reference for how to integrate |
| `LEAN:K1-K5` | `proofs/lean/Semantos/Theorems/` | Kernel invariants — scope note update is a deliverable |

---

## Deliverables

### D29.5.1 — Shared `PolicyRuntime` helper

**File**: `packages/policy-runtime/src/index.ts` (new package)

One small package that every extension grammar calls into. Thin wrapper that:

1. Takes a compiled capability cell (`Uint8Array` — output of `packCapabilityCell`) and a runtime context.
2. Invokes the WASM engine's `executeScript` export with the cell's script body and a populated host-function registry handle.
3. Returns a `PolicyResult` with:
   - `ok: boolean` (did the 2-PDA reach `VERIFY` with a true top-of-stack?)
   - `gas: number` (opcodes consumed)
   - `hostCalls: Array<{ name: string; args: unknown[]; result: unknown }>` (audit trail of every `OP_CALLHOST` that fired)
   - `rejectionCode?: KernelErrorCode` (if `ok === false`, the opcode-level reason)

```typescript
export interface PolicyContext {
  /** Serialized runtime fields the policy can reference via OP_LOADFIELD */
  fields: Record<string, Uint8Array>;
  /** Identity facet performing the action */
  actor: { certId: string; capabilities: number[] };
  /** Optional second authorizer for dual-auth policies */
  coActor?: { certId: string; capabilities: number[] };
  /** Domain-specific host-function providers */
  hostFunctions: HostFunctionProvider[];
}

export interface PolicyResult {
  ok: boolean;
  gas: number;
  hostCalls: HostCallRecord[];
  rejectionCode?: KernelErrorCode;
  rejectionDetail?: string;
}

export class PolicyRuntime {
  constructor(private engine: CellEngine, private registry: HostFunctionRegistry) {}
  evaluate(policyCell: Uint8Array, context: PolicyContext): Promise<PolicyResult>;
}
```

Notes:

- The helper lives in its own package so that `@semantos/cdm`, `@semantos/scada`, and the future `@semantos/bol` can depend on it symmetrically, and so it can be tested in isolation.
- `hostCalls` is the audit trail. Every `OP_CALLHOST` dispatch appends one record. This is what downstream observability (loom inspector, regulator export, litigation hold) consumes.
- `gas` uses the existing opcode-consumption counter in the executor. Extension grammars get uniform metering cost reporting for free.

### D29.5.2 — Extension-grammar host-function registration

**Files**: `packages/cdm/src/policies/host-functions.ts` (new), `packages/scada/src/policies/host-functions.ts` (rewrite)

Each extension grammar exposes a single function:

```typescript
export function registerCDMHostFunctions(registry: HostFunctionRegistry): void;
export function registerSCADAHostFunctions(registry: HostFunctionRegistry): void;
```

These land the domain predicates in the same registry that `OP_CALLHOST` dispatches from. The registration is idempotent, parameterized by runtime providers (e.g. SCADA takes a `TelemetryStateProvider`, CDM takes a `CounterpartyDefaultProvider`), and goes through the same API `builtin-host-functions.ts` uses.

CDM predicate set (from the existing `.policy` files — union of every symbol that isn't a core Lisp form):

- `counterparty-default-status` → string
- `time-before?` → bool
- `product-class-eq?` → bool
- `clearing-status?` → string
- `variation-margin-threshold?` → bool
- `has-capability` → bool (shared — move to core, not CDM-specific)
- `check-domain` → bool (shared — move to core)

SCADA predicate set:

- `sensor-reading` → number
- `sensor-quality` → enum
- `target-eq?` → bool
- `pressure-below-limit?` → bool
- `temperature-below-limit?` → bool
- `level-above-minimum?` → bool
- `dual-auth` → bool

Shared predicates (`has-capability`, `check-domain`, `chain-continuous?`, `sanctions-hit?` once BoL lands, etc.) move to `packages/cell-engine/bindings/builtin-host-functions.ts` so every grammar sees them without re-registering.

### D29.5.3 — Rewire CDM lifecycle to go through the kernel

**File**: `packages/cdm/src/lifecycle.ts` (rewrite)

`CDMLifecycleEngine.executeEvent()` becomes:

1. Look up the relevant policy cell(s) for the (`state`, `event`) tuple from the compiled policy bundle.
2. Build a `PolicyContext` from the current product, the event payload, the actor, and an optional co-actor.
3. Call `PolicyRuntime.evaluate(policyCell, context)` for each applicable policy.
4. If any policy returns `ok: false`, return the result with the `rejectionCode` and `hostCalls` audit trail. The state transition does not happen. **No transitionTable check.** The transition table becomes a static assertion for test-time only; runtime enforcement lives in the policy cells.
5. If all policies pass, build the new cell header, pack the cell, invoke the anchor emitter (D29.5.5), and return the updated product.

The Result type grows to carry the audit trail:

```typescript
type LifecycleExecuteResult =
  | { ok: true; value: { product: CDMProduct; event: CDMLifecycleEvent; cell: Uint8Array;
                         policyResults: PolicyResult[]; anchorTxId?: string } }
  | { ok: false; error: string; rejectionCode?: KernelErrorCode; hostCalls?: HostCallRecord[] };
```

### D29.5.4 — Rewire SCADA command authorization to go through the kernel

**File**: `packages/scada/src/authorization.ts` (rewrite)

`CommandAuthorizationEngine.authorizeCommand()` becomes:

1. Collect every `InterlockPolicy` whose `targetAction` matches the command type.
2. Build a `PolicyContext` from the current telemetry state, the operator facet, and any dual-auth supervisor.
3. Call `PolicyRuntime.evaluate(policy.compiledBytes, context)` for each policy.
4. Aggregate: command passes only if every applicable interlock passes.
5. On pass, consume the operator's LINEAR capability cell via the existing `consumeCapability` opcode path and emit the anchor tx (D29.5.5).
6. On fail, return `InterlockViolation` populated from each failed `PolicyResult.hostCalls` — the operator sees exactly which sensor or which dual-auth requirement tripped.

`evaluatePolicyScriptWords` is deleted. The `scriptWords` field on `InterlockPolicy` becomes an audit-only human-readable projection of `compiledBytes`, not an evaluation input.

### D29.5.5 — Anchor emitter

**File**: `packages/policy-runtime/src/anchor-emitter.ts`

Shared helper that converts a packed terminal-event cell into a signed BSV anchor tx via the Plexus adapter:

```typescript
export interface AnchorEmitter {
  emit(cell: Uint8Array, opts: AnchorOptions): Promise<AnchorResult>;
}

export interface AnchorOptions {
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT';
  anchorPolicy: 'always' | 'terminal-only' | 'regulatory-only' | 'never';
  /** Idempotency key — re-emitting the same event returns the original txid */
  idempotencyKey: string;
  /** Which Plexus instance to broadcast through */
  plexusInstance?: string;
}

export interface AnchorResult {
  txid: string;
  beefEnvelope: Uint8Array;
  broadcastedAt: string;
  reused: boolean;  // true if idempotent cache hit
}
```

Call sites:

- **CDM**: on `execution`, `novation`, `settlement`, `full-termination`, `close-out-netting`. All carry `anchorPolicy: 'terminal-only'` except regulatory reports, which carry `anchorPolicy: 'regulatory-only'` and always anchor.
- **SCADA**: on any `executed` command (LINEAR consumption point) and every `CRITICAL` alarm cell.
- **Future BoL (Phase 32)**: on `issue`, `endorse`, `deliver`, `surrender`, `telex-release`.

Idempotency is enforced by keying the emission on `sha256(cellBytes)`. Re-running a demo twice does not broadcast twice; the second call returns `reused: true`.

### D29.5.6 — Gate tests that actually prove the wiring

**File**: `packages/__tests__/phase29.5-gate.test.ts`

Four hard invariants, each of which must hold or the gate fails:

1. **`no-ts-shim` invariant.** A CDM policy whose Lisp body evaluates a host predicate with a recorded, spied-on provider sees exactly one invocation of that provider per `PolicyRuntime.evaluate` call, and the invocation comes through `OP_CALLHOST` — not through the TypeScript compiler module. Asserted by spying on the registry's dispatch method and on the WASM engine's `executeScript` export.
2. **`opcode-rejection` invariant.** A policy that should fail returns a `PolicyResult` with `ok: false` and a populated `rejectionCode`, and the `hostCalls` audit trail contains the call that caused the rejection. The failure path never throws — it returns structured data.
3. **`anchor-idempotent` invariant.** Emitting the anchor tx for the same packed cell twice returns the same txid with `reused: true` on the second call. No double broadcast.
4. **`unknown-host-fn-is-loud` invariant.** A policy that references a host predicate that is not registered returns `ok: false` with `rejectionCode: ERR_UNKNOWN_HOST_FN`. Not a silent pass. Not a TS thrown exception. A specific opcode-level error code.

Additional coverage:

- Round-trip from `.policy` file → compiled cell → `PolicyRuntime.evaluate` → expected pass/fail for every shipped CDM and SCADA policy, with golden fixtures.
- Differential test: for every policy in `cdm/src/policies/*.policy` and `scada/src/policies/interlocks.ts`, the old TS-shim evaluation and the new 2-PDA evaluation must agree on every fixture input. This is the migration-safety net. Once the sweep is complete, the old TS shim is deleted and the differential test is rewritten to assert structural equivalence only at the `scriptBytes` level.

### D29.5.7 — Formal verification scope update

**File**: `proofs/lean/Semantos/Theorems/README.md` (update) + `docs/FORMAL-VERIFICATION-STRATEGY.md` (update)

The Lean K1–K5 / K7 invariants currently cover the kernel path. This sweep extends the "trusted boundary" down to include `PolicyRuntime.evaluate()`, which means the Lean coverage claim improves without any new proofs: the lifecycle engines are no longer a parallel evaluator and therefore no longer a source of kernel-invariant drift.

Two documentation updates:

1. `proofs/lean/Semantos/Theorems/README.md` gains a "Coverage boundary" section naming `PolicyRuntime.evaluate` as the downstream cut, and explicitly naming the extension-grammar lifecycle engines as "gate-but-do-not-enforce" — they can reject before the kernel runs, but they cannot admit something the kernel would reject.
2. `FORMAL-VERIFICATION-STRATEGY.md` gains a row for the differential test in D29.5.6, classified as "Regression — asserts kernel-evaluator and TS-shim-evaluator agree on fixture corpus pre-deletion."

A future phase can extend this with a Lean lemma saying "every state transition admitted by the TS lifecycle engine is also admitted by the corresponding policy cell under `PolicyRuntime.evaluate`" — but that is out of scope for 29.5. The sweep's goal is to stop the drift, not to prove equivalence.

### D29.5.8 — Demo rewrite

Both `packages/cdm/` and `packages/scada/` have existing demos. Each one gets a `demo-kernel.ts` counterpart that does the same scenario through the new path, and prints:

1. The Lisp policy source.
2. The compiled script words.
3. The 2-PDA trace (opcode-by-opcode, from the executor's debug export).
4. The host calls that fired.
5. The anchor tx envelope (hex preview).
6. The resulting product / command state.

This is the "seeing is believing" artifact. If the demo prints a 2-PDA trace and an anchor txid, the wiring is real. If it prints the TS shim calling `evaluatePolicyScriptWords`, it isn't and the gate test should have caught it.

---

## Migration Strategy

Two weeks of parallel running, one week of cutover, one week of cleanup.

### Week 1–2: Parallel

- Land `PolicyRuntime` and `AnchorEmitter` packages. Land host-function registration for CDM and SCADA. Do **not** rewire the lifecycle / authorization engines yet.
- Add a `runtime: 'ts-shim' | 'kernel'` flag to both engines, defaulting to `'ts-shim'`.
- Gate test `phase29.5-gate.test.ts` runs against `runtime: 'kernel'`. Existing CDM and SCADA gate tests keep running against `runtime: 'ts-shim'`.
- Differential test runs with both simultaneously and asserts agreement.

### Week 3: Cutover

- Flip the default to `'kernel'`.
- All existing CDM and SCADA gate tests must pass under the new runtime. Any disagreement fails the cutover.
- Anchor emission is enabled on terminal events. Broadcast is via a dev-mode Plexus (the adapter already supports this — see Phase 14 errata).

### Week 4: Cleanup

- Delete `evaluatePolicyScriptWords` and any other TS shim that is no longer reachable.
- Remove the `runtime` flag. There is one runtime now.
- Update CDM and SCADA docs to drop the "in a full implementation" hedges.
- Rewrite Phase 32 (Bills of Lading) success criteria to reference this sweep as landed.

---

## Success Criteria

Phase 29.5 is complete when:

- [ ] `PolicyRuntime.evaluate` is the only code path that executes a `.policy` cell at runtime in CDM and SCADA.
- [ ] Every CDM policy and every SCADA interlock has a registered host-function set in `HostFunctionRegistry`.
- [ ] Every terminal lifecycle event in CDM and SCADA emits a signed, idempotent anchor tx through the Plexus adapter.
- [ ] The differential test passes on every fixture for the full week of parallel running.
- [ ] The `no-ts-shim`, `opcode-rejection`, `anchor-idempotent`, and `unknown-host-fn-is-loud` gate invariants all pass.
- [ ] `evaluatePolicyScriptWords` is deleted and the `scriptWords` field is clearly marked as audit-only.
- [ ] Lean / FORMAL-VERIFICATION-STRATEGY docs reflect the new coverage boundary.
- [ ] Phase 28 and Phase 29 phase docs are edited to remove the "in a full implementation" language — not because the language was dishonest, but because it is now out of date.
- [ ] The kernel-path demos print a 2-PDA trace and an anchor txid for both CDM and SCADA.

---

## Explicitly Out of Scope

- New kernel opcodes. If a policy needs an opcode that doesn't exist, that's a different phase.
- New linearity modes.
- Proof-of-equivalence between TS shim and kernel path. The differential test is a regression net, not a proof.
- Multi-instance Plexus federation. Single dev-mode instance is enough for the gate.
- Loom UI changes to surface the audit trail. Next phase — this one ends at the API.
- Bills of lading. That is Phase 32 and it blocks on this.

---

## Relationship to Phase 32 (Bills of Lading)

Phase 32's success criteria include:

> Attempting to double-spend a negotiable BoL (issue a second original for the same bolNumber) is rejected at the opcode level, not at the application layer.

> Attempting to deliver without presentation is rejected by the `present-before-deliver` policy.

Both claims are meaningful only after 29.5 ships. Until then, Phase 32 would ship with the same "TS-shim mirroring intended opcode semantics" hedge that CDM and SCADA currently carry. With 29.5 landed, Phase 32 rides on top for free and the claims become structural properties of the runtime instead of properties of a hand-maintained TypeScript interpreter.

Phase 32 picks up no new kernel work of its own. Every gap it would otherwise inherit is closed here.

---

## Open Questions

1. **Should `PolicyRuntime` live in `packages/policy-runtime/` or inside `packages/cell-ops/`?** Leaning standalone because it has two downstream dependents today and at least one more incoming (BoL). Splitting later is harder than starting split.
2. **Anchor-tx fee policy.** Do we anchor every terminal event, or batch per block? Batching is an observability win but an idempotency / timing loss. Probably "anchor-on-terminal, batch-on-regulatory" — but worth nailing down before the emitter API locks.
3. **Differential test retention.** Do we delete the TS shim after cutover, or keep it behind a `--legacy` flag for one phase cycle as a safety net? Leaning delete — the shim is a liability if anyone accidentally runs it — but a conservative reviewer might prefer to keep it for a quarter.
4. **Host-function provider lifetime.** SCADA's `TelemetryStateProvider` is implicitly per-request (current telemetry snapshot). CDM's counterparty-default provider might be long-lived. The `HostFunctionRegistry` API today assumes long-lived providers. Need to decide whether to introduce per-call provider injection or to have providers take a `PolicyContext` argument on every call.
5. **Plexus dev-mode vs real broadcast during gate tests.** Gate tests should not broadcast to a real BSV node. The `AnchorEmitter` needs a dev-mode shim that produces structurally valid BEEF envelopes without network I/O, and the gate tests should assert that shim is in use.

---
