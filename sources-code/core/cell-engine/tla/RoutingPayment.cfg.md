---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tla/RoutingPayment.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.956456+00:00
---

# core/cell-engine/tla/RoutingPayment.cfg

```cfg
\* TLC configuration for RoutingPayment.tla
\*
\* Three runs scale the model:
\*   N=2, MAX_FAILURES=1 — minimal smoke (≤ 100 states)
\*   N=3, MAX_FAILURES=1 — exhaustive (≤ 10k states)
\*   N=4, MAX_FAILURES=2 — exhaustive (≤ 1M states) — primary check
\*   N=8 — leave for simulation mode (state-space explosion); see README.md
\*
\* Default config is N=4, MAX_FAILURES=2.  Override on the command line
\* via TLC's -config flag if running a different scale.

SPECIFICATION Spec

CONSTANTS
    N = 4
    MAX_FAILURES = 2

INVARIANTS
    TypeOK
    AtMostOneClaim
    NoCrossClaim
    ClaimImpliesDone
    DoneImpliesClaim
    FailureBound

PROPERTIES
    EventualResolution
    AllActiveClaim

```
