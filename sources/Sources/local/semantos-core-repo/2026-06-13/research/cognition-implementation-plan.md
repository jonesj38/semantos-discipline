---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/cognition-implementation-plan.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.340322+00:00
---

# Cognition Framework — TDD Implementation Plan & Multiparticipant Agreement Experiment

Companion to `research/cognition-framework.md` (the *what*) and `research/analogical-integration-assessment.md` (the *integration shape*). This is the *how* — a phased TDD plan, a tracking matrix that makes coverage visible, and a falsifiable hypothesis + methodology for demonstrating the substrate's claim that **a node is agreed-upon when independent Pask kernels subscribed to overlapping streams converge on its stability**.

The plan inherits the conventions already in tree:
- Zig tests are `*_conformance.zig` / `*_test.zig` files using `std.testing` with `test "..."` blocks (see `core/pask/tests/stability_conformance.zig`).
- TypeScript tests are `__tests__/*.test.ts` using `bun:test` (see `runtime/intent/src/__tests__/reducer-trades.test.ts`).
- The event spine is **NATS JetStream** (W7.3) — the project has pivoted away from Pravega for the short term until serious load justifies it. NATS producers live in `runtime/semantos-brain/src/nats_event_producer.zig` and `runtime/semantos-brain/src/nats_client.zig`; they share the per-operator subject hierarchy `op.<op_pkh16>.<hat_id>.<event_type>` and the per-operator JetStream stream `op_<op_pkh16>`. The legacy Pravega producers (`pask_interaction_producer.zig`, `oddjobz_event_producer.zig`) remain in tree as best-effort secondary lanes; new event types land on NATS only.
- Lean proofs live at `proofs/lean/Semantos/` and discharge per-lexicon injectivity obligations.

The plan keeps that pattern. No new test runners, no new infrastructure invented — RED commits land first against existing harnesses, GREEN follows, REFACTOR + DOCS close.

### Substrate change log

The original draft assumed Pravega as the durable event spine for every `*_producer.zig` work item. Since W7.3 landed (NATS client + producer wired into `jobs_handler.zig`), all event-emission work items below are re-targeted to NATS JetStream with no semantic change to the experiment in §4 — the cross-kernel agreement test consumes events from a stream regardless of which substrate carries them. When the project later returns to a high-throughput backplane, the producer/consumer interfaces are stable enough that swapping NATS for Pravega (or running both) is mechanical.

---

## 1. Work-item taxonomy

Every work item below carries the same five-field shape so the matrix in §3 stays uniform:

| Field | Meaning |
|---|---|
| **ID** | Stable identifier, e.g. `WI-A2`, used in commit messages and PR titles |
| **Tier** | Maps to `cognition-framework.md` §3 tiers — A (observe), B (analogical), C (federate), D (anchor) |
| **Layer** | Cybernetic order this lands at — 1st / 2nd / 3rd |
| **Files touched** | The exact paths a PR opens |
| **Acceptance** | Both the test that flips RED→GREEN, and the empirical signal we're after |

Tiers gate each other: nothing in B starts until A's measurement returns the falsifiable number; nothing in C starts until B has populated at least one library; nothing in D starts until C has a federated kernel pair producing observable cross-kernel stability. That ordering is part of the plan, not a suggestion.

---

## 2. Work items, in order

### Tier A — observe what's happening

#### WI-A0 — NATS event spine (W7.3) — **already in tree**

