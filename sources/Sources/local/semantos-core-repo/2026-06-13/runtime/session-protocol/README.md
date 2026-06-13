---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.023241+00:00
---

# @semantos/session-protocol

Domain-neutral multi-party session skeleton. Phase 35A deliverable.

Any vertical that needs a state-machine-driven multi-party session — poker,
voice/video calls, live streams, conference rooms, CDM lifecycle events,
SCADA telemetry, auctions, oracles — is the same six boxes plus a
consumer-supplied `StateMachine`. This package ships those six boxes.

```
┌──────────────────────────────────────────────────────────┐
│  Session Consumer (poker, call, cdm, auction, …)         │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Domain StateMachine<Event, State>                  │  │
│  └────────────────────────────────────────────────────┘  │
└───────────────────────▲──────────────────────────────────┘
                        │
┌───────────────────────┴──────────────────────────────────┐
│  @semantos/session-protocol                              │
│  ┌─────────────┬────────────┬─────────────┬───────────┐  │
│  │ SessionRuntime (event loop + state + metering)      │  │
│  ├─────────────┼────────────┼─────────────┼───────────┤  │
│  │ Signer seam │ BCAProvider│ MulticastAd.│ broadcast │  │
│  │ (signer.ts) │ (Plexus +  │ (injected   │ helpers   │  │
│  │             │  Determini.)│ seams)     │           │  │
│  └─────────────┴────────────┴─────────────┴───────────┘  │
└───────────────────────▲──────────────────────────────────┘
                        │ NetworkAdapter interface (core/protocol-types)
┌───────────────────────┴──────────────────────────────────┐
│  Adapter implementations (substrate-specific)            │
│  MulticastAdapter (here) · Loopback · WSS (35B) · 6LoW   │
└──────────────────────────────────────────────────────────┘
```

## Five-minute worked example

```ts
import {
  SessionRuntime,
  MulticastAdapter,
  DeterministicBCAProvider,
  type StateMachine,
  type TxidProvider,
} from "@semantos/session-protocol";
import { LoopbackUdpTransport } from "@semantos/protocol-types/adapters/udp-transport";

// 1. Define a state machine — the ONLY domain-specific piece.
type Event = { type: "ping" } | { type: "pong" };
type State = "idle" | "ponging" | "done";

const stateMachine: StateMachine<Event, State> = {
  initialState: "idle",
  terminalStates: new Set(["done"]),
  validate: () => true,
  transition(current, event) {
    if (current === "idle" && event.type === "ping") {
      return { next: "ponging", emit: [{ type: "pong" }] };
    }
    if (current === "ponging" && event.type === "pong") {
      return { next: "done" };
    }
    return { next: current };
  },
};

// 2. Wire up identity, transport, txid provider.
const identity = new DeterministicBCAProvider(1);
const transport = new LoopbackUdpTransport(await identity.deriveBCA());
const txidProvider: TxidProvider = {
  async mint() { return "tx" + Date.now().toString(16).padStart(62, "0"); },
};

// 3. Build the adapter — domain-neutral multicast with injected seams.
const adapter = new MulticastAdapter({ identity, transport, txidProvider });
await adapter.start();

// 4. Run a session.
const runtime = new SessionRuntime({
  descriptor: { id: "s1", minParty: 2, maxParty: 2, topic: "tm_pingpong" },
  stateMachine,
  adapter,
});
await runtime.start();
await runtime.submit({ type: "ping" });
// runtime.state === "done"
```

Multiply by `N` runtimes over the same `MulticastAdapter` group and every
participant converges on the terminal state. Swap `DeterministicBCAProvider`
for `PlexusCertBCAProvider` in production.

## Key shapes

| Export | What it does |
|---|---|
| `SessionRuntime<Event, State>` | Event loop driving a consumer's `StateMachine` over a `NetworkAdapter`. Handles envelope wrapping, echo filtering, emit fan-out, metering tick dispatch. |
| `MulticastAdapter` | IPv6 UDP multicast `NetworkAdapter`. Promoted from the hackathon `DockerMulticastAdapter` with injected seams (`BCAProvider`, `TxidProvider`, `HeartbeatSink`, `TopicToGroup`). |
| `Signer` / `Verifier` (`BsvSdkSigner`, `StubSigner`, `BsvSdkVerifier`) | DER-ECDSA over secp256k1. The ONLY file in the package that imports `@bsv/sdk` — every other caller uses the interface. |
| `BCAProvider` (`PlexusCertBCAProvider`, `DeterministicBCAProvider`) | IPv6 address from pubkey. `PlexusCertBCAProvider`'s algorithm is bit-identical to `core/cell-engine/src/bca.zig`, cross-verified against its golden vectors. |
| `defaultTopicToGroup`, `TopicToGroup` | Hook for Phase-34 type-hash → multicast-group routing. Default: every topic joins `ff02::1` (hackathon behaviour). |
| `MeteringHook` / `MeteringTick` | Optional billing seam. Runtime routes state-machine `meterTick` through this hook; skip it for non-commercial sessions. |
| `broadcastToSession`, `subscribeToSession` | Thin helpers for custom side-channel messages on a session topic. |

## What's NOT here

- **Chain anchoring.** A `StateMachine` might decide to commit state on-chain
  via BSV; that pipeline lives in
  [`@semantos/chain-broadcast`](../../extensions/chain-broadcast/). Session-
  protocol doesn't assume you want to anchor at all.
- **Domain orchestrators.** Poker's agent-runtime, p2p-runner, formation,
  and payment-channel stay with the consumer. The `SessionRuntime` +
  `StateMachine` abstraction is enough — formation and discovery patterns
  get promoted only when a second consumer forces the right shape.

## Gate tests

`tests/gates/phase35a-gate.test.ts` — 27 tests covering G35A.1, 2, 3, 4,
5, 6, 7, 8, 9, 10, 11, 12 (the full D35A.7 matrix).

## Import-boundary posture

This package lives in `runtime/` — it may import from `core/` and other
`runtime/` packages. The import-boundary gate (`tests/gates/import-
boundaries.test.ts`) auto-discovers it; no allowlist entry required.
