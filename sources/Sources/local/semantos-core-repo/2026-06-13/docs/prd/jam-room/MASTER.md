---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.781427+00:00
---

# Jam Room — Master PRD

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Total duration**: ~13–17 weeks across phases A–G (with 20% buffer)
**Prerequisites**: jam-room app at v0.2.0, BEAM `cell_relay` running, world-sdk wired.
**Branch prefix family**: `jam-room-*`

---

## 0. Design thesis

The jam room should feel less like a DAW and more like walking into a
shared musical machine. A player should be able to:

1. Enter the room and immediately make sound.
2. Understand where the loop is, where the beat is, and who is doing what.
3. Switch between playing, sequencing, looping, muting, arranging, and performing without opening a dense editor.
4. Bring their own controller, mappings, synth rack, PureData patch, Strudel pattern, WebAudio instrument, or external MIDI gear.
5. Leave behind a verifiable musical-object stream: patterns, loops, instrument state, arrangement moves, room actions, and authorship.

Operationally:

> The instrument must be playable first, programmable second,
> collaborative third, and semantic underneath.

Semantos must not be visible as "blockchain-ish infrastructure". It
should feel like the reason the room remembers everything, routes
everything cleanly, and lets anyone remix safely.

---

## 1. Current reality (what already exists)

This is the truth on disk in `apps/world-apps/jam-room/` as of
2026-05-03. Everything below is real working code, not aspiration.

### 1.1 Surfaces and sequencer

- `src/grid/surface.ts` (525 lines) — 8×8 pad surface with five Push-3-style modes:
  `global`, `step`, `param`, `session`, `arrangement`. Pad colours, brightness,
  pulse, label, and active state are first-class. `PadPressEvent` already
  carries mode + step + track + param + pattern-slot context.
- `src/sequencer.ts` (419 lines) — 13 tracks (`kick`, `snare`, `hat`, `clap`,
  `cb`, `tom`, `sub`, `perc`, `shaker`, `acid`, `bass`, `lead`, `samp`),
  zoomable resolution (16 / 32 / 64 steps per bar), four scenes (A/B/C/D),
  per-cell `vel` / `prob` / `ratchet` / `accent` / `slide`. External-transport
  slaving is in place via `setExternalTransport({ wallStartMs, bpm })`.
- `src/layout.ts` — drag-to-rack card layout for the workbench panels.

### 1.2 Audio + clock

- `src/audio.ts` (1089 lines) — WebAudio engine. Per-peer entity buses,
  master limiter, parallel reverb and delay buses with freeze, sidechain
  duck driven by kick, per-track filter / reverb / delay / drive /
  bitcrush, master-bus haas widener, MediaStreamAudioDestination tap for
  jam recording, censor gate.
- `src/core/beam-clock.ts` (210 lines) — `BEAMClock` NTP-style sync over
  the existing CellRelay WebSocket (`clock_ping` / `clock_pong`),
  outlier rejection (drop > 1.5× median rtt), nudge offset, beat
  message → local-time conversion.
- `src/core/sync.ts`, `src/core/dag.ts`, `src/core/anchor.ts` — DAG
  helpers, BSV PushDrop anchoring of session snapshots.

### 1.3 Semantic substrate (already cell-aware)

`src/semantic/objects.ts` (688 lines) defines `JamboxObjectKind`:

```ts
type JamboxObjectKind =
  | 'jam.world' | 'jam.instrument' | 'jam.skin' | 'jam.patch'
  | 'jam.snapshot' | 'jam.crate' | 'jam.track' | 'jam.sample-pack'
  | 'jam.sample' | 'jam.clock-calibration' | 'jam.drum-track'
  | 'jam.pattern' | 'jam.arrangement';
```

Every object carries a `SemanticObjectHeader` with version, semanticPath,
linearity class, ownerIdentity, ownerCertId, previousStateHash, parents,
optional commercial info (listed/priceSats/royaltyBps/license), skin slot,
and timestamp. Linearity is `linear | affine | relevant | debug`.

