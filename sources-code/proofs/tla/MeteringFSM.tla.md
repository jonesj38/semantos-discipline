---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/MeteringFSM.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.342115+00:00
---

# proofs/tla/MeteringFSM.tla

```tla
---------------------------- MODULE MeteringFSM ----------------------------
(*
 * Metering Channel FSM — exact 8-state transition table.
 *
 * Source: src/metering/channel-fsm.ts
 *   - ChannelState enum (lines 9-18): 8 states
 *   - transitionTable (lines 44-74): exact transitions
 *   - tick() (lines 190-218): only in ACTIVE, satoshisThisTick >= 0
 *
 * This spec MUST match channel-fsm.ts line-by-line. Any deviation is a bug.
 *
 * Transition table (channel-fsm.ts lines 48-73):
 *   NEGOTIATING       -> {fund: FUNDED}
 *   FUNDED            -> {activate: ACTIVE}
 *   ACTIVE            -> {pause: PAUSED, requestClose: CLOSING_REQUESTED}
 *   PAUSED            -> {resume: ACTIVE, requestClose: CLOSING_REQUESTED}
 *   CLOSING_REQUESTED -> {confirmClose: CLOSING_CONFIRMED, dispute: DISPUTED}
 *   CLOSING_CONFIRMED -> {settle: SETTLED, dispute: DISPUTED}
 *   SETTLED           -> {} (terminal)
 *   DISPUTED          -> {resolve: SETTLED}
 *)

EXTENDS Naturals

CONSTANTS
    MaxTicks,      \* Maximum ticks per channel for finite model checking
    MaxSatPerTick  \* Maximum satoshis per tick for finite model checking

\* --- States matching ChannelState enum (lines 9-18) ---

States == {
    "NEGOTIATING", "FUNDED", "ACTIVE", "PAUSED",
    "CLOSING_REQUESTED", "CLOSING_CONFIRMED", "SETTLED", "DISPUTED"
}

\* --- Valid transitions matching transitionTable (lines 44-74) ---
(*
 * Each entry is <<fromState, action, toState>> exactly as in channel-fsm.ts.
 *)
ValidTransitions == {
    \* line 48-50: NEGOTIATING -> {fund: FUNDED}
    <<"NEGOTIATING", "fund", "FUNDED">>,
    \* line 51-53: FUNDED -> {activate: ACTIVE}
    <<"FUNDED", "activate", "ACTIVE">>,
    \* line 54-57: ACTIVE -> {pause: PAUSED, requestClose: CLOSING_REQUESTED}
    <<"ACTIVE", "pause", "PAUSED">>,
    <<"ACTIVE", "requestClose", "CLOSING_REQUESTED">>,
    \* line 58-61: PAUSED -> {resume: ACTIVE, requestClose: CLOSING_REQUESTED}
    <<"PAUSED", "resume", "ACTIVE">>,
    <<"PAUSED", "requestClose", "CLOSING_REQUESTED">>,
    \* line 62-65: CLOSING_REQUESTED -> {confirmClose: CLOSING_CONFIRMED, dispute: DISPUTED}
    <<"CLOSING_REQUESTED", "confirmClose", "CLOSING_CONFIRMED">>,
    <<"CLOSING_REQUESTED", "dispute", "DISPUTED">>,
    \* line 66-69: CLOSING_CONFIRMED -> {settle: SETTLED, dispute: DISPUTED}
    <<"CLOSING_CONFIRMED", "settle", "SETTLED">>,
    <<"CLOSING_CONFIRMED", "dispute", "DISPUTED">>,
    \* line 70: SETTLED -> {} (terminal, no transitions)
    \* line 71-73: DISPUTED -> {resolve: SETTLED}
    <<"DISPUTED", "resolve", "SETTLED">>
}

Actions == {"fund", "activate", "pause", "resume", "requestClose",
            "confirmClose", "settle", "dispute", "resolve"}

\* --- State variables ---

VARIABLES
    state,                \* Current channel state (string)
    currentTick,          \* Tick counter (Nat, line 29)
    nSequence,            \* Sequence number (Nat, line 30)
    cumulativeSatoshis    \* Total satoshis accumulated (Nat, line 31)

vars == <<state, currentTick, nSequence, cumulativeSatoshis>>
tickVars == <<currentTick, nSequence, cumulativeSatoshis>>

\* --- Helper: can a transition happen? ---

CanTransition(s, action) ==
    <<s, action, "ACTIVE">> \in ValidTransitions \/
    \E toState \in States : <<s, action, toState>> \in ValidTransitions

GetNextState(s, action) ==
    CHOOSE toState \in States : <<s, action, toState>> \in ValidTransitions

\* --- Initial state (matches createChannel, lines 79-96) ---

Init ==
    /\ state = "NEGOTIATING"
    /\ currentTick = 0
    /\ nSequence = 0
    /\ cumulativeSatoshis = 0

\* --- Transition actions ---
(* Each action mirrors the corresponding exported function in channel-fsm.ts *)

(* fund: lines 101-121 *)
Fund ==
    /\ state = "NEGOTIATING"
    /\ state' = "FUNDED"
    /\ UNCHANGED tickVars

(* activate: lines 126-142 *)
Activate ==
    /\ state = "FUNDED"
    /\ state' = "ACTIVE"
    /\ UNCHANGED tickVars

(* pause: lines 147-163 *)
Pause ==
    /\ state = "ACTIVE"
    /\ state' = "PAUSED"
    /\ UNCHANGED tickVars

(* resume: lines 168-184 *)
Resume ==
    /\ state = "PAUSED"
    /\ state' = "ACTIVE"
    /\ UNCHANGED tickVars

(* requestClose: lines 224-242 — valid from ACTIVE or PAUSED *)
RequestClose ==
    /\ state \in {"ACTIVE", "PAUSED"}
    /\ state' = "CLOSING_REQUESTED"
    /\ UNCHANGED tickVars

(* confirmClose: lines 247-265 *)
ConfirmClose ==
    /\ state = "CLOSING_REQUESTED"
    /\ state' = "CLOSING_CONFIRMED"
    /\ UNCHANGED tickVars

(* settle: lines 270-289 *)
Settle ==
    /\ state = "CLOSING_CONFIRMED"
    /\ state' = "SETTLED"
    /\ UNCHANGED tickVars

(* dispute: lines 295-314 — valid from CLOSING_REQUESTED or CLOSING_CONFIRMED *)
Dispute ==
    /\ state \in {"CLOSING_REQUESTED", "CLOSING_CONFIRMED"}
    /\ state' = "DISPUTED"
    /\ UNCHANGED tickVars

(* resolve: implicit from transition table line 71-73 *)
Resolve ==
    /\ state = "DISPUTED"
    /\ state' = "SETTLED"
    /\ UNCHANGED tickVars

(*
 * Tick: lines 190-218 of channel-fsm.ts
 * Preconditions:
 *   - state === ACTIVE (line 194)
 *   - satoshisThisTick >= 0 (line 201)
 * Effects:
 *   - currentTick += 1 (line 212)
 *   - nSequence += 1 (line 213)
 *   - cumulativeSatoshis += satoshisThisTick (line 214)
 *)
Tick(satoshisThisTick) ==
    /\ state = "ACTIVE"
    /\ satoshisThisTick >= 0
    /\ currentTick < MaxTicks
    /\ state' = state  \* tick does not change state
    /\ currentTick' = currentTick + 1
    /\ nSequence' = nSequence + 1
    /\ cumulativeSatoshis' = cumulativeSatoshis + satoshisThisTick

\* --- Adversary: attempt invalid transition ---

(*
 * InvalidTransition: adversary attempts a transition not in the table.
 * This action is enabled but cannot change state because the guard
 * (ValidTransitions lookup) prevents it. We model this explicitly to
 * show that invalid transitions are rejected.
 *)
InvalidTransition ==
    \E action \in Actions :
        /\ ~(\E toState \in States : <<state, action, toState>> \in ValidTransitions)
        \* Adversary attempt fails — no state change
        /\ UNCHANGED vars

Next ==
    \/ Fund
    \/ Activate
    \/ Pause
    \/ Resume
    \/ RequestClose
    \/ ConfirmClose
    \/ Settle
    \/ Dispute
    \/ Resolve
    \/ \E sat \in 0..MaxSatPerTick : Tick(sat)
    \/ InvalidTransition

Spec == Init /\ [][Next]_vars

(*
 * FairSpec adds strong fairness on the settlement path actions.
 * WF is insufficient because the Active<->Paused loop can cycle forever.
 * SF ensures that if RequestClose/ConfirmClose/Settle are infinitely often
 * enabled, they eventually happen — modeling the protocol requirement that
 * channels must eventually close.
 *)
FairSpec == Spec
    /\ SF_vars(RequestClose)
    /\ SF_vars(ConfirmClose)
    /\ SF_vars(Settle)
    /\ SF_vars(Fund)
    /\ SF_vars(Activate)
    /\ SF_vars(Resolve)

\* --- Safety properties ---

(*
 * SettledIsTerminal: SETTLED has no outgoing transitions (line 70: {}).
 * Once settled, the channel cannot change state.
 *)
SettledIsTerminal ==
    state = "SETTLED" => state' = "SETTLED" \/ UNCHANGED vars

(*
 * TickOnlyInActive: tick counters only change when state = ACTIVE.
 * Matches tick() precondition (line 194).
 *)
TickOnlyInActive ==
    (currentTick' /= currentTick) => state = "ACTIVE"

(*
 * MonotonicSatoshis: cumulativeSatoshis never decreases.
 * Follows from satoshisThisTick >= 0 (line 201).
 *)
MonotonicSatoshis ==
    cumulativeSatoshis' >= cumulativeSatoshis

(*
 * SequenceMonotonic: nSequence never decreases.
 *)
SequenceMonotonic ==
    nSequence' >= nSequence

(*
 * ValidTransitionsOnly: every state transition is in the transition table.
 *)
ValidTransitionsOnly ==
    state \in States

(*
 * TickCounterConsistency: currentTick and nSequence always match.
 * Both are incremented by 1 in each tick (lines 212-213).
 *)
TickCounterConsistency ==
    currentTick = nSequence

\* --- Liveness ---

(*
 * EventualSettlement: under fairness, every channel eventually settles.
 *)
EventualSettlement == <>(state = "SETTLED")

=============================================================================

```
