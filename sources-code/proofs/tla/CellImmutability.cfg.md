---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/CellImmutability.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.349184+00:00
---

# proofs/tla/CellImmutability.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    CellIds = {c1, c2, c3}
    Linearities = {"LINEAR", "AFFINE", "RELEVANT", "DEBUG"}
    TypeHashes = {th1, th2}
    OwnerIds = {o1}
    MaxStackDepth = 2

INVARIANTS
    TypeInv
    K7_HeaderImmutable
    K7a_LinearityImmutable
    K7_CellImmutability

```
