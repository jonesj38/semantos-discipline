---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/36-federation-transport.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.645801+00:00
---

# Chapter 36 — Federation Transport: Four Layers, Not One

The word "federation" gets attached to too many things. Public framing treats federation as a single layer ("federation = UDP multicast"); reality is **four cleanly-separated layers** with different responsibilities, different identity primitives, different wire formats, and different deployment topologies. Conflating them produces the kind of categorical confusion that the §11 truth-alignment supplement was written to fix.

This chapter pins each layer in place:

1. **Phase-26D — `NetworkAdapter` interface.** The seam that lets any transport plug in.
2. **Phase-35A — `MulticastAdapter`.** UDP multicast for local mesh / campus LAN.
3. **Phase-35B — `WsNodeAdapter`.** WSS-based federation for cross-internet topology.
4. **Dispatch envelope.** Semantic seam above transport; cross-vertical object exchange.

Plus a sibling layer that often gets miscategorized as federation but isn't:

5. **Operator-internal NATS event spine.** Local event distribution within one operator's tenant — *not* federation.

---

## 36.1 The "Do Not Conflate" Table

A condensed version of the table in `docs/prd/PHASE-26D-NETWORK-ADAPTER.md`, extended with the federation-specific layers:

| Concern | Layer | What it does | Implementations |
|---|---|---|---|
| Where bytes live | Storage adapter | Persistence + local state | Memory, NodeFs, BsvOverlay |
| Who you are | Identity adapter | Identity, derivation, capabilities | Stub, Local, Cloud |
| Proving things existed | Anchor adapter | Timestamp proofs on chain | Stub, BSV |
| How objects move (interface) | **NetworkAdapter** | publish, subscribe, resolve | (interface only) |
| How objects move (LAN) | **MulticastAdapter** (Phase-35A) | IPv6 UDP multicast | `runtime/session-protocol/` |
| How objects move (internet) | **WsNodeAdapter** (Phase-35B) | WSS with license handshake | `runtime/ws-node-adapter/` |
| How objects find peers | **PeerLocator** | BCA → endpoint resolution | `runtime/peer-locator/` |
| Cross-vertical seam | **Dispatch envelope** | RELEVANT cell + AFFINE patches | `extensions/dispatch/` |
| Operator-internal events | **NATS bridge** (today) | NATS subject → in-memory bus → WSS | `runtime/semantos-brain/src/nats_event_bridge.zig` |

All eight are distinct. A node may compose all of them; none substitutes for another.

---

## 36.2 Layer 1 — Phase-26D `NetworkAdapter` (the interface)

The kernel doesn't talk to UDP, to WSS, to NATS, or to anything else directly. It talks to a `NetworkAdapter` interface. Phase-26D unifies what used to be three separate clients (`TopicManagerClient`, `LookupServiceClient`, `ShardProxyClient`) behind one interface so that the wire underneath can be swapped without touching session logic above.

### The five methods

The `NetworkAdapter` interface exposes a small surface (see chapter 17 §17.3 for the canonical contract):

- `publish(topic, frame)` — emit a signed frame to all subscribers of a topic
- `subscribe(topic, handler)` — register a handler for frames on a topic
- `resolve(query)` — look up cell IDs / objects by content-address or service-prefix query
- `start()` / `stop()` — lifecycle

That's it. Five methods. Every adapter implementation honors the same contract: the `MulticastAdapter`, the `WsNodeAdapter`, the `LoopbackAdapter` (in-process for tests), and the future `SixLoWPanAdapter` (Phase-33B radio).

### BRC alignment (per §11.6)

Phase-26D's three pre-unification clients map directly to BRC standards:

