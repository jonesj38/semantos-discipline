---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/16-world-host-regions.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.651415+00:00
---

# World Host and the Region Model

Part V of this textbook covers the adapters that compose substrate capability into user-facing surfaces. Chapter 15 established the substrate-versus-adapter distinction and the unification matrix. Chapter 16 examines the first named adapter in that matrix: World Host.

World Host is the OTP/Elixir authoritative-region runtime. It hosts persistent shared spaces in which many entities coexist, move, and interact under governance. This chapter describes how World Host structures authority through the region model, how it advances time through WorldTick, how it preserves the per-entity hash chain across that advancement, and why the no-CRDT / no-drift property is a consequence of the substrate rather than an implementation choice.

The chapter ends with a worked trace of a single entity-action from the moment a client submits it through region serialisation, `OP_CALLHOST` dispatch, authoritative-write commit, and WorldTick fan-out. That trace closes boot-sequence step 9.

---

## The Missing Piece

The substrate provides cells with substructural types, an evidence chain, a multicast fabric, BCA-derived identities, a session skeleton, and a metering plane. What it does not yet provide — as of boot-sequence step 8 — is an authoritative runtime host: something that owns the lifecycle of long-lived entities, arbitrates their interactions, fans out state to interested clients, and survives crashes without losing the world.

World Host supplies that missing piece. It is implemented in Elixir/OTP and speaks the same envelopes everything else on the mesh already speaks. No existing protocol is replaced. SignedBundle, CellHeader, MeteringTick, NetworkAdapter, and SessionRuntime are reused verbatim. The OTP host adds authority, persistence, and tick-based time to the substrate without forking the substrate.

Three.js and the WASM cell engine run client-side for prediction. The OTP region is authoritative for commit. The gap between prediction and authority is closed by the per-entity hash chain and the WorldTick Merkle root.

---

## Vocabulary: Two Ticks, Not One

Before continuing, it is necessary to distinguish two concepts that share the word "tick."

A WorldTick is a per-region monotonic counter that advances the region's Merkle-rooted state hash at soft-realtime cadence — 20 Hz by default, configurable per region. It is new; this doc introduces it.

A MeteringTick is a billing event on a cashlane (an MFP channel). It is scoped to a channel, advances on FSM transitions rather than wall-clock time, and is entirely unchanged by World Host. The two tick kinds co-exist without interaction; a metered world region emits both, for different reasons, to different consumers.

Any artifact that uses the word "tick" without qualification violates the glossary discipline. This chapter always qualifies.

---

## World Host Architecture

### The OTP Supervision Tree

World Host is an OTP application. Its top-level supervisor owns one child supervisor per region. Each region supervisor owns one `GenServer` per entity in that region. The supervision tree gives the system two critical properties:

1. Process isolation. An entity-level crash does not propagate to sibling entities or to the region supervisor. The entity is restarted from its last persisted snapshot.
2. Crash recovery. A region-level crash restarts from an append-only event log combined with periodic snapshots stored in Postgres. Replay from snapshot restores the region to its last committed state.

The supervision tree is the mechanism that replaces distributed consensus. There is no distributed consensus in the World Host design. Authority is vested in one OTP process at a time; the supervision tree ensures that process is always reachable.

### Region

A region is an authoritative shard in World Host. One region equals one OTP supervisor process, one multicast PubSub topic, and one set of co-located entity `GenServer` processes.

The region's identity is:

```
regionId = BCA(regionSeed, epoch)
```

This derives the region's address from the BCA mechanism used throughout the substrate for peer and entity identity. The region has a stable identifier that changes only on explicit epoch rotation, and that identifier is what clients subscribe to for fan-out.

Regions can migrate between OTP nodes without changing their `regionId`. Horde tracks the `regionId → pid` mapping across the cluster. This migration capability means region placement is an operational concern, not a protocol concern: the wire contract depends only on `regionId`, not on which BEAM node is currently authoritative.

