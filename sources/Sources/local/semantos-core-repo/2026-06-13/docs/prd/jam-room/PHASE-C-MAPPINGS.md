---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-C-MAPPINGS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.780322+00:00
---

# Phase C — Bring-Your-Own Mappings: Controllers, Surfaces, Racks

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 2 weeks (with 20% buffer: ~2.5 weeks)
**Prerequisites**: Phase A merged (`jam.mapping` kind, `JamMappingHint` on every rack); Phase B merged (mode row including Custom button slot).
**Branch prefix**: `jam-room-c-mappings`
**Master document**: `MASTER.md`

---

## Context

The brief's strongest single insight is the Launchpad observation:
*every controller is a Semantos input/output surface*. Phase C makes
that real. After this phase, a player can:

1. Plug in any MIDI controller (MPK49, RX2, Launchpad, Push, Circuit,
   a generic 8×8) or use QWERTY, touch, gamepad, or phone.
2. Have it auto-recognised against a built-in profile.
3. Edit the mapping in-app and save it as a `jam.mapping` semantic
   object — versioned, owned, attributable, shareable.
4. Fork someone else's mapping for their own controller.
5. Drive the same surface (the 8×8 grid, mix strip, note grid, etc.)
   from multiple devices simultaneously without conflict.

Phase C is largely an integration phase: the runtime hooks exist
already (`src/instruments/midi.ts`, `src/instruments/midi-map.ts`,
`getMappingHints()` on every rack from Phase A). What's missing is the
mapping-as-object layer, the editor UI, and the layered routing
pipeline.

### What this phase is not

- Not a new UI framework. The mapping editor is a single workbench
  card; it does not become a separate page.
- Not a sample / preset marketplace. Mapping sharing rides
  `world-sdk` content addressing the same way patterns and crates do
  (Phase A `jam.mapping` is `linear`).
- Not a hardware driver. It uses Web MIDI, Web HID, gamepad, and
  pointer/touch events; native bridges are out of scope.

---

## Architecture

### C.1 The five-layer mapping pipeline

```
┌──────────────────────────────────────────────────────────┐
│ 1. Device layer                                          │
│    Web MIDI / Web HID / pointer / touch / gamepad / WS   │
│    raw input  → normalised DeviceEvent                    │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│ 2. Surface layer                                         │
│    DeviceEvent → SurfaceEvent (pad / key / knob / fader  │
│    / touch / xy / gamepad-axis-or-button)                │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│ 3. Mode layer                                            │
│    Current GridMode (Phase B) decides what each surface  │
│    element means right now.                              │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│ 4. Semantic layer                                        │
│    Emits canonical jam.input.* / jam.note.* / jam.rack.* │
│    cells (Phase A families).                             │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│ 5. Feedback layer                                        │
│    Reads room state → produces device-specific feedback  │
│    (LED colour, label, motorised fader, haptic).         │
└──────────────────────────────────────────────────────────┘
```

### C.2 `jam.mapping` payload

Phase A defined the kind. Phase C defines the canonical payload:

```ts
export interface JamboxMappingPayload {
  /** Stable mapping name. */
  name: string;
  /** Author identity. */
  author: string;
  /** What surface shape this mapping targets. */
  surfaceShape: 'grid-8x8' | 'grid-4x8' | 'grid-16x8'
              | 'keyboard' | 'dj-deck' | 'mpk49' | 'launchpad'
              | 'push' | 'circuit' | 'qwerty' | 'touch'
              | 'gamepad' | 'phone' | 'phone-with-controller'
              | 'three-room' | 'custom';
  /** Map every input to a target. */
  inputs: MappingInput[];
  /** Map device feedback channels to room state subscriptions. */
  outputs: MappingOutput[];
  /** Constraints — e.g. "this mapping requires the Drum mode". */
  constraints?: MappingConstraint[];
  /** Visual feedback colour rules. */
  colourRules?: MappingColourRule[];
  /** Semantic version. */
  version: string;
  /** License — passes through to fork lineage. */
  license: 'personal' | 'remixable' | 'commercial';
}

export interface MappingInput {
  /** Source — the surface element being mapped from. */
  type: 'pad' | 'key' | 'knob' | 'fader' | 'touch' | 'xy' | 'gamepad-axis' | 'gamepad-button' | 'transport';
  /** Specific identifier on that surface. */
  selector: string | number;
  /** Optional value transform (linear / exp / log / clamp). */
  transform?: { kind: 'linear' | 'exp' | 'log' | 'clamp'; min?: number; max?: number; gamma?: number };
  /** Target — what the input drives. */
  target: MappingTarget;
}

export type MappingTarget =
  | { kind: 'mode'; mode: GridModeKind }
  | { kind: 'rack.macro'; rackId: string; macro: number }
  | { kind: 'rack.note'; rackId: string }
  | { kind: 'rack.trigger'; rackId: string; voiceId: string }
  | { kind: 'pattern.step'; patternId: string; lane: string; step: number }
  | { kind: 'clip.launch'; clipId: string }
  | { kind: 'scene.launch'; sceneId: string }
  | { kind: 'transport'; verb: 'play' | 'stop' | 'record' | 'overdub' | 'tap' | 'metronome' | 'undo' | 'redo' | 'capture' | 'quantize' };

export interface MappingOutput {
  /** Device feedback channel. */
  type: 'led' | 'label' | 'motor-fader' | 'haptic';
  selector: string | number;
  /** Room state subscription that drives the output. */
  source: 'clip.state' | 'scene.state' | 'rack.macro' | 'pattern.playhead'
        | 'transport.state' | 'player.colour' | 'scale.degree';
  /** Optional projection (e.g. clip.state → colour, scale.degree → colour). */
  projection?: 'colour' | 'brightness' | 'pulse' | 'flash' | 'value' | 'label';
}
```

