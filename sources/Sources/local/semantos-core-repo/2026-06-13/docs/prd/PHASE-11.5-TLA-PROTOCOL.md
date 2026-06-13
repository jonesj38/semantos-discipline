---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-11.5-TLA-PROTOCOL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.681994+00:00
---

# Phase 11.5 — TLA+ Protocol Model: Hash Chains, FSM, Concurrency

**Depends on**: Phase 11 (Lean proofs provide kernel invariants; TLA+ models the protocol layer above)
**Branch**: `phase-11.5-tla-protocol`
**Tag**: `v11.5`

---

## Objective

Model check the distributed protocol properties that Lean cannot reach: temporal ordering, replay prevention under concurrency, FSM correctness across interleavings, partition resilience, and hash-chain integrity. These are the properties that involve multiple actors, time, and network behavior.

Lean proves "the kernel enforces linearity." TLA+ proves "even with concurrent actors and network failures, the protocol-level properties hold for bounded state spaces." Together with stated assumptions (crypto primitives, host import correctness, trusted boot), these provide the kernel's contribution to regulatory requirement satisfaction.

---

## Deliverables

### D11.5.0: TLA+ Project Scaffold + Base Types

**What**: Initialize TLA+ specs directory. Define base types (SemanticObject, PlexusCert, EvidenceItem, ChannelState) and the state space.

**Files**:
- `proofs/tla/SemanticTypes.tla` — type definitions, constants
- `proofs/tla/README.md` — how to run TLC, what each spec checks

**Base types**:

```tla
CONSTANTS
  ObjectIDs,         \* e.g., {"obj1", "obj2", "obj3"}
  CertIDs,           \* e.g., {"operator_a", "sensor_b", "admin_c"}
  DomainFlags,       \* e.g., {1, 4}  (Zone 1, Zone 4)
  LinearityTypes     \* {"LINEAR", "AFFINE", "RELEVANT"}

VARIABLES
  objects,           \* ObjectIDs -> [linearity, stateHash, prevStateHash, consumed, payload, authorCert, timestamp]
  certs,             \* CertIDs -> [pubkey, revoked, domainFlags, issuedAt]
  evidenceChain,     \* Seq([objectId, action, certId, timestamp, prevHash, stateHash])
  channels,          \* ChannelIDs -> [state, providerCert, consumerCert, tick, satoshis]
  bsvAnchors,        \* Set of [stateHash, blockHeight]
  clock              \* Monotonic logical clock
```

**Gate**: TLC parses the spec without errors. Type invariant holds on initial state.

**Commit**: `phase-11.5/D11.5.0: TLA+ scaffold + base types`

---

### D11.5.1: Hash-Chain Integrity (K6 — kernel contribution to Tests 3.3.1, P2.1)

**What**: Model the evidence chain as an append-only sequence where each item's prevHash equals the previous item's stateHash. Prove this is an invariant under all reachable states.

**File**: `proofs/tla/EvidenceChain.tla`

**Actions**:
- `AppendEvidence(objectId, action, certId)` — appends a new evidence item with correct hash chaining
- `TamperEvidence(index)` — adversary action that modifies a chain entry
- `VerifyChain` — checks chain integrity against BSV anchors

**Properties to check**:

```tla
\* Invariant: chain is always well-linked
ChainIntegrity ==
  \A i \in 2..Len(evidenceChain) :
    evidenceChain[i].prevHash = evidenceChain[i-1].stateHash

\* Temporal: if an adversary tampers, verification detects it
TamperDetectable ==
  []([](TamperOccurred => <>VerificationFails))

\* Temporal: events are ordered — if A happened before B, A's index < B's index
TemporalOrdering ==
  \A i, j \in 1..Len(evidenceChain) :
    evidenceChain[i].timestamp < evidenceChain[j].timestamp => i < j
```

**Model checking bounds**: 3 objects, 3 certs, evidence chain up to 8 items, 1 adversary tamper action.

**Gate**: TLC exhaustively checks all reachable states. ChainIntegrity and TemporalOrdering hold. TamperDetectable holds under fairness.

**Commit**: `phase-11.5/D11.5.1: evidence chain integrity model + temporal ordering`

---

### D11.5.2: Replay Prevention Under Concurrency (kernel contribution to Test 1.1.2)

**What**: Model concurrent actors attempting to consume the same LINEAR object. Prove that exactly one succeeds and all others fail.

**File**: `proofs/tla/ReplayPrevention.tla`

**Actions**:
- `ConsumeObject(certId, objectId)` — certified actor consumes a LINEAR object
- `ReplayAttack(capturedCommand, objectId)` — adversary replays a previously captured command

**Properties**:

```tla
\* Safety: a consumed LINEAR object stays consumed
LinearConsumedForever ==
  \A obj \in DOMAIN objects :
    objects[obj].linearity = "LINEAR" /\ objects[obj].consumed =>
      [][objects'[obj].consumed]_objects

\* Safety: no two different consume actions succeed on the same LINEAR object
SingleConsumption ==
  \A obj \in DOMAIN objects :
    objects[obj].linearity = "LINEAR" =>
      Cardinality({e \in Range(evidenceChain) : e.objectId = obj /\ e.action = "consume"}) <= 1

\* Replay impossibility: replayed command always fails
ReplayAlwaysFails ==
  \A obj \in DOMAIN objects :
    objects[obj].consumed =>
      ~ENABLED ConsumeObject(_, obj)
```