The expected entity count per region is 10³–10⁴ on a single BEAM node, tunable by entity count and host-call throughput. Spatial resolution follows from region size. If finer granularity is required — because entities are dense in a subregion — the operator subdivides into smaller regions. There is no sub-region visibility computation server-side; the subdivision is the visibility mechanism.

### WorldEntity

Every object in a World Host region is a WorldEntity. A WorldEntity extends the cell concept with spatial and region metadata:

```ts
interface WorldEntity extends LoomObject {
  regionId: string;
  spatial: {
    position: [number, number, number];
    orientation: [number, number, number, number]; // quaternion
    velocity?: [number, number, number];
    bbox?: { min: [number, number, number]; max: [number, number, number] };
  };
  controllerSessionId?: string;
}
```

The `spatial` field is top-level so region tick logic can make visibility decisions without unpacking every cell's payload. The `regionId` field is updated atomically on cross-region transfer. The `controllerSessionId` field is non-null exactly when the entity is an avatar — a WorldEntity whose state is controlled by a connected client session.

`LoomObject` is the runtime/services-layer wrapper that contains a cell along with UI-presentation metadata. A WorldEntity is a `LoomObject` with spatial extension. The underlying cell is still a cell in the canonical sense: a 256-byte typed header plus payload, hash-chained, carrying linearity class, pipeline phase, owner identifier, and cryptographic provenance. The spatial extension does not replace any of that structure.

### Avatar

