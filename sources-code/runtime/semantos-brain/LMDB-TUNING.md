---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/LMDB-TUNING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.028408+00:00
---

# LMDB Environment Tuning (M1.9)

This document records the durability and safety choices made for the LMDB
environment used by the BRAIN substrate, and describes the crash-recovery
guarantees provided by each mode.

---

## Flag comparison

| Mode | Flag(s) | Commit latency | Durability on power-loss | Notes |
|------|---------|---------------|--------------------------|-------|
| **Full sync** (LMDB default) | _(none)_ | Slowest — two fsyncs per commit | Strongest — every committed transaction survives | Rarely needed at this scale |
| **NOMETASYNC** | `MDB_NOMETASYNC` | Fast — one fsync (data pages) | Data pages flushed; meta page may lag one txn | **Chosen production default** |
| **NOSYNC** | `MDB_NOSYNC` | Fastest — zero fsyncs | Unsafe — arbitrary page corruption on power-loss | CI / benchmarks only |

---

## Chosen defaults

### Production: `NOTLS | NOMETASYNC`

Defined as `LmdbConfig.prod_flags` in `src/lmdb/lmdb_config.zig`.

**`MDB_NOTLS`** is always set because the BRAIN substrate runs in a
single-threaded WASM/async event-loop context.  LMDB's default behaviour
uses thread-local storage (TLS) to track reader lock slots; in a
single-threaded host this causes deadlocks when the same OS thread re-enters
LMDB from different async tasks.  `MDB_NOTLS` disables TLS and uses a
per-handle reader slot instead.

**`MDB_NOMETASYNC`** is the production durability setting.  LMDB's commit
path with this flag:

1. Writes dirty data pages to the OS page cache.
2. Calls `fdatasync` (or `msync`) to flush data pages to stable storage.
3. Writes the new meta page (B-tree root, last-txn-id) — but does **not**
   fsync it.

On an unclean shutdown (power-loss, OOM kill, SIGKILL) the data pages are
already on disk.  The meta page may still hold the pointer from the
**previous** transaction.  LMDB detects this on re-open and presents the
last fully committed transaction — at most one transaction is lost.

This is an acceptable trade-off for the substrate:

* The lost transaction window is bounded to one commit cycle (typically
  milliseconds).
* There is **no** corruption risk — LMDB always recovers to a consistent
  state.
* Throughput is significantly higher than full-sync mode on spinning disks
  and only marginally slower on NVMe.

### CI / testing: `NOTLS | NOSYNC`

Defined as `LmdbConfig.ci_flags`.

`MDB_NOSYNC` skips all fsyncs.  In a CI sandbox the OS flushes all dirty
pages on process exit, so data durability is effectively provided by the
container lifecycle.  **Never use this in production.**

---

## Crash-recovery guarantee (NOMETASYNC)

With `prod_flags` (`NOTLS | NOMETASYNC`):

* **Clean close** → all committed transactions are intact.
* **SIGKILL / power-loss** → LMDB recovers to the last committed transaction.
  At most the meta page for the final in-flight commit is missing; data pages
  for that commit are present on disk but unreachable until LMDB is reopened
  and rebuilds the meta from the previous clean snapshot.
* **No silent corruption** — LMDB uses copy-on-write B-trees; partial writes
  never overwrite live data.

The conformance test `tests/lmdb_crash_recovery.sh` verifies all four
properties:

| Test ID | Assertion |
|---------|-----------|
| `M1.9-T-clean-commit` | 10 records written + clean close → 10 records on reopen |
| `M1.9-T-nometasync-recovery` | 10 records + SIGKILL → ≥ 9 records on reopen, no corruption |
| `M1.9-T-nosync-not-default` | `prod_flags & MDB_NOSYNC == 0` (static) |
| `M1.9-T-notls-always` | `prod_flags & MDB_NOTLS != 0` (static) |

---

## When to change the defaults

| Scenario | Recommended flags |
|----------|-------------------|
| Production node | `LmdbConfig.prod_flags` (default) |
| CI / integration tests | `LmdbConfig.ci_flags` |
| Benchmark / profiling | `ci_flags` or add `MDB_WRITEMAP | MDB_MAPASYNC` |
| Read-only replica | `prod_flags | EnvFlags.RDONLY` |
| Embedded / memory-constrained | Reduce `map_size`; keep `prod_flags` |

---

## Sizing

The default map size is **1 GiB** (`LmdbConfig.default.map_size`).  LMDB
uses a sparse file backed by `mmap`; the file only consumes disk space
proportional to actual data written.  For production deployments with large
cell graphs, set `map_size` to 2–4× the expected dataset size to avoid
`MDB_MAP_FULL` errors without hot-resize downtime.