- `TopicManagerClient` → **BRC-22** (SHIP — Overlay Network Data Synchronization)
- `LookupServiceClient` → **BRC-24** (SLAP — Overlay Network Lookup Services)
- `ShardProxyClient` → UDP multicast (Phase-35A's territory)

The §11.6 binding recommendation to BRC-22/23/24/87/88 falls out of Phase-26D's existing architecture — the NetworkAdapter's `publish` is BRC-22 semantics; its `resolve` is BRC-24 semantics. Tightening this binding is the D-C6c contract test suite work.

### What Phase-26D is NOT

- Not a wire format. (The wire format lives in the adapter implementations.)
- Not a transport. (The transport is whichever adapter is installed.)
- Not federation. (Federation rides over the interface; the interface itself is topology-neutral.)

---

## 36.3 Layer 2 — Phase-35A `MulticastAdapter` (local mesh)

Lives at `runtime/session-protocol/`. Phase-35A deliverable. The default `NetworkAdapter` implementation for nodes that share a network segment (campus LAN, residential ISP, internal datacenter).

### What it does

Joins IPv6 multicast groups (default `ff02::1`). Frames are UDP datagrams carrying:

```
┌──────────────────────────────────────────┐
│  12-byte adapter header                  │ ← magic, version, msgType, nonce
├──────────────────────────────────────────┤
│  SignedBundle<T>                         │ ← BRC-100 envelope (CBOR)
│  ┌────────────────────────────────────┐  │
│  │  x-brc100-identitykey              │  │
│  │  x-brc100-nonce                    │  │
│  │  x-brc100-timestamp                │  │
│  │  x-brc100-signature                │  │
│  │  x-brc52-certificate               │  │
│  │  payload: T                        │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

Per chapter 17 §17.2 + chapter 34 §34.2: payload bounded by `65,507 - HEADER_SIZE` bytes (UDP datagram limit), reject with `PayloadTooLargeError` rather than fragment silently. With 1024-byte cells, ~63 cells per datagram (chapter 34 §34.7).

### Five seams

The `MulticastAdapter` exposes five composable seams (per `runtime/session-protocol/README.md`):

1. **Signer** — BRC-52 cert-bound signing
2. **BCAProvider** — Blockchain Channel Address derivation (Plexus or deterministic)
3. **MulticastAdapter** — the multicast itself
4. **broadcast helpers** — fan-out logic
5. **SessionRuntime** — event loop + state + metering

Any vertical that needs multi-party sessions plugs in a domain `StateMachine<Event, State>` and consumes these five seams. Poker, voice/video, conference rooms, CDM lifecycle events, SCADA telemetry — six boxes plus the state machine.

### When 35A is the wrong layer

- **Across the internet.** UDP multicast doesn't route across BGP boundaries. Cross-tenant federation needs Phase-35B.
- **Through browsers / mobile.** Web Workers and mobile runtimes can't do UDP. They connect via Phase-35B WSS to a node that participates in 35A on their behalf.
- **Through Vercel / serverless.** Per `docs/PLATFORM-ARCHITECTURE.md:287`, Vercel can't do UDP multicast. Phase-35B is required.

The "Federation = UDP multicast" framing in earlier memory entries was correct for *local-mesh* federation in V1/V2 but missed the cross-internet case entirely. Per the corrected memory `semantos_federation_transport.md`: Phase-35A is the local-mesh default; Phase-35B is required for cross-internet topology.

---

## 36.4 Layer 3 — Phase-35B `WsNodeAdapter` (cross-internet federation)

Lives at `runtime/ws-node-adapter/`. **Code ships today** (correction to §11.6's "not shipped" framing — see chapter D-Doc-adapters §3). The transport for federation between sovereign nodes that are not on the same network segment.

### Wire format

CBOR frames with a leading `kind` discriminator. Four kinds in Phase-35B.1:

| Kind | Direction | Role |
|---|---|---|
| `license_handshake` | bidirectional, first frame | Identity + authorisation proof |
| `session_envelope` | post-handshake | Carries `PublishableObject` payload |
| `heartbeat` | post-handshake | Idle filler (30s) to keep NATs happy |
| `bye` | post-handshake, optional | Graceful shutdown |

### License handshake

The first frame is a license-handshake that proves three things:

1. The sender holds a valid License signed by an issuer the recipient accepts (`verifyLicense` + `isAcceptableIssuer` policy)
2. The sender controls the holder private key (signature over `challenge || sha256(licenseBytes)`)
3. The sender's claimed BCA matches the derivation from `license.pubkey`

Replay protection comes from TLS at the transport layer; the 32-byte challenge prevents signature caching across connections.

### Components

```
┌──────────────────────────────────────────────────────────┐
│  WsNodeAdapter                                           │
│  ┌──────────────┬──────────────┬──────────────────────┐  │
│  │  Bun.serve   │  connect(bca)│  publish / subscribe │  │
│  │  /session    │  via locator │  (topic fan-out)     │  │
│  └──────┬───────┴───────┬──────┴──────────────────────┘  │
│         │               │                                │
│  ┌──────▼───────────────▼──────────────────────────────┐ │
│  │  WsPeerConnection (per-peer state machine)         │ │
│  │  authenticating → authenticated → closing → closed │ │
│  └─────────────────────┬──────────────────────────────┘ │
│                        │                                │
│  ┌─────────────────────▼──────────────────────────────┐ │
│  │  license-handshake ← codec ← types                 │ │
│  │  (verify frame)    (CBOR)  (FRAME_KIND enum)       │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

Bun.serve accepts inbound `/session` connections. `connect(bca)` dials outbound via the peer locator. Both directions exchange `license_handshake` first, then carry `session_envelope` frames for the duration.

---

## 36.5 Layer 3.5 — `PeerLocator` (BCA → endpoint resolution)

Lives at `runtime/peer-locator/`. Three implementations, two shipping today, one for Phase-35B.3.

### The contract

```ts
export interface NodeEndpoint {
  bca: string;                // IPv6 BCA of the node
  wssUrl: string;             // wss://host:port/session
  pubkey?: Uint8Array;        // 33-byte compressed secp256k1 (optional pinning)
  licenseCertId?: string;     // "sha256:<hex>" (optional pinning)
}

export interface PeerLocator {
  resolve(bca: string): Promise<NodeEndpoint | null>;
  register(endpoint: NodeEndpoint): Promise<void>;
}
```

Optional `pubkey` and `licenseCertId` provide identity pinning — a locator that lies about the WSS URL still cannot substitute a peer whose license cert differs from what was advertised.

### Three implementations

- **StaticPeerLocator** — map-backed, synchronous, deterministic. Used for tests, bootstrap lists, small private federations.
- **DnsPeerLocator** — DNS TXT-backed. Queries `_semantos-node.<hostname>` for records like `bca=<ipv6>;wss=<url>;licenseCertId=<id>;pubkey=<hex>`. 60s cache TTL by default.
- **FederatedPeerLocator** — operator-run federated registry, lands in Phase-35B.3. The decentralized variant.

### BRC alignment (per §11.6)

The peer locator's role corresponds to **BRC-101** (SHIP / SLAP Overlay Advertisements). BRC-101 currently specifies only plain HTTPS for advertisement URLs; the `wss://` scheme used by Phase-35B is aspirational per BRC-101's own framing. The §11.6 open decision **OD-BRC-3** captures this: lock to HTTPS for V1 advertisement, hook composite schemes for later.

---

## 36.6 Layer 4 — Dispatch Envelope (semantic seam above transport)

Lives at `extensions/dispatch/`. Chapter 29 of this textbook is the canonical narrative. The federation layer that operates on **meaning**, not bytes.

### What dispatch is

The dispatch envelope is a **RELEVANT** cell visible to all hat-holders, carrying **AFFINE** patches that are encrypted per-hat and invisible to every other participant. Two verticals reference the same envelope; each reads the RELEVANT shared fields plus their own AFFINE partition.

Three cell types are defined:

- `dispatch.envelope.v1` (LINEAR) — the envelope itself, carrying a payload cell signed by the originating hat
- `dispatch.accepted.v1` (LINEAR) — receive-side acknowledgement after the receiving extension successfully materialises the envelope
- `dispatch.completion.v1` (LINEAR) — completion-and-billing patch from the receiving vertical when work reaches its terminal state

### Payload-agnostic routing

The dispatch handler **knows nothing about the shape of the inner payload cell**. It routes by `payload_type` (e.g. `re-desk.maintenance-request.v1`) to a registered accept-handler contributed by the receiving extension at boot. Adding a new vertical doesn't modify dispatch — only register the new payload type.

This is the load-bearing claim: dispatch is a universal bridge primitive; verticals plug in by registering accept-handlers. Chapter 29 walks through the worked example with `oddjobz` (trades) on the receiving side and `re-desk-stub` (property management) on the originating side.

### How dispatch composes with transport

The dispatch envelope is a *cell*. It rides whatever transport the node has installed — `MulticastAdapter` on LAN, `WsNodeAdapter` on the internet, `LoopbackAdapter` for in-process tests. The dispatch primitive doesn't care which.

The signed-bundle envelope around it does. Per chapter 17 §17.2.1: every cross-process or cross-node message is wrapped in a `SignedBundle<T>` BRC-100 envelope before the multicast adapter / WSS adapter touches it. The Verifier Sidecar (§9.5 of the protocol spec) verifies every header before the payload is processed.

```
┌────────────────────────────────────────────────┐
│  Cell engine (per node)                        │ ← evaluates dispatch.envelope.v1
└──────────────────┬─────────────────────────────┘
                   │ SignedBundle<dispatch.envelope.v1>
                   ▼
┌────────────────────────────────────────────────┐
│  Verifier Sidecar                              │ ← BRC-100 + BRC-52 + identity bind
└──────────────────┬─────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────┐
│  NetworkAdapter (Phase-26D interface)          │
│    publish(topic="dispatch.envelope.v1", …)    │
└──────────┬────────────────────┬────────────────┘
           │ LAN                │ Internet
           ▼                    ▼
┌──────────────────┐   ┌──────────────────────┐
│  Multicast (35A) │   │  WsNodeAdapter (35B) │
└──────────────────┘   └──────────────────────┘
```

---

## 36.7 The Sibling Layer: Operator-Internal NATS Bridge

A common misclassification: people see "NATS in the architecture diagram" and assume it's federation. It isn't. The NATS event spine is **operator-internal**.

### What it is

`runtime/semantos-brain/src/nats_event_bridge.zig` (landed `7247694` on 2026-05-13 per memory `brain_reactor_v1_recovery_complete.md` and `docs/REACTOR-PORT-TRACKER.md`). Subscribes to subjects on the operator's local NATS stream and bridges incoming `MSG` frames into the in-memory `OddjobzEventBus` that `WSS /api/v1/events` consumes.

```
┌────────────────────────────────────────────────────────────┐
│  jobs_handler                                              │ ← emits to NATS only
└──────────────────────────────┬─────────────────────────────┘
                               │ nats pub op.<op_pkh>.<hat>.<event>
                               ▼
┌────────────────────────────────────────────────────────────┐
│  NATS broker (operator-local)                              │
└──────────────────────────────┬─────────────────────────────┘
                               │ MSG frame on subject op.>
                               ▼
┌────────────────────────────────────────────────────────────┐
│  nats_event_bridge.zig (subscriber)                        │
└──────────────────────────────┬─────────────────────────────┘
                               │ OddjobzEventBus.publish()
                               ▼
┌────────────────────────────────────────────────────────────┐
│  In-memory bus → reactor.pre_tick_drain → write_buf        │
└──────────────────────────────┬─────────────────────────────┘
                               │ WSS frame
                               ▼
┌────────────────────────────────────────────────────────────┐
│  /api/v1/events?hat=<hat> (single operator's tenant)       │
└────────────────────────────────────────────────────────────┘
```

### Why it's not federation

- It stays **within one operator's local environment**. The NATS broker is the operator's; the subjects are scoped to `op.<op_pkh>.*`.
- It carries **event notifications**, not authoritative cell state. The cells live in LMDB stores; the events are state-transition fanout.
- It is **TCP, not multicast**, and **WSS-to-client, not WSS-to-peer**. The transport choices are operator-internal optimization, unrelated to peer federation.

NATS is the canonical local event stream for one operator's tenant. Federation between operators rides Phase-26D/35A/35B. The two are siblings, not the same thing — and confusing them produces the "but we have NATS, isn't that federation?" misframing that earlier memory entries hinted at.

### Anti-claim test (D-W3)

§11.2's D-W3 captures this property explicitly: freeze region A's tick (or NATS broker) and verify that cells in region B continue to advance their own `prevStateHash` chains via the federation transport. The two event streams are independent.

---

## 36.8 Identity at Each Layer

A frame travelling end-to-end across federation carries multiple identity primitives, each enforced at a different layer:

| Identity primitive | Bound where | Verified by | BRC reference |
|---|---|---|---|
| BCA (Blockchain Channel Address) | Adapter address (multicast group or WSS endpoint) | PeerLocator at dial time; signature on every frame | derived from BRC-52 |
| BRC-52 certificate | `x-brc52-certificate` header in `SignedBundle` | Verifier Sidecar at every adapter boundary | **BRC-52** |
| BRC-100 signature | `x-brc100-signature` over canonical preimage | Verifier Sidecar at every adapter boundary | **BRC-100** |
| License (Phase-35B only) | License-handshake frame | `verifyLicense` + `isAcceptableIssuer` policy | per Phase-35B spec |
| Hat (within cell payload) | `facetId` on each patch | Policy evaluator at query time (`checkContributionRight`) | per chapter 29 |
| Capability (UTXO) | OP_CHECKCAPABILITY in cell bytecode | Cell engine; pending D-Dcap-engine binding to BRC-108 + BRC-115 | **BRC-108**, **BRC-115** (post §11.6) |

Each identity primitive serves a distinct purpose. Stripping any one breaks the layer that needed it. The Verifier Sidecar is the single chokepoint for the BRC-100 / BRC-52 pair at every adapter boundary (per §8 Q3 of the unification roadmap, default deployment is per-node process).

---

## 36.9 What's Shipped, What's Designed, What's Remaining

Cross-referencing chapter D-Doc-adapters (`docs/ADAPTER-TAXONOMY.md` §3, §4):

| Component | Status | Path |
|---|---|---|
| `NetworkAdapter` interface (Phase-26D) | ✓ shipped | `core/protocol-types/` |
| `MulticastAdapter` (Phase-35A) | ⚠ partial | `runtime/session-protocol/` |
| `WsNodeAdapter` (Phase-35B) | ✓ shipped | `runtime/ws-node-adapter/` |
| `StaticPeerLocator` + `DnsPeerLocator` | ✓ shipped | `runtime/peer-locator/` |
| `FederatedPeerLocator` (35B.3) | DESIGN | (pending) |
| Verifier Sidecar (D-V1) | ⚠ partial | `runtime/verifier-sidecar/` |
| Dispatch envelope | ✓ shipped | `extensions/dispatch/` |
| NetworkAdapter contract test suite (D-C6c, §11.6) | NOT STARTED | (pending) |
| BRC-22/24/87/88 binding (§11.6) | NOT STARTED | (pending) |
| Cross-internet deployment topology | NOT STARTED | (pending production rollout) |

The biggest remaining gaps are the **contract test suite** and the **production deployment topology** for Phase-35B. Both blockers are operational, not architectural — the code exists, the test discipline and deploy runbook don't.

---

## 36.10 Common Misclassifications and Their Fixes

| Misclassification | Correction |
|---|---|
| "Federation = UDP multicast" | False. Federation rides over Phase-26D `NetworkAdapter`. UDP multicast is *one* implementation (Phase-35A). WSS is another (Phase-35B). |
| "Phase-35B isn't shipped" | False (as of 2026-05-13). `runtime/ws-node-adapter/` ships. What's not shipped is the production deployment topology. |
| "NATS is federation" | False. NATS in `nats_event_bridge.zig` is operator-internal event distribution. Federation between operators rides Phase-35A/35B. |
| "We need to build our own peer discovery" | False. `runtime/peer-locator/` ships two implementations today (Static, Dns). Federated registry is Phase-35B.3. |
| "Dispatch is a transport" | False. Dispatch is a *semantic seam* above transport. It rides whichever transport the node has installed. |
| "The world-host 20 Hz tick orders all cells across federation" | False (per chapter D-Doc-adapters and §11). The 20 Hz tick is region-scoped within one world-host. Cells across federation order via their own `prevStateHash` chains. |
| "BRC-22 is the multicast standard" | False. BRC-22 is the *Overlay Network Data Sync* standard — semantically equivalent to `NetworkAdapter.publish()`, transport-agnostic. The multicast standard is BRC-82 / BRC-124. |

---

## 36.11 Sources Referenced

- `docs/prd/PHASE-26D-NETWORK-ADAPTER.md` — interface unification spec
- `docs/textbook/17-mesh-and-session-skeleton.md` — multicast wire format, codec port
- `docs/textbook/29-cross-vertical-dispatch-and-federation.md` — dispatch envelope narrative
- `docs/textbook/34-cell-alignment.md` §34.2 — 1024-byte cell + UDP datagram alignment
- `docs/prd/UNIFICATION-ROADMAP.md` §11.6 — BRC bindings (BRC-22/24/82/87/88/101/124)
- `docs/ADAPTER-TAXONOMY.md` §3, §4 — adapter status table
- `runtime/session-protocol/README.md` — Phase-35A multicast adapter
- `runtime/ws-node-adapter/README.md` — Phase-35B WSS adapter
- `runtime/peer-locator/README.md` — three peer-locator implementations
- `extensions/dispatch/README.md` — dispatch envelope contract
- `runtime/verifier-sidecar/README.md` — D-V2 deployment topology
- `runtime/semantos-brain/src/nats_event_bridge.zig` — operator-internal NATS bridge (sibling, not federation)
- Memory `semantos_federation_transport.md` (corrected 2026-05-13)
- Memory `brain_reactor_v1_recovery_complete.md` — NATS A+B landing

Four federation layers. One operator-internal sibling. Eleven misclassifications worth being explicit about. The substrate doesn't have a federation problem; it has a federation *naming* problem, and naming is what this chapter exists to fix.
