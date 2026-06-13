---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.312455+00:00
---

# world-host

OTP-hosted world layer for Semantos. Implements the Elixir side of
`docs/prd/WORLD-PROTOCOL.md` — regions as supervisors, entities as
GenServers, 20 Hz tick scheduler, Phoenix Channels transport.

This is the first real implementation on top of the feasibility tests in
`apps/world-feasibility/`. Scope is deliberately narrow: a single
hardcoded region with three LINEAR cubes, ticking at 20 Hz, broadcasting
deltas over a WebSocket channel. A browser smoke-test page lives in
`priv/static/index.html`.

## What works today

- Region supervisor with per-entity GenServers.
- 20 Hz tick scheduler emitting `tick_delta` frames with a region-level
  hash chain (`prev_state_hash` → `state_hash`).
- Client-initiated `entity_action` (move / dup / drop) routed through the
  entity mailbox; linearity rules enforced server-side before dispatch.
- Phoenix Channel on `world:region:<id>` with snapshot-on-join.
- REST health + snapshot endpoints at `/api/health` and
  `/api/regions/:id/snapshot`.

## What's stubbed

- **Cell engine dispatch.** `WorldHost.CellEngine` can load the Wasmex
  module but `OP_CALLHOST` dispatch returns 0 for allowlisted names and
  0xFFFFFFFF for everything else. Actions mutate Elixir-side state
  directly (fast, deterministic) and the authoritative WASM path will be
  wired once `kernel_snapshot_state` lands.
- **Signature verification.** `SignedBundle` shapes are used on the wire
  but signatures aren't checked yet. The `UserSocket.connect/3` hook is
  where real BCA-derived authentication will attach.
- **CBOR encoding.** JSON for now; swap at the encoder layer later.
- **Multi-region / federation.** Only one region boots today. The
  plumbing (RegionDynSupervisor, Registry lookup) supports many.
- **Persistence.** Everything is in-memory. Postgres event log + snapshot
  table is the next story once `kernel_snapshot_state` exists.

## Running

Prereqs: Elixir 1.15+ on OTP 25–27 (see `.tool-versions`). Hex must
match your OTP:

    mix local.hex --force

Then:

    cd apps/world-host
    mix deps.get
    mix test            # runs region/entity/linearity unit tests
    mix phx.server      # starts the server on http://localhost:4000

The server logs should show, in order:

    [info] tick scheduler started: 20 Hz (50 ms period)
    [info] world_host started (protocol v1)
    [info] demo region region-0001 up
    [info] entity spawned: cube-1
    [info] entity spawned: cube-2
    [info] entity spawned: cube-3

Open http://localhost:4000 — you should see three cubes appear, the
`tick_seq` counter advancing, and both buttons working:

- **move cube-1 +1x** — cube-1's position increments; a `tick_delta` with
  the updated position arrives on the next tick.
- **try dup cube-1 (should fail)** — logs `action_rejected` with
  `reason: "linearity_violation"`. cube-1 is LINEAR, so DUP is refused
  server-side.

## Smoke-test endpoints

    curl http://localhost:4000/api/health
    curl http://localhost:4000/api/regions/region-0001/snapshot

The snapshot JSON matches what a client sees on channel join.

## Architecture quick-reference

    WorldHost.Application
     ├─ Phoenix.PubSub                       (world:region:<id> topics)
     ├─ WorldHost.RegionSupervisor
     │   ├─ WorldHost.RegionRegistry         ({:via, Registry, ...})
     │   ├─ WorldHost.EntityRegistry
     │   ├─ WorldHost.EntitySupervisor       (DynamicSupervisor → entities)
     │   ├─ WorldHost.RegionDynSupervisor    (DynamicSupervisor → regions)
     │   └─ WorldHost.Tick                   (20 Hz → advance_tick/1)
     ├─ WorldHostWeb.Endpoint                (HTTP + WebSocket)
     │   └─ WorldHostWeb.WorldChannel        ("world:region:*")
     └─ Bootstrap task                       (seeds demo region)

## Next iteration checklist

1. **Extract the cell engine embedder** into a shared package
   (`packages/cell-engine-elixir` or similar) so `world-feasibility`
   and `world-host` stop duplicating it.
2. **Wire a real host-call** (`move`, or a simple `increment_counter`)
   through the Wasmex instance and confirm server-side authoritative
   state matches client-side prediction.
3. **Client prediction.** Update `apps/demo-wasm-threejs` (or a new
   `apps/world-client`) to render the cubes in 3D, predict locally,
   reconcile against `tick_delta`.
4. **Entity snapshot/restore** in Zig (the Test 2 deliverable from the
   feasibility pass). Unblocks region migration and persistence.
5. **Second region + Horde.** Prove federation works at the cheapest
   possible scope — entity transfer between two local regions.

## References

- `docs/prd/WORLD-PROTOCOL.md` — protocol spec this app implements.
- `apps/world-feasibility/` — feasibility tests + Python sanity check.
- `core/cell-engine/` — Zig WASM kernel embedded by `WorldHost.CellEngine`.
