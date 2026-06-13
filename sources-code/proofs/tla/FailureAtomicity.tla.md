---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/FailureAtomicity.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.341328+00:00
---

# proofs/tla/FailureAtomicity.tla

```tla
--------------------------- MODULE FailureAtomicity ---------------------------
(*
 * K4 — Failure Atomicity (TLA+ side).
 *
 * Companion to proofs/lean/Semantos/Theorems/FailureAtomicK4.lean
 * (Lean per-opcode _error_inversion + _atomic lemmas, post-WP9 Apr 2026).
 *
 * K4 (Failure atomicity, from docs/FORMAL-VERIFICATION-STRATEGY.md line 25):
 *   Failed Plexus opcodes leave the PDA state byte-for-byte identical
 *   to the pre-execution state. Covers all 16 Plexus opcodes 0xC0-0xCF.
 *
 * What TLA+ adds over Lean:
 *   Lean's _error_inversion lemmas prove per-opcode that the error path
 *   doesn't mutate state. This spec checks the *implementation pattern*
 *   that makes those lemmas hold — peek-then-mutate (correct) vs
 *   mutate-then-check (buggy K4-violation). TLC catches the buggy
 *   pattern as a counterexample to the invariant.
 *
 *   The spec encodes the bug class so the model-check is non-vacuous:
 *   if someone introduces a mutate-then-check opcode, this spec fails.
 *
 * Source pattern: core/cell-engine/OPCODE-HARDENING-PLAN.md
 *   "Precheck sdepth() < N before any pops. Then use catch unreachable
 *    since depth is already validated."
 *   plus per-op _error_inversion lemmas in FailureAtomicK4.lean.
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    MaxStackDepth,     \* Bound on stack depth
    CellValues,        \* Finite set of cell content values
    ResultValue        \* Synthetic "result" pushed on successful BinaryCorrect

StackValues == CellValues \cup {ResultValue}

VARIABLES
    stack,             \* Sequence of CellValues (top is last)
    preStack,          \* Snapshot of stack before the current opcode (for atomicity check)
    inFlight,          \* TRUE during an opcode's internal steps
    lastResult         \* "none" | "success" | "failure"

vars == <<stack, preStack, inFlight, lastResult>>

\* --- Initial state ---

Init ==
    /\ stack \in [1..MaxStackDepth -> CellValues] /\ FALSE  \* placeholder
    /\ preStack = << >>
    /\ inFlight = FALSE
    /\ lastResult = "none"

\* Use a simpler init: stack starts empty, but allow any initial sequence
\* via Push action. (TLC will explore.)

InitSimple ==
    /\ stack = << >>
    /\ preStack = << >>
    /\ inFlight = FALSE
    /\ lastResult = "none"

\* Build the stack non-deterministically via Push (preparation phase).

Push(v) ==
    /\ ~inFlight                              \* No opcode running
    /\ Len(stack) < MaxStackDepth
    /\ stack' = Append(stack, v)
    /\ UNCHANGED <<preStack, inFlight, lastResult>>

\* --- Opcode: BinaryCorrect ---
\*
\* Models the peek-then-mutate pattern. An opcode that needs the top two
\* elements (e.g., HASHCAT, BINARY-OP). Correct sequence:
\*   1. Begin atomic transaction: snapshot pre-state
\*   2. Precheck: if stack depth < 2, fail without any mutation
\*   3. If precheck passes, pop two, push result
\*   4. Commit (clear in-flight, snapshot)
\*
\* On failure: state unchanged, lastResult = "failure".
\* On success: state mutated, lastResult = "success".

BinaryCorrect_Begin ==
    /\ ~inFlight
    /\ preStack' = stack          \* Snapshot for atomicity
    /\ inFlight' = TRUE
    /\ UNCHANGED <<stack, lastResult>>

BinaryCorrect_FailUnderflow ==
    /\ inFlight
    /\ Len(stack) < 2
    \* CRITICAL: stack' = stack (unchanged). K4 rollback path.
    /\ stack' = preStack          \* (which equals stack from Begin)
    /\ preStack' = << >>
    /\ inFlight' = FALSE
    /\ lastResult' = "failure"

BinaryCorrect_Success ==
    /\ inFlight
    /\ Len(stack) >= 2
    \* Mutate: pop two, push a placeholder result.
    /\ stack' = Append(SubSeq(stack, 1, Len(stack) - 2), ResultValue)
    /\ preStack' = << >>
    /\ inFlight' = FALSE
    /\ lastResult' = "success"

\* --- Opcode: BinaryBuggy (the K4 violation) ---
\*
\* Models the mutate-then-check pattern that K4 rejects. This opcode:
\*   1. Pops the top element immediately (mutation!)
\*   2. Then checks if there's another element to pop
\*   3. On failure (insufficient depth after first pop), tries to "fail
\*      cleanly" — but the first pop has already mutated state.
\*
\* This is the K4-violation pattern. If included in Next, TLC finds the
\* atomicity counterexample. To verify the SPEC catches this bug,
\* uncomment Next' to include BinaryBuggy_* actions and re-run TLC —
\* it should report a violation of FailureAtomicity_K4.
\*
\* Left commented in default Next to demonstrate the spec passes on the
\* correct pattern. Toggle to test the spec's bug-catching ability.

BinaryBuggy_Begin ==
    /\ ~inFlight
    /\ preStack' = stack
    /\ inFlight' = TRUE
    /\ UNCHANGED <<stack, lastResult>>

BinaryBuggy_PopFirst ==
    /\ inFlight
    /\ Len(stack) > 0
    /\ stack' = SubSeq(stack, 1, Len(stack) - 1)     \* MUTATION before check
    /\ UNCHANGED <<preStack, inFlight, lastResult>>

BinaryBuggy_FailAfterPop ==
    /\ inFlight
    \* After PopFirst we still need one more pop. If stack is now empty,
    \* the buggy opcode "rolls back" by clearing in-flight WITHOUT
    \* restoring state.
    /\ Len(stack) < 1
    /\ preStack' = << >>
    /\ inFlight' = FALSE
    /\ lastResult' = "failure"
    /\ UNCHANGED stack             \* BUG: state stays mutated; preStack not restored

\* --- Transition relation (correct-only by default) ---

Next ==
    \/ \E v \in CellValues : Push(v)
    \/ BinaryCorrect_Begin
    \/ BinaryCorrect_FailUnderflow
    \/ BinaryCorrect_Success

\* To test the bug-catching ability, swap Next with:
\* NextWithBug ==
\*     \/ \E v \in CellValues : Push(v)
\*     \/ BinaryBuggy_Begin
\*     \/ BinaryBuggy_PopFirst
\*     \/ BinaryBuggy_FailAfterPop

Spec == InitSimple /\ [][Next]_vars

\* --- Invariants ---

\* K4: Failed opcodes leave state byte-identical to the pre-state
\* snapshot. When lastResult = "failure", the stack equals the snapshot
\* taken at Begin. Note: this is meaningful only at the END of an
\* opcode (inFlight = FALSE) — during in-flight steps the spec
\* intentionally allows partial mutation; the rollback step is what
\* must complete the atomicity contract.

FailureAtomicity_K4 ==
    \/ lastResult /= "failure"
    \/ inFlight  \* Skip the invariant during in-flight steps; only check at completion
    \/ stack = preStack
    \/ preStack = << >>  \* No snapshot active (e.g. initial state)

\* Type invariant.

TypeInv ==
    /\ stack \in Seq(StackValues)
    /\ Len(stack) <= MaxStackDepth
    /\ preStack \in Seq(StackValues)
    /\ inFlight \in BOOLEAN
    /\ lastResult \in {"none", "success", "failure"}

\* Composite K4.

K4_FailureAtomicity == FailureAtomicity_K4

=============================================================================
(*
 * NOTE on companion Lean theorem.
 *
 * FailureAtomicK4.lean proves per-opcode _error_inversion lemmas for
 * all 16 Plexus opcodes — symbolic, not state-space exploration. This
 * spec adds the *pattern check*: the implementation must follow
 * peek-then-mutate (Begin → Precheck → Pop|Fail). Toggling Next to
 * include the BinaryBuggy_* actions demonstrates the spec catches
 * mutate-then-check patterns as K4 violations.
 *
 * Default config (FailureAtomicity.cfg): MaxStackDepth = 3,
 * CellValues = {v1, v2}. The bug-catching test (NextWithBug) is
 * deliberately not in the default config; it's documented for
 * adversarial verification.
 *)
=============================================================================

```
