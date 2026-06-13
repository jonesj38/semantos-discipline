---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PROOFS-WALLET-EXTENSION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.721829+00:00
---

# Wallet Proof Extension Plan — WP1–WP8

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/FORMAL-VERIFICATION-STRATEGY.md`, `docs/design/WALLET-TIER-CUSTODY.md`, `core/cell-engine/OPCODE-HARDENING-PLAN.md`

---

## 0. Purpose

The W1–W3.5 wallet implementation introduced three new opcodes — `OP_SIGN` (0xCD), `OP_DECREMENT_BUDGET` (0xCE), `OP_REFILL_BUDGET` (0xCF) — and one new state primitive (`DerivationState`). The Lean proof library currently has:

- **New theorems that build**: K11 (SignSoundness), K12 (KeyCustody), K13 (BudgetMonotonicity).
- **Existing theorems that don't yet account for the new opcodes**: K4 (FailureAtomicity), K9 (TemporalMorphism), K10 (TuringCompleteness).
- **One existing theorem broken on Lean 4.29 only**: K8 (Demotion) — fixed in flight.
- **One Zig fuzz test stale against the new dispatch table**: `plexus_atomic_fuzz: reserved opcodes (0xC9-0xCF)`.

The new opcodes are trust-critical — they hold the wallet's signing semantics. **Every opcode the cell engine dispatches must be covered by K4 (failure atomicity), K9 (peek-then-mutate temporal ordering), and where applicable K1 (linearity preservation).** This document plans the proof-side work to bring the Lean library back to full coverage of the cell engine's now-extended dispatch table.

---

## 1. Current State

### 1.1 Proof-side gaps

| Theorem | Status on HEAD + W1-W3.5 | Gap |
|---|---|---|
| K1 (Linearity) | builds | Implicit coverage of OP_SIGN (LINEAR consumed) and budget ops (AFFINE preserved) — no explicit per-op theorem yet |
| K2 (Authorization Soundness) | builds | OP_SIGN trivially extends K2 (any signature ⇒ private key was on stack) — covered by K11b |
| K3 (Domain Isolation) | builds | New opcodes use existing OP_CHECKDOMAINFLAG before signing — no new K3 obligation |
| K4 (Failure Atomicity) | **fails** | Master theorem hard-codes 0xC9–0xCF as reserved; new opcodes need per-op failure-atomicity theorems and the master theorem must extend to cover 0xC0–0xCF as fully assigned |
| K5 (Termination) | builds | New opcodes are bounded (no loops) — no new obligation |
| K7 (Cell Immutability) | builds | OP_SIGN consumes the cell rather than mutating it; budget ops construct new cells — no header mutation |
| K8 (Demotion) | **fails** (pre-existing keyword + tactic) | No new opcode demotes — only needs the K8 tactic fix already in flight |
| K9 (Temporal Morphism) | **fails** (pre-existing 4.29 tactic) | K9a/K9b need the new peek-then-mutate opcodes added to the structural theorem; tactic syntax needs 4.29 update |
| K10 (Turing Completeness) | **fails** (pre-existing `decide` over non-decidable goals) | No new opcode adds computational power — just needs tactic update |
| K11 (Sign Soundness) | builds | New, complete |
| K12 (Key Custody) | builds | New, complete |
| K13 (Budget Monotonicity) | builds | New, complete |

### 1.2 Implementation-side gaps

| File | Issue |
|---|---|
| `proofs/lean/Semantos/Opcodes/Plexus.lean` | `executePlexus` dispatches 0xC0–0xCC; doesn't know about OP_SIGN, OP_DECREMENT_BUDGET, OP_REFILL_BUDGET |
| `proofs/lean/Semantos/Opcodes/Classify.lean` | Has OP_SIGN but missing OP_DECREMENT_BUDGET and OP_REFILL_BUDGET classifications |
| `proofs/lean/Semantos/Opcodes/Sign.lean` | Models opSign — must be wired into Plexus.lean dispatch |
| `proofs/lean/Semantos/Opcodes/Budget.lean` | Does not exist — needs creation for opDecrementBudget + opRefillBudget |
| `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` | Loop iterates 0xC9–0xCF asserting all reserved; reality is 0xC9–0xCF are now all assigned. Test must be narrowed to actually-unmapped opcodes outside the dispatch table |

---

## 2. Phases

The plan is structured as eight phases (WP1–WP8) that can land in sequence. WP1–WP3 are the critical path for K4 coverage of the new opcodes. WP4–WP6 close out the unrelated 4.29 issues. WP7–WP8 are validation.

### WP1 — Lean models for the new opcodes (~ half-day)

**Goal**: every dispatched opcode has a Lean model with explicit pre/post stack behavior and explicit error paths.

**Deliverables**:

1. New file `proofs/lean/Semantos/Opcodes/Budget.lean`. Defines:
   - `opDecrementBudget : PDA → Except OpcodeError PDA`. Mirrors `opCheckCapability`'s peek-then-mutate shape: depth precheck (sdepth ≥ 2), peek both arguments, validate AFFINE linearity, validate amount ≥ 0 and amount ≤ remaining, only then pop both and push the updated cell.
   - `opRefillBudget : PDA → (Bytes → Bytes → Bytes → Bool) → Except OpcodeError PDA`. Takes an explicit `checksig` oracle (analogous to how `opDerefPointer` takes `hostFetch`). Depth precheck (sdepth ≥ 4), peek all four, validate AFFINE linearity, validate pubkey/sig lengths, validate `checksig`, overflow guard on credit, only then pop all four and push the updated cell.
   - `BudgetCell` accessor: a structured view over the cell payload exposing `remaining_satoshis : UInt64`. Mirrors how `Cell` already exposes header fields.

2. Extend `proofs/lean/Semantos/Opcodes/Sign.lean` (existing) to expose the existing `opSign` model in the dispatch shape needed by `executePlexus`. (The existing definition is already in this shape — verify and document.)

**Out of scope**: actual cryptographic semantics. `opSign` calls the `ecdsaSign` axiom from CryptoAxioms.lean for the sign operation; `opRefillBudget` takes an opaque `checksig` oracle. No new axioms required.

**Success criterion**: `lake build Semantos.Opcodes.Budget` and `lake build Semantos.Opcodes.Sign` both succeed. New file follows the existing peek-then-mutate idiom verbatim.

### WP2 — Extend `executePlexus` dispatch (~ 1 hour)

**Goal**: `Plexus.lean::executePlexus` dispatches all 16 opcodes 0xC0–0xCF.

**Deliverables**:

1. `proofs/lean/Semantos/Opcodes/Plexus.lean` — extend `executePlexus` to dispatch:
   - `OP_SIGN` (0xCD) → `Sign.opSign pda`
   - `OP_DECREMENT_BUDGET` (0xCE) → `Budget.opDecrementBudget pda`
   - `OP_REFILL_BUDGET` (0xCF) → `Budget.opRefillBudget pda checksig` (takes the same oracle pattern as `opDerefPointer hostFetch`)
2. `proofs/lean/Semantos/Opcodes/Classify.lean` — add classifications:
   - `OP_DECREMENT_BUDGET = 0xCE` → `OpcodeKind.consume` (consumes amount + cell, produces updated cell)
   - `OP_REFILL_BUDGET = 0xCF` → `OpcodeKind.consume` (consumes 4 args, produces 1)
   - Confirm `OP_SIGN = 0xCD` is already classified `consume` (added in W2)
3. The signature of `executePlexus` likely needs to change to take the `checksig` oracle, paralleling how it already takes `hostFetch`. Update all `executePlexus` call sites accordingly.

**Success criterion**: `lake build Semantos.Opcodes.Plexus` succeeds. The dispatch table covers exactly 0xC0–0xCF with no reserved entries; opcodes 0xD1+ continue to fall through to `OpcodeError.reservedOpcode`.

### WP3 — K4 extension (the critical path) (~ 1 day)

**Goal**: K4 (Failure Atomicity) covers all 16 dispatched Plexus opcodes including the three new wallet opcodes.

**Deliverables**:

1. `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean` — add per-opcode atomicity theorems:
   - `k4_sign_atomic` — for `opSign pda`, error implies pda unchanged. Three failure paths: depth underflow, linearity check fail, sign_failed.
   - `k4_decrement_budget_atomic` — for `opDecrementBudget pda`, error implies pda unchanged. Four failure paths: depth, linearity, amount sign, insufficient.
   - `k4_refill_budget_atomic` — for `opRefillBudget pda checksig`, error implies pda unchanged. Six failure paths: depth, linearity, amount sign, pubkey length, sig length/checksig fail, overflow.

2. Update `k4_plexus_failure_atomic` (the master theorem) to:
   - Take the same `checksig` oracle parameter that `executePlexus` now takes.
   - Cover the dispatch arms for 0xCD/CE/CF.
   - Discharge the new arms via the per-op theorems above.

3. **Delete** (or re-state vacuously) `k4_reserved_opcodes_error`. After WP2, no opcode in 0xC0–0xCF is reserved. Either:
   - **Option A** — delete the theorem; it has no valid premise.
   - **Option B** — restate as `k4_unmapped_opcodes_error`: for `op ≥ 0xD1`, `executePlexus` returns `.reservedOpcode` and pda unchanged. (This is the genuinely-true property the original theorem was approximating.) Recommended.

**Each per-op theorem follows the same structural pattern** already established by `k4_checkdomainflag_error_preserves_stack` (lines 89–98 of FailureAtomicK4.lean): walk the error paths, observe each one returns before any stack mutation, conclude the pda is unchanged.

**Success criterion**: `lake build Semantos.Theorems.FailureAtomicK4` succeeds. Master theorem references all 16 dispatched opcodes plus the unmapped tail.

### WP4 — K8 verification (~ 15 minutes)

**Goal**: Confirm the K8 fix already applied (rename + tactic restructure) builds clean.

**Deliverables**:

1. Run `lake build Semantos.Theorems.DemotionK8`.
2. If the new `first | rfl | simp [validDemotion] at h` tactic chain still has unsolved goals, fall back to the explicit case-by-case:
   ```lean
   theorem k8_only_linear_demotable (src tgt : Linearity) :
       validDemotion src tgt = true → src = .linear := by
     intro h
     match src, tgt, h with
     | .linear, _, _ => rfl
     | .affine, _, h => by simp [validDemotion] at h
     | .relevant, _, h => by simp [validDemotion] at h
     | .debug, _, h => by simp [validDemotion] at h
   ```
   The `match` form is bulletproof against tactic-resolution ordering changes.

**Success criterion**: K8 builds. No regression to K11/K12/K13 (which depend on Plexus.lean and CryptoAxioms.lean unchanged).

### WP5 — K9 extension + 4.29 tactic fix (~ half-day)

**Goal**: K9 (Temporal Morphism) covers the new peek-then-mutate opcodes; 4.29 tactic syntax updated.

**Diagnosis (pre-WP5)**: capture the actual `lake build Semantos.Theorems.TemporalMorphismK9` error. Likely culprits:
- The bracketed `<;> [tac1; tac2]` syntax at lines 59 / 77 — Lean 4.29 changed `[...]` to `[...; ...]` semantics. Replacement: `<;> first | tac1 | tac2`.
- `Except.isOk` may have moved or been renamed in 4.29 stdlib.

**Deliverables**:

1. Update K9a / K9b tactic blocks to 4.29-compatible syntax:
   ```lean
   refine ⟨?_, ?_, ?_, ?_⟩ <;> intro pda' h <;>
     simp only [opCheckLinearType, ...] at h <;>
     (split at h <;> first | (simp at h) | (simp [Except.isOk]))
   ```
   (or whatever the actual diagnosis dictates — exact form depends on what the error message says).

2. Add the new peek-then-mutate ops to K9a's structural theorem:
   ```lean
   theorem k9a_attestation_precedes_commitment_extended (pda : PDA) :
       (∀ pda', opSign pda = .ok pda' → pda.sdepth ≥ 3) ∧
       (∀ pda', opDecrementBudget pda = .ok pda' → pda.sdepth ≥ 2) ∧
       (∀ pda' c, opRefillBudget pda c = .ok pda' → pda.sdepth ≥ 4) := by ...
   ```
   This is the temporal-ordering property: success implies the depth precondition was satisfied (i.e., the attestation phase completed before any mutation).

3. Verify that the existing K9c (compositional morphisms) is not broken by the addition of new opcodes — if `executePlexus` now handles more cases, the composition over arbitrary scripts should still hold structurally.

**Success criterion**: `lake build Semantos.Theorems.TemporalMorphismK9` succeeds. The new peek-then-mutate opcodes are covered alongside the existing CHECK opcodes.

### WP6 — K10 4.29 tactic fix (~ 2 hours)

**Goal**: K10 (Turing Completeness) builds on Lean 4.29.

**Diagnosis (pre-WP6)**: capture the actual `lake build Semantos.Theorems.TuringCompletenessK10` error. The agent's earlier scan flagged three `decide` invocations at lines 190, 212, 223. `decide` works only on decidable propositions; if the goals involve Bool comparisons over opaque types or quantifiers introduced by `refine`, decide will fail in 4.29 (and arguably should have failed before too).

**Deliverables**:

1. Replace `<;> decide` with the appropriate tactic for each goal. Likely `rfl` for definitional equalities, or `Bool.decide_eq` / `simp; decide` for compound goals.

2. K10's structural argument is "2-PDA + DAG + arithmetic = Turing complete." None of the new wallet opcodes change this argument — the new opcodes are bounded peek-then-mutate ops, contributing nothing to the computational-power case. **No new opcodes need to be added to K10.** Just the tactic fix.

**Success criterion**: `lake build Semantos.Theorems.TuringCompletenessK10` succeeds.

### WP7 — Update `plexus_atomic_fuzz.zig` (~ 1 hour)

**Goal**: the fuzz test reflects the post-W1-W3 dispatch table.

**Deliverables**:

1. Replace the existing `test "fuzz: reserved opcodes (0xC9-0xCF) always error with stack unchanged"` with two tests:

   **Test A — fuzz the now-fully-assigned 0xC0–0xCF range, asserting K4 (failure atomicity).** For every opcode in the range, run with adversarial cell content; assert that on any error the stack is unchanged byte-for-byte. This is the *positive* form of K4 in Zig: matches the Lean theorem we'll prove in WP3.

   **Test B — fuzz the unmapped tail (0xD1-0xFF excluding 0xD0=OP_CALLHOST), asserting reserved-opcode error.** For every opcode in this range, assert `executePlexus` returns `error.reserved_opcode` and the stack is unchanged.

2. Both tests should iterate at the same `ITERATIONS` count as before to maintain coverage budget.

**Success criterion**: `zig build test` passes 100% (modulo any other unrelated pre-existing failures in different test files — list separately if found).

### WP8 — Full library build verification (~ 30 minutes)

**Goal**: every K-theorem builds, every Zig test passes, and the proofs cover the now-extended cell engine.

**Deliverables**:

1. `cd proofs/lean && lake build` — should succeed end-to-end. Capture the trace of which `.olean` files were rebuilt and confirm K1–K13 are all present in the build cache (no longer just K1, K2, K3, K7, K11, K12, K13).

2. `cd core/cell-engine && zig build test` — should report 100% pass after WP7.

3. Update the K-theorem index in `proofs/lean/Semantos/Theorems/README.md` with the new K-theorems and any updated coverage statements.

4. Update `docs/FORMAL-VERIFICATION-STRATEGY.md` §"Execution Invariants" table:
   - K4: extend "Where Enforced" column to include `opSign`, `opDecrementBudget`, `opRefillBudget`.
   - Add K11, K12, K13 rows.

**Success criterion**: green build, complete coverage, docs updated.

---

## 3. Dependency Graph

```
   ┌─── WP1 (Lean models for new ops)
   │       │
   │       ▼
   │    WP2 (executePlexus dispatch + Classify)
   │       │
   │       ▼
   │    WP3 (K4 extension) ◄─── critical path
   │       │
   │       ▼
   │    WP8 (full build verification) ◄─── final
   │       ▲
   │       │
   ├─── WP4 (K8 — independent, fast)
   │       │
   ├─── WP5 (K9 ext + 4.29 fix — independent of WP1-WP3)
   │       │
   ├─── WP6 (K10 4.29 fix — independent)
   │       │
   └─── WP7 (Zig fuzz update — depends on WP3 narratively but can land separately)
