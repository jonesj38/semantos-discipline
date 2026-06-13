---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.781698+00:00
---

# Phase A Execution Prompt — Jam Room Vocabulary + JamRack Contract

> Paste this prompt into a fresh session to execute Phase A.

## Context

You are working in the `semantos-core` repo, specifically in
`apps/world-apps/jam-room/`. The jam-room is a real working surface:
8×8 grid with five Push-3 modes, a 13-track sequencer with 16/32/64
zoom and four scenes, a 1089-line WebAudio engine, a BEAMClock NTP-style
sync layer, a Three.js room projection, and rekordbox/splice importers.
The semantic-objects file already defines thirteen `jam.*` kinds.

Phase A is the **plumbing phase**. It does not change the UI. It adds
the missing semantic kinds (`jam.rack`, `jam.macro`, `jam.clip`,
`jam.scene`, `jam.take`, `jam.contribution`, `jam.player`,
`jam.gesture`, `jam.mapping`, `jam.permission`), the `JamRack` runtime
contract, and the event-cell families that every later phase depends
on. Four default WebAudio racks wrap the existing audio path so no
audio code is rewritten.

Your task is Phase A. The five existing surface modes must keep working
exactly as they do now; only the *emitted* cell shapes change to be
canonical.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.
These are the real implementations you will build on. If you haven't
read them, you will miss architectural dependencies.

**Read first** (the PRD and master document):

- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — Phase A spec
  with vocabulary delta, JamRack contract, event-cell families,
  deliverables D-A.1–D-A.7, gate tests, completion criteria.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context: what already
  exists, the primitive rack at a glance, success metric.

**Read second** (the primary implementation targets — these are what
you will extend, not replace):

- `apps/world-apps/jam-room/src/semantic/objects.ts` — Existing 13-kind
  union, `JamboxSemanticObject<T>` envelope, `SemanticObjectHeader`,
  factory pattern (`createDrumTrack`, `createPattern`,
  `createArrangement`, etc.). **Match this style exactly.**
- `apps/world-apps/jam-room/src/audio.ts` — The WebAudio engine you
  will wrap into four racks. Look for `playDrum`, `playNote`, `playFmNote`,
  `playSquareNote`, `playPulseNote`, `playSubNote`, `playEpianoNote`,
  `playPadNote`, `playAcid`, `playSample`, `setTrackFilter`,
  `setTrackReverb`, `setTrackDelay`, `setTrackDrive`, `setTrackBitcrush`,
  `setTrackSidechain`. These are your fan-out targets for the eight macros.
- `apps/world-apps/jam-room/src/sequencer.ts` — `TRACK_NAMES`,
  `TRACK_KIND`, `Cell`, `Grid`, `Scene`, `StepCount`. The migration in
  D-A.4 changes the cells emitted on step toggle, not these types.
- `apps/world-apps/jam-room/src/grid/surface.ts` — `PadPressEvent`,
  `GridModeKind`, the five modes. `PadPressEvent` stays as the internal
  shape; you add canonical `jam.input.pad` emission alongside it.
- `apps/world-apps/jam-room/src/core/beam-clock.ts` — `BEAMClock`,
  `BeatInfo`. Beat callback emits `jam.clock.tick`.
- `apps/world-apps/jam-room/src/semantic/importers.ts` — Reference for
  factory style; do not change it.

**Read third** (cell-engine plumbing you must respect, not modify):

- `core/cell-engine/` — Linearity classes (`linear`, `affine`,
  `relevant`, `debug`). Match `JamboxLinearity` to these.
- `packages/world-sdk/src/relay/client.ts` — How cells are sent to the
  CellRelay. New event-cell families ride this same client unchanged.

**Read fourth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `jam-room-a-vocabulary`,
  commits as `jam-room-a/D-A.{N}: ...`. Gate test path:
  `apps/world-apps/jam-room/__tests__/phase-a-gate.test.ts`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO NEW AUDIO CODE

Phase A wraps the existing `audio.ts` engine. You do not add a single
new oscillator, filter, or reverb path. The four default racks call
**existing** functions in `audio.ts`. If you find yourself reaching for
`new OscillatorNode`, you are in the wrong phase.

### 2. NO UI CHANGES

This phase is invisible to the user. The grid surface, sequencer card,
mixer card, jambox-world canvas, and import panel all behave exactly as
they do today. Only the *cells emitted to the room channel* change
shape — the surface UI is untouched.

### 3. MACROS ARE MUSICAL NAMES

The eight macros are `brightness`, `dirt`, `wobble`, `space`, `snap`,
`body`, `chaos`, `tension`. You do not invent new macro names. You do
not expose raw DSP names like `osc1_fm_mod_depth_raw`. If a rack cannot
fan out to one of the eight names meaningfully, document that the macro
is no-op for that rack — do not rename the macro.