#### C.2a LED feedback for the scale channel

Mappings that target a controller with RGB pad / per-key LED feedback
(Launchpad Pro, Push 3, Roli Lumi, Yamaha CP with retrofit strip,
etc.) can subscribe to `source: 'scale.degree'` with `projection:
'colour'`. The mapping output layer reads `colourForPitch` from the
Phase A scale-colour module and pushes the resulting hue/saturation
into the device-specific LED protocol (SysEx for Launchpad Pro,
proprietary for Push 3, BLE for Lumi).

This is what makes "learn an instrument" work on a real keyboard:
the controller's keys light up in the active scale's palette, locked
to the same root the room uses, with the same `◊` accent on modal
characteristic notes Note mode shows on the on-screen grid.

```ts
// example mapping snippet for Launchpad Pro programmer mode
{ type: 'led', selector: 'pad.0.0', source: 'scale.degree',
  projection: 'colour' }

export interface MappingConstraint {
  kind: 'requires-mode' | 'requires-rack' | 'requires-permission';
  value: string;
}

export interface MappingColourRule {
  /** Maps a room-state predicate to a pad colour. */
  when: string;
  colour: PadColor;
}
```

### C.3 Built-in profiles

Phase C ships eight profiles in
`apps/world-apps/jam-room/src/mappings/profiles/`:

| File                  | Surface             | Default behaviour                                                                  |
| --------------------- | ------------------- | ---------------------------------------------------------------------------------- |
| `qwerty.ts`           | QWERTY keyboard     | Z–M = bottom row of selected mode; A–L = upper rows; 1–8 = mode shortcuts (Phase B) |
| `touch.ts`            | Touch / pointer     | Pointer events translate to pad presses                                            |
| `launchpad.ts`        | Novation Launchpad / Mini / X | 8×8 = grid surface; right column = scene launch; top row = mode row      |
| `launchpad-pro.ts`    | Launchpad Pro       | Adds programmer-mode SysEx for full RGB feedback                                   |
| `push3.ts`            | Ableton Push 3      | 8×8 + macros (8 knobs) + transport row                                             |
| `circuit.ts`          | Novation Circuit / Tracks | 4×8 grid; bottom row = mute/solo; macro knobs map to rack macros 0..3        |
| `mpk49.ts`            | Akai MPK49          | Keys = note mode pitch; pads = drum rack; 8 knobs = rack macros; 8 faders = mix volume; transport buttons = transport |
| `rx2.ts`              | Numark RX2          | Decks A/B = scene A/B; crossfader = scene morph; jog wheels = nudge / scrub; FX pads = gestures |
| `gamepad.ts`          | Gamepad             | Sticks = XY pad; D-pad = mode; face buttons = transport                            |
| `phone.ts`            | Phone-as-controller | XY pad + accelerometer-driven macro 7 (chaos) + gyroscope-driven macro 6 (body)    |
| `phone-with-controller.ts` | Phone hosting a USB/BLE controller (Phase G path) | Phone runs the jam-room mobile shell; a connected MIDI controller routes through the same registry as desktop |

`qwerty` and `touch` are loaded by default. The rest activate when a
matching device is detected.

### C.4 Mapping registry

```
src/mappings/registry.ts

class MappingRegistry {
  install(mapping: JamboxSemanticObject<JamboxMappingPayload>, surface: SurfaceId): void;
  uninstall(mappingId: string): void;
  fork(fromMappingId: string, owner: Identity): JamboxSemanticObject<JamboxMappingPayload>;
  active(surfaceId: SurfaceId): JamboxMappingPayload | null;
  list(): JamboxSemanticObject<JamboxMappingPayload>[];
}
```

Install emits `jam.mapping.install`; uninstall emits
`jam.mapping.uninstall`; fork emits `jam.mapping.fork` with parent
lineage filled in via the existing `parents: string[]` header field.

### C.5 Mapping editor UI

A new workbench card `data-card="mapping-editor"`:

- Top: surface picker (drop-down of detected surfaces).
- Left: list of inputs (pads / keys / knobs / faders) with current
  binding shown.
- Right: target picker — narrows by `MappingTarget.kind`.
- Bottom: save / fork / publish buttons.
- Live: when the user touches the device, the corresponding row in the
  left list highlights so binding is by-touch instead of by-typing.

