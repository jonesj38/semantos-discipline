---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/PRIMER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.798244+00:00
---

# Pask Primer

A reader's guide to the Pask kernel. The machine-derived spec
([`pask-spec.json`](zig-out/release/pask-spec.json)) tells you the
**shape** of every export, struct, and config; this document tells you
the **why**, the **contract**, and the **invariants** that make the
shape load-bearing. Read this first, then the spec.

Pinned alongside each release: the spec.json, the wasm artifacts, and
this primer all hash into the release cell. The version of this doc
that ships with `pask-X.Y.Z` is exactly the contract for that version.

---

## What Pask is

Pask is a constraint-graph learning kernel. You feed it interactions
between named cells; it maintains a graph where edges accumulate
weight on co-occurrence, propagates local constraint effects, and
surfaces the cells whose behaviour has settled — *stable threads* —
as the discovered structure of the input.

It runs as a WASM module with a flat C ABI. Two distribution shapes:

- **Sibling** — `pask.wasm` (~7 KB freestanding, ~7 KB WASI). Loads
  alongside other kernels in the same host.
- **Combined** — `pask-and-cell.wasm` (~42 KB). One module exporting
  both `pask_*` and `kernel_*` (cell-engine), sharing one
  `WebAssembly.Memory`. Zero-copy between kernels.

There is no JavaScript or Rust port. The Zig source is the single
source of truth; everything downstream — the TS bindings, the spec
JSON, the comptime layout asserts — is derived from it.

## What Pask is NOT

- **Not a database.** It's a process that runs in linear memory. Its
  long-term home is the snapshot ABI: capture a 16 MB blob, persist
  it however you like (cells, SQLite, file, S3), restore later.
- **Not a graph database.** Nodes and edges are integer-indexed in
  fixed-pool arrays; you can't run arbitrary queries. The exposed
  query primitives are: stable threads (sorted by h_state),
  neighbours, and direct array views.
- **Not a recommendation engine.** It tells you what's *settled*. It
  does not tell you what's *next*. Building "next" is a layer above
  the kernel — see the helm-attention proposal.
- **Not online-learnable in the ML sense.** No backprop, no model
  weights to train. The graph evolves under constraint propagation;
  there's no objective being minimised.

---

## The model in five lines

```
G = (V, E)              graph of nodes and edges
h_i ∈ R                  state of node i
C_ij ∈ R                 constraint weight on edge (i, j)
ΔH(i) ≈ avg|recent ΔC|  node i's recent activity
stable(i) iff ΔH(i) < ε  node i has settled
```

Source: Pask's own constraint-mesh learning, reduced to the operations
the graph needs.

## What `interact` actually does

```
interact(primary, kind, strength, related[], now_ms):
  1. upsert primary node
  2. for r in related:
       upsert r
       upsert edge (primary → r)
       edge.weight += strength * lr
       record delta on the edge with timestamp now_ms
  3. primary.h_state += strength
  4. propagate (k iterations of localUpdate + region expansion)
  5. if tick % stability_check_every == 0:
       for n in affected: checkStability(n)
  6. if tick % prune_every == 0:
       pruneOnce()
```

Where:

- **localUpdate(node)**: walks node's outgoing edges, computes
  `(target.h - source.h) * edge.weight * lr` per edge, sums them,
  applies once to source. Edge trend EMA: `0.9 * old + 0.1 * effect`.
- **expandRegion**: grows the affected set by adding both endpoints
  of every edge touching any current member. One hop per call.
- **checkStability(node)**: averages `avgDelta(edge, window)` across
  every edge touching the node; marks stable iff that average is
  below `epsilon` and the node has at least `minInteractions`.
- **pruneOnce**: marks `is_pruned=1` on any non-pruned node whose
  inbound edge trend (mean of `delta_trend` on edges *into* it) is
  below `prune_threshold`. Nodes with no inbound edges are exempt.

Defaults are at the bottom of [src/config.zig](src/config.zig) and in
the spec under `defaultConfig`.

---

## The contract

These are the invariants the kernel guarantees. If you see a violation,
it's a bug — not a tuning issue.

### 1. Determinism is total

Every kernel call takes a `now_ms` argument. The kernel does not call
into a host clock, host RNG, host alloc, or any I/O. **The same input
sequence produces the same output state, byte for byte, on any machine
running the same wasm.** This is regression-tested
([determinism_conformance.zig](tests/determinism_conformance.zig)) by
running two engines independently over the same inputs and comparing
the resulting `Store` images bit-for-bit.

