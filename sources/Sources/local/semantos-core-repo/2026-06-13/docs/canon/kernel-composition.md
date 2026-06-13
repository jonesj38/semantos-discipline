---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/kernel-composition.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.629129+00:00
---

# Kernel composition: cell engine + Pask, one linear memory

**Status:** canonical. Architectural claim about how the substrate's two WASM kernels relate to each other and to the four-tier DB topology.

**Sources:** `core/cell-engine/src/main.zig`, `core/pask/src/main.zig`, `core/pask-and-cell/src/combined.zig`, `docs/paskian-learning-system-explainer.md`, `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md`.

---

## The structural claim

> **The cell engine handles state and verification; Pask handles meaning and learning; the DB topology serves both with the same vtable discipline; Pravega's exactly-once ordering plus Pask's determinism gives federated learning convergence as a kernel-level property, not an application feature.**

This sentence is canonical. Every artifact downstream of it — the DB wishlist, the four-tier topology, the implementation pipeline, Bert's reasoning-tier schema, the Helm read-views — derives from this division of concern.

---

## What the sentence asserts

**The cell engine handles state and verification.** Cells, capability tokens, identity certs, edges, hash chains, K1–K7 enforcement. Bytes-in, bytes-out, byte-identical across profiles. The cell carries its own proof (continuation cells 0x01 BUMP, 0x02 atomic-BEEF, 0x03 envelope). The engine is the trusted-by-construction verifier. State transitions are deterministic, bounded, and auditable.

**Pask handles meaning and learning.** Conversational learning per Gordon Pask (1976). Every concept is a Node keyed by `cell_id`; every relationship is an Edge with `constraint_weight` and `delta_trend`; stable threads emerge from local coherence over enough interactions; pruning removes concepts whose neighbourhood has gone cold. The graph is the system's persistent, evolving record of what has been learned. The kernel is bounded (fixed-size arrays, no heap), deterministic (no host clock; all timestamps are caller-supplied), and snapshot-able (`@memcpy` of the `Store` extern struct).

**The DB topology serves both with the same vtable discipline.** Every `runtime/semantos-brain/src/*_store_fs.zig` declares a vtable interface (`HeaderStore`, `OutputStore`, `DerivationStateStore`, etc.) with three planned backings (`Local`, `Plexus`, `FederatedSemantos`). Pask gets its own member of that family — `PaskSnapshotStore` — sized for the Pask `Store` blob. LMDB owns the sovereign-node hot path; SQLite-WASM-OPFS owns the browser; UHRP owns octave 2+ blobs; Postgres exposes the read views. The same four engines, the same vtable contract, no kernel-specific persistence path.

**Pravega's exactly-once ordering plus Pask's determinism gives federated learning convergence as a kernel-level property.** Two federated nodes that subscribe to the same `pask-interactions` Pravega stream produce **bit-identical Pask graphs**, regardless of snapshot timing or commit cadence. The snapshot is a fast-restart optimisation; the stream is canonical. This is K6-style append-only chain integrity at the learning layer — joining the cell `prevStateHash` chain (Semantos K6) and the session `prev_close_txid` chain (Bert's extension) as the third hash chain in K9's temporal-morphism stack. Cross-device convergence, federated audit, and "reinstall from genesis" recovery all fall out as direct consequences. **This is what the previous DB design docs missed:** federated learning consistency is not an application feature to bolt on; it is a property of two deterministic kernels reading from the same exactly-once stream.

---

## What this rules out

This canonical claim rules out a class of design moves that would otherwise look attractive:

1. **No "Pask service" running outside the kernel.** Pask is not a separate microservice or a cloud-side learning pipeline. It is a co-resident WASM kernel sharing linear memory with the cell engine. If a future deliverable proposes "Pask-as-a-service," it violates this canon and requires a design note.

2. **No host-clock dependence in Pask.** Same K5-style termination argument as the cell engine: the kernel never reads a host clock. Any Pask deliverable that introduces non-deterministic timing breaks federated convergence and must be rejected.

3. **No bespoke Pask persistence.** Pask snapshot persistence goes through the same `PaskSnapshotStore` vtable as every other store. No "Pask uses a different storage system because it's a learning kernel" exception.

4. **No application-side reimplementation of stable-thread detection.** The kernel's `pask_stable_threads_into` export is the canonical surface. Postgres queries it via FDW; Helm reads materialised views off it; Bert's intent reducer joins against it. Reimplementing stability detection at the application layer creates a divergence risk.

5. **No "approximate determinism."** Pask's compile-time-locked struct offsets (`@compileError("Node size drift")`, `@compileError("Edge offset drift")`, etc.) are non-negotiable. Drift between the Zig kernel and the TypeScript bindings = silent corruption. Layout changes go through a coordinated multi-kernel update, not unilateral edits.

---

## What this rules in

The same canonical claim makes a small set of design moves natural and load-bearing:

1. **The Pask snapshot can be a cell.** The snapshot blob fits in an octave-1 (or octave-2) cell. `pask_snapshot_state` produces self-describing bytes; mint a pointer cell at octave 0 pointing at the snapshot blob; persist via the existing octave escalation path. Pask state becomes K6-protected, BUMP/BEEF-anchorable, hash-chained — the same way every other large artifact is. Full layer collapse: cell engine, Pask kernel, and storage tier all speak the same physical bytes.

2. **`cell_id` is the bridge.** Every Pask Node is keyed by a `cell_id` — the same byte string the cell engine uses for content addressing. Cells minted by the cell engine are the entities the Pask kernel learns about. There is no separate "agent ID" or "concept ID" namespace; the cell IS the concept.

3. **Bert's reasoning tier queries Pask state.** `pask_node_view`, `pask_entailment`, `pask_stable_thread` are first-class Postgres tables. The intent reducer's job becomes "given the user's current stable threads and the entailment graph from them, compose an SIR program that respects what the user has already learned." Without Pask in the picture, the reasoning tier reasons over cells without knowing which cells matter to the user right now.

4. **Federated learning is opt-in via Pravega subscription topology.** A user's Pask kernel subscribes to a stream they trust. They don't replay other users' interactions by default; they replay their own. If they want cross-user learning, they subscribe to the appropriate federation stream — same shape as subscribing to the region tick stream or the identity event stream. Privacy is per-subscription, not per-application-feature.

---

## Where this sits relative to existing canon

This file does not supersede any existing K-theorem in `theorems.yml`; it asserts an architectural composition that the K-theorems together permit but no single K-theorem states. It is a peer of `sovereignty-cell-signing.md` — a focused architectural claim, not a kernel invariant.

The unification matrix (`unification-matrix.yml`) currently lists U1 (cell engine) but does not list Pask as a substrate component. A future stage-1 update SHOULD add a U-row for Pask, aligning with the per-axis status format the existing rows use. Until then, this file is the canonical reference for Pask's architectural status.

---

## Cross-references

- `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md` — the full DB-tier integration: per-tier roles, the seven new pipeline deliverables (M1.11, M1.12, M2.8, M3.9, M3.10, M5.11, M5.12, M5.13), and the M3-T-Pask determinism torture test.
- `docs/paskian-learning-system-explainer.md` — Conversation Theory grounding and the algorithm in plain language.
- `docs/textbook/19-hash-chains-as-time.md` — the four-chain time model that this addendum extends with a fifth (session) and sixth (Pask interaction) chain.
- `core/pask-and-cell/src/combined.zig` — the 17-line file that builds both kernels into one WASM module.