### 4. EVERY NEW KIND DECLARES LINEARITY

The PRD's §A.1 table is law. `jam.rack` is `linear`, `jam.contribution`
is `relevant`, `jam.gesture` is `debug`, etc. The factory test in
D-A.5 will fail if you guess.

### 5. EVENT FAMILIES ARE FROZEN

The list in §A.4 is the complete set of cell families this phase
introduces. You do not add `jam.input.eyeTrack` or `jam.clip.uplift` or
anything else not in the list. Phases B–F may add more; phase A may not.

### 6. EXISTING CELLS KEEP WORKING

Anyone running the jam-room from before this phase must still see every
existing cell parse correctly. Migration of `surface.ts`, `sequencer.ts`
and `beam-clock.ts` is *additive*: emit canonical events alongside
existing event paths until the gate test confirms parity, then remove
the old emission inside the same PR.

### 7. NO PHASE-B/C/D/E/F/G WORK

You will be tempted to add a Note-mode surface (B), a mapping editor
(C), a Strudel adapter (D), a take-recorder (F), or a Flutter shell
(G). Do none of these. The deliverable list is the deliverable list.

### 8. THE TWO PARALLELISM DELIVERABLES ARE CONTRACT-ONLY

D-A.7 (`viewportPlan`) and D-A.8 (`scale-colour` module) exist so
designers can render visuals against fixture data while system work
proceeds. **Ship the types, the constants, and the pure function;
do not ship a renderer that consumes them.** No CSS, no DOM updates,
no Note-mode pad colours in this phase. The renderer arrives in
Phase B. If you find yourself editing `style.css` or
`grid/surface.ts` colour rules, you are in the wrong phase.

---

## Deliverable mapping

| ID    | File(s) you create or change                                                              |
| ----- | ----------------------------------------------------------------------------------------- |
| D-A.1 | `apps/world-apps/jam-room/src/semantic/objects.ts` (extend union + 9 new factories)       |
| D-A.2 | `apps/world-apps/jam-room/src/racks/contract.ts`, `src/racks/registry.ts` (new)           |
| D-A.3 | `apps/world-apps/jam-room/src/racks/webaudio/{drum808,acid303,bassMono,polyKeys}.ts`      |
| D-A.4 | `apps/world-apps/jam-room/src/semantic/events.ts` (new); migrate `grid/surface.ts`, `sequencer.ts`, `core/beam-clock.ts` |
| D-A.5 | Linearity defaults in `objects.ts` + unit test                                            |
| D-A.6 | Optional `racks` field on existing factories                                              |
| D-A.7 | `JamboxWorldPayload` extension (`viewportPlan`, `palette`, `labelMode`); `src/world/viewport-plans.ts` (new) |
| D-A.8 | `src/colour/scale-colour.ts` (new) with snapshot tests                                    |
| D-A.9 | `apps/world-apps/jam-room/__tests__/phase-a-gate.test.ts`                                 |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-a-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

All four must pass with zero warnings before merge.

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-a-vocabulary
```

Commit prefix: `jam-room-a/D-A.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.3.0`.

---

## Definition of done

1. The 22-kind union compiles (13 existing + 9 new).
2. `JamRack` contract is in `src/racks/contract.ts`; four default
   WebAudio racks satisfy it.
3. The five surface modes still play sound and capture loops exactly as
   they did before this phase.
4. Every cell leaving the jam-room over the cell-relay channel maps to
   one of the families in §A.4 of the PRD.
5. `JamboxWorldPayload` carries `viewportPlan`, `palette`, `labelMode`
   with documented defaults; `src/world/viewport-plans.ts` exports
   the three plan constants.
6. `src/colour/scale-colour.ts` exports `classifyPitch` and
   `colourForPitch`; snapshot tests cover the documented matrix.
7. `phase-a-gate.test.ts` passes.
8. `src/racks/README.md` exists and documents how to add a fifth rack.
9. No file in `src/three/`, `src/instruments/keys.ts`,
   `src/instruments/arp.ts`, `src/grid/surface.ts` colour rules, or any
   UI HTML/CSS file has been modified.

---

## What to **not** do

- Don't rename existing kinds. `jam.drum-track` stays. The new kinds
  *augment* the union; they do not replace anything.
- Don't change the BEAM relay protocol. The new event-cell families
  ride the same WS client unmodified.
- Don't ship a mapping editor or BYO mapping import. That's phase C.
- Don't load Strudel or libpd. That's phase D.
- Don't introduce a "take recorder" UI. That's phase F.
- Don't add CI workflow files; the existing CI picks up the new gate
  test by path convention.
