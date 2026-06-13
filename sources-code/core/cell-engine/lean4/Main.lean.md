---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/lean4/Main.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.991580+00:00
---

# core/cell-engine/lean4/Main.lean

```lean
/-
  BranchOnOutputOracle — differential oracle for OP_BRANCHONOUTPUT.

  Implements the model's core computable predicate: given a `currentOutputIndex`
  value, what 4-byte little-endian sequence does `OP_BRANCHONOUTPUT` push?

  Theorems covered:
    T1 — determinism:      pure function, trivially deterministic
    T2 — stack delta = +1: oracle computes the exact 4 bytes pushed
    T4 — sole observer:    tested indirectly (scripts without 0xE0 are
                           outputIndex-independent)

  Reads a single JSON line from stdin:
    {"outputIndex": N}      — N is a decimal uint32 (0 .. 4294967295)

  Prints a single JSON line to stdout:
    {"bytes": [b0,b1,b2,b3]} — 4-byte LE encoding of N (u32ToLE from the model)
    {"error": "bad_input"}   — missing or out-of-range field

  Used by `proofs/fuzz/branch-on-output/fuzz.test.ts`.
-/
namespace BranchOnOutputOracle

-- ── Model function (matches u32ToLE in BranchOnOutput.lean) ──────────────────

/-- 4-byte little-endian encoding of a UInt32. -/
def u32ToLE (n : UInt32) : List UInt8 :=
  let v := n.toNat
  [ UInt8.ofNat (v        &&& 0xff)
  , UInt8.ofNat ((v >>> 8 ) &&& 0xff)
  , UInt8.ofNat ((v >>> 16) &&& 0xff)
  , UInt8.ofNat ((v >>> 24) &&& 0xff) ]

-- ── JSON helpers ──────────────────────────────────────────────────────────────

def stripToken (s : String) : String :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.startsWith "\"" && t.endsWith "\"" then
    (t.drop 1).dropEnd 1 |>.toString
  else t

def jsonGet (key : String) (json : String) : Option String :=
  let inner := (json.trimAsciiStart.trimAsciiEnd.toString.drop 1).dropEnd 1 |>.toString
  let pairs := inner.splitOn ","
  pairs.findSome? fun pair =>
    let parts := pair.splitOn ":"
    match parts with
    | k :: rest =>
      let k' := stripToken k
      let v  := stripToken (":".intercalate rest)
      if k' == key then some v else none
    | _ => none

-- ── Decimal integer parser ────────────────────────────────────────────────────

/-- Parse a non-negative decimal integer from a string. -/
def parseNat (s : String) : Option Nat :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.isEmpty then none
  else
    t.toList.foldlM (fun acc c =>
      if '0' ≤ c && c ≤ '9' then some (acc * 10 + (c.toNat - '0'.toNat))
      else none
    ) 0

/-- Parse a uint32 from a decimal string, returning none if out of range. -/
def parseUInt32 (s : String) : Option UInt32 :=
  match parseNat s with
  | none => none
  | some n =>
    if n > 4294967295 then none
    else some (UInt32.ofNat n)

-- ── JSON serialiser ───────────────────────────────────────────────────────────

def bytesToJsonArray (bs : List UInt8) : String :=
  "[" ++ (", ".intercalate (bs.map fun b => toString b.toNat)) ++ "]"

end BranchOnOutputOracle

open BranchOnOutputOracle

-- ── Entry point ───────────────────────────────────────────────────────────────

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  let s := line.trimAsciiStart.trimAsciiEnd.toString
  match jsonGet "outputIndex" s with
  | none =>
    IO.println "{\"error\": \"bad_input\"}"
  | some raw =>
    match parseUInt32 raw with
    | none =>
      IO.println "{\"error\": \"bad_input\"}"
    | some n =>
      let bs := u32ToLE n
      IO.println s!"\{\"bytes\": {bytesToJsonArray bs}}"

```
