---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/KeyCustodyK12.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.368924+00:00
---

# proofs/lean/Semantos/Theorems/KeyCustodyK12.lean

```lean
-- Semantos Plane — Theorem K12: Key Custody  (Phase W1)
--
-- Two sub-theorems:
--
-- K12a: No reachable script execution copies a LINEAR key cell into a
--       non-linear cell. (Inherits structurally from K1c — LINEAR cells
--       cannot be duplicated, so they cannot be re-typed by way of
--       creating a copy.)
-- K12b: Tier-N key cell consumption requires the tier-N domain flag check
--       before OP_SIGN. (Witnessed by the standard prelude in §7 of the
--       wallet design — every tier flow does
--       OP_CHECK*TYPE → OP_CHECKDOMAINFLAG → OP_SIGN.)
--
-- Proof targets:
--   - K12a: linearity.zig checkLinearity (.linear, .duplicate) = false
--           combined with K1c (LINEAR appears at most once on stacks).
--   - K12b: structural property of the wallet's signing prelude — formalized
--           as a precondition for invoking opSign in any tier-N flow.

import Semantos.Theorems.LinearityK1
import Semantos.Theorems.SignSoundnessK11
import Semantos.Opcodes.Sign

namespace Semantos.Theorems

open Semantos Semantos.Opcodes

-- ══════════════════════════════════════════════════════════════════════
-- K12a: No script execution copies a LINEAR key into a non-linear cell.
-- ══════════════════════════════════════════════════════════════════════

/-- K12a (linearity inheritance): No opcode classified as `.duplicate` can
    succeed on a LINEAR cell. This is K1a applied to the wallet's tier-N
    key custody — since tier-N base/leaf keys live in LINEAR cells (per
    §6.2.1), no script path can copy them.

    A "copy into a non-linear cell" would require an explicit duplicate
    + re-tag. The duplicate is forbidden by linearityPermits, and even
    if it were allowed, OP_DEMOTE only handles LINEAR→AFFINE/RELEVANT,
    not the inverse direction needed to "downgrade" a stored key. So
    the leak path is structurally impossible. -/
theorem k12a_linear_key_cannot_be_duplicated :
    linearityPermits .linear .duplicate = false :=
  k1a_linear_no_duplicate

/-- K12a (cell-level): A LINEAR cell remains uniquely-counted under any
    successful executor step. Specializes K1c (Theorems/LinearityK1.lean).
    For tier keys this means: at most one LINEAR copy of a tier key cell
    exists in the PDA at any execution step. -/
theorem k12a_tier_key_unique_under_step
    (cell : Cell)
    (h_lin : cell.header.linearity = .linear)
    (state : ExecutorState)
    (h_enf : state.linearityEnforced = true)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_count : countCell cell (allStackCells state.pda) ≤ 1) :
    countCell cell (allStackCells state'.pda) ≤ 1 :=
  k1c_linear_unique_on_stacks cell h_lin state h_enf hostFetch state' h_step h_count

-- ══════════════════════════════════════════════════════════════════════
-- K12b: Tier-N key consumption requires the tier-N domain flag check.
-- ══════════════════════════════════════════════════════════════════════
--
-- Each tier flow in §7 of WALLET-TIER-CUSTODY.md follows:
--   OP_CHECKAFFINETYPE/OP_CHECKLINEARTYPE → OP_CHECKDOMAINFLAG → OP_SIGN
--
-- We model this as a structural precondition: any successful invocation
-- of opSign that consumes a tier-N key was preceded by an opCheckDomainFlag
-- against that tier's flag. Lean cannot prove this for arbitrary scripts —
-- it must be enforced by the script template builder. We instead state
-- the property as a verified obligation on the script form.
-- ══════════════════════════════════════════════════════════════════════

/-- A tier-N domain flag, abstractly. The wallet defines:
    Tier 1 base = 0x10000003, Tier 2 = 0x10000004, Tier 3 = 0x10000005,
    Tier-0 hot = 0x10000001 (cell layouts §6.1, §6.2). -/
abbrev TierFlag := UInt32

def tier1BaseFlag : TierFlag := 0x10000003
def tier2BaseFlag : TierFlag := 0x10000004
def tier3BaseFlag : TierFlag := 0x10000005
def tier0HotFlag  : TierFlag := 0x10000001

/-- A "tier-key cell at tier N" carries the corresponding tier-N domain flag. -/
def tierKeyCellHasFlag (cell : Cell) (flag : TierFlag) : Prop :=
  cell.header.domainFlag = flag

/-- K12b (witness theorem): When opSign is invoked on a key cell whose
    domain flag is `tierFlag`, that key was previously checked against
    `tierFlag` by an OP_CHECKDOMAINFLAG. We state this as the converse:
    if opCheckDomainFlag passed, then the (peeked) cell.domainFlag matches.
    Together with the script-template constraint that OP_SIGN follows
    OP_CHECKDOMAINFLAG, this gives the K12b guarantee. -/
theorem k12b_checkdomainflag_witnesses_tier
    (pda pda' : PDA)
    (cell flagCell : Cell)
    (h_depth : pda.sdepth ≥ 2)
    (h_p0 : pda.speekAt 0 = .ok flagCell)
    (h_p1 : pda.speekAt 1 = .ok cell)
    (h_ok : opCheckDomainFlag pda = .ok pda') :
    cell.header.domainFlag = flagCell.header.domainFlag := by
  unfold opCheckDomainFlag at h_ok
  have hd : ¬(pda.sdepth < 2) := by omega
  rw [if_neg hd] at h_ok
  rw [h_p0, h_p1] at h_ok
  simp only at h_ok
  -- Case-split on the BEQ check between the two domain flags.
  cases hbe : cell.header.domainFlag == flagCell.header.domainFlag with
  | true => exact LawfulBEq.eq_of_beq hbe
  | false =>
    -- BEQ false → BNE true → the if takes the error branch — contradicts h_ok.
    exfalso
    have hbne : (cell.header.domainFlag != flagCell.header.domainFlag) = true := by
      simp [bne, hbe]
    rw [hbne] at h_ok
    simp at h_ok

end Semantos.Theorems

```
