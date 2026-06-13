---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/EvidenceChain.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.347862+00:00
---

# proofs/tla/EvidenceChain.cfg

```cfg
SPECIFICATION AppendOnlySpec

CONSTANTS
    MaxChainLen = 4
    NULL_HASH = NULL_HASH
    Actors = {a1, a2}
    HashValues = {NULL_HASH, h1, h2, h3, h4, h5}

INVARIANTS
    ChainIntegrity
    UniqueStateHashes

```