An avatar is a user-controlled WorldEntity in a World Host region. It is an OTP-process-backed object whose state is mutated only by intents authored by the controlling user's BRC-52 cert. The cert binding is enforced at the Phoenix `UserSocket.connect/3` boundary by `WorldHost.VerifierClient` calling the per-node Verifier Sidecar over loopback HTTP; on success, `socket.assigns.bca` and `socket.assigns.cert_id` are populated and every subsequent `entity_action` is matched against the entity's `controller` for ownership (K2) [D-V3 / #193, D-A1 / #200; `apps/world-host/lib/world_host_web/user_socket.ex`]. Currently rendered as a LINEAR cube whose colour is derived from the controlling cert's public key.

The "LINEAR cube" label combines two facts: the linearity class of the underlying cell (LINEAR — consumed exactly once per mutation) and the current rendering shape. The rendering shape is replaceable; the linearity class is not.

Identity follows the existing BCA derivation. An avatar's identity is:

```
avatarId = BCA(userCert, sessionEphemeralSubkey)
```

This gives each session a stable-yet-session-scoped identifier without exposing the user's root cert to the mesh. The per-account BCA plus per-session ephemeral subkey pattern is consistent with how the substrate handles per-session scoping elsewhere.

---

## WorldTick

### Structure

A WorldTick is the region's unit of time:

```ts
interface WorldTick {
  regionId: string;
  tickSeq: bigint;
  prevStateHash: Uint8Array;
  stateHash: Uint8Array;
  wallClockHint: bigint;
}
```

Three invariants hold:

- `tick[N].prevStateHash == tick[N-1].stateHash` — the per-region hash chain is continuous.
- `stateHash` is a Merkle root over entity hashes at tick commit time in canonical order.
- `tickSeq` never decreases.

The `wallClockHint` is advisory, not authoritative. Clock drift between nodes does not affect the hash chain's integrity; the chain is ordered by `tickSeq`, not by wall time.

### The Per-Region Hash Chain

The per-region hash chain is a direct application of the Phase 11.5 evidence-chain invariant extended from the per-cell scope to the per-region scope. The per-cell invariant is:

```
patches[i].prevHash == patches[i-1].stateHash
```

The per-region invariant adds:

```
tick[N].prevStateHash == tick[N-1].stateHash
```

Where `tick[N].stateHash = MerkleRoot({ entity.stateHash | entity ∈ region, in canonical order })`.

This creates a verifiable cryptographic timeline for the entire region. A client that receives two consecutive WorldTicks can verify that the second is a valid successor of the first by checking `prevStateHash`. A client that misses ticks can request a snapshot and resume from any valid tick boundary.

### Fan-Out

One region equals one multicast topic. The `TopicToGroup` hook in the multicast adapter maps `regionId` to an IPv6 multicast group via the Phase 34 type-hash-to-group derivation. Every client subscribed to a region receives every `tick_delta` frame on that region's multicast group.

The server does not compute per-client visibility. Spatial resolution is set by region granularity — subdivide for finer granularity. Client-side frustum culling is permitted but optional.

Border entities — entities near the boundary of a region — publish to neighbouring region topics with a `borderHint: true` flag. This gives clients near the border context about entities they will soon encounter without requiring the server to track per-client position.

### WorldTick Cadence

The default cadence is 20 Hz. This is configurable per region. The cadence is soft-realtime: the tick fires approximately every 50 ms but the system makes no hard real-time guarantees.

The tick cadence is independent of MeteringTick cadence. A single region can be simultaneously emitting WorldTicks at 20 Hz and MeteringTicks on cashlane transitions for any metered operations within it. The two tick kinds are produced by different mechanisms for different consumers.

[FIGURE — needs real graphic for layout pass]

```
Region GenServer
│
├── 50ms wall-clock interval fires
│   ├── Collect entity deltas since last tick
│   ├── Compute MerkleRoot over entity stateHashes
│   ├── Emit WorldTick {tickSeq: N+1, prevStateHash: H_N, stateHash: H_N+1}
│   └── Publish tick_delta frame to region multicast topic
│
└── On entity-action receipt (any time between ticks)
    ├── Serialise into entity GenServer mailbox
    ├── Dispatch through OP_CALLHOST
    ├── On success: advance entity hash chain
    └── Include delta in next WorldTick
```

---

## Authority and the K1 Gate

### The No-CRDT Property

The World Host design makes no use of CRDTs (conflict-free replicated data types) or merge functions. This is not an omission — it is a consequence of the substrate's substructural type discipline and the kernel invariant K1.

K1 is the linearity kernel invariant. K1 states that a cell marked LINEAR is consumed exactly once: it cannot be duplicated and it cannot be used after consumption. Enforced structurally at the bytecode gate of the cell engine, K1 makes the notion of "simultaneous conflicting writes" unambiguous rather than continuous. Two entity-actions that arrive at the same region `GenServer` at the same time are not simultaneous in the operational sense — they are ordered by the `GenServer` mailbox. One executes first. The other executes second, against the updated state that the first left behind. There is no partial-credit merge because there are no partial states to merge: each action either succeeds (the cell was available to consume) or fails (the cell was already consumed or the linearity gate rejected the operation).

The absence of drift follows directly from K1 linearity. Drift requires a system to accumulate divergent state that must later be reconciled. K1 prevents the accumulation: no entity has two authoritative states because exactly one process is authoritative for any entity at any time, and that process's mailbox serialises all actions. The client may predict ahead of the authoritative state — that is the client-side prediction loop described in the next section — but the client's prediction is not authoritative, and when it diverges from the authoritative hash it is snapped back, not merged.

The phrase "no CRDT, no drift" in the World Host design notes is therefore a consequence of K1 linearity, not an independent architectural commitment.

### Client Prediction and Authoritative Commit

The client runs a local WASM cell engine for prediction. When the user takes an action, the client:

1. Predicts the outcome locally, using the same cell engine kernel that the region runs server-side.
2. Renders the predicted state immediately.
3. Sends a `SignedBundle<entity_action>` to the region.

The region `GenServer`:

1. Receives the action.
2. Serialises it into the entity's mailbox (ordering relative to all other actions for that entity).
3. Dispatches through `OP_CALLHOST`. The K1 gate enforces linearity.
4. On success: advances the entity's patch chain. The entity's `stateHash` advances.
5. Includes the delta in the next WorldTick.

The client receives the next WorldTick and compares the authoritative `stateHash` to its local prediction. If they match, the prediction is confirmed. If they diverge, the client snaps to the authoritative state and rolls back any subsequent local predictions.

The client runs a byte-identical kernel to the server because the prediction uses the same WASM module (`apps/world-client`) that the region loads. This byte-identity is what makes the comparison meaningful: the client knows whether its prediction was correct because it knows what the correct answer should be.

### Wire Format

All world-layer messages use the same envelope as every other mesh message:

```
SignedBundle<WorldFrame>
```

Serialised in CBOR (JSON fallback). On multicast, the 12-byte adapter header carries `msgType = 0x04` (world_frame) — a newly allocated message type that does not conflict with the existing heartbeat (0x01), cell (0x02), or control (0x03) message types.

The `WorldFrame` tagged union covers the full set of world-layer events:

```ts
type WorldFrame =
  | { kind: 'tick_delta';           tick: WorldTick; deltas: EntityDelta[]; borderHint?: boolean }
  | { kind: 'entity_spawn';         regionId: string; entity: WorldEntity }
  | { kind: 'entity_despawn';       regionId: string; entityId: string; reason: DespawnReason }
  | { kind: 'entity_action';        regionId: string; entityId: string; action: EntityAction }
  | { kind: 'entity_action_result'; regionId: string; actionId: string; outcome: ActionOutcome }
  | { kind: 'entity_transfer_intent'; fromRegion: string; toRegion: string; entityId: string; intentId: string }
  | { kind: 'entity_transfer_commit'; intentId: string; tickSeq: bigint }
  | { kind: 'presence_beacon';      avatarId: string; regionId: string; spatialDigest: Uint8Array };
```

The `tick_delta` frame is the primary fan-out mechanism. It carries the full WorldTick and the set of entity deltas since the previous tick. Clients that receive consecutive `tick_delta` frames with matching `prevStateHash → stateHash` chains have a complete and verified picture of the region's state evolution.

---

## Cross-Region Transfer

### Two-Phase Commit

When an entity moves from one region to another — as when an avatar crosses a region boundary — the transfer uses a two-phase commit to preserve the hash chain without interruption:

1. The source region emits `entity_transfer_intent` naming the entity, the source, the target, and a unique `intentId`.
2. The target region accepts or rejects. If the target rejects (capacity, policy), the entity stays in the source region.
3. On acceptance, the source region emits a final `tick_delta` marking the entity's last state in the source region, then `entity_despawn`.
4. The target region emits `entity_spawn` with the same `entityId` and with `prevStateHash` equal to the entity's last `stateHash` in the source region.

The hash chain continues unbroken across the transfer. A verifier examining the entity's patch history sees a continuous chain from creation through any number of region migrations.

The `regionId` field on the `WorldEntity` is updated atomically as part of the spawn event in the target region. There is no intermediate state in which the entity exists in neither or both regions.

### Admission Control

Whether the target region accepts a transfer intent is controlled by the region's admission policy. The design reuses `FormationPolicy` from the session layer — the same policy mechanism used for session admission. This avoids a second admission-control vocabulary and keeps the enforcement point consistent.

---

## Subscription and Interest Management

### One Region, One Topic

The subscription model is deliberately coarse. One region equals one multicast topic. Clients subscribe to the topic for every region they want to observe. There is no server-side per-client filtering.

This design has a specific trade-off profile: it is simple to implement and operate, and it scales by subdivision rather than by filtering. If a region has 10 000 entities and a client only wants to see 200 of them, the client receives the full 10 000 and discards what it does not need. The alternative — server-side per-client filtering — would require the server to track every client's position and interest state, which is a significantly more complex system.

The appropriate response to density is subdivision: split the region into smaller regions until each region's entity count matches the desired granularity. The multicast fabric handles fan-out at whatever granularity the operator chooses.

### Presence and Avatar Tracking

Avatar presence uses the existing `HeartbeatSink` mechanism. Peers in the multicast group emit `PeerInfo { bca, firstSeen, lastSeen, metadata }` heartbeats at the standard 5-second cadence. The `presence_beacon` frame in the WorldFrame union is the world-layer complement: it carries the avatar's BCA, region, and a spatial digest that lets the receiver know approximately where in the region the avatar is without requiring a full state deserialization.

Avatar-to-region mapping is session-layer state. The session runtime tracks which region an avatar is currently authoritative in. When the avatar's session transitions regions, the session runtime updates its avatar-to-region mapping.

### Metering Integration

Metering is unchanged. Regions that are metered services open cashlanes and emit MeteringTicks on FSM transitions within those cashlanes. WorldTick cadence is orthogonal to cashlane billing. A region can run at 20 Hz with no cashlane open (unmetered) or with multiple cashlanes open (metered by capability class). The `Semantos.World.Network` module handles the WorldTick fan-out; the MFP engine handles the cashlane settlement. Neither knows about the other at the interface level.

---

## Persistence

### Event Log and Snapshots

The region's persistent state is an append-only event log combined with periodic snapshots. The event log records every committed entity-action in tick order. The snapshot records the full state of the region at a given `tickSeq`. On crash, the region replays from the most recent snapshot through the event log to reconstruct current state.

Storage is Postgres in the reference implementation. The append-only event log maps directly to a Postgres table with one row per committed action; the snapshot maps to a serialised region state stored as a large binary. Neither the log nor the snapshot format is specified in the wire protocol — they are implementation concerns.

### Reconnect

A client that misses fewer than K ticks (a configurable constant) can request a tick replay from the region: the region streams the missed `tick_delta` frames. A client that misses more than K ticks receives a snapshot followed by the most recent tick. The K-tick threshold is tunable per region and per deployment.

---

## Elixir Module Scaffold

The World Host wire contract is stable enough to scaffold the Elixir module structure against. The six planned modules are:

| Module | Responsibility |
|---|---|
| `Semantos.World.Region` | Supervisor and authority surface; one per region |
| `Semantos.World.Entity` | Per-entity `GenServer`; one per entity |
| `Semantos.World.Tick` | WorldTick construction and Merkle root computation |
| `Semantos.World.Network` | WorldFrame serialisation and multicast fan-out |
| `Semantos.World.Persistence` | Append-only event log and snapshot management |
| `Semantos.World.Federation` | Cross-region transfer two-phase commit |

`Semantos.World.Region` is the authority surface. It owns the region's entity set and the tick timer. `Semantos.World.Entity` is the per-entity state machine; it receives actions from the region, dispatches through `OP_CALLHOST`, and advances the entity's patch chain on success. `Semantos.World.Tick` is the Merkle-root computation and WorldTick emission. `Semantos.World.Network` is the multicast adapter for the world layer. `Semantos.World.Persistence` handles durable storage. `Semantos.World.Federation` handles cross-region transfers.

Server-side WASM evaluation uses Wasmex as the first implementation choice, falling back to a sidecar process only if profiling demands it. The cell engine's WASM profile (185 KB full, 29 KB embedded) is small enough that in-process evaluation with Wasmex is feasible on a BEAM node hosting thousands of entities.

---

## Worked Program: One Entity-Action Through Region Authority and WorldTick

> This trace follows a single entity-action from client submission through authoritative commit and WorldTick fan-out. The entity is an avatar; the action is a positional move.
>
> All frames are carried inside `SignedBundle<WorldFrame>`. All hashes are abbreviated for readability.

### Setup

The operator has booted a sovereign node through step 8 (the Verifier Sidecar is enforcing BRC-52 cert authenticity and capability UTXO validity at every adapter boundary). World Host is running. Region R1 is active with `regionId = "R1"` and 847 entities. One of them is avatar A, controlled by user U's BRC-52 cert with session ephemeral subkey S.

Avatar A's current state in region R1:
- `entityId = "A"`
- `stateHash = 0xAAA1` (abbreviated)
- `spatial.position = [10.0, 0.0, 5.0]`

The region's last WorldTick:
- `tickSeq = 1041`
- `stateHash = 0xRRR1041` (Merkle root over all 847 entity hashes at tick 1041)

### Step 1: Client Sends entity_action

User U issues a movement command. The client-side predictor:

1. Predicts the outcome locally using the embedded WASM cell engine.
2. Advances A's local shadow state: `spatial.position = [11.0, 0.0, 5.0]`.
3. Renders the new position immediately.

The client constructs the action frame and wraps it in a signed bundle:

```ts
const action: WorldFrame = {
  kind: 'entity_action',
  regionId: 'R1',
  entityId: 'A',
  action: {
    type: 'move',
    intent: { position: [11.0, 0.0, 5.0] }
  }
};

const bundle = SignedBundle.wrap(action, userCert, sessionEphemeralSubkey);
```

The bundle is transmitted to region R1's multicast group. `msgType = 0x04`.

### Step 2: Region GenServer Receives the Action

The `Semantos.World.Region` GenServer for R1 receives the signed bundle on its mailbox. It:

1. Verifies the outer `SignedBundle` signature using the Verifier Sidecar — BRC-100 signature, BRC-52 cert authenticity, identity binding, capability UTXO validity via SPV.
2. Routes the action to the entity `GenServer` for entity A.

Entity A's `GenServer` receives the action. The mailbox serialises it: if two actions for entity A arrived simultaneously, they are ordered by mailbox receipt time. One executes first. This ordering is the mechanism that eliminates the need for conflict resolution — there is no conflict, only an ordered queue.

### Step 3: OP_CALLHOST Dispatch

The entity `GenServer` dispatches the action through `OP_CALLHOST`. The WASM cell engine (loaded via Wasmex) evaluates the action against entity A's current cell.

The K1 gate runs: the cell engine checks that the cell is available to consume and that the linearity class permits mutation. Entity A's cell is LINEAR (class 0). The move action is a valid mutation for a LINEAR entity. The gate passes.

The spatial field is updated:

```
prevStateHash = 0xAAA1
newPosition   = [11.0, 0.0, 5.0]
newStateHash  = Hash(prevStateHash || "A" || newPosition || ...)
             = 0xAAA2  (abbreviated)
```

The entity's patch chain advances:

```
patch[N]:   prevHash = 0xAAA1, stateHash = 0xAAA2
```

This satisfies the per-entity evidence-chain invariant: `patch[N].prevHash == patch[N-1].stateHash`.

### Step 4: Entity Delta Queued for Next WorldTick

The entity `GenServer` reports the committed delta to the region:

```
EntityDelta {
  entityId: "A",
  prevStateHash: 0xAAA1,
  stateHash: 0xAAA2,
  spatial: { position: [11.0, 0.0, 5.0] }
}
```

The region accumulates this delta in a buffer. The entity's new `stateHash` (`0xAAA2`) will be included in the next WorldTick's Merkle root computation.

### Step 5: WorldTick 1042 Fires

Approximately 50 ms after tick 1041, the tick timer fires in the region `GenServer`. The region:

1. Collects all entity deltas accumulated since tick 1041. This includes the delta for entity A.
2. Recomputes the Merkle root over all 847 entity `stateHash` values (now including A's updated `0xAAA2`).
3. Constructs WorldTick 1042:

```ts
const tick1042: WorldTick = {
  regionId: 'R1',
  tickSeq: 1042n,
  prevStateHash: 0xRRR1041,
  stateHash: 0xRRR1042,   // Merkle root including A's 0xAAA2
  wallClockHint: BigInt(Date.now())
};
```

4. Emits a `tick_delta` WorldFrame:

```ts
const delta: WorldFrame = {
  kind: 'tick_delta',
  tick: tick1042,
  deltas: [entityDeltaA, /* ...other deltas... */]
};
```

5. Publishes `SignedBundle<WorldFrame>` to R1's multicast topic.

### Step 6: Client Receives and Verifies

The client receives `tick_delta` for tick 1042. It verifies:

- `tick1042.prevStateHash == tick1041.stateHash` — the region hash chain is continuous.
- The delta for entity A shows `stateHash = 0xAAA2`.
- The client's local shadow `stateHash` for A also shows `0xAAA2` (from the prediction in Step 1).
- Match confirmed: the prediction was correct. No snap.

If the prediction had been wrong — if the server's `stateHash` for A differed from the client's shadow — the client would snap A's spatial state to the authoritative value and roll back any subsequent local predictions.

[FIGURE — needs real graphic for layout pass]

```
Client                     Region R1
  │                            │
  │──entity_action (bundle)──▶│
  │                            │ Verify SignedBundle
  │                            │ Route to entity A GenServer
  │                            │ Serialise in mailbox
  │  (local prediction)        │ OP_CALLHOST dispatch
  │  render [11.0, 0.0, 5.0]  │ K1 gate: pass
  │                            │ patch chain: 0xAAA1 → 0xAAA2
  │                            │ delta queued
  │                            │
  │                      [~50ms tick timer]
  │                            │
  │◀── tick_delta (1042) ─────│ Merkle root recomputed
  │    tick.stateHash=0xRRR1042│ tick emitted to multicast
  │    A.stateHash=0xAAA2      │
  │                            │
  │ verify: local==auth?        │
  │ 0xAAA2 == 0xAAA2: ✓ confirm│
  │                            │
```

### What the Trace Demonstrates

The trace shows the authoritative-write path: client action → region receipt → serialisation → K1 gate → patch chain advance → WorldTick Merkle root → multicast fan-out → client verification. At no point is there a merge, a CRDT operation, or a conflict resolution step. The serialisation in the entity `GenServer` mailbox is the conflict-resolution mechanism; K1 linearity ensures that the outcome is discrete rather than continuous.

The per-entity hash chain (`0xAAA1 → 0xAAA2`) satisfies the same evidence-chain invariant that governs every cell in the substrate. The per-region WorldTick chain (`0xRRR1041 → 0xRRR1042`) extends that invariant to the region as a whole. A verifier can check either chain independently.

---

## Summary

World Host is an adapter over the substrate. It adds one thing the substrate does not have by itself: an authoritative runtime host for long-lived entities. Everything else — identity, linearity, hash chaining, multicast fan-out, session management, metering — comes from the substrate unchanged.

The region model provides authority through OTP process isolation: exactly one process is authoritative for any entity at any time. The WorldTick provides verifiable time through a Merkle-rooted hash chain that extends the per-entity evidence chain to the per-region scope.

The no-CRDT / no-drift property is not a design goal that World Host achieves through careful engineering. It is a consequence of K1 linearity: substructural types make conflicting writes discrete rather than continuous, and the entity `GenServer` mailbox serialises the discrete cases. There is nothing to merge because there is no state that requires reconciliation.

The `Semantos.World.Region`, `Semantos.World.Entity`, `Semantos.World.Tick`, `Semantos.World.Network`, `Semantos.World.Persistence`, and `Semantos.World.Federation` modules are scaffoldable against this stable wire contract. The client `Predictor` in `apps/world-client` runs the same WASM kernel as the server.

**Boot-sequence step 9 is now unlocked.** With the region model, WorldTick, and the authoritative-write path specified, the World Host adapter has a complete wire contract. An operator who has completed step 8 (Verifier Sidecar enforcing BRC verification at every adapter boundary) can proceed to step 9: deploying the World Host OTP application and confirming that entity-actions flow through the authoritative-write path described in this chapter's worked trace.

Chapter 17 covers the mesh layer — IPv6 multicast and the session codec port — which is the transport substrate that both World Host and the other adapters share.
