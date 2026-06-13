---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/mutations/linearity_mutations.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.955573+00:00
---

# Linearity Mutation Testing Results (M1–M4)

Kill rate: **100%** (4/4 killed)

| ID | Target | Mutation | Catching Tests | Status |
|----|--------|----------|----------------|--------|
| M1 | `src/linearity.zig:45` | `.duplicate => return error.cannot_duplicate_linear` → `.duplicate => {}` | `linearity_conformance: LINEAR: DUP fails`, `differential_conformance: K1 permission matrix`, `fuzz/linearity_fuzz: permission matrix` | KILLED |
| M2 | `src/linearity.zig:46` | `.discard => return error.cannot_discard_linear` → `.discard => {}` | `linearity_conformance: LINEAR: DROP fails`, `differential_conformance: K1 permission matrix`, `fuzz/linearity_fuzz: permission matrix` | KILLED |
| M3 | `src/linearity.zig:50` | `.duplicate => return error.cannot_duplicate_affine` → `.duplicate => {}` | `linearity_conformance: AFFINE: DUP fails`, `differential_conformance: K1 permission matrix`, `fuzz/linearity_fuzz: permission matrix` | KILLED |
| M4 | `src/linearity.zig:54` | `.discard => return error.cannot_discard_relevant` → `.discard => {}` | `linearity_conformance: RELEVANT: DROP fails`, `differential_conformance: K1 permission matrix`, `fuzz/linearity_fuzz: permission matrix` | KILLED |

## Analysis

All 4 linearity mutations are caught by multiple independent test layers:
1. **Conformance tests** (existing Phase 4) — direct unit tests for each error
2. **Differential tests** (Phase 12) — Lean model permission matrix verification
3. **Fuzz harnesses** (Phase 12) — random input verification against known table
