---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Jural.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.366013+00:00
---

# proofs/lean/Semantos/Lexicons/Jural.lean

```lean
-- Semantos Plane — Jural Lexicon
--
-- The legal/Hohfeldian discourse vocabulary: the seven categories that
-- classify jural relations between parties. First concrete instance of
-- `Semantos.Substrate.Lexicon`.
--
-- Proof obligation per lexicon:
--   1. Define the category enum (inductive).
--   2. Provide the header function.
--   3. Prove header injectivity.
--   4. Register the `Lexicon` instance.
--
-- Once registered, the substrate theorems (M1-M4, D1-D3, renderCard_*)
-- apply at `Patch JuralCategory` by specialisation — no per-lexicon
-- re-proof of those invariants is required.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive JuralCategory where
  | declaration
  | obligation
  | permission
  | prohibition
  | power
  | condition
  | transfer
  deriving Repr, DecidableEq, BEq

def juralHeader : JuralCategory → String
  | .declaration => "DECLARATION"
  | .obligation  => "OBLIGATION"
  | .permission  => "PERMISSION"
  | .prohibition => "PROHIBITION"
  | .power       => "POWER"
  | .condition   => "CONDITION"
  | .transfer    => "TRANSFER"

theorem juralHeader_injective : ∀ c₁ c₂ : JuralCategory,
    juralHeader c₁ = juralHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [juralHeader]

instance : Lexicon JuralCategory where
  header          := juralHeader
  headerInjective := juralHeader_injective

end Semantos.Lexicons

```
