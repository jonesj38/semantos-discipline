---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/lean4/BranchOnOutput.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.991289+00:00
---

# core/cell-engine/lean4/BranchOnOutput.lean

```lean
/-
  Formal verification of OP_BRANCHONOUTPUT invariants — Phase 2.

  Spec:    ../../docs/design/OP-BRANCHONOUTPUT-SPEC.md
  Tracker: ../../docs/OP-BRANCHONOUTPUT-TRACKER.md

  We define a shallow embedding of the cell-engine stack machine sufficient
  to prove the spec's invariants:

    T1 — determinism             stepOp on equal inputs gives equal outputs
    T2 — stack delta = +1        executing OP_BRANCHONOUTPUT pushes exactly one item
    T3 — non-malleability        no opcode can write tx.currentOutputIndex
    T4 — observation closure     scripts without OP_BRANCHONOUTPUT are independent
                                  of currentOutputIndex (the meta-property that
                                  underwrites the LINEAR single-claim guarantee)

  All four are machine-checked, no `sorry`.  T3 is the load-bearing
  safety theorem: no opcode in the cell engine can write
  `currentOutputIndex`, so the only path by which the script observes
  the runtime's choice of output is through the `branchOnOutput` opcode.

  T4 lifts that to the meta-property that scripts not containing
  `branchOnOutput` produce results independent of `currentOutputIndex`
  — i.e., the opcode is the SOLE discriminator.  Proved by a parallel-
  evaluation invariant (`EqExceptTxc`) preserved across single steps
  for every non-`branchOnOutput` opcode, lifted to `runScript` by
  induction, then projected onto the truthy-stack-top check.

  No Mathlib used — just core Lean 4.29.1 tactics (by_cases, cases,
  simp only with explicit rewrites).
-/

namespace BranchOnOutput

/-! ## Core types -/

/-- 4-byte little-endian encoding of a `UInt32`.  Matches the Zig implementation
    in `src/opcodes/routing.zig`. -/
def u32ToLE (n : UInt32) : List UInt8 :=
  let v := n.toNat
  [ UInt8.ofNat (v        &&& 0xff)
  , UInt8.ofNat ((v >>> 8 ) &&& 0xff)
  , UInt8.ofNat ((v >>> 16) &&& 0xff)
  , UInt8.ofNat ((v >>> 24) &&& 0xff) ]

theorem u32ToLE_length (n : UInt32) : (u32ToLE n).length = 4 := by
  simp [u32ToLE]

/-- Transaction context exposing read-only fields to the script.
    Only `currentOutputIndex` is modelled — the spec property to prove
    is that no opcode can write it. -/
structure TxContext where
  currentOutputIndex : UInt32
  deriving DecidableEq, Repr

abbrev Item := List UInt8

/-- The minimal opcode set sufficient to express routing scripts. -/
inductive OpCode
  | push (data : Item)
  | dup
  | drop
  | equal
  | if_op
  | else_op
  | endif_op
  | checksig (sigOk : Bool)
  | branchOnOutput
  deriving DecidableEq, Repr

abbrev Script := List OpCode

structure ExecCtx where
  stack     : List Item
  condStack : List Bool
  executing : Bool
  txc       : TxContext
  deriving DecidableEq, Repr

inductive StepResult
  | ok  (ctx : ExecCtx)
  | err
  deriving DecidableEq, Repr

/-! ## Helpers -/

def truthy : Item → Bool
  | []      => false
  | b :: bs => decide (b ≠ 0) || (bs.any (· ≠ 0))

def boolToItem (b : Bool) : Item := if b then [1] else []

def allTrue : List Bool → Bool
  | []      => true
  | b :: bs => b && allTrue bs

/-! ## Small-step semantics

    `stepOp` is the central definition.  Critically: NO branch updates
    `ctx.txc`.  This structural property is what T3 captures. -/

def stepOp (op : OpCode) (ctx : ExecCtx) : StepResult :=
  if ctx.executing then
    match op with
    | .push data =>
        .ok { ctx with stack := data :: ctx.stack }
    | .dup =>
        match ctx.stack with
        | top :: _ => .ok { ctx with stack := top :: ctx.stack }
        | []       => .err
    | .drop =>
        match ctx.stack with
        | _ :: rest => .ok { ctx with stack := rest }
        | []        => .err
    | .equal =>
        match ctx.stack with
        | a :: b :: rest =>
            .ok { ctx with stack := boolToItem (decide (a = b)) :: rest }
        | _ => .err
    | .if_op =>
        match ctx.stack with
        | top :: rest =>
            let t := truthy top
            .ok { ctx with
                  stack     := rest
                  condStack := t :: ctx.condStack
                  executing := t && ctx.executing }
        | [] => .err
    | .else_op =>
        match ctx.condStack with
        | b :: rest =>
            .ok { ctx with
                  condStack := (!b) :: rest
                  executing := (!b) && allTrue rest }
        | [] => .err
    | .endif_op =>
        match ctx.condStack with
        | _ :: rest =>
            .ok { ctx with
                  condStack := rest
                  executing := allTrue rest }
        | [] => .err
    | .checksig sigOk =>
        match ctx.stack with
        | _ :: _ :: rest =>
            .ok { ctx with stack := boolToItem sigOk :: rest }
        | _ => .err
    | .branchOnOutput =>
        -- The ONLY opcode that reads ctx.txc.  Note: ctx.txc is not mutated.
        .ok { ctx with stack := u32ToLE ctx.txc.currentOutputIndex :: ctx.stack }
  else
    match op with
    | .if_op =>
        .ok { ctx with condStack := false :: ctx.condStack }
    | .else_op =>
        match ctx.condStack with
        | b :: rest =>
            .ok { ctx with
                  condStack := (!b) :: rest
                  executing := (!b) && allTrue rest }
        | [] => .err
    | .endif_op =>
        match ctx.condStack with
        | _ :: rest =>
            .ok { ctx with
                  condStack := rest
                  executing := allTrue rest }
        | [] => .err
    | _ => .ok ctx

def runScript : Script → ExecCtx → Option ExecCtx
  | [],         ctx => some ctx
  | op :: rest, ctx =>
      match stepOp op ctx with
      | .ok ctx' => runScript rest ctx'
      | .err     => none

def scriptDoneTrue (s : Script) (ctx : ExecCtx) : Bool :=
  match runScript s ctx with
  | some ctx' =>
      match ctx'.stack with
      | top :: _ => truthy top
      | []       => false
  | none => false

/-! ## Theorems -/

/-! ### T1 — Determinism

    `stepOp` is a (Lean) total function, so determinism on any opcode
    holds by congruence. -/
theorem T1_determinism
    (ctx₁ ctx₂ : ExecCtx) (h : ctx₁ = ctx₂) :
    stepOp .branchOnOutput ctx₁ = stepOp .branchOnOutput ctx₂ := by
  rw [h]

/-! ### T2 — Stack delta = +1

    On the executing branch, `OP_BRANCHONOUTPUT` always succeeds and the
    resulting stack has exactly one more entry.  In a non-executing
    branch it is a complete no-op. -/
theorem T2_stack_delta_plus_one
    (ctx : ExecCtx) (h_exec : ctx.executing = true) :
    ∃ ctx', stepOp .branchOnOutput ctx = .ok ctx' ∧
            ctx'.stack.length = ctx.stack.length + 1 := by
  refine ⟨{ ctx with stack := u32ToLE ctx.txc.currentOutputIndex :: ctx.stack }, ?_, ?_⟩
  · simp [stepOp, h_exec]
  · simp

theorem T2_skip_when_not_executing
    (ctx : ExecCtx) (h : ctx.executing = false) :
    stepOp .branchOnOutput ctx = .ok ctx := by
  simp [stepOp, h]

/-! ### T3 — Non-malleability of `currentOutputIndex`

    The load-bearing safety theorem.  Every opcode's `stepOp` body uses
    the record-update form `{ ctx with ... }` and never assigns to `txc`
    — so the structural fact that `ctx'.txc = ctx.txc` holds for every
    successful step, regardless of the opcode.

    Lifted to `runScript` by induction, this means no script (whatever
    its sequence of opcodes) can change `currentOutputIndex` between
    entry and exit.  This is what prevents a malicious script from
    forging a different output index to the cell engine. -/

