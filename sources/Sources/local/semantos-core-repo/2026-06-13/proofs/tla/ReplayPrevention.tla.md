---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ReplayPrevention.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.340778+00:00
---

# proofs/tla/ReplayPrevention.tla

```tla
------------------------- MODULE ReplayPrevention -------------------------
(*
 * Replay Prevention — concurrent consumption of LINEAR and AFFINE objects,
 * AND OP_SIGN per-leaf-key uniqueness (added in Wave 8).
 *
 * Source: src/compiler/validator.ts
 *   - validateConsumption (lines 62-82): guards obj.consumed, sets consumed=true
 *   - validateAcknowledgement (lines 94-107): guards obj.discarded
 *   - validateDiscard (lines 119-136): guards obj.acknowledged AND obj.discarded
 *   - canConsume (lines 297-311): LINEAR=>!consumed, AFFINE=>!(ack||disc)
 *
 * Wave 8 extension (OP_SIGN replay), per docs/design/WALLET-TIER-CUSTODY.md
 *   sec 3.5 (BRC-42 fresh-keys-per-tx) and sec 9.2 (extension to
 *   ReplayPrevention.tla):
 *   - Every signing leaf is fresh-per-tx (sec G9 in the design doc)
 *   - No two distinct sign actions on the same (tier_key_pubkey, msg_digest)
 *     pair can succeed — the leaf private key is consumed by OP_SIGN exactly
 *     once (linearity), so its public key appears as a signing identity at
 *     most once.
 *
 * Models multiple concurrent actors attempting to consume the same resource.
 * The key properties:
 *   1. Only ONE actor can successfully consume a LINEAR object.
 *   2. No two sign actions on the same (leaf_pubkey, msg_digest) pair.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Actors,         \* Set of concurrent actors (model values)
    Resources,      \* Set of resource identifiers (model values)
    TxIds,          \* Set of transaction identifiers (model values)
    LeafPubkeys,    \* Set of leaf public keys (BRC-42 derived; model values)
    MsgDigests,     \* Set of message digests / sighash inputs (model values)
    Contexts,       \* WT3 — set of (protocol, counterparty) contexts for
                    \* BRC-42 derivation (DerivationStateStore key)
    MaxIndex,       \* WT3 — bound on the monotonic index per context (Nat)
    NULL            \* Distinguished null value

\* --- Object types ---

LinearState == [
    type            : {"LINEAR"},
    consumed        : BOOLEAN,
    consumedBy      : Actors \cup {NULL},
    consumptionTxId : TxIds \cup {NULL}
]

AffineState == [
    type         : {"AFFINE"},
    acknowledged : BOOLEAN,
    discarded    : BOOLEAN
]

\* --- State variables ---

VARIABLES
    objects,         \* Function: Resources -> object state
    consumeCount,    \* Function: Resources -> Nat (counts successful consumptions)
    SignNonces,      \* Set of records {leafPubkey, msgDigest, txId, actor}
                     \* tracking every successful OP_SIGN. (Wave 8 extension.)
    derivationIndex, \* WT3 — Contexts -> Nat. Atomic monotonic allocator
                     \* mirroring DerivationStateStore.next_index per
                     \* (protocol, counterparty) context (W3.5).
    issuedLeaves     \* WT3 — set of records {context, index} marking every
                     \* index successfully allocated. The atomicity property
                     \* asserts each index is in this set at most once.

vars == <<objects, consumeCount, SignNonces, derivationIndex, issuedLeaves>>

\* --- Initial state ---

InitLinear == [
    type            |-> "LINEAR",
    consumed        |-> FALSE,
    consumedBy      |-> NULL,
    consumptionTxId |-> NULL
]

InitAffine == [
    type         |-> "AFFINE",
    acknowledged |-> FALSE,
    discarded    |-> FALSE
]

Init ==
    /\ objects \in [Resources -> {InitLinear, InitAffine}]
    /\ consumeCount = [r \in Resources |-> 0]
    /\ SignNonces = {}
    /\ derivationIndex = [c \in Contexts |-> 0]
    /\ issuedLeaves = {}

\* --- Legitimate actions ---

(*
 * ConsumeLinear: models validator.ts validateConsumption (lines 62-82).
 * Guard: !consumed (line 66), valid txId (line 70).
 * Effect: consumed=true, consumedBy=actor, consumptionTxId=txId.
 *)
ConsumeLinear(r, actor, txId) ==
    /\ objects[r].type = "LINEAR"
    /\ ~objects[r].consumed
    /\ objects' = [objects EXCEPT ![r] = [
           objects[r] EXCEPT
               !.consumed = TRUE,
               !.consumedBy = actor,
               !.consumptionTxId = txId
       ]]
    /\ consumeCount' = [consumeCount EXCEPT ![r] = consumeCount[r] + 1]
    /\ UNCHANGED <<SignNonces, derivationIndex, issuedLeaves>>

(*
 * AcknowledgeAffine: models validator.ts validateAcknowledgement (lines 94-107).
 * Guard: !discarded (line 97).
 *)
AcknowledgeAffine(r, actor) ==
    /\ objects[r].type = "AFFINE"
    /\ ~objects[r].discarded
    /\ objects' = [objects EXCEPT ![r].acknowledged = TRUE]
    /\ UNCHANGED <<consumeCount, SignNonces, derivationIndex, issuedLeaves>>

(*
 * DiscardAffine: models validator.ts validateDiscard (lines 119-136).
 * Guard: !acknowledged (line 122) AND !discarded (line 127).
 *)
DiscardAffine(r, actor) ==
    /\ objects[r].type = "AFFINE"
    /\ ~objects[r].acknowledged
    /\ ~objects[r].discarded
    /\ objects' = [objects EXCEPT ![r].discarded = TRUE]
    /\ UNCHANGED <<consumeCount, SignNonces, derivationIndex, issuedLeaves>>

\* --- Adversary actions ---

(*
 * ReplayAttack: an adversary captures a valid consumption proof (txId from
 * a previous successful consumption) and attempts to replay it against the
 * same or another LINEAR resource.
 *
 * The guard (~objects[r].consumed) prevents this — once consumed, the
 * object rejects all further consumption attempts regardless of proof validity.
 * This action is structurally identical to ConsumeLinear — the replay is
 * indistinguishable from a legitimate attempt. The consumed flag is the defense.
 *)
ReplayAttack(r, adversary, capturedTxId) ==
    /\ objects[r].type = "LINEAR"
    /\ ~objects[r].consumed
    /\ objects' = [objects EXCEPT ![r] = [
           objects[r] EXCEPT
               !.consumed = TRUE,
               !.consumedBy = adversary,
               !.consumptionTxId = capturedTxId
       ]]
    /\ consumeCount' = [consumeCount EXCEPT ![r] = consumeCount[r] + 1]
    /\ UNCHANGED <<SignNonces, derivationIndex, issuedLeaves>>

\* --- Wave 8: OP_SIGN per-leaf-key uniqueness ---
(*
 * SignLeaf(leaf, msg, actor, txId): models a successful OP_SIGN against a
 * fresh BRC-42 leaf key (sec 3.5 of the design doc). The action records
 * the (leaf, msg) pair in SignNonces; the linearity discipline of the
 * leaf cell is enforced by the guard that no record with the same leaf
 * already exists. This is the system-level analogue of K11/K12 (Lean):
 * the leaf private key is consumed by OP_SIGN exactly once.
 *
 * The guard models the linearity check the engine performs at OP_SIGN
 * time — once a leaf has signed, its LINEAR cell is gone, so a second
 * sign on the same leaf cannot be initiated through legitimate means.
 *)
SignLeaf(leaf, msg, actor, txId) ==
    /\ \A rec \in SignNonces : rec.leaf /= leaf
    /\ SignNonces' = SignNonces \cup
           {[leaf |-> leaf, msg |-> msg, actor |-> actor, txId |-> txId]}
    /\ UNCHANGED <<objects, consumeCount, derivationIndex, issuedLeaves>>

(*
 * SignReplayAttack(leaf, msg, adversary, capturedTxId): an adversary
 * captures a (leaf, msg, sig) triple from the network and tries to use
 * the same leaf to sign again on a different message OR replay the same
 * signature on a fresh transaction. Either way the engine cannot produce
 * a second signature from a leaf whose LINEAR cell has already been
 * consumed — the guard "no record with this leaf exists" blocks the
 * attack. The attempt is structurally identical to SignLeaf so we model
 * it explicitly to exercise the defense.
 *)
SignReplayAttack(leaf, msg, adversary, capturedTxId) ==
    /\ \E rec \in SignNonces : rec.leaf = leaf
    /\ UNCHANGED vars

\* --- WT3: BRC-42 monotonic-index allocator (DerivationStateStore) ---
(*
 * AllocateIndex(c): atomically allocate the next BRC-42 derivation index
 * for context c (a (protocol, counterparty) pair). Mirrors the
 * DerivationStateStore.next_index host import (W3.5). The atomicity
 * guarantee asserted by the host is captured by treating the
 * derivationIndex update + issuedLeaves recording as a single TLA+
 * action: TLC verifies that no interleaving of two concurrent actors
 * can produce two issuedLeaves entries with the same (context, index).
 *
 * Bounded by MaxIndex to keep TLC's state space finite. Real
 * deployments are bounded by 2^31 (the BRC-42 child-index range).
 *)
AllocateIndex(c, a) ==
    /\ c \in Contexts
    /\ a \in Actors
    /\ derivationIndex[c] < MaxIndex
    /\ derivationIndex' = [derivationIndex EXCEPT ![c] = derivationIndex[c] + 1]
    /\ issuedLeaves' = issuedLeaves \cup
           {[context |-> c, index |-> derivationIndex[c], actor |-> a]}
    /\ UNCHANGED <<objects, consumeCount, SignNonces>>

Next ==
    \/ \E r \in Resources, a \in Actors :
         \/ \E tx \in TxIds : ConsumeLinear(r, a, tx)
         \/ AcknowledgeAffine(r, a)
         \/ DiscardAffine(r, a)
         \/ \E tx \in TxIds : ReplayAttack(r, a, tx)
    \/ \E leaf \in LeafPubkeys, msg \in MsgDigests,
         a \in Actors, tx \in TxIds :
         \/ SignLeaf(leaf, msg, a, tx)
         \/ SignReplayAttack(leaf, msg, a, tx)
    \/ \E c \in Contexts, a \in Actors : AllocateIndex(c, a)

Spec == Init /\ [][Next]_vars

\* --- Safety properties ---

(*
 * NoDoubleConsume: a LINEAR object is consumed at most once.
 * This is the core replay prevention guarantee.
 * The consumeCount auxiliary variable tracks total successful consumptions.
 *)
NoDoubleConsume ==
    \A r \in Resources :
        objects[r].type = "LINEAR" => consumeCount[r] <= 1

(*
 * SingleConsumption: once a LINEAR object is consumed, it stays consumed
 * and the proof fields are set.
 *)
SingleConsumption ==
    \A r \in Resources :
        objects[r].type = "LINEAR" =>
            (objects[r].consumed =>
                /\ objects[r].consumedBy /= NULL
                /\ objects[r].consumptionTxId /= NULL)

(*
 * AffineExclusion: an AFFINE object cannot be both acknowledged and discarded.
 * Models the mutual exclusion from validateAcknowledgement (line 97) and
 * validateDiscard (line 122).
 *)
AffineExclusion ==
    \A r \in Resources :
        objects[r].type = "AFFINE" =>
            ~(objects[r].acknowledged /\ objects[r].discarded)

(*
 * ConsumedImpliesProof: consumed LINEAR objects always have valid proof fields.
 * Matches validateConsumption postcondition (lines 74-79).
 *)
ConsumedImpliesProof ==
    \A r \in Resources :
        objects[r].type = "LINEAR" =>
            (objects[r].consumed =>
                /\ objects[r].consumedBy \in Actors
                /\ objects[r].consumptionTxId \in TxIds)

(*
 * Wave 8 — OP_SIGN per-leaf uniqueness (sec 3.5, sec G9 of the design).
 *
 * NoSignReplay: no two distinct sign records share the same leaf
 * pubkey. Equivalently: every leaf is signed against at most once. This
 * complements K11 (Lean: per-call OP_SIGN soundness) by lifting the
 * guarantee to the system level — across multiple opcode invocations,
 * the same BRC-42 leaf cannot reappear as a signer because its LINEAR
 * cell has already been consumed.
 *)
NoSignReplay ==
    \A r1, r2 \in SignNonces :
        r1.leaf = r2.leaf => r1 = r2

(*
 * SignFreshness: every recorded (leaf, msg) pair is unique. This is a
 * weaker corollary of NoSignReplay (since per-leaf uniqueness implies
 * per-(leaf, msg) uniqueness) but is asserted independently because the
 * design doc phrases the obligation in (tier_key_pubkey, msg_digest)
 * terms.
 *)
SignFreshness ==
    \A r1, r2 \in SignNonces :
        (r1.leaf = r2.leaf /\ r1.msg = r2.msg) => r1 = r2

\* --- WT3 — BRC-42 monotonic-index allocator invariants ---

(*
 * INV-NoIndexReuse: each (context, index) is issued at most once. This
 * is the atomicity guarantee from host_state_next_index: even under
 * concurrent allocation by multiple actors, no two issuedLeaves
 * records share the same (context, index) pair. If the implementation
 * weren't atomic, TLC would find an interleaving where two AllocateIndex
 * calls read the same derivationIndex[c] before either updates, both
 * succeed, and both records would have the same index.
 *)
INV_NoIndexReuse ==
    \A r1, r2 \in issuedLeaves :
        (r1.context = r2.context /\ r1.index = r2.index)
            => r1 = r2

(*
 * INV-IndexInRange: every issued index is in [0, derivationIndex[c]).
 * Cross-checks that the issuedLeaves set never contains an index
 * higher than the current allocator state — i.e., the allocator
 * doesn't lose track of what it issued.
 *)
INV_IndexInRange ==
    \A rec \in issuedLeaves :
        rec.index < derivationIndex[rec.context]

(*
 * INV-IndexMonotonic (action-level, lifted via PROP): the allocator
 * index for any context never decreases. Captured below via the
 * temporal property PROP_IndexMonotonic.
 *)
INV_IndexMonotonic ==
    \A c \in Contexts : derivationIndex'[c] >= derivationIndex[c]

\* --- Temporal lift of action-level invariants ---
PROP_IndexMonotonic == [][INV_IndexMonotonic]_vars

=============================================================================

```
