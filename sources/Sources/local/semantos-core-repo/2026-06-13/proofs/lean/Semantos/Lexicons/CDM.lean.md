---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/CDM.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.366559+00:00
---

# proofs/lean/Semantos/Lexicons/CDM.lean

```lean
-- Semantos Plane — CDM (Common Domain Model) Lexicon
--
-- ISDA-style lifecycle events for financial derivatives and structured
-- trades. The seven categories span trade confirmation through
-- settlement / termination:
--
--   confirmation — trade terms confirmed between counterparties
--   amendment    — modification of an existing trade's terms
--   allocation   — assignment of trade portions across accounts
--   exercise     — triggering a contractual optionality
--   termination  — early unwinding before maturity
--   novation     — transfer of a position to a new counterparty
--   settlement   — payment / delivery at maturity or exercise
--
-- These are the first-class lifecycle events in the ISDA CDM specification;
-- each generates distinct regulatory and accounting obligations, which is
-- why they warrant category-level status.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive CDMCategory where
  | confirmation
  | amendment
  | allocation
  | exercise
  | termination
  | novation
  | settlement
  deriving Repr, DecidableEq, BEq

def cdmHeader : CDMCategory → String
  | .confirmation => "CONFIRMATION"
  | .amendment    => "AMENDMENT"
  | .allocation   => "ALLOCATION"
  | .exercise     => "EXERCISE"
  | .termination  => "TERMINATION"
  | .novation     => "NOVATION"
  | .settlement   => "SETTLEMENT"

theorem cdmHeader_injective : ∀ c₁ c₂ : CDMCategory,
    cdmHeader c₁ = cdmHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [cdmHeader]

instance : Lexicon CDMCategory where
  header          := cdmHeader
  headerInjective := cdmHeader_injective

end Semantos.Lexicons

```
