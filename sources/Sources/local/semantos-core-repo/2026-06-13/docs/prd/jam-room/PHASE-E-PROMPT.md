---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-E-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.781962+00:00
---

# Phase E Execution Prompt — 3D Room as Control Surface

> Paste this prompt into a fresh session to execute Phase E.

## Context

You are working in `apps/world-apps/jam-room/`. Phases A through D are
merged. The semantic vocabulary, JamRack contract, mode row, Note +
Mix modes, BYO mappings, and Strudel / PureData / external MIDI
engines are all live. The Three.js canvas (`src/three/jambox-world.ts`,
`src/three/pod-hud.ts`) currently *projects* room state but does not
accept interaction.

Phase E makes the canvas a peer of the 8×8 grid. Pointer / touch /
gamepad input on the canvas produces canonical `jam.*` cells through
the same mapping router every other surface uses. Loop orbs become
draggable, scene tiles become floor pads, the arrangement wall accepts
section blocks, instrument pods become focusable rack interfaces.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD and prior phases):

- `docs/prd/jam-room/PHASE-E-3D-CONTROL-SURFACE.md` — Phase E spec with
  object inventory (§E.1), interaction model (§E.2), state subscription
  (§E.3), loop orb visual language (§E.4), default layout (§E.5),
  performance budget (§E.6), deliverables D-E.1–D-E.10.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context.
- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — `jam.clip`,
  `jam.scene`, `jam.player`, `jam.gesture`, `jam.contribution` are the
  semantic anchors the canvas projects.

**Read second** (existing canvas code you extend):

- `apps/world-apps/jam-room/src/three/jambox-world.ts` (512 lines) —
  Existing scene graph, camera, render loop. Your new modules
  (`picker.ts`, `interaction-router.ts`, `loop-orb.ts`, `scene-tile.ts`,
  `arrangement-wall.ts`, `player-avatar.ts`) attach into this scene.
- `apps/world-apps/jam-room/src/three/pod-hud.ts` (200 lines) — HUD
  patterns; reuse for the contribution-stream HUD.

**Read third** (mappings and routers):

- `apps/world-apps/jam-room/src/mappings/router.ts` (Phase C) — All
  three-room events go through this router with `surfaceShape:
  'three-room'`.
- `apps/world-apps/jam-room/src/mappings/profiles/touch.ts` and
  `gamepad.ts` (Phase C) — Reuse for pointer / gamepad in the canvas.

**Read fourth** (state and clock):

- `apps/world-apps/jam-room/src/core/beam-clock.ts` — `onBeat`
  callback drives 3D pulse animations.
- `apps/world-apps/jam-room/src/racks/registry.ts` — Used to render
  one instrument pod per registered rack.
- `apps/world-apps/jam-room/src/sequencer.ts` — Scene state for tile
  flashes.

**Read fifth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `jam-room-e-3d-surface`,
  commits as `jam-room-e/D-E.{N}: ...`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. THE CANVAS IS A PROJECTION

Three.js scene graph is a **projection** of room state, not the source
of truth. Cells flow up; render flows down. You do not mutate scene
graph state directly in response to user input — you emit a cell, the
cell-relay broadcasts, the scene graph re-renders.

### 2. ALL CANVAS EVENTS GO THROUGH THE MAPPING ROUTER

`surfaceShape: 'three-room'`. The Phase C mapping router gets first
right of refusal. Custom mappings can rebind canvas interactions.
Never short-circuit the router.

### 3. PERFORMANCE BUDGETS ARE NOT NEGOTIABLE

8 ms / frame on M1, 16 ms / frame on iPad. The audit fixture is the
arbiter. If you exceed the budget, the gate fails. Don't add shadow
maps. Don't add post-processing. Use instanced rendering for orbs and
tiles.

### 4. NO PARALLEL AUDIO PATH

The mixer rail and effect altar adjust the SAME audio nodes Mix mode
adjusts. Do not introduce a second mute system or a second send-bus
graph. The 3D affordances are a UI layer over the existing audio.

### 5. LOOP ORB VISUAL LANGUAGE IS FIXED

Size = length, colour = owner, pulse = phase, orbit = collaboration,
trail = recent edits. The PRD's §E.4 is law. Custom skins arrive in a
later phase if needed.

### 6. INTERACTION GESTURES MAP TO EXISTING VERBS

Drag-orb-to-tile = `jam.scene.add-clip`. Drag-orb-to-wall =
`jam.arrangement.section.add`. Step-on-tile = `jam.scene.launch`.
Drag-block = `jam.arrangement.section.move`. You do not invent new
verbs in this phase.

### 7. NO PHASE-F WORK

Sections render a "Promote" button that emits
`jam.arrangement.take.promote`. The actual take object construction is
Phase F. Phase E emits the cell, period.

---

## Deliverable mapping

| ID    | File(s) you create or change                                                |
| ----- | --------------------------------------------------------------------------- |
| D-E.1 | `src/three/picker.ts`, `src/three/interaction-router.ts`                    |
| D-E.2 | Extend `src/three/jambox-world.ts` for instrument pods                      |
| D-E.3 | `src/three/loop-orb.ts`                                                     |
| D-E.4 | `src/three/scene-tile.ts`                                                   |
| D-E.5 | `src/three/arrangement-wall.ts`                                             |
| D-E.6 | `src/three/player-avatar.ts`                                                |
| D-E.7 | Extend `src/three/jambox-world.ts` for mixer rail + effect altar            |
| D-E.8 | `src/three/contribution-hud.ts`                                             |
| D-E.9 | `scripts/audit-three-perf.ts`                                               |
| D-E.10| `apps/world-apps/jam-room/__tests__/phase-e-gate.test.ts`                   |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-e-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
node scripts/audit-three-perf.ts
```

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-e-3d-surface
```

Commit prefix: `jam-room-e/D-E.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.7.0`.

---

## Definition of done

1. Picker resolves canvas pointer events to the correct semantic object.
2. Interaction router emits canonical `jam.*` cells via the mapping
   router with `surfaceShape: 'three-room'`.
3. Loop orbs follow the §E.4 visual language; instanced rendering is in
   place.
4. Scene tiles flash on `jam.scene.launch`; step-on emits the launch
   cell.
5. Arrangement wall blocks render, drag, resize, and emit the right
   cells.
6. Mixer rail / effect altar share state with Mix mode; no parallel
   audio.
7. Performance audit passes both budgets.
8. Phase A/B/C/D/E gate tests all pass.

---

## What to **not** do

- Don't add shadow maps, post-processing, or third-party physics.
- Don't add an XR / VR / AR mode.
- Don't author new mesh assets that aren't required by the
  inventory in §E.1.
- Don't mutate scene-graph state directly on user input — emit cells.
- Don't reach for a global rendering loop rewrite; extend the existing
  one.
- Don't construct take objects; just emit `jam.arrangement.take.promote`.
