---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera/TamperOneShot.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.374874+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera/TamperOneShot.lean

```lean
-- Semantos Plane — V5.2 Tessera Theorem: tamper_one_shot
--
-- Once a bottle's tamper-loop seal transitions to `broken`, no further
-- patch sequence yields `intact`. The tamper-loop FSM is intentionally
-- one-shot: every patch either marks the seal broken (if not already)
-- or is a no-op on an already-broken seal. There is no `restoreIntact`
-- transition — the underlying physical mechanism (NFC tamper loop on
-- a NTAG 213-TT chip) cannot be undone after the loop is cut.
--
-- The substrate guarantee is K1 LINEAR enforcement at the executor:
-- a LINEAR bottle cell carrying tamper-state cannot be DUP'd or
-- DROP'd, so the only state-progression is forward-only via
-- `tessera.tamper` walker patches. This file proves the FSM-level
-- statement (no `broken → intact` patch sequence) at the abstract
-- semantic level; the executor-level K1 in
-- proofs/lean/Semantos/Theorems/LinearityK1.lean closes the loop
-- by showing the LINEAR substrate cannot bypass the FSM.
--
-- Lands per docs/canon/commissions/wave-tessera.md §7.6 V5.2.

namespace Semantos.Lexicons.Tessera

-- ══════════════════════════════════════════════════════════════════════
-- Tamper-loop FSM — abstract model
-- ══════════════════════════════════════════════════════════════════════

/-- The two states the tamper-loop seal can be in. -/
inductive TamperState where
  | intact
  | broken
  deriving Repr, DecidableEq, BEq

/-- The only patch kind the tamper-loop accepts. `MarkBroken` corresponds
    to a `tessera.tamper-event` cell minted by the consumer-scan walker
    when an NFC tap reports `tamper_loop = broken`. There is no
    `MarkIntact` constructor — the FSM has no transition restoring
    intactness, and a LINEAR bottle cell cannot be respend per K1. -/
inductive TamperPatch where
  | markBroken
  deriving Repr, DecidableEq, BEq

/-- FSM transition. Once `broken`, every patch is a no-op on tamper
    state — idempotent because the underlying physical seal cannot
    be un-broken. -/
def applyTamper : TamperState → TamperPatch → TamperState
  | _, .markBroken => .broken

/-- Apply a sequence of patches left-to-right. -/
def applyTamperList (s : TamperState) : List TamperPatch → TamperState
  | []         => s
  | p :: rest  => applyTamperList (applyTamper s p) rest

-- ══════════════════════════════════════════════════════════════════════
-- V5.2 — tamper_one_shot
-- ══════════════════════════════════════════════════════════════════════

/-- Every application of any `TamperPatch` to any state results in
    `broken`. The FSM has a single sink state. -/
private theorem applyTamper_eq_broken (s : TamperState) (p : TamperPatch) :
    applyTamper s p = .broken := by
  cases p
  rfl

/-- If the starting state is `broken`, applying any sequence of patches
    yields `broken`. -/
private theorem applyTamperList_broken_stays_broken (patches : List TamperPatch) :
    applyTamperList .broken patches = .broken := by
  induction patches with
  | nil => rfl
  | cons p rest ih =>
    simp [applyTamperList, applyTamper_eq_broken]
    exact ih

/-- V5.2 — `tessera.tamper_one_shot`. Once the tamper-loop seal is
    broken, no sequence of `tessera.tamper-event` patches yields
    `intact`. Provable by case analysis from K1 LINEAR (here at the
    abstract FSM level; the executor closes the gap by refusing to
    allow a LINEAR cell to bypass FSM application). -/
theorem tessera_tamper_one_shot (patches : List TamperPatch) :
    applyTamperList .broken patches ≠ .intact := by
  rw [applyTamperList_broken_stays_broken]
  intro h
  cases h

end Semantos.Lexicons.Tessera

```
