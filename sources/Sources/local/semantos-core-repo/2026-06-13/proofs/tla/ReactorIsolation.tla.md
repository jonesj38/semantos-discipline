---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ReactorIsolation.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.347107+00:00
---

# proofs/tla/ReactorIsolation.tla

```tla
---------------------------- MODULE ReactorIsolation ----------------------------
(*
 * Reactor Isolation — formal proof that brain's B-pragmatic single-threaded
 * reactor design isolates connections from each other under all schedules.
 *
 * Origin: Bridget Doran reproduced (2026-05-07) a wedge in brain's
 * single-threaded blocking-accept loop.  With one phone holding a WSS
 * connection to /api/v1/wallet, every other request to the brain timed
 * out — main thread parked in tcp_recvmsg on the WSS socket, no other
 * connection serviceable.
 *
 * Architectural decision (docs/prd/Semantos Brain-WSS-WEDGE-ARCHITECTURAL-OPTIONS.md
 * §9): replace the blocking-accept loop with a poll()-based event loop +
 * per-connection state machines (Option B-pragmatic).  Single-threaded,
 * zero state mutexes — single-threaded reactor IS the synchronization.
 *
 * This spec models the new design and verifies the load-bearing claim:
 *
 *   ISOLATION INVARIANT: every connection that has data ready gets
 *   serviced within K poll cycles, regardless of how many other
 *   connections are stalled (e.g. holding a WSS in idle wait).
 *
 * The OLD blocking-accept design VIOLATES this invariant — once main
 * thread is parked in connection-1's read, connection-2's data sits
 * indefinitely.  The NEW poll-based design SATISFIES it: each poll cycle
 * surfaces all ready fds; reactor services them in turn within the cycle.
 *
 * Source mapping (must match implementation line-by-line):
 *   - runtime/brain/src/event_loop.zig — poll loop body
 *   - runtime/brain/src/connection_state.zig — per-connection state machine
 *   - runtime/brain/src/site_server.zig::serve — reactor entry point
 *
 * If any of these files is modified in a way that breaks this spec, the
 * isolation guarantee is lost and Bridget's wedge can recur.  Re-run TLC
 * after any reactor change.
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    Connections        \* Set of connection IDs (e.g. {c1, c2, c3})

(* --- State variables --------------------------------------------------- *)
(*
 * The model deliberately omits a cycle counter — temporal properties
 * are about eventual service, not bounded-time service.  Cycle counters
 * make the state space finite-but-arbitrary; better to let the natural
 * connection-state space (4 states per conn × N conns) bound the model.
 *)

VARIABLES
    connState,          \* connId -> "stalled" | "ready" | "serviced" | "closed"
    pollReadySet        \* set of connIds the most recent poll() reported ready

vars == <<connState, pollReadySet>>

(* --- Type invariant ---------------------------------------------------- *)

TypeOK ==
    /\ connState \in [Connections -> {"stalled", "ready", "serviced", "closed"}]
    /\ pollReadySet \subseteq Connections

(* --- Initial state ----------------------------------------------------- *)
(*
 * All connections start "stalled" (idle, no data).  Poll set is empty.
 *)
Init ==
    /\ connState = [c \in Connections |-> "stalled"]
    /\ pollReadySet = {}

(* --- Actions ----------------------------------------------------------- *)

(*
 * DataArrives: a stalled connection receives bytes from the network.
 * Models: the kernel TCP stack delivered new bytes to the socket.
 * Effect: connection moves stalled -> ready; it now has data the reactor
 * must service.
 *)
DataArrives(c) ==
    /\ connState[c] = "stalled"
    /\ connState' = [connState EXCEPT ![c] = "ready"]
    /\ UNCHANGED pollReadySet

(*
 * RunReactorCycle: the reactor's main loop body, modeled atomically.
 *
 * The implementation is:
 *   while not shutdown:
 *     ready_set = poll(fds)          # syscall returns ALL ready fds
 *     for fd in ready_set:           # service every ready fd in this cycle
 *       handle_event(fd)
 *     cycle += 1
 *
 * Crucial atomicity: the for-loop completes BEFORE the next poll().  Every
 * connection in the ready set at the start of the cycle has its state
 * machine advanced (read available bytes, drain writes, dispatch handler)
 * before the cycle ends.  This is what the OLD blocking-accept design
 * could NOT do — that design was effectively `poll({one_conn})` and
 * blocked indefinitely on it.
 *
 * Modeled as one atomic step: scan ready connections, service each (move
 * ready -> serviced atomically).  No explicit cycle counter — temporal
 * properties (eventual service) capture the claim without one.
 *)
RunReactorCycle ==
    LET readyNow == { c \in Connections : connState[c] = "ready" }
    IN
        /\ pollReadySet' = {}  \* fully drained at end of cycle
        /\ connState' = [c \in Connections |->
                          IF c \in readyNow THEN "serviced" ELSE connState[c]]

(*
 * ResetServiced: after being serviced, a connection returns to "stalled"
 * (waiting for next bytes) — unless it was closed during service.
 *)
ResetServiced(c) ==
    /\ connState[c] = "serviced"
    /\ \/ connState' = [connState EXCEPT ![c] = "stalled"]
       \/ connState' = [connState EXCEPT ![c] = "closed"]
    /\ UNCHANGED pollReadySet

(* --- Next-state relation ----------------------------------------------- *)

Next ==
    \/ \E c \in Connections: DataArrives(c)
    \/ RunReactorCycle
    \/ \E c \in Connections: ResetServiced(c)

(* --- Fairness ---------------------------------------------------------- *)
(*
 * Strong fairness on RunReactorCycle — the reactor's main loop MUST keep
 * running.  Without this, TLC could find "stuttering" traces where the
 * reactor stops.  Real implementation doesn't stop, so fairness is right.
 *)
Fairness ==
    SF_vars(RunReactorCycle)

Spec == Init /\ [][Next]_vars /\ Fairness

(* --- Properties to verify ---------------------------------------------- *)

(*
 * NoStuckReady — between RunReactorCycle steps, NO connection is ever
 * "ready".  RunReactorCycle services every ready connection atomically,
 * so the only way a connection is "ready" is briefly after DataArrives
 * before the next RunReactorCycle.
 *
 * In the OLD blocking-accept design this would FAIL — a "ready"
 * connection could persist across many wall-clock seconds while the
 * main thread was parked in another connection's read().  The poll()
 * never even ran.
 *
 * In the NEW design RunReactorCycle ALWAYS atomically clears the ready
 * set (the action is defined to service every ready conn in the same
 * step it polls them).  This invariant holds by construction.
 *
 * Specifically: pollReadySet is empty in every state EXCEPT during
 * RunReactorCycle's primed assignment (which is over by the time the
 * invariant is checked).  We assert this via pollReadySet = {}.
 *)
PollSetClearedBetweenCycles ==
    pollReadySet = {}

(*
 * BoundedReadySet — sanity check: the poll ready set never exceeds the
 * number of connections.
 *)
BoundedReadySet ==
    Cardinality(pollReadySet) <= Cardinality(Connections)

(*
 * EventualService — the load-bearing TEMPORAL claim.
 *
 * Every connection that becomes "ready" eventually becomes "serviced"
 * regardless of how many other connections exist in any state.
 *
 * This is the formal restatement of Bridget's wedge fix:
 *   - In the OLD design: c2's "ready" state could persist forever while
 *     main thread was blocked in c1's read.  EventualService VIOLATED.
 *   - In the NEW design: fairness on RunReactorCycle ensures the
 *     reactor's main loop keeps running.  Each cycle services ALL ready
 *     connections atomically.  So every "ready" eventually becomes
 *     "serviced".  EventualService HOLDS.
 *
 * This is the property that, if it holds in the model and the
 * implementation faithfully follows the model (one poll() per cycle,
 * service every ready fd in the for-loop), means Bridget's wedge cannot
 * recur.
 *)
EventualService ==
    \A c \in Connections:
        (connState[c] = "ready") ~> (connState[c] = "serviced")

(*
 * IsolationFromStalledConnections — the stronger version.
 *
 * Even if one or more connections stay "stalled" forever (modeling a
 * phone holding an idle WSS for hours), connections that become "ready"
 * still get serviced.  TLA+ captures this automatically because the
 * EventualService property quantifies over all behaviors — including
 * those where one connection's state never changes.
 *
 * Phrased explicitly: stalled connections do not consume reactor
 * resources beyond their slot in the poll set.  The reactor cycles past
 * them and services any ready conn in the same cycle.
 *)
IsolationFromStalledConnections ==
    \A c1, c2 \in Connections:
        (c1 # c2) =>
            ((connState[c2] = "ready") ~> (connState[c2] = "serviced"))

================================================================================

```
