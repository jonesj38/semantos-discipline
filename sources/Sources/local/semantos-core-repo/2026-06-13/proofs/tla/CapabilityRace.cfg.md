---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/CapabilityRace.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.349932+00:00
---

# proofs/tla/CapabilityRace.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    Actors = {a1, a2}
    CapabilityIds = {c1}
    PubKeys = {pk1, pk2}
    DomainFlags = {d1}

INVARIANTS
    TypeInv
    K15_NoDoubleSpend
    K15_SpendCountConsistent
    K15_CapabilityRace

```
