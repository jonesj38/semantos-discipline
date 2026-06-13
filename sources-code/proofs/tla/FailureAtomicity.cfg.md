---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/FailureAtomicity.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.341855+00:00
---

# proofs/tla/FailureAtomicity.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    MaxStackDepth = 3
    CellValues = {v1, v2}
    ResultValue = r

INVARIANTS
    TypeInv
    FailureAtomicity_K4
    K4_FailureAtomicity

```
