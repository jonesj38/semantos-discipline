---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/Linearity.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.344478+00:00
---

# proofs/tla/Linearity.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    LinearCells = {l1}
    NonLinearCells = {n1}
    MaxMainDepth = 3
    MaxAuxDepth = 2

INVARIANTS
    TypeInv
    K1a_NoDuplication
    K1c_NoReappearance
    K1_Linearity

```
