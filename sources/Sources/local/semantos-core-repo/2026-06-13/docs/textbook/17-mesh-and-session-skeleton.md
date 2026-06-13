---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/17-mesh-and-session-skeleton.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.652606+00:00
---

# Chapter 17 — The Mesh: IPv6 Multicast and the Codec Port

Part V covers the adapters that connect the substrate to the outside world. Chapter 16 handled the World Host region model — an intra-node authority structure. This chapter covers the mesh: the cross-node transport layer that lets peer nodes discover one another, form multi-party sessions, and exchange signed frames without a coordinator.

The mesh does not introduce new kernel invariants. It is substrate plumbing: a replaceable transport beneath a fixed session contract. Everything above the transport interface is domain-neutral. The only domain-specific contribution a vertical makes is its state machine. That one sentence is the load-bearing claim of this chapter.

---

## 17.1 What the Mesh Is

The mesh is the substrate's peer-discovery and signed-bundle transport layer. Peers are identified by BCA (Blockchain Channel Address); frames travel as `SignedBundle<T>` envelopes over the default IPv6 multicast transport, mediated by a codec port — an interface seam that is replaceable without changing any session logic above it.

The glossary entry for mesh names three canonical aliases: mesh, IPv6 multicast, and peer mesh. IPv6 multicast is the default transport implementation, not a synonym for the concept. The mesh survives a transport swap — the same session code runs unchanged over a WebSocket adapter, an in-process loopback adapter for tests, or, in Phase 33B, a 6LoWPAN radio adapter. Treating "IPv6 multicast" as the canonical name would over-bind the concept to one substrate choice.

BCA derives from the cert's public key. The derivation is implemented in `packages/cell-engine/src/bca.zig` and produces an IPv6-shaped address deterministically from the 33-byte compressed secp256k1 pubkey of a BRC-52 cert. Because the derivation is deterministic, any peer who knows a node's BRC-52 cert can compute its BCA without a directory lookup. The BCA is the peer identity the mesh uses for routing; the MFP channel-funding key uses the same value for a different purpose.

---

## 17.2 The Wire Format

### 17.2.1 The SignedBundle Envelope

Every cross-process or cross-node message is wrapped in a `SignedBundle<T>` — the BRC-100 envelope. On first introduction: *SignedBundle* (BRC-100 envelope) is the canonical wire container for all inter-node frames. Its CBOR encoding carries the following mandatory headers:

| Header | Type | Description |
|---|---|---|
| `x-brc100-identitykey` | bytes(33) | Sender's compressed secp256k1 pubkey |
| `x-brc100-nonce` | bytes(32) | Anti-replay nonce |
| `x-brc100-timestamp` | uint64 | Milliseconds since epoch |
| `x-brc100-signature` | bytes(64+) | ECDSA over canonical preimage |
| `x-brc52-certificate` | bytes | Sender's BRC-52 cert or cert reference |
| `payload` | T (CBOR) | Vertical-specific payload |

The Verifier Sidecar (§9.5 of the protocol spec) must verify every header before the payload is processed. JSON fallback is permitted where CBOR is impractical, but CBOR is the canonical wire format. The Verifier Sidecar's role here is the same as at every adapter boundary: it enforces BRC-100 signature validity, BRC-52 cert authenticity, and identity binding before any domain logic runs.

### 17.2.2 The Multicast Frame Header

Below the signed-bundle sits the 12-byte multicast adapter header, carried on each UDP datagram:

| Offset | Size | Field | Description |
|---|---|---|---|
| 0 | 1 | Magic | Frame magic byte |
| 1 | 1 | Version | Adapter wire version |
| 2 | 1 | MsgType | `0x01`=heartbeat, `0x02`=cell, `0x03`=control, `0x04`=world_frame |
| 3 | 1 | Reserved | Zero |
| 4 | 8 | Nonce | 8-byte randomness |

This header is the multicast adapter's concern, not the session layer's. Code above the `NetworkAdapter` interface never touches it.

### 17.2.3 Payload Size Enforcement

The protocol spec (§12.2) states the constraint plainly: a maximum payload size must be enforced, and oversized publishes must reject with `PayloadTooLargeError` rather than silently dropping. The default limit is 65,507 minus `HEADER_SIZE` bytes — the UDP datagram limit minus the adapter header. Non-IP transports must enforce their own MTU at the adapter boundary. The session layer above does not negotiate payload sizes; it receives an error and decides whether to fragment, retry, or surface the failure.

