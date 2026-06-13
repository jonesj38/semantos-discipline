---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PROOFS-WT-TLA-EXTENSION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.731428+00:00
---

# Wallet TLA+ Extension Plan — WT1–WT3

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` §9.2, `docs/design/PROOFS-WALLET-EXTENSION-PLAN.md`, `docs/design/PROOFS-WP9-K4-PROMOTION.md`, `proofs/tla/README.md`, `proofs/tla/Makefile`

---

## 0. Purpose

Close out the wallet's TLA+ obligations from `WALLET-TIER-CUSTODY.md` §9.2. The Lean layer (K1–K13, with K4 substantively promoted in WP9) covers per-opcode structural properties. TLA+ uniquely covers what Lean can't: **multi-step temporal and concurrency claims** about how keys flow through the unlock → sign → lock → recovery cycle, how tier escalation behaves under simultaneous tabs/sessions, and how OP_SIGN's nonce / sighash discipline prevents signature replay.

When WT1–WT3 land, the wallet's trust story is layered three ways: Lean per-opcode soundness (K1–K13) + TLA+ multi-step safety/liveness (KeyCustody, TierEscalation, ReplayPrevention) + Zig empirical fuzz/differential coverage. Each layer catches a class of regression the others can't.

---

## 1. Current State

The repo has 9 model-checked TLA+ specs, all wallet-unrelated:

| File | Property |
|---|---|
| `SemanticTypes.tla` | Base types + linearity invariant |
| `EvidenceChain.tla` | Append-only chain integrity |
| `ReplayPrevention.tla` | No double-consume under concurrency |
| `CertRevocation.tla` | Revocation immediacy |
| `MeteringFSM.tla` | 8-state FSM correctness |
| `ZoneBoundary.tla` | Domain flag zone enforcement |
| `PartitionResilience.tla` | Partition tolerance + reconciliation |
| `DemotionSafety.tla` | Linearity demotion safety |
| `TransactionDAG.tla` | DAG ordering + acyclicity |

Wallet design doc §9.2 specified three TLA+ deliverables, **none of which exist**:

| Specified | Status |
|---|---|
| `KeyCustody.tla` — per-tier-key state machine + safety invariants | missing |
| `TierEscalation.tla` — tier classification + cooldown | missing |
| Extension to `ReplayPrevention.tla` for OP_SIGN nonces | not started |

Infrastructure is fully in place — `Makefile` runs TLC (TLA+ model checker) over each `.tla` + `.cfg` pair via `make check`, with a vacuous-model guard that fails if `0 distinct states found`.

---

## 2. Phases

### WT1 — `KeyCustody.tla` (~ 1 day)

**Goal**: model the lifecycle of every tier key as a finite state machine and prove it satisfies the security invariants from the wallet design doc.

**The state machine**

For each key K (one per tier per identity):

```
            Unlock(auth)         Sign
encrypted_at_rest ─────────► decrypted_in_engine ─────► consumed
       ▲                              │                    │
       │                              ▼                    │
       │ Lock                                              │
       └─────────────────────────────                      │
                                                            │
                            Recovery(otp ∧ challenge)       │
       reconstructible_via_plexus ◄─────────────────────────┘
                       │
                       ▼ ReseedFromMnemonic
            encrypted_at_rest
```

**Actors**: multiple concurrent actors model browser tabs / sovereign-node sessions / recovery flows happening simultaneously.

**Variables**:

```tla
VARIABLES
    keyState,        \* Function: Keys -> {"encrypted", "decrypted", "consumed", "recoverable"}
    decryptedBy,     \* Function: Keys -> Actors \cup {NULL} — who unlocked
    consumedTxId,    \* Function: Keys -> TxIds \cup {NULL} — single-use tracking
    plexusEnrolled,  \* Function: Identities -> BOOLEAN — opt-in recovery flag
    sessionAuth      \* Function: Actors -> Set of (TierLevel, FactorKind) pairs proven this session
