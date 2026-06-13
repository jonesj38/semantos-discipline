---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.692705+00:00
---

# Phase 35A — Session Protocol Promotion

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1–2 weeks
**Prerequisites**: Phase 26D (NetworkAdapter interface), Phase 27 (poker-agent MVP), Phase H1 (DockerMulticastAdapter hackathon code)
**Branch prefix**: `phase-35a-`
**Master document**: `PHASE-35-USER-NODE-SERVICE.md` (this doc + 35B together)

---

## Context

Semantos has, without fully realising it, two independent implementations of the same multi-party session-protocol pattern: `packages/poker-agent/` in semantos-core (integrated, mid-restructure) and the extracted `src/agent/` in the `todriguez/hackathon-submission` repo (isolated, self-contained, ships with a working IPv6 UDP multicast transport). The file lists overlap almost one-to-one — `agent-discovery`, `agent-runtime`, `direct-broadcast-engine`, `p2p-agent-runner`, `payment-channel`, `poker-message-transport`, `table-formation`, `poker-state-machine` — but the extracted version also carries `src/protocol/adapters/docker-multicast-adapter.ts` and `udp-transport.ts`, which are the running-code equivalents of what Phase 34 is designing.

Phase 35A formalises the abstraction that both implementations converged on. The skeleton is domain-neutral: agent discovery, session formation, state-machine-driven event flow, broadcast engine, metered participation, and agent runtime. The only domain-specific piece is the state machine itself. Every vertical (poker, calls, CDM lifecycle, SCADA events, auctions, oracles) becomes a thin consumer of the same skeleton plus its own state machine.

This phase does the extraction as a promotion: the hackathon code comes back into the main repo as a named platform package, with the stubs replaced by real platform primitives. Poker-agent becomes the first consumer. Phase 35B (node-as-service) is the second consumer.

### Why This Is a Separate Phase from Phase 34

Phase 34 designs a type-hash → multicast group addressing scheme with SRv6 segment routing. That's the network layer's semantic addressing story. Phase 35A is one layer up: given any `NetworkAdapter` implementation, what is the reusable session shape that agents run on top of it. The two phases compose cleanly — the session-protocol package has no opinion on whether the underlying adapter is Phase 34's SRv6 fabric, the current DockerMulticast transport, a future WebSocket transport, or 6LoWPAN. It only requires the five interface methods.

### Prior Art in the Codebase

| Concept | Source | Status |
|---------|--------|--------|
| Agent discovery | `packages/poker-agent/src/agent-discovery.ts` | Built — poker-coupled |
| Agent runtime | `packages/poker-agent/src/agent-runtime.ts` | Built — poker-coupled |
| Broadcast engine | `packages/poker-agent/src/direct-broadcast-engine.ts` | Built — poker-coupled |
| P2P agent runner | `packages/poker-agent/src/p2p-agent-runner.ts` | Built — poker-coupled |
| Payment channel hub | `packages/poker-agent/src/payment-channel.ts` | Built — poker-coupled |
| Table formation | `packages/poker-agent/src/table-formation.ts` | Built — poker-coupled |
| Multicast adapter | `todriguez/hackathon-submission:src/protocol/adapters/docker-multicast-adapter.ts` | Built — external repo |
| UDP transport | `todriguez/hackathon-submission:src/protocol/adapters/udp-transport.ts` | Built — external repo |
| NetworkAdapter interface | `packages/protocol-types/src/network.ts` | Built — platform |

### What Already Exists (Production)

| Component | Location | What it provides |
|-----------|----------|------------------|
| NetworkAdapter interface | `packages/protocol-types/src/network.ts` | `publish`, `subscribe`, `resolve`, `resolveBCA`, `sendToNode` |
| BCA derivation | `packages/cell-engine/src/bca.zig` | Real IPv6 from Plexus cert pubkey |
| Metering FSM | `packages/metering/` | 8-state channel lifecycle, tick proofs, settlement |
| Settlement batching | `packages/settlement/` | Border-router aggregation, CBOR, Merkle batching |
| Node daemon | `packages/node/` | HTTPS admin API, TLS, routes |
| Cell-ops | `packages/cell-ops/` | Type hash registry, packing, merkle |

