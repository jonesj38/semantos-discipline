---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.586810+00:00
---

# Torture Tests

Per §6 of `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`, each milestone
exit gate requires a **24-hour** sustained-load + fault-injection test to pass
continuously before the milestone is considered complete.

Torture tests are authored by a *different agent* than the one that wrote the
deliverable (to avoid "I tested what my code does" bias).

## Running a torture test

```
# Run the M1 LMDB torture test (requires LMDB-backed brain running):
bash tests/torture/M1_torture.sh

# Run the M5 Postgres torture test:
bash tests/torture/M5_torture.sh

# Run all (sequential; each takes up to 24 h):
bash tests/torture/run_all.sh
```

## File index

| File                  | Milestone | Description                                        |
|-----------------------|-----------|----------------------------------------------------|
| `M1_torture.sh`       | M1-T      | LMDB 100 M cells + crash + reorg load              |
| `M2_torture.sh`       | M2-T      | SQLite-OPFS tab-kill + quota + concurrency         |
| `M3_torture.sh`       | M3-T      | Pravega 24 h 20 Hz tick + subscriber restart       |
| `M3_Pask_torture.sh`  | M3-T-Pask | Pask determinism: 1 M interactions, replay + 5-node convergence |
| `M4_torture.sh`       | M4-T      | Octave 1+ 1 M windowed reads + MFP budget          |
| `M5_torture.sh`       | M5-T      | Postgres 100 M cert_dag recursive CTE + FDW        |
| `M6_torture.sh`       | M6-T      | Registry drift detection + reconciliation          |
| `M7_torture.sh`       | M7-T      | Federation byzantine + slot rebalance              |
| `run_all.sh`          | all       | Sequential runner; logs to `tests/torture/logs/`  |

## Pass criteria

Each script exits 0 only if all conditions from §6 held for the full duration.
A non-zero exit code means the milestone has not passed its exit gate.
