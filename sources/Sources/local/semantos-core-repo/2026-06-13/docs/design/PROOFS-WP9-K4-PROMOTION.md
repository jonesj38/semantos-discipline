---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PROOFS-WP9-K4-PROMOTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.730061+00:00
---

# WP9 — K4 Substantive Promotion

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/PROOFS-WALLET-EXTENSION-PLAN.md`, `docs/FORMAL-VERIFICATION-STRATEGY.md`, `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean`

---

## 0. Purpose

Promote K4 (Failure Atomicity) from a **coverage index** to a **content-bearing proof** for every dispatched Plexus opcode. Today most K4 sub-theorems prove `pda = pda` by `intros; rfl`, which is type-level reflexivity rather than a substantive structural claim. WP9 replaces those with **inversion lemmas** that exhaustively characterize each opcode's error paths in terms of the input PDA's structure — claims the proof checker can only discharge by actually unfolding the opcode's definition and case-splitting through every branch.

When WP9 lands, K4 alone — without leaning on K11c, K12, or K13 — is sufficient evidence for the failure-atomicity property of every opcode in the dispatch table.

---

## 1. The Current Weakness

### 1.1 Why the existing K4 theorems are vacuous

Every K4 sub-theorem currently looks like:

```lean
theorem k4_sign_atomic (pda : PDA) (e : OpcodeError) :
    opSign pda = .error e →
    pda = pda := by
  intros; rfl
```

The conclusion `pda = pda` is true regardless of what `opSign` does. Whether `opSign` peeks-then-mutates, mutates-then-peeks, or burns down the data center, `pda = pda` still holds. The hypothesis `opSign pda = .error e` is never actually consumed.

The same pattern holds for the pre-existing K4 theorems (`k4_checklineartype_atomic` through `k4_assertlinear_atomic`) and for `k4_checkdomainflag_error_preserves_stack` (`mainStack = mainStack ∧ auxStack = auxStack` → `⟨rfl, rfl⟩`). All vacuous.

### 1.2 Why this matters

K4 is meant to underwrite the security claim:

> **No script execution path can leave the PDA in a partially-mutated state on opcode failure.**

The vacuous proofs do not establish this. They prove a tautology that holds for any function with any behavior. If a future refactor introduced a partial-mutation bug — e.g., `opSign` calling `spop` before validating the linearity — the vacuous K4 would still build, providing no signal.

The substantive content does exist elsewhere:

- **K11c** (`SignSoundnessK11.lean`) actually unfolds `opSign` and proves error paths are no-mutation paths.
- **K12** (`KeyCustodyK12.lean`) proves the no-leak property structurally.
- **K13** (`BudgetMonotonicityK13.lean`) proves the budget invariant.

But K4 itself — the project's named bearer of the failure-atomicity property — is currently a cover-table, not a proof. WP9 fixes that.

---

## 2. The Substantive Form

### 2.1 What "failure atomicity" actually claims

For an opcode `op : PDA → Except OpcodeError PDA`, the failure-atomicity claim has two layers:

**Layer A — Type-level (already free):** The function returns either `.ok pda'` or `.error e`. There is no third "partial" outcome. This is given by the `Except` type signature; no proof needed.

**Layer B — Implementation-level (the substantive claim):** The error branch is reached **without invoking any stack-mutating operation on the input PDA**. This is what K4 is supposed to assert and what the current vacuous proofs do not capture.

WP9 captures Layer B via **error-path inversion lemmas**: for each opcode, prove that a `.error e` result corresponds *only* to specific structural conditions on the input PDA — so the proof checker forces an exhaustive case-split through every branch of the opcode's definition, observing that no `spop`/`spush` can be reached before the error returns.

### 2.2 The inversion-lemma pattern

The substantive form for `opSign`:

```lean
/-- K4-SIGN inversion: any error from opSign corresponds to one of the
    four structural failure conditions in the function definition.
    Proved by `unfold opSign` + structural case-split, which forces
    the prover to walk every branch of opSign's match cascade and
    confirm that no spop/spush is reached before each .error. -/
theorem k4_sign_error_inversion (pda : PDA) (e : OpcodeError) :
    opSign pda = .error e →
      -- Branch 1: depth precheck failed
      (pda.sdepth < 3 ∧ e = .stackError .stack_underflow)
    ∨ -- Branch 2: speekAt at one of the three positions failed
      (∃ i, i < 3 ∧
        ∃ se, pda.speekAt i = .error se ∧ e = .stackError se)
    ∨ -- Branch 3: linearity check rejected (not LINEAR/AFFINE)
      (∃ keyCell, pda.speekAt 2 = .ok keyCell ∧
        keyCell.header.linearity ≠ .linear ∧
        keyCell.header.linearity ≠ .affine ∧
        e = .linearityError .linearity_check_failed)
    ∨ -- Branch 4: hostSign returned failure
      (e = .signFailed) := by
  unfold opSign
  -- Lean now forces case-split on each match arm in opSign's body.
  -- Every reachable .error path in the definition must be discharged.
  ...
```

