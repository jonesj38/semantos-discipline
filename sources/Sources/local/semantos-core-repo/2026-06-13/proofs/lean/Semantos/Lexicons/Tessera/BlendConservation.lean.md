---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera/BlendConservation.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.374003+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera/BlendConservation.lean

```lean
-- Semantos Plane — V5.4 Tessera Theorem: blend_conservation
--
-- At any blend transition, total amount is conserved:
--
--   Σ input_barrel.amount = Σ output_barrel.amount
--
-- A `tessera.blend` walker consuming N input barrels into K output
-- barrels (typically K = 1 — one consolidated barrel) cannot create
-- or destroy volume. The walker's job is to record the transition;
-- the physical reality (liquid from N barrels pours into K barrels;
-- volume conserves up to evaporation, which the cartridge models
-- explicitly as a separate `addition` event, not implicitly in
-- blend).
--
-- The substrate guarantee is proposed K15 (capability-UTXO
-- conservation) per docs/PROOF-COVERAGE.md — the same shape of
-- conservation invariant applied to the capability domain. K15
-- formalises the no-mint / no-burn law for capability UTXOs at the
-- executor level; this theorem instantiates that shape at the
-- tessera level for fluid-volume conservation across a blend
-- transition.
--
-- The walker is verified against this theorem at PR time: the
-- production `tessera.blend` walker must produce an output list
-- whose summed `amount` equals the summed input `amount`, or fail
-- with a conservation-violation error.
--
-- Lands per docs/canon/commissions/wave-tessera.md §7.6 V5.4.

namespace Semantos.Lexicons.Tessera

-- ══════════════════════════════════════════════════════════════════════
-- Blend FSM — abstract model
-- ══════════════════════════════════════════════════════════════════════

/-- A barrel cell carries an `amount` in some canonical unit (e.g.
    litres × 1000 for centilitre precision; the unit is opaque to
    this proof). -/
structure Barrel where
  amount : Nat
  deriving Repr, DecidableEq, BEq

/-- Sum the amounts across a list of barrels. -/
def totalAmount (barrels : List Barrel) : Nat :=
  (barrels.map Barrel.amount).foldl (· + ·) 0

/-- A blend transition consumes a list of input barrels and produces
    a list of output barrels. The smart constructor `mkBlend` is the
    only way to build a valid `BlendOp` — it ensures the output list
    sums to exactly the input total. -/
structure BlendOp where
  inputs  : List Barrel
  outputs : List Barrel
  conservation : totalAmount inputs = totalAmount outputs

/-- The canonical blend constructor for the single-output case: blend
    a list of inputs into one consolidated output barrel whose
    amount is the input total. This is what the `tessera.blend`
    walker generates in the common case. -/
def mkBlend (inputs : List Barrel) : BlendOp :=
  { inputs  := inputs
    outputs := [{ amount := totalAmount inputs }]
    conservation := by
      simp [totalAmount, List.map_cons, List.map_nil, List.foldl] }

-- ══════════════════════════════════════════════════════════════════════
-- V5.4 — blend_conservation
-- ══════════════════════════════════════════════════════════════════════

/-- V5.4 — `tessera.blend_conservation`. At any valid blend
    transition, total amount is conserved across the transition.
    This is the type-level statement of the K15-shaped invariant:
    `BlendOp.conservation` is the proof field, and this theorem
    just re-exposes it as a top-level statement.

    Provable from K15 specialised at the tessera fluid-volume FSM:
    K15 is the substrate-level conservation invariant for capability
    UTXOs; the tessera blend FSM applies the same shape at the
    domain level. -/
theorem tessera_blend_conservation (op : BlendOp) :
    totalAmount op.inputs = totalAmount op.outputs :=
  op.conservation

/-- Corollary: `mkBlend` always produces a conservation-respecting
    BlendOp. The canonical walker invocation can rely on this
    constructor without needing to re-discharge the proof. -/
theorem mkBlend_conserves (inputs : List Barrel) :
    totalAmount (mkBlend inputs).inputs = totalAmount (mkBlend inputs).outputs :=
  (mkBlend inputs).conservation

end Semantos.Lexicons.Tessera

```
