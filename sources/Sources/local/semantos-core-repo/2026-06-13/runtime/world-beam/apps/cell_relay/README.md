---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.313247+00:00
---

# cell-relay-beam

Elixir/OTP/BEAM implementation of the cell-relay protocol
(see [`@semantos/cell-relay`](../../packages/cell-relay/)).

A cell-relay is a per-room append-only signed-cell log with WebSocket
broadcast. Originally written as `jam-beam` for the
[`jam-room`](../jam-room/) sovereign-node POC; renamed to reflect that
the role is generic — every room in the cell DAG (jam sessions,
`release.kernel.*` rooms, future helm sessions, MUD chat streams,
anything else using append-only collaborative versioning) is just
another instance of this runtime.

Drop-in replacement for the Bun dev relay
(`apps/demo-collab-versioning/server.ts`) — same wire protocol, same
JSONL persistence format on disk, same port (`5178`).

## Topology

```
CellRelay.Application                  (top-level Application)
├── CellRelay.Registry                 (room_id → pid)
├── CellRelay.RoomSupervisor           (DynamicSupervisor of CellRelay.Room)
│   └── CellRelay.Room (× N)           (one GenServer per room)
└── Plug.Cowboy listener :5178
    ├── CellRelay.Endpoint             (HTTP /health /rooms + CORS)
    └── CellRelay.WSHandler            (cowboy_websocket per client)
```

Each room is a leaf GenServer in the supervision tree. Subscribers
are monitored so a crashed WS pid is GC'd from the room's `:subs` set
automatically. If a room crashes, the supervisor restarts it and the
JSONL log is replayed — no in-memory state is lost.

## Run

```sh
mix deps.get
mix run --no-halt
```

The browser jam-room (`apps/jam-room`, served on `:5180`) connects
unchanged. To migrate from the Bun dev relay, just stop the Bun
process and start this — the JSONL files in `data/` are
byte-compatible.

## Wire protocol

Same as the Bun dev variant. Defined in [`@semantos/cell-relay`](../../packages/cell-relay/):

- client → server: `{type: 'commit', cell}` / `{type: 'live', payload}` / `{type: 'reset'}`
- server → client (on connect): `{type: 'snapshot', cells, presence, your: {id, identity, room}}`
- server → other clients: `{type: 'commit', cell, from: {identity}}` / `{type: 'live', payload, from: {identity}}`
- server → all-in-room: `{type: 'presence', identities, joined?, left?}` / `{type: 'reset'}`

The relay tags every persisted cell with `author` so consumers can
bucket commits by authoring identity.

## HTTP

- `GET /health` — full room snapshot (`{rooms: [{id, cells, clients}]}`)
- `GET /rooms` — discovery list of rooms with at least one subscriber
- `OPTIONS *` — CORS preflight (`*` origin so the browser on `:5180`
  can poll cross-port without a proxy)

## Cell-relay vs. World Host

Don't confuse this with [`apps/world-host/`](../world-host/) — the
larger-scope tick-driven entity simulator (regions, per-entity
GenServers, 20 Hz scheduler, Phoenix Channels). The two abstractions
are separate today; when they're unified, the World Host's tick +
entity model and the cell-relay's append-only commit log will
probably become two faces of one runtime.
