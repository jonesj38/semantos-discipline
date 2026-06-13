---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera/CareScoreMonotonic.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.374302+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera/CareScoreMonotonic.lean

```lean
-- Semantos Plane — V5.3 Tessera Theorem: care_score_monotonic
--
-- The care-score view derived from a bottle's care-event AFFINE chain
-- is non-increasing: each new care-event either decreases the score
-- (an out-of-spec excursion or environmental insult) or leaves it
-- unchanged (a within-spec reading). The score can never go UP from
-- a new event arrival — that would require evidence that prior
-- bad-handling somehow undid itself, which the physical model
-- (temperature exposure, humidity, shock cumulating into protein /
-- aroma / sediment damage) does not admit.
--
-- The substrate guarantee is K1 AFFINE enforcement at the executor:
-- AFFINE cells (here, `tessera.care-event` per TESSERA-CARTRIDGE.md
-- §3.3) accumulate against a bottle / shipment chain; they cannot
-- be retracted or removed. This file proves the score-function
-- monotonicity at the abstract semantic level; the executor-level
-- K1 in proofs/lean/Semantos/Theorems/LinearityK1.lean closes the
-- loop by showing the AFFINE substrate cannot delete a care-event
-- cell, so the score is computed over a strictly extending chain.
--
-- This theorem is the formal correctness basis for the V2.2
-- Postgres view `tessera_care_score(p_cell_id)`: that view computes
-- the score by folding the AFFINE chain, and the V2.2 acceptance
-- ("score never increases with new event added") follows directly
-- from `tessera_care_score_monotonic`.
--
-- Lands per docs/canon/commissions/wave-tessera.md §7.6 V5.3.

namespace Semantos.Lexicons.Tessera

-- ══════════════════════════════════════════════════════════════════════
-- Care-event chain — abstract model
-- ══════════════════════════════════════════════════════════════════════

/-- A care event carries a severity weight. The semantics: severity is
    the score penalty contributed by this event. A within-spec reading
    has severity 0 (no score reduction); an out-of-spec excursion or
    insult contributes a positive severity. Tampering, the worst-case,
    contributes a severity that saturates the score to 0. -/
structure CareEvent where
  severity : Nat
  deriving Repr, DecidableEq, BEq

/-- Score function — fold the AFFINE chain, subtracting each event's
    severity with saturating subtraction (Nat truncates at 0). -/
def careScore : Nat → List CareEvent → Nat
  | initial, []        => initial
  | initial, e :: rest => careScore (initial - e.severity) rest

-- ══════════════════════════════════════════════════════════════════════
-- V5.3 — care_score_monotonic
-- ══════════════════════════════════════════════════════════════════════

/-- Helper: appending a single event to the chain never increases the
    score. Saturating Nat subtraction ensures `s - e.severity ≤ s`. -/
private theorem careScore_append_le (s : Nat) (e : CareEvent)
    (events : List CareEvent) :
    careScore s (events ++ [e]) ≤ careScore s events := by
  induction events generalizing s with
  | nil =>
    simp [careScore]
  | cons head rest ih =>
    simp [careScore]
    exact ih (s - head.severity)

/-- V5.3 — `tessera.care_score_monotonic`. The score sequence is
    non-increasing as care-events arrive. For any initial score, any
    existing event chain, and any new event, the score after appending
    the new event is no greater than the score before.

    Provable from K1 AFFINE specialised at the care-event FSM: AFFINE
    cells cannot be retracted (per the executor-level K1 in
    LinearityK1.lean), so the chain only extends. Combined with the
    saturating-subtraction semantics of `careScore`, monotonicity is
    structural. -/
theorem tessera_care_score_monotonic (initial : Nat)
    (events : List CareEvent) (newEvent : CareEvent) :
    careScore initial (events ++ [newEvent]) ≤ careScore initial events :=
  careScore_append_le initial newEvent events

/-- Corollary: extending the chain by any number of new events can
    only decrease (or leave unchanged) the score. This is the form the
    V2.2 view consumes — `tessera_care_score(p_cell_id)` over a
    longer chain returns ≤ the score over a prefix. -/
theorem tessera_care_score_monotonic_list (initial : Nat)
    (events newEvents : List CareEvent) :
    careScore initial (events ++ newEvents) ≤ careScore initial events := by
  induction newEvents generalizing events with
  | nil => simp
  | cons e rest ih =>
    have h₁ : careScore initial (events ++ e :: rest)
            = careScore initial ((events ++ [e]) ++ rest) := by
      simp [List.append_assoc]
    rw [h₁]
    have h₂ : careScore initial ((events ++ [e]) ++ rest)
            ≤ careScore initial (events ++ [e]) := ih (events ++ [e])
    have h₃ : careScore initial (events ++ [e])
            ≤ careScore initial events :=
      careScore_append_le initial e events
    exact Nat.le_trans h₂ h₃

end Semantos.Lexicons.Tessera

```
