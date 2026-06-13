---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/FederationPropagation.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.342665+00:00
---

# proofs/tla/FederationPropagation.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    Regions = {r1, r2}
    CellIds = {cell1, cell2}
    MaxChainPos = 3

INVARIANTS
    TypeInv
    K18c_ChainMonotonic
    K18d_PropagationPersistent
    K18_FederationPropagation

```