Editor changes mutate a draft `JamboxMappingPayload` in memory; Save
emits a `jam.mapping.install` cell with the new content hash. Fork
duplicates and reparents.

### C.6 Custom mode

Phase B reserved a Custom button on the mode row. Phase C activates it:
selecting Custom uses the active mapping for the current surface
without imposing any of the built-in mode rules. This is the escape
hatch for users who want to drive the surface entirely from their own
mapping.

### C.7 Sharing

Mappings ride the same content-addressed path as patterns and crates:

- Save → write `JamboxSemanticObject<JamboxMappingPayload>` to the
  cell-relay CAS.
- Share → produce a content link the recipient resolves through
  `world-sdk`.
- Install from share → `MappingRegistry.install`.

The existing `world-sdk` client is unchanged.

---

## Deliverables

### D-C.1 — `JamboxMappingPayload` and registry

- Add the payload type to `src/semantic/objects.ts` (the kind already
  exists from Phase A; this fills out the payload).
- Implement `src/mappings/registry.ts`.
- Implement `src/mappings/router.ts` — the layered pipeline (§C.1) that
  every input goes through.

### D-C.2 — Device-layer adapters

- `src/mappings/devices/web-midi.ts` — MIDI in/out adapter.
- `src/mappings/devices/web-hid.ts` — HID for devices that need it
  (Push 3 SysEx etc.).
- `src/mappings/devices/pointer-touch.ts` — DOM pointer/touch.
- `src/mappings/devices/gamepad.ts` — Gamepad API.
- `src/mappings/devices/keyboard.ts` — DOM key events.
- Each adapter emits a normalised `DeviceEvent`.

### D-C.3 — Built-in profiles

- Eight files in `src/mappings/profiles/` per the table in §C.3.
- `qwerty` and `touch` always active; others activate on detection.

### D-C.4 — Mapping editor card

- `src/ui/mapping-editor.ts` — new card in the pool.
- Surface picker; live highlight on device touch; target picker;
  save / fork / publish.
- Save emits `jam.mapping.install`; fork emits `jam.mapping.fork`.

### D-C.5 — Custom mode wiring

- `surface.setMode('custom')` consults
  `MappingRegistry.active(surfaceId)`; routing skips built-in mode
  rules and goes mapping-direct.
- The mode row's Custom button (Phase B disabled stub) is enabled.

### D-C.6 — Auto-detect and prompt

- On a new device appearing, the app checks the registry for a saved
  mapping and falls back to the built-in profile.
- If neither matches, a non-blocking toast offers "Create mapping for
  X?" which opens the editor.

### D-C.7 — Conflict resolution

- Two devices mapping the same target: the **last touched** device wins
  the visual feedback; both still produce events.
- A device mapping that would shadow Phase B's Note-mode in-key
  guardrail emits a warning toast and falls back to scale-locked input
  unless the mapping declares `MappingConstraint { kind: 'requires-permission', value: 'chromatic' }`.

### D-C.8 — Phase C gate test

`apps/world-apps/jam-room/__tests__/phase-c-gate.test.ts`:

- Loading a `JamboxSemanticObject<JamboxMappingPayload>` round-trips.
- Installing a mapping for the QWERTY profile produces the expected
  pads-by-key behaviour.
- A simulated MIDI controller posting note-on events through the
  router lights the correct grid pads.
- Forking a mapping creates a new id whose `parents[0]` is the
  original.
- Phase A and Phase B gates re-run and still pass.

---

## Gate tests (commands)

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-c-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

---

## Completion criteria

1. Eight built-in profiles installable.
2. QWERTY and touch active by default; MIDI / HID / gamepad activate on
   detection.
3. Mapping editor card creates, edits, saves, and forks mappings.
4. Custom mode honours the active mapping.
5. Mappings serialise to `JamboxSemanticObject<JamboxMappingPayload>`
   and are content-addressed.
6. A user can plug in an MPK49, hit a key, and have it play through
   `jam.rack.poly-keys` without touching the editor.

---

## Risks & mitigations

| Risk                                                                     | Mitigation                                                                                                |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| Web MIDI permission UX confusing on first connect                        | Detection adapter fires a single user-gesture-prompted permission request; cached after first grant.      |
| Mapping editor turns into a kitchen sink                                 | Strict deliverable list; no automation, no learn-mode beyond the live highlight, no per-key macros yet.   |
| Forks proliferate and pollute the cell-relay CAS                         | Existing CAS dedup catches identical content; the fork lineage is a graph on `parents`, not duplicate bytes. |
| Mapping gives a malicious device authority over the room                 | All device events are local-only; only the canonical jam.* cells go to the relay, after the surface/mode layers run. |

---

## Non-goals

- No engine changes (= phase D).
- No 3D affordances (= phase E).
- No take capture (= phase F).
- No marketplace UI (commercial / royalty fields exist but no payment
  flow is wired in this phase).
- No native MIDI hosting (Web MIDI only).