This is the load-bearing claim for offchain consensus, replay-based
audit, and cross-node migration.

### 2. Snapshot/restore is byte-stable

`pask_snapshot_state` returns a pointer to a header (`magic`, `version`,
`length`) followed by a copy of the entire `Store` struct. Restoring
the same blob produces a kernel state indistinguishable from the
original. The blob is **portable** between hosts running the same
kernel version.

The header layout — `[u32 magic = 0x4B534150 "PASK"][u32 version=1][u32 length][payload]` — mirrors the cell-engine's CESN format. One
persistence story for both.

### 3. Layout is comptime-locked

Every `extern struct` in [src/types.zig](src/types.zig) has its size
and field offsets asserted at compile time in [src/main.zig](src/main.zig).
The TS bindings and the spec JSON read those offsets directly; a struct
field rename or reorder fails the build before producing a wasm. Drift
is mechanically prevented.

### 4. NaN/Inf at the boundary cannot poison state

`updateNodeState` and `recordDelta` drop non-finite values silently.
This is intentional: a propagation step that briefly produces NaN
shouldn't corrupt every neighbour's state on the next interact. The
guard is at the input boundary; downstream code can assume `h_state`
is always finite.

### 5. Pruned nodes are never resurrected automatically

Once `pask_node_is_pruned` returns 1, the node is excluded from
stability checks and from new inbound edges' propagation. The only way
back is `pask_reset` (full kernel wipe) or `pask_restore_state` to a
snapshot from before the prune. This makes audit clean: a pruning
record is a one-way commit.

### 6. Indices are stable for the kernel's lifetime

A `NodeIdx` returned from `pask_upsert_node` remains valid until
`pask_reset`. Pruning sets a flag but does not free or re-pack the
slot. Callers can hold onto indices indefinitely.

---

## Capacities

Compile-time fixed pools (in [src/config.zig](src/config.zig)):

| Quantity | Cap | Static cost |
| --- | --- | --- |
| Nodes | 16,384 | 5.2 MB |
| Edges | 32,768 | 1.3 MB |
| Delta ring | 65,536 entries | 1.5 MB |
| Cell-id length | 64 bytes | inline in node |
| Type-path length | 96 bytes | inline in node |
| Affected-set per interact | 4,096 | bitset + array |
| Related cells per interact | 32 | scratch-allocated |

Total static state: ~18 MB (including the snapshot buffer mirror).
Initial WASM memory: 24 MB; ceiling: 64 MB.

Past these caps `pask_upsert_node` / `pask_upsert_edge` /
`pask_interact_run` return negative error codes (see the `errToCode`
table in [src/main.zig](src/main.zig)). They never silently truncate.

For graphs that don't fit, the answer is multi-instance: shard your
problem (e.g. one kernel per hat, per region, per shard), snapshot
state into the cell DAG, and route interactions to the right kernel
on the host side. Don't grow the caps unless every consumer can pay
the linear-memory cost.

---

## Tuning the config

