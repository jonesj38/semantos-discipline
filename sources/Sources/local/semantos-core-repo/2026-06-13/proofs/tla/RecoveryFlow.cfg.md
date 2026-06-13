---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/RecoveryFlow.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.349684+00:00
---

# proofs/tla/RecoveryFlow.cfg

```cfg
SPECIFICATION FairSpec

CONSTANTS
    Actors = {legit, adversary}
    LegitActor = legit
    MaxOtpAttempts = 2
    NEVER = NEVER

INVARIANTS
    TypeInv
    SAFE_OtpRateLimit
    SAFE_LockedNoCompletion
    SAFE_RecoveryRequiresEnrollment
    SAFE_EnvelopeRequiresCorrectAnswers
    SAFE_SeedRequiresEnvelopeAndAnswers
    SAFE_AdversaryCannotComplete

PROPERTIES
    PROP_OneCompletion
    LIVE_EventualEnrollment

```
