---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-E-3D-CONTROL-SURFACE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.782232+00:00
---

# Phase E — 3D Room as a Control Surface

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 2 weeks
**Prerequisites**: Phase A (`jam.clip`, `jam.scene`, `jam.player`, `jam.gesture`, `jam.contribution`); Phase B (Mix mode for the mixer-rail readout); Phase C (mappings can target room objects).
**Branch prefix**: `jam-room-e-3d-surface`
**Master document**: `MASTER.md`

---

## Context

`apps/world-apps/jam-room/src/three/jambox-world.ts` (512 lines) and
`pod-hud.ts` (200 lines) already render a 3D room next to the
workbench. Today the canvas is decorative — it visualises room state
but doesn't accept interaction beyond camera moves. The brief argues
the room should be a control surface: instrument pods you walk to,
loop orbs you grab, scene tiles you stand on, an arrangement wall you
build sections against.

Phase E makes the canvas interactive. Every Three.js object becomes a
projection of a Phase A semantic object, and interactions emit
canonical `jam.*` cells through the same router every other surface
uses. Three.js stops being a parallel decoration and becomes a peer of
the 8×8 grid.

### What this phase is not

- Not XR / VR / AR. The canvas remains a desktop / laptop DOM canvas.
  Headset support is a future phase.
- Not a 3D editor. Users place loop orbs, drop scene tiles, drag
  arrangement blocks. They do not author meshes.
- Not a physics engine. Movement is constrained kinematic. No physics
  library is added.

### Viewport rule (folded in from `design/CSD-COMPRESSION-GRADIENT.md`)

The 3D room is a **desktop-only** projection. The renderer reads the
active `JamboxWorldPayload.viewportPlan` (Phase A) and:

| Plan         | What renders                                                                                |
| ------------ | ------------------------------------------------------------------------------------------- |
| `desktopPlan`| Full Three.js scene per §E.5 of this PRD.                                                   |
| `tabletPlan` | A 2D session-view fallback (still semantic; same `jam.input.*` cells via Phase C router).   |
| `mobilePlan` | Hidden entirely. The L1 anchor card and L2 bottom tabs occupy the screen; the canvas does not load. |

This rule is enforced at module init: the Three.js bundle is a
dynamic import gated on `viewportPlan.surfacedLayers.includes('L4')`.
On `mobilePlan` the Three.js bundle never loads, so phone bundle size
stays under the Phase D budget.

---

## Architecture

### E.1 Object inventory and semantic backing

Every interactive object in the canvas projects a Phase A semantic
object. The mapping is one-way: room state is the source of truth;
the 3D scene graph re-renders on cell changes.

| 3D object              | Backing semantic object        | Interactions                                                                       |
| ---------------------- | ------------------------------ | ---------------------------------------------------------------------------------- |
| Instrument pod         | `jam.instrument` + `jam.rack`  | Walk near = focus rack; press E = play default voice; rotate knob ring = `jam.rack.macro.set` |
| Loop orb               | `jam.clip` (or `jam.pattern`)  | Click = preview; grab = move; throw to scene tile = clip-into-scene; throw to arrangement wall = arrangement section; split = fork into variation |
| Scene tile (floor)     | `jam.scene`                    | Step on = `jam.scene.launch`; long-press = preview without launching                |
| Arrangement block (wall)| `jam.arrangement` section     | Drag = move section; stretch handle = resize; promote button = `jam.arrangement.take.promote` |
| Player avatar          | `jam.player`                   | Hover = ownership/identity HUD; raise-hand gesture = `jam.gesture { kind: 'propose' }` |
| Mixer rail             | Live readout of all racks       | Slider drag = `jam.rack.macro.set`; mute/solo toggles match Mix mode                |
| Effect altar           | Room sends (`jam.effect`)       | Faders for room reverb / delay / crush / wash send levels                          |
| Sample crate           | `jam.crate` / `jam.sample-pack`| Browse, drag a sample to a sampler rack pod                                         |
| Contribution stream    | Live `jam.contribution` feed   | Read-only HUD (left edge); click = identity card                                   |

### E.2 Interaction model

```
Pointer / touch / gamepad
        │
        ▼
  three/picker.ts (raycast → object id)
        │
        ▼
  three/interaction-router.ts
        │
        ▼
  Phase C MappingRegistry (custom mappings get a hook)
        │
        ▼
  Canonical jam.* cell emission
        │
        ▼
  CellRelay (existing)
```

The interaction router sits next to the existing surface router from
Phase C. It does **not** bypass the mapping system; the mapping system
gets `surfaceShape: 'three-room'` events and can rewrite them.

### E.3 State subscription

The Three.js scene subscribes to:

- `jam.clock.tick` for visual pulse and orbit motion.
- `jam.clip.*` for loop-orb state colour.
- `jam.scene.launch` for floor-tile flash.
- `jam.player.*` for avatar presence.
- `jam.contribution` for the contribution-stream HUD.

State changes are throttled at 30 Hz; clock pulses tick at the BEAM
clock rate.

### E.4 Loop orb visual language

Per the brief §6.4.2:

- Size = pattern length / energy.
- Colour = owning track / player / instrument.
- Pulse = current playback phase (driven by `jam.clock.tick`).
- Orbit = ownership / collaboration (multiple owners = orbiting pair).
- Trail = recent edits (last 8 changes).

### E.5 Default room layout

