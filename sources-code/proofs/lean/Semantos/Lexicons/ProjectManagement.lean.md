---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/ProjectManagement.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.365206+00:00
---

# proofs/lean/Semantos/Lexicons/ProjectManagement.lean

```lean
-- Semantos Plane — Project Management Lexicon
--
-- Work-breakdown and execution lifecycle for planned endeavours, drawn
-- from the PMBOK / PRINCE2 family of project-management disciplines.
-- Each category represents a distinct stage-gate decision or state
-- transition with its own curator-facing enables and forecloses:
--
--   scope       — definition / change to work boundaries
--   plan        — schedule, dependencies, milestone structure
--   commitment  — resource or budget allocation
--   execution   — work performed against a plan
--   change      — scope / schedule / resource change request
--   review      — stage-gate, quality gate, or retrospective
--   closure     — phase or project sign-off
--
-- Granularity rationale: a change-request patch and an execution-progress
-- patch have very different curator obligations — confusion between them
-- is a canonical source of delivery disputes — so they earn category-level
-- status.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive ProjectManagementCategory where
  | scope
  | plan
  | commitment
  | execution
  | change
  | review
  | closure
  deriving Repr, DecidableEq, BEq

def projectManagementHeader : ProjectManagementCategory → String
  | .scope      => "SCOPE"
  | .plan       => "PLAN"
  | .commitment => "COMMITMENT"
  | .execution  => "EXECUTION"
  | .change     => "CHANGE"
  | .review     => "REVIEW"
  | .closure    => "CLOSURE"

theorem projectManagementHeader_injective : ∀ c₁ c₂ : ProjectManagementCategory,
    projectManagementHeader c₁ = projectManagementHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [projectManagementHeader]

instance : Lexicon ProjectManagementCategory where
  header          := projectManagementHeader
  headerInjective := projectManagementHeader_injective

end Semantos.Lexicons

```
