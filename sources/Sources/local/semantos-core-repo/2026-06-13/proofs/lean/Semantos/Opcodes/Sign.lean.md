---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Opcodes/Sign.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.360458+00:00
---

# proofs/lean/Semantos/Opcodes/Sign.lean

```lean
-- Semantos Plane — OP_SIGN (0xCD) Opcode Semantics  (Phase W1)
--
-- Models the wallet tier-key signing opcode from
-- core/cell-engine/src/opcodes/plexus.zig (opSign).
--
-- Stack: [key_cell, msg_digest, sighash_type] → [sig]
--
-- The key cell must be LINEAR (consumed on success — fresh-key-per-tx leaf)
-- or AFFINE (kept on stack — Tier-0 budget cell with embedded priv_key).
-- RELEVANT keys are forbidden — vault keys must not be RELEVANT-class.
--
-- Failure-atomic peek-then-mutate, parallel to opCheckCapability:
--   1. Precheck depth (≥ 3)
--   2. Peek all three items
--   3. Validate key cell linearity
--   4. Sign (axiomatized — host call)
--   5. Only mutate on success: pop sighash, pop msg, pop key (if LINEAR), push sig

import Semantos.PDA
import Semantos.Opcodes.Classify
import Semantos.Opcodes.Standard

namespace Semantos.Opcodes

open Semantos

/-- Abstract signature cell — produced by OP_SIGN, pushed on success.

    Concrete plexus.zig:opSign produces a DER signature byte string with the
    sighash byte appended; we abstract this to a placeholder cell for the
    Lean-level reasoning. The cryptographic content is captured separately
    by the `ecdsaSign` axiom in CryptoAxioms.lean — the cell here is the
    on-stack representation. -/
def signatureCell : Cell :=
  { header := {
      linearity := .debug
      version := ⟨1⟩
      domainFlag := ⟨0⟩
      refCount := ⟨0⟩
      typeHash := ⟨0, by omega⟩
      ownerId := ⟨0, by omega⟩
      timestamp := ⟨0⟩
      cellCount := ⟨1⟩
      payloadTotal := ⟨73⟩  -- max DER 72 + sighash byte
    }
    capabilityType := none }

/-- 0xCD OP_SIGN  (Phase W1)
    Stack: [key_cell, msg_digest, sighash_type] → [sig]
    Failure-atomic. Mirrors plexus.zig:opSign.

    LINEAR key cells are consumed on success (fresh-key-per-tx leaf).
    AFFINE key cells stay on stack on success (Tier-0 budget fast path).
    RELEVANT and DEBUG key cells are rejected with linearity_check_failed. -/
def opSign (pda : PDA) : Except OpcodeError PDA :=
  -- Step 1: Precheck depth (need 3 items: key, msg, sighash_type)
  if pda.sdepth < 3 then .error (.stackError .stack_underflow)
  else
    -- Step 2: Peek all three without consuming
    match pda.speekAt 0, pda.speekAt 1, pda.speekAt 2 with
    | .error e, _, _ => .error (.stackError e)
    | _, .error e, _ => .error (.stackError e)
    | _, _, .error e => .error (.stackError e)
    | .ok _sighashItem, .ok _msgItem, .ok keyItem =>
      -- Step 3: Validate key linearity (RELEVANT and DEBUG forbidden).
      -- Stack unchanged on failure.
      match keyItem.header.linearity with
      | .relevant => .error (.linearityError .linearity_check_failed)
      | .debug    => .error (.linearityError .linearity_check_failed)
      | .linear =>
        -- Step 4: All checks passed — pop sighash, msg, key; push sig.
        match pda.spop with
        | .error e => .error (.stackError e)
        | .ok (_, pda1) =>
          match pda1.spop with
          | .error e => .error (.stackError e)
          | .ok (_, pda2) =>
            match pda2.spop with
            | .error e => .error (.stackError e)
            | .ok (_, pda3) =>
              match pda3.spush signatureCell with
              | .error e => .error (.stackError e)
              | .ok pda4 => .ok pda4
      | .affine =>
        -- AFFINE key stays on stack — Tier-0 budget fast path.
        -- Pop only sighash and msg, then push sig (key remains beneath).
        match pda.spop with
        | .error e => .error (.stackError e)
        | .ok (_, pda1) =>
          match pda1.spop with
          | .error e => .error (.stackError e)
          | .ok (_, pda2) =>
            match pda2.spush signatureCell with
            | .error e => .error (.stackError e)
            | .ok pda3 => .ok pda3

end Semantos.Opcodes

```
