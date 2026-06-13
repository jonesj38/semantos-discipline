---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.690283+00:00
---

# world-client

Three.js client for the Semantos world-host. Renders authoritative entities
from `world:region:<id>` as cubes in 3D, runs local prediction, reconciles
against `tick_delta` frames, and visualises substructural-type violations
(LINEAR cube refusing DUP → shatter).

Companion to `apps/world-host`. The two together are the first real
demonstration of the protocol in `docs/prd/WORLD-PROTOCOL.md`.

## Run both ends

Terminal 1 — the Elixir server:

    cd apps/world-host
    mix phx.server

Terminal 2 — the three.js client (Vite dev server with WebSocket proxy):

    cd apps/world-client
    pnpm install            # or npm install / yarn install
    pnpm dev                # starts on http://localhost:5175

Open `http://localhost:5175` in two browser windows side by side. Both
subscribe to the same region; both see the same three LINEAR cubes.

## What each key does

- **Click** a cube → select it (blue glow).
- **W / A / S / D** or arrow keys → move the selected cube by 1 metre.
  Client predicts the move locally for instant feedback; next tick the
  server's authoritative state either confirms (no change) or overrides
  (yellow flash on divergence).
- **X** → attempt to DUP the selected cube. LINEAR cubes reject
  server-side — both tabs see a red shatter effect and `linearity_violation`
  in the log. This is the key demo of "server-authoritative substructural
  typing".
- **R** → attempt to DROP. Same story — LINEAR rejects, AFFINE accepts.

## Architecture

    [three.js client]                       [Elixir world-host]
        ▲                                        │
        │  WebSocket (/socket via vite proxy)    │
        ├──────── join "world:region:..." ──────▶│  WorldChannel
        │                                        │
        │◀────── "snapshot" (initial state) ─────│
        │                                        │
        │◀────── "tick_delta" (20 Hz) ───────────│  Region.advance_tick/1
        │                                        │
        │        "entity_action" (move/dup/...) ▶│  Region → Entity mailbox
        │                                        │    ├ Linearity.check/2
        │                                        │    └ Entity.apply_op/3
        │◀────── "entity_action_result" ─────────│  (fan-out via PubSub)

The client's render loop interpolates `displayPosition → predictedPosition`
smoothly. On every `tick_delta`, authoritative positions replace predicted
where they differ (with a visual cue).

## Files

- `src/main.ts` — bootstrap; wires socket → world → scene → input.
- `src/types.ts` — wire types matching `docs/prd/WORLD-PROTOCOL.md` §8.
- `src/scene.ts` — three.js scene (renderer, camera, lights, ground).
- `src/entity.ts` — `EntityMesh` — one cube per `WorldEntity`.
- `src/world.ts` — entity map, prediction, reconciliation, shatter lifecycle.
- `src/socket.ts` — Phoenix `Socket` + `Channel` wrapper.
- `src/input.ts` — keyboard + pointer → `entity_action`.
- `src/shatter.ts` — shard particle effect for LINEAR DUP rejection.
- `src/log.ts` — minimal DOM log panel.
- `public/cell-engine.wasm` — auto-copied by `vite.config.ts` from
  `core/cell-engine/zig-out/bin/`. Not executed yet; staged here for when
  the next iteration wires WASM-backed client prediction to match the
  server-side authoritative execution path.

## Things the POC does

- ✅ Two tabs see a consistent region at 20 Hz.
- ✅ Click-to-select; keyboard-to-move; client prediction.
- ✅ Server-authoritative state wins; client snaps + flashes on divergence.
- ✅ LINEAR type enforcement is visible cross-client.
- ✅ Hash chain advances every tick (check the server logs + `state_hash`
  field in each `tick_delta`).

## Things the POC intentionally defers

- **WASM prediction.** Client prediction currently mirrors server arithmetic
  directly. `public/cell-engine.wasm` is loaded and present for the next
  step, which is invoking it on the client per action and comparing the
  resulting `stateHash` against `local_predicted_state_hash`.
- **Signed actions.** `entity_action` goes over the wire without ECDSA
  signatures. The `UserSocket` session id is random per tab. Real
  BCA-derived identity slots in at `socket.ts:WorldSocket` constructor.
- **CBOR encoding.** JSON is fine for debugging; switch at the encoder
  boundary once the wire format stabilises.
- **Camera controls.** Fixed isometric-ish camera. OrbitControls would be
  a two-line addition; left out to keep the demo scope tight.

## References

- `docs/prd/WORLD-PROTOCOL.md` — protocol spec.
- `apps/world-host/` — Elixir server this client talks to.
- `apps/world-feasibility/` — the benchmark + Wasmex feasibility tests.
- `apps/demo-wasm-threejs/` — single-player WASM-in-browser sibling that
  this client's `cell-engine.wasm` loader pattern is copied from.
