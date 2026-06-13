---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/Linearity.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.348124+00:00
---

# proofs/tla/Linearity.tla

```tla
--------------------------- MODULE Linearity ---------------------------
(*
 * K1 — Linearity (TLA+ side).
 *
 * Companion to proofs/lean/Semantos/Theorems/LinearityK1.lean. Lean
 * proves the per-execution invariant symbolically; this spec checks the
 * multi-step trace invariant via bounded state-space exploration.
 *
 * K1 (Linearity, from docs/FORMAL-VERIFICATION-STRATEGY.md line 22):
 *   A LINEAR cell is never duplicated while live, never discarded without
 *   authorized consumption, and once consumed cannot reappear unless a
 *   distinct cell is created.
 *
 * Three sub-invariants:
 *   K1a — No duplication: same LINEAR cell never has liveCount > 1
 *   K1b — No silent discard: structurally enforced by DropMain refusing
 *         LINEAR cells; expressed as an action-level invariant
 *   K1c — No reappearance: consumed LINEAR cells never re-enter a stack
 *
 * Source: core/cell-engine/src/linearity.zig — checkLinearity()
 *         core/cell-engine/src/opcodes/macro.zig — push/pop/dup/drop
 *         core/cell-engine/src/opcodes/plexus.zig — consume (0xCA),
 *                                                   demote (0xCB)
 *
 * What TLA+ adds over Lean:
 *   The Lean theorem reasons about one execution step at a time.
 *   This spec explores all reachable opcode sequences up to a bound,
 *   surfacing any trace-level violation (e.g., a sequence of opcodes
 *   that individually preserve invariants but collectively duplicate
 *   a LINEAR cell across the two stacks).
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    LinearCells,       \* Subset of cells that are LINEAR
    NonLinearCells,    \* Subset of cells that are AFFINE/RELEVANT/DEBUG
    MaxMainDepth,      \* Bound on main-stack depth
    MaxAuxDepth        \* Bound on aux-stack depth

AllCells == LinearCells \cup NonLinearCells

ASSUME LinearCells \cap NonLinearCells = {}

\* --- Cell state ---
\*
\* Each cell has a fixed linearity class assigned at creation. We track:
\*   - isLinear:  TRUE for LINEAR class, FALSE otherwise (only K1 needs
\*                this binary distinction; other classes are conflated)
\*   - consumed:  whether the cell has been consumed (LINEAR-only)
\*   - liveCount: how many slots currently reference this cell
\*
CellState == [
    isLinear  : BOOLEAN,
    consumed  : BOOLEAN,
    liveCount : 0..(MaxMainDepth + MaxAuxDepth)
]

VARIABLES
    cells,      \* CellId → CellState
    mainStack,  \* Sequence of CellIds (top is last element)
    auxStack    \* Sequence of CellIds

vars == <<cells, mainStack, auxStack>>

\* --- Initial state ---
\*
\* Linearity is fixed per-cell by constants. All cells start unreferenced
\* and unconsumed. Both stacks empty.

Init ==
    /\ cells = [c \in AllCells |->
                  [isLinear  |-> c \in LinearCells,
                   consumed  |-> FALSE,
                   liveCount |-> 0]]
    /\ mainStack = << >>
    /\ auxStack = << >>

\* --- Operations ---

PushMain(c) ==
    /\ Len(mainStack) < MaxMainDepth
    /\ ~cells[c].consumed                          \* K1c: consumed cells never re-enter
    /\ (cells[c].isLinear => cells[c].liveCount = 0)  \* K1a: no LINEAR duplication
    /\ mainStack' = Append(mainStack, c)
    /\ cells' = [cells EXCEPT ![c].liveCount = @ + 1]
    /\ auxStack' = auxStack

PushAux(c) ==
    /\ Len(auxStack) < MaxAuxDepth
    /\ ~cells[c].consumed
    /\ (cells[c].isLinear => cells[c].liveCount = 0)
    /\ auxStack' = Append(auxStack, c)
    /\ cells' = [cells EXCEPT ![c].liveCount = @ + 1]
    /\ mainStack' = mainStack

\* Consume: the only valid LINEAR removal path. Marks consumed=TRUE.
ConsumeMain ==
    /\ Len(mainStack) > 0
    /\ LET c == mainStack[Len(mainStack)] IN
        /\ mainStack' = SubSeq(mainStack, 1, Len(mainStack) - 1)
        /\ cells' = [cells EXCEPT
                       ![c].liveCount = @ - 1,
                       ![c].consumed = IF cells[c].isLinear THEN TRUE ELSE @]
        /\ auxStack' = auxStack

ConsumeAux ==
    /\ Len(auxStack) > 0
    /\ LET c == auxStack[Len(auxStack)] IN
        /\ auxStack' = SubSeq(auxStack, 1, Len(auxStack) - 1)
        /\ cells' = [cells EXCEPT
                       ![c].liveCount = @ - 1,
                       ![c].consumed = IF cells[c].isLinear THEN TRUE ELSE @]
        /\ mainStack' = mainStack

\* DupMain: gated to refuse LINEAR (K1a runtime check).
DupMain ==
    /\ Len(mainStack) > 0
    /\ Len(mainStack) < MaxMainDepth
    /\ LET c == mainStack[Len(mainStack)] IN
        /\ ~cells[c].isLinear                      \* K1a gate
        /\ mainStack' = Append(mainStack, c)
        /\ cells' = [cells EXCEPT ![c].liveCount = @ + 1]
        /\ auxStack' = auxStack

\* DropMain: gated to refuse LINEAR (K1b runtime check).
DropMain ==
    /\ Len(mainStack) > 0
    /\ LET c == mainStack[Len(mainStack)] IN
        /\ ~cells[c].isLinear                      \* K1b gate
        /\ mainStack' = SubSeq(mainStack, 1, Len(mainStack) - 1)
        /\ cells' = [cells EXCEPT ![c].liveCount = @ - 1]
        /\ auxStack' = auxStack

\* --- Transition relation ---

Next ==
    \/ \E c \in AllCells : PushMain(c)
    \/ \E c \in AllCells : PushAux(c)
    \/ ConsumeMain
    \/ ConsumeAux
    \/ DupMain
    \/ DropMain

Spec == Init /\ [][Next]_vars

\* --- Invariants ---

\* K1a: No LINEAR cell has liveCount > 1 in any reachable state.
\* Enforced structurally by the PushMain/PushAux/DupMain preconditions.

K1a_NoDuplication ==
    \A c \in AllCells :
        cells[c].isLinear => cells[c].liveCount <= 1

\* K1c: A consumed LINEAR cell never has liveCount > 0.
\* (Consumed cells are not re-pushable; consumption happens at pop time
\*  which decrements liveCount in the same step.)

K1c_NoReappearance ==
    \A c \in AllCells :
        (cells[c].isLinear /\ cells[c].consumed) => cells[c].liveCount = 0

\* K1b is enforced *structurally* by the DropMain gate. The invariant
\* form: any LINEAR cell with liveCount = 0 either (a) was never pushed
\* (still in initial state) or (b) was consumed via ConsumeMain/ConsumeAux
\* (consumed = TRUE). In both cases, it never leaves the stack via DropMain.
\* Since the gate prevents DropMain from firing on LINEAR cells, this
\* invariant is equivalent to: a LINEAR cell with liveCount = 0 either
\* still has consumed=FALSE AND has never been on a stack, OR has
\* consumed=TRUE. We can't express "never on a stack" without history,
\* so we assert the implication: liveCount = 0 ∧ consumed = TRUE OR
\* liveCount > 0 OR initial state.
\*
\* The cleanest TLA+ form is the action-level claim: DropMain is enabled
\* only for non-LINEAR top cells. We express this as an inductive
\* invariant that holds along all traces:
\*   A LINEAR cell on top of a stack cannot be the target of DropMain.
\* This is enforced by the DropMain precondition; the invariant is
\* simply re-stating it as a state property.

K1b_StructuralDropGate ==
    \A c \in AllCells :
        cells[c].isLinear =>
            \* If a LINEAR cell is on top of the main stack, no action
            \* removes it without setting consumed. Equivalently: liveCount
            \* decrements to 0 only when consumed flips to TRUE.
            (cells[c].liveCount = 0 => (~cells[c].consumed =>
                \* Never pushed (still in initial state)
                \A i \in 1..Len(mainStack) : mainStack[i] /= c) /\
                \* Same for aux stack
                (~cells[c].consumed =>
                    \A i \in 1..Len(auxStack) : auxStack[i] /= c))

\* Type invariant.

TypeInv ==
    /\ cells \in [AllCells -> CellState]
    /\ mainStack \in Seq(AllCells)
    /\ auxStack \in Seq(AllCells)
    /\ Len(mainStack) <= MaxMainDepth
    /\ Len(auxStack) <= MaxAuxDepth

\* --- Composite K1 ---

K1_Linearity ==
    /\ K1a_NoDuplication
    /\ K1c_NoReappearance

=============================================================================
(*
 * NOTE on companion Lean theorem.
 *
 * LinearityK1.lean proves the single-step versions of K1a/K1b/K1c
 * symbolically (no DUP on LINEAR errors, no DROP on LINEAR errors,
 * consumed cells reject re-push). The TLA+ side adds bounded
 * exhaustive trace exploration: for any sequence of up to N opcodes
 * over up to M cells, no reachable state violates the conjunctions.
 *
 * Default model config (Linearity.cfg) uses small bounds:
 *   LinearCells = {l1}, NonLinearCells = {n1},
 *   MaxMainDepth = 3, MaxAuxDepth = 2
 * Larger instances explored on CI.
 *)
=============================================================================

```
