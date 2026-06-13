---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tla/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.956198+00:00
---

# TLA+ models — cell-engine

This directory holds TLA+ specifications for cell-engine invariants that
extend beyond what unit tests can express — typically concurrent or
multi-actor properties.

## Files

| File                   | Models                                                                        |
| ---------------------- | ----------------------------------------------------------------------------- |
| `RoutingPayment.tla`   | OP_BRANCHONOUTPUT concurrent claim safety (N relays, multi-output payment)    |
| `RoutingPayment.cfg`   | Default model parameters (N=4, MAX_FAILURES=2)                                |

## Running TLC

TLC isn't bundled with the repo. Install once:

```bash
# Option A: download tla2tools.jar from the TLA+ GitHub releases
curl -L -o /tmp/tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar

# Option B: install the TLA+ Toolbox (GUI + bundled TLC)
brew install --cask tla-plus-toolbox
```

Then from this directory:

```bash
java -jar /tmp/tla2tools.jar -config RoutingPayment.cfg RoutingPayment.tla
```

Expected output: `Model checking completed. No error has been found.`

## Model scales

The `RoutingPayment.cfg` defaults to N=4, MAX_FAILURES=2 — exhaustive
state-space search completes in seconds. For larger N:

```bash
# Simulation mode (random walk) for N=8
java -jar /tmp/tla2tools.jar \
  -simulate -depth 200 -workers 4 \
  -config RoutingPayment.cfg RoutingPayment.tla
```

Override constants on the command line by editing `RoutingPayment.cfg`
or generating a temporary config — TLC has no built-in CLI override.

## Spec linkage

- Top-level spec: `../../../docs/design/OP-BRANCHONOUTPUT-SPEC.md`
- Delivery tracker: `../../../docs/OP-BRANCHONOUTPUT-TRACKER.md`
- Lean4 proofs of the per-script invariants this model assumes:
  `../lean4/` (Phase 2)