`src/semantic/importers.ts` (191 lines) imports rekordbox XML and Splice
folders into `jam.crate` / `jam.sample-pack` / `jam.sample` / `jam.track`
objects.

### 1.4 Three.js, instruments, transport bus

- `src/three/jambox-world.ts` (512 lines) and `src/three/pod-hud.ts` (200 lines)
  render a 3D room projection alongside the workbench.
- `src/instruments/{arp,keys,sampler,midi,midi-map}.ts` — local instrument
  modules that all dispatch into `audio.ts`.

### 1.5 BEAM backend

- `runtime/world-beam/apps/cell_relay/` — Elixir CellRelay process that
  serves rooms (`room.ex`), endpoints, and the WS handler. The jam-room
  client connects via `@semantos/world-sdk` (`packages/world-sdk/`).

### 1.6 What is **not** there yet

| Brief calls for                           | Status                                                                            |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `jam.macro` (8 macros per rack)           | Missing — only ad-hoc track FX exist                                              |
| `jam.clip` (launchable, distinct from pattern) | Missing — patterns and scenes are not yet a launch object                    |
| `jam.scene` as launchable group           | Partial — scene is currently an integer 0–3, not a semantic object                |
| `jam.take` (captured performance pass)    | Missing                                                                            |
| `jam.contribution` (authorship object)    | Missing — `ownerIdentity` exists, but not split-aware contribution                 |
| `jam.player` (formal player object)       | Implicit — peers exist via the BEAM presence layer but no semantic object          |
| `jam.mapping` (controller/rack mapping)   | Missing entirely                                                                   |
| `jam.rack` (composable instrument bundle) | Missing — there's `jam.instrument` but no rack contract                            |
| `jam.gesture` (filter sweep, riser, etc.) | Missing                                                                            |
| Note mode (scale / iso / chord)           | Sequencer supports melodic tracks; surface has no Note mode                        |
| Mix mode                                  | Track FX exist; no Mix mode UI on the grid                                         |
| Strudel adapter                           | Missing                                                                            |
| PureData bridge                           | Missing                                                                            |
| Loop-orb / scene-floor / arrangement-wall as control surfaces | Three.js exists; not wired to interaction       |

These six gaps are exactly what phases A–F close.

---

## 2. The primitive rack (target end-state vocabulary)

After phase A, `JamboxObjectKind` extends to:

```
existing            jam.world  jam.instrument  jam.skin  jam.patch
                    jam.snapshot  jam.crate  jam.track  jam.sample-pack
                    jam.sample  jam.clock-calibration  jam.drum-track
                    jam.pattern  jam.arrangement

added in phase A    jam.rack         (composable instrument bundle)
                    jam.macro        (safe performance parameter)
                    jam.clip         (launchable pattern/audio unit)
                    jam.scene        (launchable group of clips)
                    jam.take         (captured performance pass)
                    jam.contribution (authorship/attribution)
                    jam.player       (room participant)
                    jam.gesture      (high-level expressive move)
                    jam.mapping      (controller/surface mapping)
                    jam.permission   (per-object permission grant)
```

Event-cell families introduced in phase A (these are the verbs):

```
jam.input.{pad,key,knob,fader,touch,gamepad}
jam.clock.{tick,start,stop,nudge}
jam.note.{on,off,expression}
jam.trigger
jam.control.{change,gesture}
jam.pattern.{step.toggle,step.setVelocity,step.setProbability,lane.select}
jam.clip.{arm,record.start,record.stop,launch.queue,stop.queue}
jam.scene.launch
jam.arrangement.{section.add,section.move,section.resize,take.capture,take.promote}
jam.rack.{macro.set,preset.load,state.save}
jam.mapping.{install,uninstall,fork}
jam.room.{broadcast.statePatch,player.join,player.leave}
```

---

## 3. The `JamRack` runtime contract

Phase A introduces a single rack contract that every engine
implementation conforms to:

```ts
export interface JamRack {
  id: string;
  name: string;
  engine: 'webaudio' | 'puredata' | 'strudel' | 'midi' | 'hybrid';

  play(event: JamNoteOn | JamTrigger): void;
  stop(event: JamNoteOff | JamStop): void;
  setMacro(index: number, value: number): void;   // 0..7, value 0..1
  setPreset(presetId: string): void;
  getState(): JamRackState;
  setState(state: JamRackState): void;
  getMeters(): JamMeters;
  getMappingHints(): JamMappingHint[];
}
```