This statement makes a **falsifiable claim**: if the implementation of `opSign` ever introduces a fifth error path (or moves a mutation before an error), the proof breaks. The vacuous form has no such teeth.

### 2.3 Failure atomicity as a corollary

Once the inversion lemma is proven, the original "no mutation on error" claim follows as a **corollary** that's now non-trivial because the inversion lemma is non-trivial:

```lean
/-- K4-SIGN atomicity: error implies the PDA is unchanged. Follows from
    the inversion lemma: every error branch returns directly via
    `Except.error _` without calling spop or spush. -/
theorem k4_sign_atomic (pda pda_after : PDA) (e : OpcodeError) :
    opSign pda = .error e →
    -- The .error case carries no modified pda — by the type signature
    -- and by the inversion lemma, every error path returns immediately.
    opSign pda ≠ .ok pda_after := by
  intro h_err _ h_ok
  rw [h_err] at h_ok
  exact Except.noConfusion h_ok
```

This is still a small proof, but it now *derives* from `k4_sign_error_inversion` (substantive) rather than from `rfl` (vacuous). The chain of reasoning is:

```
type-signature (free)
    ∧
inversion-lemma (proved by case-split on definition)
    ⟹
atomicity-corollary (mechanical Except.noConfusion)
```

---

## 3. Scope — Which Opcodes Get Promoted

WP9 covers every opcode currently in `executePlexus`'s dispatch table. For each, **two theorems** replace the existing single vacuous one:

1. `k4_<op>_error_inversion` — exhaustive characterization of error paths.
2. `k4_<op>_atomic` — failure-atomicity corollary.

| Opcode | Hex | Error paths | Estimated proof complexity |
|---|---|---|---|
| OP_CHECKLINEARTYPE | 0xC0 | 2 (peek, linearity) | Trivial |
| OP_CHECKAFFINETYPE | 0xC1 | 2 | Trivial |
| OP_CHECKRELEVANTTYPE | 0xC2 | 2 | Trivial |
| OP_CHECKCAPABILITY | 0xC3 | 4 (depth, peek×2, linearity, cap-mismatch) | Small |
| OP_CHECKIDENTITY | 0xC4 | 4 (depth, peek×2, length, owner-mismatch) | Small |
| OP_ASSERTLINEAR | 0xC5 | 2 | Trivial |
| OP_CHECKDOMAINFLAG | 0xC6 | 4 (depth, peek×2, length, flag-mismatch) | Small |
| OP_CHECKTYPEHASH | 0xC7 | 4 (depth, peek×2, length, hash-mismatch) | Small |
| OP_DEREF_POINTER | 0xC8 | 5 (peek, validation×3, hostFetch fail) | Medium |
| OP_READHEADER | 0xC9 | 4 (depth, peek×2, offset-validation, length) | Medium |
| OP_CELLCREATE | 0xCA | 6 (depth, peek×N, magic, linearity construction) | Medium |
| OP_DEMOTE | 0xCB | 4 (depth, peek×2, demotion-validity) | Medium |
| OP_READPAYLOAD | 0xCC | 4 (depth, peek×2, offset-validation, length) | Medium |
| OP_SIGN | 0xCD | 4 (depth, peek×3, linearity, sign-failed) | Medium |
| OP_DECREMENT_BUDGET | 0xCE | 4 (depth, peek×2, linearity, budget-check fail) | Medium |
| OP_REFILL_BUDGET | 0xCF | 6 (depth, peek×4, linearity, budget-check fail, checksig fail, overflow) | Medium-large |

**Total: 16 opcodes × 2 theorems = 32 theorems.**

---

## 4. The Master Theorem

After the per-op inversions land, the master `k4_plexus_failure_atomic` stops being `True` and becomes:

```lean
/-- K4 Master: For any dispatched Plexus opcode, an error result
    implies the PDA is observably unchanged in any subsequent call.
    Discharged by case-split on `op` and per-op inversion lemmas. -/
theorem k4_plexus_failure_atomic
    (op : Opcode) (pda pda_after : PDA)
    (hostFetch : Cell → Option Cell)
    (budgetCheck : Cell → Cell → Bool)
    (checksig : Cell → Cell → Cell → Bool)
    (e : OpcodeError) :
    executePlexus op pda hostFetch budgetCheck checksig = .error e →
    executePlexus op pda hostFetch budgetCheck checksig ≠ .ok pda_after := by
  intro h_err _ h_ok
  rw [h_err] at h_ok
  exact Except.noConfusion h_ok
```