---

## 17.3 The Transport Interface

### 17.3.1 NetworkAdapter

The `NetworkAdapter` interface is the codec port — the seam between session logic and transport substrate. It exposes five methods:

```typescript
interface NetworkAdapter {
  publish(topic: string, payload: Uint8Array): Promise<void>;
  subscribe(topic: string, handler: (payload: Uint8Array) => void): () => void;
  resolve(topic: string): Promise<NodeInfo[]>;
  resolveBCA(bca: string): Promise<PlexusCertMetadata>;
  sendToNode(bca: string, payload: Uint8Array): Promise<void>;
}
```

Five methods, no more. The multicast adapter, the WebSocket adapter, the in-process loopback adapter, and the 6LoWPAN adapter all implement this same contract. Session code above the interface calls only these five methods and has no awareness of how they are implemented.

### 17.3.2 The topicToGroup Hook

The multicast adapter joins IPv6 multicast groups. Which group a topic maps to is controlled by a `topicToGroup` hook:

```typescript
type TopicToGroup = (topic: string) => string;

// Default: all topics on one group, software demultiplexing
const defaultTopicToGroup: TopicToGroup = () => 'ff02::1';
```

The default maps every topic to the link-local all-nodes group `ff02::1` and demultiplexes in software. This is the hackathon-era behaviour and it ships as the current default because it is correct and self-contained — all subscribers receive all frames and filter in process.

Phase 34 designs a type-hash-to-group derivation scheme in which each type hash maps to a distinct IPv6 multicast group, giving transport-level filtering: nodes that have not subscribed to a topic do not receive its frames at the NIC. The Phase 35A architecture supports this as a one-line config swap — replace `defaultTopicToGroup` with the Phase 34 derivation function. The session layer is unaffected.

### 17.3.3 UdpTransport

Beneath the `NetworkAdapter`, the multicast adapter composes a `UdpTransport` instance that wraps `node:dgram`:

```typescript
interface UdpTransport {
  bind(port: number, group: string): Promise<void>;
  send(bytes: Uint8Array, port: number, address: string): Promise<void>;
  onMessage(cb: (msg: Uint8Array, rinfo: RemoteInfo) => void): void;
  close(): Promise<void>;
  addMembership(group: string): Promise<void>;
  dropMembership(group: string): Promise<void>;
  memberships(): ReadonlySet<string>;
}
```

`addMembership` and `dropMembership` are present for Phase 34 readiness — when the type-hash group derivation lands, the adapter calls them to join and leave groups dynamically as subscriptions open and close. The `LoopbackUdpTransport` implementation provides an in-memory substitute for tests, maintaining a `Map<group, Set<cb>>` rather than opening OS sockets.

---

## 17.4 Identity on the Mesh

### 17.4.1 BCA Derivation

