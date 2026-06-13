---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/TreeOfChainsMerge.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.344233+00:00
---

# proofs/tla/TreeOfChainsMerge.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    Editors = {e1, e2}
    HashValues = {h1, h2, h3}
    MaxBranchLen = 2
    NullHash = NullHash

INVARIANTS
    TypeInv
    K17a_MergeConsistency
    K17b_TipMatchesBranch
    K17c_MergeIsOneShot
    K17_TreeOfChainsMerge

```
