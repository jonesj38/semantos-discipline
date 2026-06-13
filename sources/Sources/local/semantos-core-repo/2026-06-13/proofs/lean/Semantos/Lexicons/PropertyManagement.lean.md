---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/PropertyManagement.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.364652+00:00
---

# proofs/lean/Semantos/Lexicons/PropertyManagement.lean

```lean
-- Semantos Plane — Property Management Lexicon
--
-- Rental-operations lifecycle for a property under management (distinct
-- from the sale-preparation narrative modelled in demo-estate-to-auction).
-- Each category corresponds to an operational event with its own
-- regulatory / tenancy-law consequences:
--
--   lease         — creation of a tenancy
--   maintenance   — repair / upkeep work on the property
--   inspection    — scheduled or incident-triggered condition check
--   rent          — payment obligation, collection, or arrears notice
--   violation     — breach notice (cure-or-quit, nuisance, etc.)
--   renewal       — extension or re-negotiation of tenancy terms
--   termination   — end of tenancy (notice, eviction, mutual surrender)
--
-- Granularity rationale: residential-tenancy law treats these events
-- differently (a rent-payment patch triggers different clocks to a
-- violation patch) so the curator needs distinct cards per category.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive PropertyManagementCategory where
  | lease
  | maintenance
  | inspection
  | rent
  | violation
  | renewal
  | termination
  deriving Repr, DecidableEq, BEq

def propertyManagementHeader : PropertyManagementCategory → String
  | .lease       => "LEASE"
  | .maintenance => "MAINTENANCE"
  | .inspection  => "INSPECTION"
  | .rent        => "RENT"
  | .violation   => "VIOLATION"
  | .renewal     => "RENEWAL"
  | .termination => "TERMINATION"

theorem propertyManagementHeader_injective : ∀ c₁ c₂ : PropertyManagementCategory,
    propertyManagementHeader c₁ = propertyManagementHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [propertyManagementHeader]

instance : Lexicon PropertyManagementCategory where
  header          := propertyManagementHeader
  headerInjective := propertyManagementHeader_injective

end Semantos.Lexicons

```
