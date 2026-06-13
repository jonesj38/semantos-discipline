---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/SemanticTypes.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.344982+00:00
---

# proofs/tla/SemanticTypes.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    NULL = NULL
    Actors = {a1, a2}
    ResourceIds = {r1, r2}
    TxIds = {tx1, tx2}

INVARIANTS
    TypeInv
    LinearAtMostOnce
    AffineExclusion
    RevokedHasProof
    ConsistentConsumeCanConsume

```
