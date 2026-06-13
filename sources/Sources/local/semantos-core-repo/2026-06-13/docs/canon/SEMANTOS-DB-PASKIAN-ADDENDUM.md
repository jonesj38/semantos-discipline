---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.628242+00:00
---

# Paskian Kernel and the DB Topology — Addendum
**Companion to:** `SEMANTOS-DB-WISHLIST.md`, `SEMANTOS-DB-MULTI-TIER-TOPOLOGY.md`, `SEMANTOS-DB-OCTAVE-ADDENDUM.md`, `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`.
**Sources:** `core/pask/src/{main,types,store,propagation,stability,pruner,config}.zig`, `core/pask-and-cell/src/combined.zig`, `docs/paskian-learning-system-explainer.md`, `docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md`, `docs/prd/analyses/prd-paskian-analysis.html`.
**Honest preface:** the previous design docs treated the cell engine as the only kernel and shaped the four-tier DB topology around it. That's incomplete. The substrate has **two co-resident WASM kernels** — the cell engine and the Paskian Learning System (PLS) — and the DB topology has to serve both, including the bridge between them. This addendum revises the topology to add the third structural axis: **Pask state as a first-class storage citizen**.

---

## 1. What Pask is, in one paragraph

The Paskian Learning System is a Zig-implemented WASM kernel at `core/pask/` that ports Gordon Pask's 1976 *Conversation Theory* into a bounded, deterministic graph-update engine. Every concept in the system is a node identified by a `cell_id` (the same byte-string the cell engine uses for content addressing). Every relationship between concepts is an edge with a `constraint_weight` (how tightly coupled) and a `delta_trend` (the EMA of recent changes — the liveness of the relationship). Each interaction (a "turn" in Pask's sense) updates a primary node's `h_state` (activation level), reinforces edges to related nodes, and propagates the change through up to 3 hops of constraint propagation. Nodes whose state has stopped changing rapidly across enough interactions are declared **stable threads** — the system's computational equivalent of "learned." Nodes whose inbound delta trend goes negative are **pruned** — concepts that have gone cold get removed. The output is a persistent, evolving graph of meaning where stability is the test of agreement and entailment is the structure of inference.

This is not a transformer. There is no training phase, no offline fitting, no gradient descent. Every interaction updates the graph in place. Stability emerges from interaction history rather than from a pre-computed weight matrix. It is **conversational**, **persistent**, and **inspectable** in ways transformers are not.

---

## 2. The fact that changes the DB topology: two kernels, one linear memory

`core/pask-and-cell/src/combined.zig` is the production target. It builds a single WASM module with both kernels co-resident, sharing one `WebAssembly.Memory`:

```zig
comptime {
    _ = @import("cell_main");
    _ = @import("pask_main");
}
```

The result is one WASM file exposing both `kernel_*` (cell engine) and `pask_*` (Pask) exports against the same linear memory. **Cell IDs the cell engine writes can be passed straight into `pask_upsert_node` as a `(ptr, len)` pair without copying.** The bridge is structural, not interpretive.

Both kernels share three properties critical for the DB story:

1. **Bounded, fixed-size state.** Pask's `Store` is a single `extern struct` with fixed-size arrays (Node × `MAX_NODES`, Edge × `MAX_EDGES`, Delta ring × `MAX_DELTAS`). No heap. Snapshot-able by `@memcpy`. Mirrors the cell engine's discipline.
2. **Snapshot ABI parity.** `pask_snapshot_state` and `pask_restore_state` mirror `kernel_snapshot_state` and `kernel_restore_state`, including the magic-version-length envelope (Pask's magic is `0x4B534150` = "PASK"; the cell engine's is "CESN"). Persistence is the same shape for both.
3. **Determinism.** The kernel never reads a host clock; all timestamps arrive as `now_ms` parameters. Replays are bit-identical. Same K5-style argument as the cell engine.

These three properties mean the DB topology that serves the cell engine — LMDB hot path, SQLite browser, Pravega streams, Postgres reasoning — has to serve Pask too, with the same layered shape. There is no separate "Pask database"; there is the same four-tier topology, with Pask state slotted into each tier alongside the cell store.

---

## 3. The exact state shapes the DB has to serve

Compile-time layout asserts in `core/pask/src/main.zig` lock these:

| Type           | Size     | Composition (offsets locked at compile time)                                                   |
|----------------|----------|------------------------------------------------------------------------------------------------|
| `Node`         | 208 B    | cell_id[64] + cell_id_len + type_path[92] + type_path_len + h_state(f64) + stability(f64) + interaction_count(u32) + is_stable(u8) + is_pruned(u8) + pad + created_at(u64) + updated_at(u64) |
| `Edge`         | 40 B     | from_idx(u32) + to_idx(u32) + constraint_weight(f64) + delta_trend(f64) + interaction_count(u32) + pad + last_updated(u64) |
| `StableThread` | 32 B     | node_idx(u32) + h_state(f64) + total_constraint_strength(f64) + interaction_count(u32) + pad |
| `Config`       | 48 B     | prune_threshold + stability_epsilon + min_interactions + propagation_depth + learning_rate + stability_window_ms + stability_check_every + prune_every |

