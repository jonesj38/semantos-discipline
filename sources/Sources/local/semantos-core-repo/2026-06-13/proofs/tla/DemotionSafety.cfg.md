---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/DemotionSafety.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.346796+00:00
---

# proofs/tla/DemotionSafety.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    ResourceIds = {r1, r2}
    Actors = {a1}
    TxIds = {tx1}
    NULL = NULL

INVARIANTS
    TypeInv
    NoPromotion
    DemotedFromLinearOnly
    ConsumedIsLinear

```