---

## Architecture

### The Six-Piece Skeleton

Strip every domain-specific token (poker, table, shuffle, blinds) from both implementations and the remaining structure is:

```
┌──────────────────────────────────────────────────────────┐
│  Session Consumer (poker, call, cdm, auction, …)         │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Domain StateMachine (the only vertical-specific    │  │
│  │ piece — implements StateMachine<Event, State>)     │  │
│  └────────────────────────────────────────────────────┘  │
└───────────────────────▲──────────────────────────────────┘
                        │
┌───────────────────────┴──────────────────────────────────┐
│  packages/session-protocol/ (this phase)                 │
│  ┌────────────┬────────────┬────────────┬─────────────┐  │
│  │ Discovery  │ Formation  │ Runtime    │ Broadcast   │  │
│  │            │            │            │ Engine      │  │
│  ├────────────┼────────────┼────────────┼─────────────┤  │
│  │ Transport  │ Metering   │                          │  │
│  │ (via       │ Hook       │                          │  │
│  │  interface)│ (optional) │                          │  │
│  └────────────┴────────────┴────────────┴─────────────┘  │
└───────────────────────▲──────────────────────────────────┘
                        │ NetworkAdapter interface
┌───────────────────────┴──────────────────────────────────┐
│  Adapter implementations (substrate-specific)            │
│  ┌────────────┬────────────┬────────────┬─────────────┐  │
│  │ Multicast  │ WebSocket  │ WebRTC     │ SixLowPan   │  │
│  │ Adapter    │ NodeAdapter│ Adapter    │ Adapter     │  │
│  │ (from      │ (Phase 35B)│ (Phase 35B)│ (Phase 33)  │  │
│  │  hackathon)│            │            │             │  │
│  └────────────┴────────────┴────────────┴─────────────┘  │
└──────────────────────────────────────────────────────────┘
```

Every box above the `NetworkAdapter` interface line is domain-neutral and belongs in `session-protocol`. Every box below it is substrate-specific and belongs in its own adapter package.

### The StateMachine Plug-in

The one domain-specific piece session-protocol depends on is a `StateMachine` interface:

```typescript
export interface StateMachine<Event, State, Context = unknown> {
  readonly initialState: State;
  readonly terminalStates: ReadonlySet<State>;
  transition(current: State, event: Event, ctx: Context): {
    next: State;
    emit?: Event[];             // downstream events to broadcast
    meterTick?: MeteringTick;   // optional billing event
  };
  validate(current: State, event: Event, ctx: Context): boolean;
}
```

Poker-agent provides `PokerStateMachine`. Call-protocol (Phase 35B) provides `CallStateMachine`. Neither cares what the other looks like.

### Topic-to-Group Derivation Hook

The hackathon `DockerMulticastAdapter` joins one IPv6 multicast group (`ff02::1`) and demultiplexes all topics in software. Phase 34 wants each type hash to have its own group. Rather than choose one today, this phase introduces a `topicToGroup` hook with the hackathon behaviour as default:

```typescript
export type TopicToGroup = (topic: string) => string;

// Default: everything on one group (current hackathon behaviour)
export const defaultTopicToGroup: TopicToGroup = () => 'ff02::1';

// Phase 34 implementation (deferred):
// import { deriveMulticastGroup } from '@semantos/protocol-types/multicast';
// export const typeHashTopicToGroup: TopicToGroup = (topic) => {
//   const [what, how, inst] = topic.split(':');
//   return deriveMulticastGroup({ what, how, inst });
// };
```

