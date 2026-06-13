---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ReactorIsolation.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.342370+00:00
---

# proofs/tla/ReactorIsolation.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    Connections = {c1, c2, c3}

INVARIANTS
    TypeOK
    PollSetClearedBetweenCycles
    BoundedReadySet

PROPERTIES
    EventualService
    IsolationFromStalledConnections

```
