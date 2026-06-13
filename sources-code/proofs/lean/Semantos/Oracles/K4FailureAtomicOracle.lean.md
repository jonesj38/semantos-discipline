---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Oracles/K4FailureAtomicOracle.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.362872+00:00
---

# proofs/lean/Semantos/Oracles/K4FailureAtomicOracle.lean

```lean
/-
  K4FailureAtomicOracle — differential oracle for K4 (Failure Atomicity).

  K4 states that for ALL Plexus opcodes (0xC0-0xCF), an error result precludes
  a successful result on the same call (error → no .ok, by type disjointness).
  The substantive content lives in the per-opcode inversion lemmas which enumerate
  the exact structural conditions that can trigger each error.

  The most testable K4 property is the depth-underflow gate: every Plexus
  opcode has a minimum stack depth it requires before doing any mutation.
  If that depth is not met, the opcode returns `.error (.stackError .stack_underflow)`
  and the stack is completely unchanged.

  This oracle outputs the minimum stack depth for each Plexus opcode,
  read directly from the Lean4 opcode definitions in `Semantos.Opcodes.Plexus`,
  `Semantos.Opcodes.Sign`, and `Semantos.Opcodes.Budget`.

  Reads a single JSON line from stdin:
    {"op": "0xC0"|"0xC1"|...|"0xCF"}

  Prints a single JSON line to stdout:
    {"minDepth": N}        — minimum stack depth to avoid stack_underflow
    {"error": "bad_input"} — unrecognised opcode token

  Source depth checks (matching the Lean4 opcode definitions):
    0xC0 opCheckLinearType:   match pda.speek      → minDepth = 1
    0xC1 opCheckAffineType:   match pda.speek      → minDepth = 1
    0xC2 opCheckRelevantType: match pda.speek      → minDepth = 1
    0xC3 opCheckCapability:   sdepth < 2           → minDepth = 2
    0xC4 opCheckIdentity:     sdepth < 2           → minDepth = 2
    0xC5 opAssertLinear:      match pda.speek      → minDepth = 1
    0xC6 opCheckDomainFlag:   sdepth < 2           → minDepth = 2
    0xC7 opCheckTypeHash:     sdepth < 2           → minDepth = 2
    0xC8 opDerefPointer:      match pda.speek      → minDepth = 1
    0xC9 opReadHeader:        sdepth < 3           → minDepth = 3
    0xCA opCellCreate:        sdepth < 4           → minDepth = 4
    0xCB opDemote:            sdepth < 2           → minDepth = 2
    0xCC opReadPayload:       sdepth < 3           → minDepth = 3
    0xCD opSign:              sdepth < 3           → minDepth = 3
    0xCE opDecrementBudget:   sdepth < 2           → minDepth = 2
    0xCF opRefillBudget:      sdepth < 4           → minDepth = 4

  Used by `proofs/fuzz/k4-failure-atomic/fuzz.test.ts` to assert that
  the Zig WASM cell-engine returns stack_underflow (error code 2) exactly
  when the model predicts depth < minDepth, covering all 16 Plexus opcodes.
-/
import Semantos.Opcodes.Plexus
import Semantos.Opcodes.Sign
import Semantos.Opcodes.Budget

open Semantos Semantos.Opcodes

-- ── Minimum stack depth table ─────────────────────────────────────────────────

/-- Minimum stack depth required by each Plexus opcode to avoid
    `.error (.stackError .stack_underflow)`.
    Derived directly from the opcode definitions. -/
def plexusMinDepth (op : UInt8) : Option Nat :=
  if op == OP_CHECKLINEARTYPE  then some 1  -- match pda.speek
  else if op == OP_CHECKAFFINETYPE   then some 1  -- match pda.speek
  else if op == OP_CHECKRELEVANTTYPE then some 1  -- match pda.speek
  else if op == OP_CHECKCAPABILITY   then some 2  -- sdepth < 2
  else if op == OP_CHECKIDENTITY     then some 2  -- sdepth < 2
  else if op == OP_ASSERTLINEAR      then some 1  -- match pda.speek
  else if op == OP_CHECKDOMAINFLAG   then some 2  -- sdepth < 2
  else if op == OP_CHECKTYPEHASH     then some 2  -- sdepth < 2
  else if op == OP_DEREF_POINTER     then some 1  -- match pda.speek
  else if op == OP_READHEADER        then some 3  -- sdepth < 3
  else if op == OP_CELLCREATE        then some 4  -- sdepth < 4
  else if op == OP_DEMOTE            then some 2  -- sdepth < 2
  else if op == OP_READPAYLOAD       then some 3  -- sdepth < 3
  else if op == OP_SIGN              then some 3  -- sdepth < 3
  else if op == OP_DECREMENT_BUDGET  then some 2  -- sdepth < 2
  else if op == OP_REFILL_BUDGET     then some 4  -- sdepth < 4
  else none  -- not a Plexus opcode

-- ── Hex parsing ───────────────────────────────────────────────────────────────

/-- Parse one hex character (0-9, a-f, A-F) to its nibble value. -/
def hexNibbleK4? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- Parse a hex opcode string like "0xC0" to a UInt8.
    Accepts "0xXX" (with optional leading/trailing whitespace).
    Returns none if the format is invalid. -/
def parseOpByte (s : String) : Option UInt8 :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if !(t.startsWith "0x" || t.startsWith "0X") then none
  else
    let hex := (t.drop 2).toString
    if hex.length != 2 then none
    else
      let chars := hex.toList
      match chars with
      | [hi, lo] =>
        match hexNibbleK4? hi, hexNibbleK4? lo with
        | some h, some l => some (UInt8.ofNat (h * 16 + l))
        | _, _ => none
      | _ => none

-- ── JSON helpers ──────────────────────────────────────────────────────────────

def stripTokenK4 (s : String) : String :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.startsWith "\"" && t.endsWith "\"" then
    (t.drop 1).dropEnd 1 |>.toString
  else t

def jsonGetK4 (key : String) (json : String) : Option String :=
  let inner := (json.trimAsciiStart.trimAsciiEnd.toString.drop 1).dropEnd 1 |>.toString
  let pairs := inner.splitOn ","
  pairs.findSome? fun pair =>
    let parts := pair.splitOn ":"
    match parts with
    | k :: rest =>
      let k' := stripTokenK4 k
      let v  := stripTokenK4 (":".intercalate rest)
      if k' == key then some v else none
    | _ => none

-- ── Entry point ──────────────────────────────────────────────────────────────

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  let s := line.trimAsciiStart.trimAsciiEnd.toString
  match jsonGetK4 "op" s with
  | none =>
    IO.println "{\"error\": \"bad_input\"}"
  | some opRaw =>
    match parseOpByte opRaw with
    | none =>
      IO.println "{\"error\": \"bad_input\"}"
    | some op =>
      match plexusMinDepth op with
      | none =>
        IO.println "{\"error\": \"not_plexus_opcode\"}"
      | some n =>
        IO.println s!"\{\"minDepth\": {n}}"

```