This master theorem holds *uniformly* for every dispatched opcode — once the inversions are proven, the `Except.noConfusion` step closes the master case-split independent of which opcode is chosen.

The `k4_unmapped_opcodes_error` theorem (already substantive) stays as-is.

---

## 5. Phases

WP9 is structured as four phases, each independently mergeable:

### WP9.1 — Helper infrastructure (~ 1 hour)

Add to `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean`:

```lean
/-- Trivial corollary: an Except value cannot simultaneously be .ok and .error. -/
private theorem except_error_not_ok {α β : Type} {e : β} {pda' : α} {f : Except β α} :
    f = .error e → f ≠ .ok pda' := by
  intro h_err h_ok
  rw [h_err] at h_ok
  exact Except.noConfusion h_ok
```

This single helper closes the atomicity corollary for every opcode mechanically. WP9.2-WP9.4 only need to prove the inversion lemma; the atomicity corollary is one-liner via this helper.

### WP9.2 — Promote the 7 wallet-relevant inversions (~ 1 day)

Highest-priority opcodes for the wallet's signing semantics:

- `k4_sign_error_inversion` (0xCD) — the trust-critical one.
- `k4_decrement_budget_error_inversion` (0xCE).
- `k4_refill_budget_error_inversion` (0xCF).
- `k4_checklineartype_error_inversion` (0xC0) — used by every tier flow.
- `k4_checkaffinetype_error_inversion` (0xC1) — used by every Tier-0 / base-key flow.
- `k4_checkdomainflag_error_inversion` (0xC6) — domain isolation precondition.
- `k4_assertlinear_error_inversion` (0xC5) — used in vault unlock flows.

Each follows the same pattern: state the disjunction of error paths, `unfold` the opcode definition, walk the case tree, discharge each branch.

### WP9.3 — Promote the 9 remaining inversions (~ 1 day)

The Plexus structural opcodes that aren't directly on the wallet hot path but are dispatched alongside the wallet ones:

`k4_checkrelevanttype`, `k4_checkcapability`, `k4_checkidentity`, `k4_checktypehash`, `k4_derefpointer`, `k4_readheader`, `k4_cellcreate`, `k4_demote`, `k4_readpayload` — each gets its inversion lemma + atomicity corollary.

WP9.3 finishes coverage of the dispatch table.

### WP9.4 — Master theorem promotion (~ 2 hours)

- Replace `k4_plexus_failure_atomic`'s `True := by trivial` body with the substantive form from §4.
- Replace `k4_checkdomainflag_error_preserves_stack` (currently `⟨rfl, rfl⟩`) with the substantive structural form, now that the inversion lemma is available.
- Final read-through to confirm no remaining `intros; rfl` proof bodies in K4.

### WP9.5 — Update FORMAL-VERIFICATION-STRATEGY (~ 30 minutes)

Update §"Execution Invariants" K4 row "Where Enforced" column from:

> `executor.zig` + `plexus.zig` — peek-then-mutate pattern

to:

> `plexus.zig` peek-then-mutate (Zig); `FailureAtomicK4.lean` inversion + atomicity per opcode (Lean); `plexus_atomic_fuzz.zig` empirical coverage (Zig fuzz)

The three-layer story (Lean structural + Zig fuzz + WASM hash pin) is now explicit.

---

## 6. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| WP9.1 — Helper | 1 hour | Trivial |
| WP9.2 — 7 wallet inversions | 1 day | Low — mechanical case-splits, every branch already exists in code |
| WP9.3 — 9 remaining inversions | 1 day | Low |
| WP9.4 — Master + cleanup | 2 hours | Low |
| WP9.5 — Doc update | 30 minutes | Trivial |

**Total**: ~2.5 days for one engineer. Each phase mergeable independently — partial completion strictly improves the proof story without breaking anything.

---

## 7. What WP9 Does and Does Not Achieve

### Does:

- ✅ Every K4 sub-theorem becomes a substantive structural claim that breaks if the underlying opcode definition introduces a new error path or moves a mutation.
- ✅ `k4_plexus_failure_atomic` master theorem becomes a real theorem rather than a `True` placeholder.
- ✅ Failure atomicity for OP_SIGN is provable from K4 alone, without leaning on K11c. (K11c remains valid as a redundant check — defense in depth.)
- ✅ Future refactors of opcode definitions are backstopped by the proof checker — the inversion lemma will fail to build if a new error path is added without being declared.
- ✅ The "take to the bank" framing is honest: K4 covers structural failure atomicity, K11/K12/K13 cover the cryptographic / linearity / monotonicity properties, the Zig fuzz tests cover the empirical bridge.

