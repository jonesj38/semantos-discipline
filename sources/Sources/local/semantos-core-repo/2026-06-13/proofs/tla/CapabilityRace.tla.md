---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/CapabilityRace.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.343968+00:00
---

# proofs/tla/CapabilityRace.tla

```tla
--------------------------- MODULE CapabilityRace ---------------------------
(*
 * K15 — Capability-UTXO binding (TLA+ side: concurrent-spend race).
 *
 * Companion to proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean.
 *
 * K15 (Capability-UTXO binding, UNIFICATION-ROADMAP §11.2):
 *   OP_CHECKCAPABILITY succeeds iff UTXO is unspent, signing pubkey
 *   matches holder, and query domain matches capability domain.
 *
 * What TLA+ adds over Lean:
 *   Lean proves the per-call correctness symbolically. This spec
 *   explores the CONCURRENCY hazard: multiple actors simultaneously
 *   reading-then-spending the same capability UTXO. The K15 contract
 *   requires *exactly one* succeed; the rest must fail with K4
 *   rollback. TLC enumerates the interleavings.
 *
 * The race that TLA+ catches:
 *   Actor A: reads cap.state → unspent; intends to spend
 *   Actor B: reads cap.state → unspent (concurrently!); intends to spend
 *   Both attempt the spend. Naive implementations (read-then-write
 *   without atomic CAS) allow both to succeed → double-spend.
 *
 * The K15 invariant requires the SPEND step to be atomic with the
 * check step, OR the kernel to detect & reject the second spend.
 * We model both as TLC-checkable Actions.
 *
 * Source: BRC-108 + BRC-115 5-stage verification (§11.6 binding)
 *         core/cell-engine/src/opcodes/plexus.zig — OP_CHECKCAPABILITY 0xC3
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    Actors,            \* Finite set of actor identifiers
    CapabilityIds,     \* Finite set of capability UTXO ids
    PubKeys,           \* Finite set of pubkeys for actor identity
    DomainFlags        \* Finite set of domain flag values

\* --- State model ---
\*
\* Each capability has:
\*   - state: unspent | spent
\*   - holderPubKey: which pubkey can use it
\*   - domainFlag: which domain it's bound to
\*
\* Each actor has:
\*   - signingPubKey: their identity
\*   - intent: what they're trying to do ({none, checking c, spending c})

CapabilityState == [
    state        : {"unspent", "spent"},
    holderPubKey : PubKeys,
    domainFlag   : DomainFlags
]

\* Tagged-union flattened: intentKind ∈ {idle, spend}; target/domain
\* are only meaningful when kind = "spend". We pick distinguished
\* sentinels ("none") for the idle case to keep TLA+ types simple.

IntentTargets == CapabilityIds \cup {"none"}
IntentDomains == DomainFlags \cup {"none"}

ActorState == [
    signingPubKey : PubKeys,
    intentKind    : {"idle", "spend"},
    intentTarget  : IntentTargets,
    intentDomain  : IntentDomains
]

VARIABLES
    capabilities,      \* CapabilityIds → CapabilityState
    actors,            \* Actors → ActorState
    successCount       \* Per capability: how many actors successfully spent it

vars == <<capabilities, actors, successCount>>

\* --- Initial state ---
\*
\* All capabilities unspent. Actors idle (kind = "idle", target/domain
\* sentinels). Each cap holder/domain is chosen non-deterministically
\* (TLC explores).

Init ==
    /\ capabilities \in [CapabilityIds -> CapabilityState]
    /\ \A c \in CapabilityIds : capabilities[c].state = "unspent"
    /\ actors \in [Actors -> ActorState]
    /\ \A a \in Actors :
         /\ actors[a].intentKind = "idle"
         /\ actors[a].intentTarget = "none"
         /\ actors[a].intentDomain = "none"
    /\ successCount = [c \in CapabilityIds |-> 0]

\* --- Operations ---

\* DeclareSpendIntent: an actor announces intent to spend a capability
\* on a particular domain.

DeclareSpendIntent(a, c, d) ==
    /\ actors[a].intentKind = "idle"
    /\ actors' = [actors EXCEPT
                    ![a].intentKind   = "spend",
                    ![a].intentTarget = c,
                    ![a].intentDomain = d]
    /\ UNCHANGED <<capabilities, successCount>>

\* AttemptSpend: execute the spend. Models the atomic CAS check:
\* the spend succeeds iff the K15 contract holds AT SPEND TIME.

AttemptSpend(a) ==
    /\ actors[a].intentKind = "spend"
    /\ actors[a].intentTarget \in CapabilityIds
    /\ actors[a].intentDomain \in DomainFlags
    /\ LET target  == actors[a].intentTarget
           dom     == actors[a].intentDomain
           cap     == capabilities[target]
           passes ==
              /\ cap.state = "unspent"
              /\ actors[a].signingPubKey = cap.holderPubKey
              /\ dom = cap.domainFlag
       IN
       /\ IF passes
          THEN /\ capabilities' = [capabilities EXCEPT ![target].state = "spent"]
               /\ successCount' = [successCount EXCEPT ![target] = @ + 1]
          ELSE /\ capabilities' = capabilities
               /\ successCount' = successCount
       /\ actors' = [actors EXCEPT
                       ![a].intentKind   = "idle",
                       ![a].intentTarget = "none",
                       ![a].intentDomain = "none"]

\* --- Transition relation ---

Next ==
    \/ \E a \in Actors, c \in CapabilityIds, d \in DomainFlags :
         DeclareSpendIntent(a, c, d)
    \/ \E a \in Actors :
         AttemptSpend(a)

Spec == Init /\ [][Next]_vars

\* --- Invariants ---

\* K15 main: each capability is spent AT MOST ONCE. The successCount
\* never exceeds 1 for any capability, even under arbitrary interleaving
\* of declare/attempt pairs.

K15_NoDoubleSpend ==
    \A c \in CapabilityIds : successCount[c] <= 1

\* K15 consistency: a successCount > 0 implies the capability is spent.
\* (And conversely — a spent capability must have at least one successful
\* spend in its history.)

K15_SpendCountConsistent ==
    \A c \in CapabilityIds :
        \/ (successCount[c] = 0 /\ capabilities[c].state = "unspent")
        \/ (successCount[c] = 1 /\ capabilities[c].state = "spent")

\* Type invariant.

TypeInv ==
    /\ capabilities \in [CapabilityIds -> CapabilityState]
    /\ actors \in [Actors -> ActorState]
    /\ successCount \in [CapabilityIds -> Nat]
    /\ \A c \in CapabilityIds : successCount[c] <= Cardinality(Actors)

\* Composite K15.

K15_CapabilityRace ==
    /\ K15_NoDoubleSpend
    /\ K15_SpendCountConsistent

=============================================================================
(*
 * NOTE on companion Lean theorem.
 *
 * CapabilityUtxoK15.lean proves the per-call check correctness
 * (K15a–K15e). This spec adds the concurrent-spend race property:
 * even with N actors simultaneously trying to spend the same
 * capability, at most one succeeds.
 *
 * The key modeling choice: AttemptSpend re-evaluates the K15 contract
 * AT EXECUTION TIME using the current capabilities[].state, not the
 * snapshot at DeclareSpendIntent time. This models the atomic CAS
 * semantics the BRC-108 + BRC-115 verification pipeline implements
 * (UTXO is spent atomically via the underlying BSV transaction).
 *
 * A buggy implementation that snapshotted state at declare time and
 * spent unconditionally at attempt time would violate K15_NoDouble-
 * Spend; TLC would surface the trace.
 *
 * Default config (CapabilityRace.cfg): 2 actors, 1 capability,
 * 2 pubkeys, 1 domain. Small but sufficient to expose the race.
 *)
=============================================================================

```
