---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-12-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.657298+00:00
---

# Phase 12 Errata

## Audit Summary

Audit performed against the 10-point scan checklist from the Phase 12 execution prompt. **8 items passed on initial review; 2 issues found and fixed.**

## Issues Found

### Issue 1: Differential vectors missing 0xC8 (OP_DEREF_POINTER)

**Severity**: SHOULD FIX
**File**: `proofs/vectors/plexus-vectors.json`, `packages/cell-engine/tests/differential_conformance.zig`
**Description**: The differential test vectors covered opcodes 0xC0-0xC7 and 0xC9-0xCF but omitted 0xC8 (OP_DEREF_POINTER). While this opcode requires host functions for its success path (making full integration testing impossible in native Zig), the failure path (non-pointer cell → `invalid_pointer_cell`) is testable.
**Fix**: Added 0xC8 vector to `plexus-vectors.json` and corresponding test to `differential_conformance.zig`. Total vectors: 57 → 58.

### Issue 2: CI fuzz step used --dry-run fallback pattern

**Severity**: COSMETIC
**File**: `.github/workflows/gate.yml`
**Description**: The fuzz compilation step used `--dry-run 2>/dev/null || zig build ...` which was unclear about intent. The fuzz harnesses are already part of `zig build test` via `test_step` dependencies. The separate CI step should clearly indicate it compiles and runs the fuzz harnesses.
**Fix**: Simplified to direct `zig build fuzz-linearity fuzz-opcodes fuzz-stack fuzz-plexus` without `--dry-run` fallback.

## Items Passed

1. **Fuzz harnesses actually fuzz** — All 4 use `std.Random.Xoshiro256` with deterministic seeds and ≥50K iterations
2. **Linearity fuzzer checks BOTH stacks** — `countLinearCells()` scans main_stack + aux_stack
3. **Differential vectors cover all Plexus opcodes** — Now covers 0xC0-0xCF (after fix)
4. **Mutation testing reverted cleanly** — `git diff src/` shows no residual mutations
5. **Reproducible build tested twice** — Script does two full builds from scratch with hash comparison
6. **P4.1 capstone references real files** — All 24 referenced artifact files exist
7. **Compliance matrix covers all tests** — 26 tests across 7 frameworks, zero gaps
8. **Compliance matrix proof artifacts exist** — All 24 unique referenced files verified
9. **Gate test validates fuzz compilation** — CI verifies fuzz harnesses compile and run
10. **No mock fuzz results** — Real PRNG, real iterations, real pass/fail