The defaults match `friend-semantos/packages/paskian/src/grammar.ts`
and reproduce the chess result at 1500 GM games (see "Empirical
basis" below). For most uses, leave them alone. Knobs you might want
to touch:

- **`propagation_depth`** (default 3): how many hops constraint
  effects propagate per interact. Higher = richer reach, more compute.
  Drop to 1 for chat / message graphs where reach is already implicit
  in the edge structure.
- **`stability_window_ms`** (default 60_000): the time window over
  which `avgDelta` is computed. Shorter = stability tracks recent
  activity only. Set to your operational pulse — UI session length,
  daily reset, whatever lines up with the cadence at which you want
  "stable" to refresh.
- **`stability_check_every` / `prune_every`** (default 1 each):
  amortise cost across batches. Set to 0 to disable in-loop checks
  and call `pask_finalize` once at the end of a batch.
- **`min_interactions`** (default 5): minimum events before a node
  qualifies as stable. The chess rig uses 10. Raise it if you have
  noisy short-lived interactions you don't want crystallising.

The remaining defaults — `prune_threshold`, `learning_rate`,
`stability_epsilon` — should not be touched without re-running the
chess conformance test and confirming you still find the canonical
openings. They're not magic numbers; they're load-bearing.

---

## Empirical basis

The chess test ([tests/chess_conformance.zig](tests/chess_conformance.zig))
is the load-bearing conformance check. It feeds 1500 GM games as
move-prefix transitions through the kernel with no chess knowledge,
runs `finalize`, and asserts:

1. The number of stable threads is non-trivial.
2. The four most-trafficked first-ply prefixes are dominated by
   `e4`, `d4`, `Nf3`, `c4` — the canonical opening moves chess
   theory has built two centuries of analysis around.

If you change propagation, stability, or pruning math and the chess
test stops finding those moves, **the change is wrong, no matter
what other tests pass.** The chess result is the empirical anchor for
the whole system.

The TS reference implementation
(`friend-semantos/packages/paskian/src/`) produced this result first;
the Zig port had to reproduce it before being declared green. Same
empirical claim, two implementations, both pinned.

---

## Zero-copy, in plain words

The kernel keeps nodes, edges, and stable threads in contiguous arrays
in WASM linear memory. The TS bindings expose direct `Uint8Array`
views over those arrays:

```ts
const nodes = adapter.nodesView();
// nodes.bytes is a Uint8Array view onto the kernel's nodes array.
// Each record is nodes.stride bytes wide, with offsets given in spec.json.
```

For range queries, `pask_stable_threads_build(N)` materialises the
top N stable threads into the snapshot buffer once; the TS layer then
slices `[from, to)` from that buffer with one trampoline call total.
The cost is independent of slice size.

The views go stale on `pask_reset` and on memory growth (the
`ArrayBuffer` detaches). Re-call the view helpers after either event.

---

## Snapshot ABI in one paragraph

```
[u32 magic = 0x4B534150 ("PASK")]
[u32 version = 1]
[u32 length = sizeof(Store)]
[length bytes Store image]
```

The kernel writes this layout into a static buffer and returns its
pointer. `pask_restore_state(ptr)` reads from any pointer with the
same layout — typically the kernel's own buffer (after `pask_snapshot_buf_ptr`
write) or the scratch region for small blobs.

Versioning: future kernel versions that change the `Store` layout
bump the `version` byte. Old blobs become unreadable until you run
them through a migration. The kernel never silently accepts a
version mismatch — `pask_restore_state` returns -3.

---

## External library management

Pask's embedded build has zero external dependencies. The combined
build optionally pulls in `bsvz` for the cell-engine's full profile;
`build.zig.zon` pins each dep by URL + sha256. The release manifest's
`dependencies` array lifts those pins into the signed cell, so a
consumer fetching pask transitively verifies the full dep tree by
walking each dep's own release chain.

This is the same shape as npm or Cargo's lockfile, but living inside
the substrate's hash-chained signed cell DAG instead of a separate
package registry.

---

## When to use Pask

- An operator's behaviour over a set of objects (the helm
  attention-surface case).
- Co-occurrence learning over any stream of named events: which
  cells get worked on together, which prefixes recur in a corpus,
  which workflow steps the operator's brain has settled into.
- Any case where you want the *settled* answer — the canonical
  reference points the data has converged on, not the trending /
  freshest / loudest.

## When not to use Pask

- You have ~100 nodes — simpler than this. A `Map<string, number>`
  with a manually-tracked decay is enough.
- You need exact arithmetic — pask's edge weights are f64; floating
  point drift is bounded but real. For audit-grade arithmetic stay
  in fixed-point at a higher layer.
- You need cross-host realtime convergence — the kernel is
  deterministic *given the same input stream*. Two hosts processing
  partially-overlapping input streams will diverge. Solve with the
  cell DAG: snapshot, exchange, restore on the merge point.

---

## Where to read next

- **Spec**: [zig-out/release/pask-spec.json](zig-out/release/pask-spec.json)
  — the API surface, struct layouts, capacity caps. Machine-derived,
  always current.
- **Bindings adapter**: [bindings/ts/src/adapter.ts](bindings/ts/src/adapter.ts)
  — the TS surface that mirrors `friend-semantos/packages/paskian`.
- **Demo**: [demo/damian-demo.ts](demo/damian-demo.ts) — both kernels
  driven from one host, sibling and combined modes.
- **Source of truth**: [src/main.zig](src/main.zig). Everything in
  this primer is locked there or in the modules it imports.
