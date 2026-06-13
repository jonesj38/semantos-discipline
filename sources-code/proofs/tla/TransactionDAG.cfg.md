---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/TransactionDAG.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.343436+00:00
---

# proofs/tla/TransactionDAG.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    TxIds = {t1, t2, t3}
    OutputIds = {o1, o2, o3, o4}
    MaxTxCount = 3
    NULL = NULL

INVARIANTS
    TypeInv
    Acyclicity
    PathExclusivity
    PruningIrreversibility
    AttestationValidity
    TemporalOrdering
    SpentHasSpender

```
