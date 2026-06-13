---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ReplayPrevention.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.345240+00:00
---

# proofs/tla/ReplayPrevention.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    NULL = NULL
    Actors = {a1, a2}
    Resources = {r1, r2}
    TxIds = {tx1, tx2}
    LeafPubkeys = {leaf1, leaf2}
    MsgDigests = {msg1, msg2}
    Contexts = {ctx1, ctx2}
    MaxIndex = 2

INVARIANTS
    NoDoubleConsume
    SingleConsumption
    AffineExclusion
    ConsumedImpliesProof
    NoSignReplay
    SignFreshness
    INV_NoIndexReuse
    INV_IndexInRange

PROPERTIES
    PROP_IndexMonotonic

```
