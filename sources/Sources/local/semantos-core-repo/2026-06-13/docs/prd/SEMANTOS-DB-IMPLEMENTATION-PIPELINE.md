---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.693529+00:00
---

# Semantos DB — Implementation Pipeline

**Status:** plan only. Hand-off artifact for a Claude Code session driving the multi-tier DB integration. Do not implement from this document directly; it is the brief for the implementer.

**Companion docs (read these first):**
- `docs/canon/SEMANTOS-DB-WISHLIST.md` — capability requirements (Tier A/B/C).
- `docs/canon/SEMANTOS-DB-MULTI-TIER-TOPOLOGY.md` — per-engine roles (LMDB / Pravega / Postgres / SQLite).
- `docs/canon/SEMANTOS-DB-OCTAVE-ADDENDUM.md` — per-octave storage shapes.
- `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md` — second-kernel (Pask) integration; defines M1.11–12, M2.8, M3.9–10, M5.11–13 and the determinism + Pravega-replay convergence property.
- `docs/canon/REVIEW-bert-van-brakel-extensions.md` — context on Bert's session-trust extension proposal.
- `docs/paskian-learning-system-explainer.md` — Conversation Theory grounding for the Pask kernel.
- `docs/textbook/07-cells-types-linearity.md`, `11-2pda-cell-engine.md`, `14-verifier-sidecar.md`, `19-hash-chains-as-time.md` — kernel/engine reference.
- `core/cell-engine/src/{cell,header_store,output_store,derivation_state,octave,pointer,local_chain_tracker}.zig` — current cell-engine implementation.
- `core/pask/src/{main,types,store,propagation,stability,pruner,config}.zig` — current Pask-kernel implementation.
- `core/pask-and-cell/src/combined.zig` — the production target: both kernels co-resident, sharing one linear memory.
- `runtime/semantos-brain/src/*_store_fs.zig` — current Local backings (the things being superseded).

**Scope:** ship a four-tier DB topology (LMDB hot path / SQLite browser / Pravega streams / Postgres reasoning) over ~6 months, slotting in behind the existing vtable pattern in `*_store_fs.zig`. Out of scope (tracked, not delivered): NVMe computational storage, multi-engine kernel diversity, Bert's BFT committee model, federated octave-3.

---

## 0. Reading order for a Claude Code agent

1. Read this document end-to-end before opening any code.
2. Read the four companion docs above.
3. Read the textbook chapters referenced.
4. Read the current `*_store_fs.zig` files to understand the vtable contract.
5. Pick up a deliverable from the tracking matrix (§3) by ID. Confirm dependencies are met (§3 column "Depends on"). Confirm an agent slot is open in the wave (§4).
6. Author tests before code (§5 TDD discipline).
7. Land the deliverable. Mark it complete in the matrix. Run the milestone torture test (§6) when the milestone's deliverables are all green.

---

## 1. Architectural invariants the implementation MUST preserve

These are non-negotiable. Any deliverable that breaks one is rejected.

| Invariant                                      | Source                                       | Why it matters                                                       |
|------------------------------------------------|----------------------------------------------|----------------------------------------------------------------------|
| 1024-byte cell shape (256 hdr + 768 payload)   | Wishlist §0; `core/cell-engine/src/cell.zig` | Page geometry, K5 termination argument                              |
| K1 linearity                                   | `proofs/lean/Semantos/Theorems/LinearityK1.lean` | LINEAR cell consumed exactly once                                |
| K3 domain isolation                            | `DomainIsolationK3.lean`                     | `OP_CHECKDOMAINFLAG` is total + correct                              |
| K4 failure atomicity                           | `FailureAtomicK4.lean`                       | Failed scripts leave PDA byte-for-byte unchanged                     |
| K5 termination                                 | `TerminationK5.lean`                         | Bounded opcount; no DB-side compute the kernel must model            |
| K6 hash-chain integrity (append-only)          | TLA+ `ReplayPrevention.tla`                  | `prevStateHash` chain is append-only across all four chain scopes    |
| K7 cell immutability                           | `CellImmutabilityK7.lean`                    | 256-byte header read-only after pack                                 |
| Cell carries its own proof                     | Wishlist §0b                                 | DB is not the verifier; trust gradient is per-cell composition       |
| LMDB is dumb storage                           | Topology §1.5, §4                            | No storage-side compute; kernel reads bytes only                     |
| Embedded WASM ≤ 50 KB (target ~29 KB) — cell engine alone | `core/cell-engine/build.zig`      | Phone / esp32 viability                                              |
| Combined `pask-and-cell` WASM ≤ 200 KB full, ≤ 80 KB embedded | `core/pask-and-cell/build.zig` | Production target; cell engine + Pask kernel share one linear memory |
| Pask determinism (no host clock, replay = bit-identical) | `core/pask/src/main.zig`           | Pravega-replay graph convergence; cross-device + federated consistency |
| Pask snapshot/Store layout offsets (compile-time asserted) | `core/pask/src/main.zig` §asserts | TS bindings hand-roll offsets; drift = silent corruption             |
| Existing vtable contract                       | `runtime/semantos-brain/src/*_store_fs.zig`             | Engine-agnostic; new backings slot in without kernel changes         |
| **Kernel composition** (cell engine + Pask, one linear memory) | `docs/canon/kernel-composition.md` | Cell engine handles state and verification; Pask handles meaning and learning; the DB topology serves both with the same vtable discipline; no "Pask database" separate from the four-tier topology |
| **MNCA-as-Pask-federation** (federation is 3rd-order MNCA-shape) | `docs/canon/mnca-as-pask-federation.md` | Federation is a 3rd-order structure built from 2nd-order Pask primitives; existing DB primitives (Pravega exactly-once + Pask determinism) are sufficient for MNCA convergence; do not collapse federation into application logic |
| **Three-order cybernetic layering** (1st = cell engine, 2nd = Pask + gradient, 3rd = federation + lexicons + governance) | `docs/canon/cybernetic-orders.md` | Every deliverable belongs to one order; collapsing the orders is a design error; 1st-order deliverables do not require Pask review; 3rd-order deliverables (governance domain shape, extension manifest schema, lexicon structure) require multi-community review |
| **Compression gradient = teachback** (no action without the gradient) | `docs/canon/compression-gradient-as-teachback.md` | No surface bypasses SIR; no runtime SIR interpretation; no best-effort lowering; every action-phase cell (`phase = 0x06`) must carry a recoverable explanation chain back to its SIR program — see wishlist B11 and deliverable M5.14 |