```

**Actions**:

- `Unlock(k, actor, factor)` — guard: `keyState[k] = "encrypted"` ∧ `factor` satisfies `requiredFactor(k.tier)` ∧ no other actor currently has it decrypted. Effect: `keyState[k]' = "decrypted"`, `decryptedBy[k]' = actor`.
- `Sign(k, actor, txId)` — guard: `keyState[k] = "decrypted"` ∧ `decryptedBy[k] = actor`. Effect: `keyState[k]' = "consumed"`, `consumedTxId[k]' = txId`.
- `Lock(k, actor)` — guard: `keyState[k] = "decrypted"` ∧ `decryptedBy[k] = actor`. Effect: `keyState[k]' = "encrypted"`.
- `RecoverViaPlexus(k, actor, otp, challenge)` — guard: `keyState[k] = "consumed"` ∧ `plexusEnrolled[identity] = TRUE` ∧ valid OTP ∧ valid challenge hashes. Effect: `keyState[k]' = "recoverable"`.
- `ReseedFromMnemonic(k, actor, mnemonic)` — guard: `keyState[k] ∈ {"consumed", "recoverable"}` ∧ valid BIP39. Effect: `keyState[k]' = "encrypted"` (re-derive and re-encrypt).

**Safety invariants** (model-checked):