The whole `Store` is one contiguous extern struct. `MAX_NODES` and `MAX_EDGES` are config-fixed; the snapshot is `sizeof(Store)` bytes — typically a few MB for a working graph. Importantly, this puts the snapshot in **octave 1** territory (1 MB cells) by default, not octave 0. A serialised Pask graph is a single octave-1 cell.

---

## 4. Layer collapse: the Pask snapshot is a cell

Every storage tier we already designed has a clean expression for "store one large blob keyed by content hash":

- **Octave 1** is exactly this — 1 MB cells stored in `packages/content-store-local-fs` or LMDB-with-extended-values, addressable by `(typeHash, OctaveAddress)`.
- A Pask snapshot fits in one octave-1 cell when `MAX_NODES ≤ ~5000` (208 B × 5000 + 40 B × ~50 K = ~3 MB — already overflows; bump to octave 2 for production graphs).
- The snapshot's `magic + version + length` envelope is structurally identical to a continuation cell type, just at a different octave.

So the Paskian state, properly persisted, **is a cell**. The bytes that `pask_snapshot_state()` produces are a self-describing blob with an envelope that matches the cell discipline. Persisting the Pask graph is the same operation as persisting any other large-payload cell:

1. Call `pask_snapshot_state()` → get a pointer to the snapshot in linear memory.
2. Compute its SHA-256 → that's the `content_hash`.
3. Compute its `typeHash` from `(whatPath="substrate.pask.graph", howSlug="snapshot", instPath="v1")`.
4. Mint an octave-1 (or octave-2 for big graphs) pointer cell at octave 0 that points at the snapshot blob.
5. Write the snapshot to whichever tier owns its octave (LMDB octave 1, UHRP for octave 2).
6. Anchor the pointer cell's BUMP/BEEF if you want on-chain provenance for the learning state.

The cell engine can then carry the Pask graph as a versioned, hash-chained, K6-protected, SPV-anchored artifact — the same way it carries everything else. **The Paskian "I have learned this" claim becomes a cryptographically anchored cell**, not just an in-memory state.

---

## 5. Per-tier role for Pask state

### LMDB (kernel hot path)
- **Stores:** the in-flight Pask snapshot blob keyed by `(user_cert_id, snapshot_version)`. One LMDB env or one column family alongside the cell store. Snapshot writes are atomic blob swaps — LMDB's natural shape.
- **Hot read:** `pask_restore_state` from LMDB on kernel boot. mmap the snapshot, point Pask's `g_store` at it.
- **Pask-specific store:** new vtable `PaskSnapshotStore` alongside `HeaderStore`, `OutputStore`, `DerivationStateStore`. Methods: `loadCurrent`, `commitSnapshot`, `rollbackTo(version)`, `snapshotHistory(limit)`.

### SQLite (browser parity)
- **Stores:** the same snapshot blob in OPFS, one row per `(user_cert_id, snapshot_version)`. Browser tab can run Pask end-to-end against local snapshot without round-tripping to the sovereign node.
- **Sync:** browser and sovereign node converge via Pravega-streamed interaction events, not by snapshot copying — see §6 below.

### Pravega (event streams)
- **Adds a sixth stream:** `pask-interactions`. Every `pask_interact_run` call emits an event with `(primary_cell_id, related_cell_ids, effective_strength, now_ms)`. Subscribers replay the stream to reconstruct the graph state.
- **This is the critical property:** the snapshot is convenient, but the **interaction stream is canonical**. Two nodes in the same federation can disagree on snapshots (different snapshot points, different prune cycles) but they agree on the interaction stream that produced them. Pask is **deterministic** — same interactions in the same order produce bit-identical graphs.
- **Determinism + Pravega exactly-once = deterministic graph convergence** across nodes that subscribe to the same interaction stream.

### Postgres (Bert's reasoning tier)
- **New tables:**
  - `pask_node_view` — materialised view of Pask's Node array.
  - `pask_entailment` — materialised view of Pask's Edge array.
  - `pask_stable_thread` — the system's "what has been learned" surface.
- **FDW into LMDB:** `pask_snapshot_lmdb` foreign table exposes the live snapshot binary; a parser FDW decodes Node/Edge arrays in-place using the compile-time-locked offsets.
- **Bert's intent reducer queries this directly:** stable threads, entailment chains, cold concepts.

### Octave (escalation)
- Small graphs: in-memory + LMDB-backed snapshot (octave 0 pointer + octave 1 blob).
- Production user graphs: octave 2 (via UHRP) for snapshots > 1 MB.
- Federated graph audit: octave 3 for cross-user learned-thread aggregations.

---

## 6. Determinism + Pravega = federated learning convergence

