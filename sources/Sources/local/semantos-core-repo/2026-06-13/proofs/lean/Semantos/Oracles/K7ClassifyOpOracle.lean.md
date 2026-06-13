---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Oracles/K7ClassifyOpOracle.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.363161+00:00
---

# proofs/lean/Semantos/Oracles/K7ClassifyOpOracle.lean

```lean
/-
  K7ClassifyOpOracle — differential oracle for K7 (Cell Immutability).

  K7 proves that no opcode modifies cell header fields. The key sub-theorems
  testable via this oracle are K7d, K7e, K7f, which prove that specific
  opcodes are classified as `inspect` (read-only from a linearity perspective):

    K7d: classifyOp OP_READHEADER    = .inspect  (0xC9)
    K7e: classifyOp OP_READPAYLOAD   = .inspect  (0xCC)
    K7f: classifyOp OP_CODESEPARATOR = .inspect  (0xAB)

  Contrast: OP_DUP (0x76) = .duplicate, OP_DROP (0x75) = .discard.
  These are proven by K1 (LinearityK1.lean).

  This oracle wraps `Semantos.Opcodes.classifyOp` to support differential
  testing: given any opcode byte, predict its classification; the Bun fuzzer
  then validates that the Zig WASM engine respects this classification when
  linearity enforcement is enabled.

  Reads a single JSON line from stdin:
    {"op": "0xXX"}

  Prints a single JSON line to stdout:
    {"classification": "duplicate"|"discard"|"consume"|"swap"|"inspect"}
    {"error": "bad_input"}

  Used by `proofs/fuzz/k7-cell-immutability/fuzz.test.ts`.
-/
import Semantos.Opcodes.Classify

open Semantos Semantos.Opcodes

-- ── Hex parser (same pattern as K4) ──────────────────────────────────────────

def hexNibbleK7? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

def parseOpByteK7 (s : String) : Option UInt8 :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if !(t.startsWith "0x" || t.startsWith "0X") then none
  else
    let hex := (t.drop 2).toString
    if hex.length != 2 then none
    else
      let chars := hex.toList
      match chars with
      | [hi, lo] =>
        match hexNibbleK7? hi, hexNibbleK7? lo with
        | some h, some l => some (UInt8.ofNat (h * 16 + l))
        | _, _ => none
      | _ => none

-- ── JSON helpers ──────────────────────────────────────────────────────────────

def stripTokenK7 (s : String) : String :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.startsWith "\"" && t.endsWith "\"" then
    (t.drop 1).dropEnd 1 |>.toString
  else t

def jsonGetK7 (key : String) (json : String) : Option String :=
  let inner := (json.trimAsciiStart.trimAsciiEnd.toString.drop 1).dropEnd 1 |>.toString
  let pairs := inner.splitOn ","
  pairs.findSome? fun pair =>
    let parts := pair.splitOn ":"
    match parts with
    | k :: rest =>
      let k' := stripTokenK7 k
      let v  := stripTokenK7 (":".intercalate rest)
      if k' == key then some v else none
    | _ => none

-- ── Classification serialiser ─────────────────────────────────────────────────

def stackOpName : StackOp → String
  | .duplicate => "duplicate"
  | .discard   => "discard"
  | .consume   => "consume"
  | .swap      => "swap"
  | .inspect   => "inspect"

-- ── Entry point ──────────────────────────────────────────────────────────────

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  let s := line.trimAsciiStart.trimAsciiEnd.toString
  match jsonGetK7 "op" s with
  | none =>
    IO.println "{\"error\": \"bad_input\"}"
  | some opRaw =>
    match parseOpByteK7 opRaw with
    | none =>
      IO.println "{\"error\": \"bad_input\"}"
    | some op =>
      let cls := classifyOp op
      IO.println s!"\{\"classification\": \"{stackOpName cls}\"}"

```
