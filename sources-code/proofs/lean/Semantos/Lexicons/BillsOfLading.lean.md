---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/BillsOfLading.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.366293+00:00
---

# proofs/lean/Semantos/Lexicons/BillsOfLading.lean

```lean
-- Semantos Plane — Bills of Lading Lexicon
--
-- Lifecycle events on a maritime / multimodal Bill of Lading, the
-- document that simultaneously represents title to the goods, a receipt
-- of shipment, and a contract of carriage. Each category triggers a
-- distinct legal position:
--
--   issuance       — carrier issues the original BoL
--   endorsement    — transfer of title by endorsement (order BoLs)
--   surrender      — original BoL returned at destination for delivery
--   transshipment  — goods moved between vessels / carriers mid-voyage
--   amendment      — correction of BoL particulars (switch bill, letter of indemnity)
--   release        — cargo handed over to the consignee
--   claim          — notice of loss, shortage, or damage
--
-- Chosen granularity: each event has distinct commercial and insurance
-- consequences, so they warrant category-level status rather than being
-- compressed into a generic jural "transfer".

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive BillsOfLadingCategory where
  | issuance
  | endorsement
  | surrender
  | transshipment
  | amendment
  | release
  | claim
  deriving Repr, DecidableEq, BEq

def billsOfLadingHeader : BillsOfLadingCategory → String
  | .issuance      => "ISSUANCE"
  | .endorsement   => "ENDORSEMENT"
  | .surrender     => "SURRENDER"
  | .transshipment => "TRANSSHIPMENT"
  | .amendment     => "AMENDMENT"
  | .release       => "RELEASE"
  | .claim         => "CLAIM"

theorem billsOfLadingHeader_injective : ∀ c₁ c₂ : BillsOfLadingCategory,
    billsOfLadingHeader c₁ = billsOfLadingHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [billsOfLadingHeader]

instance : Lexicon BillsOfLadingCategory where
  header          := billsOfLadingHeader
  headerInjective := billsOfLadingHeader_injective

end Semantos.Lexicons

```