**Model checking bounds**: 3 objects (2 LINEAR, 1 AFFINE), 3 actors, up to 2 concurrent consume attempts per object.

**Gate**: TLC verifies SingleConsumption and ReplayAlwaysFails across all interleavings.

**Commit**: `phase-11.5/D11.5.2: replay prevention + concurrent consumption model`

---

### D11.5.3: Revocation Immediacy (kernel contribution to Test 1.3.1)

**What**: Model cert revocation as a state transition. Prove that after revocation, no action signed by the revoked cert succeeds.

**File**: `proofs/tla/CertRevocation.tla`

**Actions**:
- `RevokeCert(certId)` — marks cert as revoked in the state
- `AttemptSignedAction(certId, objectId, action)` — attempts an action using a cert

**Properties**:

```tla
\* Safety: revoked cert cannot perform any action
RevocationImmediate ==
  \A cert \in DOMAIN certs :
    certs[cert].revoked =>
      ~(\E action \in PossibleActions : ENABLED AttemptSignedAction(cert, _, action))

\* The revocation itself is recorded in the evidence chain
RevocationRecorded ==
  \A cert \in DOMAIN certs :
    certs[cert].revoked =>
      \E e \in Range(evidenceChain) : e.action = "revoke" /\ e.certId = cert
```

**Gate**: TLC verifies RevocationImmediate across all interleavings.

**Commit**: `phase-11.5/D11.5.3: cert revocation immediacy model`

---

### D11.5.4: Metering FSM Correctness (Channel FSM from `channel-fsm.ts`)

**What**: Model the 8-state metering channel FSM. Prove no invalid transitions, no stuck states (except SETTLED), and correct tick accounting.

**File**: `proofs/tla/MeteringFSM.tla`

**States**: `NEGOTIATING, FUNDED, ACTIVE, PAUSED, CLOSING_REQUESTED, CLOSING_CONFIRMED, SETTLED, DISPUTED`

**Transition table** (from `src/metering/channel-fsm.ts`):

```tla
Transitions == [
  NEGOTIATING       |-> {"fund"},
  FUNDED            |-> {"activate"},
  ACTIVE            |-> {"pause", "requestClose"},
  PAUSED            |-> {"resume", "requestClose"},
  CLOSING_REQUESTED |-> {"confirmClose", "dispute"},
  CLOSING_CONFIRMED |-> {"settle", "dispute"},
  SETTLED           |-> {},
  DISPUTED          |-> {"resolve"}
]
```

**Properties**:

```tla
\* Safety: only valid transitions
ValidTransitionsOnly ==
  \A ch \in DOMAIN channels :
    channels'[ch].state # channels[ch].state =>
      \E event \in Transitions[channels[ch].state] :
        channels'[ch].state = NextState(channels[ch].state, event)

\* Liveness: ACTIVE always eventually reaches SETTLED (under fairness)
EventualSettlement ==
  \A ch \in DOMAIN channels :
    channels[ch].state = "ACTIVE" ~> channels[ch].state = "SETTLED"

\* Safety: tick only increments in ACTIVE state
TickOnlyInActive ==
  \A ch \in DOMAIN channels :
    channels'[ch].tick > channels[ch].tick =>
      channels[ch].state = "ACTIVE"

\* Safety: settled amount matches cumulative ticks
SettlementCorrect ==
  \A ch \in DOMAIN channels :
    channels[ch].state = "SETTLED" =>
      channels[ch].satoshis = channels[ch].tick * pricePerUnit
```

**Model checking bounds**: 2 channels, up to 5 ticks each, all state transitions explored.

**Gate**: TLC verifies ValidTransitionsOnly and TickOnlyInActive. EventualSettlement holds under weak fairness.

**Commit**: `phase-11.5/D11.5.4: metering FSM correctness model`

---

### D11.5.5: Zone Boundary Enforcement (kernel contribution to Test 2.1.1)

**What**: Model multi-zone architecture where each cert has domain flags and each object belongs to a zone. Prove cross-zone access is impossible without matching flags.

**File**: `proofs/tla/ZoneBoundary.tla`

**Properties**:

```tla
\* Safety: action on object requires matching domain flag
ZoneEnforcement ==
  \A obj \in DOMAIN objects, cert \in DOMAIN certs :
    ActionSucceeds(cert, obj) =>
      objects[obj].domainFlag \in certs[cert].domainFlags

\* Zone 4 cert cannot access Zone 1 object
NoZoneCrossing ==
  \A cert \in DOMAIN certs, obj \in DOMAIN objects :
    certs[cert].domainFlags = {4} /\ objects[obj].domainFlag = 1 =>
      ~ActionSucceeds(cert, obj)
```

**Model checking bounds**: 3 certs (Zone 1, Zone 4, Zone 1+4), 4 objects (2 in Zone 1, 2 in Zone 4).

