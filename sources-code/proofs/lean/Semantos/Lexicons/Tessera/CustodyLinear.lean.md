---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera/CustodyLinear.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.374591+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera/CustodyLinear.lean

```lean
-- Semantos Plane — V5.5 Tessera Theorem: custody_linear
--
-- A case / pallet / shipment cell has at most one open custodian at
-- any time. The custody-transfer FSM is a single-cursor model: each
-- transfer moves the cursor from operator A to operator B atomically;
-- there is no `forkCustody` operation in the FSM grammar.
--
-- The substrate guarantee is K1 LINEAR enforcement at the executor:
-- a LINEAR case cell carrying the custody field cannot be DUP'd, so
-- there can never be two concurrent custodian states. This file
-- proves the FSM-level statement (open-custodian count ≤ 1) at the
-- abstract semantic level; the executor-level K1 in
-- proofs/lean/Semantos/Theorems/LinearityK1.lean closes the loop
-- by showing the LINEAR substrate cannot fork a cell.
--
-- Lands per docs/canon/commissions/wave-tessera.md §7.6 V5.5.

namespace Semantos.Lexicons.Tessera

-- ══════════════════════════════════════════════════════════════════════
-- Custody FSM — abstract model
-- ══════════════════════════════════════════════════════════════════════

/-- An operator's certificate id (BRC-52 cert subject identifier). For
    the purposes of this proof, a stable string. -/
abbrev OperatorCertId := String

/-- The custody state of a case / pallet / shipment cell. Either the
    cell is unowned (between transfers, e.g. immediately after
    assemble-case before the first transfer-custody) or held by
    exactly one operator. The type itself encodes the "at most one
    custodian" invariant — there is no `heldByMany` constructor. -/
inductive CustodyState where
  | unowned
  | heldBy (operator : OperatorCertId)
  deriving Repr, DecidableEq, BEq

/-- The patches the custody FSM accepts. `transferTo` moves the cursor
    atomically; there is no `fork` patch. `release` moves to `unowned`
    (e.g. for shipment closure). -/
inductive CustodyPatch where
  | transferTo (op : OperatorCertId)
  | release
  deriving Repr, DecidableEq, BEq

/-- FSM transition. Atomic cursor move — no patch can produce a state
    with more than one custodian. -/
def applyCustody : CustodyState → CustodyPatch → CustodyState
  | _, .transferTo op => .heldBy op
  | _, .release       => .unowned

/-- Apply a sequence of patches left-to-right. -/
def applyCustodyList (s : CustodyState) : List CustodyPatch → CustodyState
  | []         => s
  | p :: rest  => applyCustodyList (applyCustody s p) rest

/-- The number of open custodians on a custody state. By construction
    of `CustodyState`, this is 0 (unowned) or 1 (heldBy _). -/
def openCustodiansCount : CustodyState → Nat
  | .unowned    => 0
  | .heldBy _   => 1

-- ══════════════════════════════════════════════════════════════════════
-- V5.5 — custody_linear
-- ══════════════════════════════════════════════════════════════════════

/-- Every custody state has open-custodian count at most one. This is
    the type-level expression of the invariant — `CustodyState` has
    no constructor admitting two concurrent custodians. -/
theorem openCustodiansCount_le_one (s : CustodyState) :
    openCustodiansCount s ≤ 1 := by
  cases s <;> simp [openCustodiansCount]

/-- V5.5 — `tessera.custody_linear`. After any sequence of custody
    patches starting from any state, the case cell has at most one
    open custodian. Provable from K1 LINEAR specialised at the
    custody FSM: the type-level construction of `CustodyState`
    is what K1 enforces at the executor (no DUP on a LINEAR case
    cell carrying custody). -/
theorem tessera_custody_linear (s : CustodyState) (patches : List CustodyPatch) :
    openCustodiansCount (applyCustodyList s patches) ≤ 1 :=
  openCustodiansCount_le_one _

end Semantos.Lexicons.Tessera

```
