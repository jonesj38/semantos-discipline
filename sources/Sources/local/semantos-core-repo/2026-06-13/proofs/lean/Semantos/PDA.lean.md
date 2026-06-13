---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/PDA.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.357241+00:00
---

# proofs/lean/Semantos/PDA.lean

```lean
-- Semantos Plane — 2-PDA (Dual-Stack Pushdown Automaton) Model
--
-- Models the dual-stack machine from packages/cell-engine/src/pda.zig.
-- Main stack: 1024 cells (constants.zig: MAIN_STACK_CELLS=1024)
-- Aux stack: 256 cells (constants.zig: AUX_STACK_CELLS=256)

import Semantos.Cell
import Semantos.BoundedStack

namespace Semantos

-- Stack bounds matching constants.zig:13-16
def mainStackDepth : Nat := 1024
def auxStackDepth : Nat := 256

/-- The 2-PDA state. Models pda.zig PDA struct (lines 21-40). -/
structure PDA where
  mainStack : BoundedStack Cell mainStackDepth
  auxStack : BoundedStack Cell auxStackDepth
  opcount : Nat
  maxOps : Nat
  enforcementEnabled : Bool
  deriving Repr

/-- Create an empty PDA with given execution limit.
    Matches pda.zig init() (lines 44-58). -/
def PDA.init (maxOps : Nat) : PDA :=
  { mainStack := BoundedStack.empty Cell mainStackDepth
  , auxStack := BoundedStack.empty Cell auxStackDepth
  , opcount := 0
  , maxOps := maxOps
  , enforcementEnabled := false }

-- ── Main stack operations ──

/-- Push to main stack. Matches pda.zig spush(). -/
def PDA.spush (pda : PDA) (cell : Cell) : Except StackError PDA :=
  match pda.mainStack.push cell with
  | .ok s' => .ok { pda with mainStack := s' }
  | .error e => .error e

/-- Pop from main stack. Matches pda.zig spop(). -/
def PDA.spop (pda : PDA) : Except StackError (Cell × PDA) :=
  match pda.mainStack.pop with
  | .ok (cell, s') => .ok (cell, { pda with mainStack := s' })
  | .error e => .error e

/-- Peek top of main stack. Matches pda.zig speek(). -/
def PDA.speek (pda : PDA) : Except StackError Cell :=
  pda.mainStack.peek

/-- Peek at depth on main stack. Matches pda.zig speekAt(). -/
def PDA.speekAt (pda : PDA) (depth : Nat) : Except StackError Cell :=
  pda.mainStack.peekAt depth

/-- Main stack depth. Matches pda.zig sdepth(). -/
def PDA.sdepth (pda : PDA) : Nat :=
  pda.mainStack.depth

-- ── Aux stack operations ──

/-- Push to aux stack. Matches pda.zig apush(). -/
def PDA.apush (pda : PDA) (cell : Cell) : Except StackError PDA :=
  match pda.auxStack.push cell with
  | .ok s' => .ok { pda with auxStack := s' }
  | .error e => .error e

/-- Pop from aux stack. Matches pda.zig apop(). -/
def PDA.apop (pda : PDA) : Except StackError (Cell × PDA) :=
  match pda.auxStack.pop with
  | .ok (cell, s') => .ok (cell, { pda with auxStack := s' })
  | .error e => .error e

/-- Aux stack depth. Matches pda.zig adepth(). -/
def PDA.adepth (pda : PDA) : Nat :=
  pda.auxStack.depth

-- ── Stack manipulation operations ──

/-- DUP: duplicate top of main stack. Matches pda.zig sdup(). -/
def PDA.sdup (pda : PDA) : Except StackError PDA := do
  let top ← pda.speek
  pda.spush top

/-- DROP: discard top of main stack. Matches pda.zig sdrop(). -/
def PDA.sdrop (pda : PDA) : Except StackError PDA := do
  let (_, pda') ← pda.spop
  return pda'

/-- SWAP: swap top two elements. Matches pda.zig sswap(). -/
def PDA.sswap (pda : PDA) : Except StackError PDA := do
  let (a, pda1) ← pda.spop
  let (b, pda2) ← pda1.spop
  let pda3 ← pda2.spush a
  pda3.spush b

/-- OVER: copy second element to top. Matches pda.zig sover(). -/
def PDA.sover (pda : PDA) : Except StackError PDA := do
  let second ← pda.speekAt 1
  pda.spush second

/-- ROT: rotate top three (a b c → b c a). Matches pda.zig srot(). -/
def PDA.srot (pda : PDA) : Except StackError PDA := do
  let (c, pda1) ← pda.spop
  let (b, pda2) ← pda1.spop
  let (a, pda3) ← pda2.spop
  let pda4 ← pda3.spush b
  let pda5 ← pda4.spush c
  pda5.spush a

/-- NIP: remove second element. Matches pda.zig snip(). -/
def PDA.snip (pda : PDA) : Except StackError PDA := do
  let (top, pda1) ← pda.spop
  let (_, pda2) ← pda1.spop
  pda2.spush top

/-- TOALTSTACK: move top of main to aux. Matches pda.zig toalt(). -/
def PDA.toalt (pda : PDA) : Except StackError PDA := do
  let (cell, pda1) ← pda.spop
  pda1.apush cell

/-- FROMALTSTACK: move top of aux to main. Matches pda.zig fromalt(). -/
def PDA.fromalt (pda : PDA) : Except StackError PDA := do
  let (cell, pda1) ← pda.apop
  pda1.spush cell

/-- PICK: copy nth element to top. Matches pda.zig spick(). -/
def PDA.spick (pda : PDA) (n : Nat) : Except StackError PDA := do
  let cell ← pda.speekAt n
  pda.spush cell

/-- 2DUP: duplicate top two. Matches pda.zig s2dup(). -/
def PDA.s2dup (pda : PDA) : Except StackError PDA := do
  let a ← pda.speekAt 0
  let b ← pda.speekAt 1
  let pda1 ← pda.spush b
  pda1.spush a

/-- 2DROP: drop top two. Matches pda.zig s2drop(). -/
def PDA.s2drop (pda : PDA) : Except StackError PDA := do
  let (_, pda1) ← pda.spop
  let (_, pda2) ← pda1.spop
  return pda2

/-- 3DUP: duplicate top three. Matches pda.zig s3dup(). -/
def PDA.s3dup (pda : PDA) : Except StackError PDA := do
  let a ← pda.speekAt 0
  let b ← pda.speekAt 1
  let c ← pda.speekAt 2
  let pda1 ← pda.spush c
  let pda2 ← pda1.spush b
  pda2.spush a

/-- TUCK: copy top before second. Matches pda.zig stuck(). -/
def PDA.stuck (pda : PDA) : Except StackError PDA := do
  let (a, pda1) ← pda.spop
  let (b, pda2) ← pda1.spop
  let pda3 ← pda2.spush a
  let pda4 ← pda3.spush b
  pda4.spush a

/-- IFDUP: duplicate top if truthy (non-zero). Matches pda.zig sifdup(). -/
def PDA.sifdup (pda : PDA) (isTruthy : Cell → Bool) : Except StackError PDA := do
  let top ← pda.speek
  if isTruthy top then pda.spush top else return pda

/-- ROLL: move nth element to top. Matches pda.zig sroll().
    Modeled as peek-at-n then rebuild for simplicity. -/
def PDA.sroll (pda : PDA) (n : Nat) : Except StackError PDA :=
  if n == 0 then .ok pda
  else if h : n < pda.mainStack.items.length then
    let cell := pda.mainStack.items[n]
    let newItems := cell :: (pda.mainStack.items.take n ++ pda.mainStack.items.drop (n + 1))
    have hlen : newItems.length ≤ mainStackDepth := by
      simp only [newItems, List.length_cons, List.length_append]
      have htake := List.length_take_le n pda.mainStack.items
      have hdrop : (pda.mainStack.items.drop (n + 1)).length =
        pda.mainStack.items.length - (n + 1) := by simp [List.length_drop]
      have := pda.mainStack.depth_invariant
      omega
    .ok { pda with mainStack := ⟨newItems, hlen⟩ }
  else .error .stack_underflow

end Semantos

```