```

WP1 → WP2 → WP3 is the trust-critical path. WP4/WP5/WP6/WP7 are independent and can land in parallel. WP8 gates the merge.

---

## 4. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| WP1 — Lean models for budget ops | 0.5 day | Low — direct mirror of existing peek-then-mutate models |
| WP2 — Dispatch extension | 1 hour | Low — mechanical |
| WP3 — K4 extension | 1 day | Medium — must hit every error path of the new opcodes |
| WP4 — K8 verification | 15 min | Low |
| WP5 — K9 extension + tactic fix | 0.5 day | Medium — needs 4.29 error diagnosis first |
| WP6 — K10 tactic fix | 2 hours | Low — no semantic change |
| WP7 — Fuzz test update | 1 hour | Low |
| WP8 — Build verification + doc update | 30 min | Low |

**Total**: ~2.5 days for one engineer; ~1.5 days with WP4/5/6/7 in parallel after WP3 lands.

---

## 5. Commit Boundary Plan

One PR per phase (or grouped per dependency cluster), so that a regression in any single piece is bisectable:

1. `feat(proofs): WP1 — Lean models for OP_DECREMENT_BUDGET, OP_REFILL_BUDGET`
2. `feat(proofs): WP2 — extend executePlexus dispatch to OP_SIGN + budget ops`
3. `feat(proofs): WP3 — K4 covers all 16 Plexus opcodes; add k4_unmapped_opcodes_error`
4. `fix(proofs): WP4 — K8 tactic fixed for Lean 4.29`
5. `fix(proofs): WP5 — K9 4.29 tactic update + extend to wallet opcodes`
6. `fix(proofs): WP6 — K10 decide → explicit tactic for 4.29`
7. `fix(cell-engine): WP7 — plexus_atomic_fuzz tests post-W1+W3 dispatch table`
8. `chore(proofs): WP8 — verify full Lean build + update K-theorem index`

---

## 6. Acceptance Criteria

The plan succeeds when:

- ✅ Every dispatched Plexus opcode (0xC0–0xCF, 16 total) has an explicit Lean model and an explicit K4 failure-atomicity theorem.
- ✅ K4 master theorem references the same dispatch table the Zig executor uses (no drift).
- ✅ K9 covers the new peek-then-mutate opcodes alongside the existing CHECK ops.
- ✅ K1, K2, K3, K4, K5, K7, K8, K9, K10, K11, K12, K13 all build under Lean 4.29.
- ✅ `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` tests the actual dispatch table, not a stale view.
- ✅ `cd core/cell-engine && zig build test` reports 100% pass.
- ✅ `cd proofs/lean && lake build` reports 100% success.
- ✅ `docs/FORMAL-VERIFICATION-STRATEGY.md` invariant table updated with the new ops and theorems.

When all eight criteria are green, the wallet's signing semantics are mechanically verified — the new opcodes are first-class in the proof library, not exceptions or carve-outs.

---

## 7. What This Plan Does Not Cover

For clarity:

- **TLA+ models** for `KeyCustody.tla` and `TierEscalation.tla` — that's W8 of the wallet design doc, separate workstream.
- **`OP_DERIVE_LEAF` opcode promotion** — currently a host import; promoting to a dedicated opcode would let K12 cover the base→leaf transition structurally. That's a v0.2 design call (see §11 Q14 of the wallet design doc), out of scope here.
- **Differential testing** between the Lean opSign and bsvz primitives — would require an executable Lean → Zig oracle. Defer.
- **The 3 unrelated Zig tests** (capability/multicell/spv) that fail on HEAD — those predate W1 and have nothing to do with the wallet work. Surface separately, fix or document, not part of this plan.

---

*Cross-references*

- `core/cell-engine/src/opcodes/plexus.zig` — the source of truth for the dispatch table the Lean model must mirror
- `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean` — the existing per-op atomicity pattern to follow for the new ops
- `proofs/lean/Semantos/Opcodes/Plexus.lean` — peek-then-mutate model template
- `proofs/lean/Semantos/Opcodes/Sign.lean` — opSign model (already exists, just needs dispatch wiring)
- `proofs/lean/Semantos/Theorems/SignSoundnessK11.lean` — companion property to K4 for OP_SIGN
- `proofs/lean/Semantos/Theorems/BudgetMonotonicityK13.lean` — companion property to K4 for budget ops
- `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` — fuzz test to update in WP7
- `docs/design/WALLET-TIER-CUSTODY.md` §9 — the proof obligations originally specified
- `docs/FORMAL-VERIFICATION-STRATEGY.md` §"Execution Invariants" — table to update in WP8
