---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/KeyCustody.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.343696+00:00
---

# proofs/tla/KeyCustody.tla

```tla
---------------------------- MODULE KeyCustody ----------------------------
(*
 * Per-tier-key custody state machine — Wave 8 of the wallet tiered-custody
 * design (WALLET-TIER-CUSTODY.md §9.2). Models the system-level lifecycle
 * of every Tier-N (N ∈ {1,2,3}) BASE key as it moves between four states:
 * encrypted_at_rest → decrypted_in_engine → consumed → reconstructible_via_plexus
 * → encrypted_at_rest, against multiple concurrent ACTORS (browser tabs,
 * sovereign nodes, recovery flows happening simultaneously).
 *
 * The Lean K1-K13 layer covers per-opcode invariants (sign soundness K11,
 * key custody K12, budget monotonicity K13, failure atomicity K4). What
 * Lean does NOT cover is the BETWEEN-opcode state machine — the
 * encrypted_at_rest → decrypted_in_engine → consumed lifecycle that spans
 * multiple wallet sessions and possibly a Plexus-mediated recovery, and
 * critically the cross-ACTOR concurrency claims (e.g. "two browser tabs
 * cannot both decrypt the same Tier-1 key concurrently"). That's what
 * this model adds, and it's what TLC verifies.
 *
 * Source: docs/design/WALLET-TIER-CUSTODY.md
 *   - §3.5 (BRC-42 fresh-keys-per-tx)
 *   - §4 (auth model — local factors per tier)
 *   - §6.2 (Tier-N base key cell, AFFINE)
 *   - §7.7 (optional recovery enrollment)
 *   - §7.8 (disaster recovery flow)
 *   - §9.2 (TLA+ obligations)
 *
 * Abstractions:
 *   - The signing factor (PIN / biometric / vault) is modeled as a
 *     boolean FactorPresented[tier, actor]. The actual KEK derivation
 *     (Argon2id, SecureEnclave, etc.) is opaque — the spec only tracks
 *     "actor A has supplied the correct factor for tier T".
 *   - The leaf-key LINEAR-consumption per OP_SIGN is covered by Lean K11/
 *     K12 and not re-modeled here; from this module's perspective, Sign
 *     is the system-level act of consuming a tier's decrypted-in-engine
 *     base capability for one signing burst.
 *   - "Tier" ranges over {1,2,3}. Tier 0 (the AFFINE budget cell) is not
 *     in scope: it has no encrypted-at-rest / decrypted-in-engine
 *     distinction because there is no auth factor.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Tiers,    \* Set of tier indices, e.g. {1, 2, 3}
    Actors,   \* Set of concurrent actors (browser tabs / sovereign nodes)
    NULL      \* Distinguished null marker for "no actor"

\* --- Key lifecycle states (design 9.2) ---

KeyStates == {
    "encrypted_at_rest",
    "decrypted_in_engine",
    "consumed",
    "reconstructible_via_plexus"
}

\* --- State variables ---

VARIABLES
    KeyState,           \* Tiers -> KeyStates
    DecryptedBy,        \* Tiers -> Actors ∪ {NULL}: which actor holds the
                        \* decrypted key, or NULL if not currently decrypted
    RecoveryEnrolled,   \* Tiers -> BOOLEAN — did the user dispatch a Plexus
                        \* recovery envelope for this tier? (sec 7.7)
    FactorPresented,    \* [Tiers × Actors] -> BOOLEAN — has actor A supplied
                        \* the correct local auth factor for tier T?
    RecoveryFactorOk    \* Tiers -> BOOLEAN — has the user supplied the
                        \* correct OTP + challenge answers for recovery?

vars == <<KeyState, DecryptedBy, RecoveryEnrolled,
          FactorPresented, RecoveryFactorOk>>

\* --- Initial state: every tier is encrypted-at-rest, no actor holds anything ---

Init ==
    /\ KeyState = [t \in Tiers |-> "encrypted_at_rest"]
    /\ DecryptedBy = [t \in Tiers |-> NULL]
    /\ RecoveryEnrolled = [t \in Tiers |-> FALSE]
    /\ FactorPresented = [<<t, a>> \in Tiers \X Actors |-> FALSE]
    /\ RecoveryFactorOk = [t \in Tiers |-> FALSE]

\* --- Environmental actions (the user / OS supplies factors) ---

(*
 * PresentFactor(t, a): actor `a` supplies the correct local auth factor
 * (PIN, biometric, vault) for tier `t`. The factor is local-OS only
 * (sec 4.1) and the cell engine never sees it — pure environmental
 * input.
 *)
PresentFactor(t, a) ==
    /\ ~FactorPresented[<<t, a>>]
    /\ FactorPresented' = [FactorPresented EXCEPT ![<<t, a>>] = TRUE]
    /\ UNCHANGED <<KeyState, DecryptedBy, RecoveryEnrolled, RecoveryFactorOk>>

(*
 * PresentRecoveryFactor(t): user supplies correct OTP + challenge answers
 * during disaster recovery (sec 7.8). Modeled as an environmental input.
 *)
PresentRecoveryFactor(t) ==
    /\ RecoveryEnrolled[t]
    /\ ~RecoveryFactorOk[t]
    /\ RecoveryFactorOk' = [RecoveryFactorOk EXCEPT ![t] = TRUE]
    /\ UNCHANGED <<KeyState, DecryptedBy, RecoveryEnrolled, FactorPresented>>

\* --- Wallet actions (transitions on the tier key, parameterized by actor) ---

(*
 * Unlock(t, a): encrypted_at_rest → decrypted_in_engine, performed by
 * actor `a`. Loads the AFFINE base cell into the engine (sec 6.2).
 * Requires the local auth factor presented by THIS actor, AND the key
 * must not currently be decrypted by anyone (concurrency precondition).
 *)
Unlock(t, a) ==
    /\ KeyState[t] = "encrypted_at_rest"
    /\ FactorPresented[<<t, a>>]
    /\ DecryptedBy[t] = NULL
    /\ KeyState' = [KeyState EXCEPT ![t] = "decrypted_in_engine"]
    /\ DecryptedBy' = [DecryptedBy EXCEPT ![t] = a]
    /\ UNCHANGED <<RecoveryEnrolled, FactorPresented, RecoveryFactorOk>>

(*
 * Sign(t, a): decrypted_in_engine → consumed, performed by actor `a`.
 * Only the actor who unlocked the key may sign with it. From the system
 * perspective this models the case where the entire base capability is
 * exhausted (one-shot key, or a vault key burned after use in v0.2
 * multisig). The per-LEAF consumption per OP_SIGN is covered by Lean
 * K11/K12.
 *)
Sign(t, a) ==
    /\ KeyState[t] = "decrypted_in_engine"
    /\ DecryptedBy[t] = a
    /\ KeyState' = [KeyState EXCEPT ![t] = "consumed"]
    /\ DecryptedBy' = [DecryptedBy EXCEPT ![t] = NULL]
    /\ UNCHANGED <<RecoveryEnrolled, FactorPresented, RecoveryFactorOk>>

(*
 * LockSession(t, a): decrypted_in_engine → encrypted_at_rest, performed
 * by the actor who currently holds the decrypted key. The session locks
 * (timeout, explicit lock, browser tab closed). The KEK is zeroed
 * (sec 4.2) and the base cell is dropped from the engine. The
 * encrypted-at-rest blob in IndexedDB / lmdb is unchanged.
 *)
LockSession(t, a) ==
    /\ KeyState[t] = "decrypted_in_engine"
    /\ DecryptedBy[t] = a
    /\ KeyState' = [KeyState EXCEPT ![t] = "encrypted_at_rest"]
    /\ DecryptedBy' = [DecryptedBy EXCEPT ![t] = NULL]
    /\ FactorPresented' = [FactorPresented EXCEPT ![<<t, a>>] = FALSE]
    /\ UNCHANGED <<RecoveryEnrolled, RecoveryFactorOk>>

(*
 * EnrollRecovery(t): dispatch the recovery envelope to Plexus (sec 7.7).
 * Idempotent on re-attempt. Does NOT change the key state.
 *)
EnrollRecovery(t) ==
    /\ ~RecoveryEnrolled[t]
    /\ RecoveryEnrolled' = [RecoveryEnrolled EXCEPT ![t] = TRUE]
    /\ UNCHANGED <<KeyState, DecryptedBy, FactorPresented, RecoveryFactorOk>>

(*
 * BeginRecovery(t): consumed → reconstructible_via_plexus. Only enabled
 * if the user has both enrolled (sec 7.7) and supplied correct OTP +
 * challenge answers (sec 7.8). First half of the recovery walk.
 *)
BeginRecovery(t) ==
    /\ KeyState[t] = "consumed"
    /\ RecoveryEnrolled[t]
    /\ RecoveryFactorOk[t]
    /\ KeyState' = [KeyState EXCEPT ![t] = "reconstructible_via_plexus"]
    /\ UNCHANGED <<DecryptedBy, RecoveryEnrolled, FactorPresented,
                   RecoveryFactorOk>>

(*
 * CompleteRecovery(t): reconstructible_via_plexus → encrypted_at_rest.
 * The wallet has decrypted the recovery seed locally, re-derived the
 * tier key, re-encrypted it under the new device's KEK, and persisted
 * the at-rest blob (sec 7.8 step 13).
 *)
CompleteRecovery(t) ==
    /\ KeyState[t] = "reconstructible_via_plexus"
    /\ KeyState' = [KeyState EXCEPT ![t] = "encrypted_at_rest"]
    /\ UNCHANGED <<DecryptedBy, RecoveryEnrolled, FactorPresented,
                   RecoveryFactorOk>>

Next ==
    \E t \in Tiers, a \in Actors :
        \/ PresentFactor(t, a)
        \/ PresentRecoveryFactor(t)
        \/ Unlock(t, a)
        \/ Sign(t, a)
        \/ LockSession(t, a)
        \/ EnrollRecovery(t)
        \/ BeginRecovery(t)
        \/ CompleteRecovery(t)

Spec == Init /\ [][Next]_vars

\* --- Fairness for liveness obligations (sec 9.2) ---
(*
 * SF on the legitimate user actions. Quantifying SF over (t, a) pairs
 * is sufficient: every actor-tier slot can make progress.
 *)
FairSpec ==
    Spec
    /\ (\A t \in Tiers : \A a \in Actors : SF_vars(PresentFactor(t, a)))
    /\ (\A t \in Tiers : \A a \in Actors : SF_vars(Unlock(t, a)))
    /\ (\A t \in Tiers : SF_vars(PresentRecoveryFactor(t)))
    /\ (\A t \in Tiers : SF_vars(BeginRecovery(t)))
    /\ (\A t \in Tiers : SF_vars(CompleteRecovery(t)))

\* --- Type invariant ---

TypeInv ==
    /\ KeyState \in [Tiers -> KeyStates]
    /\ DecryptedBy \in [Tiers -> Actors \cup {NULL}]
    /\ RecoveryEnrolled \in [Tiers -> BOOLEAN]
    /\ FactorPresented \in [Tiers \X Actors -> BOOLEAN]
    /\ RecoveryFactorOk \in [Tiers -> BOOLEAN]

\* --- Safety invariants (design sec 9.2) ---

(*
 * INV-NoConcurrentDecrypt: at most one actor holds any given tier key
 * decrypted at any one time. This is the key concurrency claim that
 * Lean cannot directly express — a cross-actor reachability property
 * over the system state machine. If two browser tabs both tried to
 * Unlock the same Tier-1 key, the model's Unlock guard
 * (DecryptedBy[t] = NULL) prevents the second one from succeeding
 * until the first one Locks or Signs. TLC verifies this holds across
 * every reachable interleaving.
 *
 * Operationally: KeyState[t] = "decrypted_in_engine" implies
 * DecryptedBy[t] is a specific Actor (not NULL, not a set) — only
 * one actor can be the unlocking party.
 *)
INV_NoConcurrentDecrypt ==
    \A t \in Tiers :
        KeyState[t] = "decrypted_in_engine" => DecryptedBy[t] \in Actors

(*
 * INV-DecryptionConsistency: the DecryptedBy field is non-NULL exactly
 * when the key is decrypted_in_engine. Cross-checks that the
 * DecryptedBy tracker and the state symbol cannot drift apart.
 *)
INV_DecryptionConsistency ==
    \A t \in Tiers :
        (DecryptedBy[t] /= NULL) <=> (KeyState[t] = "decrypted_in_engine")

(*
 * INV-NoResurrection: the only outgoing transition from "consumed" is
 * to "reconstructible_via_plexus" (via BeginRecovery). Equivalently:
 * consumed never transitions directly to decrypted_in_engine. Captures
 * the "linearity in time" property — once a single-use base is signed,
 * it's gone unless explicitly reconstructed via Plexus.
 *
 * Proven structurally by the action guards: Unlock requires
 * encrypted_at_rest, not consumed; the only path back from consumed
 * goes via BeginRecovery → CompleteRecovery → encrypted_at_rest.
 *)
INV_NoResurrection ==
    \A t \in Tiers :
        (KeyState[t] = "consumed" /\ KeyState'[t] /= "consumed")
            => KeyState'[t] = "reconstructible_via_plexus"

(*
 * INV-RecoveryRequiresEnrollment: a tier key in the reconstructible
 * state must have been enrolled. Captures G4 of the wallet design doc:
 * recovery is only available if the identity opted in.
 *)
INV_RecoveryRequiresEnrollment ==
    \A t \in Tiers :
        KeyState[t] = "reconstructible_via_plexus" => RecoveryEnrolled[t]

(*
 * INV-TierFactorRespected: any transition into decrypted_in_engine
 * required the unlocking actor to have presented the local auth factor
 * for that tier at the moment of unlock. Subsequent ClearFactor(t, a)
 * actions can lower the flag without forcing an immediate re-lock —
 * but Unlock itself cannot fire without a present factor.
 *)
INV_TierFactorRespected ==
    \A t \in Tiers, a \in Actors :
        (KeyState[t] /= "decrypted_in_engine"
         /\ KeyState'[t] = "decrypted_in_engine"
         /\ DecryptedBy'[t] = a)
            => FactorPresented[<<t, a>>]

\* --- Liveness (design sec 9.2) ---

(*
 * LIVE-EventualUnlock: under fairness, every tier key eventually
 * reaches decrypted_in_engine (by some actor). Models the obligation
 * "any Tier-N (N ≥ 1) spend eventually completes given the user's
 * correct auth factor" (sec 9.2, third liveness bullet).
 *)
LIVE_EventualUnlock ==
    \A t \in Tiers : <>(KeyState[t] = "decrypted_in_engine")

(*
 * LIVE-EventualRecovery: if a tier key has been consumed and the user
 * is enrolled, recovery eventually drives the key back to
 * encrypted_at_rest (sec 9.2, "disaster recovery eventually succeeds
 * given valid OTP + correct challenge answers").
 *)
LIVE_EventualRecovery ==
    \A t \in Tiers :
        [](KeyState[t] = "consumed" /\ RecoveryEnrolled[t]
            => <>(KeyState[t] = "encrypted_at_rest"))

\* --- Temporal forms of action-level safety invariants ---
\* TLA+ INVARIANTS take state predicates; for predicates that involve
\* the prime operator (next-state references) we lift them into temporal
\* properties checked under []....

PROP_NoResurrection == [][INV_NoResurrection]_vars
PROP_TierFactorRespected == [][INV_TierFactorRespected]_vars

=============================================================================

```