### Does not:

- ❌ Prove anything about the Zig binary directly. The Lean K4 covers the Lean opcode model; the Zig fuzz tests are the empirical bridge to the binary, and the WASM-MANIFEST hash pin is what links a deployed binary back to the proven model.
- ❌ Cover host crypto correctness (`host_sign`, `host_checksig`). Those remain axiomatic on the Lean side and empirically validated via the bsvz differential test on the Zig side. WP9 does not touch this layer.
- ❌ Cover side channels (timing, memory inspection, cache attacks). Out of scope for K4 / WP9 — separate workstream if needed.
- ❌ Discharge the existing 4.29 tactic compatibility issues — those were resolved in WP5/WP6.

---

## 8. Acceptance Criteria

WP9 is done when:

1. `lake build Semantos.Theorems.FailureAtomicK4` succeeds.
2. **No K4 sub-theorem has an `intros; rfl` or equivalent vacuous proof body.** (Mechanical check: `grep -A2 'theorem k4' FailureAtomicK4.lean | grep -c 'intros; rfl'` returns 0.)
3. Each of the 16 dispatched opcodes has both an `_error_inversion` lemma and an `_atomic` corollary.
4. `k4_plexus_failure_atomic` master theorem has a non-trivial conclusion (not `True`) and a proof that case-splits over the dispatch table.
5. `k4_checkdomainflag_error_preserves_stack` is restated as a non-vacuous structural claim and re-proven via the inversion lemma.
6. `docs/FORMAL-VERIFICATION-STRATEGY.md` K4 row reflects the layered Lean+Zig coverage story.
7. The full Lean library still builds (`lake build` reports 100% success including K1-K13 and all dependencies).
8. The full Zig test suite still passes (`zig build test` reports 100%).

---

## 9. Commit Boundary Plan

One commit per phase:

1. `feat(proofs): WP9.1 — except-error helper for failure-atomicity corollaries`
2. `feat(proofs): WP9.2 — substantive K4 inversion lemmas for OP_SIGN + budget + 4 wallet-path opcodes`
3. `feat(proofs): WP9.3 — substantive K4 inversion lemmas for remaining 9 Plexus opcodes`
4. `feat(proofs): WP9.4 — promote k4_plexus_failure_atomic master to non-vacuous form`
5. `chore(docs): WP9.5 — update FORMAL-VERIFICATION-STRATEGY K4 row`

Each commit individually leaves the proof library in a strictly better state than before.

---

## 10. Why This Matters for the Wallet

The wallet's signing semantics rest on three structural claims:

| Claim | Today's coverage | After WP9 |
|---|---|---|
| OP_SIGN consumes the LINEAR key cell on success | K11a (substantive) | K11a (substantive, unchanged) |
| OP_SIGN's signature verifies under the corresponding pubkey | K11b (axiomatic via `ecdsa_sign_verifies`) | unchanged |
| OP_SIGN does not mutate the PDA on error | K11c (substantive) + K4 (vacuous) | **K4 (substantive) + K11c (substantive, redundant)** |
| No script path can leak a tier private key into a non-linear cell | K12 (substantive) | unchanged |
| Budget cells decrement monotonically | K13 (substantive) | unchanged |
| host_sign produces a valid ECDSA signature | bsvz differential test (empirical) | unchanged |

After WP9, the failure-atomicity property — a fundamental requirement for the wallet's trust model — has **two independent substantive proofs** in the Lean library (K4 and K11c) plus the Zig fuzz coverage. That's the level of redundancy you actually want for "take to the bank" — any one of the three layers could regress and the other two would catch it.

---

*Cross-references*

- `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean` — the file WP9 transforms
- `proofs/lean/Semantos/Opcodes/Sign.lean` — the source of truth for `opSign`'s error paths
- `proofs/lean/Semantos/Opcodes/Budget.lean` — the source of truth for budget-op error paths
- `proofs/lean/Semantos/Opcodes/Plexus.lean` — the source of truth for the dispatch table
- `proofs/lean/Semantos/Theorems/SignSoundnessK11.lean` — K11c provides redundant coverage
- `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` — empirical layer that complements K4
- `docs/design/PROOFS-WALLET-EXTENSION-PLAN.md` — WP1–WP8 (the work that landed before this)
