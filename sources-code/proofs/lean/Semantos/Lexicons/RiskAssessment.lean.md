---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/RiskAssessment.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.365480+00:00
---

# proofs/lean/Semantos/Lexicons/RiskAssessment.lean

```lean
-- Semantos Plane — Risk Assessment Lexicon
--
-- Lifecycle vocabulary for risk-management discourse (BREM, ISO 31000,
-- COSO ERM family). The seven categories span the identification-through-
-- acceptance loop that every formal risk register executes:
--
--   identification  — naming a new risk source (hazard, vulnerability)
--   analysis        — likelihood + consequence estimation
--   evaluation      — comparison against risk appetite / tolerance
--   treatment       — control selection, mitigation, transfer, avoidance
--   monitoring      — ongoing measurement of residual risk
--   acceptance      — formal sign-off on residual risk by an authority
--   communication   — disclosure to stakeholders / regulators
--
-- Granularity rationale: BREM's Mutation Authority claim lands on
-- `acceptance` specifically — whoever can ratify a residual-risk
-- acceptance patch is by definition the holder of mutation authority on
-- the risk register. This is why acceptance warrants its own category
-- rather than being collapsed into a generic decision verb.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive RiskAssessmentCategory where
  | identification
  | analysis
  | evaluation
  | treatment
  | monitoring
  | acceptance
  | communication
  deriving Repr, DecidableEq, BEq

def riskAssessmentHeader : RiskAssessmentCategory → String
  | .identification => "IDENTIFICATION"
  | .analysis       => "ANALYSIS"
  | .evaluation     => "EVALUATION"
  | .treatment      => "TREATMENT"
  | .monitoring     => "MONITORING"
  | .acceptance     => "ACCEPTANCE"
  | .communication  => "COMMUNICATION"

theorem riskAssessmentHeader_injective : ∀ c₁ c₂ : RiskAssessmentCategory,
    riskAssessmentHeader c₁ = riskAssessmentHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [riskAssessmentHeader]

instance : Lexicon RiskAssessmentCategory where
  header          := riskAssessmentHeader
  headerInjective := riskAssessmentHeader_injective

end Semantos.Lexicons

```