Pask's `pask_interact_run` is fully deterministic — given the same `(primary_idx, kind, effective_strength, related_idx_list, now_ms)`, the kernel produces a bit-identical state transition every time.

If two nodes in a federation subscribe to the same `pask-interactions` Pravega stream, they will produce **bit-identical Pask graphs**. The graph state can be re-derived from the stream alone:

```
Cell layer:    prevStateHash chains computation steps          (Semantos K6)
Session layer: prev_close_txid chains hands/trades/handoffs    (Bert's extension)
Pask layer:    Pravega interaction stream chains learning      (this addendum)
```

What this enables:
- **Recovery without copying snapshots.** Subscribe to the stream from genesis, replay through Pask, same graph.
- **Audit.** Anyone with read access to the stream can reproduce the graph state at any point in history.
- **Cross-device convergence.** Phone, laptop, browser tab, sovereign node — same stream → same graph.
- **Selective forgetting with proof.** Pruning is a deterministic operation triggered by inbound delta trend. Replay confirms it.

---

## 7. Where Pask state belongs in the wishlist

- **Tier A7 (non-negotiable):** Pask snapshot persistence with snapshot+stream duality. Snapshot is fast-restart optimisation; stream is canonical.
- **Tier B10 (strong win):** Pask graph as a queryable Postgres surface (`pask_node_view` / `pask_entailment` / `pask_stable_thread`).
- **Tier B11 (strong win):** Recoverable teachback chain on action cells. Every cell at phase `0x06` (action) carries a 32-byte `sir_program_hash` in its payload or reserved-block field referencing the `sir_program` row that produced it. The explanation chain from any action back through the compression gradient is recoverable by hash pointer, not reconstructable by correlation. Canonically required by `compression-gradient-as-teachback.md` §"What this rules in" claim 1: *"every action has a recoverable explanation chain."* Without this backref, the teachback property holds in the gradient at compile-time but is not verifiable post-hoc from the cell store. Implemented by pipeline deliverable M5.14; checked by M5-T torture-test condition 6.
- **Tier C7 (accelerator):** Federated Pask interaction stream replication.

**Cybernetic-order annotation.** Each tier item above belongs to one cybernetic order per `cybernetic-orders.md`: A7 = 2nd-order (Pask snapshot persistence); B10 = 2nd-order (Pask graph as queryable surface); B11 = 2nd-order (teachback chain on action cells — the 2nd-order self-observation record persisted as a 1st-order storage invariant); C7 = 3rd-order (federated interaction replication). In general: Tier A items are 1st-order (storage mechanism) or 2nd-order (learning state); Tier B/C items that touch Pask or the compression gradient are 2nd-order; items that touch federation, lexicons, or governance are 3rd-order. Implementers working on 3rd-order wishlist items should read `cybernetic-orders.md` §"What this rules in" point 2 before opening code — 3rd-order changes require multi-community review because they touch the shared-vocabulary layer.

---

## 8. Implementation pipeline additions

See the tracking matrix in `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` for rows:
- **M1.11** — `LmdbPaskSnapshotStore`
- **M1.12** — Combined WASM build wiring
- **M2.8** — Browser-side `SqlitePaskSnapshotStore`
- **M3.9** — Pravega `pask-interactions` stream producer
- **M3.10** — Pravega-replay → Pask snapshot derivation tool
- **M5.11** — `pask_node_view` + `pask_entailment` + `pask_stable_thread` DDL (`db/postgres/migrations/005_pask_tables.sql`)
- **M5.12** — Helm "what's been learned" view
- **M5.13** — Bert's intent reducer integration with `pask_entailment`

Torture test: **M3-T-Pask** (`tests/torture/M3_Pask_torture.sh`).

---

## 9. The composition picture, complete

```
┌──────────────────────────────────────────────────────────────┐
│            Single WASM module (core/pask-and-cell)           │
│    Cell engine + Pask kernel sharing one linear memory       │
│                                                              │
│  Cell engine writes a cell_id into linear memory      ┐      │
│         ▼                                             │      │
│    Pask reads it directly (zero-copy)  ←──────────────┘      │
│         ▼                                                    │
│    pask_upsert_node + pask_interact_run → graph mutation     │
│         ▼                                                    │
│    pask_snapshot_state → bytes → octave-1 cell               │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
        Same four-tier DB topology, with three new slots:
        ┌─────────────────────────────────────────────┐
        │ LMDB:    PaskSnapshotStore (M1.11)          │
        │ SQLite:  SqlitePaskSnapshotStore (M2.8)     │
        │ Pravega: pask-interactions stream (M3.9-10) │
        │ Postgres: pask_node_view + entailment (M5.11+)│
        └─────────────────────────────────────────────┘
The chains compose at three levels:
  Cell:    prevStateHash       (K6, kernel-enforced)
  Session: prev_close_txid     (Bert's extension, application-level)
  Pask:    pask-interactions   (Pravega stream, kernel-deterministic)
```
