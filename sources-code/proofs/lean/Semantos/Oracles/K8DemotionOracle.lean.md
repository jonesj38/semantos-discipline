---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Oracles/K8DemotionOracle.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.363433+00:00
---

# proofs/lean/Semantos/Oracles/K8DemotionOracle.lean

```lean
/-
  K8DemotionOracle — differential oracle for K8 (Linearity Demotion Safety).

  Reads a single JSON line from stdin:
    {"from": "linear"|"affine"|"relevant"|"debug",
     "to":   "linear"|"affine"|"relevant"|"debug"}

  Prints a single JSON line to stdout:
    {"valid": true}        — validDemotion src tgt = true
    {"valid": false}       — validDemotion src tgt = false
    {"error": "bad_input"} — unrecognised linearity token

  The oracle is a thin wrapper around `Semantos.Opcodes.validDemotion`.
  It covers all 16 cells of the 4×4 demotion table proved in K8
  (DemotionK8.lean: k8a_linear_to_affine_valid, k8b_linear_to_relevant_valid,
   k8c through k8i all invalid, plus k8_only_linear_demotable).

  Used by `proofs/fuzz/k8-demotion/fuzz.test.ts` to assert that the
  Zig WASM cell-engine's OP_DEMOTE (0xCB) agrees with the Lean4 demotion
  model on every (from, to) pair.

  Lean 4.29.0 API notes:
    - String.drop / dropEnd return String.Slice, not String
    - Use .toString to convert back to String before calling splitOn etc.
-/
import Semantos.Opcodes.Plexus

open Semantos Semantos.Opcodes

-- ── JSON helpers (same pattern as K1LinearityOracle) ─────────────────────────

def stripTokenK8 (s : String) : String :=
  let t := s.trimAsciiStart.trimAsciiEnd.toString
  if t.startsWith "\"" && t.endsWith "\"" then
    (t.drop 1).dropEnd 1 |>.toString
  else t

def jsonGetK8 (key : String) (json : String) : Option String :=
  let inner := (json.trimAsciiStart.trimAsciiEnd.toString.drop 1).dropEnd 1 |>.toString
  let pairs := inner.splitOn ","
  pairs.findSome? fun pair =>
    let parts := pair.splitOn ":"
    match parts with
    | k :: rest =>
      let k' := stripTokenK8 k
      let v  := stripTokenK8 (":".intercalate rest)
      if k' == key then some v else none
    | _ => none

-- ── Parsers ──────────────────────────────────────────────────────────────────

def parseLin : String → Option Linearity
  | "linear"   => some .linear
  | "affine"   => some .affine
  | "relevant" => some .relevant
  | "debug"    => some .debug
  | _          => none

-- ── Entry point ──────────────────────────────────────────────────────────────

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  let s := line.trimAsciiStart.trimAsciiEnd.toString
  match jsonGetK8 "from" s, jsonGetK8 "to" s with
  | none, _ | _, none =>
    IO.println "{\"error\": \"bad_input\"}"
  | some fRaw, some tRaw =>
    match parseLin fRaw, parseLin tRaw with
    | none, _ | _, none =>
      IO.println "{\"error\": \"bad_input\"}"
    | some src, some tgt =>
      if validDemotion src tgt then
        IO.println "{\"valid\": true}"
      else
        IO.println "{\"valid\": false}"

```
