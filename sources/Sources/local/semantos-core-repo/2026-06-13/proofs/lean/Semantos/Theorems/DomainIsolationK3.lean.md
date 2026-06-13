---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/DomainIsolationK3.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.370643+00:00
---

# proofs/lean/Semantos/Theorems/DomainIsolationK3.lean

```lean
-- Semantos Plane — Theorem K3: Domain Isolation
--
-- OP_CHECKDOMAINFLAG pushes TRUE iff the domain flags match.
-- No other code path produces a TRUE result for domain checking.
-- Failure case leaves stack unchanged.
--
-- Proof target: plexus.zig opCheckDomainFlag (lines 126-142)

import Semantos.Opcodes.Plexus

namespace Semantos.Theorems

open Semantos Semantos.Opcodes

-- ══════════════════════════════════════════════════════════════════════
-- K3a: Domain flag mismatch → error, stack unchanged
-- ══════════════════════════════════════════════════════════════════════

/-- K3a: If OP_CHECKDOMAINFLAG is called and the domain flags don't match,
    the operation returns domain_flag_mismatch error and the PDA state
    is unchanged (failure-atomic). -/
theorem k3a_domain_flag_mismatch (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_mismatch : cellItem.header.domainFlag ≠ flagItem.header.domainFlag) :
    opCheckDomainFlag pda = .error (.linearityError .domain_flag_mismatch) := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp [hd, h_peek0, h_peek1]
  -- After simp, the != on UInt32 (LawfulBEq) reduces. The goal becomes
  -- a = b → ..., which we contradict with h_mismatch.
  intro heq; exact absurd heq h_mismatch

-- ══════════════════════════════════════════════════════════════════════
-- K3b: Domain flag match → success (TRUE pushed)
-- ══════════════════════════════════════════════════════════════════════

/-- K3b: If OP_CHECKDOMAINFLAG is called and the domain flags match,
    and pop/push succeed, the operation succeeds with the new PDA. -/
theorem k3b_domain_flag_match (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_match : cellItem.header.domainFlag = flagItem.header.domainFlag)
    (cell0 : Cell) (pda1 : PDA)
    (h_pop : pda.spop = .ok (cell0, pda1))
    (pda2 : PDA)
    (h_push : pda1.spush trueCell = .ok pda2) :
    opCheckDomainFlag pda = .ok pda2 := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp only [hd, h_peek0, h_peek1, ite_false]
  -- Resolve the != (BNE) on UInt32 using LawfulBEq
  have hbeq : (cellItem.header.domainFlag != flagItem.header.domainFlag) = false := by
    simp [bne, h_match]
  simp [hbeq, h_pop, h_push]

-- ══════════════════════════════════════════════════════════════════════
-- K3c: Completeness — domain flag check is total
-- ══════════════════════════════════════════════════════════════════════

/-- K3c: OP_CHECKDOMAINFLAG always returns either ok or error.
    It never diverges. -/
theorem k3c_domain_check_total (pda : PDA) :
    (∃ pda', opCheckDomainFlag pda = .ok pda') ∨
    (∃ e, opCheckDomainFlag pda = .error e) := by
  cases h : opCheckDomainFlag pda with
  | error e => exact Or.inr ⟨e, rfl⟩
  | ok pda' => exact Or.inl ⟨pda', rfl⟩

end Semantos.Theorems

```
