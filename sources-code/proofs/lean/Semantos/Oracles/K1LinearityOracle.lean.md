---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Oracles/K1LinearityOracle.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.362589+00:00
---

# proofs/lean/Semantos/Oracles/K1LinearityOracle.lean

```lean
/-
  K1LinearityOracle — differential oracle for K1 (Linearity).

  Reads a single JSON line from stdin:
    {"linearity": "linear"|"affine"|"relevant"|"debug",
     "op":        "duplicate"|"discard"|"consume"|"swap"|"inspect"}

  Prints a single JSON line to stdout:
    {"permitted": true}    — linearityPermits l op = true
    {"permitted": false}   — linearityPermits l op = false
    {"error": "bad_input"} — unrecognised linearity or op token

  The oracle is a thin wrapper around `Semantos.linearityPermits`.
  It covers all 20 cells of the 4×5 permission table proved in K1
  (LinearityK1.lean: k1a_linear_no_duplicate, k1b_linear_no_discard,
   affine_no_duplicate, relevant_no_discard + the 16 always-true cells).

  Used by `proofs/fuzz/k1-linearity/fuzz.test.ts` to assert that the
  Zig WASM cell-engine agrees with the Lean4 linearity model on every
  (linearity-type, stack-op) pair.

  Lean 4.29.0 API notes:
    - String.drop / dropEnd return String.Slice, not String
    - Use .toString to convert back to String before calling splitOn etc.
    - trimAsciiStart / trimAsciiEnd return String.Slice too
-/
import Semantos.Linearity

open Semantos

-- ── JSON helpers ─────────────────────────────────────────────────────────────

/-- Trim ASCII whitespace and strip outer double-quotes from a raw token.
    E.g. `"  \"linear\"  "` → `"linear"`. -/
def stripToken (s : String) : String :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.startsWith "\"" && t.endsWith "\"" then
    (t.drop 1).dropEnd 1 |>.toString
  else t

/-- Extract the value for a JSON string key from a flat one-level JSON object.
    Splits on `,`, then each pair on the first `:`.
    Only handles string values (double-quoted).
    Returns `none` if the key is not present. -/
def jsonGet (key : String) (json : String) : Option String :=
  -- Strip outer braces
  let inner := (json.trimAsciiStart.trimAsciiEnd.toString.drop 1).dropEnd 1 |>.toString
  -- Split on comma; each element is a `"key":"value"` pair
  let pairs := inner.splitOn ","
  pairs.findSome? fun pair =>
    -- Split on colon to separate key from value
    let parts := pair.splitOn ":"
    match parts with
    | k :: rest =>
      let k' := stripToken k
      let v  := stripToken (":".intercalate rest)  -- rejoin in case value contains ':'
      if k' == key then some v else none
    | _ => none

-- ── Parsers ──────────────────────────────────────────────────────────────────

def parseLinearity : String → Option Linearity
  | "linear"   => some .linear
  | "affine"   => some .affine
  | "relevant" => some .relevant
  | "debug"    => some .debug
  | _          => none

def parseStackOp : String → Option StackOp
  | "duplicate" => some .duplicate
  | "discard"   => some .discard
  | "consume"   => some .consume
  | "swap"      => some .swap
  | "inspect"   => some .inspect
  | _           => none

-- ── Entry point ──────────────────────────────────────────────────────────────

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  let s := line.trimAsciiStart.trimAsciiEnd.toString
  match jsonGet "linearity" s, jsonGet "op" s with
  | none, _ | _, none =>
    IO.println "{\"error\": \"bad_input\"}"
  | some lRaw, some oRaw =>
    match parseLinearity lRaw, parseStackOp oRaw with
    | none, _ | _, none =>
      IO.println "{\"error\": \"bad_input\"}"
    | some l, some op =>
      if linearityPermits l op then
        IO.println "{\"permitted\": true}"
      else
        IO.println "{\"permitted\": false}"

```