- **Status.** Done. Kept here for matrix completeness because every downstream item depends on it.
- **Files.** `runtime/semantos-brain/src/nats_client.zig`, `runtime/semantos-brain/src/nats_event_producer.zig`, `runtime/semantos-brain/src/resources/jobs_handler.zig` (FSM transitions emit), `docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2.4.
- **What it gives downstream.** A working `NatsEventProducer` with `publish`/`emitJobTransition`/`ensureStream`/`ensureBrainConsumer`/`deleteStream`, plus the subject convention `op.<op_pkh16>.<hat_id>.<event_type>` and the per-operator stream `op_<op_pkh16>`. WI-A1 and WI-A3 extend this producer; they do not introduce a new transport.

#### WI-A1 — `emitIntentOutcome` on the NATS producer

- **Layer.** 2nd order (the system observing its own intent reductions).
- **Files.** Modified: `runtime/semantos-brain/src/nats_event_producer.zig` (add `emitIntentOutcome` + payload schema + inline tests). New: `runtime/semantos-brain/tests/nats_event_producer_intent_outcome_test.zig` for the emit-shape integration test against `MockHttpServer`.
- **Pattern.** Add a method alongside `emitJobTransition`. Subject: `op.<op_pkh16>.<hat_id>.intent_outcome`. Payload:
  ```json
  {
    "intent_id": "<uuid>",
    "domain_flag": <u32>,
    "lexicon": "<string>",
    "jural_category": "<string>",
    "anf_bindings": [{ "name": "$0", "kind": "comparison", ... }],
    "composite_confidence": <f64>,
    "cell_outcome_hash": "<hex64>",
    "ts_ms": <u64>,
    "hat_id": "<string>",
    "op_pkh": "<16hex>"
  }
  ```
- **RED tests** (inline in `nats_event_producer.zig`).
  - `WI-A1-T-subject-shape` — built subject equals `op.<op_pkh16>.<hat_id>.intent_outcome`.
  - `WI-A1-T-payload-required-fields` — payload JSON contains all ten top-level fields.
  - `WI-A1-T-anf-bindings-survive` — passing two bindings (comparison + timeConstraint) round-trips through the payload string.
  - `WI-A1-T-empty-bindings-emits-empty-array` — zero bindings produces `"anf_bindings":[]`, not `null`.
- **GREEN.** Implementation against the existing `NatsClient.publish` mutex-serialised hot path. No new transport.
- **Acceptance.** `zig build test-nats-event-producer` green. Subject prefix and JetStream subject filter `op.<pkh>.>` deliver this message identically to `fsm_transition` (proves the spine is event-type-agnostic, which the federation experiment depends on).

#### WI-A2 — TS adapter that drives `emitIntentOutcome` after `processIntent`

- **Layer.** 2nd order.
- **Files.** New: `runtime/intent/src/outcome-emitter.ts`, `runtime/intent/src/__tests__/outcome-emitter.test.ts`. Modified: the call site in `runtime/services/src/services/` where `processIntent` returns with the lowered `IRProgram`.
- **Pattern.** A thin emitter that takes `(Intent, IRProgram, cellOutcomeHash, hat_id)` and invokes the Zig producer through the existing host bridge — same path BRAIN already uses for `OddjobzEventProducer`. Behind a `NatsEmitter` interface so tests can substitute a recording double.
- **RED tests.**
  - `WI-A2-T-emit-on-success` — successful Intent commit calls the emitter exactly once.
  - `WI-A2-T-no-emit-on-rejection` — SIR rejection produces no emit (rejected programs are not outcomes).
  - `WI-A2-T-anf-bindings-passthrough` — IRProgram bindings reach the emitter payload unchanged.
- **GREEN.** Implementation. Wire into the existing intent processing flow.
- **Acceptance.** End-to-end through a single trades fixture (T-1 from `trades-fixtures.ts`): the test commits an Intent and asserts the recording double captured an event with the correct domain_flag and category.

#### WI-A3 — `emitStableTransition` on the NATS producer

- **Layer.** 2nd order (kernel reporting its own state changes).
- **Files.** Modified: `runtime/semantos-brain/src/nats_event_producer.zig` (add `emitStableTransition` + inline tests). New: a small host-side wrapper around `pask_interact_run` that inspects the post-tick stability state and calls `emitStableTransition` for each node where `transitioned_to_stable=true`. The Pask kernel itself stays untouched — this is host-side observation, not kernel modification.
- **Pattern.** Subject: `op.<op_pkh16>.pask.stable_transition` (using `pask` as a synthetic hat namespace because stability transitions are kernel-level events not bound to any hat). Payload:
  ```json
  {
    "node_idx": <u32>,
    "cell_id": "<hex64>",
    "h_state": <f64>,
    "total_constraint_strength": <f64>,
    "interaction_count": <u32>,
    "kernel_id": "<host-uuid>",
    "ts_ms": <u64>,
    "op_pkh": "<16hex>"
  }
  ```
  - `kernel_id` is critical for federation work later — it's how downstream consumers attribute events to specific kernels in the multiparticipant agreement experiment in §4.
- **RED tests.**
  - `WI-A3-T-subject-shape` — built subject equals `op.<op_pkh16>.pask.stable_transition`.
  - `WI-A3-T-payload-fields` — payload contains node_idx, cell_id, kernel_id, h_state, ts_ms.
  - `WI-A3-T-kernel-id-stable` — same producer instance always emits same `kernel_id`.
  - `WI-A3-T-no-emit-on-skip` — host wrapper does not emit when `StabilityResult.skipped=true` or `transitioned_to_stable=false`.
- **Acceptance.** Run the chess-PGN demo (the kernel's existing canonical learning task in `core/pask/tests/chess_conformance.zig`) under the host wrapper; assert that the count of `stable_transition` emissions equals the count of false→true flips reported by `pask_stable_threads_into`.

#### WI-A4 — Empirical HRR encoding feasibility on existing fixtures

- **Layer.** 2nd order. **No new code yet** — this is a *measurement* work item, not a build item.
- **Files.** New: `research/experiments/hrr-encoding-feasibility.ts` (a script, not production code), and a results file `research/experiments/hrr-encoding-feasibility.results.md`.
- **Pattern.** Implement a one-file HRR encoder following Plate's circular-convolution scheme (1024-D, role vectors seeded by `(domain_flag, role_name)` via SHA-256). Iterate over the trades + SCADA fixtures already in `runtime/intent/src/reducer/__fixtures__/`. For each pair of fixtures, compute the cosine of their full-program HRRs.
- **Falsifiable measurement.** Three concrete numbers:
  1. **Same-category mean cosine** — within `(domain=trades, category=obligation)`, mean cosine across all pairs.
  2. **Cross-category mean cosine** — across `(domain=trades, category=obligation)` vs `(domain=trades, category=transfer)`.
  3. **Cross-domain mean cosine** — `(domain=trades, *)` vs `(domain=scada, *)`. **Should be ≈ 0** because the role-vector basis is orthogonal-by-construction across domains. If it isn't, the seeding is wrong.
- **Acceptance.** Numbers (1) > 0.7, (2) < 0.5, (3) within ε of 0 (say, |cos| < 0.1 averaged). If any threshold is missed, **WI-A4 stops the plan**: tier B does not proceed until the encoding redesign produces these numbers.

This is the **falsification gate for the analogical layer**. Cheap to run, expensive to ignore.

---

### Tier B — build the analogical layer

Gated on WI-A4 returning the right numbers.

#### WI-B1 — Production HRR encoder package

- **Layer.** 2nd order.
- **Files.** New: `core/hrr/src/encode.ts`, `core/hrr/src/role-vectors.ts`, `core/hrr/src/__tests__/encode.test.ts`, `core/hrr/package.json`, etc.
- **Pattern.** Promote the experiment script into a real package. Public API: `encodeSIRProgram(program: IRProgram, domainFlag: number): Float64Array`, `cosine(a, b)`, `bind(role, filler)`, `unbind(bound, role)`.
- **RED tests.**
  - `WI-B1-T-encode-deterministic` — same program → same vector.
  - `WI-B1-T-bind-unbind-roundtrip` — `unbind(bind(r, f), r) ≈ f` within HRR noise budget.
  - `WI-B1-T-orthogonal-basis-across-domains` — role vector for `(d=1, "obligor")` and `(d=2, "obligor")` cosine ≈ 0.
  - `WI-B1-T-fixture-cosines` — re-run WI-A4's three measurements as unit tests with assertions, not just a script.

#### WI-B2 — HRR library indexed per `(domain_flag, jural_category)`

- **Layer.** 2nd order, with a 3rd-order seam (capability-gated reads).
- **Files.** New: `runtime/hrr-library/src/library.ts`, `runtime/hrr-library/src/__tests__/library.test.ts`. Modified: a new Pravega consumer subscribed to `stable_transition` (WI-A3) and `intent_outcome` (WI-A1) that populates the library.
- **Pattern.** In-memory map keyed by `(domain_flag, jural_category) → Map<cell_id, Float64Array>`. Persisted to disk on snapshot. Query API: `nearest(query: Float64Array, domainFlag: number, jural: string, k: number, capabilities: Set<number>): {cellId, similarity}[]`. Capability set acts as a projection operator — only roles in the capability set are deconvolved at query time.
- **RED tests.**
  - `WI-B2-T-promote-on-stable-transition` — an event arriving promotes a vector into the library if its companion `intent_outcome` event also arrived.
  - `WI-B2-T-nearest-respects-domain` — query in domain A never returns vectors from domain B.
  - `WI-B2-T-capability-projection` — query with capability set X recovers only roles in X.
  - `WI-B2-T-snapshot-roundtrip` — library state survives serialise/deserialise.

#### WI-B3 — Pre-filter reducer pass

- **Layer.** 2nd order.
- **Files.** New: `runtime/intent/src/reducer/analogical-prefilter-pass.ts`, `runtime/intent/src/reducer/__tests__/analogical-prefilter-pass.test.ts`. Modified: `runtime/intent/src/reducer/index.ts` (insert the new pass between rhetoric and arithmetic).
- **Pattern.** Implement `PassFn`. Encodes the partial Intent structure as a query HRR using the data from grammar+logic+rhetoric (`taxonomy.what`, `taxonomy.how`, `category`, `action`). Queries the library via WI-B2. Writes top-K matches to `producerMeta.candidateTemplates`.
- **RED tests.**
  - `WI-B3-T-emits-empty-on-cold-library` — with no library entries, contribution is empty, confidence = 1 (vacuously satisfied).
  - `WI-B3-T-finds-known-template` — populate library with T-1, run T-1', assert T-1 is in top-3.
  - `WI-B3-T-respects-domain-flag` — a trades query never surfaces SCADA templates.

#### WI-B4 — Pragmatic-rank reducer pass

- **Layer.** 2nd order.
- **Files.** New: `runtime/intent/src/reducer/analogical-rank-pass.ts`, `runtime/intent/src/reducer/__tests__/analogical-rank-pass.test.ts`. Modified: `runtime/intent/src/reducer/index.ts` (append after astronomy).
- **Pattern.** Encode the now-complete Intent as a full-program HRR. Score against the candidates from WI-B3. Write `producerMeta.analogicalMatches: { templateCellId, similarity }[]`.
- **RED tests.**
  - `WI-B4-T-self-similarity-one` — encoding the same program twice gives cosine 1.
  - `WI-B4-T-monotonic-similarity` — small mutations of a program produce monotonically-decreasing similarity to the original.

#### WI-B5 — Hierarchical HRR for octave-1+ structures

- **Layer.** 2nd order.
- **Files.** Modified: `core/hrr/src/encode.ts`. New: `core/hrr/src/hierarchical.ts`, `core/hrr/src/__tests__/hierarchical.test.ts`.
- **Pattern.** Compressed summary HRR for octave-0 surface; pointer-deref to detailed structure stored separately for deep matching. Mirrors how `OP_DEREF_POINTER` works at the cell-engine level.
- **Acceptance.** Library can index octave-1 contracts (e.g., a multi-clause real-estate contract from the property-management lexicon) and retrieve them at the same noise budget as octave-0.

---

### Tier C — federate

Gated on WI-B2 producing a non-empty library against real fixture data.

#### WI-C1 — Two-kernel single-process harness

- **Layer.** 3rd order, but in a *test* environment so the canon's "no silent cross-user learning" rule is preserved by construction (no real users).
- **Files.** New: `core/pask-and-cell/tests/two_kernel_harness.zig` and a TS counterpart `runtime/services/src/__tests__/two-kernel-harness.test.ts` for cross-language coverage.
- **Pattern.** Instantiate two `Store` instances in the same process. Feed both an interleaved sequence of interactions, with a configurable overlap parameter (`shared_fraction`: how many interactions go to both vs. one only). Compute cross-kernel stability convergence — for each cell present in both stores, is it stable in both? In one but not the other?
- **RED tests.**
  - `WI-C1-T-disjoint-streams-no-convergence` — `shared_fraction = 0`: convergence rate ≈ 0 (no shared cells).
  - `WI-C1-T-identical-streams-full-convergence` — `shared_fraction = 1`, both kernels deterministic: every shared cell stable in A is stable in B (this is the determinism replay test from `core/pask/tests/determinism_conformance.zig` lifted to two kernels).
  - `WI-C1-T-partial-overlap-intermediate-convergence` — `shared_fraction = 0.5`: convergence rate is between the two extremes, monotonically increasing in shared_fraction (this is the empirical input to §4 below).

#### WI-C2 — Federation-aware pruning policy

- **Layer.** 3rd order.
- **Files.** Modified: `core/pask/src/pruner.zig` is **not** modified (kernel stays observer-independent at the federation level). New: `runtime/semantos-brain/src/federation_prune_guard.zig` — host-side that consults a `federation_keep_alive` Pravega stream before invoking `pask_finalize`.
- **Pattern.** Before pruning a node, check whether any peer kernel emitted a `keep_alive` signal for that cell within the configured window. If yes, suppress pruning at the host adapter level by deferring the affected node's processing. The kernel itself doesn't know — its prune rule remains local; the host decides whether to call it.
- **RED tests.**
  - `WI-C2-T-prune-suppressed-by-peer-signal` — peer emits keep_alive; local prune-eligible node is not pruned.
  - `WI-C2-T-prune-proceeds-without-peer-signal` — same node, no peer signal, gets pruned per local rule.

#### WI-C3 — N-kernel deployment with Mandala subscription rule

- **Layer.** 3rd order.
- **Files.** New: `runtime/semantos-brain/src/mandala_subscriber.zig`, `runtime/semantos-brain/tests/mandala_subscriber_conformance.zig`, plus a deployment harness in `infra/`.
- **Pattern.** Implement a candidate subscription rule from `cognition-framework.md` §4 Gap 4: "subscribe to (a) every counterparty stream above a transaction threshold, (b) every stream tagged with the same `domain_flag` as your active hat, (c) a small random sample of high-`h_state` streams from outside your domain." Parameterise so the mix can be tuned.
- **RED tests.**
  - `WI-C3-T-subscription-includes-counterparties` — kernel with N counterparty interactions has N corresponding subscriptions.
  - `WI-C3-T-domain-flag-subscription-active` — kernel with active hat in domain D subscribes to D's stream.
  - `WI-C3-T-random-sample-bounded` — random-sample slice never exceeds the configured cap.
- **Acceptance graph metrics.** Deploy 16 kernels with this rule. Measure clustering coefficient and average path length on the resulting subscription graph. Compare against the Sampaio et al. 2015 Mandala-graph parameters cited in the paper (`b=2..4`, `n_1=3..4`, `λ=2`). Plan succeeds if the produced graph lies in the small-world band; iterate the rule otherwise.

#### WI-C4 — K10–K12 formal invariants

- **Layer.** 3rd order, formal-verification work.
- **Files.** New: `proofs/lean/Semantos/Federation/Invariants.lean`, `proofs/lean/Semantos/Federation/Convergence.lean`.
- **Theorems to prove.**
  - **K10 (federation determinism)** — given identical interaction streams to two kernels with identical configs, the resulting Stores are bit-identical (this is the determinism conformance test promoted to a formal theorem).
  - **K11 (federation monotonicity)** — under WI-C2's prune guard, increasing the peer-keep-alive set never increases the set of pruned nodes.
  - **K12 (federation stability composition)** — if a cell is stable in kernels A and B subscribed to overlapping streams S_A ∩ S_B ≠ ∅, then it is stable when their stability counts are unioned over the shared sub-stream. This is the formal version of Pask's multi-participant agreement criterion.

---

### Tier D — anchor and incentivise

Gated on Tier C demonstrating cross-kernel stability is observable and the K10–K12 invariants pass.

#### WI-D1 — Stable-thread Merkle anchor

- **Layer.** 3rd order.
- **Files.** New: `runtime/semantos-brain/src/stable_thread_anchor.zig`, plus an sCrypt cell type in `core/cell-engine/`.
- **Pattern.** When a kernel's stable-thread set crosses a confirmation threshold (e.g., N consecutive snapshots with no churn in the top-K threads), publish a Merkle root of the threads to chain via a stateful sCrypt cell. Cell carries `(kernel_id, snapshot_seq, merkle_root, timestamp)`.
- **RED tests.**
  - `WI-D1-T-anchor-on-threshold` — N stable snapshots → exactly one anchor cell minted.
  - `WI-D1-T-merkle-roundtrip` — anchored root matches independently-computed root.

#### WI-D2 — Capability-token incentive UTXO

- **Layer.** 3rd order.
- **Files.** New: a sCrypt contract in `core/cell-engine/` or `apps/` with full conformance tests.
- **Pattern.** UTXO predicated on `(verified_weight_output_match)` — a downstream kernel that cites a peer's stable thread can release the UTXO when the citation is itself anchored. This is the paper's "training-as-public-bounty" reified.
- **Acceptance.** End-to-end test: kernel A produces a stable thread, anchors it, kernel B's reducer picks it up via WI-B3, kernel B's intent commits citing it, the citation anchors, the UTXO releases.

---

## 3. Tracking matrix

The matrix lives here in markdown. Each row is a work item; each column is a TDD/coverage stage. Entries:
- ❑ — not started
- 🔴 — RED (test exists, fails)
- 🟢 — GREEN (test passes)
- ♻️ — REFACTOR done
- ✅ — landed + documented + acceptance signal observed
- N/A — not applicable to this item

| ID | Tier | Layer | Unit RED | Unit GREEN | Refactor | Integration | Fixture/empirical | Formal proof | Docs | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| WI-A0 | A | 2 | ✅ | ✅ | ✅ | ✅ | N/A | N/A | ✅ | ✅ landed (W7.3) |
| WI-A1 | A | 2 | 🟢 | 🟢 | ❑ | ❑ | N/A | N/A | ❑ | `zig build test` confirmed exit 0; 11 inline tests pass; integration via WI-A2 |
| WI-A2 | A | 2 | 🟢 | 🟢 | ❑ | ❑ | ❑ (T-1 fixture) | N/A | ❑ | `outcome-emitter.ts` + 7 bun tests pass (146/146); `NatsEmitter` wired into `PipelineDeps` |
| WI-A3 | A | 2 | 🟢 | 🟢 | ❑ | ❑ (chess PGN demo) | ❑ | N/A | ❑ | producer extended (11 inline tests); `pask_stable_observer.zig` + 5 inline tests; 340/340 build steps pass |
| WI-A4 | A | 2 | N/A | N/A | N/A | N/A | 🟢 (3 cosine measurements) | N/A | 🟢 | **gate passed** — same-cat 0.8005 > 0.7, cross-cat 0.4257 < 0.5, cross-dom 0.0143 < 0.1³ |
| WI-B1 | B | 2 | 🟢 | 🟢 | ❑ | ❑ | 🟢 (re-run WI-A4 as tests) | N/A | ❑ | 14/14 bun tests pass — `core/hrr/` package; `encodeSIRProgram`, `bind`, `unbind`, `cosine` wired; WI-A4 cosine thresholds asserted |
| WI-B2 | B | 2/3 | 🟢 | 🟢 | ❑ | ❑ | N/A | N/A | ❑ | 19/19 bun tests pass — `runtime/hrr-library/`; two-phase promotion, domain filtering, capability gating, snapshot roundtrip |
| WI-B3 | B | 2 | 🟢 | 🟢 | ❑ | ❑ (full reducer flow) | N/A | N/A | ❑ | 10/10 bun tests pass — `analogical-prefilter-pass.ts` wired between rhetoric and arithmetic; cold-library vacuous, top-K candidates, domain-flag isolation |
| WI-B4 | B | 2 | 🟢 | 🟢 | ❑ | ❑ | N/A | N/A | ❑ | 10/10 bun tests pass — `analogical-rank-pass.ts` after astronomy; `encodePartialIntent` extended with `howTaxonomy`; self-similarity=1, monotonic mutations, domain isolation |
| WI-B5 | B | 2 | 🟢 | 🟢 | ❑ | ❑ | 🟢 (octave-1 contract) | N/A | ❑ | 9/9 bun tests pass — `core/hrr/src/hierarchical.ts`; summary stable at 10–15 clauses, detail encodes clause content, cross-domain isolation preserved |
| WI-C1 | C | 3 | 🟢 | 🟢 | ❑ | 🟢 (two-kernel harness) | ❑ (§4 experiment) | N/A | ❑ | 3/3 Zig (core/pask-and-cell) + 3/3 TS (runtime/services); disjoint < 0.5, identical = 1, monotonic partial |
| WI-C2 | C | 3 | 🟢 | 🟢 | ❑ | ❑ | N/A | 🟢 (K11) | ❑ | 5/5 Zig inline tests — `runtime/semantos-brain/src/federation_prune_guard.zig`; suppress/proceed/expired/bump/eviction |
| WI-C3 | C | 3 | 🟢 | 🟢 | ❑ | ❑ (16-kernel deploy) | ❑ (Mandala metrics) | N/A | ❑ | 4/4 Zig inline tests — `runtime/semantos-brain/src/mandala_subscriber.zig`; counterparty threshold, domain flag, sample cap |
| WI-C4 | C | 3 | N/A | N/A | N/A | N/A | N/A | 🟢 (K10–K12) | ❑ | Lean proofs in `proofs/lean/Semantos/Federation/`; K10 by rfl, K11 Finset monotone, K12 concat-avg-≤ lemma |
| WI-D1 | D | 3 | 🟢 | 🟢 | ❑ | ❑ (anchor end-to-end) | N/A | N/A | ❑ | 4/4 Zig inline tests — `runtime/semantos-brain/src/stable_thread_anchor.zig`; threshold, Merkle roundtrip, churn reset |
| WI-D2 | D | 3 | 🟢 | 🟢 | ❑ | ❑ (UTXO release) | N/A | N/A | ❑ | 4/4 Zig inline tests — `core/cell-engine/src/cognition_bounty.zig`; release/wrong-root/unanchored/end-to-end |

**How to keep it accurate.** Check the matrix in to git alongside the code. Update the cell on the same PR that lands the code or test. PR template includes "matrix update?" as a checkbox; CI reads the matrix and emits a coverage summary. When a cell flips to ✅, the next gated item unlocks for owner assignment.

**Footnotes.**

² WI-A3 adds `pask_stable_observer.zig` (5 inline tests) and wires native pask modules (`pask_config_mod`, `pask_types_mod`, `pask_store_native_mod`) into `runtime/semantos-brain/build.zig`. These are the first native Pask Store uses in the BRAIN build graph. `zig build test` confirmed 340/340 build steps, 1435/1479 tests pass (44 skipped; 2 pre-existing flaky failures in unrelated LMDB/unix-socket tests).

³ WI-A4 ran `research/experiments/hrr-encoding-feasibility.ts` (Plate 1995 circular-convolution HRR, D=1024). Same-category mean cosine 0.8005, cross-category mean cosine 0.4257, cross-domain mean |cosine| 0.0143. One outlier: `(scada, actuation) vs (scada, measurement)` at 0.6051 because both share `objectType=scada.equipment` (3/5 shared bindings). Mean still clears the 0.5 threshold. WI-B1 should consider down-weighting `objectType` for categories sharing a natural equipment class. Results in `research/experiments/hrr-encoding-feasibility.results.md`.

**Coverage roll-up rules.**
- A row reaches ✅ only when *every applicable cell* in that row is ✅ — partial green doesn't ship.
- A tier reaches ✅ only when every row in it does.
- Tier B does not begin until WI-A4 cell `Fixture/empirical` is ✅.
- Tier C does not begin until WI-B2 row is ✅.
- Tier D does not begin until WI-C3 row is ✅ **and** WI-C4 row is ✅.

That last gate is deliberate. Federating without the K10–K12 formal property would be deploying behaviour the substrate cannot prove.

---

## 4. Hypothesis & methodology — the multiparticipant agreement experiment

This is what the framework actually claims is novel: **the substrate operationalises Pask's 1976 multi-participant agreement criterion in a way that's computationally tractable and empirically falsifiable.** §4 turns that claim into a falsifiable experiment that runs on top of WI-C1, with a clean statistical test.

### 4.1. Hypothesis

Let *S(c, K)* denote the event "cell *c* is marked stable in kernel *K* at the end of an interaction run." Let *O(K_A, K_B)* denote the set of cells that appear in both kernels' stores when *K_A* and *K_B* subscribe to overlapping interaction streams. Define the *cross-kernel agreement rate*:

  *A(K_A, K_B) = P[ S(c, K_A) ∧ S(c, K_B) | c ∈ O(K_A, K_B) ]*

and the *marginal agreement rate*:

  *M(K_A, K_B) = P[S(c, K_A) | c ∈ O(K_A, K_B)] · P[S(c, K_B) | c ∈ O(K_A, K_B)]*

The marginal rate is what you'd expect under the null that cross-kernel stability is independent across kernels — that two kernels both happening to stabilise the same cell is just the product of their independent marginal stability rates.

**H_0 (null)** — Cross-kernel stability is independent. *A(K_A, K_B) ≈ M(K_A, K_B)* across all overlap fractions. Under H_0, the substrate's claim that federation gives genuinely-multiparticipant agreement is false: federation is just two kernels coincidentally agreeing.

**H_1 (substrate claim)** — Cross-kernel stability is genuinely informative. *A(K_A, K_B) > M(K_A, K_B)* with effect size growing in the overlap fraction. Specifically, we expect *A − M* to be near zero at overlap = 0 (no shared evidence, kernels can't co-stabilise on the same cells beyond chance) and to rise monotonically toward a plateau as overlap → 1 (the determinism property — fully shared streams produce fully co-stable cells, which is K10).

**H_1 falsification.** If at overlap = 1 we have *A* materially below *M* + 0.5 (for example), the determinism conformance test is failing across kernels and the substrate is broken. If *A − M* doesn't rise with overlap, the substrate is correct but federation isn't adding anything beyond what the marginal stability detector already gives — federation is decorative. Either failure mode kills the canon claim.

This is a clean falsifiable hypothesis. It does not depend on disputed cognitive-science definitions, AGI definitions, or the strength of the MNCA conjecture. It's a property of the substrate's stability propagation under shared subscription.

### 4.2. Methodology

#### 4.2.1. Setup

- **Platform.** Single-process two-kernel harness (WI-C1). Multi-process and distributed deployments are deferred — they introduce confounds (network jitter, clock skew) that the hypothesis isn't about.
- **Data source.** Real interaction streams, not synthetic. Use the chess-PGN dataset already used by the kernel's canonical learning task (the `chess_conformance.zig` test). Each PGN move is one Pask interaction. The dataset has known stable structure (canonical openings) which gives us ground truth without needing to invent it.
- **Configuration.** Both kernels run identical `Config` (same `MAX_NODES`, `stability_epsilon`, `min_interactions`, `prune_threshold`). This is required for K10. Config divergence is a separate experiment, out of scope here.
- **Kernel IDs.** A and B, persistent across runs. Recorded in every emitted event.

#### 4.2.2. Independent variable — overlap fraction

For each run *r*, define **overlap fraction** *φ_r ∈ {0.0, 0.1, 0.2, …, 1.0}*. Construct two interaction streams *Σ_A* and *Σ_B* from the source PGN dataset such that:
- *|Σ_A ∩ Σ_B| / |Σ_A ∪ Σ_B| = φ_r* (Jaccard),
- *|Σ_A| = |Σ_B|* (same total work per kernel),
- The shared subset is sampled uniformly at random per run, with a fixed seed for reproducibility.

#### 4.2.3. Dependent variables

For each run, after both streams are fully consumed, measure:

- *S_A* — number of stable cells in kernel A.
- *S_B* — number of stable cells in kernel B.
- *|O|* — number of cells present in both stores.
- *|S_A ∩ S_B ∩ O|* — number of cells stable in both.
- *A_r* = *|S_A ∩ S_B ∩ O| / |O|*.
- *M_r* = (*|S_A ∩ O| / |O|*) · (*|S_B ∩ O| / |O|*).
- The matrix of per-cell `(stable_A, stable_B)` outcomes restricted to *O*.

#### 4.2.4. Replication and sample size

- **Replicates per φ.** 30 runs at each overlap fraction, fresh random seed each run. 11 overlap fractions × 30 runs = 330 total runs. Cheap (the kernel is fast; runs are minutes, not hours).
- **Why 30.** Standard sample size for the central limit theorem to give meaningful confidence intervals on the mean *A − M* per overlap fraction. Larger if variance turns out high.

#### 4.2.5. Statistical test

For each *φ_r*, compute *Δ_r = A_r − M_r*. The vector of *Δ_r* values across runs is the experimental signal.

- **Primary test.** One-sample t-test against zero, per overlap fraction. H_0 rejected at φ if mean *Δ_r* is statistically distinguishable from 0 at p < 0.01.
- **Secondary test.** Linear regression of *Δ_r* on *φ_r* across all 330 runs. H_1 predicts positive slope; H_0 predicts zero slope. Report slope, R², and 95% CI.
- **Sanity test (checks K10).** At φ = 1.0, *A_r* must equal `1.0` exactly across all 30 runs — that's the determinism property under fully shared streams. Anything else indicates a non-determinism in the kernel under federation, which is a P0 substrate bug.
- **Sanity test (checks chance baseline).** At φ = 0.0, *Δ_r* must be near zero across all 30 runs. Anything else indicates a leakage path between kernels that shouldn't exist.

#### 4.2.6. Pre-registered success criteria

Before running the experiment, commit the following thresholds to `research/experiments/multiparticipant-agreement.protocol.md`:

1. **Substrate claim supported** if both:
   - Slope of *Δ* on *φ* is positive with p < 0.01 and 95% CI excluding zero, AND
   - At φ = 1.0, *A_r* = 1.0 across all replicates (K10 determinism), AND
   - At φ = 0.0, mean *Δ_r* is within 0.05 of zero (no spurious convergence).
2. **Substrate claim falsified** if any of:
   - Slope is zero or negative with p < 0.05, OR
   - Determinism fails at φ = 1.0 (P0 bug — fix before continuing), OR
   - φ = 0.0 shows non-zero *Δ* (leakage — also P0).

If neither set of criteria triggers, the result is *underpowered* and we re-run with more replicates.

#### 4.2.7. Reporting

The experiment writes:
- `research/experiments/multiparticipant-agreement.results.md` — narrative, plots, conclusions.
- `research/experiments/multiparticipant-agreement.results.csv` — per-run measurements.
- `research/experiments/multiparticipant-agreement.replay.zig` — single-binary replay that reconstructs the entire experiment from seed, for independent verification. Mirrors the kernel's existing `pask_replay_tool.zig` pattern.

If H_1 is supported, the result anchors the canon claim with a number. If H_0 fails to be rejected, the canon doc gets revised and the federation work pivots.

### 4.3. What this experiment is and isn't

**Is.** A clean falsifiable test of whether the substrate's federation primitive — overlapping Pravega subscriptions producing co-stability — does what the canon says. Pass/fail by pre-registered numerical criteria. Reproducible from seed.

**Isn't.** A test of whether the substrate produces "intelligence," "consciousness," or any of the MNCA paper's deeper conjectures. Those are out of scope and explicitly named as out of scope in `research/cognition-framework.md` §4 Gap 6. This experiment validates one specific computational property that the rest of the framework rests on, with a number and a confidence interval.

### 4.4. Path from experiment to published claim

1. WI-C1 lands (two-kernel harness with deterministic conformance).
2. The pre-registered protocol commits to `research/experiments/multiparticipant-agreement.protocol.md`.
3. The experiment runs; results commit alongside.
4. If H_1 is supported, the canon doc gets a "validated empirically by experiment X at commit Y" reference.
5. If H_0 cannot be rejected, the canon doc gets revised — federation as currently specified isn't doing what we said. Likely fix candidates: (a) interaction strength weighting differs across kernels in a way the test caught, (b) edge-trend computation interacts badly with partial overlap, (c) the stability epsilon needs to be tighter. Each is a separate work item.

---

## 5. The connection back

The plan above is *not* an attempt to build AGI on a blockchain. It's an attempt to make the substrate's three-order cybernetic claims testable, and to make the analogical-reasoning layer that closes the gap between Pask stability and Pask teachback empirically grounded. The MNCA paper's framing — generalist agents, Mandala topology, deterministic+probabilistic split, blockchain anchor — is the canon's frame for what is being implemented; the cybernetic-orders doc is the canon's frame for *why* the implementation is layered the way it is; this plan is *how* it gets built and tested.

The deliverable, per `cognition-framework.md` §5, remains three things:
1. A formally-grounded analogical layer (Tier B closes this).
2. A computational substrate for Paskian distributed cognition (Tier C closes this; §4 of this doc proves it).
3. An auditable society of generalist agents (Tier D closes this).

The AGI question stays where the MNCA paper leaves it.
