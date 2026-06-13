---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.387030+00:00
---

# `@semantos/cell-relay`

Wire-protocol types + client SDK for the **cell-relay** runtime — a
per-room append-only signed-cell log with WebSocket broadcast.

This is the substrate's collaborative-versioning primitive at its
simplest shape: one room per logical cell-stream, every commit is a
signed cell, the JSONL log is authoritative. Every consumer that
wants to subscribe to a cell-stream room and commit cells to it
talks through this package.

## Two interchangeable runtimes

The cell-relay protocol has two implementations in the repo. Same wire
shape, same JSONL format on disk; pick whichever is up.

| Runtime | Where | When to use |
| --- | --- | --- |
| Elixir / OTP / BEAM (production) | [`apps/cell-relay-beam/`](../../apps/cell-relay-beam/) | Sovereign-node deployment, supervised process tree, durability-on-crash |
| Bun (dev) | [`apps/demo-collab-versioning/`](../../apps/demo-collab-versioning/) | Local dev, single-machine, fast iteration |

The wire protocol below is the single source of truth — defined here,
implemented there.

## Cell-relay vs. World Host (clearing up the confusion)

**This package is not the same thing as `apps/world-host/`.**

`apps/world-host/` is a different abstraction in the codebase:
tick-driven entity simulator with regions, per-entity GenServers,
20 Hz tick scheduler, Phoenix Channels. It exists to host worlds in
the textbook ch.16 sense — game/MUD/metaverse style domains where
state advances continuously and entities have their own supervisors.

The cell-relay (this package) is much simpler: append-only per-room
cell logs over plain WebSocket. Not tick-driven, no entity model,
no region supervision. Used by the jam-room client and by
[`tools/release/`](../../tools/release/) for the repo-wide release
pipeline.

When the two abstractions are unified later, the World Host's tick +
entity model and the cell-relay's append-only commit log will probably
become two faces of one runtime. Until then they're separate things
with separate names.

## Wire protocol

```
client → server  { type: 'commit', cell }
client → server  { type: 'live', payload }
client → server  { type: 'reset' }

server → client  { type: 'snapshot', cells, presence, your: { id, identity, room } }
server → client  { type: 'commit', cell, from: { identity } }
server → client  { type: 'live', payload, from: { identity } }
server → client  { type: 'presence', identities, joined?, left? }
server → client  { type: 'reset' }
```

Connection URL: `ws://host:5178/?room=<id>&as=<identity>`

## What's in here

### `types.ts` — the wire shape

`SerializedCell` plus the typed `ClientMsg` / `ServerMsg`
discriminated unions. Single source of truth for the protocol.

### `client.ts` — `RelayClient`

```ts
import { RelayClient } from '@semantos/cell-relay';

const c = new RelayClient({
  url: 'ws://localhost:5178',
  room: 'jam-friday-night',
  identity: 'todd',
});

const snapshot = await c.connect();
console.log(`got ${snapshot.cells.length} cells, ${snapshot.presence.length} peers`);

c.on('commit', ({ cell, from }) => {
  console.log(`peer ${from.identity} committed ${cell.stateHashHex.slice(0, 12)}`);
});

c.commit(myCell);
c.live({ stepFire: 14 });
c.disconnect();
```

### `cell.ts` — cell construction primitives

`buildCell` + `buildChildCell` produce `SerializedCell` objects with
correctly-computed `stateHashHex`. The hash rule is the same one both
runtime implementations use — sha256 of canonical-JSON-encoded cell
core (id and stateHashHex omitted from the hashing input).

```ts
import { buildChildCell } from '@semantos/cell-relay';

const cell = buildChildCell(parent, {
  patch: { op: 'release.kernel.publish', payload: manifest },
  hat: 'maintainer@semantos',
});
// cell.stateHashHex is the canonical pin
```

### `jsonl.ts` — direct file access

Read/append room state from disk without going through a relay
process. The runtime treats the JSONL as authoritative — appending
here is durable.

```ts
import { loadAllCells, walkChain, indexByHash } from '@semantos/cell-relay';

const cells = loadAllCells('apps/demo-collab-versioning/data/release.kernel.pask.jsonl');
const byHash = indexByHash(cells);
const chain = walkChain(byHash, '<pin>');  // root → head
```

## Where this is used today

- [`tools/release/`](../../tools/release/) — the repo-wide release
  pipeline builds release-cells via `buildChildCell` and submits them
  via `appendCell(jsonlPath, cell)`. Consumers fetch via `walkChain`.
- The Elixir [`apps/cell-relay-beam/`](../../apps/cell-relay-beam/)
  implements the same wire protocol on the server side.
- [`apps/jam-room/`](../../apps/jam-room/) is the original consumer
  (the jam-room browser client — wire-protocol parity is what allowed
  the BEAM relay to be a drop-in for the Bun dev one).

Future consumers (helm panels, release-fetcher CLIs, MUD-client cell
streams, anything else using append-only collab versioning) all use
this same surface. The wire protocol is the contract; this package is
the only place it should be defined.

## NOT in here

- The runtime itself (per-room GenServer / connection state). That's
  [`apps/cell-relay-beam/`](../../apps/cell-relay-beam/) (Elixir) or
  [`apps/demo-collab-versioning/`](../../apps/demo-collab-versioning/) (Bun).
- BRC-52 cert binding + BRC-100 envelope signing on commits. Stubbed
  (`hat:` is a plain string today). Wallet-client + verifier-sidecar
  wiring is a follow-up; the cell shape already carries the field.
- WorldTick / 20 Hz heartbeat / entity simulation. Those are
  `apps/world-host/`'s job, with a separate protocol.