**Gate**: TLC verifies ZoneEnforcement across all interleavings.

**Commit**: `phase-11.5/D11.5.5: zone boundary enforcement model`

---

### D11.5.6: Partition Resilience (kernel contribution to Test 6.1)

**What**: Model a network partition where a subset of nodes lose connectivity. Prove that local operations continue and reconciliation produces a consistent state.

**File**: `proofs/tla/PartitionResilience.tla`

**Actions**:
- `Partition(nodeSet)` — isolates a set of nodes from the rest
- `LocalOperation(node, certId, objectId, action)` — local operation during partition
- `Heal` — restores connectivity
- `Reconcile` — merges local evidence chains

**Properties**:

```tla
\* Safety: local operations succeed during partition
LocalContinuity ==
  \A node \in PartitionedNodes :
    node.localCertCache # {} =>
      ENABLED LocalOperation(node, _, _, _)

\* Safety: after reconciliation, no evidence items lost
ReconciliationComplete ==
  (Healed /\ Reconciled) =>
    \A e \in LocalEvidence : e \in GlobalEvidenceChain

\* Safety: no duplicate consumption across partitions
NoSplitBrainConsume ==
  \A obj \in DOMAIN objects :
    objects[obj].linearity = "LINEAR" =>
      Cardinality({n \in Nodes : n.localConsumed[obj]}) <= 1
```

**Note on NoSplitBrainConsume**: This requires that LINEAR consumption is only valid when BSV-anchored. During a partition, a node can tentatively consume but must confirm post-partition. If two partitions consume the same object, reconciliation detects the conflict and rolls back one.

**Gate**: TLC verifies LocalContinuity and ReconciliationComplete.

**Commit**: `phase-11.5/D11.5.6: partition resilience model`

---

### D11.5.7: Gate Test + CI Integration

**What**: Gate test that runs TLC on all specs. CI step.

**Files**:
- `packages/__tests__/phase11.5-gate.test.ts`
- `.github/workflows/gate.yml` updated

**Gate test**:

```typescript
describe("Phase 11.5: TLA+ protocol model", () => {
  test("TLC checks EvidenceChain.tla", async () => {
    // Run: java -jar tla2tools.jar -config MC_EvidenceChain.cfg EvidenceChain.tla
    // Verify: "Model checking completed. No error has been found."
  });

  test("TLC checks ReplayPrevention.tla", async () => { ... });
  test("TLC checks CertRevocation.tla", async () => { ... });
  test("TLC checks MeteringFSM.tla", async () => { ... });
  test("TLC checks ZoneBoundary.tla", async () => { ... });
  test("TLC checks PartitionResilience.tla", async () => { ... });

  test("All TLA+ spec files present", () => {
    // Check all 7 .tla files exist
  });
});
```

**Gate**: All TLC runs complete without errors.

**Commit**: `phase-11.5/D11.5.7: gate test + CI for TLA+ model checking`

---

## Errata Scan Checklist

1. **State space explosion?** If TLC doesn't terminate in 30 minutes for any spec, the bounds are too large. Reduce and document.
2. **Missing actions?** Does the model include adversary actions (tamper, replay, forge), not just happy-path actions?
3. **Fairness assumptions?** Liveness properties require fairness. Are the fairness assumptions documented and reasonable?
4. **FSM transition table match?** Compare `MeteringFSM.tla` transition table against `src/metering/channel-fsm.ts` line by line.
5. **Partition model realism?** Does the partition model allow tentative LINEAR consumption during partition? If so, is the reconciliation conflict resolution modeled?
6. **Zone flag values?** Do the TLA+ constants match the domain flag values in `src/types/domain-flags.ts`?
7. **Evidence chain hash function?** TLA+ can't compute SHA-256. Is the hash modeled as an injective function? Is this documented as an abstraction?

---

## Anti-Bullshit Rules

1. **TLC must terminate.** A model that doesn't finish checking is not a proof.
2. **Include adversary actions.** A model with only honest actors proves nothing about security.
3. **Match the implementation.** The FSM transition table in TLA+ must match `channel-fsm.ts` exactly.
4. **Document all abstractions.** Where TLA+ abstracts away implementation details (e.g., hash as injective function), document it.
5. **No vacuous truth.** If a property holds because the precondition is never satisfied in the model, that's a bug in the model.
6. **Commit after each gate.**

---

## Completion Check

```
<hash> Phase 11.5 errata: audit doc + fix N issues
<hash> phase-11.5/D11.5.7: gate test + CI for TLA+ model checking
<hash> phase-11.5/D11.5.6: partition resilience model
<hash> phase-11.5/D11.5.5: zone boundary enforcement model
<hash> phase-11.5/D11.5.4: metering FSM correctness model
<hash> phase-11.5/D11.5.3: cert revocation immediacy model
<hash> phase-11.5/D11.5.2: replay prevention + concurrent consumption model
<hash> phase-11.5/D11.5.1: evidence chain integrity + temporal ordering
<hash> phase-11.5/D11.5.0: TLA+ scaffold + base types
```

Each commit has TLC passing. All properties verified. Adversary actions included.
