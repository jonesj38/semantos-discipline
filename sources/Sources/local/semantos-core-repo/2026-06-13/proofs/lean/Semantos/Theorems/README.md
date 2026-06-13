---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.369207+00:00
---

# Semantos Kernel Invariants — Lean Proofs

## Proven Invariants

| ID | Name | File | What it covers |
|----|------|------|----------------|
| K1 | Linearity | `LinearityK1.lean` | LINEAR cells consumed exactly once; AFFINE no-duplicate; RELEVANT no-discard |
| K2 | Auth Soundness | `AuthSoundnessK2.lean` | Capability tokens require valid ownership proof |
| K3 | Domain Isolation | `DomainIsolationK3.lean` | Cross-domain operations blocked at opcode level |
| K4 | Failure Atomicity | `FailureAtomicK4.lean` | Failed scripts leave stack in pre-execution state — covers all 16 Plexus opcodes 0xC0-0xCF including OP_SIGN (0xCD), OP_DECREMENT_BUDGET (0xCE), OP_REFILL_BUDGET (0xCF) |
| K5 | Termination | `TerminationK5.lean` | All scripts terminate (no loops, bounded opcodes) |
| K7 | Cell Immutability | `CellImmutabilityK7.lean` | Packed cells are bitwise immutable after construction |
| K8 | Demotion Safety | `DemotionK8.lean` | OP_DEMOTE only allows LINEAR→AFFINE / LINEAR→RELEVANT |
| K9 | Temporal Morphism | `TemporalMorphismK9.lean` | Attestation precedes commitment (peek-then-mutate) — covers wallet ops (OP_SIGN/OP_DECREMENT_BUDGET/OP_REFILL_BUDGET) alongside CHECK ops |
| K10 | Turing Completeness | `TuringCompletenessK10.lean` | Constructive: 2-PDA + transaction DAG + restored arithmetic = Turing complete |
| K11 | Sign Soundness | `SignSoundnessK11.lean` | OP_SIGN: LINEAR keys consumed; emitted signature verifies; failure-atomic |
| K12 | Key Custody | `KeyCustodyK12.lean` | LINEAR tier-key cells cannot be duplicated; tier-N signing requires domain-flag check |
| K13 | Budget Monotonicity | `BudgetMonotonicityK13.lean` | OP_DECREMENT_BUDGET strictly decreases remaining; OP_REFILL_BUDGET strictly increases (with valid parent sig) |

## Coverage Boundary (Phase 29.5)

The Lean K1-K5 / K7 invariants cover the **kernel path**: opcodes dispatched
by `executor.zig`, including OP_CALLHOST (0xD0) for host function dispatch.

As of Phase 29.5, `PolicyRuntime.evaluate()` is the downstream cut point.
Extension grammar lifecycle engines (CDM `executeEvent`, SCADA `authorizeCommand`)
are classified as **"gate-but-do-not-enforce"**:

- They **can reject** before the kernel runs (e.g., invalid state transition).
- They **cannot admit** something the kernel would reject.
- All policy enforcement flows through `PolicyRuntime.evaluate()` → `CellEngine.executeScript()`.

This means the Lean coverage claim applies to the full lifecycle path without
new proofs — the lifecycle engines no longer contain a parallel evaluator.

### OP_CALLHOST boundary

The kernel verifies that:
1. A host function name was on the stack (valid string, non-empty).
2. The extern `host_call_by_name` was called with the name bytes.
3. The result was pushed back onto the stack as a script number.
4. If the result is 0xFFFFFFFF (unknown function), `error.unknown_host_function` fires.

The kernel does NOT verify the host function's implementation — that is the
responsibility of the host (TypeScript `HostFunctionRegistry`). Host functions
are external to the formal verification boundary.

### What changed in Phase 29.5

| Before | After |
|--------|-------|
| CDM lifecycle uses TS `transitionTable` for enforcement | CDM lifecycle calls `PolicyRuntime.evaluate()` for policy enforcement |
| SCADA authorization uses TS regex evaluator (`evaluatePolicyScriptWords`) | SCADA authorization calls `PolicyRuntime.evaluate()` for interlock enforcement |
| No anchor tx emission | Terminal events emit signed BEEF anchor tx via `AnchorEmitter` |
| Host predicates in disconnected TS modules | Host predicates registered with `HostFunctionRegistry`, dispatched via `OP_CALLHOST` |

### Future work

A future phase can extend this with a Lean lemma asserting:
> Every state transition admitted by the TS lifecycle engine is also admitted
> by the corresponding policy cell under `PolicyRuntime.evaluate()`.

This is out of scope for Phase 29.5. The sweep's goal is to stop the drift,
not to prove equivalence.