Macros are **musical** (`brightness`, `dirt`, `wobble`, `space`, `snap`,
`body`, `chaos`, `tension`), never raw DSP names. Each macro can fan
out to many low-level parameters inside the rack.

Engines that conform:

- **WebAudio** — phase A wraps the existing `audio.ts` per-track FX into
  a default 4-rack starter set (drum, bass, lead/pad, sampler).
- **Strudel** — phase D.
- **PureData** — phase D.
- **MIDI external** — phase D's last deliverable.

---

## 3a. The 1-3-5-3-1 Conscious Stack mapping

A song really is a pyramid. Folded in from
[`design/CSD-COMPRESSION-GRADIENT.md`](./design/CSD-COMPRESSION-GRADIENT.md):

```
L1 — 1 ANCHOR        the loop (active jam.scene/jam.clip)
L2 — 3 ACTIVE        rhythm + melody + bassline (jam.rack ×3)
L3 — 5 SUPPORT       pads, effects, generative, external MIDI, capture
L4 — 3 INFRASTRUCTURE clock, identity, persistence (invisible)
L5 — 1 DEVICE        the surface (jam.mapping.surfaceShape)
```

**Compression gradient** — as real estate compresses, peel layers
from the bottom up. Mobile shows L1 + L2; tablet adds L3 (gated);
desktop adds L4 hover-HUD; L5 is what it is.

Phase A ships the `viewportPlan` field on `jam.world` plus three
default plans (`desktopPlan`, `tabletPlan`, `mobilePlan`) so every
renderer reads the same projection rule. Phase G ships the actual
mobile renderer + Flutter shell.

## 3b. Colour as a first-class dimension

Folded in from [`design/COLOUR-AS-DIMENSION.md`](./design/COLOUR-AS-DIMENSION.md):

Colour carries two orthogonal channels:

- **Track channel** (existing) — hue encoded by track, clip state, mode.
- **Scale channel** (new) — saturation, brightness, border, label
  encoded by scale degree (root / in-scale / modal / chromatic).

Phase A ships `src/colour/scale-colour.ts` with the pure
`classifyPitch` and `colourForPitch` functions. Phase B's Note mode
is the first consumer. Phase C lets controllers with RGB feedback
(Launchpad Pro, Push 3, Roli Lumi) project the scale channel onto
their physical pads / keys via `MappingOutput { source: 'scale.degree',
projection: 'colour' }` — which is what makes "learn an instrument"
work on a real keyboard.

Three palettes ship: **Boomwhacker** (default; educational standard),
**Newton** (classical), **Scriabin** (synesthete).

Five label modes: `off | number | solfege | note-name | fingering`.
Fingering enables piano lessons — colours light up under each key,
locked to the active scale.

Scale lock is on by default; chromatic pads dim and emit a silent
no-op + 600 ms visual flash on press, enforcing the "no wrong notes"
guarantee visually as well as audibly.

## 4. Phase breakdown

Each phase is shippable independently after phase A. Phases B / C / D /
E / F / G can run concurrently once A is in main.

### Phase A — Vocabulary + Rack contract + viewport + colour (1.5–2 weeks)

Adds the missing semantic kinds and the `JamRack` interface. Wraps the
existing audio engine into four conformant racks. Introduces the
event-cell families. Ships the **`viewportPlan` field** on `jam.world`
+ three default plans, and the **`scale-colour` pure module**
(`classifyPitch` + `colourForPitch`) so phases B and G have stable
contracts to render against. **Blocks every other phase.**

### Phase B — Mode row revision + Note + Mix + colour (1.5–2 weeks)

