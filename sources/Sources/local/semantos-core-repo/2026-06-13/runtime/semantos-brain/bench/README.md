---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/bench/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.266773+00:00
---

# Semantos Benchmark Suite — `runtime/semantos-brain/bench/`

Standalone benchmark executables for Semantos kernel components. No external
dependencies beyond Zig 0.15 (and `liblmdb` for the LMDB bench).

---

## LMDB Throughput Benchmarks

File: `bench_lmdb.zig`  
Build step: `bench-lmdb` (defined in `core/cell-engine/build.zig`)

Uses the realistic cell shape from M1.5 (`cell_store_lmdb.zig`):
- **Key**: 32-byte `type_hash`
- **Value**: 1024-byte cell body

### Prerequisites

| Platform | Command |
|---|---|
| macOS | `brew install lmdb` |
| Debian / Ubuntu | `apt-get install liblmdb-dev` |
| Arch Linux | `pacman -S lmdb` |
| Alpine | `apk add lmdb-dev` |

### How to run

```sh
cd core/cell-engine
zig build bench-lmdb
```

Built in `ReleaseFast` mode. The 1M row takes 1–3 minutes on Apple Silicon.

### What each benchmark measures

| Benchmark | What it tests |
|---|---|
| Sequential write | Throughput of writing N cells in a single transaction (best-case write) |
| Sequential read | Throughput of reading N cells by key in insertion order (hot-page scenario) |
| Random read | Throughput of reading N cells by shuffled key order (cold-page scenario) |
| Cursor scan full table | Throughput of iterating the entire table via `cursor.next()` |
| Reorg rollback (ms/rollback) | Latency of deleting 10 consecutive block headers — simulates height truncation |
| Txn batch size 1 | One `txn.commit()` per cell — worst-case write durability overhead |
| Txn batch size 100 | 100 cells per transaction — typical streaming ingestion |
| Txn batch size 1000 | 1000 cells per transaction — bulk ingestion |
| Sequential write NOSYNC | Same as sequential write but with `MDB_NOSYNC` — durability disabled |

### Interpreting results against M1-T targets

The **Target** column shows the M1-T torture test requirements:

- **Sequential write ≥ 50K cells/sec** sustained
- **Random read ≥ 200K cells/sec**

Measured on Apple Silicon (for reference):

| Benchmark | 10K | 100K | 1M | Target |
|---|---|---|---|---|
| Sequential write | 67.2K/s | 27.7K/s | 14.7K/s | 50K/s |
| Sequential read | 1.6M/s | 1.1M/s | 164.8K/s | 200K/s |
| Random read | 2.7M/s | 1.2M/s | 666.9K/s | 200K/s |
| NOSYNC write | 280.5K/s | 164.8K/s | 116.0K/s | — |

**Note**: sequential write degrades at 1M entries due to fsync + B-tree CoW
overhead. NOSYNC mode exceeds target at all scales. See durability flags below.

Values below target indicate:
1. Map size needs tuning (set `map_size` to 2–3× the expected data size)
2. Filesystem is slow (use SSD or tmpfs)
3. Batch size is too small (use batch ≥ 100 for sustained writes)

### What "reorg rollback" tests

Measures time to delete the last 10 block headers from a 10K-height table —
simulating height truncation during a chain reorganisation. Does not include
UTXO rollback or subscriber notification.

### Durability flags

The **NOSYNC** row disables `fsync` (`MDB_NOSYNC`) — maximum throughput, not
safe for production write nodes. The default configuration uses `fdatasync`
on every commit.

---

## Pask Kernel Benchmarks

File: `bench_pask.zig`  
Build step: `bench-pask` (defined in `core/cell-engine/build.zig`)

### How to run

```sh
cd core/cell-engine
zig build bench-pask
```

No prerequisites beyond Zig 0.15. All Pask kernel modules compiled from source
in `core/pask/src/`.

### What it measures

| Benchmark | Description |
|---|---|
| `interact() with 0 related cells` | Cost of a pure single-node interaction (no edge work) |
| `interact() with 5 related cells` | Moderate fanout — typical workload |
| `interact() with 10 related cells` | High fanout — stress-tests propagation |
| `Graph size: nodes` | Node pool utilisation at each scale point |
| `Graph size: edges` | Edge pool utilisation at each scale point |
| `Snapshot serialize (µs)` | Write magic header + Store bytes; 100 reps, mean ± stddev |
| `Snapshot restore (µs)` | Read back and copy Store bytes; 100 reps, mean ± stddev |
| `Round-trip byte-identical` | Serialize → restore → re-serialize → `std.mem.eql` |
| `Replay 1K events determinism` | Same 1K sequence on two fresh stores → snapshots byte-identical |

The `interact()` benchmarks replicate `pask_interact_run()` using the `Store`
API directly — pure kernel throughput with no WASM boundary overhead.

### Interpreting results against M3-T-Pask targets

**Throughput target — 1M interactions**

If the 100K rate extrapolates to > 60 seconds for 1M, the 1M column is skipped
with a `(skip)` marker and an estimated time. A passing M3-T-Pask result
requires the 1M column to complete (100K rate ≥ ~17K calls/sec).

**Determinism target — byte-identical replay**

Both correctness checks must print `PASS`. A `FAIL` exits with code 1.

- **Round-trip**: proves the snapshot ABI round-trips losslessly. Any struct
  size change or padding shift will break this.
- **Replay determinism**: same `(cell_id, related_ids, strength, now_ms)`
  sequence on two independent stores → bit-identical `Store` structs. This is
  the invariant that makes Pravega-based replay (M3.10) safe.

### What "determinism" means

The Pask kernel never reads a system clock — `now_ms` is always caller-supplied.
Deterministic means: given the same sequence of inputs, two fresh kernel
instances produce bit-for-bit identical internal state. This is what allows
M3.10 (replay-from-genesis) to reconstruct any historical Pask snapshot.

### Key Config defaults

| Parameter | Default | Effect |
|---|---|---|
| `propagation_depth` | 3 | Propagation iterations per interact() |
| `learning_rate` | 0.1 | Scales edge weight deltas |
| `stability_check_every` | 1 | Check stability every interaction |
| `prune_every` | 1 | Prune graph every interaction |
| `MAX_NODES` | 16,384 | Fixed node pool cap |
| `MAX_EDGES` | 32,768 | Fixed edge pool cap |
