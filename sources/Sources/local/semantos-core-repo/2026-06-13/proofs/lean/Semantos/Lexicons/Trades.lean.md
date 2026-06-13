---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Trades.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.365746+00:00
---

# proofs/lean/Semantos/Lexicons/Trades.lean

```lean
-- Semantos Plane — Trades Lexicon
--
-- Trades / services discourse vocabulary for the oddjobz extension. Each
-- category names a distinct discourse move that produces or transitions
-- a typed cell in the trades vertical (the Job/Quote/Visit/Invoice/
-- Customer/Site/Estimate/Message family per ODDJOBZ-EXTENSION-PLAN.md
-- §O2). The categories track the speech acts, not the cells themselves
-- — same pattern as project-management, where `commitment` is the act
-- not the artefact.
--
-- The eight categories mirror the §O4 state-machine transitions:
--
--   lead      — origin of work (∅ → lead): visitor enquiry via public
--               chat or operator-entered customer record
--   estimate  — operator drafts a pre-quote proposal (AFFINE; can be
--               discarded without becoming a quote)
--   quote     — operator sends a firm priced offer (lead → quoted)
--   dispatch  — operator commits a worker to a visit slot
--               (quoted → scheduled)
--   visit     — worker on site / work performed
--               (scheduled → in_progress → completed)
--   invoice   — billing record issued (completed → invoiced)
--   settle    — payment received and engagement closed
--               (invoiced → paid → closed)
--   message   — vertical-context communication act, including public
--               chat, customer chat, and internal patches against
--               Customer / Job
--
-- Granularity rationale: estimate vs quote, dispatch vs visit, and
-- invoice vs settle are pairs that look adjacent but carry different
-- curator obligations and different capability tokens (cap.oddjobz.
-- {quote, dispatch, invoice, close} per §O3). Confusing them is a
-- canonical source of trades-vertical disputes — so they earn
-- category-level status. See ODDJOBZ-EXTENSION-PLAN.md §10 for the
-- "trades = jural + project-mgmt?" question this lexicon answers in
-- the negative.
--
-- Proof obligation per lexicon (matches every other registered lexicon):
--   1. Define the category enum (inductive).
--   2. Provide the header function.
--   3. Prove header injectivity.
--   4. Register the `Lexicon` instance.
--
-- Once registered, the substrate theorems (M1-M4 merge, D1-D3 diff,
-- renderCard_*) apply at `Patch TradesCategory` by specialisation —
-- no per-lexicon re-proof of those invariants is required.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive TradesCategory where
  | lead
  | estimate
  | quote
  | dispatch
  | visit
  | invoice
  | settle
  | message
  deriving Repr, DecidableEq, BEq

def tradesHeader : TradesCategory → String
  | .lead     => "LEAD"
  | .estimate => "ESTIMATE"
  | .quote    => "QUOTE"
  | .dispatch => "DISPATCH"
  | .visit    => "VISIT"
  | .invoice  => "INVOICE"
  | .settle   => "SETTLE"
  | .message  => "MESSAGE"

theorem tradesHeader_injective : ∀ c₁ c₂ : TradesCategory,
    tradesHeader c₁ = tradesHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [tradesHeader]

instance : Lexicon TradesCategory where
  header          := tradesHeader
  headerInjective := tradesHeader_injective

end Semantos.Lexicons

```
