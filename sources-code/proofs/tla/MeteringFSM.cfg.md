---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/MeteringFSM.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.351013+00:00
---

# proofs/tla/MeteringFSM.cfg

```cfg
SPECIFICATION FairSpec

CONSTANTS
    MaxTicks = 3
    MaxSatPerTick = 2

INVARIANTS
    ValidTransitionsOnly
    TickCounterConsistency

PROPERTIES
    EventualSettlement

```
