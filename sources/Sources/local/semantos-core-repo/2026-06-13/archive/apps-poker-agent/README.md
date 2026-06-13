---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.689355+00:00
---

# @semantos/poker-agent

Skeleton consumer demonstrating `@semantos/session-protocol` +
`@semantos/chain-broadcast` integration. Claude-powered poker agents with
on-chain state anchoring.

## Status

This package is a **skeleton / reference consumer**, not the production
poker runtime. The production-grade version lives in the standalone
[`todriguez/hackathon-submission`](https://github.com/todriguez/hackathon-submission)
repo — that's where the MAPI broadcast pipeline, BEEF dedup, and fleet
funding coordination actually run at load.

Post-Phase-35A, this in-repo version:

- **imports** `MulticastAdapter` from `@semantos/session-protocol` (was
  `DockerMulticastAdapter` from `@semantos/protocol-types`)
- **wires** `DeterministicBCAProvider` for identity and a counter
  `TxidProvider` for tx minting (see `runtime/node/src/entrypoint.docker-swarm.ts`)
- **can adopt** `ChainBroadcaster` from `@semantos/chain-broadcast` to
  replace its in-tree `DirectBroadcastEngine` — left for a follow-up sprint;
  the current in-tree engine still compiles and is kept for continuity.

## Key migrations (Phase 35A)

| Before                               | After                                                          |
|--------------------------------------|----------------------------------------------------------------|
| `DockerMulticastAdapter`             | `MulticastAdapter` from `@semantos/session-protocol`           |
| `deriveBCA(botIndex)` (stub)         | `DeterministicBCAProvider(botIndex).deriveBCA()`               |
| Internal txid counter in adapter     | Injected `TxidProvider` (counter stub in the docker entrypoint)|
| `/tmp/semantos-heartbeat` file write | Optional `HeartbeatSink` (not wired by default)                 |

The test-time behaviour-parity gate lives at
`tests/gates/phase35a-gate.test.ts` G35A.4 — it asserts the barrel
re-exports haven't regressed and `TableFormationService` accepts the new
`MulticastAdapter` ctor shape.

## When to use which

- **Learning the protocol, wiring new extensions** → this package
- **Running the 24h hackathon throughput target / real BSV mainnet** →
  the standalone `hackathon-submission` repo
- **Neither — I just want a session skeleton for a new vertical** →
  depend on `@semantos/session-protocol` directly and plug in your own
  `StateMachine<Event, State>` + optional `MeteringHook`. See
  [runtime/session-protocol/src/runtime.ts](../../runtime/session-protocol/src/runtime.ts)
  and its `SessionRuntime` class.