| Invariant | Statement |
|---|---|
| `INV-NoResurrection` | `∀ k : keyState[k] = "consumed" ⟹ ◯(keyState[k] ≠ "decrypted")` — a consumed key cannot directly transition to decrypted; must go through `recoverable` first. (Captures the "linearity in time" property — once a single-use leaf is signed, it's gone unless explicitly reconstructed.) |
| `INV-NoConcurrentDecrypt` | `∀ k : keyState[k] = "decrypted" ⟹ decryptedBy[k] ≠ NULL ∧ ∀ a₁, a₂ : (a₁ ≠ a₂ ⟹ ¬(decryptedBy[k] = a₁ ∧ decryptedBy[k] = a₂))` — at most one actor can hold a key decrypted at any time. |
| `INV-SignRequiresUnlock` | `∀ k, txId : consumedTxId[k] = txId ⟹ ∃ prior state where keyState[k] = "decrypted"` — every Sign action implies a prior Unlock action by the same actor. |
| `INV-RecoveryRequiresEnrollment` | `∀ k : keyState[k] = "recoverable" ⟹ plexusEnrolled[identityOf(k)] = TRUE` — recovery is only available if the identity opted in (G4 of the wallet design doc). |
| `INV-TierFactorRespected` | `∀ k : keyState[k] = "decrypted" ⟹ (k.tier, requiredFactor(k.tier)) ∈ sessionAuth[decryptedBy[k]]` — the auth factor matching the tier was proven before unlock. |

**Liveness obligations** (checked under fairness):

| Obligation | Statement |
|---|---|
| `LIVE-RecoveryAvailable` | `□ (keyState[k] = "consumed" ∧ plexusEnrolled[identityOf(k)] ⟹ ◇ keyState[k] ∈ {"recoverable", "encrypted"})` — a consumed key is eventually recoverable if Plexus enrollment holds. |
| `LIVE-SpendCompletes` | `□ ((∃ a : Unlock(k, a, f) enabled ∧ Sign(k, a, _) enabled) ⟹ ◇ keyState[k] = "consumed")` — any well-formed unlock+sign pair eventually completes. |

**Constants** (the `.cfg`):

```
CONSTANTS
    Identities  = {id1, id2}
    TierLevels  = {0, 1, 2, 3}
    Keys        = {k0_id1, k1_id1, k2_id1, k3_id1, k0_id2, k1_id2, k2_id2, k3_id2}
    Actors      = {tab1, tab2, node1}
    TxIds       = {tx1, tx2, tx3, tx4}
    FactorKinds = {NONE, PIN, BIOMETRIC, VAULT}
    NULL        = NULL
INVARIANTS
    INV_NoResurrection
    INV_NoConcurrentDecrypt
    INV_SignRequiresUnlock
    INV_RecoveryRequiresEnrollment
    INV_TierFactorRespected
PROPERTIES
    LIVE_RecoveryAvailable
    LIVE_SpendCompletes
```

Model size with these constants: 4 keys per identity × 2 identities × small action space — well within TLC's tractable range.

**Deliverables**:

1. `proofs/tla/KeyCustody.tla` — full spec.
2. `proofs/tla/KeyCustody.cfg` — TLC configuration.
3. `make check-keycustody` (extends Makefile `SPECS` list) — runs TLC, must report `0 violations` and not be vacuous.
4. README.md table updated.

**Success criterion**: `make KeyCustody` reports `Model checking completed. No error has been found.` AND TLC reports >100 distinct states (non-vacuous).

---

### WT2 — `TierEscalation.tla` (~ 1 day)

**Goal**: model the tier-classification and cooldown logic as a temporal property over a sequence of spends, prove tier discipline is enforced.

**The state machine**

A wallet processes a sequence of spend requests. For each request:

1. `Classify(amount)` returns a tier `T ∈ {0, 1, 2, 3}` based on the policy cell's sat-denominated thresholds (default 1M / 10M / 100M).
2. `requireFactor(T)` returns the auth factor for tier T (NONE, PIN, BIOMETRIC, VAULT).
3. `presentFactor(actor, factor)` either succeeds (auth proven, valid for the session window) or fails.
4. `enforceCooldown(T)` for T = 3 requires `now - lastT3SpendTime ≥ COOLDOWN_SECONDS`.
5. `signAt(T)` proceeds only if classify, factor, cooldown all pass.

**Variables**:

```tla
VARIABLES
    pendingSpends,    \* Sequence of <<actor, amount>> pairs queued
    completedSpends,  \* Sequence of <<actor, amount, tier, time>> tuples — audit log
    sessionAuth,      \* Function: Actors -> Set of (TierLevel, time-presented) pairs
    lastT3Time,       \* Nat — most recent successful tier-3 spend
    now,              \* Nat — host-clock counter (monotonically advancing)
    policyCell        \* Record with tier1/2/3 ceilings + factor kinds + cooldown
```

**Actions**:

- `EnqueueSpend(actor, amount)` — append to `pendingSpends`.
- `PresentFactor(actor, factor, tier)` — record `(tier, now)` into `sessionAuth[actor]` if valid.
- `ProcessSpend(actor, amount)` — if head of `pendingSpends` for `actor`, classify, check factor, check cooldown, complete or reject.
- `Tick` — advance `now` by 1 (models passage of time).

**Safety invariants** (model-checked):

| Invariant | Statement |
|---|---|
| `INV-TierClassificationCorrect` | `∀ s ∈ completedSpends : s.tier = classifyAmount(s.amount, policyCell)` — every completed spend was tagged with the right tier per the policy. |
| `INV-FactorPresentedBeforeSign` | `∀ s ∈ completedSpends : ∃ (t, time) ∈ sessionAuth[s.actor] : t = s.tier ∧ time ≤ s.time` — for every spend at tier T, the matching factor was proven at or before the spend. |
| `INV-T3CooldownRespected` | `∀ s₁, s₂ ∈ completedSpends : (s₁.tier = 3 ∧ s₂.tier = 3 ∧ s₂.time > s₁.time) ⟹ s₂.time - s₁.time ≥ policyCell.tier3Cooldown` — consecutive Tier-3 spends respect the cooldown. |
| `INV-NoTierSkipping` | `∀ s ∈ completedSpends : s.tier ∈ {0, 1, 2, 3}` — no spend gets dispatched at an undefined tier. |
| `INV-PolicyCellSigned` | `policyCell.identity_signature` verifies under user identity key (modeled axiomatically via the existing TLA+ Hash injection abstraction). |

**Liveness obligations**:

| Obligation | Statement |
|---|---|
| `LIVE-NonT3SpendsCompleteWithoutCooldown` | `□ (head(pendingSpends).amount < policyCell.tier3_ceiling ∧ factorPresent(head(pendingSpends)) ⟹ ◇ head(pendingSpends) ∈ completedSpends)` |
| `LIVE-T3SpendsCompleteAfterCooldown` | `□ (∃ pending T3 spend ∧ factor present ∧ now - lastT3Time ≥ COOLDOWN ⟹ ◇ that spend completes)` |

**v0.2 extension hook**: include a comment block sketching the `nSequence`-based on-chain cooldown enforcement (UTXO-chain encoding), but model only the host-clock variant in v0.1. The transition to nSequence-based cooldown is a refinement that preserves the safety invariants.

**Deliverables**: `TierEscalation.tla` + `.cfg` + Makefile entry + README row. Same acceptance pattern as WT1.

---

### WT3 — Extension to `ReplayPrevention.tla` (~ half day)

**Goal**: extend the existing replay-prevention model to cover OP_SIGN-emitted signatures, proving that the BRC-42 fresh-key-per-tx discipline (W3.5 / DerivationStateStore monotonic indices) prevents signature replay.

**What ReplayPrevention.tla currently models**

LINEAR/AFFINE object consumption under concurrent actors. The key invariant `NoDoubleConsume` says: only one actor can successfully consume a LINEAR object. The model handles `obj.consumed` flag races.

**What WT3 adds**

A complementary model element: each Sign action consumes a derived leaf key, and the derivation-state store atomically allocates a monotonic index per `(protocol, counterparty)` context. The replay-prevention claim:

> No two distinct transactions are signed with the same leaf key.

This follows mechanically from the monotonic-index allocator, but TLA+ verifies it under concurrency:

```tla
VARIABLES
    derivationState,   \* Function: (protocol, counterparty) -> Nat — current index
    issuedLeaves,      \* Set of <<base, protocol, counterparty, index>> tuples
    signedTxs          \* Set of <<txId, leaf, msg, sighash, signature>> tuples

\* Atomically allocate next index for a context
NextIndex(p, c) ==
    LET i == derivationState[<<p, c>>] IN
    /\ derivationState' = [derivationState EXCEPT ![<<p, c>>] = i + 1]
    /\ issuedLeaves' = issuedLeaves \cup {<<base, p, c, i>>}

\* Sign action records the leaf used
SignWithLeaf(actor, txId, leaf, msg, sighash) ==
    /\ leaf \in issuedLeaves
    /\ ~ \E s \in signedTxs : s.leaf = leaf  \* leaf not previously signed with
    /\ signedTxs' = signedTxs \cup {<<txId, leaf, msg, sighash, sigOf(leaf, msg)>>}
```

**New invariants**:

| Invariant | Statement |
|---|---|
| `INV-LeafSingleUse` | `∀ s₁, s₂ ∈ signedTxs : s₁.leaf = s₂.leaf ⟹ s₁.txId = s₂.txId` — no leaf signs two distinct txs. |
| `INV-IndexMonotonic` | `∀ (p, c) : derivationState[<<p, c>>]' ≥ derivationState[<<p, c>>]` — derivation state never decreases. |
| `INV-NoIndexReuse` | `∀ <<p, c, i₁>>, <<p, c, i₂>> ∈ issuedLeaves : i₁ ≠ i₂` — each (protocol, counterparty) issues each index at most once. |

**Concurrency model**: multiple actors (browser tabs, sovereign nodes) attempt to allocate indices and sign concurrently. The model verifies the atomic-allocation guarantee from `host_state_next_index` / `DerivationStateStore.next_index`.

**Deliverables**: extension to `ReplayPrevention.tla` (new actions + invariants) + `.cfg` updates + README amendment. Existing invariants (`NoDoubleConsume` etc.) preserved.

---

## 3. Dependency Graph

```
   ┌─── WT1 (KeyCustody) ───┐
   │                         │
   ├─── WT2 (TierEscalation) ─┼──► WT4 (full make check, README/strategy update)
   │                         │
   └─── WT3 (ReplayExtension) ┘
```

WT1, WT2, WT3 are **fully independent** — each is a self-contained model. They can land in any order or in parallel. WT4 (a small validation phase) gates the merge.

---

## 4. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| WT1 — KeyCustody.tla | 1 day | Medium — multi-actor lifecycle is the largest model; expect 1-2 invariant violations on first run that surface real design questions |
| WT2 — TierEscalation.tla | 1 day | Low — sequential model, tractable state space |
| WT3 — ReplayPrevention extension | 0.5 day | Low — extends an existing model with well-bounded new actions |
| WT4 — make check + doc updates | 30 min | Trivial |

**Total**: ~2.5 days for one engineer.

---

## 5. Commit Boundary Plan

One PR per phase:

1. `feat(proofs-tla): WT1 — KeyCustody state machine + 5 safety + 2 liveness invariants`
2. `feat(proofs-tla): WT2 — TierEscalation classification + cooldown + 5 safety + 2 liveness invariants`
3. `feat(proofs-tla): WT3 — ReplayPrevention extended for OP_SIGN leaf-single-use + monotonic index`
4. `chore(proofs-tla): WT4 — make check covers all 12 specs, README + FORMAL-VERIFICATION-STRATEGY updated`

---

## 6. Acceptance Criteria

WT1–WT3 are done when:

1. `proofs/tla/KeyCustody.tla` and `proofs/tla/KeyCustody.cfg` exist.
2. `proofs/tla/TierEscalation.tla` and `proofs/tla/TierEscalation.cfg` exist.
3. `proofs/tla/ReplayPrevention.tla` extended with the WT3 invariants and actions; `.cfg` updated to declare them.
4. `make KeyCustody`, `make TierEscalation`, `make ReplayPrevention` each report `Model checking completed. No error has been found.`
5. None of the three models is vacuous (Makefile vacuity guard passes — `0 distinct states found` is treated as failure).
6. `make check` from `proofs/tla/` runs all 12 (was 9, now 12) specs, all pass.
7. `proofs/tla/README.md` updated with the three new entries in the Specs table.
8. `docs/FORMAL-VERIFICATION-STRATEGY.md` Protocol Invariants section adds rows for KeyCustody / TierEscalation / extended ReplayPrevention.

---

## 7. Why Each Model Earns Its Keep

### KeyCustody.tla

Lean per-opcode reasoning can prove: "OP_SIGN consumes a LINEAR cell on success" (K1, K11a) and "OP_SIGN doesn't leak the key into a non-linear cell" (K12). What Lean cannot directly express:

- "Across **multiple sessions** and **multiple actors**, a consumed key is only ever resurrected via the explicit Plexus recovery flow" — this is a property of the wallet's state-machine over time, not of any single opcode invocation.
- "Two browser tabs cannot both decrypt the same Tier-1 key concurrently" — concurrency claim, requires interleaving reasoning.
- "Recovery without prior enrollment is unreachable from any reachable state" — reachability claim over the protocol graph.

These are exactly TLA+'s wheelhouse. WT1 catches design bugs in the unlock/sign/recovery cycle that no per-opcode proof would catch.

### TierEscalation.tla

Lean K3 (DomainIsolation) checks that domain flags are enforced at the opcode level. What it doesn't enforce: that the **policy** (which factor for which tier, which threshold for which amount) is consistently applied across a sequence of spends, and that the cooldown actually prevents two consecutive Tier-3 transactions within the window. WT2 verifies the policy enforcement at the protocol-flow level.

### Extension to ReplayPrevention.tla

The existing `NoDoubleConsume` invariant covers LINEAR object consumption. The wallet adds a new replay surface: signed transactions with reusable leaf keys. WT3 establishes that the BRC-42 fresh-key-per-tx + monotonic-index allocator (W3.5) is a correct replay-prevention mechanism under concurrency, not just under sequential reasoning.

---

## 8. What WT1–WT3 Do Not Cover

For honesty:

- **The actual storage backend** (IndexedDB / lmdb) is abstracted as `keyState[k] = "encrypted_at_rest"`. WT1 doesn't model bytes-on-disk corruption or partial-write scenarios — those would require a lower-level model. (The acceptance criteria just say the persistence-failure paths return errors before any state transition, which K4 + K13 cover at the opcode layer.)
- **Cryptographic primitives** (AES-GCM, Argon2id, ECDSA) are abstracted as oracles. The TLA+ Hash-as-Injection convention (per `proofs/tla/README.md`) handles SHA-256 idealization; same applies here.
- **Network interactions** with Plexus are abstracted as atomic actions (`RecoverViaPlexus`). The OTP rate-limiting / email infrastructure is the Plexus operator's concern, not modeled here.
- **WASM extern correctness** (`host_sign`, `host_state_next_index`) — same caveat as WP9. Lean uses axioms; WT models the axioms' temporal consequences. The empirical bridge to the binary stays in Zig differential testing.
- **Side channels** (timing, cache, memory inspection) — out of scope for this proof layer.

---

## 9. The Layered Wallet Trust Story After WT1-WT3

| Layer | Tool | What it covers |
|---|---|---|
| Per-opcode structural soundness | Lean (K1–K13, K4 substantive via WP9) | Failure atomicity, linearity, signing soundness, key custody, budget monotonicity |
| Multi-step temporal + concurrency safety | TLA+ (KeyCustody, TierEscalation, ReplayPrevention extended) | State-machine reachability, cross-actor concurrency, policy enforcement over sequences |
| Engine implementation correctness | Zig conformance + fuzz tests | Implementation matches the Lean model; failure-atomicity holds in practice |
| Crypto primitive correctness | bsvz differential test | host_sign produces signatures matching an independent secp256k1 implementation |
| Binary-to-model linkage | WASM-MANIFEST hash pin | Deployed binary is the one the proofs reason about |

After WT1–WT3 complete, every level has substantive coverage. The wallet's signing semantics are mechanically verified at every layer where mechanical verification applies, and empirically validated where it doesn't.

---

## 10. After WT — What's Left

If you want a complete picture of what remains after WT1-WT3 ship:

| Status | Workstream |
|---|---|
| ✅ Done | W1–W3.5 (engine + budget + derivation state) |
| ✅ Done | WP1–WP9 (Lean K4 substantive promotion + dispatch alignment) |
| 🟦 This plan | WT1–WT3 (TLA+ wallet models) |
| 🔲 Next | W4 (storage: AES-GCM at rest + host_unlock_tier / persist / load) |
| 🔲 Next | W5 (browser bundle: trim bsvz + iframe/popup transport) |
| 🔲 Next | W6 (sovereign-node target: Caddyfile + WSS BRC-100 endpoint) |
| 🔲 Next | W7 (Plexus Dispatch Module — envelope + OTP + recovery) |
| 🔲 Next | W9 (Wallet UI — first-time enrollment, tier setup, send/receive) |
| 🔲 Next | W10 (End-to-end recovery test) |
| 🔲 v0.2 | W11 (Vault multisig + nSequence cooldown) |

WT1–WT3 sits naturally before W4 because it surfaces design bugs in the unlock-flow state machine *before* the storage layer commits to a particular implementation shape. Lands cheap, pays back high.

---

*Cross-references*

- `proofs/tla/Makefile` — TLC harness; new specs added to `SPECS` list
- `proofs/tla/README.md` — convention reference, including Hash-as-Injection and Time-as-Counter abstractions
- `proofs/tla/ReplayPrevention.tla` — file extended in WT3
- `proofs/tla/SemanticTypes.tla` — base linearity types this work builds on
- `docs/design/WALLET-TIER-CUSTODY.md` §9.2 — original TLA+ obligations
- `docs/design/PROOFS-WALLET-EXTENSION-PLAN.md` — companion W1-W8 (engine + Lean) plan
- `docs/design/PROOFS-WP9-K4-PROMOTION.md` — WP9 (substantive K4) plan
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — overall layered verification doc to update in WT4
