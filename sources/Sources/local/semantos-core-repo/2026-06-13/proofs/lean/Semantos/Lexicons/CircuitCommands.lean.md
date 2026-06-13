---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/CircuitCommands.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.364928+00:00
---

# proofs/lean/Semantos/Lexicons/CircuitCommands.lean

```lean
-- Semantos Plane — Circuit Commands Lexicon
--
-- Fine-grained verb-level vocabulary for electrical / circuit operations.
-- Each category is a distinct operational command with distinct
-- enables / forecloses for the curator:
--
--   charge       — deliver energy to a storage element (cap / inductor / battery)
--   discharge    — drain energy from a storage element
--   connect      — close a circuit path
--   disconnect   — open a circuit path
--   bias         — apply a DC offset
--   clamp        — limit voltage / current to a threshold
--   trip         — safety shutoff (breaker / MOSFET isolation)
--
-- Granularity rationale: each verb has legally-distinct enables/forecloses
-- (e.g. `charge` enables energy storage while forbidding simultaneous
-- discharge). A mistaken ratification between them is a real-world injury,
-- so they get category-level status rather than living inside an
-- Actuation subfield.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive CircuitCommandsCategory where
  | charge
  | discharge
  | connect
  | disconnect
  | bias
  | clamp
  | trip
  deriving Repr, DecidableEq, BEq

def circuitHeader : CircuitCommandsCategory → String
  | .charge     => "CHARGE"
  | .discharge  => "DISCHARGE"
  | .connect    => "CONNECT"
  | .disconnect => "DISCONNECT"
  | .bias       => "BIAS"
  | .clamp      => "CLAMP"
  | .trip       => "TRIP"

theorem circuitHeader_injective : ∀ c₁ c₂ : CircuitCommandsCategory,
    circuitHeader c₁ = circuitHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [circuitHeader]

instance : Lexicon CircuitCommandsCategory where
  header          := circuitHeader
  headerInjective := circuitHeader_injective

end Semantos.Lexicons

```
