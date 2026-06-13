---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/TierEscalation.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.346013+00:00
---

# proofs/tla/TierEscalation.cfg

```cfg
SPECIFICATION FairSpec

CONSTANTS
    MaxAmount = 3
    MaxNow = 3
    Tier1Ceiling = 1
    Tier2Ceiling = 2
    Tier3Ceiling = 3
    Tier3Cooldown = 2
    Tier1Factor = "PIN"
    Tier2Factor = "BIO"
    Tier3Factor = "VAULT"
    NEVER = NEVER

INVARIANTS
    TypeInv
    INV_FactorMatchesTier
    INV_Tier3CooldownRespected
    INV_MonotonicAuthFriction
    INV_ClassifyRange
    INV_LastTier3Ordered

PROPERTIES
    LIVE_Tier0NoPrompt
    LIVE_MonotonicTime

```
