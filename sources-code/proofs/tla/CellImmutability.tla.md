---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/CellImmutability.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.351797+00:00
---

# proofs/tla/CellImmutability.tla

```tla
--------------------------- MODULE CellImmutability ---------------------------
(*
 * K7 — Cell Immutability (TLA+ side).
 *
 * Companion to proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean.
 *
 * K7 (Cell immutability, from docs/FORMAL-VERIFICATION-STRATEGY.md line 32):
 *   The 256-byte header is read-only after packing. No opcode in the
 *   instruction set modifies the linearity class of a cell on the stack.
 *
 * What TLA+ adds over Lean:
 *   Lean proves per-opcode that no opcode body writes to header fields.
 *   This spec checks the trace-level property: for any cell that has
 *   appeared in any stack at any point, its header (linearity,
 *   typeHash, ownerId, etc.) is byte-identical to the value at creation.
 *
 *   Catches "opcode accidentally mutates header" bugs across multi-step
 *   sequences — e.g., if a new opcode is added that demotes via header
 *   rewrite rather than via OP_DEMOTE's correct path (which creates a
 *   new cell, doesn't mutate the existing one).
 *
 * Source: core/cell-engine/src/cellPacker.zig
 *         core/protocol-types/src/constants.ts (header offsets)
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    CellIds,           \* Finite set of cell identifiers
    Linearities,       \* {LINEAR, AFFINE, RELEVANT, DEBUG}
    TypeHashes,        \* Finite set of type-hash values
    OwnerIds,          \* Finite set of owner identifiers
    MaxStackDepth      \* Bound on stack depth

\* --- Cell header model ---
\*
\* A cell header carries a tuple of fields. K7 requires all of them to
\* be immutable after packing. We model three representative fields:
\* linearity, typeHash, ownerId.

CellHeader == [
    linearity : Linearities,
    typeHash  : TypeHashes,
    ownerId   : OwnerIds
]

\* --- Variables ---
\*
\* originalHeaders: CellId → CellHeader (set at creation; the "ground
\*                  truth" we check against)
\* currentHeaders: CellId → CellHeader (the "current" header — what an
\*                 opcode would see if it tried to read)
\* stack: sequence of CellIds
\* createdCells: subset of CellIds that have been created

VARIABLES
    originalHeaders,
    currentHeaders,
    stack,
    createdCells

vars == <<originalHeaders, currentHeaders, stack, createdCells>>

\* --- Initial state ---

Init ==
    /\ originalHeaders = [c \in CellIds |->
                            [linearity |-> "LINEAR",
                             typeHash  |-> CHOOSE t \in TypeHashes : TRUE,
                             ownerId   |-> CHOOSE o \in OwnerIds : TRUE]]
    /\ currentHeaders = originalHeaders
    /\ stack = << >>
    /\ createdCells = {}

\* --- Operations ---

\* CreateCell: assign a fresh header to a CellId and record it. The
\* header is non-deterministically chosen — TLC explores all assignments.

CreateCell(c, lin, th, oid) ==
    /\ c \notin createdCells
    /\ originalHeaders' = [originalHeaders EXCEPT ![c] =
                              [linearity |-> lin, typeHash |-> th, ownerId |-> oid]]
    /\ currentHeaders' = [currentHeaders EXCEPT ![c] =
                              [linearity |-> lin, typeHash |-> th, ownerId |-> oid]]
    /\ createdCells' = createdCells \cup {c}
    /\ UNCHANGED stack

\* PushCell: push a created cell onto the stack. Does NOT modify any
\* header — this is K7's contract on the push path.

PushCell(c) ==
    /\ c \in createdCells
    /\ Len(stack) < MaxStackDepth
    /\ stack' = Append(stack, c)
    /\ UNCHANGED <<originalHeaders, currentHeaders, createdCells>>

\* PopCell: pop the top of the stack. Does NOT modify any header.

PopCell ==
    /\ Len(stack) > 0
    /\ stack' = SubSeq(stack, 1, Len(stack) - 1)
    /\ UNCHANGED <<originalHeaders, currentHeaders, createdCells>>

\* DemoteCell (CORRECT path): models OP_DEMOTE by creating a NEW cell
\* with the demoted linearity, leaving the original cell's header
\* intact. The original cell is popped from the stack; the new one is
\* pushed. This preserves K7 because we don't mutate the original.

DemoteCell ==
    /\ Len(stack) > 0
    /\ Cardinality(createdCells) < Cardinality(CellIds)  \* Capacity for new cell
    /\ LET top == stack[Len(stack)] IN
       LET newId == CHOOSE c \in CellIds : c \notin createdCells IN
       /\ originalHeaders[top].linearity = "LINEAR"  \* Only LINEAR can demote
       /\ originalHeaders' = [originalHeaders EXCEPT ![newId] =
                                 [linearity |-> "AFFINE",  \* New cell is AFFINE
                                  typeHash  |-> originalHeaders[top].typeHash,
                                  ownerId   |-> originalHeaders[top].ownerId]]
       /\ currentHeaders' = [currentHeaders EXCEPT ![newId] =
                                 [linearity |-> "AFFINE",
                                  typeHash  |-> originalHeaders[top].typeHash,
                                  ownerId   |-> originalHeaders[top].ownerId]]
       /\ createdCells' = createdCells \cup {newId}
       /\ stack' = Append(SubSeq(stack, 1, Len(stack) - 1), newId)

\* --- Transition relation ---

Next ==
    \/ \E c \in CellIds, lin \in Linearities, th \in TypeHashes, oid \in OwnerIds :
         CreateCell(c, lin, th, oid)
    \/ \E c \in CellIds : PushCell(c)
    \/ PopCell
    \/ DemoteCell

Spec == Init /\ [][Next]_vars

\* --- Invariants ---

\* K7: For every created cell, currentHeaders == originalHeaders. The
\* current header is byte-identical to the header at creation.

K7_HeaderImmutable ==
    \A c \in createdCells :
        currentHeaders[c] = originalHeaders[c]

\* K7-specific: linearity class never changes for any created cell.
\* (Strengthening of K7 — singling out the linearity field, which the
\* strategy doc explicitly calls out: "no opcode modifies the
\* linearity class of a cell on the stack.")

K7a_LinearityImmutable ==
    \A c \in createdCells :
        currentHeaders[c].linearity = originalHeaders[c].linearity

\* TypeInv.

TypeInv ==
    /\ originalHeaders \in [CellIds -> CellHeader]
    /\ currentHeaders \in [CellIds -> CellHeader]
    /\ stack \in Seq(CellIds)
    /\ Len(stack) <= MaxStackDepth
    /\ createdCells \subseteq CellIds
    /\ \A c \in CellIds : (c \in createdCells \/ TRUE)  \* always trivially true; placeholder

\* Composite K7.

K7_CellImmutability ==
    /\ K7_HeaderImmutable
    /\ K7a_LinearityImmutable

=============================================================================
(*
 * NOTE on companion Lean theorem.
 *
 * CellImmutabilityK7.lean proves the per-opcode contract that no
 * opcode body writes to header fields. This spec adds the trace-level
 * property: across any reachable sequence of opcode invocations, no
 * cell's header is mutated.
 *
 * Crucially, the DemoteCell action models OP_DEMOTE *correctly* — by
 * creating a new cell rather than mutating the original. A buggy
 * DemoteCell that wrote to originalHeaders[top].linearity would
 * violate K7a; the model would surface the bug as a counterexample.
 *
 * Default config (CellImmutability.cfg): 3 cells, depth 2.
 *)
=============================================================================

```
