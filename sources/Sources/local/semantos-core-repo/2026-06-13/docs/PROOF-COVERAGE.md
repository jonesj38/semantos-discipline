---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PROOF-COVERAGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.332211+00:00
---

# Proof Coverage Map — Claims × Proof Status

**Status:** Skeleton (D-Dform-coverage per §11.2 of UNIFICATION-ROADMAP). Populated as D-Dform-property (property-test derivation) lands.
**Date:** 2026-05-13
**Author:** Tier-B burst iter 9
**Purpose:** Honest reckoning of which substrate-paper claims are backed by which artifact (Lean theorem, property test, integration test) — replaces the unqualified "mathematically proven correct" framing per §11 GD3.

---

## 1. What "proved" actually means

The substrate ships three kinds of artifacts that argue for correctness, and they're not interchangeable:

| Artifact | What it proves | What it doesn't prove |
|---|---|---|
| **Lean 4 theorem** | A property holds in the *abstract specification* of the kernel | The running Zig/TypeScript code matches the spec |
| **Property test** | A property holds across a large random sample of inputs | All cases (only the sampled ones, with shrinking) |
| **Integration test** | A specific scenario works end-to-end | Generalization to untested scenarios |
| **Mutation test** | Tests catch deliberate code corruption | Anything the mutations don't model |

Public framing should NOT say "mathematically proven correct" without qualifying which artifact backs it. The four are complementary, not equivalent.

---

## 2. Kernel invariants (K1–K14) — current state

The K-invariants are documented in `docs/FORMAL-VERIFICATION-STRATEGY.md`. Lean theorems live under `proofs/lean/Semantos/Theorems/`. All Lean files contain explicit "no `sorry`, no `admit`" comments and grep confirms zero unfilled holes.

