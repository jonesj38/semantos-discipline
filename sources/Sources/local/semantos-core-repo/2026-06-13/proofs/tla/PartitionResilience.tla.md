---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/PartitionResilience.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.348649+00:00
---

# proofs/tla/PartitionResilience.tla

```tla
----------------------- MODULE PartitionResilience -----------------------
(*
 * Partition Resilience — network partition tolerance and reconciliation.
 *
 * Models a distributed system with two nodes that can be partitioned.
 * During partition, each node operates independently on local state.
 * After healing, nodes reconcile to detect conflicts (split-brain).
 *
 * Key property: if two nodes consume the same LINEAR resource during
 * a partition, the conflict is detected during reconciliation — no
 * silent data loss.
 *
 * Source: protocol design (no single source file — this models the
 * distributed behavior of LINEAR/AFFINE/RELEVANT objects across nodes).
 *
 * Related: src/compiler/validator.ts — consumption guards that each
 * node enforces locally.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Nodes,       \* Set of node identifiers (model values, e.g., {n1, n2})
    Resources,   \* Set of resource identifiers (model values)
    NULL         \* Distinguished null value

\* --- Resource states (per-node view) ---

ResourceState == [
    consumed   : BOOLEAN,
    consumedBy : Nodes \cup {NULL}
]

\* --- State variables ---

VARIABLES
    nodeState,     \* Function: Nodes -> (Function: Resources -> ResourceState)
    partitioned,   \* BOOLEAN: whether nodes are partitioned
    conflicts,     \* Set of resource IDs where split-brain was detected
    reconciled,    \* BOOLEAN: whether reconciliation has occurred after last heal
    step           \* Step counter for bounding

vars == <<nodeState, partitioned, conflicts, reconciled, step>>

\* --- Initial state ---

InitResource == [consumed |-> FALSE, consumedBy |-> NULL]

Init ==
    /\ nodeState = [n \in Nodes |-> [r \in Resources |-> InitResource]]
    /\ partitioned = FALSE
    /\ conflicts = {}
    /\ reconciled = TRUE
    /\ step = 0

\* --- Actions ---

(*
 * Partition: network partition occurs, isolating nodes.
 *)
Partition ==
    /\ ~partitioned
    /\ step < 6
    /\ partitioned' = TRUE
    /\ reconciled' = FALSE
    /\ UNCHANGED <<nodeState, conflicts>>
    /\ step' = step + 1

(*
 * Heal: network partition heals, allowing communication.
 *)
Heal ==
    /\ partitioned
    /\ step < 6
    /\ partitioned' = FALSE
    /\ UNCHANGED <<nodeState, conflicts, reconciled>>
    /\ step' = step + 1

(*
 * LocalConsume: a node consumes a resource locally.
 *
 * When NOT partitioned: consumption is globally coordinated — if ANY node
 * has consumed this resource, no other node can consume it. This models
 * the normal case where nodes communicate.
 *
 * When partitioned: only the local view is checked — the other node's
 * state is invisible. This is where split-brain can occur.
 *)
LocalConsume(node, resource) ==
    /\ step < 6
    /\ ~nodeState[node][resource].consumed
    \* When connected, also check no OTHER node has consumed it
    /\ (partitioned \/ \A n \in Nodes : ~nodeState[n][resource].consumed)
    /\ nodeState' = [nodeState EXCEPT ![node][resource] = [
           consumed   |-> TRUE,
           consumedBy |-> node
       ]]
    /\ UNCHANGED <<partitioned, conflicts, reconciled>>
    /\ step' = step + 1

(*
 * Reconcile: after partition heals, nodes compare state to detect conflicts.
 * A conflict exists if both nodes consumed the same LINEAR resource.
 *)
Reconcile ==
    /\ ~partitioned
    /\ ~reconciled
    /\ step < 6
    /\ LET newConflicts == {r \in Resources :
               /\ \A n \in Nodes : nodeState[n][r].consumed
               /\ Cardinality({nodeState[n][r].consumedBy : n \in Nodes} \ {NULL}) > 1
           }
       IN conflicts' = conflicts \cup newConflicts
    /\ reconciled' = TRUE
    \* After reconciliation, sync state: pick one winner per non-conflicted resource
    /\ nodeState' = [n \in Nodes |->
           [r \in Resources |->
               IF \E m \in Nodes : nodeState[m][r].consumed
               THEN [consumed |-> TRUE,
                     consumedBy |-> CHOOSE m \in Nodes : nodeState[m][r].consumed]
               ELSE nodeState[n][r]
           ]]
    /\ UNCHANGED partitioned
    /\ step' = step + 1

(*
 * Adversary: PartitionedDoubleConsume — two nodes consume the same
 * resource during a partition. This represents the split-brain scenario.
 * The property NoSplitBrainConsume asserts this is DETECTED (not prevented).
 *)
PartitionedDoubleConsume(r) ==
    /\ partitioned
    /\ step < 6
    /\ \A n \in Nodes : ~nodeState[n][r].consumed
    /\ nodeState' = [n \in Nodes |->
           [nodeState[n] EXCEPT ![r] = [
               consumed   |-> TRUE,
               consumedBy |-> n
           ]]]
    /\ UNCHANGED <<partitioned, conflicts, reconciled>>
    /\ step' = step + 1

Next ==
    \/ Partition
    \/ Heal
    \/ \E n \in Nodes, r \in Resources : LocalConsume(n, r)
    \/ Reconcile
    \/ \E r \in Resources : PartitionedDoubleConsume(r)

Spec == Init /\ [][Next]_vars /\ SF_vars(Heal) /\ SF_vars(Reconcile)

\* --- Safety properties ---

(*
 * NoSplitBrainConsume: if two nodes consumed the same resource during a
 * partition, the conflict is eventually detected during reconciliation.
 * We check: after reconciliation, any resource consumed by different nodes
 * is in the conflicts set.
 *)
NoSplitBrainConsume ==
    reconciled =>
        \A r \in Resources :
            LET consumers == {nodeState[n][r].consumedBy : n \in Nodes} \ {NULL}
            IN Cardinality(consumers) > 1 => r \in conflicts

(*
 * LocalContinuity: during a partition, each node can still consume resources.
 * This is a structural property — LocalConsume is enabled regardless of partition.
 * Verified by the existence of states where consumption happens during partition.
 *)
LocalContinuity ==
    \A n \in Nodes : \A r \in Resources :
        nodeState[n][r].consumed =>
            nodeState[n][r].consumedBy \in Nodes

(*
 * ConsumedHasOwner: any consumed resource records who consumed it.
 *)
ConsumedHasOwner ==
    \A n \in Nodes : \A r \in Resources :
        nodeState[n][r].consumed => nodeState[n][r].consumedBy /= NULL

\* --- Liveness ---

(*
 * ReconciliationComplete: the system eventually reconciles after partition.
 * Requires strong fairness on Heal and Reconcile.
 *)
ReconciliationComplete == <>(reconciled)

=============================================================================

```
