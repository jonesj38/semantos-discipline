---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/WORLD-PROTOCOL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.718722+00:00
---

# Semantos World Protocol

**Version**: 0.1 (draft)
**Date**: April 2026
**Status**: Design proposal — for review before promotion to a numbered Phase
**Prerequisites**: Phase 11.5 (TLA / evidence chain), Phase 34 (type-hash → multicast addressing), Phase 35A (Session Protocol Promotion), current CellEngine host-call contract
**Target runtime**: Elixir/OTP (new) — client remains TypeScript + three.js + WASM cell engine

---

## 1. Purpose and scope

Semantos has the pieces of a persistent multi-user world without calling it one: cells with substructural types, an evidence chain, a multicast fabric, BCA-derived identities, a domain-neutral session skeleton, a metering plane, and a client-side three.js / WASM demo. The missing piece is an *authoritative runtime host* — something that owns the lifecycle of many long-lived entities, arbitrates their interactions, fans out state to interested clients, and survives crashes without losing the world.

OTP (Erlang/BEAM, accessed via Elixir) is the right shape for that host: process-per-entity, supervision trees, distributed registry, PubSub fan-out. This doc specifies the wire contract between an OTP world-host, the existing Semantos session layer, and the three.js + WASM client, so that:

- No existing protocol is broken or replaced. `SignedBundle`, `CellHeader`, `MeteringTick`, `NetworkAdapter`, `SessionRuntime` are reused verbatim.
- The OTP host speaks the same envelopes everything else on the mesh already speaks.
- Clients run a local WASM cell engine for prediction; the OTP region is authoritative for commit.
- A "Ready Player One"-class persistent 3D space is a finite delta on top of what exists, not a fresh stack.

### Non-goals

- **Not a new transport.** Reuses `NetworkAdapter` (`core/protocol-types/src/network.ts`) — any concrete adapter (DockerMulticast, UDP, future WebSocket) works.
- **Not a new identity model.** Entities, regions, avatars all get identities via the existing BCA derivation (`core/cell-engine/src/bca.zig`).
- **Not a rendering spec.** Client is three.js; this doc says nothing about shaders, materials, or scene graphs.
- **Not a replacement for `LoomObject`.** A `WorldEntity` *is* a `LoomObject` with additional spatial metadata.
- **Not an OTP implementation guide.** Supervision tree topology, Horde vs `:global`, Wasmex vs sidecar — those are implementation concerns covered briefly in §13.

---

## 2. Relationship to existing protocol

| World-layer concept | Backed by existing primitive | Source of truth |
|---|---|---|
| Envelope for every world message | `SignedBundle<T>` (v1) | `runtime/session-protocol/src/bundle-envelope.ts` |
| On-wire cell format | `CellHeader` (256 bytes) | `core/protocol-types/src/cell-header.ts` |
| Entity payload shape | `LoomObject` + spatial extension | `runtime/services/src/types/loom.ts` |
| Entity hash chain | Evidence-chain invariant `prevHash == prior.stateHash` | `docs/prd/PHASE-11.5-TLA-PROTOCOL.md` |
| Identity (entity, region, avatar) | BCA IPv6 from pubkey | `core/cell-engine/src/bca.zig` |
| Fan-out | IPv6 multicast with topic-derived groups | `runtime/session-protocol/src/adapters/multicast-adapter.ts` (injected `TopicToGroup` hook); Phase 34 supplies type-hash → group derivation |
| Session handshake / FSM | `SessionRuntime` + `SessionDescriptor` + pluggable `StateMachine<Event, State>` | `runtime/session-protocol/src/types.ts` |
| Billing | `MeteringTick` emitted by region FSM transitions | `runtime/session-protocol/src/types.ts` L132–141 |
| Peer/avatar presence | Existing `HeartbeatSink` (`PeerInfo { bca, firstSeen, lastSeen, metadata }`) | multicast adapter heartbeats, 5 s cadence |
| Host execution | `OP_CALLHOST` dispatching via `host-exec-registry` | `core/cell-engine/src/opcodes/hostcall.zig` |

**New concepts introduced by this doc:**

- `WorldEntity` — a `LoomObject` plus `spatial` and `region` fields.
- `Region` — a logical shard of the world hosted by one authoritative OTP process at a time.
- `WorldTick` — a per-region monotonic advance-of-time marker. **Distinct from `MeteringTick`.**
- `WorldFrame` — tagged union of world-layer payloads, always carried inside a `SignedBundle`.

---

## 3. Vocabulary, carefully

- **MeteringTick**: billing event on a cashlane. Scope: channel. Cadence: on FSM transitions, not wall-clock. Unchanged by this doc.
- **WorldTick**: region-scoped monotonic counter. Scope: region. Cadence: soft-realtime, configurable per region (default 20 Hz). **New.**
- **Cell / CellHeader**: the 256-byte on-wire cell format. Unchanged.
- **LoomObject**: host-side object. Unchanged; extended by `WorldEntity`.
- **Region**: an authoritative shard — an OTP supervisor owning a set of `WorldEntity` processes. New.
- **Entity**: a `WorldEntity`; one OTP `GenServer` per instance under a region supervisor. New.
- **Avatar**: a `WorldEntity` whose controller is a connected client session. New sub-type.
- **Topic**: subscription key for multicast fan-out.

---

## 4. WorldEntity

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

- `spatial` is top-level so region tick logic doesn't unpack every cell for visibility decisions.
- `regionId` is a pointer; cross-region transfer updates it atomically.
- Linearity lives in `header.linearity`, enforced by the cell engine on the region (not re-invented here).