```
Front floor:    Session grid — 8 columns of 4 scene tiles each
Left wall:      Instrument pods (one per registered rack)
Right wall:     Mixer rail + effect altar
Back wall:      Arrangement timeline (8–16 sections visible)
Centre:         Loop-orb constellation; player avatars
Ceiling / sky:  Clock readout, energy meter, key, transport state
```

Layout is configurable per-room via a `jam.world.layout` field. Phase E
ships a single default; future phases can ship presets.

### E.6 Performance budget

Three.js rendering must stay below:

- 8 ms / frame on a 2020 MacBook Pro M1.
- 16 ms / frame on a current-gen iPad.

Hard rules: no shadow maps in default scene, no post-processing
effects, max 200 mesh instances, instanced rendering for loop orbs and
scene tiles.

---

## Deliverables

### D-E.1 — Picker and interaction router

- `src/three/picker.ts` — raycast picker over the existing scene graph.
- `src/three/interaction-router.ts` — translates picks into canonical
  `jam.input.*` cells (with `surfaceShape: 'three-room'`).
- Hooks into the Phase C `MappingRegistry` so `surfaceShape:
  'three-room'` mappings can rebind interactions.

### D-E.2 — Instrument pods

- Extend `src/three/jambox-world.ts` to render one pod per registered
  rack from the Phase A registry.
- Pod knob ring drives `jam.rack.macro.set`.
- Pod focus state synchronises with the active rack used by Drum / Note
  / Step modes.

### D-E.3 — Loop orbs

- New `src/three/loop-orb.ts`.
- Visual language per §E.4. Instanced rendering.
- Drag = `jam.input.touch` with `target = orbId`. Drop on a scene tile
  emits `jam.scene.add-clip { sceneId, clipId }`. Drop on the
  arrangement wall emits `jam.arrangement.section.add { sceneId, lengthBars }`.
- Click previews via `jam.clip.launch.queue` with `quantum: 'immediate'`.

### D-E.4 — Scene tile floor

- New `src/three/scene-tile.ts`.
- Floor laid out as 8 cols × 4 rows by default.
- Step-on emits `jam.scene.launch`.
- Tile flashes on `jam.scene.launch` cell received via the cell-relay.

### D-E.5 — Arrangement wall

- New `src/three/arrangement-wall.ts`.
- Sections rendered as blocks coloured by `jam.scene` colour.
- Drag = `jam.arrangement.section.move`. Stretch handle =
  `jam.arrangement.section.resize`. Promote button on each section =
  `jam.arrangement.take.promote` (the take object itself is a Phase F
  deliverable; phase E only emits the cell).

### D-E.6 — Player avatars

- New `src/three/player-avatar.ts`.
- One per `jam.player` in the room.
- Avatar position updates from `jam.input.*` cells (a player who's
  currently driving the drum rack stands near that pod).
- Hover = identity HUD.
- Raise-hand gesture = `jam.gesture { kind: 'propose' }` cell.

### D-E.7 — Mixer rail and effect altar

- Existing per-track FX exposed as 3D faders/knobs. Drag = `jam.rack.macro.set`.
- Read-only meters from `JamRack.getMeters()` per Phase A.
- Reuse the Phase B Mix mode bindings.

### D-E.8 — Contribution stream HUD

- Left-edge HUD listing the last 32 `jam.contribution` cells.
- Each entry shows player avatar, action ("placed kick step at 1.3"),
  and timestamp.
- Click an entry = camera dolly to the related object.

### D-E.9 — Performance audit

- `scripts/audit-three-perf.ts` measures frame time on a synthetic
  workload (busy room: 100 orbs, 32 scenes, 8 players).
- Phase E gate test asserts the 8 ms / 16 ms budgets.

### D-E.10 — Phase E gate test

`apps/world-apps/jam-room/__tests__/phase-e-gate.test.ts`:

- Picker correctly resolves a synthetic pointer event to the
  expected loop-orb id.
- Stepping on a scene tile produces the correct `jam.scene.launch` cell.
- Dragging an orb to a scene tile produces a `jam.scene.add-clip` cell.
- Performance audit passes.
- Phase A/B/C/D gates re-run and pass.

---

## Gate tests (commands)

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-e-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
node scripts/audit-three-perf.ts
```

---

## Completion criteria

1. Every interactive 3D object projects a Phase A semantic object.
2. Pointer / touch / gamepad input on the canvas produces canonical
   `jam.*` cells through the mapping router.
3. Default room layout matches §E.5; loop orbs follow the visual
   language in §E.4.
4. Performance budgets met on the audit fixture.
5. Mixer rail and effect altar drive the same audio nodes the Mix mode
   does (no parallel audio paths).
6. All prior phase gates pass.

---

## Risks & mitigations

| Risk                                                                        | Mitigation                                                                                          |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Three.js bundle creep                                                       | The base bundle audit from Phase D extends; canvas code is bundled lazily where possible.           |
| Picker accuracy on touch                                                    | Hit-targets enlarged 1.5× on touch input; primary visual stays the same size.                       |
| Frame-time blow-up on Android                                               | Performance audit fixture runs on a synthetic CPU-throttled simulation in CI; real-device measured separately. |
| Mapping router misses three-room events                                     | All canvas events go through the router with `surfaceShape: 'three-room'`; never short-circuit.     |
| Avatar position oscillation when a player switches racks rapidly            | Position interpolates with a 200 ms easing; rapid switches are debounced.                           |

---

## Non-goals

- No XR.
- No physics.
- No 3D rack editor.
- No mesh authoring.
- No take recording (= phase F).
