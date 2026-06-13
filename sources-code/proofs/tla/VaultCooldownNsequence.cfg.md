---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/VaultCooldownNsequence.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.346272+00:00
---

# proofs/tla/VaultCooldownNsequence.cfg

```cfg
SPECIFICATION FairSpec

CONSTANTS
    MaxBlocks = 10
    MaxUtxos = 3
    DefaultNsequence = 2

INVARIANTS
    TypeInv
    INV_NsequenceRespected
    INV_ChainStructurallyConsistent
    INV_SpendsRespected

PROPERTIES
    LIVE_VaultEventuallySpendable
    LIVE_BlocksAdvance
    PROP_NsequenceRespected

```