Replaces the eight-button mode row with **anchor row + 3 L2 buttons
(Rhythm / Melody / Bass) + 5-entry support sheet** (Sequencer / Mix /
Session / Arrange / Custom) per the Sincerity Filter. Adds Note mode
(scale / iso-fourths / chord / bassline) consuming Phase A's
`colourForPitch` for scale-channel rendering, with scale-lock on by
default. Adds Mix peek (inline on Bass + Melody pods) plus full Mix
mode in the support sheet. Refines Drum and Step against the new
clip / scene / rack primitives. Demotes Session and Arrangement views
to support sheet entries; their handlers are upgraded the same way.

### Phase C — Bring-your-own mappings (2 weeks)

`jam.mapping` becomes a first-class object: layered (device → surface →
mode → semantic → feedback), versioned, shareable. Built-in profiles for
Launchpad, Push, Circuit, MPK49, RX2, QWERTY, touch, gamepad, phone.
Mapping editor panel.

### Phase D — Engine bridges: Strudel + PureData (2–3 weeks)

`StrudelRack` and `PureDataRack` implementations of `JamRack`. Strudel
runs in-process (eval'd patterns); PureData runs via libpd-WASM where
viable, OSC bridge otherwise. Both write capture back into `jam.pattern`
on demand. MIDI external rack as the final deliverable.

### Phase E — 3D room as control surface (2 weeks)

Three.js objects become semantic interaction surfaces: loop orbs are
draggable / throwable, scene tiles are floor pads, the arrangement wall
accepts blocks, instrument pods are focusable. The room is a projection
of room state, not a parallel decoration.

### Phase F — Takes, contributions, lineage (1.5–2 weeks)

Live launch passes record into `jam.take`. Promote a take to
`jam.arrangement`. `jam.contribution` carries split-aware attribution.
Anchoring extends to take and arrangement objects via the existing
PushDrop path. License + permission propagation through fork lineage.

### Phase G — Mobile compression + Flutter shell (2.5–3 weeks)

Responsive web layout for the existing browser app honouring
`viewportPlan`. New `apps/world-apps/jam-room-mobile/` Flutter app
modelled on `apps/oddjobz-mobile/` — pairs with `runtime/semantos-brain` over
WSS, subscribes to LoomState, dispatches LoomActions, renders L1 +
L2 natively. MIDI hosting on phone via `flutter_midi_command`
(USB OTG on Android; CoreMIDI on iOS — the only path for hosting a
controller on iPhone since Safari has no Web MIDI). Phone-as-
controller (web) extended with gyroscope, multi-touch, three-finger
gestures.

---

## 5. Dependency graph

```
                      ┌────────────────────────────────┐
                      │  Phase A — Vocabulary          │
                      │  + JamRack + viewport + colour │
                      └────────────┬───────────────────┘
                                   │
       ┌────────────┬──────────────┼──────────────┬─────────────┐
       │            │              │              │             │
┌──────▼─────┐ ┌────▼──────┐ ┌─────▼─────┐ ┌──────▼──────┐ ┌────▼──────┐
│ Phase B —  │ │ Phase C — │ │ Phase D — │ │ Phase E —   │ │ (Phase G  │
│ Mode row + │ │ Mappings  │ │ Strudel + │ │ 3D control  │ │  starts   │
│ Note + Mix │ │ + BYO     │ │ PureData  │ │ surface     │ │  after A  │
│ + colour   │ │           │ │           │ │ (desktop)   │ │  + B + C) │
└─────┬──────┘ └─────┬─────┘ └─────┬─────┘ └──────┬──────┘ └────┬──────┘
      │              │             │              │             │
      └──────┬───────┴─────────────┴──────────────┘             │
             │                                                  │
     ┌───────▼───────┐                                ┌─────────▼────────┐
     │ Phase F —     │                                │ Phase G —        │
     │ Takes +       │                                │ Mobile + Flutter │
     │ lineage       │                                │ shell            │
     └───────────────┘                                └──────────────────┘
```

Phase F integrates outputs from B–E (modes, mappings, engine racks, 3D
gestures) into a single attributable performance object. Phase G
ports the upper triangle of the pyramid (L1 + L2 + selective L3) to
phone and tablet — needs A's `viewportPlan`, B's mode row, and C's
mappings.

---

## 6. Success metric — the first 30 seconds

The phase set is **not** complete until a fresh user can:

1. Enter a jam-room URL.
2. See the grid, hear the room clock pulse.
3. Press a pad in **under 3 seconds** and hear something musical.
4. Capture a 4-bar loop with one button.
5. See that loop appear as an orb in the 3D room and as a clip in
   session view, owned by them, attributable.
6. Have a second player join and contribute on a different track without
   any setup.
7. Promote the resulting performance to a take, fork it, and replay it
   later from the take object alone.

If any of those seven steps requires a screen of configuration, the
phase set has failed regardless of how complete the semantic model is.

---

## 6a. Parallelism — UI track and system track

Phase A's `viewportPlan` and `colourForPitch` deliverables exist
specifically so design and system can advance simultaneously. Once
Phase A merges:

- **System track** can land Phase B's mode-row scaffolding, Phase C's
  mapping registry + device adapters, Phase D's engine bridges, Phase
  E's three-room interactions, Phase F's take pipeline, and Phase G's
  Flutter scaffold + WSS plumbing.
- **Design track** can simultaneously polish: the L1 anchor card
  visual, the three L2 button glyphs, the support sheet ordering and
  open gesture, the Boomwhacker palette's exact sRGB values, the modal
  characteristic-note glyph, the layout-by-scale transition timing,
  the Mix-peek inline rows, the Custom mode visual, the loop-orb
  visual language, the arrangement wall typography, and the mobile
  bottom-tab-bar styling.

The design track polishes against `colourForPitch` snapshots and
`mobilePlan` constants; the system track wires the renderers. Neither
blocks the other. They land together when the phase merges.

**The four design notes under [`design/`](./design/) are the contract
between the two tracks.** Decisions there propagate back into phase
PRDs over time; until that fold-back happens, the design notes are
the source of truth for visual decisions.

## 7. Non-goals (explicit)

- **Not** a DAW. No multitrack audio recording timeline beyond the take
  object. No VST host. No mastering chain.
- **Not** a generic Three.js engine. The room is a projection; phases E
  and F do not invent a general-purpose 3D editor.
- **Not** a payment system. `jam.contribution` records splits; it does
  not move money. Settlement is downstream (existing `packages/settlement/`).
- **Not** a replacement for `packages/poker-agent` style session protocol.
  Multiplayer continues to ride the existing CellRelay BEAM channels.

---

## 8. Risks

| Risk                                                 | Mitigation                                                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Phase A vocabulary becomes too big to land           | Hard cap at the 9 new kinds + 12 event-cell families listed above. Future kinds need a new phase.|
| `JamRack` contract leaks WebAudio assumptions        | Phase D ships PureData and Strudel implementations as a stress test of the contract.             |
| Strudel / libpd-WASM bundle size bloats the app      | Both are loaded on first use, not at boot. Audit in phase D gate.                                |
| Mappings become a security surface (DOM events claiming authority) | All mapping payloads are content-addressed and validated; phase C gate test asserts.|
| Taking eats memory (loop buffers per pass)           | Phase F caps default take retention; long-form takes spool to the cell-relay's CAS.              |

---

## 9. Branch and CI policy

Every phase follows the existing repo policy
(`docs/BRANCHING-AND-CI-POLICY.md`):

- One branch per phase: `jam-room-{a..f}-{slug}`.
- Optional sub-branches: `jam-room-{x}-{slug}/D-{X}.{N}`.
- Cumulative gate test:
  `apps/world-apps/jam-room/__tests__/phase-{x}-gate.test.ts` — each
  phase imports and re-runs prior phases' gate.
- Tag after merge: `jam-room-v0.{x}.0`.

---

## 10. The thing to obsess over

The first instrument cannot feel like a demo. It needs:

- beautiful pads, punchy drums, zero-lag feel
- obvious loop capture
- juicy macro controls
- satisfying visual feedback
- instant mute/solo
- clear mode switching
- session-to-arrangement magic

Everything else can be rough. **If the first 30 seconds feel amazing,
the architecture will make sense.** If the first 30 seconds feel like
setup, nobody will care how elegant the semantic model is.