This keeps Phase 35A shippable today and makes Phase 34's promotion a one-line config swap when the SRv6 fabric lands.

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `TYPES:NETWORK` | `packages/protocol-types/src/network.ts` | NetworkAdapter interface |
| `TYPES:CELL` | `packages/protocol-types/src/index.ts` | PublishableObject, NetworkEvent |
| `BCA:ZIG` | `packages/cell-engine/src/bca.zig` | Real BCA derivation |
| `POKER:AGENT` | `packages/poker-agent/src/` | Incumbent domain-neutral skeleton (to be extracted) |
| `HACK:MC` | `todriguez/hackathon-submission:src/protocol/adapters/docker-multicast-adapter.ts` | Multicast adapter to import |
| `HACK:UDP` | `todriguez/hackathon-submission:src/protocol/adapters/udp-transport.ts` | UDP transport to import |
| `METERING` | `packages/metering/` | Channel FSM for optional metering hook |
| `SETTLE` | `packages/settlement/` | Txid provider source |
| `PHASE:34` | `docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md` | Future multicast group derivation |

---

## Deliverables

### D35A.1 — New Package `packages/session-protocol/`

Establish the package with standard `package.json`, `tsconfig.json`, `src/`, `__tests__/`. Workspace root `pnpm-workspace.yaml` updated.

Public entry surface (`src/index.ts`) exports:

```typescript
export type {
  StateMachine,
  SessionDescriptor,
  SessionHandle,
  AgentDescriptor,
  FormationPolicy,
  MeteringHook,
  TopicToGroup,
  TxidProvider,
  Signer,
  Verifier,
  BCAProvider,
} from './types';

export { SessionRuntime } from './runtime';
export { SessionFormation } from './formation';
export { AgentDiscovery } from './discovery';
export { BroadcastEngine } from './broadcast';
export { defaultTopicToGroup } from './topics';
export { BsvSdkSigner, BsvSdkVerifier, StubSigner } from './signer';
export { PlexusCertBCAProvider, DeterministicBCAProvider } from './adapters/bca-provider';
```

### D35A.2 — Domain-Neutral Skeleton Extraction

Move and rename the following files out of `packages/poker-agent/`:

| From | To | Rename changes |
|------|----|----------------|
| `agent-discovery.ts` | `session-protocol/src/discovery.ts` | Remove poker-specific stake/persona negotiation; add `DomainCapability` descriptor |
| `agent-runtime.ts` | `session-protocol/src/runtime.ts` | Accept `StateMachine` as constructor parameter; remove poker-specific game-loop |
| `p2p-agent-runner.ts` | `session-protocol/src/p2p-runner.ts` | Remove `poker*` imports |
| `direct-broadcast-engine.ts` | `session-protocol/src/broadcast.ts` | No changes needed |
| `table-formation.ts` | `session-protocol/src/formation.ts` | Rename `TableProposal` → `SessionProposal`; parameterise min/max party size |
| `payment-channel.ts` | `session-protocol/src/metering.ts` | Keep as optional hook; wrap in `MeteringHook` interface |

Poker-agent imports the new names. Game-loop, state machines, and message-transport that are poker-specific stay in `poker-agent`.

### D35A.3 — Multicast Adapter Import and Generalisation

**New file**: `packages/session-protocol/src/adapters/multicast-adapter.ts`

Import from `todriguez/hackathon-submission:src/protocol/adapters/docker-multicast-adapter.ts`. Rename class to `MulticastAdapter`. Changes required:

```typescript
export interface MulticastAdapterConfig {
  identity: BCAProvider;          // was: botIndex: number
  transport: UdpTransport;
  topicToGroup?: TopicToGroup;    // new — defaults to defaultTopicToGroup
  txidProvider: TxidProvider;     // new — was: internal fake counter
  heartbeatSink?: HeartbeatSink;  // new — lifts /tmp/semantos-heartbeat file write out
  port?: number;
  primaryGroup?: string;          // default ff02::1 (used when topicToGroup is default)
  maxPayload?: number;            // default 65507-HEADER_SIZE (Docker); override for 6LoWPAN
  heartbeatIntervalMs?: number;
  staleTimeoutMs?: number;
}

export interface BCAProvider extends Signer {
  // BCAProvider *is a* Signer with a BCA-derived identity.
  // Signing primitive lives in the Signer seam (D35A.5); BCAProvider only
  // contributes the BCA derivation from a Plexus cert on top of it.
  deriveBCA(): Promise<string>;           // hits cell-engine bca.zig via host functions
  // identity() and sign() inherited from Signer — delegate to the underlying Signer
}

export interface TxidProvider {
  mint(cellBytes: Uint8Array): Promise<string>;  // settlement-backed in production, counter in tests
}

export interface HeartbeatSink {
  onHeartbeatSent?(timestamp: number): void;  // Docker health-check writes /tmp/semantos-heartbeat here
  onPeerHeartbeatReceived?(peer: PeerInfo): void;
}
```

Removals:
- `deriveBCA(botIndex)` stub function deleted — callers inject `BCAProvider`
- `generateTxid()` counter removed — callers inject `TxidProvider`
- `/tmp/semantos-heartbeat` file write removed — callers attach `HeartbeatSink` if desired
- `DockerMulticastConfig.botIndex` removed — replaced by `identity`
- Fake Plexus cert fields in `resolveBCA` response (`nodeCert: 'bot-N'`, `identity: 'stub'`, `anchor: 'stub'`) replaced with real values from an injected `NodeMetadataProvider`

Additions:
- `topicToGroup` hook applied at `publish()` and `subscribe()` time; when non-default, transport joins/leaves groups dynamically via `UdpTransport.addMembership(group)` / `dropMembership(group)`
- `maxPayload` enforced; oversized publish rejects with `PayloadTooLargeError` rather than silently dropping
- Duplicate-path detection: `handleCell` now keys `this.objects` on `(semanticPath, ownerCert)` and fires a `duplicate_path` observer event when two owners publish to the same path

### D35A.4 — UDP Transport Import

**New file**: `packages/session-protocol/src/adapters/udp-transport.ts`

Import from `todriguez/hackathon-submission:src/protocol/adapters/udp-transport.ts`. Extensions:

```typescript
export interface UdpTransport {
  bind(port: number, group: string): Promise<void>;
  send(bytes: Uint8Array, port: number, address: string): Promise<void>;
  onMessage(cb: (msg: Uint8Array, rinfo: RemoteInfo) => void): void;
  close(): Promise<void>;

  // New for multi-group support (Phase 34 readiness)
  addMembership(group: string): Promise<void>;
  dropMembership(group: string): Promise<void>;
  memberships(): ReadonlySet<string>;
}

export class LoopbackUdpTransport implements UdpTransport { /* in-memory, for tests */ }
export class NodeUdpTransport implements UdpTransport { /* wraps node:dgram */ }
```

`NodeUdpTransport.addMembership` calls `socket.addMembership(group)` (which is the standard `node:dgram` API); `LoopbackUdpTransport` maintains a `Map<group, Set<cb>>`.

### D35A.5 — Signer Seam and BCA Provider Wiring

