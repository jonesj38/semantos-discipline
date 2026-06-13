---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.341066+00:00
---

# TLA+ Protocol Verification — Phase 11.5

Model-checked verification of Semantos protocol-layer properties using TLA+/TLC.
These specs complement the Phase 11 Lean 4 kernel proofs (K1–K5, K7) by verifying
distributed and concurrent behaviors that sequential theorem proving cannot express.

## Specs

| File | Property | Source |
|------|----------|--------|
| SemanticTypes.tla | Base types + linearity invariant | semantic-objects.ts, validator.ts |
| EvidenceChain.tla | Append-only chain integrity | cell-header.ts (prevStateHash) |
| ReplayPrevention.tla | No double-consume under concurrency; OP_SIGN per-leaf uniqueness; BRC-42 monotonic-index allocator atomicity (WT3) | validator.ts (validateConsumption); WALLET-TIER-CUSTODY 3.5; W3.5 DerivationStateStore |
| CertRevocation.tla | Revocation immediacy | validator.ts (validateRevocation) |
| MeteringFSM.tla | 8-state FSM correctness | channel-fsm.ts (transition table) |
| ZoneBoundary.tla | Domain flag zone enforcement | domain-flags.ts |
| PartitionResilience.tla | Partition tolerance + reconciliation | protocol design |
| DemotionSafety.tla | Linearity demotion safety | linearity.zig |
| TransactionDAG.tla | DAG ordering + acyclicity | transaction-dags.md |
| KeyCustody.tla (WT1) | Per-tier-key state machine + cross-actor concurrency: NoConcurrentDecrypt, NoResurrection, RecoveryRequiresEnrollment, TierFactorRespected | WALLET-TIER-CUSTODY 9.2 |
| TierEscalation.tla (WT2) | Tier classification + factor matching + Tier-3 cooldown over a sequence of spends | WALLET-TIER-CUSTODY 9.2 |
| RecoveryFlow.tla | Plexus disaster-recovery protocol — refines KeyCustody's BeginRecovery to a 4-step round-trip with OTP rate limiting, challenge-answer hashing, and adversarial-actor safety (envelope-requires-correct-answers, seed-requires-envelope-and-answers, adversary-cannot-complete) | WALLET-TIER-CUSTODY 7.7, 7.8, 8.1, 8.2; W7 dispatch.ts + envelope.ts |
| Linearity.tla | K1 (Linearity) trace-level — no LINEAR cell duplicated (K1a), structurally enforced no-silent-discard via DropMain gate (K1b), no reappearance after consume (K1c). Companion to `proofs/lean/Semantos/Theorems/LinearityK1.lean`. | core/cell-engine/src/linearity.zig; D-Proof-1 per UNIFICATION-ROADMAP.md §11.7.4 |
| FailureAtomicity.tla | K4 (Failure atomicity) implementation pattern check — peek-then-mutate (correct) vs mutate-then-check (buggy K4-violation). On every failure transition, post-state equals pre-state snapshot. Companion to `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean` (per-op `_error_inversion` lemmas). | core/cell-engine/OPCODE-HARDENING-PLAN.md; D-Proof-2 per UNIFICATION-ROADMAP.md §11.7.4 |
| CellImmutability.tla | K7 (Cell immutability) trace-level — current header bytes equal original header bytes for every created cell. OP_DEMOTE modeled correctly (creates new AFFINE cell, leaves original LINEAR cell's header intact). Companion to `proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean`. | core/cell-engine/src/cellPacker.zig; D-Proof-3 per UNIFICATION-ROADMAP.md §11.7.4 |
| CapabilityRace.tla | K15 (Capability-UTXO binding) concurrent-spend race property — at most one of N racing actors successfully spends a capability UTXO; the others fail with K4 rollback. Companion to `proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean`. | BRC-108 + BRC-115 5-stage verification; D-Proof-7 per UNIFICATION-ROADMAP.md §11.7.4 |
| FederationPropagation.tla | K18 (Federation propagation independence) — cells propagate via NetworkAdapter regardless of world-host tick state. Anti-claim test for the "20 Hz tick orders all cells" misclassification (chapter 36 §36.7). Companion to `proofs/lean/Semantos/Theorems/FederationPropagationK18.lean`. | docs/textbook/36-federation-transport.md; D-Proof-10 per UNIFICATION-ROADMAP.md §11.7.4 |
| TreeOfChainsMerge.tla | K17 (Tree-of-chains merge integrity) — concurrent editors converging on a merge cell with two parent-hashes. Merge tip is determined by (parent₁, parent₂, commit). Companion to `proofs/lean/Semantos/Theorems/TreeOfChainsK17.lean`. | §8 Q4 governance (2026-04-26); D-Proof-9 per UNIFICATION-ROADMAP.md §11.7.4 |

## Running

```bash
# Install TLC (requires Java 17+)
make setup

# Check all specs
make check

# Check a single spec
make EvidenceChain
```

## Abstractions

### Hash-as-Injection

SHA-256 is modeled as an injective function over a finite set of model values.
TLC cannot reason about cryptographic hash functions directly, so we assume:

```
ASSUME \A x, y \in HashDomain : Hash(x) = Hash(y) => x = y
```

This is sound because SHA-256 is collision-resistant (no known collision exists).
The injective model is strictly stronger than collision-resistance — if a property
holds under injection, it holds under collision-resistance.

### prevStateHash Correction

The Phase 11.5 PRD stated that `prevStateHash` does not exist in `semantic-objects.ts`.
This is true but misleading. `prevStateHash` is a concrete 32-byte field in the cell
header binary format:

- **packages/protocol-types/src/cell-header.ts** line 41: `prevStateHash: Uint8Array`
- Binary offset 128, 32 bytes (HeaderOffsets.commercePrevState)
- Also in **src/cell-engine/typeHashRegistry.ts** line 133: `prevStateHash: Buffer`

The evidence chain (EvidenceChain.tla) models this actual implementation field,
not an abstract protocol concept. Each cell's `prevStateHash` links to the hash
of the previous cell, forming the append-only evidence chain.

### Time-as-Counter

Unix timestamps are modeled as monotonically increasing natural numbers.
This abstracts away wall-clock time while preserving temporal ordering.