---

## 5. Region

- **Authority**: exactly one OTP process may commit state for a given entity at a time. Reads fan out via tick deltas; writes go through the region.
- **Subscription**: one region = one multicast topic. `TopicToGroup(regionId)` → IPv6 multicast group.
- **Migration**: regions can move between OTP nodes without changing `regionId`. Horde tracks `regionId → pid`.
- **Identity**: `regionId = BCA(regionSeed, epoch)`.
- **Size**: tune by entity count and host-call throughput. Expect 10³–10⁴ entities per region on one BEAM node.

---

## 6. WorldTick

```ts
interface WorldTick {
  regionId: string;
  tickSeq: bigint;
  prevStateHash: Uint8Array;
  stateHash: Uint8Array;
  wallClockHint: bigint;
}
```

Invariants:
- `tick[N].prevStateHash == tick[N-1].stateHash`
- `stateHash` is a Merkle root over entity hashes at tick commit time.
- `tickSeq` never goes backwards.

Cadence: soft real-time, 20 Hz default, configurable per region. Not to be confused with `MeteringTick`.

---

## 7. Subscription and interest management

- **One region = one topic.** Server doesn't compute per-client visibility.
- Spatial resolution set by region size — subdivide for finer granularity.
- Client-side frustum culling allowed but optional.
- Border entities publish to neighbour topics with `borderHint: true` for context only.
- Avatar-to-region mapping is session-layer state.

---

## 8. Wire format

All messages: `SignedBundle<WorldFrame>`, CBOR (JSON fallback). On multicast, reuses the 12-byte adapter header with `msgType = 0x04` (world_frame).

```ts
type WorldFrame =
  | { kind: 'tick_delta'; tick: WorldTick; deltas: EntityDelta[]; borderHint?: boolean }
  | { kind: 'entity_spawn'; regionId: string; entity: WorldEntity }
  | { kind: 'entity_despawn'; regionId: string; entityId: string; reason: DespawnReason }
  | { kind: 'entity_action'; regionId: string; entityId: string; action: EntityAction }
  | { kind: 'entity_action_result'; regionId: string; actionId: string; outcome: ActionOutcome }
  | { kind: 'entity_transfer_intent'; fromRegion: string; toRegion: string; entityId: string; intentId: string }
  | { kind: 'entity_transfer_commit'; intentId: string; tickSeq: bigint }
  | { kind: 'presence_beacon'; avatarId: string; regionId: string; spatialDigest: Uint8Array };
```

---

## 9. Authority and client prediction

1. Client predicts locally (same WASM kernel), renders immediately.
2. Client sends `SignedBundle<entity_action>` to the region.
3. Region `GenServer` serialises actions for the entity, dispatches through `OP_CALLHOST`. K1 gate enforces linearity.
4. On success: patch chain advances, delta emitted on next `WorldTick`.
5. Client compares authoritative `stateHash` to local prediction. Match → confirmed. Mismatch → snap + roll back.

Substructural types make conflict resolution discrete — no continuous drift, no partial-credit merges.

---

## 10. Causality and persistence

- Per-entity: `patches[i].prevHash == patches[i-1].stateHash` (Phase 11.5 invariant).
- Per-region: `tick[N].prevStateHash == tick[N-1].stateHash`.
- Region `stateHash` = Merkle root over entity stateHashes in canonical order.
- Storage: append-only event log + periodic snapshots (Postgres). Replay from snapshot on crash.

---

## 11. Cross-region transfer

Two-phase commit: source emits `entity_transfer_intent`; target accepts/rejects; on accept source emits final `tick_delta` + `entity_despawn`; target emits `entity_spawn` with the same entityId and prevStateHash. Hash chain continues across regions.

---

## 12. Metering hook

Unchanged. Regions that are metered services open cashlanes and emit `MeteringTick`s; `WorldTick` cadence is orthogonal.

---

## 13. Open questions

- WASM on server: Wasmex first, sidecar only if profiling demands.
- Region placement: Horde over `:global`.
- Tick cadence: 20 Hz default; adaptive later.
- Client reconnect: replay if < K ticks missed, snapshot otherwise.
- Avatar identity: per-account BCA + per-session ephemeral subkey.
- Admission control: reuse `FormationPolicy`.
- Physics: out of scope. Lives in region GenServers as host-calls.
- Conflict resolution: serialised by the region mailbox. No CRDT. Linearity makes "simultaneous" unambiguous.
- Bandwidth: ~100 entities × 20 Hz ≈ 100 KB/s per client per region. Interest management scales via region subdivision.

---

## 14. What this unblocks

- `Semantos.World.Region`, `Semantos.World.Entity`, `Semantos.World.Tick`, `Semantos.World.Network`, `Semantos.World.Persistence`, `Semantos.World.Federation` — Elixir modules scaffoldable against a stable contract.
- Client `Predictor` (`apps/world-client`) runs the same WASM kernel as the server for byte-identical prediction.

---

## Appendix A — `msgType` allocation

| Value | Meaning |
|---|---|
| 0x01 | heartbeat (existing) |
| 0x02 | cell (existing) |
| 0x03 | control (existing) |
| **0x04** | **world_frame (this doc)** |

## Appendix B — Glossary cross-reference

| This doc | Existing term |
|---|---|
| WorldEntity | LoomObject + spatial |
| Region | (new) |
| WorldTick | (new) — do **not** conflate with MeteringTick |
| Topic | SessionDescriptor.topic |
| Action | StateMachine event |
| Entity transfer | (new) |