If a deliverable requires loosening any of these, **stop and write a design note**; do not weaken the invariant unilaterally.

---

## 2. Milestones (M0 → M7)

Each milestone is a coherent shippable slice. Milestones are sequential at the gate level (M2 cannot ship before M1's torture test passes), but deliverables within a milestone are mostly parallel.

### M0 — Baseline (already done)

**State now.** All `*_store_fs.zig` Local backings operational with JSONL or atomic-rewrite-binary persistence. Kernel + verifier sidecar + identity DAG functional. Phase 6 octave memory complete (D6.1–D6.7 merged). Existing test suite green.

**Acceptance:** test suite green at `HEAD`. No deliverables.

---

### M1 — LMDB Hot Path (Octave 0)

**Goal:** every kernel-hot-path `*_store_fs.zig` has an LMDB backing alongside the current FS backing, behind the same vtable. Kernel reads continue to work; the only change is the bytes-on-disk shape and the access pattern (mmap'd KV instead of in-memory + JSONL replay).

**Deliverables:** see §3 matrix rows M1.1–M1.10.

**Exit gate:** §6 torture test M1-T passes.

**Estimated effort:** ~6–8 weeks with 2–3 parallel agents.

---

### M2 — SQLite Browser Tier

**Goal:** browser side has a SQLite-WASM-OPFS-backed `Local…Store` set matching the sovereign-node LMDB stores in shape. World-Client app (`apps/world-client`, `apps/loom-svelte`, `apps/oddjobz-mobile`) can run the cell engine end-to-end against local SQLite without round-tripping to the sovereign node for routine reads.

**Deliverables:** see §3 matrix rows M2.1–M2.7.

**Exit gate:** §6 torture test M2-T passes.

**Estimated effort:** ~3–5 weeks with 1–2 parallel agents. Can run in parallel with M1 because the vtable is shared.

---

### M3 — Pravega Streaming

**Goal:** Pravega replaces the current PubSub / Phoenix-Channels stub for the five canonical event streams. Adapters subscribe per the boot-sequence step-12 contract.

**Deliverables:** see §3 matrix rows M3.1–M3.8.

**Exit gate:** §6 torture test M3-T passes.

**Estimated effort:** ~6–8 weeks. Can run in parallel with M1 + M2 because the streams are produced from kernel commits but the storage tier is independent.

---

### M4 — Octave 1+ Escalation

**Goal:** `OP_DEREF_POINTER` (0xC8) escalates to octave 1 via `content-store-local-fs` and to octave 2 via `content-store-uhrp-http`. MFP metering fires on every billable octave-1+ fetch.

**Deliverables:** see §3 matrix rows M4.1–M4.6.

**Exit gate:** §6 torture test M4-T passes.

**Estimated effort:** ~3–4 weeks. Depends on M1 (LMDB octave-0 stable) but is otherwise independent.

---

### M5 — Postgres Reasoning Tier

**Goal:** Bert's intent-reducer Postgres tier deployed with the registry as source of truth. FDWs into LMDB, Pravega, and SQLite. First end-to-end intent → cell pipeline running.

**Deliverables:** see §3 matrix rows M5.1–M5.10.

**Exit gate:** §6 torture test M5-T passes.

**Estimated effort:** ~10–12 weeks (this is the largest milestone and Bert's primary work). Coordinated with Bert; depends on M1 + M3 for FDW targets.

---

### M6 — Octave Registry Source of Truth

**Goal:** the dual-addressed registry (Wishlist Tier A6) is live with Postgres source-of-truth, LMDB cache, Pravega change feed, SQLite browser mirror.

**Deliverables:** see §3 matrix rows M6.1–M6.5.

**Exit gate:** §6 torture test M6-T passes.

**Estimated effort:** ~4–6 weeks. Depends on M1 + M3 + M5.

---

### M7 — Federated Tier (Octave 3)

**Goal:** `FederatedSemantos…Store` bindings ship; octave-3 fetches route across federation peers.

**Deliverables:** see §3 matrix rows M7.1–M7.5.

**Exit gate:** §6 torture test M7-T passes.

**Estimated effort:** ~6–8 weeks. Depends on M1–M6.

---

### Out of scope (tracked, not delivered)

- **M8 (future):** NVMe Computational Storage spike.
- **M9 (future):** Multi-engine kernel diversity (run Zig kernel + a second-language kernel in parallel; disagreement is a bug signal).
- **M10 (future):** Bert's BFT committee + equivocation slashing protocol.

These are documented in `REVIEW-bert-van-brakel-extensions.md` and `SEMANTOS-DB-WISHLIST.md` Tier B5; do not start them as part of this pipeline.

---

## 3. Tracking matrix

Each row is one shippable deliverable. Status field = `pending | in_progress | review | merged | blocked`. Owners filled in at agent assignment time.

### M1 — LMDB Hot Path

| ID    | Deliverable                                                  | Tier | Depends on                       | Owner | Status   | Acceptance                                                                                                  |
|-------|--------------------------------------------------------------|------|----------------------------------|-------|----------|--------------------------------------------------------------------------------------------------------------|
| M1.1  | LMDB Zig binding selection + vendoring                       | A    | —                                | Claude | merged | System liblmdb via C FFI; `runtime/semantos-brain/src/lmdb/lmdb.zig`; 6 smoke tests green (`zig build test-lmdb`) |
| M1.2  | `LmdbHeaderStore` — `HeaderStore` vtable impl                | A    | M1.1                             | Claude | merged | `header_store_lmdb.zig`; 6 conformance tests green incl. reorg-rollback (heights 0–9 → rollback → 0–4 survive) |
| M1.3  | `LmdbOutputStore` — `OutputStore` vtable impl                | A    | M1.1                             | Claude | merged | `output_store_lmdb.zig`; 6 conformance tests green; mark-spent atomicity verified |
| M1.4  | `LmdbDerivationStateStore` — `DerivationStateStore` vtable   | A    | M1.1                             | Claude | merged | `derivation_state_store_lmdb.zig`; 5 conformance tests green; ceiling enforcement across txn boundaries |
| M1.5  | `LmdbCellStore` — new vtable for raw cells                   | A    | M1.1                             | Claude | merged | `cell_store.zig` vtable + `cell_store_lmdb.zig`; 5 conformance tests green; 4 KiB alignment verified |
| M1.6  | Composite-cell write (cell 0 + BUMP + BEEF + envelope)       | A    | M1.5                             |       | merged   | Multi-cell write atomic; partial-write rollback tested                                                       |
| M1.7  | LMDB integration in `runtime/semantos-brain/src/main.zig`               | A    | M1.2, M1.3, M1.4, M1.5           |       | merged   | `brain` boots with LMDB backings selected by config; existing fs backing remains as fallback                  |
| M1.8  | Migration tool: JSONL → LMDB                                 | A    | M1.2, M1.3, M1.4                 |       | merged   | All current production JSONL files import cleanly; idempotent re-run                                         |
| M1.9  | LMDB env tuning + safety knobs                               | A    | M1.7                             |       | merged   | `MDB_NOSYNC`/`MDB_NOMETASYNC` choice documented; crash-recovery tested                                       |
| M1.10 | Cursor host-import bindings (`hostDbOpenCursor`, etc.)       | A    | M1.5                             |       | merged   | WASM kernel can stream cells via cursor; peak heap bounded at one cell                                       |
| M1.11 | `LmdbPaskSnapshotStore` — `PaskSnapshotStore` vtable impl    | A    | M1.1                             | Claude | merged | `pask_snapshot_store_lmdb.zig`; 6 conformance tests green; atomic commit + PASK-magic validation; rollbackTo; O(1) loadCurrent; two-user isolation |
| M1.12 | Pask + cell-engine combined WASM build wiring                | A    | M1.10, M1.11                     |       | merged   | `core/pask-and-cell/zig-out/bin/pask-and-cell.wasm` ships as the production kernel; both `kernel_*` and `pask_*` exports active; binary size ≤ 80 KB embedded / ≤ 200 KB full |

### M2 — SQLite Browser Tier

| ID    | Deliverable                                                  | Tier | Depends on        | Owner | Status   | Acceptance                                                                                                |
|-------|--------------------------------------------------------------|------|-------------------|-------|----------|------------------------------------------------------------------------------------------------------------|
| M2.1  | SQLite-WASM-OPFS bring-up in `apps/world-client`             | A    | —                 | Claude | merged | `SqliteOpfsDb` in `sqlite-opfs.ts`; OPFS + memory fallback; 6 tests green (`vitest run`)               |
| M2.2  | Browser-side `SqliteHeaderStore`                             | A    | M2.1              | Claude | merged | `sqlite-header-store.ts`; 11 vitest tests green incl. reorg-rollback + prev_hash continuity |
| M2.3  | Browser-side `SqliteOutputStore`                             | A    | M2.1              | Claude | merged | `sqlite-output-store.ts`; 11 vitest tests green; markSpent uses BEGIN IMMEDIATE for atomicity |
| M2.4  | Browser-side `SqliteDerivationStateStore`                    | A    | M2.1              | Claude | merged | `sqlite-derivation-state-store.ts`; 9 vitest tests green; ceiling_exceeded enforced pre-issue |
| M2.5  | Audit-log table (BRC-100 envelope history)                   | B    | M2.1              |       | merged   | Append-only; nonce-replay cache enforces uniqueness with TTL                                                 |
| M2.6  | Recovery-payload `ATTACH DATABASE` per domain flag           | C    | M2.1              |       | merged   | One `.sqlite` file per governance domain; detach/encrypt/re-attach round-trip tested                        |
| M2.7  | World-Client cell-engine WASM integration                    | A    | M2.2, M2.3, M2.4  |       | merged   | Browser kernel verifies a T0 composite end-to-end without sovereign-node round-trip                         |
| M2.8  | Browser-side `SqlitePaskSnapshotStore`                       | A    | M2.1, M1.11       |       | merged   | Same vtable shape as `LmdbPaskSnapshotStore`; OPFS-backed; browser tab can load snapshot + run `pask_interact_run` end-to-end |

### M3 — Pravega Streaming

| ID    | Deliverable                                                          | Tier | Depends on   | Owner | Status   | Acceptance                                                                                          |
|-------|----------------------------------------------------------------------|------|--------------|-------|----------|------------------------------------------------------------------------------------------------------|
| M3.1  | Pravega single-node dev cluster                                      | B    | —            | Claude | review | `infra/pravega/docker-compose.yml` + `tests/smoke_test.sh`; needs docker pull to validate        |
| M3.2  | Pravega host-side client (Zig FFI to Java/Go gateway, or native)     | B    | M3.1         |       | merged   | `brain` writes one event to a Pravega stream; reads it back                                            |
| M3.3  | Region tick stream producer (20 Hz)                                  | B    | M3.2         |       | merged   | World Host emits a tick event per region per 50 ms; tick carries Merkle root                          |
| M3.4  | Identity event stream producer                                       | B    | M3.2         |       | merged   | Cert mint / edge / revoke events stream; ordering preserved                                          |
| M3.5  | Capability UTXO change feed producer                                 | B    | M3.2         |       | merged   | UTXO mint / spend / reorg events stream; per-domain-flag partitioning                                |
| M3.6  | MFP HMAC tick stream producer                                        | B    | M3.2         |       | merged   | Per-channel ticks streamed with HMAC + nSequence                                                      |
| M3.7  | Adapter-side subscriber replacing PubSub stub                        | B    | M3.3–M3.6    |       | merged   | One adapter subscribes to all four streams; replays from snapshot correctly                          |
| M3.8  | Snapshot + replay-from-tick semantics                                | B    | M3.7         |       | merged   | Adapter restart resumes from last-acked tick; no event loss; no duplicate processing                 |
| M3.9  | Pravega `pask-interactions` stream producer                          | B    | M3.2, M1.12  |       | merged   | every `pask_interact_run` call emits a Pravega event with `(primary_cell_id, related_cell_ids, effective_strength, now_ms)`; ordering preserved per user_cert_id |
| M3.10 | Pravega-replay → Pask snapshot derivation tool                       | B    | M3.9, M1.11  |       | merged   | given a stream from genesis, produce a current snapshot; result byte-identical to live `pask_snapshot_state` under load (determinism check) |

### M4 — Octave 1+ Escalation

| ID    | Deliverable                                                  | Tier | Depends on             | Owner | Status   | Acceptance                                                                                       |
|-------|--------------------------------------------------------------|------|------------------------|-------|----------|---------------------------------------------------------------------------------------------------|
| M4.1  | `host_fetch_cell` octave-1 backing via `content-store-local-fs` | A    | M1                     |       | merged   | `OP_DEREF_POINTER` to octave-1 cell returns a 1024-byte window from a 1 MB slot file              |
| M4.2  | `host_fetch_cell` octave-2 backing via `content-store-uhrp-http` | A    | M4.1                   |       | merged   | `OP_DEREF_POINTER` to octave-2 cell returns a 1024-byte window via HTTP range                    |
| M4.3  | MFP metering tick on octave-1+ fetches                       | B    | M3.6, M4.1             |       | merged   | Every octave-1+ fetch emits an MFP tick; budget exhaustion rejects the fetch                      |
| M4.4  | Pointer cell pack/unpack TS parity (D6.3 deferred work)      | A    | —                      |       | merged   | TS pointer cell bytes equal Zig pointer cell bytes byte-for-byte                                  |
| M4.5  | `storeWithEscalation` (D6.6 deferred work)                   | A    | M4.1                   |       | merged   | 500-byte object → octave 0; 2 MB object → octave 1 + pointer cell; 2 GB object → octave 2 + pointer |
| M4.6  | In-memory CellRegistry CAS+location dual addressing (D6.6)   | A    | M4.5                   |       | merged   | Lookup by typeHash returns same cell as lookup by OctaveAddress                                    |

### M5 — Postgres Reasoning Tier

| ID    | Deliverable                                                  | Tier | Depends on             | Owner | Status   | Acceptance                                                                                                  |
|-------|--------------------------------------------------------------|------|------------------------|-------|----------|--------------------------------------------------------------------------------------------------------------|
| M5.1  | Postgres schema: `cert_dag`, `intent`, `intent_edge`         | A    | —                      | Claude | merged | `db/postgres/migrations/001_cert_dag.sql`; tests green `test_cert_dag.sql`                              |
| M5.2  | Postgres schema: `lexicon_category`, `taxonomy_index`        | B    | M5.1                   | Claude | merged | `002_lexicon_category.sql`; GIN index + uniqueness verified; `proof_status TEXT NOT NULL CHECK (proof_status IN ('proven', 'partial', 'unverified'))` and `lean_ref TEXT` columns present; SIR composition layer (`lowerSIR`) rejects composition against an `unverified` lexicon at the lower-pass gate; tests green |
| M5.3  | Postgres schema: `sir_program`, `host_reputation`            | B    | M5.1                   | Claude | merged | `003_sir_program.sql`; validate_sir_json trigger verified; tests green                                  |
| M5.4  | Postgres schema: `session_chain`, `equivocation_evidence`    | B    | M5.1                   | Claude | merged | `004_session_chain.sql`; K6 trigger + recursive walk verified; tests green                              |
| M5.5  | FDW: `cells_lmdb` foreign table                              | B    | M1, M5.1               |       | merged   | `SELECT cell_bytes FROM cells_lmdb WHERE type_hash = $1` returns the 1024-byte cell                          |
| M5.6  | FDW: `region_ticks_pravega` foreign table                    | B    | M3.3, M5.1             |       | merged   | Pravega segment readable as a Postgres relation; tick number ordering preserved                             |
| M5.7  | FDW: `signed_bundle_audit_sqlite` foreign table              | B    | M2.5, M5.1             |       | merged   | Browser-side audit rows queryable from Postgres                                                              |
| M5.8  | Helm read-view materialised views (one per the 15 contexts)  | B    | M5.5, M5.6, M5.7       |       | merged   | Each view refresh < 1 s on representative dataset                                                            |
| M5.9  | `cert_dag` populator from `identity_certs.zig` log replay    | A    | M5.1                   |       | merged   | Replays the existing identity-certs log into `cert_dag` rows; idempotent                                    |
| M5.10 | Bert's intent reducer integration (Bert-owned)               | B    | M5.1, M5.5             |       | pending  | One end-to-end pipeline: incoming intent → reducer → SIR → OIR → bytecode → cell into LMDB → audit → Pravega |
| M5.11 | `pask_node_view` + `pask_entailment` + `pask_stable_thread` tables | B | M1.11, M5.1            | Claude | merged  | `005_pask_tables.sql` + `011_pask_fdw_plumbing.sql`; 12 tests green; refresh functions + soft-prune |
| M5.12 | Helm "what's been learned" view                              | B    | M5.11                  |       | merged   | Helm context surfaces current stable threads with descending `h_state`; refresh < 1 s; pruned nodes excluded |
| M5.13 | Bert's intent reducer integration with `pask_entailment`     | B    | M5.10, M5.11           |       | pending  | Intent reducer queries entailment graph to compose SIR programs; one end-to-end pipeline using stable threads as context |
| M5.14 | Action-cell teachback backref: `sir_program_hash` in phase-`0x06` payload | B | M5.3 | | merged  | Every action-phase cell carries a 32-byte `sir_program_hash` field (payload or reserved-block); for every such cell in the LMDB store a corresponding `sir_program` row is reachable by that hash; M5-T condition 6 verifies this exhaustively; implements wishlist B11 |

### M6 — Octave Registry Source of Truth

| ID    | Deliverable                                                       | Tier | Depends on                  | Owner | Status   | Acceptance                                                                                          |
|-------|-------------------------------------------------------------------|------|-----------------------------|-------|----------|------------------------------------------------------------------------------------------------------|
| M6.1  | Postgres `octave_registry` table (source of truth)                | A    | M5.1                        |       | merged   | DDL applies; CHECK constraints enforce K1/K7 (linearity + state consistency)                         |
| M6.2  | LMDB-side registry cache                                          | A    | M1, M6.1                    |       | merged   | Cache populated via Pravega change feed; stale-cache detection                                       |
| M6.3  | Pravega "registry-change" event stream                            | A    | M3.7, M6.1                  |       | merged   | Every registry mutation emits a Pravega event; consumers pick it up < 100 ms                         |
| M6.4  | SQLite browser-side registry mirror                               | A    | M2, M6.3                    |       | merged   | Browser registry stays in sync; can verify pointer-cell escalation locally                           |
| M6.5  | Drift-detection job (registry vs LMDB content_hash)               | A    | M6.2                        |       | merged   | Periodic walk reports any divergence; auto-quarantines suspect rows                                  |

### M7 — Federated Tier (Octave 3)

| ID    | Deliverable                                                     | Tier | Depends on             | Owner | Status   | Acceptance                                                                                          |
|-------|-----------------------------------------------------------------|------|------------------------|-------|----------|------------------------------------------------------------------------------------------------------|
| M7.1  | Slot-to-peer routing function                                   | C    | M6.1                   |       | merged   | `slot_to_peer(slot) → peer_id` deterministic; peer churn rebalances slot ownership                    |
| M7.2  | `FederatedSemantosOutputStore` vtable impl                      | C    | M1.3, M7.1             |       | merged   | UTXO writes replicate to peer; reads route correctly                                                  |
| M7.3  | `FederatedSemantosHeaderStore` vtable impl                      | C    | M1.2, M7.1             |       | merged   | Headers replicate; reorg-rollback distributes to peers                                                |
| M7.4  | `FederatedSemantosStateStore` vtable impl                       | C    | M1.4, M7.1             |       | merged   | Derivation-state ceiling enforcement across peers                                                    |
| M7.5  | Federation reputation + peer onboarding flow                    | C    | M7.1                   |       | merged   | New peer can join; reputation accrues; bad peer evicted                                              |

---

## 4. Agent deployment schedule

Three concurrency levels, each respecting the dependency graph in §3.

### Wave 1 — parallel kickoff (week 0–2)

These start simultaneously; no internal dependencies.

| Agent slot | Deliverable IDs            | Working area                                      |
|------------|----------------------------|---------------------------------------------------|
| Agent A    | M1.1                       | `core/cell-engine/build.zig`, vendor LMDB binding |
| Agent B    | M2.1                       | `apps/world-client`, `apps/loom-svelte`           |
| Agent C    | M3.1                       | `infra/pravega/` (new), `docker-compose.yml`     |
| Agent D    | M5.1, M5.2, M5.3, M5.4     | `db/postgres/migrations/` (new)                  |

Wave 1 exit: M1.1 + M2.1 + M3.1 + M5.1 all green. Schema review with Bert for M5.x.

### Wave 2 — parallel core build (week 2–8)

| Agent slot | Deliverable IDs                                  | Notes                                                  |
|------------|--------------------------------------------------|--------------------------------------------------------|
| Agent A    | M1.2 → M1.3 → M1.4 → M1.5 (sequential within A)  | One LMDB store at a time per agent; 4 stores → 4 weeks |
| Agent A2   | M1.5 → M1.6 → M1.10 (cell store + cursor)        | Parallel with Agent A if a second Zig agent is available |
| Agent B    | M2.2 → M2.3 → M2.4 (sequential)                  | Browser stores; same shape as A but TypeScript        |
| Agent C    | M3.2 → M3.3 → M3.4 → M3.5 → M3.6                 | Pravega producers; can fan out to two agents after M3.2 |
| Agent D    | M5.5 (FDW into LMDB) — depends on Agent A's M1.5  | Starts as soon as M1.5 lands                          |
| Agent E    | M5.9 (cert_dag populator)                        | Independent; reads existing log files                 |

Wave 2 exit: all M1.x except M1.7-9 done; all M2.x except M2.7 done; all M3.x except M3.7-8 done; M5.1-5 done.

### Wave 3 — integration (week 8–14)

| Agent slot | Deliverable IDs                                  | Notes                                                            |
|------------|--------------------------------------------------|-------------------------------------------------------------------|
| Agent A    | M1.7 → M1.8 → M1.9                               | Brain integration + migration + tuning. Sequential (each gates next). |
| Agent A2   | M4.1 → M4.2 → M4.3                               | Octave 1+ escalation. Depends on M1 done.                          |
| Agent B    | M2.5 → M2.6 → M2.7                               | Audit log + recovery + cell-engine browser integration.           |
| Agent C    | M3.7 → M3.8                                      | Adapter subscriber + replay semantics.                             |
| Agent D    | M5.6 → M5.7 → M5.8 → M5.10                       | Remaining FDWs + Helm views + Bert integration.                   |

Wave 3 exit: M1, M2, M3, M4 milestones torture-tested green. M5 mostly done.

### Wave 4 — registry + federation (week 14–24)

| Agent slot | Deliverable IDs                                  | Notes                                                          |
|------------|--------------------------------------------------|-----------------------------------------------------------------|
| Agent A    | M6.1 → M6.2 → M6.3 → M6.4 → M6.5                 | Registry + cache + change feed + mirror + drift detection.      |
| Agent B    | M7.1 → M7.2 → M7.3 → M7.4 → M7.5                 | Federation. Sequential.                                         |
| Agent D    | M5 cleanup + Helm integration                    | Tail-end Postgres polish.                                       |

Wave 4 exit: full pipeline green; all torture tests pass.

### Agent specialization

- **Zig agents (A, A2):** familiar with `core/cell-engine/`, vtable pattern, K-invariant tests, `*_store_fs.zig` shape. Read kernel chapters first.
- **TypeScript agents (B):** familiar with `apps/world-client`, SQLite-WASM, OPFS, the WASM kernel host imports (`core/cell-ops/src/wasm/`).
- **Infra agents (C):** Docker, Pravega, JVM/Go for the Pravega gateway. Lighter on Semantos canon; heavier on systems integration.
- **Postgres agents (D):** PL/pgSQL, FDW (`postgres_fdw`, `multicorn` for Pravega), schema design. Coordinates with Bert.
- **Bert (external):** owns M5.10 and provides schema review for M5.1–4. Independent agent, not a Cowork agent.

### Parallelization rules

1. **Two agents must not both write to the same `*_store_fs.zig`** — one store per agent at a time. The vtable conformance test suite is the gate.
2. **Schema migrations are append-only** — never two agents on the same migration file. Numbered serially: `001_cert_dag.sql`, `002_intent.sql`, ...
3. **Pravega stream definitions are owned by one agent at a time** — schema files in `infra/pravega/schemas/`.
4. **Cross-tier work (FDW, registry) requires both upstream tiers green** — agent must verify dependencies in §3 before claiming.
5. **An agent that breaks an invariant from §1 stops, opens a design note, requests review**. No silent invariant erosion.

---

## 5. TDD discipline

Every deliverable lands with tests written **before** the implementation. The matrix's "Acceptance" column is the integration target; the unit-test set listed below is the per-deliverable obligation.

### 5.1 Per-store test obligations (applies to M1.2–M1.5, M2.2–M2.4, M7.2–M7.4)

Every store backing MUST pass:

1. **Vtable conformance** — exact same behaviour as the existing `Local…Store` for every method. Reuse the existing test suite verbatim where possible.
2. **1024-byte alignment property test** — random input cells; assert every stored cell is exactly 1024 bytes; assert page boundaries never split a cell.
3. **K6 append-only property** — attempt to overwrite an existing key with different bytes; assert error.
4. **K7 cell-immutability property** — attempt to mutate header bytes (offsets 0–255) of a stored cell; assert error.
5. **Cursor-streaming peak-memory property** — open cursor over 100K cells; assert peak heap < 4 KiB during traversal (kernel sees one cell at a time).
6. **Reorg/rollback property** — for header store: `rollback_from(height)` on a 1000-deep chain; assert all rows ≥ height removed; assert chain still well-formed below.
7. **Snapshot/replay property** — snapshot N records, replay into fresh store, assert byte-equality.
8. **Concurrent next_index property** (derivation state only) — N threads call `next_index` for the same `(protocol, counterparty)`; assert no duplicate index.
9. **Crash-recovery property** — kill the process mid-write (test harness with `kill -9` or fault-injection); assert on restart no half-written rows.

### 5.2 Per-Postgres-table obligations (applies to M5.1–M5.4, M6.1)

1. **Schema-apply test** — DDL applies cleanly to an empty database; idempotent re-run is a no-op.
2. **Constraint-fire test** — every CHECK / FK / UNIQUE constraint has a test that violates it and asserts the rejection.
3. **Recursive CTE test** (cert_dag, session_chain) — 100-deep recursive walk returns the full path in deterministic order.
4. **Index plan test** — `EXPLAIN ANALYZE` over the canonical query for the table; assert the expected B+tree / GIN / GiST plan is chosen.
5. **JSONB validation test** (sir_program) — invalid JSONB structure rejected by trigger.

### 5.3 Per-FDW obligations (applies to M5.5–M5.7)

1. **Foreign-table read test** — `SELECT * FROM <foreign>` returns rows matching upstream truth.
2. **Pushdown test** — `EXPLAIN ANALYZE` shows predicate pushdown to upstream where supported.
3. **Materialisation fallback test** — predicate that cannot push down still returns correct results, just slower.
4. **Cross-tier JOIN test** — one query joins LMDB cell + Pravega tick + SQLite audit; assert byte-correct result.

### 5.4 Per-Pravega-stream obligations (applies to M3.3–M3.7)

1. **Exactly-once delivery test** — produce 10K events; subscriber reads 10K distinct events; no duplicates.
2. **Replay-from-snapshot test** — kill subscriber mid-stream; restart; assert no event loss, no duplicate.
3. **Segment-rollover test** — produce events past segment-size boundary; reads continue across rollover.
4. **Fan-out throughput test** — N subscribers reading the same stream; assert no producer slowdown.
5. **Schema-evolution test** — schema change is forward + backward compatible across one version.

### 5.5 Per-octave-fetch obligations (applies to M4.1–M4.6)

1. **Window-at-offset test** — fetch 1024 bytes at a specified offset within a 1 MB octave-1 cell; assert byte-correct.
2. **MFP metering test** — fetch with sufficient budget succeeds + emits tick; fetch with insufficient budget rejects.
3. **Cross-octave escalation test** — `OP_DEREF_POINTER` from octave 0 to octave 1, then from octave 1 to octave 2 (explicit per call); assert no auto-dereference.
4. **Linearity-preservation test** — LINEAR cell at octave 1 dereferenced via RELEVANT pointer; consumed-once enforced.
5. **Pointer-pack/unpack round-trip** — TS and Zig produce byte-identical pointer cells.

### 5.6 Test-naming convention

Every test file lives next to the code it tests:
- Zig: `core/cell-engine/src/foo_test.zig` (or use `zig build test` discovery).
- TS: `apps/world-client/src/foo.test.ts`.
- Postgres: `db/postgres/tests/test_<table>.sql`.
- Pravega: `infra/pravega/tests/test_<stream>.go` (or whichever language the gateway uses).

Test IDs map to deliverable IDs: `M1.2-T-vtable-conformance`, `M5.1-T-recursive-walk`, etc. The torture tests (§6) carry IDs `M<n>-T-torture-<name>`.

---

## 6. Torture tests (per-milestone exit gates)

A milestone does not exit until its torture test is green for **24 consecutive hours** under the conditions described. These are adversarial, sustained-load, fault-injection tests; they go beyond the unit/integration suite.

### M1-T — LMDB Hot Path Torture

**Setup:** LMDB-backed sovereign node loaded with synthetic data: 100 M cells, 10 M UTXOs, 1 M block headers, 100 K certs.

**Conditions:**
1. Sustained 50 K cell writes/sec for 24 h.
2. Concurrent random reads at 200 K/sec from 8 reader threads.
3. Reorg-truncate-from-height every 10 minutes (rollback 10 random heights, rebuild).
4. Power-loss simulation every 6 h (`kill -9` of the Semantos Brain process; assert clean restart).
5. Disk-full simulation: fill the LMDB env to capacity; assert graceful error, no corruption.

**Pass criteria:** all 100 M cells readable byte-identical at end; no JSONL replay needed; vtable conformance suite green.

### M2-T — SQLite Browser Torture

**Setup:** browser tab with 1 M cells in OPFS, cell engine running.

**Conditions:**
1. Tab-kill mid-write every minute for an hour.
2. OPFS quota exhaustion (fill quota; assert graceful error).
3. 10 concurrent tabs writing to the same OPFS handle.
4. Browser refresh mid-cell-engine-execution; assert engine resumes from last committed cell.

**Pass criteria:** no OPFS corruption; all valid writes durable; concurrent-tab semantics enforce single-writer.

### M3-T — Pravega Streaming Torture

**Setup:** single-node Pravega cluster with all five streams active.

**Conditions:**
1. 20 Hz region-tick sustained for 24 h (1.7 M ticks total).
2. 100 simultaneous subscribers per stream.
3. Segment-rollover every 1 h.
4. Pravega-node kill + restart every 6 h; assert no event loss.
5. Subscriber kill + restart every 30 minutes; assert resume-from-last-acked.

**Pass criteria:** zero event loss; no duplicate processing; consumer lag < 1 s under steady state.

### M3-T-Pask — Pask determinism + replay convergence torture

**Setup:** Pravega cluster with `pask-interactions` stream, plus 5 federated nodes all subscribed.

**Conditions:**
1. Run 1 M `pask_interact_run` calls against node A; capture the Pravega stream with all `(primary_cell_id, related_cell_ids, effective_strength, now_ms)` events.
2. Replay the captured stream on a fresh node B; assert `pask_snapshot_state` blob is **byte-identical** to node A's snapshot.
3. Inject 100 K out-of-order Pravega events (exactly-once should reorder per stream key); assert all 5 nodes converge to the same snapshot.
4. Kill the kernel mid-`pask_interact_run`; restart from last Pravega ack; assert no graph drift.
5. After 1 M sustained interactions across all 5 federated nodes, assert all 5 snapshots are byte-identical.

**Pass criteria:** zero drift across nodes; deterministic replay byte-identical; reorder-tolerant within Pravega ordering guarantees; recovery from mid-interaction kill is clean.

### M4-T — Octave Escalation Torture

**Setup:** node with 1 GB octave-1 dataset (1024 octave-1 cells), 1 TB octave-2 dataset via UHRP-HTTP.

**Conditions:**
1. 1 M random 1024-byte windowed reads against octave-1 cells over 24 h.
2. 100 K windowed reads against octave-2 cells (HTTP range).
3. MFP budget exhaustion mid-fetch every 1000 reads; assert clean rejection.
4. Pointer-cell forging attempt: feed a malformed pointer cell; assert kernel rejects with `K4` failure-atomic.
5. Nested-pointer auto-dereference attempt: chain pointer → pointer; assert no auto-deref.

**Pass criteria:** no incorrect bytes returned; no kernel crash; MFP metering exact; all forging attempts rejected.

### M5-T — Postgres Reasoning Torture

**Setup:** Postgres with 100 M-row `cert_dag`, 50 M `intent`, 10 M `lexicon_category`, FDWs into LMDB + Pravega + SQLite.

**Conditions:**
1. 100 K concurrent recursive ancestry walks over 24 h.
2. Four-way FDW JOIN query running every 10 s.
3. Bert's intent reducer producing 1000 intents/sec.
4. Schema migration applied mid-load; assert no downtime, no incorrect results.
5. FDW upstream node (LMDB) restarts every 4 h; assert FDW reconnects cleanly.
6. For every action-phase cell (`phase = 0x06`) written during the load: assert `sir_program_hash` field is non-zero and a corresponding `sir_program` row exists in Postgres keyed by that hash (teachback-chain completeness check, per wishlist B11 and deliverable M5.14).

**Pass criteria:** all queries return correct results; no FDW-stale-result errors; schema migration completes without lock contention > 1 min; teachback-chain check reports zero missing `sir_program` rows.

### M6-T — Registry Drift Torture

**Setup:** registry source-of-truth in Postgres, LMDB cache, Pravega change feed, SQLite browser mirror.

**Conditions:**
1. Inject simulated drift (manually edit LMDB cache to disagree with Postgres); drift-detection must catch within 60 s.
2. Pravega change-feed lag injected; cache invalidation must respect lag.
3. Browser mirror falls behind by 1000 events; resyncs cleanly on next connection.
4. Federation peer joins with conflicting registry view; reconciliation must preserve source-of-truth.

**Pass criteria:** all drift detected; all reconciliations preserve Postgres source-of-truth; no silent drift survives 60 s.

### M7-T — Federation Torture

**Setup:** 5-node federation; each node holds ~20 % of octave-3 slots.

**Conditions:**
1. Network partition between two nodes for 30 minutes; cells routed correctly to surviving partition.
2. One node simulated byzantine (returns wrong bytes); detection within 60 s, eviction triggered.
3. New node joins; receives slot subset; reads work.
4. Old node leaves; slots rebalanced to remaining peers; reads continue.
5. Sustained 1000 fetches/sec across all 5 nodes for 24 h.

**Pass criteria:** no incorrect bytes returned; no slot lost; no double-ownership; rebalance completes < 5 minutes.

### Torture-test ownership

Torture tests are **not** authored by the same agent as the deliverable. A torture-test agent reads the milestone's deliverables and writes adversarial scenarios. This avoids "I tested what my code does" bias.

---

## 7. Risk register

| Risk                                                    | Severity | Mitigation                                                                                                  |
|---------------------------------------------------------|----------|--------------------------------------------------------------------------------------------------------------|
| LMDB max-value-size limit hit at octave 1               | Med      | M4.1 uses `content-store-local-fs` not LMDB for octave 1; LMDB capped at octave 0                           |
| Pravega operational complexity                          | High     | M3.1 dev cluster first; production cluster only after M3.7 proven                                            |
| FDW pushdown limits on cells_lmdb                       | Med      | Materialisation fallback (§5.3) is acceptable for low-frequency Helm queries; not the kernel hot path        |
| Bert's Postgres tier behind schedule                    | Med      | M1–M4 do not depend on M5; pipeline can ship without M5 in a "no reasoning tier" v0.5 mode                  |
| WASM kernel binary size grows past 50 KB                | High     | Every M1.10 / M2.7 PR runs a binary-size check; regression fails CI                                          |
| Vtable contract subtly broken by new backing            | High     | §5.1 obligation #1 (vtable conformance) reuses the existing test suite verbatim; no new tests substitute for it |
| Browser OPFS quota too small for production data        | Med      | M2.6 ATTACH-per-domain pattern lets the browser carry only the active domain                                 |
| Registry-LMDB cache drift                               | Med      | M6.5 drift-detection job is a hard requirement of M6 exit                                                    |
| Federation peer byzantine behaviour                     | High     | M7-T explicitly tortures byzantine peers; no production federation without M7-T green                       |
| Reading this doc from inside an agent loses context     | Low      | Companion docs in §0 are kept short; agent reads them in order before opening code                           |

---

## 8. What "done" looks like

The pipeline is complete when:
- All matrix rows in §3 are `merged` status.
- All §6 torture tests have been green for 24 h continuous on the staging cluster.
- A 7-day soak test of a full sovereign-node + 5 World-Client browsers + 5 federation peers passes with no incidents.
- Documentation cross-links updated: `docs/canon/SEMANTOS-DB-WISHLIST.md` Tier A/B/C items reference the matrix IDs that delivered them.
- `runtime/semantos-brain/src/main.zig` boots with LMDB + SQLite + Pravega + Postgres bindings active by default; the FS-store fallback is preserved for emergency rollback only.

Out-of-scope items (M8 NVMe-CS, M9 multi-engine, M10 BFT committee) remain `pending` in their own future-milestone tracking files and do not gate this pipeline.

---

## 9. How an agent claims a row

1. Open `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`.
2. Find a row in §3 with `Status: pending` and `Depends on:` all `merged`.
3. Edit the row: set `Owner: <agent name>`, `Status: in_progress`. Commit + push as a single-row PR.
4. Read the four companion docs in §0 if not already loaded.
5. Author the §5-required tests for the row. Land tests first, code second.
6. When the row's Acceptance column is green, set `Status: review`. Open PR.
7. After merge, set `Status: merged`. Note the commit/PR in the row.
8. If the milestone's other rows are also `merged`, schedule the §6 torture test against staging.

---

## 10. Open questions for the implementer

These are unresolved at plan time and need either a design note or a quick decision before the relevant deliverable starts:

1. **Which LMDB Zig binding?** Options: `lmdb-zig` (Karrick), hand-rolled FFI to liblmdb. Plan: use the most actively-maintained one; M1.1 acceptance includes a written justification.
2. **Pravega gateway language?** Native Pravega client is JVM. Options: JVM gateway with Zig-via-FFI; Go gateway via `pravega-client-go`; native Zig client (significant effort). Plan: M3.2 spike chooses; document tradeoffs.
3. **FDW for Pravega?** Postgres `multicorn` (Python FDW framework) is the most flexible but adds a Python runtime. Alternative: cron-based materialised view refreshes. Plan: M5.6 spike chooses.
4. **Octave-1 storage layout — one file per slot or one big sparse file?** Per-slot is simpler; sparse file is more compact. Plan: M4.1 acceptance tests both, picks the better mmap behaviour.
5. **SQLite-WASM-OPFS production browser story** — Chrome, Safari, Firefox quota limits differ. Plan: M2.1 includes per-browser quota table.
6. **Bert's Postgres deployment (managed vs self-hosted)?** — coordinate with Bert; not blocking until M5.

These questions live here, not in implementation PRs. An agent that hits one stops, drafts a design note, gets review, then implements.

---

## 11. Document maintenance

This pipeline is the source of truth for DB-tier work. When status changes:

- Edit the matrix row in-place. Commit message: `pipeline: M<n>.<m> → <status>`.
- Add a one-line note in the row's Acceptance cell when the actual gate text differs from the planned text.
- Promote rows that complete to `merged`; do not delete them. The matrix is the post-mortem record.
- New deliverables added mid-pipeline get IDs `M<n>.<next>` continuing the sequence; never reuse an ID.

If the topology itself changes (new engine added, milestone restructured), revise the companion docs first (`SEMANTOS-DB-WISHLIST.md` / `SEMANTOS-DB-MULTI-TIER-TOPOLOGY.md`); this pipeline follows from them, not the reverse.

---

## 12. Hand-off checklist for the Claude Code session

When starting a Claude Code session against this pipeline, the agent should:

- [ ] Read this document in full.
- [ ] Read the four companion docs (§0).
- [ ] Read the textbook chapters referenced in §0.
- [ ] Read `runtime/semantos-brain/src/header_store_fs.zig`, `output_store_fs.zig`, `state_store_fs.zig` to understand the vtable.
- [ ] Read `core/cell-engine/src/cell.zig`, `octave.zig`, `pointer.zig`, `headers.zig`.
- [ ] Read the existing test suite shape in `core/cell-engine/tests/`.
- [ ] Pick one row from §3 matching the agent's specialization (§4).
- [ ] Confirm dependencies are `merged`.
- [ ] Update the row to `in_progress` with owner.
- [ ] Author tests per §5.
- [ ] Land code per §3 acceptance.
- [ ] Update row to `review` then `merged`.
- [ ] Run §6 torture test if the milestone's last row.

The architecture is designed; the engineering follows the plan. No invariant in §1 is negotiable. Every deliverable in §3 is a discrete unit that fits in a focused Code session.