theorem T3_step_preserves_txc
    (op : OpCode) (ctx ctx' : ExecCtx)
    (h : stepOp op ctx = .ok ctx') :
    ctx'.txc = ctx.txc := by
  -- We case on the structure of `op` and the `executing` flag.  In every
  -- non-erroring branch of `stepOp`, the result is `{ ctx with stack := ... }`
  -- or `{ ctx with condStack := ... }` or `{ ctx with executing := ... }`
  -- or a combination — none of which touch `ctx.txc`.
  unfold stepOp at h
  split at h
  · -- executing = true
    split at h
    all_goals (
      first
      | (cases h; rfl)
      | (split at h <;>
          first | (cases h; rfl) | cases h)
    )
  · -- executing = false
    split at h
    all_goals (
      first
      | (cases h; rfl)
      | (split at h <;>
          first | (cases h; rfl) | cases h)
    )

/-- Corollary: `currentOutputIndex` specifically is preserved. -/
theorem T3_step_preserves_outputIdx
    (op : OpCode) (ctx ctx' : ExecCtx)
    (h : stepOp op ctx = .ok ctx') :
    ctx'.txc.currentOutputIndex = ctx.txc.currentOutputIndex := by
  rw [T3_step_preserves_txc op ctx ctx' h]

/-- Multi-step preservation: `runScript` preserves the full `txc`. -/
theorem T3_runScript_preserves_txc
    (s : Script) (ctx ctx' : ExecCtx)
    (h : runScript s ctx = some ctx') :
    ctx'.txc = ctx.txc := by
  induction s generalizing ctx with
  | nil =>
      simp [runScript] at h
      exact congrArg (·.txc) h.symm
  | cons op rest ih =>
      simp only [runScript] at h
      split at h
      case h_1 ctx_mid h_step =>
          have h_pres : ctx_mid.txc = ctx.txc :=
            T3_step_preserves_txc op ctx ctx_mid h_step
          have h_rest : ctx'.txc = ctx_mid.txc := ih ctx_mid h
          rw [h_rest, h_pres]
      case h_2 => cases h

/-- Multi-step preservation, lifted to the spec's exact statement. -/
theorem T3_runScript_preserves_outputIdx
    (s : Script) (ctx ctx' : ExecCtx)
    (h : runScript s ctx = some ctx') :
    ctx'.txc.currentOutputIndex = ctx.txc.currentOutputIndex := by
  rw [T3_runScript_preserves_txc s ctx ctx' h]

/-! ### T4 — Observation closure (statement + outline)

    The full T4 theorem says: a script that does NOT contain `branchOnOutput`
    produces a result independent of `currentOutputIndex`.

    Stated formally:

      ∀ (s : Script) (ctx : ExecCtx) (i j : UInt32),
        ¬ usesBranchOnOutput s →
        scriptDoneTrue s (withOutputIndex ctx i)
          = scriptDoneTrue s (withOutputIndex ctx j)

    Proof sketch (deferred — multi-hundred-line tactic work):

      1. By induction on `s`.
      2. Base case (`s = []`): both runScripts return `ctx` directly,
         which has identical non-txc fields and only differs in txc;
         the truthy check on the stack top is independent of txc.
      3. Inductive step (`s = op :: rest`):
         a. If `op = branchOnOutput`: contradiction with `¬ usesBranchOnOutput`.
         b. Otherwise: the step result for `c_i` and `c_j` agree on
            `stack`, `condStack`, and `executing` (provable by case analysis
            over `op` — each branch's update is a function of those three
            fields only, never of `txc`).  Apply induction hypothesis.

    The structural fact in step (3b) is essentially T3 strengthened from
    "txc is preserved" to "the non-txc fields are a function of the non-txc
    fields of the input."  A clean formalisation requires either parallel
    coupled evaluation or a refactor of `stepOp` to factor out the txc
    dependency; both are tractable but each is 200-400 lines of tactic
    work that we land in a follow-up.

    Land justification: T3 (non-malleability) is the safety-critical
    theorem the cell engine and TLA+ model depend on.  T4 is a
    completeness property that strengthens the I4 single-claim claim in
    the spec — important but not required for the implementation to be
    correct.  The TLA+ model (RoutingPayment.tla) takes T4 as an axiom
    (via the `NoCrossClaim` invariant) and verifies the system-level
    consequence over the full state space; this is a reasonable interim
    bridge until the Lean4 T4 lands. -/

/-- A script "uses BRANCHONOUTPUT" iff any opcode in it is `branchOnOutput`. -/
def usesBranchOnOutput : Script → Prop
  | []                  => False
  | .branchOnOutput :: _ => True
  | _ :: rest           => usesBranchOnOutput rest

/-- Re-bind the tx context (what the runtime does per output evaluation). -/
def withOutputIndex (ctx : ExecCtx) (i : UInt32) : ExecCtx :=
  { ctx with txc := { currentOutputIndex := i } }

/-- Two contexts agree on every field except `txc`. -/
structure EqExceptTxc (c₁ c₂ : ExecCtx) : Prop where
  stack     : c₁.stack = c₂.stack
  condStack : c₁.condStack = c₂.condStack
  executing : c₁.executing = c₂.executing

theorem EqExceptTxc.refl (c : ExecCtx) : EqExceptTxc c c := ⟨rfl, rfl, rfl⟩

theorem withOutputIndex_eqExceptTxc (ctx : ExecCtx) (i j : UInt32) :
    EqExceptTxc (withOutputIndex ctx i) (withOutputIndex ctx j) :=
  ⟨rfl, rfl, rfl⟩

theorem usesBranchOnOutput_cons
    {op : OpCode} {rest : Script}
    (h : ¬ usesBranchOnOutput (op :: rest)) :
    op ≠ .branchOnOutput ∧ ¬ usesBranchOnOutput rest := by
  refine ⟨?_, ?_⟩
  · intro heq
    cases heq
    exact h trivial
  · intro h_rest
    apply h
    cases op <;> first | exact h_rest | trivial

/-- Step preservation: for `op ≠ branchOnOutput`, two contexts that
    agree on every non-txc field step to results that also agree on
    every non-txc field (or both error).  Proved by explicit case
    analysis on `op`, the `executing` flag, and the relevant
    stack/condStack pattern — no Mathlib automation. -/
theorem step_non_branch_preserves_eqExceptTxc
    (op : OpCode) (h_op : op ≠ .branchOnOutput)
    (c₁ c₂ : ExecCtx) (h_eq : EqExceptTxc c₁ c₂) :
    (match stepOp op c₁, stepOp op c₂ with
     | .ok c₁', .ok c₂' => EqExceptTxc c₁' c₂'
     | .err,    .err    => True
     | _,       _       => False) := by
  obtain ⟨hs, hc, he⟩ := h_eq
  cases op with
  | branchOnOutput => exact absurd rfl h_op
  | push d =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp [stepOp, hex, hex₂]
      exact ⟨by simp [hs], hc, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp [stepOp, hex', hex₂]
      exact ⟨hs, hc, he⟩
  | dup =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_stack : c₁.stack with
      | nil =>
        have h_stack₂ : c₂.stack = [] := hs ▸ h_stack
        simp [h_stack, h_stack₂]
      | cons top rest =>
        have h_stack₂ : c₂.stack = top :: rest := hs ▸ h_stack
        simp [h_stack, h_stack₂]
        exact ⟨by simp [hs], hc, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp [stepOp, hex', hex₂]
      exact ⟨hs, hc, he⟩
  | drop =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_stack : c₁.stack with
      | nil =>
        have h_stack₂ : c₂.stack = [] := hs ▸ h_stack
        simp [h_stack, h_stack₂]
      | cons _ rest =>
        have h_stack₂ : c₂.stack = _ :: rest := hs ▸ h_stack
        simp [h_stack, h_stack₂]
        exact ⟨rfl, hc, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp [stepOp, hex', hex₂]
      exact ⟨hs, hc, he⟩
  | equal =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_stack : c₁.stack with
      | nil =>
        have h_stack₂ : c₂.stack = [] := hs ▸ h_stack
        simp [h_stack, h_stack₂]
      | cons a rest₁ =>
        cases h_rest : rest₁ with
        | nil =>
          have h_stack₂ : c₂.stack = [a] := hs ▸ h_stack ▸ h_rest ▸ rfl
          simp [h_stack, h_rest, h_stack₂]
        | cons b rest₂ =>
          have h_stack₂ : c₂.stack = a :: b :: rest₂ :=
            hs ▸ h_stack ▸ h_rest ▸ rfl
          simp [h_stack, h_rest, h_stack₂]
          exact ⟨rfl, hc, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp [stepOp, hex', hex₂]
      exact ⟨hs, hc, he⟩
  | if_op =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_stack : c₁.stack with
      | nil =>
        have h_stack₂ : c₂.stack = [] := hs ▸ h_stack
        simp [h_stack, h_stack₂]
      | cons top rest =>
        have h_stack₂ : c₂.stack = top :: rest := hs ▸ h_stack
        simp [h_stack, h_stack₂]
        refine ⟨rfl, by simp [hc], by simp [he]⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp only [stepOp, hex', hex₂, if_false]
      exact ⟨hs, by simp [hc], rfl⟩
  | else_op =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_cond : c₁.condStack with
      | nil =>
        have h_cond₂ : c₂.condStack = [] := hc ▸ h_cond
        simp [h_cond, h_cond₂]
      | cons b rest =>
        have h_cond₂ : c₂.condStack = b :: rest := hc ▸ h_cond
        simp [h_cond, h_cond₂]
        exact ⟨hs, rfl, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp only [stepOp, hex', hex₂, if_false]
      cases h_cond : c₁.condStack with
      | nil =>
        have h_cond₂ : c₂.condStack = [] := hc ▸ h_cond
        simp [h_cond, h_cond₂]
      | cons b rest =>
        have h_cond₂ : c₂.condStack = b :: rest := hc ▸ h_cond
        simp [h_cond, h_cond₂]
        exact ⟨hs, rfl, rfl⟩
  | endif_op =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_cond : c₁.condStack with
      | nil =>
        have h_cond₂ : c₂.condStack = [] := hc ▸ h_cond
        simp [h_cond, h_cond₂]
      | cons _ rest =>
        have h_cond₂ : c₂.condStack = _ :: rest := hc ▸ h_cond
        simp [h_cond, h_cond₂]
        exact ⟨hs, rfl, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp only [stepOp, hex', hex₂, if_false]
      cases h_cond : c₁.condStack with
      | nil =>
        have h_cond₂ : c₂.condStack = [] := hc ▸ h_cond
        simp [h_cond, h_cond₂]
      | cons _ rest =>
        have h_cond₂ : c₂.condStack = _ :: rest := hc ▸ h_cond
        simp [h_cond, h_cond₂]
        exact ⟨hs, rfl, rfl⟩
  | checksig sigOk =>
    by_cases hex : c₁.executing = true
    · have hex₂ : c₂.executing = true := he ▸ hex
      simp only [stepOp, hex, hex₂, if_true]
      cases h_stack : c₁.stack with
      | nil =>
        have h_stack₂ : c₂.stack = [] := hs ▸ h_stack
        simp [h_stack, h_stack₂]
      | cons a rest₁ =>
        cases h_rest : rest₁ with
        | nil =>
          have h_stack₂ : c₂.stack = [a] := hs ▸ h_stack ▸ h_rest ▸ rfl
          simp [h_stack, h_rest, h_stack₂]
        | cons b rest₂ =>
          have h_stack₂ : c₂.stack = a :: b :: rest₂ :=
            hs ▸ h_stack ▸ h_rest ▸ rfl
          simp [h_stack, h_rest, h_stack₂]
          exact ⟨rfl, hc, rfl⟩
    · have hex' : c₁.executing = false := by cases h : c₁.executing <;> simp_all
      have hex₂ : c₂.executing = false := he ▸ hex'
      simp [stepOp, hex', hex₂]
      exact ⟨hs, hc, he⟩

/-- Multi-step preservation: a script without `branchOnOutput`
    preserves `EqExceptTxc` across `runScript`. -/
theorem runScript_non_branch_preserves_eqExceptTxc
    (s : Script) (h_no_branch : ¬ usesBranchOnOutput s)
    (c₁ c₂ : ExecCtx) (h_eq : EqExceptTxc c₁ c₂) :
    (match runScript s c₁, runScript s c₂ with
     | some c₁', some c₂' => EqExceptTxc c₁' c₂'
     | none,     none     => True
     | _,        _        => False) := by
  induction s generalizing c₁ c₂ with
  | nil =>
    simp [runScript]
    exact h_eq
  | cons op rest ih =>
    obtain ⟨h_op, h_rest⟩ := usesBranchOnOutput_cons h_no_branch
    have h_step := step_non_branch_preserves_eqExceptTxc op h_op c₁ c₂ h_eq
    simp only [runScript]
    match hsi : stepOp op c₁, hsj : stepOp op c₂ with
    | .ok c₁', .ok c₂' =>
      rw [hsi, hsj] at h_step
      exact ih h_rest c₁' c₂' h_step
    | .err, .err =>
      trivial
    | .ok _, .err =>
      rw [hsi, hsj] at h_step
      exact h_step.elim
    | .err, .ok _ =>
      rw [hsi, hsj] at h_step
      exact h_step.elim

/-- T4 — observation closure.

    A script that does not contain `branchOnOutput` produces the same
    `scriptDoneTrue` result for any two contexts that differ only in
    `currentOutputIndex`.  Therefore `branchOnOutput` is the sole
    channel through which the runtime's choice of output reaches the
    script's truth value — exactly the meta-property that underwrites
    the spec's I4 LINEAR single-claim guarantee. -/
theorem T4_branchOnOutput_is_sole_observer
    (s : Script) (ctx : ExecCtx) (i j : UInt32)
    (h_no_branch : ¬ usesBranchOnOutput s) :
    scriptDoneTrue s (withOutputIndex ctx i) =
      scriptDoneTrue s (withOutputIndex ctx j) := by
  have h_eq : EqExceptTxc (withOutputIndex ctx i) (withOutputIndex ctx j) :=
    withOutputIndex_eqExceptTxc ctx i j
  have h_run := runScript_non_branch_preserves_eqExceptTxc s h_no_branch
                  (withOutputIndex ctx i) (withOutputIndex ctx j) h_eq
  simp only [scriptDoneTrue]
  match hri : runScript s (withOutputIndex ctx i),
        hrj : runScript s (withOutputIndex ctx j) with
  | some c₁', some c₂' =>
    rw [hri, hrj] at h_run
    have hs := h_run.stack
    cases h₁ : c₁'.stack with
    | nil =>
      have h₂ : c₂'.stack = [] := by rw [← hs, h₁]
      simp [h₁, h₂]
    | cons top₁ rest₁ =>
      have h₂ : c₂'.stack = top₁ :: rest₁ := by rw [← hs, h₁]
      simp [h₁, h₂]
  | none, none => rfl
  | some _, none =>
    -- h_run's match collapses to False on (some _, none); fold via simp.
    simp [hri, hrj] at h_run
  | none, some _ =>
    simp [hri, hrj] at h_run

end BranchOnOutput

```