| Invariant | Statement | Lean theorem | Spec ref | Status |
|---|---|---|---|---|
| **K1** | Linearity — LINEAR cells never duplicated, never silently discarded | [`LinearityK1.lean`](../proofs/lean/Semantos/Theorems/LinearityK1.lean) | [`Linearity.tla`](../proofs/tla/Linearity.tla) (NEW 2026-05-13) | ✓ **both sides** |
| **K2** | Authorization soundness — authenticated state changes require identity proof | [`AuthSoundnessK2.lean`](../proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean) | `ReplayPrevention.tla` + `CertRevocation.tla` (partial supplements) | ⚠ partial both — Lean primary; TLA+ covers replay + revocation sub-properties |
| **K3** | Domain isolation — `OP_CHECKDOMAINFLAG` rejects on mismatch | [`DomainIsolationK3.lean`](../proofs/lean/Semantos/Theorems/DomainIsolationK3.lean) | `ZoneBoundary.tla` + `SemanticTypes.tla` + `ReactorIsolation.tla` (supplement) | ✓ **both sides** |
| **K4** | Failure atomicity — failed Plexus opcodes leave state byte-identical | [`FailureAtomicK4.lean`](../proofs/lean/Semantos/Theorems/FailureAtomicK4.lean) + per-op `_error_inversion` + `_atomic` lemmas | [`FailureAtomicity.tla`](../proofs/tla/FailureAtomicity.tla) (NEW 2026-05-13) | ✓ **both sides** (plus `plexus_atomic_fuzz.zig` empirical) |
| **K5** | Deterministic termination — no loops, bounded opcount, bounded stack | [`TerminationK5.lean`](../proofs/lean/Semantos/Theorems/TerminationK5.lean) | — (TLA+ adds little; bounded by construction) | Lean only (intentional) |
| **K6** | Hash-chain integrity — prevStateHash append-only chain, externally anchored | [`HashChainIntegrityK6.lean`](../proofs/lean/Semantos/Theorems/HashChainIntegrityK6.lean) (NEW 2026-05-13) | `EvidenceChain.tla` | ✓ **both sides** |
| **K7** | Cell immutability — header read-only after packing | [`CellImmutabilityK7.lean`](../proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean) | [`CellImmutability.tla`](../proofs/tla/CellImmutability.tla) (NEW 2026-05-13) | ✓ **both sides** |
| **K8** | Demotion safety — only LINEAR→{AFFINE, RELEVANT}; no promotions | [`DemotionK8.lean`](../proofs/lean/Semantos/Theorems/DemotionK8.lean) | `DemotionSafety.tla` | ✓ **both sides** |
| **K9** | Canonical temporal morphism — coarse-grained timelines preserve causal order from fine-grained | [`TemporalMorphismK9.lean`](../proofs/lean/Semantos/Theorems/TemporalMorphismK9.lean) | `TransactionDAG.tla` | ✓ **both sides** |
| **K10** | Turing completeness (negative) — kernel is *not* Turing complete | [`TuringCompletenessK10.lean`](../proofs/lean/Semantos/Theorems/TuringCompletenessK10.lean) | n/a (TLA+ inapplicable for negative property over instruction set) | Lean only (intentional) |
| **K11** | Sign soundness — `OP_SIGN` consumes LINEAR keys; signatures verify; error paths atomic | [`SignSoundnessK11.lean`](../proofs/lean/Semantos/Theorems/SignSoundnessK11.lean) | n/a (TLA+ can't model SHA/ECDSA — they stay axiomatic in Lean) | Lean only (intentional) |
| **K12** | Key custody — LINEAR tier-key cells cannot be duplicated | [`KeyCustodyK12.lean`](../proofs/lean/Semantos/Theorems/KeyCustodyK12.lean) | `KeyCustody.tla` + `TierEscalation.tla` | ✓ **both sides** |
| **K13** | Budget monotonicity — `OP_DECREMENT_BUDGET` decreases; `OP_REFILL_BUDGET` increases | [`BudgetMonotonicityK13.lean`](../proofs/lean/Semantos/Theorems/BudgetMonotonicityK13.lean) | `MeteringFSM.tla` | ✓ **both sides** |
| **K14** | Vault multisig — vault tier requires N-of-M signatures over correct domain | [`VaultMultisigK14.lean`](../proofs/lean/Semantos/Theorems/VaultMultisigK14.lean) | `VaultCooldownNsequence.tla` | ✓ **both sides** |

**Summary 2026-05-13 (post-Phase-P1 + P3 forward-looking):** **13 of 18 K-invariants have both-sides coverage** (K1, K3, K4, K6, K7, K8, K9, K12, K13, K14 base + K15, K17, K18 proposed). K10 + K11 are inherently Lean-only. K5 is intentional Lean-only (bounded termination is structural). K2 has partial TLA+ coverage via existing specs (`ReplayPrevention`, `CertRevocation`) covering replay + revocation sub-properties. K16 (input-mode equivalence) remains genuinely gated on D-Dlex-voice — needs SIR runtime to formalize against.

### Proposed K-invariants from §11.2 — forward-looking specs

| K | Statement | Lean | TLA+ | Status |
|---|---|---|---|---|
| **K15** | Capability-UTXO binding | [`CapabilityUtxoK15.lean`](../proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean) (NEW 2026-05-13) | [`CapabilityRace.tla`](../proofs/tla/CapabilityRace.tla) (NEW 2026-05-13) | ✓ **both sides** — forward-looking; D-Dcap-engine must conform |
| **K16** | Input-mode equivalence | — | — | gated on D-Dlex-voice (no SIR runtime to formalize against) |
| **K17** | Tree-of-chains merge | [`TreeOfChainsK17.lean`](../proofs/lean/Semantos/Theorems/TreeOfChainsK17.lean) (NEW 2026-05-13) | [`TreeOfChainsMerge.tla`](../proofs/tla/TreeOfChainsMerge.tla) (NEW 2026-05-13) | ✓ **both sides** — forward-looking; D-E-md must conform |
| **K18** | Federation propagation independence | [`FederationPropagationK18.lean`](../proofs/lean/Semantos/Theorems/FederationPropagationK18.lean) (NEW 2026-05-13) | [`FederationPropagation.tla`](../proofs/tla/FederationPropagation.tla) (NEW 2026-05-13) | ✓ **both sides** — algebraic core (Lean) + distributed-protocol traces (TLA+); anti-claim test for "20 Hz orders all cells" |

**Standalone TLA+ specs mapped as K-supplements (D-Proof-4 / D-Proof-5):**
- `ReplayPrevention.tla` → K2 supplement (no double-consume; OP_SIGN per-leaf uniqueness; BRC-42 monotonic-index)
- `CertRevocation.tla` → K2 supplement (revocation immediacy)
- `ReactorIsolation.tla` → K3 supplement (runtime-level domain isolation)
- `PartitionResilience.tla` → reserved for K18 (federation propagation) once authored
- `RecoveryFlow.tla` → axis-F (recovery) coverage, not a K-invariant
- `SemanticTypes.tla` → K3 supplement (base types + linearity invariant)

---

## 3. Extension-specific theorems (Oddjobz)

The Oddjobz extension ships its own per-extension invariants, proved separately:

| Invariant | Statement | Lean theorem | Status |
|---|---|---|---|
| K2a (Oddjobz auth) | Per-FSM authorization at transition boundaries | [`Extensions/Oddjobz/StateMachines/JobFSM.lean`](../proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/JobFSM.lean) + sibling FSMs | ✓ proved |
| K3a (Oddjobz domain) | Per-extension domain isolation | [`Capabilities/Oddjobz.lean`](../proofs/lean/Semantos/Capabilities/Oddjobz.lean) | ✓ proved |
| K11a-c, K13a-c, K14a-c | Per-FSM analogues for sign / budget / vault | (Common.lean + per-FSM) | ✓ proved |

These are the "extension is built Plexus-native from day one" exemplar (referenced in `docs/prd/UNIFICATION-ROADMAP.md` §2 A6 row narrative).

---

## 4. Other Lean coverage (beyond K-invariants)

The `proofs/lean/Semantos/` tree contains 53 files. Beyond the K-invariant theorems above, the coverage groups:

### Category theory (foundational)

- [`Category.lean`](../proofs/lean/Semantos/Category.lean) — Reflexivity, transitivity, antisymmetry of taxonomy refinement (`TaxPath` ordering). Foundational for lexicon hierarchy.

### Substrate types

- [`Substrate/Types.lean`](../proofs/lean/Semantos/Substrate/Types.lean) — Cell, header, payload type definitions
- [`Substrate/Diff.lean`](../proofs/lean/Semantos/Substrate/Diff.lean) — Patch / diff algebra
- [`Substrate/Merge.lean`](../proofs/lean/Semantos/Substrate/Merge.lean) — Merge semantics
- [`Substrate/Lexicon.lean`](../proofs/lean/Semantos/Substrate/Lexicon.lean) — Lexicon registration

### Cell + executor base

- [`Cell.lean`](../proofs/lean/Semantos/Cell.lean) — Cell shape, invariants
- [`Linearity.lean`](../proofs/lean/Semantos/Linearity.lean) — Linearity class algebra (underlies K1)
- [`PDA.lean`](../proofs/lean/Semantos/PDA.lean) + [`BoundedStack.lean`](../proofs/lean/Semantos/BoundedStack.lean) — Two-stack PDA model (underlies K5)
- [`Executor.lean`](../proofs/lean/Semantos/Executor.lean) — Execution step relation (`step_advances`, `step_pc_increases`, `step_opcount_increases`, `step_at_limit`, `step_total`)
- [`CryptoAxioms.lean`](../proofs/lean/Semantos/CryptoAxioms.lean) — Treated-as-axiomatic primitives (ECDSA, SHA-256) — the irreducible base

### Opcodes (per-family)

- [`Opcodes/Standard.lean`](../proofs/lean/Semantos/Opcodes/Standard.lean) — Bitcoin Script standard ops
- [`Opcodes/Plexus.lean`](../proofs/lean/Semantos/Opcodes/Plexus.lean) — Plexus extension ops 0xC0–0xCF
- [`Opcodes/Budget.lean`](../proofs/lean/Semantos/Opcodes/Budget.lean) — OP_DECREMENT_BUDGET / OP_REFILL_BUDGET (underlies K13)
- [`Opcodes/Sign.lean`](../proofs/lean/Semantos/Opcodes/Sign.lean) — OP_SIGN (underlies K11)
- [`Opcodes/Classify.lean`](../proofs/lean/Semantos/Opcodes/Classify.lean) — Opcode classification
- [`Opcodes/HostCall.lean`](../proofs/lean/Semantos/Opcodes/HostCall.lean) — Host-call boundary

### Federation

- [`Federation/Convergence.lean`](../proofs/lean/Semantos/Federation/Convergence.lean) — Convergence properties of distributed cell state
- [`Federation/Invariants.lean`](../proofs/lean/Semantos/Federation/Invariants.lean) — Cross-node invariants

### Lexicons (per-vertical)

Each domain lexicon has its own Lean module proving the lexicon's type rules are coherent:

- [`Lexicons/Jural.lean`](../proofs/lean/Semantos/Lexicons/Jural.lean) — Jural relations (Hohfeldian)
- [`Lexicons/CDM.lean`](../proofs/lean/Semantos/Lexicons/CDM.lean) — ISDA CDM lifecycle
- [`Lexicons/PropertyManagement.lean`](../proofs/lean/Semantos/Lexicons/PropertyManagement.lean) — re-desk domain
- [`Lexicons/Trades.lean`](../proofs/lean/Semantos/Lexicons/Trades.lean) — oddjobz domain
- [`Lexicons/BillsOfLading.lean`](../proofs/lean/Semantos/Lexicons/BillsOfLading.lean)
- [`Lexicons/ControlSystems.lean`](../proofs/lean/Semantos/Lexicons/ControlSystems.lean) — SCADA domain
- [`Lexicons/CircuitCommands.lean`](../proofs/lean/Semantos/Lexicons/CircuitCommands.lean)
- [`Lexicons/ProjectManagement.lean`](../proofs/lean/Semantos/Lexicons/ProjectManagement.lean)
- [`Lexicons/RiskAssessment.lean`](../proofs/lean/Semantos/Lexicons/RiskAssessment.lean)

### Legal cards (cross-vertical jural objects)

- [`LegalCards/Types.lean`](../proofs/lean/Semantos/LegalCards/Types.lean) — base types
- [`LegalCards/Diff.lean`](../proofs/lean/Semantos/LegalCards/Diff.lean) — diff semantics
- [`LegalCards/Merge.lean`](../proofs/lean/Semantos/LegalCards/Merge.lean) — merge semantics
- [`LegalCards/RoundTrip.lean`](../proofs/lean/Semantos/LegalCards/RoundTrip.lean) — encode/decode round-trip
- [`LegalCards/Render.lean`](../proofs/lean/Semantos/LegalCards/Render.lean) — render to user-readable form

---

## 5. Public-facing claims × proof status

Mapping the substrate paper's load-bearing claims to actual artifact backing:

| Claim | Lean | Property test | Integration test | Status |
|---|---|---|---|---|
| "Cells are mathematically impossible to duplicate or drop silently" (K1) | ✓ LinearityK1 | ✗ (D-Dform-property) | ⚠ partial (cell-engine conformance tests) | ⚠ spec-proved; runtime relies on conformance |
| "Failed executions leave state byte-identical" (K4) | ✓ FailureAtomicK4 + per-op | ✗ (D-Dform-property) | ✓ `plexus_atomic_fuzz.zig` empirical | ⚠ spec-proved + fuzzed |
| "Every execution terminates in bounded opcount" (K5) | ✓ TerminationK5 | ✗ | ⚠ partial | ⚠ spec-proved |
| "Capability tokens bound to on-chain UTXOs" | ✗ (D-Dcap-engine pending) | ✗ | ✗ | ✗ aspirational — current code is bearer tokens |
| "Universal intent pipeline closes the API loophole" | ✗ (D-IP-equiv pending K15) | ✗ | ✗ | ✗ aspirational — chat.ts emits JSON not cells |
| "Hash chains give every change a verifiable order" (K6) | ✗ (TLA+ only) | ✗ | ⚠ partial | ⚠ TLA+ model-checked; no Lean |
| "1024-byte cells aligned across UDP / LMDB / WASM / SHA" | n/a (architectural, not invariant) | n/a | ✓ `constants.test.ts` pins | ✓ pinned by test |
| "Federation rides transport-agnostic NetworkAdapter" | ✗ (Federation/Invariants.lean covers some) | ✗ (D-C6c pending) | ⚠ partial | ⚠ code shipped; no contract suite |
| "Tree-of-chains for collaborative documents" (D-E-md) | ✗ | ✗ | ✗ | ✗ design-only |
| "BRC-52 cert binds every actor" | n/a | ✗ | ⚠ partial (D-A1..D-A7 staged) | ⚠ staged per §5 |
| "Lean-4 proofs back the substrate" | ✓ (this doc) | n/a | n/a | ✓ but qualify: theorems over spec, not extracted from code |

---

## 6. The gap that motivates this doc

Lean theorems prove properties of an **abstract specification**, not of the running code. The path from spec to running code goes:

```
Lean spec (theorems hold)
   │
   │ informal correspondence — engineer reads spec, writes Zig
   │ verified by: conformance tests, fuzz, manual review
   │
   ▼
Zig / TypeScript implementation
   │
   │ compilation
   │
   ▼
Running binary
```

Each transition is a place divergence can hide:

- **Spec → Zig:** the engineer might misread the spec, miss a corner case, choose a different algorithm with subtly different behavior
- **Zig → binary:** compiler bugs (unlikely but non-zero)

The substrate paper's "mathematically proven" framing implies all three boxes are equivalent. They are not.

**What closes the gap:**

1. **D-Dform-property** (§11.2): Property tests *derived from theorem statements*. Same property, generated test inputs, exercised on the running implementation. Catches divergence at the spec→Zig boundary.
2. **D-Dform-mechanized** (future / out of scope per GD6): Extract the implementation from Lean. The Lean text *is* the source. Eliminates the spec→Zig divergence by construction. Out of scope per §11.6 GD6.
3. **Differential testing**: Same input through two implementations (Zig + TS); compare outputs. Catches single-implementation bugs.
4. **Mutation testing**: Deliberately corrupt the code; verify tests catch it. Existing tooling claims "100% mutation kill rate" per FORMAL-VERIFICATION-STRATEGY.md line 563.

Today's coverage uses (3) and (4) implicitly via the conformance-test discipline. (1) and (2) are the §11 supplement work.

---

## 7. Proposed new K-invariants (from §11.2)

These don't exist yet; D-Dform-property + new Lean files would add them:

| Proposed | Source | What it proves |
|---|---|---|
| **K15 (Capability-UTXO binding)** | §11.2 D-Dcap-engine, W-CAP-7 | OP_CHECKCAPABILITY succeeds ↔ UTXO unspent ∧ cert proves ownership ∧ domain matches |
| **K16 (Input-mode equivalence)** | §11.2 D-IP-5 | All 5 input modes (voice, click, NL, ballot, batch) lower to identical SIR for equivalent intent |
| **K17 (Tree-of-chains merge)** | §11.2 D-E-md, governance Q4 | Multi-parent merge cells preserve hash-chain integrity; merge is associative + commutative within branch policy |
| **K18 (Federation propagation)** | §11.2 D-W3, D-C6 | Cells propagate via NetworkAdapter independent of world-host tick |

These are the K-invariants the §11 work is trying to add. The first three are explicitly anti-claims for the gaps named in §11.1 G1, G2, G6.

---

## 8. Honest framing for public communication

The substrate paper's claim should land as:

> The Semantos substrate ships 13 mechanically-verified Lean 4 theorems (K1, K2, K3, K4, K5, K7, K8, K9, K10, K11, K12, K13, K14) covering linearity, authorization, domain isolation, failure atomicity, termination, cell immutability, demotion safety, temporal morphism, non-Turing-completeness, and cryptographic operations. Theorems are over an abstract 2-PDA model. K6 (hash-chain integrity) is TLA+ model-checked rather than Lean-proved. Conformance to the running Zig/TypeScript implementation is checked via a fuzz suite, differential testing, and a property-test layer derived from theorem statements (D-Dform-property, in flight). The runtime is not mechanically extracted from Lean — the proofs are witness artifacts, not source of truth.

Not: *"correct by construction."* That overshoots. The constructions are correct; whether the running code matches the construction is a separate question that conformance testing addresses.

---

## 9. Maintenance

This doc is a **skeleton**. Maintenance steps as the §11 work lands:

1. As each D-Dform-property property-test lands, flip the ✗ in column 2 of §5 to ✓
2. As each new K-invariant theorem lands (K15-K18 per §7), add a row to §2 and §5
3. As mechanized extraction lands (future, per GD6), update §6 to reflect collapsed gap
4. Quarterly: re-run `grep -rn "sorry\|admit" proofs/lean/Semantos/` and confirm zero unfilled

Single source of truth for "what's proved" — anyone making a claim about the substrate's verifiability should reference this doc.

---

## 10. Sources referenced

- `docs/FORMAL-VERIFICATION-STRATEGY.md` — K1–K14 statements + Zig file references
- `proofs/lean/Semantos/Theorems/*.lean` — 13 K-invariant theorems
- `proofs/lean/Semantos/Capabilities/Oddjobz.lean` — Oddjobz-specific K2a, K3a
- `proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/*.lean` — per-FSM Oddjobz theorems
- `proofs/lean/Semantos/Lexicons/*.lean` — 9 lexicon-specific theorem files
- `proofs/lean/Semantos/LegalCards/*.lean` — cross-vertical jural object theorems (5 files)
- `proofs/lean/Semantos/Federation/{Convergence,Invariants}.lean` — federation properties
- `proofs/lean/Semantos/Substrate/*.lean` — base substrate types (4 files)
- `proofs/lean/Semantos/Opcodes/*.lean` — per-opcode-family theorems (6 files)
- `proofs/lean/Semantos/{Cell,Linearity,PDA,BoundedStack,Executor,Category,CryptoAxioms}.lean` — foundational lemmas
- `docs/prd/UNIFICATION-ROADMAP.md` §11 — D-Dform-property and D-Dform-coverage deliverables; GD6 mechanized extraction out of scope
- `core/cell-engine/tests/plexus_atomic_fuzz.zig` — empirical K4 coverage

53 Lean files. Zero `sorry`. Zero `admit`. 13 K-invariants formalized. K6 in TLA+. **Honest framing wins over impressive framing — that's the point of this doc.**
