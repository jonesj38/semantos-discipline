---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/KeyCustody.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.351546+00:00
---

# proofs/tla/KeyCustody.cfg

```cfg
SPECIFICATION FairSpec

CONSTANTS
    Tiers = {1, 2}
    Actors = {tab1, tab2}
    NULL = NULL

INVARIANTS
    TypeInv
    INV_NoConcurrentDecrypt
    INV_DecryptionConsistency
    INV_RecoveryRequiresEnrollment

PROPERTIES
    PROP_NoResurrection
    PROP_TierFactorRespected
    LIVE_EventualUnlock
    LIVE_EventualRecovery

```
