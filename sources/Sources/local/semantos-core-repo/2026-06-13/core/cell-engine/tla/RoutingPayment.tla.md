---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tla/RoutingPayment.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.956722+00:00
---

# core/cell-engine/tla/RoutingPayment.tla

```tla
---------------------------- MODULE RoutingPayment ----------------------------
\* OP_BRANCHONOUTPUT — concurrent routing payment safety model.
\*
\* Models the system-level behavior of N relays racing to claim their
\* corresponding outputs from a multi-output payment cell whose locking
\* script branches on OP_BRANCHONOUTPUT (0xE0).
\*
\* What the cell-engine-level invariants (proved in Lean4, Phase 2) give us:
\*   I3 non-malleability — current_output_index is runtime-only; no script
\*                         path can change which output it appears to claim.
\*   I4 linear single-claim — for a LINEAR cell, the script can succeed for
\*                            at most one current_output_index value.
\*
\* The TLA+ model takes those as axioms and proves the system-level safety
\* and liveness properties for concurrent claim attempts:
\*   AtMostOneClaim — each output is claimed by at most one relay.
\*   NoCrossClaim   — relay r claims output r (binding from I3).
\*   EventualResolution — every relay eventually claims or fails.
\*   AllActiveClaim — every non-failing relay eventually claims.
\*
\* Spec: ../../../docs/design/OP-BRANCHONOUTPUT-SPEC.md
\* Tracker: ../../../docs/OP-BRANCHONOUTPUT-TRACKER.md

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    N,             \* Number of relays / outputs (and hops in the route)
    MAX_FAILURES   \* Upper bound on relay failures during the model run

ASSUME N \in 1..16
ASSUME MAX_FAILURES \in 0..N

Relays  == 1..N
Outputs == 1..N

VARIABLES
    claimed,       \* claimed[i]    ∈ BOOLEAN — has output i been claimed?
    claimed_by,    \* claimed_by[i] ∈ 0..N    — which relay claimed it (0 = none)
    relay_state,   \* relay_state[r] ∈ {"running","done","failed"}
    failures       \* total relays that have failed so far

vars == <<claimed, claimed_by, relay_state, failures>>

\* ── Types ────────────────────────────────────────────────────────────────────

TypeOK ==
    /\ claimed     \in [Outputs -> BOOLEAN]
    /\ claimed_by  \in [Outputs -> 0..N]
    /\ relay_state \in [Relays  -> {"running", "done", "failed"}]
    /\ failures    \in 0..N

\* ── Initial state ────────────────────────────────────────────────────────────

Init ==
    /\ claimed     = [i \in Outputs |-> FALSE]
    /\ claimed_by  = [i \in Outputs |-> 0]
    /\ relay_state = [r \in Relays  |-> "running"]
    /\ failures    = 0

\* ── Actions ──────────────────────────────────────────────────────────────────

\* Relay r executes the locking script with current_output_index = r and
\* successfully claims output r.  This action models the post-condition of
\* a successful spend attempt: the cell engine accepted the script, OP_CHECKSIG
\* matched relay r's signature, output r is permanently bound to r.
\*
\* Note: by I3 (non-malleability), relay r CANNOT claim output i ≠ r — the
\* runtime sets current_output_index, and the only script path producing
\* done_true is the one matching the runtime's value.  This action thus
\* covers all successful claims a relay can make.
ClaimOutput(r) ==
    /\ relay_state[r] = "running"
    /\ ~claimed[r]
    /\ claimed'     = [claimed     EXCEPT ![r] = TRUE]
    /\ claimed_by'  = [claimed_by  EXCEPT ![r] = r]
    /\ relay_state' = [relay_state EXCEPT ![r] = "done"]
    /\ UNCHANGED failures

\* Relay r fails before claiming (network partition, crash, validation
\* timeout, payment expiry, etc.).  Bounded by MAX_FAILURES to keep the
\* model state space finite.
RelayFail(r) ==
    /\ relay_state[r] = "running"
    /\ failures < MAX_FAILURES
    /\ relay_state' = [relay_state EXCEPT ![r] = "failed"]
    /\ failures'    = failures + 1
    /\ UNCHANGED <<claimed, claimed_by>>

\* Self-loop once every relay has resolved (claimed or failed).  Without
\* this, TLC reports a spurious "deadlock" when the system reaches its
\* natural terminal state.  Stuttering here is correct behavior.
AllResolved == \A r \in Relays : relay_state[r] \in {"done", "failed"}

Termination ==
    /\ AllResolved
    /\ UNCHANGED vars

Next ==
    \/ \E r \in Relays : ClaimOutput(r)
    \/ \E r \in Relays : RelayFail(r)
    \/ Termination

\* Weak fairness on every per-relay action: a continuously enabled
\* running relay must eventually act (claim or fail).
Fairness == \A r \in Relays : WF_vars(ClaimOutput(r) \/ RelayFail(r))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ── Safety invariants ───────────────────────────────────────────────────────

\* SAFETY-1.  AtMostOneClaim: each output is claimed by at most one relay.
\* (Trivially true here — `claimed` is a boolean and ClaimOutput's guard
\* `~claimed[r]` forbids re-claim.  Stated explicitly for clarity.)
AtMostOneClaim ==
    \A i \in Outputs : claimed[i] => claimed_by[i] /= 0

\* SAFETY-2.  NoCrossClaim: relay r can only claim output r.  This is the
\* TLA+ statement of I3 (non-malleability) lifted to the system level:
\* OP_BRANCHONOUTPUT binds claim r ↔ output r structurally.
NoCrossClaim ==
    \A i \in Outputs : claimed[i] => claimed_by[i] = i

\* SAFETY-3.  ClaimImpliesDone: a claimed output's relay is in done state.
\* Ensures we cannot have stale "running" relays holding claims.
ClaimImpliesDone ==
    \A i \in Outputs : claimed[i] => relay_state[i] = "done"

\* SAFETY-4.  DoneImpliesClaim: a "done" relay has claimed its output.
\* The converse — a relay only transitions to "done" via a successful claim.
DoneImpliesClaim ==
    \A r \in Relays : relay_state[r] = "done" => claimed[r]

\* SAFETY-5.  FailureBound: total failures never exceed MAX_FAILURES.
FailureBound == failures <= MAX_FAILURES

\* ── Liveness properties ────────────────────────────────────────────────────

\* LIVENESS-1.  EventualResolution: every relay eventually transitions
\* out of "running" (to either "done" or "failed").  No relay stalls.
EventualResolution ==
    \A r \in Relays : <>(relay_state[r] \in {"done", "failed"})

\* LIVENESS-2.  AllActiveClaim: every relay eventually either fails
\* or claims its output.  Together with FailureBound, this guarantees
\* that at least (N - MAX_FAILURES) outputs get claimed.
AllActiveClaim ==
    <>(\A r \in Relays : relay_state[r] = "failed" \/ claimed[r])

\* ── Theorems ────────────────────────────────────────────────────────────────

THEOREM Safety ==
    Spec =>
       /\ []TypeOK
       /\ []AtMostOneClaim
       /\ []NoCrossClaim
       /\ []ClaimImpliesDone
       /\ []DoneImpliesClaim
       /\ []FailureBound

THEOREM Liveness ==
    Spec =>
       /\ EventualResolution
       /\ AllActiveClaim

==============================================================================

```
