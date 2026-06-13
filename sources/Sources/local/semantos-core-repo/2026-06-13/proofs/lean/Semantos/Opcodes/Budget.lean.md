---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Opcodes/Budget.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.359908+00:00
---

# proofs/lean/Semantos/Opcodes/Budget.lean

```lean
-- Semantos Plane — Wallet Budget Opcode Semantics  (Phase W3)
--
-- Models OP_DECREMENT_BUDGET (0xCE) and OP_REFILL_BUDGET (0xCF) from
-- core/cell-engine/src/opcodes/plexus.zig.
--
-- Both opcodes operate on Tier-0 budget cells, which are AFFINE-class
-- (per §6.1 of WALLET-TIER-CUSTODY.md). The cell-level model abstracts
-- the byte-level `remaining_satoshis` arithmetic — that semantic content
-- is captured separately by Theorems.BudgetMonotonicityK13 over the
-- BudgetState type. What this file provides is the on-stack peek-then-
-- mutate skeleton that K4 (FailureAtomicity) reasons about.
--
-- Stack effects:
--   OP_DECREMENT_BUDGET: [budget_cell, amount]                    → [budget_cell']
--   OP_REFILL_BUDGET:    [budget_cell, amount, parent_pk, parent_sig] → [budget_cell']
--
-- Both follow the failure-atomic peek-then-mutate idiom:
--   1. Precheck depth
--   2. Peek all arguments
--   3. Validate cell linearity (must be AFFINE)
--   4. Validate amount and (for refill) parent signature
--   5. Only then pop arguments and push the updated cell
--
-- The budget arithmetic and signature verification are abstracted as
-- oracles (`budgetCheck`, `checksig`), paralleling how `opDerefPointer`
-- abstracts host fetch.

import Semantos.PDA
import Semantos.Opcodes.Classify
import Semantos.Opcodes.Standard

namespace Semantos.Opcodes

/-- Abstract updated budget cell — the result of a successful debit or refill.
    Concrete plexus.zig writes a new `remaining_satoshis` value at payload
    byte 32; the cell-level model replaces the cell with this placeholder.
    The substantive arithmetic property (strict decrease / increase) is in
    Theorems.BudgetMonotonicityK13. The differential test
    `tests/budget_conformance.zig` ties the placeholder back to the bytes. -/
def budgetCell : Cell :=
  { header := {
      linearity := .affine
      version := ⟨1⟩
      domainFlag := ⟨0x10000001⟩  -- tier-0 hot flag (§6.1)
      refCount := ⟨0⟩
      typeHash := ⟨0, by omega⟩
      ownerId := ⟨0, by omega⟩
      timestamp := ⟨0⟩
      cellCount := ⟨1⟩
      payloadTotal := ⟨120⟩  -- privkey(32) + remaining(8) + epoch(16) + sig(64)
    }
    capabilityType := none }

/-- 0xCE OP_DECREMENT_BUDGET  (Phase W3 — Tier-0 micropayment debit)
    Stack: [budget_cell, amount] → [budget_cell']
    The cell must be AFFINE; the budget arithmetic is abstracted as a
    `budgetCheck` oracle that returns true iff the debit is valid
    (amount ≥ 0 and amount ≤ remaining). On success, the cell is replaced
    with a placeholder representing the post-debit cell.
    Failure-atomic: stack unchanged on any error.
    Mirrors plexus.zig:opDecrementBudget. -/
def opDecrementBudget (pda : PDA) (budgetCheck : Cell → Cell → Bool) :
    Except OpcodeError PDA :=
  -- Step 1: Precheck depth
  if pda.sdepth < 2 then .error (.stackError .stack_underflow)
  else
    -- Step 2: Peek both without consuming
    match pda.speekAt 0, pda.speekAt 1 with
    | .error e, _ => .error (.stackError e)
    | _, .error e => .error (.stackError e)
    | .ok amountItem, .ok cellItem =>
      -- Step 3: Validate cell linearity (must be AFFINE)
      if cellItem.header.linearity != .affine then
        .error (.linearityError .linearity_check_failed)
      -- Step 4: Validate the debit (amount ≥ 0 and amount ≤ remaining)
      else if !(budgetCheck cellItem amountItem) then
        .error .insufficientBudget
      else
        -- Step 5: All checks passed — pop amount, pop cell, push updated cell
        match pda.spop with
        | .error e => .error (.stackError e)
        | .ok (_, pda1) =>
          match pda1.spop with
          | .error e => .error (.stackError e)
          | .ok (_, pda2) =>
            match pda2.spush budgetCell with
            | .error e => .error (.stackError e)
            | .ok pda3 => .ok pda3

/-- 0xCF OP_REFILL_BUDGET  (Phase W3 — credit a Tier-0 budget under parent auth)
    Stack: [budget_cell, refill_amount, parent_pubkey, parent_sig] → [budget_cell']

    The cell must be AFFINE. The signature check is modeled as an opaque
    `checksig` oracle (pubkey_cell → msg_cell → sig_cell → Bool) — the
    Zig builds msg = HASH256(cell.header || amount_LE8) and calls host.checksig.
    The amount-positivity check and overflow guard are abstracted into
    `budgetCheck` (true iff amount ≥ 0 and remaining + amount does not
    overflow u64).

    Failure-atomic: stack unchanged on any error.
    Mirrors plexus.zig:opRefillBudget. -/
def opRefillBudget (pda : PDA)
    (budgetCheck : Cell → Cell → Bool)
    (checksig : Cell → Cell → Cell → Bool) :
    Except OpcodeError PDA :=
  -- Step 1: Precheck depth
  if pda.sdepth < 4 then .error (.stackError .stack_underflow)
  else
    -- Step 2: Peek all four without consuming
    match pda.speekAt 0, pda.speekAt 1, pda.speekAt 2, pda.speekAt 3 with
    | .error e, _, _, _ => .error (.stackError e)
    | _, .error e, _, _ => .error (.stackError e)
    | _, _, .error e, _ => .error (.stackError e)
    | _, _, _, .error e => .error (.stackError e)
    | .ok sigItem, .ok pkItem, .ok amountItem, .ok cellItem =>
      -- Step 3: Validate cell linearity (must be AFFINE)
      if cellItem.header.linearity != .affine then
        .error (.linearityError .linearity_check_failed)
      -- Step 4: Validate amount (≥ 0, no overflow on credit)
      else if !(budgetCheck cellItem amountItem) then
        .error .insufficientBudget
      -- Step 5: Validate parent signature over (cell.header || amount)
      else if !(checksig pkItem cellItem sigItem) then
        .error .invalidRefillSignature
      else
        -- Step 6: All checks passed — pop sig, pk, amount, cell; push updated
        match pda.spop with
        | .error e => .error (.stackError e)
        | .ok (_, pda1) =>
          match pda1.spop with
          | .error e => .error (.stackError e)
          | .ok (_, pda2) =>
            match pda2.spop with
            | .error e => .error (.stackError e)
            | .ok (_, pda3) =>
              match pda3.spop with
              | .error e => .error (.stackError e)
              | .ok (_, pda4) =>
                match pda4.spush budgetCell with
                | .error e => .error (.stackError e)
                | .ok pda5 => .ok pda5

end Semantos.Opcodes

```