Every peer's address on the mesh is its BCA. The BCA is derived from a Plexus cert's public key via the algorithm in `packages/cell-engine/src/bca.zig`. The derivation has conformance vectors at `packages/cell-engine/tests/vectors/bca_*.json`; the canonical TypeScript mirror ships at `core/protocol-types/src/bca.ts` [D-A0 / #195] and is conformance-vector-equal to the Zig reference, so every adapter that needs to derive a peer BCA from a BRC-52 cert imports the same library. The key property is determinism: given a cert, any node can compute the BCA without contacting a directory service. The mesh uses BCA for two distinct purposes: routing (which multicast address to use for direct-send), and payment-channel funding (which MFP key to use for the metering hook).

### 17.4.2 The Signer Seam

Signing is exposed behind a `Signer` / `Verifier` interface rather than directly wiring `@bsv/sdk` calls throughout the session layer:

```typescript
interface Identity {
  bca: string;           // IPv6 string, derived from pubkey
  pubkey: Uint8Array;    // 33-byte compressed secp256k1
  certId?: string;       // Plexus cert SHA-256 when available
}

interface Signer {
  identity(): Promise<Identity>;
  sign(bytes: Uint8Array): Promise<Uint8Array>;
}

interface Verifier {
  verify(pubkey: Uint8Array, bytes: Uint8Array, sig: Uint8Array): Promise<boolean>;
}
```

The only file under `session-protocol/src/` that imports `@bsv/sdk` directly is `signer.ts`. Every consumer — the BCA provider, the multicast adapter envelope auth, the WebSocket adapter, session join tokens, metering channel commitments — calls through this choke point. When the Plexus SDK lands, a `PlexusSigner` with the same shape slots in without call-site churn.

The `BCAProvider` composes a `Signer` with BCA derivation from a Plexus cert:

```typescript
interface BCAProvider extends Signer {
  deriveBCA(): Promise<string>; // calls cell-engine bca.zig via host functions
}
```

`BCAProvider` is a `Signer` with an additional derivation method. The signing primitive is inherited, not reimplemented.

---

## 17.5 The Six-Piece Session Skeleton

Above the transport, the substrate provides a domain-neutral session skeleton. The six pieces are:

| Piece | Role |
|---|---|
| Discovery | Peer discovery via heartbeats; BCA-to-endpoint resolution |
| Formation | Multi-party session formation: proposal, acceptance, FormationPolicy |
| Runtime | Per-session state-machine driver; consumes a `StateMachine<Event, State>` |
| Broadcast | Multi-recipient publish; fan-out via the mesh |
| Transport | NetworkAdapter abstraction (multicast, WSS, 6LoWPAN, loopback) |
| Metering Hook | Optional MFP integration; MeteringTicks emitted on FSM transitions |

The skeleton lives in `packages/session-protocol/`. Its public surface exports the six structural pieces as named modules: `AgentDiscovery`, `SessionFormation`, `SessionRuntime`, `BroadcastEngine`, and the `NetworkAdapter` abstraction, with an optional `MeteringHook` interface for MFP integration.

```
[FIGURE — needs real graphic for layout pass]

┌──────────────────────────────────────────────────────────────┐
│  Session Consumer (poker, call, cdm, auction, scada, …)      │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ Domain StateMachine                                   │    │
│  │ (the only vertical-specific piece —                   │    │
│  │  implements StateMachine<Event, State>)               │    │
│  └──────────────────────────────────────────────────────┘    │
└────────────────────────▲─────────────────────────────────────┘
                         │
┌────────────────────────┴─────────────────────────────────────┐
│  packages/session-protocol/                                  │
│  ┌────────────┬─────────────┬────────────┬───────────────┐   │
│  │ Discovery  │  Formation  │  Runtime   │  Broadcast    │   │
│  │            │             │            │  Engine       │   │
│  ├────────────┼─────────────┼────────────┴───────────────┤   │
│  │ Transport  │  Metering Hook (optional MFP integration) │   │
│  │ (via       │                                           │   │
│  │  interface)│                                           │   │
│  └────────────┴───────────────────────────────────────────┘  │
└────────────────────────▲─────────────────────────────────────┘
                         │ NetworkAdapter interface (5 methods)
┌────────────────────────┴─────────────────────────────────────┐
│  Adapter implementations (substrate-specific)                │
│  ┌─────────────┬─────────────┬──────────┬────────────────┐   │
│  │ Multicast   │  WebSocket  │  WebRTC  │  SixLowPan     │   │
│  │ Adapter     │  NodeAdapter│  Adapter │  Adapter       │   │
│  │ (Phase 35A) │  (Phase 35B)│ (35B)    │  (Phase 33B)   │   │
│  └─────────────┴─────────────┴──────────┴────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

Every box above the `NetworkAdapter` interface line is domain-neutral and lives in `session-protocol`. Every box below it is substrate-specific and lives in its own adapter package.

---

## 17.6 The Six Pieces in Detail

### 17.6.1 Discovery

`AgentDiscovery` manages peer presence. It sends periodic heartbeat frames on the primary multicast group and maintains a peer table keyed by BCA. On receiving a heartbeat, it updates the stale-timeout clock for that peer and fires a peer-joined observer event. When a peer's heartbeat is absent past `staleTimeoutMs`, it fires a peer-left event.

Heartbeat frames carry the sender's BCA, timestamp, and the list of topics the peer is currently subscribed to. The discovery layer does not authenticate heartbeats beyond the `SignedBundle` envelope — the Verifier Sidecar at the receive boundary handles that. Discovery is a statement of presence, not a claim of authority.

The BCA-to-endpoint resolution path (`NetworkAdapter.resolveBCA`) retrieves Plexus cert metadata for a peer given its BCA. This is the call site that connects the mesh identity (BCA) to the identity DAG (BRC-52 cert). In the multicast adapter, this lookup consults the `NodeMetadataProvider` rather than returning stub values.

### 17.6.2 Formation

`SessionFormation` implements the multi-party handshake that takes a set of discovered peers and produces a formed session with a known participant list. The inputs are a `SessionProposal` (formerly `TableProposal` in the poker-coupled codebase) and a `FormationPolicy` that controls minimum and maximum party size, required peer capabilities, and timeout behaviour.

Formation proceeds in three stages: the proposer broadcasts a proposal; interested peers respond with acceptance frames; the proposer collects acceptances until the `FormationPolicy` is satisfied and broadcasts a formation-complete frame with the canonical participant list. The participant list is sorted by BCA and hashed; every participant verifies the hash matches what they received. This gives all participants a shared identifier for the formed session.

```typescript
interface SessionDescriptor {
  sessionId: string;          // hash of sorted participant BCAs + formation nonce
  participants: string[];     // BCAs, sorted
  formedAt: number;           // epoch ms
  domain: string;             // topic namespace for this session's frames
}
```

The session ID is the correlation key for all subsequent frames. The domain string namespaces the session's broadcast topic; two sessions on the same multicast group use different domain strings and do not interfere.

### 17.6.3 Runtime

`SessionRuntime` is the per-session state-machine driver. It receives a `StateMachine<Event, State>` at construction time and drives transitions as events arrive from the broadcast layer:

```typescript
interface StateMachine<Event, State, Context = unknown> {
  readonly initialState: State;
  readonly terminalStates: ReadonlySet<State>;
  transition(
    current: State,
    event: Event,
    ctx: Context
  ): {
    next: State;
    emit?: Event[];          // downstream events to broadcast
    meterTick?: MeteringTick; // optional billing event
  };
  validate(current: State, event: Event, ctx: Context): boolean;
}
```

The runtime calls `validate` before `transition`. An invalid event is logged and dropped; the state machine does not see it. `emit` returns downstream events that the runtime broadcasts on behalf of this participant after the transition completes. `meterTick` is forwarded to the `MeteringHook` if one is attached.

On reaching a state in `terminalStates`, the runtime closes the session: it fires a session-complete observer event, cancels the broadcast subscription, and if a metering hook is attached, triggers channel settlement.

The runtime is stateless across sessions — it holds no global mutable state. Each formed session gets its own runtime instance.

### 17.6.4 Broadcast Engine

`BroadcastEngine` publishes events to the full set of session participants using `NetworkAdapter.publish` on the session's domain topic. It applies back-pressure: if a publish call returns a `PayloadTooLargeError`, the engine surfaces the error to the caller rather than silently dropping or splitting.

Fan-out to individual peers for point-to-point frames (session join acceptance, direct acknowledgements) uses `NetworkAdapter.sendToNode` addressed by BCA. The broadcast engine keeps the distinction between topic-broadcast and point-to-point explicit — neither path is a fallback for the other.

### 17.6.5 Transport

The transport piece is the `NetworkAdapter` interface itself. It is not a distinct runtime component but a type contract. The multicast adapter is the Phase 35A implementation: it wraps a `UdpTransport`, applies the `topicToGroup` hook, enforces payload size limits, and handles multicast group membership.

The multicast adapter detects duplicate semantic paths: when two distinct owners publish cells to the same `semanticPath`, it fires a `duplicate_path` observer event. This is not an error condition the adapter resolves — it surfaces the conflict for the session layer to handle.

### 17.6.6 Metering Hook

The metering hook is optional. When absent, the session runs without billing. When present, it receives `MeteringTick` values on each state transition that produces one, and drives the MFP channel lifecycle:

```typescript
interface MeteringHook {
  onTick(tick: MeteringTick): Promise<void>;
  onSessionClose(sessionId: string): Promise<void>;
}
```

The MFP (Metered Flow Protocol) engine beneath the hook manages the 8-state channel FSM, HMAC-authenticated tick proofs, and nSequence settlement. The session protocol does not implement billing logic; it calls through the hook and the hook's implementation handles everything below.

This design keeps billing optional at the session level and allows non-metered sessions (development, tests, governance-only flows) to run the identical code path as metered sessions. The gate test G35A.10 verifies that `SessionRuntime` instantiates without a `MeteringHook` and that tick events fire correctly when one is present.

---

## 17.7 The StateMachine Plug-in

The only domain-specific piece a vertical contributes is a `StateMachine<Event, State>` implementation. The session-protocol package defines the interface; the vertical provides the instance. The session-protocol has no opinion about what events or states are named — it only requires that the interface contract is satisfied.

Verticals supplied in the codebase:

- **Poker** — the reference implementation; `PokerStateMachine` drives the poker hand lifecycle from shuffle through showdown.
- **CDM lifecycle** — drives a derivatives contract from creation through novation, assignment, and termination.
- **SCADA event flow** — drives a control-system sequence from alarm to acknowledgement to clearance.
- **World Host region authority** — drives region-join and entity-migration handshakes.

A minimal conformance test is possible with two states and one event:

```typescript
const MinimalStateMachine: StateMachine<'ping', 'waiting' | 'done'> = {
  initialState: 'waiting',
  terminalStates: new Set(['done']),
  transition(current, event) {
    if (current === 'waiting' && event === 'ping') {
      return { next: 'done' };
    }
    throw new Error(`no transition from ${current} on ${event}`);
  },
  validate(current, event) {
    return current === 'waiting' && event === 'ping';
  },
};
```

The gate test G35A.9 drives this machine through a full session end-to-end on a `LoopbackUdpTransport`, verifying that the session-protocol package imposes no domain assumptions.

---

## 17.8 Prior Art and the Extraction Path

Phase 35A is a promotion, not a greenfield build. Two independent implementations converged on the same session-protocol pattern before the abstraction was formalised:

| Component | Prior location | Status before Phase 35A |
|---|---|---|
| Agent discovery | `packages/poker-agent/src/agent-discovery.ts` | Built — poker-coupled |
| Agent runtime | `packages/poker-agent/src/agent-runtime.ts` | Built — poker-coupled |
| Broadcast engine | `packages/poker-agent/src/direct-broadcast-engine.ts` | Built — poker-coupled |
| P2P agent runner | `packages/poker-agent/src/p2p-agent-runner.ts` | Built — poker-coupled |
| Payment channel | `packages/poker-agent/src/payment-channel.ts` | Built — poker-coupled |
| Table formation | `packages/poker-agent/src/table-formation.ts` | Built — poker-coupled |
| Multicast adapter | hackathon repo `src/protocol/adapters/docker-multicast-adapter.ts` | Built — external repo |
| UDP transport | hackathon repo `src/protocol/adapters/udp-transport.ts` | Built — external repo |

Strip every domain-specific token from both implementations — poker, table, shuffle, blinds, persona, stake — and the remaining structure is identical. Phase 35A extracts that structure into `packages/session-protocol/`, generalises the type signatures, replaces the hackathon stubs (the inline BCA derivation, the internal txid counter, the `/tmp/semantos-heartbeat` file write) with injected providers, and makes poker-agent the first consumer.

The extraction is validated by a behavioural equivalence gate: all pre-35A poker tests must pass against the refactored session-protocol without behavioural change. The session contract is isomorphic to the old poker-specific wiring; the test suite detects any regression.

---

## 17.9 Adapter Implementations

### 17.9.1 MulticastAdapter (Phase 35A)

The current default adapter wraps a `UdpTransport` and joins the link-local multicast group `ff02::1`. All topics land on one group; software demultiplexing filters by topic string inside `handleCell`. The payload limit is 65,507 minus `HEADER_SIZE`; the adapter rejects larger frames at publish time with `PayloadTooLargeError`.

The adapter's BCA derivation is injected via `BCAProvider` rather than computed inline. Its txid minting is injected via `TxidProvider`. Its heartbeat side effects are injectable via `HeartbeatSink`. These three injections replace the three stubs in the hackathon codebase and are the mechanism by which the adapter connects to real platform primitives.

### 17.9.2 Phase 34 Readiness

Phase 34 designs a type-hash-to-multicast-group addressing scheme in which each type hash maps to a distinct IPv6 multicast group. When that scheme lands, the swap is one configuration line:

```typescript
// Current default (Phase 35A):
const topicToGroup: TopicToGroup = defaultTopicToGroup; // always 'ff02::1'

// Phase 34 promotion (one-line swap):
const topicToGroup: TopicToGroup = typeHashTopicToGroup; // derived per type hash
```

The `MulticastAdapter` applies `topicToGroup` at `publish()` and `subscribe()` time and calls `UdpTransport.addMembership` / `dropMembership` when the resulting group changes. Nodes that do not subscribe to a topic will not join the corresponding group and will not receive those frames at the NIC level. This is the transport-level filtering that Phase 34 is designed to provide; Phase 35A ships the hook, not the scheme.

### 17.9.3 Future Adapters

Three additional adapter implementations are planned but are not in Phase 35A scope:

| Adapter | Phase | Transport substrate |
|---|---|---|
| `WsNodeAdapter` | 35B | WebSocket + TLS (public internet) |
| `WebRtcAdapter` | 35B | WebRTC data channels (browser peers) |
| `SixLowPanAdapter` | 33B | IEEE 802.15.4 radio (embedded, ≤127-byte MTU) |

Each adapter implements `NetworkAdapter` and enforces its own payload limit. The session protocol does not change. The SixLowPan adapter must enforce a MTU of 127 bytes minus radio header; it will reject larger payloads at the adapter boundary, giving the session layer a clear error to handle rather than a silent drop.

---

## 17.10 The Session Lifecycle

A complete session proceeds through four phases, each driven by one of the skeleton's six pieces:

### Phase 1 — Discovery

Both nodes are online and sending heartbeats on `ff02::1`. `AgentDiscovery` on each node maintains a peer table. When node A's discovery layer sees node B's heartbeat, it records B's BCA, resolves B's Plexus cert metadata via `resolveBCA`, and adds B to the available-peers set. This is a passive, continuous process — no explicit handshake is required to discover.

### Phase 2 — Formation

Node A's vertical-layer code decides to initiate a session with B (and possibly other discovered peers). It calls `SessionFormation.propose(policy, peers)`. The formation layer broadcasts a `SessionProposal` frame on the domain topic. Node B's formation layer receives the proposal, checks the `FormationPolicy`, and responds with an acceptance frame. Node A collects acceptances until the policy is satisfied and broadcasts a `FormationComplete` frame containing the `SessionDescriptor`. Both nodes now hold the same `sessionId` and participant list.

### Phase 3 — Runtime

Both nodes' `SessionRuntime` instances are now active on the same `sessionId`. Events flow via the `BroadcastEngine`: one node calls `broadcast(event)`, the engine publishes to the session's domain topic, and all participants receive the frame, verify the `SignedBundle` envelope, and feed the event into their local `StateMachine` instance. Because the state machine is deterministic, all participants converge to the same state from the same sequence of events. The runtime on each node is the authority for its own state; there is no coordinator.

### Phase 4 — Close

When any participant's state machine reaches a terminal state, that participant broadcasts a session-close frame and closes its runtime. The remaining participants see the close frame, verify it is consistent with their own terminal-state transition, and close their own runtimes. If a metering hook is attached, channel settlement is triggered on close. The session ID is retired and the peer entries remain in the discovery table for future sessions.

---

## 17.11 Multi-Party Sessions and State Machine Constraints

The session skeleton is not restricted to two parties. The `FormationPolicy` specifies minimum and maximum party size; values above two are valid. The `BroadcastEngine` fans out to all participants on the shared topic. The `StateMachine` interface does not impose any structural constraint on how many participants a transition depends on — that is a matter for the domain state machine.

A multi-party state machine must be designed to handle out-of-order event delivery and partial participation. The session-protocol does not provide sequencing guarantees beyond what the underlying UDP transport provides (none). Domain state machines that require total ordering must implement their own sequencing — for example, by including a sequence number in each event and holding events that arrive out of order.

The reference poker implementation handles this by making every game-legal action deterministic given the publicly-known game state: the state machine validates the event source against the expected player seat, so only the designated player's action can advance the FSM at each step. Other multi-party designs may use threshold signatures, witnessed majority votes, or external sequencers — the session skeleton is neutral on all of these.

---

## 17.12 Gate Tests

Phase 35A defines twelve gate tests for the session-protocol package. The ones most directly relevant to this chapter's content:

| Test | What it checks |
|---|---|
| G35A.1 | Two `SessionRuntime` instances on `LoopbackUdpTransport` form a session and reach the same terminal state after scripted events |
| G35A.2 | `MulticastAdapter.publish` with `defaultTopicToGroup` delivers to all subscribers; topic filtering is in-memory |
| G35A.3 | `MulticastAdapter.publish` with Phase-34-style `topicToGroup` — non-subscribing nodes do not observe at transport level |
| G35A.5 | `PlexusCertBCAProvider.deriveBCA()` matches `bca_conformance.zig` test vectors |
| G35A.6 | `TxidProvider` injection — the adapter never mints its own txid |
| G35A.9 | A stub `MinimalStateMachine<"ping","pong">` drives a session end-to-end |
| G35A.10 | Session instantiates without a `MeteringHook`; tick events fire correctly with one present |
| G35A.11 | `BsvSdkSigner` + `BsvSdkVerifier` round-trip on 1 KB payload; `PlexusCertBCAProvider.sign()` bytes-identical to its injected `Signer.sign()` |
| G35A.12 | Only `signer.ts` under `session-protocol/src/` imports `@bsv/sdk` — static check |

G35A.12 is a static import check, not a runtime test. It enforces the signer-seam discipline structurally.

---

## 17.13 Dependency and Composition Map

The session-protocol package depends on:

- `packages/protocol-types/` — the `NetworkAdapter` interface, `PublishableObject`, `NetworkEvent`
- `packages/cell-engine/` — BCA derivation (via WASM host function call through `BCAProvider`)
- `packages/metering/` — the MFP channel lifecycle, consumed via `MeteringHook` (optional)
- `packages/settlement/` — the `TxidProvider` implementation (injected, not imported directly)

It does not depend on any domain package. The arrow of dependency points outward from session-protocol to infrastructure, and inward from domain packages (poker-agent, call-protocol) to session-protocol. Domain packages depend on session-protocol; session-protocol does not depend on domain packages.

```
packages/poker-agent/          ──→  packages/session-protocol/
packages/call-protocol/        ──→  packages/session-protocol/
packages/cdm-protocol/         ──→  packages/session-protocol/
                                          │
                         ┌────────────────┼──────────────────┐
                         ↓               ↓                   ↓
               protocol-types/      cell-engine/          metering/
```

This dependency topology means the session-protocol package can be tested in full isolation using the `LoopbackUdpTransport`, a `StubSigner`, and a `DeterministicBCAProvider` — none of which require network, WASM, or chain access.

---

## 17.14 Relation to the Boot Sequence

The boot sequence is the 15-step canonical procedure that takes a sovereign node from cold start through recoverable, federated, metered, fully K1–K13-compliant online state. The mesh and session skeleton are the subject of boot step 10.

Steps 1 through 7 establish identity, derivation, capability tokens, domain flag enforcement, and the cell engine (`kernel_set_enforcement(1)` at step 7). Step 8 brings up the Verifier Sidecar. Step 9 brings up the World Host region runtime.

Step 10 is the session-protocol stack: the multicast transport binds its UDP socket, the discovery heartbeat starts, and the node's BCA is live on the mesh. At this point, the node can discover peers, form sessions with them, and exchange signed frames. The node is not yet metered (step 14 is MFP) and not yet fully federated for public-internet peers (Phase 35B), but the local-network session capability is operational.

---

## Summary

```
[FIGURE — needs real graphic for layout pass]

  Six-Piece Session Skeleton
  ══════════════════════════

  ┌────────────────────────────────────────────────────────────┐
  │  1. Discovery         Peer heartbeats; BCA → endpoint      │
  │  2. Formation         Proposal / acceptance / descriptor   │
  │  3. Runtime           StateMachine<E,S> driver             │
  │  4. Broadcast Engine  Fan-out via NetworkAdapter.publish   │
  │  5. Transport         NetworkAdapter (5-method interface)  │
  │  6. Metering Hook     Optional MFP tick on FSM transition  │
  └────────────────────────────────────────────────────────────┘
             │
             │ the only vertical contribution
             ▼
  ┌──────────────────────────┐
  │ Domain StateMachine      │  ← poker / cdm / scada / world-host / …
  │ StateMachine<Event,State>│
  └──────────────────────────┘
```

Every vertical is a state machine over a shared session skeleton. The poker implementation, the CDM lifecycle implementation, the SCADA event-flow implementation, and the World Host region-authority implementation all reduce to a `StateMachine<Event, State>` instance mounted on the same six-piece platform. The domain-specific code is thin; the session infrastructure is shared.

The mesh carries frames as `SignedBundle` (BRC-100 envelope) over IPv6 multicast by default. Peers are addressed by BCA. The `topicToGroup` hook is the extension point that Phase 34 will use to promote software demultiplexing to transport-level group membership. The `NetworkAdapter` interface is the codec port that makes the transport replaceable without touching any session logic.

Boot-sequence step 10 is now unlocked. The multicast transport is bound, the discovery heartbeat is running, and the node's BCA is live on the mesh. Peer sessions can form. The next chapter covers Helm — the convergence surface through which this mesh capability becomes visible to an operator.