The signing primitive is exposed behind a single `Signer` / `Verifier` interface so every downstream consumer (`BCAProvider`, `MulticastAdapter` envelope auth, 35B's `WsNodeAdapter` envelopes, session join tokens, TLS-BCA binding proofs, metering channel commitments) calls through one choke point. The real Plexus SDK is a month or two out; defining the seam now means the SDK lands behind an existing interface rather than displacing a bunch of direct `@bsv/sdk` call sites.

**New file**: `packages/session-protocol/src/signer.ts`

```typescript
export interface Identity {
  bca: string;                // IPv6 string, derived from pubkey
  pubkey: Uint8Array;         // 33-byte compressed secp256k1
  certId?: string;            // Plexus cert SHA256 when available
}

export interface Signer {
  identity(): Promise<Identity>;
  sign(bytes: Uint8Array): Promise<Uint8Array>;      // detached signature
}

export interface Verifier {
  verify(pubkey: Uint8Array, bytes: Uint8Array, sig: Uint8Array): Promise<boolean>;
}

/**
 * Production signer wrapping @bsv/sdk. When the real Plexus SDK lands,
 * a `PlexusSigner` with the same shape slots in alongside this — no
 * call-site churn downstream.
 */
export class BsvSdkSigner implements Signer {
  constructor(
    private readonly privKey: PrivateKey,   // from @bsv/sdk
    private readonly bcaDeriver: (pk: Uint8Array) => Promise<string>,
  ) {}
  async identity(): Promise<Identity> {
    const pubkey = this.privKey.toPublicKey().toCompressed();
    const bca = await this.bcaDeriver(pubkey);
    return { bca, pubkey };
  }
  async sign(bytes: Uint8Array): Promise<Uint8Array> {
    // @bsv/sdk ECDSA over sha256(bytes); returns compact 64-byte sig
  }
}

export class BsvSdkVerifier implements Verifier {
  async verify(pubkey: Uint8Array, bytes: Uint8Array, sig: Uint8Array): Promise<boolean> {
    // @bsv/sdk ECDSA verify
  }
}

export class StubSigner implements Signer {
  // Test-only — deterministic identity + stable sig for golden-vector tests.
  // Exists because the hackathon docker-swarm tests depend on deterministic bot identities.
}
```

**New file**: `packages/session-protocol/src/adapters/bca-provider.ts`

```typescript
/**
 * BCAProvider composes a Signer with Plexus cert metadata and BCA derivation.
 * It delegates all signing to the underlying Signer — never talks to @bsv/sdk directly.
 */
export class PlexusCertBCAProvider implements BCAProvider {
  constructor(
    private readonly cert: PlexusCert,
    private readonly signer: Signer,
    private readonly wasm: CellEngineInstance,
  ) {}

  async deriveBCA(): Promise<string> {
    // Calls wasm.exports.bca_derive() from packages/cell-engine on the cert's pubkey.
    // Returns IPv6 string per nChain BCA algorithm.
  }

  // Signer delegation
  identity(): Promise<Identity> { return this.signer.identity(); }
  sign(bytes: Uint8Array): Promise<Uint8Array> { return this.signer.sign(bytes); }
}

export class DeterministicBCAProvider implements BCAProvider {
  // Test-only — reproduces hackathon 2602:f9f8::<index> stub.
  // Internally uses a StubSigner; exists because existing docker-swarm hackathon
  // tests depend on it.
}
```

**Future (not in 35A scope):** `PlexusSigner` lands in whichever phase wires the real Dusk Inc SDK. It implements the same `Signer` interface. Every consumer added between now and then inherits it for free.

### D35A.6 — Poker-Agent Refactor (First Consumer)

`packages/poker-agent/` becomes a thin consumer of session-protocol. Changes:

- Remove moved files (listed in D35A.2).
- Update imports in remaining poker-specific files (`poker-state-machine.ts`, `direct-poker-state-machine.ts`, `poker-message-transport.ts`, `game-loop.ts`, `game-state-db.ts`) to reference `@semantos/session-protocol`.
- `src/index.ts` exports `PokerSessionFactory` that composes `SessionRuntime` + `PokerStateMachine` + poker-specific formation policy.
- Existing poker tests continue to pass unchanged (behavioural equivalence gate).

### D35A.7 — Gate Tests `packages/__tests__/phase35a-gate.test.ts`

Test matrix:

| ID | Scenario | Assertion |
|----|----------|-----------|
| G35A.1 | Two `SessionRuntime`s on LoopbackUdpTransport form a session | Both observe same terminal state after scripted events |
| G35A.2 | `MulticastAdapter.publish` with default `topicToGroup` | All subscribers receive; topic filtering is in-memory |
| G35A.3 | `MulticastAdapter.publish` with Phase-34-style `topicToGroup` | Non-subscribing nodes do not observe (transport-level filter via `addMembership`) |
| G35A.4 | Poker integration test (unchanged) | All pre-35A poker tests pass against refactored session-protocol |
| G35A.5 | `PlexusCertBCAProvider.deriveBCA()` | Matches `bca_conformance.zig` test vectors |
| G35A.6 | `TxidProvider` injection | `MulticastAdapter` never mints its own txid; crash-fails if provider returns empty |
| G35A.7 | Duplicate-path detection | Two owners publishing same `semanticPath` triggers `duplicate_path` event |
| G35A.8 | Multi-group membership | `UdpTransport.addMembership` / `dropMembership` correctly subscribes/unsubscribes |
| G35A.9 | State-machine polymorphism | Stub `MinimalStateMachine<"ping","pong">` drives a session end-to-end |
| G35A.10 | Metering hook optional | Session-protocol instantiates without a `MeteringHook`; with one, tick events fire per state transition |
| G35A.11 | Signer composability | `BsvSdkSigner` + `BsvSdkVerifier` round-trip sign/verify on 1KB payload; `StubSigner` passes same contract; `PlexusCertBCAProvider.sign()` bytes-identical to its injected `Signer.sign()` (proves delegation, no duplicate paths) |
| G35A.12 | No direct `@bsv/sdk` imports outside `signer.ts` | Static check: the only file under `session-protocol/src/` that imports `@bsv/sdk` is `signer.ts` (enforces single choke point) |

### D35A.8 — Documentation

- New: `packages/session-protocol/README.md` with the six-piece diagram, `StateMachine` interface, and two worked examples (poker-lite, ping-pong).
- Update: root `README.md` — add `session-protocol` to the Runtime table with status `built`, importers `2` (poker-agent + planned call-protocol).
- Update: `docs/RESTRUCTURING-PLAN.md` — session-protocol slots into `runtime/` in Phase 3 of the restructure.

---

## Definition of Done

1. `packages/session-protocol/` exists with all exports listed in D35A.1.
2. Poker-agent compiles and passes all pre-existing tests without poker-specific behaviour change.
3. `packages/__tests__/phase35a-gate.test.ts` passes 12/12.
4. No file under `session-protocol/src/` references the string `poker`, `table`, `stake`, `persona`, `blind`, or `bot`.
5. `MulticastAdapter` runs against a real `dgram` socket on a local Docker bridge and two instances discover each other via heartbeat within 6 seconds.
6. `PlexusCertBCAProvider` derives IPv6 addresses matching `bca_conformance.zig` golden vectors.
7. README and RESTRUCTURING-PLAN updates merged.
8. `bun run check` passes repo-wide.

---

## Out of Scope (Deferred to 35B and Beyond)

- Any new state machine other than poker's existing one (call-protocol → 35B).
- Any `NetworkAdapter` implementation other than `MulticastAdapter` (WebSocket → 35B, WebRTC → 35B, SixLowPan → Phase 33B).
- Peer-locator service (35B).
- Public-internet deployment (35B).
- Phase 34's type-hash-to-group derivation (Phase 34 proper; 35A ships the hook, not the scheme).

---

## Follow-on Phases

- **Phase 35B — Node as Service**: the consumer phase that turns session-protocol into a user-facing product (call-protocol, ws-node-adapter, peer-locator).
- **Phase 34A–D**: plug `typeHashTopicToGroup` into `MulticastAdapter` once SRv6 fabric is ready.
- **Phase 33B**: `SixLowPanAdapter` implements `NetworkAdapter` + `UdpTransport`; session-protocol works over radio unchanged.
- **Phase 36 (speculative)**: additional state machines — `CdmLifecycleStateMachine`, `AuctionStateMachine`, `OracleStateMachine` — each a thin consumer of session-protocol.
