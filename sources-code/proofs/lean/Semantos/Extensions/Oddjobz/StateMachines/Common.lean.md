---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/Common.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.376600+00:00
---

# proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/Common.lean

```lean
-- Semantos Plane — D-O4: Oddjobz state-machine common definitions
--
-- Reference:
--   docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (state machines + kernel-
--   gated transitions); proofs/lean/Semantos/Theorems/{LinearityK1,
--   AuthSoundnessK2,FailureAtomicK4}.lean (the substrate-level
--   theorems the per-FSM specs specialise from);
--   extensions/oddjobz/src/state-machines/kernel-gate.ts (the TS
--   surface this file mirrors).
--
-- Shape:
--
--   1. `Principal` — `operator | service` per the §O4 table column
--   2. `KernelGateFailure` — typed failure-mode enum mirroring TS
--   3. `Result α β` — Ok-or-failure result; `α` payload, `β` error
--   4. `ConsumedSet` — list-of-cell-ids substrate model (K1)
--   5. helpers + lemmas about `assertLinear` and `add`
--
-- Status: every theorem in this file proven; no `sorry`, no `admit`.

namespace Semantos.Extensions.Oddjobz.StateMachines.Common

/-- Signing-principal kinds the §O4 table column allows. -/
inductive Principal where
  | operator
  | service
  deriving Repr, DecidableEq, BEq

/-- Typed kernel-gate failure modes. Mirrors the TS
    `KernelGateFailureKind` discriminated union 1:1. -/
inductive KernelGateFailure where
  /-- The transition required a cap; none was presented. -/
  | capRequired
  /-- A cap was presented but its domain flag does not match (K3a). -/
  | wrongCap
  /-- Input cell-id consumed in a prior transition (K1). -/
  | cellAlreadyConsumed
  /-- Wrong signing principal kind. -/
  | badSigningPrincipal
  /-- (from, to) pair not in the FSM transition table. -/
  | invalidStateTransition
  /-- Input cell's `from` field does not match the table row. -/
  | fromStateMismatch
  /-- External call threw mid-transition; cell unchanged (K4). -/
  | inducedIoFailure
  deriving Repr, DecidableEq, BEq

/-- Result of a transition function call. `α` is the success payload
    type; failures always carry a `KernelGateFailure`. -/
inductive Result (α : Type) where
  | ok    : α → Result α
  | error : KernelGateFailure → Result α
  deriving Repr

/-- Has the `Result` succeeded? -/
def Result.isOk {α : Type} : Result α → Bool
  | .ok _    => true
  | .error _ => false

/-- Did the `Result` fail with the given failure kind? -/
def Result.failedWith {α : Type} (r : Result α) (k : KernelGateFailure) : Bool :=
  match r with
  | .ok _      => false
  | .error f   => f == k

/-- A consumed-cell set modelled as a (possibly-duplicate) list of
    cell-ids. We keep the model simple — duplication-tolerance is
    fine because containment is what matters; the K1 invariant is
    "an id is recorded at-least-once after consumption", and we
    achieve that by using `containsList` below. -/
structure ConsumedSet where
  ids : List String
deriving Repr

/-- Fresh empty consumed set. -/
def ConsumedSet.empty : ConsumedSet :=
  { ids := [] }

/-- Membership predicate (Prop). -/
def ConsumedSet.contains (cs : ConsumedSet) (id : String) : Prop :=
  id ∈ cs.ids

/-- Membership Bool. We use `String.decEq` via `List.elem` rather than
    `List.contains` to sidestep the `Decidable` gymnastics. -/
def ConsumedSet.containsBool (cs : ConsumedSet) (id : String) : Bool :=
  cs.ids.elem id

/-- Add a cell-id to the consumed set. We always cons — if the id is
    already in the list, the result still contains it. The `contains`
    predicate is what theorems reason over, and it's monotone under
    cons regardless of duplicates. -/
def ConsumedSet.add (cs : ConsumedSet) (id : String) : ConsumedSet :=
  { ids := id :: cs.ids }

/-- After `add`, the id is in the set. -/
theorem ConsumedSet.add_contains (cs : ConsumedSet) (id : String) :
    (cs.add id).contains id := by
  unfold ConsumedSet.add ConsumedSet.contains
  exact List.mem_cons_self

/-- Adding a different id preserves containment of the first. -/
theorem ConsumedSet.add_other_preserves
    (cs : ConsumedSet) (a b : String) :
    cs.contains a → (cs.add b).contains a := by
  intro h
  unfold ConsumedSet.add ConsumedSet.contains
  unfold ConsumedSet.contains at h
  exact List.mem_cons_of_mem b h

/-- The K1 enforcement helper: "assert linear" returns ok iff the
    cell-id is NOT yet in the consumed set. Mirrors the TS
    `assertLinear`. -/
def assertLinear (cs : ConsumedSet) (id : String) : Result Unit :=
  if cs.containsBool id then
    .error .cellAlreadyConsumed
  else
    .ok ()

/-- Bridge: `containsBool = true` iff `contains`. -/
theorem ConsumedSet.containsBool_iff_contains (cs : ConsumedSet) (id : String) :
    cs.containsBool id = true ↔ cs.contains id := by
  unfold ConsumedSet.containsBool ConsumedSet.contains
  exact List.elem_iff

theorem assertLinear_ok_of_fresh (cs : ConsumedSet) (id : String)
    (h : ¬ cs.contains id) : assertLinear cs id = .ok () := by
  unfold assertLinear
  have h2 : cs.containsBool id = false := by
    rw [Bool.eq_false_iff]
    intro heq
    exact h ((cs.containsBool_iff_contains id).mp heq)
  simp [h2]

theorem assertLinear_err_of_consumed (cs : ConsumedSet) (id : String)
    (h : cs.contains id) :
    assertLinear cs id = .error .cellAlreadyConsumed := by
  unfold assertLinear
  have h2 : cs.containsBool id = true :=
    (cs.containsBool_iff_contains id).mpr h
  simp [h2]

/-- Second `assertLinear` on the same id, AFTER `add`, fails. The
    substrate-level shape that backs every per-FSM
    `*_consumed_cell_rejected` theorem. -/
theorem assertLinear_after_add_rejects
    (cs : ConsumedSet) (id : String) :
    assertLinear (cs.add id) id = .error .cellAlreadyConsumed := by
  apply assertLinear_err_of_consumed
  exact cs.add_contains id

end Semantos.Extensions.Oddjobz.StateMachines.Common

```
