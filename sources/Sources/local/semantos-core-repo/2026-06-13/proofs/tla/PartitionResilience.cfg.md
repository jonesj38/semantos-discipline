---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/PartitionResilience.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.347368+00:00
---

# proofs/tla/PartitionResilience.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    NULL = NULL
    Nodes = {n1, n2}
    Resources = {r1, r2}

INVARIANTS
    NoSplitBrainConsume
    LocalContinuity
    ConsumedHasOwner

PROPERTIES
    ReconciliationComplete

```
