---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.779776+00:00
---

# Phase A — Jam Room Semantic Vocabulary + `JamRack` Runtime Contract

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 1.5–2 weeks (with 20% buffer: ~2–2.5 weeks)
**Prerequisites**: jam-room app at v0.2.0; `packages/world-sdk` and `runtime/world-beam` already wired.
**Branch prefix**: `jam-room-a-vocabulary`
**Master document**: `MASTER.md` (this file's parent)
**Blocks**: Phases B, C, D, E, F.

---

## Context

`apps/world-apps/jam-room/src/semantic/objects.ts` already defines a
respectable thirteen-kind `JamboxObjectKind` union (`jam.world`,
`jam.instrument`, `jam.skin`, `jam.patch`, `jam.snapshot`, `jam.crate`,
`jam.track`, `jam.sample-pack`, `jam.sample`, `jam.clock-calibration`,
`jam.drum-track`, `jam.pattern`, `jam.arrangement`). What the surface
now needs in order to keep growing without architectural drift is:

1. **A rack contract** (`JamRack`) so that every instrument — whether
   it's the existing WebAudio drum/synth path, a future Strudel pattern,
   a PureData patch, or a remote MIDI device — exposes the same five
   verbs (play / stop / setMacro / setPreset / state).
2. **Launchable primitives** (`jam.clip`, `jam.scene` as a real
   semantic object, not the integer 0–3 the sequencer uses today, and
   `jam.take`) so that session view, arrangement, and recorded
   performance can talk about the same things.
3. **Performance primitives** (`jam.macro`, `jam.gesture`, `jam.player`,
   `jam.contribution`, `jam.permission`) so phases B–F have a substrate.
4. **Mapping primitive** (`jam.mapping`) so phase C can ship without
   having to re-litigate the object model.
5. **Event-cell families** so the wire format is canonical instead of
   ad-hoc per surface.

This phase deliberately does **not** ship UI changes. It is the
plumbing under the hood. The five Push-3 modes already in
`src/grid/surface.ts` keep working; they just start dispatching
canonically named events.

### What this phase is not

- Not a UI phase. Mode rows, Note grid, Mix grid all live in phase B.
- Not an engine phase. Strudel and PureData arrive in phase D.
- Not a takes phase. Take *object* is defined here; take *capture* is
  built in phase F.
- Not a permission system overhaul. `jam.permission` carries
  per-object read/write/launch grants; the broader capability story
  remains in `core/cell-engine`.

---

## Architecture

### A.1 Vocabulary delta

After this phase, the union extends to:

```ts
export type JamboxObjectKind =
  // existing
  | 'jam.world' | 'jam.instrument' | 'jam.skin' | 'jam.patch'
  | 'jam.snapshot' | 'jam.crate' | 'jam.track' | 'jam.sample-pack'
  | 'jam.sample' | 'jam.clock-calibration' | 'jam.drum-track'
  | 'jam.pattern' | 'jam.arrangement'
  // added in phase A
  | 'jam.rack'
  | 'jam.macro'
  | 'jam.clip'
  | 'jam.scene'
  | 'jam.take'
  | 'jam.contribution'
  | 'jam.player'
  | 'jam.gesture'
  | 'jam.mapping'
  | 'jam.permission';
```

Each new kind is given a linearity class:

| Kind              | Linearity | Reason                                                                 |
| ----------------- | --------- | ---------------------------------------------------------------------- |
| `jam.rack`        | linear    | A rack instance is a singleton in a world slot; forking copies it.     |
| `jam.macro`       | debug     | Read-modify-write of a 0..1 value; not a lifecycle object on its own.  |
| `jam.clip`        | affine    | A clip can be unrecorded → recorded → muted; can be dropped.           |
| `jam.scene`       | affine    | Scenes can be edited or removed; not consumed.                         |
| `jam.take`        | linear    | A take is a once-only capture; promotion does not consume it.          |
| `jam.contribution`| relevant  | Contributions accrete; you cannot lose them once recorded.             |
| `jam.player`      | affine    | A player can join/leave; identity is the linear part, not the player.  |
| `jam.gesture`     | debug     | Transient performance event.                                           |
| `jam.mapping`     | linear    | A mapping installation owns its slot; forking creates a new mapping.   |
| `jam.permission`  | linear    | Permission grant is a definite, revocable token.                       |

### A.2 Rack contract

```ts
// apps/world-apps/jam-room/src/racks/contract.ts (new)

export type JamRackEngine =
  | 'webaudio' | 'puredata' | 'strudel' | 'midi' | 'hybrid';

export interface JamNoteOn   { kind: 'note.on';  pitch: number; velocity: number; voiceId?: string; time?: number; humanise?: number; source?: string }
export interface JamNoteOff  { kind: 'note.off'; pitch: number; voiceId?: string; time?: number }
export interface JamTrigger  { kind: 'trigger';  voiceId: string; velocity: number; probability?: number; microOffset?: number; ratchet?: number; flam?: number; condition?: string; time?: number }
export interface JamStop     { kind: 'stop';     reason: 'panic' | 'transport' | 'user' }

export interface JamMeters   { peakL: number; peakR: number; rmsL: number; rmsR: number; cpu?: number }

export interface JamMappingHint {
  inputType: 'pad' | 'key' | 'knob' | 'fader' | 'touch' | 'gamepad';
  /** Stable target id understood by the rack */
  target: string;
  /** Suggested label for surface feedback */
  label: string;
  /** 0..1 if continuous, undefined if discrete */
  range?: [number, number];
}

export interface JamRackState { presetId?: string; macros: number[]; engineState: unknown }

export interface JamRack {
  readonly id: string;
  readonly name: string;
  readonly engine: JamRackEngine;

  play(event: JamNoteOn | JamTrigger): void;
  stop(event: JamNoteOff | JamStop): void;
  setMacro(index: number, value: number): void; // 0..7, value 0..1
  setPreset(presetId: string): void;
  getState(): JamRackState;
  setState(state: JamRackState): void;
  getMeters(): JamMeters;
  getMappingHints(): JamMappingHint[];
}
```

### A.3 Macro vocabulary

The eight default macros are **musical names** with documented
intentional fan-out per rack family. Engine adapters declare their own
fan-out tables.

```
0  brightness   high-shelf gain | filter cutoff      | spectral tilt
1  dirt         drive | bitcrush | saturator         | wavefolder
2  wobble       LFO depth | filter mod | rate stir   | mod-wheel mirror
3  space        reverb send | early-reflection time  | size
4  snap         envelope attack ↘ | transient gain ↗
5  body         low-shelf gain | sub mix | compressor make-up
6  chaos        constrained random source for the rack
7  tension      filter ↘ + resonance ↗ + sidechain ↗ + pitch drift
```

Macro names ARE the contract; phase C's mapping editor and phase D's
engine bridges both rely on the same eight names being meaningful.

### A.4 Event-cell families

```
jam.input.pad        { surfaceId, x, y, pressure, velocity, aftertouch, ts, mode, target }
jam.input.knob       { surfaceId, index, value, delta, target }
jam.input.key        { surfaceId, keyCode, value, target }
jam.input.fader      { surfaceId, index, value, target }
jam.input.touch      { surfaceId, x, y, pressure, area, target }
jam.input.gamepad    { surfaceId, axisOrButton, value, target }

jam.clock.tick       { roomTime, beat, bar, bpm }
jam.clock.start      { roomTime }
jam.clock.stop       { roomTime }
jam.clock.nudge      { ms }

jam.note.on          { rackId, pitch, velocity, voiceId?, ts, gestureId? }
jam.note.off         { rackId, pitch, voiceId?, ts }
jam.note.expression  { rackId, voiceId, parameter, value }
jam.trigger          { rackId, voiceId, velocity, probability?, microOffset?, ratchet?, ts }
jam.control.change   { target, value, curve?, ts, gestureId? }
jam.control.gesture  { gestureId, kind, params, ts }

jam.pattern.step.toggle        { patternId, lane, step, on }
jam.pattern.step.setVelocity   { patternId, lane, step, velocity }
jam.pattern.step.setProbability{ patternId, lane, step, probability }
jam.pattern.lane.select        { patternId, lane }

jam.clip.arm                   { clipId, owner }
jam.clip.record.start          { clipId, ts }
jam.clip.record.stop           { clipId, ts }
jam.clip.launch.queue          { clipId, quantum, ts }
jam.clip.stop.queue            { clipId, quantum, ts }
jam.scene.launch               { sceneId, quantum, ts }

jam.arrangement.section.add    { arrangementId, section }
jam.arrangement.section.move   { arrangementId, sectionId, to }
jam.arrangement.section.resize { arrangementId, sectionId, lengthBars }
jam.arrangement.take.capture   { arrangementId, takeId, range }
jam.arrangement.take.promote   { arrangementId, takeId }

jam.rack.macro.set             { rackId, index, value }
jam.rack.preset.load           { rackId, presetId }
jam.rack.state.save            { rackId, stateHash }

jam.mapping.install            { mappingId, surfaceId }
jam.mapping.uninstall          { mappingId, surfaceId }
jam.mapping.fork               { fromMappingId, toMappingId }

jam.room.player.join           { playerId }
jam.room.player.leave          { playerId }
jam.room.broadcast.statePatch  { hash, range }
```

Every cell carries the standard `SemanticObjectHeader` envelope plus
the family payload above. Existing cells emitted by `audio.ts` and
`sequencer.ts` are migrated to these families behind the scenes; the UI
behaviour does not change.

### A.4b `JamboxWorldPayload` extensions for compression + colour

Two design notes folded back into Phase A as optional fields on the
existing `JamboxWorldPayload` (no new kinds, no breaking changes):

```ts
export interface JamboxWorldPayload {
  // existing fields ...

  /** Renderer guidance for the CSD compression gradient. */
  viewportPlan?: ViewportPlan;
  /** Selected colour palette for the scale channel (Phase B Note mode). */
  palette?: 'boomwhacker' | 'newton' | 'scriabin';
  /** Default label mode for melodic surfaces. */
  labelMode?: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering';
}

export interface ViewportPlan {
  surfacedLayers: ('L1' | 'L2' | 'L3' | 'L4')[];
  placements: {
    anchor: 'top-band' | 'hero' | 'sticky-top';
    active: 'left-wall' | 'tab-row' | 'bottom-tab-bar';
    support: 'right-wall' | 'bottom-sheet' | 'overflow-menu';
    infrastructure: 'hover-hud' | 'hidden';
  };
  activeSlots: { rhythm: string; melody: string; bassline: string };
}
```

Three default plans (`desktopPlan`, `tabletPlan`, `mobilePlan`) ship as
constants in a new module `src/world/viewport-plans.ts`. Defaults for
`palette` and `labelMode` are `'boomwhacker'` and `'off'`.

The full design rationale is in
[`design/CSD-COMPRESSION-GRADIENT.md`](./design/CSD-COMPRESSION-GRADIENT.md)
and [`design/COLOUR-AS-DIMENSION.md`](./design/COLOUR-AS-DIMENSION.md).
Phase A only ships the *types and defaults* so Phase B (mode row,
Note mode colour) and Phase G (responsive web, Flutter shell) have a
stable contract to render against. **No UI behaviour changes in
Phase A.**

### A.4c Scale-colour module (pure, no renderer)

A new pure module `src/colour/scale-colour.ts` exports the deterministic
scale-classification + colour functions used by every melodic surface
in later phases:

```ts
export type ScalePalette = 'boomwhacker' | 'newton' | 'scriabin';
export type ScaleClass   = 'root' | 'in-scale' | 'modal' | 'chromatic';

export interface ScaleColourSpec {
  hue: number;          // 0-360
  saturation: number;   // 0-1
  brightness: number;   // 0-1
  border?: 'gold-ring' | 'modal-tick' | 'chromatic-edge';
  label?: string;
}

export function classifyPitch(
  pitch: number, scale: ScaleId, root: number,
): ScaleClass;

export function colourForPitch(
  pitch: number, scale: ScaleId, root: number,
  palette: ScalePalette,
  labelMode: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering',
): ScaleColourSpec;
```

Phase A ships the **module**; Phase B is the first consumer (Note
mode pads). Shipping the module here is a deliberate parallelism move:
designers can iterate on Note-mode visuals against `colourForPitch`
fixture data while system work on Phase B's mode-row scaffolding
proceeds in parallel.

### A.5 Default rack instances

Phase A wires four `JamRack` instances around the existing
`audio.ts` engine:

| Rack id              | Engine     | Voice list                                          | Source                                         |
| -------------------- | ---------- | --------------------------------------------------- | ---------------------------------------------- |
| `jam.rack.drum-808`  | webaudio   | kick / snare / hat / clap / cb / tom / sub / perc / shaker | wraps existing drum path in `audio.ts`  |
| `jam.rack.acid-303`  | webaudio   | acid lead                                           | wraps `playAcid` in `audio.ts`                 |
| `jam.rack.bass-mono` | webaudio   | bass                                                | wraps existing bass synth path                 |
| `jam.rack.poly-keys` | webaudio   | lead                                                | wraps the existing keys / arp module           |

Each rack exposes 8 macros (page 1) using the canonical macro vocabulary.

---

## Deliverables

### D-A.1 — Semantic kinds added to `objects.ts`

- Extend `JamboxObjectKind` with the 9 new kinds.
- Add `JamboxRackPayload`, `JamboxClipPayload`, `JamboxScenePayload`,
  `JamboxTakePayload`, `JamboxContributionPayload`, `JamboxPlayerPayload`,
  `JamboxGesturePayload`, `JamboxMappingPayload`, `JamboxPermissionPayload`,
  `JamboxMacroPayload`.
- Add factory functions `createRack`, `createClip`, `createScene`,
  `createTake`, `createContribution`, `createPlayer`, `createGesture`,
  `createMapping`, `createPermission` mirroring the existing
  `createDrumTrack` / `createPattern` / `createArrangement` style.
- Each new factory emits the correct linearity per the table in §A.1.

### D-A.2 — `JamRack` contract

- Create `apps/world-apps/jam-room/src/racks/contract.ts` with the
  interface from §A.2.
- Create `apps/world-apps/jam-room/src/racks/registry.ts` — an in-memory
  registry of rack instances keyed by `rackId`.
- Add type tests: every event payload type must compile when piped to
  the corresponding rack method.

### D-A.3 — Default WebAudio racks

- Create `apps/world-apps/jam-room/src/racks/webaudio/{drum808,acid303,bassMono,polyKeys}.ts`.
- Each implements `JamRack` and forwards into existing `audio.ts`
  functions. **No new audio code.**
- Each declares its 8 macros with the canonical names from §A.3 and
  documents its fan-out table in JSDoc.

### D-A.4 — Event-cell family canonicalisation

- Add `apps/world-apps/jam-room/src/semantic/events.ts` exporting the
  full event-family type union from §A.4.
- Migrate `src/grid/surface.ts` to emit `jam.input.pad` instead of
  ad-hoc structures. Existing PadPressEvent stays as the *internal*
  shape; the *emitted* event is canonical.
- Migrate `src/sequencer.ts` step toggles to emit
  `jam.pattern.step.toggle` etc.
- Migrate `src/core/beam-clock.ts` beat callback to emit `jam.clock.tick`.

### D-A.5 — Linearity propagation

- Update `src/semantic/objects.ts`'s linearity defaults so the new
  kinds match the table in §A.1.
- Add a unit test asserting that `createRack` produces `linear`,
  `createClip` produces `affine`, etc.

### D-A.6 — Migration of existing in-flight cells

- Existing `jam.drum-track`, `jam.pattern`, `jam.arrangement` factories
  receive an optional `racks` field referencing rack ids so an existing
  pattern can declare which rack it plays through.
- Backward-compat: factories without `racks` default to
  `jam.rack.drum-808` / `jam.rack.poly-keys` based on `voiceType`.

### D-A.7 — `viewportPlan` + palette/labelMode

- Extend `JamboxWorldPayload` per §A.4b.
- New `src/world/viewport-plans.ts` exporting `desktopPlan`,
  `tabletPlan`, `mobilePlan` constants.
- World-factory tests confirm a created `jam.world` carries one of
  the three default plans by default (auto-picked from the boot
  viewport size; `mobilePlan` for ≤ 600 px, `tabletPlan` for
  601–1024 px, `desktopPlan` for > 1024 px).

### D-A.8 — Scale-colour module

- New pure module `src/colour/scale-colour.ts` per §A.4c.
- Snapshot tests covering: pentatonic / major / minor / dorian /
  phrygian × C / G / F roots × all 12 chromatic pitches.
- Boomwhacker default palette spec'd to exact sRGB values; alternate
  palettes (`newton`, `scriabin`) shipped behind feature flags but
  passing the same snapshot harness.

### D-A.9 — Phase A gate test

- `apps/world-apps/jam-room/__tests__/phase-a-gate.test.ts`:
  - All new kinds round-trip through `JamboxSemanticObject<TPayload>`
    serialisation.
  - All four default racks satisfy the `JamRack` contract via a
    structural type-check fixture.
  - Macro index is clamped to `[0,7]` and value to `[0,1]`.
  - Linearity matches the table in §A.1.
  - The five existing surface modes (`global`, `step`, `param`,
    `session`, `arrangement`) still emit canonical
    `jam.input.pad` cells.
  - `JamboxWorldPayload` accepts and round-trips `viewportPlan`,
    `palette`, `labelMode`. Defaults applied per §A.4b.
  - `colourForPitch` snapshots match for the documented palette ×
    scale × root matrix.

---

## Gate tests (commands)

```bash
# Type-check
pnpm -C apps/world-apps/jam-room typecheck

# Phase A gate
pnpm -C apps/world-apps/jam-room test --filter phase-a-gate

# No regressions in existing surface
pnpm -C apps/world-apps/jam-room test
```

All three must pass with zero warnings.

---

## Completion criteria

1. `JamboxObjectKind` lists all 22 kinds (13 existing + 9 new).
2. `JamRack` contract type-checks and the four default racks satisfy it.
3. Existing 8×8 surface continues to play sound with no UI change; user
   can still capture a 4-bar loop end-to-end.
4. Every cell emitted from the surface, sequencer, and clock maps to one
   of the documented event-cell families in §A.4.
5. `pnpm test` is green; phase-a-gate passes.
6. README in `src/racks/` documents the four starter racks and how to
   add a fifth.

---

## Risks & mitigations

| Risk                                                           | Mitigation                                                                                  |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Rack contract too WebAudio-shaped                              | Phase D will stress-test with Strudel + PureData; D-A.2 reviews the contract against §C.    |
| Cell-family migration breaks BEAM relay format                 | Migration only renames *envelope*; payload bytes are identical for existing cells.          |
| `jam.macro` overlaps with per-track FX in `audio.ts`           | Macros fan **out** to existing FX functions; FX functions remain the source of truth.       |
| Linearity classes wrong for `jam.contribution`                 | `relevant` chosen so contributions accrete; reviewed in phase F before take promotion.      |

---

## Non-goals (explicit)

- No UI changes. Mode row, Note mode, Mix mode = phase B.
- No Strudel / PureData engine. = phase D.
- No mapping editor. = phase C.
- No 3D affordances. = phase E.
- No take *capture*. = phase F. (The `jam.take` *type* is defined here.)
- No mobile renderer. = phase G. (Phase A ships the `viewportPlan`
  *contract* so phase G's renderer has something to read.)
- No scale-channel rendering. = phase B. (Phase A ships the
  `colourForPitch` *function* so phase B's Note mode has something to
  call.)

## Parallelism note

Phase A is the only phase that **must** ship before any other phase
starts. Two of its deliverables (D-A.7 viewport plans, D-A.8 scale
colour) exist primarily to unlock parallel design + system work
downstream:

- Designers can iterate Note-mode pad visuals against
  `colourForPitch` snapshot data without waiting for Phase B's mode
  row to land.
- Designers can iterate the L1 anchor card / L2 tab bar against
  `mobilePlan` constants without waiting for Phase G's Flutter shell
  to scaffold.

The rule of thumb: **system PRs land contracts; design PRs land
visuals against those contracts; both sides can move in parallel
once the contract is merged.**
