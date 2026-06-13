---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/mutations/plexus_mutations.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.954691+00:00
---

# Plexus & Kernel Mutation Testing Results (M5–M10)

Kill rate: **100%** (6/6 killed)

| ID | Target | Mutation | Catching Tests | Status |
|----|--------|----------|----------------|--------|
| M5 | `src/opcodes/plexus.zig:137` | Remove `if (actual_flag != expected_flag) return error.domain_flag_mismatch` | `plexus_conformance: CHECKDOMAINFLAG fails on mismatch`, `differential_conformance: K3 CHECKDOMAINFLAG mismatch` | KILLED |
| M6 | `src/opcodes/plexus.zig:161` | Remove `if (!std.mem.eql(u8, &actual_hash, &expected_hash)) return error.type_hash_mismatch` | `plexus_conformance: CHECKTYPEHASH fails on mismatch`, `differential_conformance: K3 CHECKTYPEHASH mismatch` | KILLED |
| M7 | `src/opcodes/plexus.zig:106` | Remove `if (!std.mem.eql(u8, &actual_id, &expected_id)) return error.owner_id_mismatch` | `plexus_conformance: CHECKIDENTITY fails on mismatch`, `differential_conformance: K2 CHECKIDENTITY mismatch` | KILLED |
| M8 | `src/constants.zig:16` | `MAIN_STACK_CELLS: u32 = 1024` → `2048` | `smoke_test: MAIN_STACK_CELLS is 1024`, `pda_conformance: stack overflow at 1024`, `differential_conformance: K5 main stack overflow` | KILLED |
| M9 | `src/executor.zig:245` | Remove `if (ctx.pda.opcount >= ctx.pda.max_ops) return error.execution_limit` | `executor_conformance: execution limit reached`, `differential_conformance: K5` | KILLED |
| M10 | `src/opcodes/plexus.zig:71` | Change `speekAt(0)` to `spop()` in CHECKCAPABILITY (break atomicity) | `plexus_conformance: CHECKCAPABILITY stack unchanged on failure`, `fuzz/plexus_atomic_fuzz: two-arg atomicity` | KILLED |

## Analysis

All 6 mutations are caught by multiple independent test layers:
- **M5–M7**: Plexus opcode check bypass — caught by both conformance and differential tests
- **M8**: Stack bounds change — caught by smoke test constants check and PDA overflow tests
- **M9**: Opcount removal — caught by executor conformance (execution limit test)
- **M10**: Atomicity break — caught by plexus conformance (failure-atomic assertions) and fuzz harness
