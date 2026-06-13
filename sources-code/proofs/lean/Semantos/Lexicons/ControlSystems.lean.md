---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/ControlSystems.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.364372+00:00
---

# proofs/lean/Semantos/Lexicons/ControlSystems.lean

```lean
-- Semantos Plane — Control Systems Lexicon
--
-- Semantic-intent vocabulary for SCADA, process automation, and
-- safety-instrumented systems. The seven categories correspond to the
-- basic lifecycle of industrial control:
--
--   measurement      — an observed value from a sensor
--   setpoint         — an operator's target state for an actuator
--   actuation        — a command to change an actuator's state
--   interlock        — a structural safety constraint on transitions
--   alarm            — a threshold-crossed notification
--   acknowledgement  — operator accepts an alarm
--   calibration      — update of a sensor reference / zero point
--
-- Second concrete instance of `Semantos.Substrate.Lexicon`, demonstrating
-- that the substrate + lexicon pattern generalises beyond legal/jural
-- vocabulary. Same proof template as Jural: header function + 7×7
-- injectivity case analysis + `Lexicon` instance. All substrate theorems
-- (M1-M4, D1-D3, renderCard_*) apply at `Patch ControlSystemsCategory`
-- automatically.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive ControlSystemsCategory where
  | measurement
  | setpoint
  | actuation
  | interlock
  | alarm
  | acknowledgement
  | calibration
  deriving Repr, DecidableEq, BEq

def controlSystemsHeader : ControlSystemsCategory → String
  | .measurement     => "MEASUREMENT"
  | .setpoint        => "SETPOINT"
  | .actuation       => "ACTUATION"
  | .interlock       => "INTERLOCK"
  | .alarm           => "ALARM"
  | .acknowledgement => "ACK"
  | .calibration     => "CALIBRATION"

theorem controlSystemsHeader_injective : ∀ c₁ c₂ : ControlSystemsCategory,
    controlSystemsHeader c₁ = controlSystemsHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [controlSystemsHeader]

instance : Lexicon ControlSystemsCategory where
  header          := controlSystemsHeader
  headerInjective := controlSystemsHeader_injective

end Semantos.Lexicons

```
