---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-B-MODES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.780880+00:00
---

# Phase B — Jam Room Modes Consolidation: Note + Mix + Drum/Step Refinement

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 1.5–2 weeks
**Prerequisites**: Phase A merged (`jam.rack`, `jam.clip`, `jam.scene`, `jam.macro` available; canonical event-cell families in place).
**Branch prefix**: `jam-room-b-modes`
**Master document**: `MASTER.md`

---

## Context

Phase A made the surface emit canonical cells but did not change what
the user sees. The grid still has five modes (`global`, `step`, `param`,
`session`, `arrangement`) and two of the modes the brief calls for —
**Note** (musical playing) and **Mix** (track strips) — do not exist.
The drum/step modes work but are not yet aware of the Phase A
`jam.clip` / `jam.scene` / `jam.rack` primitives, so the existing
session view treats scenes as the integer 0–3 the sequencer carries.

Phase B closes that gap. After this phase the user has a visible
**anchor row + 3 active mode buttons + a 5-entry support sheet**
(per the Conscious Stack 1-3-5-3-1 discipline), can play melodies in
Note mode without wrong notes, can mix tracks live in Mix mode, and
the existing drum/step/session/arrangement modes are quietly upgraded
to read and write the new clip/scene/rack objects. Note mode picks
up the Phase A scale-colour module so pads are coloured by scale
degree, modal characteristic notes get visual emphasis, and the
"no wrong notes" guarantee is enforced visually as well as audibly.

This phase folds two design notes back into the build:

- [`design/CSD-COMPRESSION-GRADIENT.md`](./design/CSD-COMPRESSION-GRADIENT.md)
  — the 1-3-5-3-1 pyramid the mode row honours.
- [`design/MODE-ROW-REVISION.md`](./design/MODE-ROW-REVISION.md) —
  the anchor + 3 active + 5 support shape, replacing the eight-button
  proposal in earlier drafts of this PRD.
- [`design/COLOUR-AS-DIMENSION.md`](./design/COLOUR-AS-DIMENSION.md)
  — the orthogonal colour channel for scale degree, mode, root, and
  scale-lock semantics that Note mode adopts as default behaviour.

### What this phase is not

- Not BYO mapping. Surface-side mode router is fixed; phase C lets
  users redirect external controllers into modes.
- Not 3D. Mode row lives in the existing workbench card pool; the
  jambox-world canvas is unchanged.
- Not engine work. Note mode plays through the Phase A racks.
- Not the mobile renderer. Phase G ships the responsive layout. Phase
  B's mode row is shaped so phase G doesn't have to redesign it; the
  same anchor + 3 active + sheet structure compresses cleanly.

---

## Architecture

### B.1 Anchor row + 3 active modes + 5 support sheet

The Conscious Stack discipline applies. Three regions:

**Anchor row** (always visible, top — L1):

```
┌──────────────────────────────────────────────────────────┐
│  ▶  120 bpm   ◇ scene A     ⏺ rec    ⌃ capture           │
└──────────────────────────────────────────────────────────┘
```

Carries play/stop, tempo (read on mobile, tap-to-edit), active scene
indicator (the L1 jam.scene object made visible), record, and capture
(Phase F's affordance pinned because it's used so often). The anchor
row is the only transport surface on mobile.

**Mode row** (3 active L2 buttons):

```
┌──────────────┬──────────────┬──────────────┐
│   RHYTHM     │   MELODY     │     BASS     │
│   (Drum)     │  (Note/Mix)  │  (Bass/Mix)  │
└──────────────┴──────────────┴──────────────┘
```

Each button carries **rack focus + default mode**:

| L2 button | Default mode               | What it shows                                    |
| --------- | -------------------------- | ------------------------------------------------ |
| Rhythm    | Drum / Step                | 8×8 step sequencer for the selected drum rack    |
| Melody    | Note (scale layout)        | Scale-locked melodic grid for the selected lead  |
| Bass      | Note (bassline layout) + Mix peek | Two-octave bass layout + volume strip      |

A second tap on the same L2 button cycles its **secondary mode** —
e.g. Rhythm tap-tap = Drum → Sequencer (param view); Melody tap-tap =
Note (scale) → Note (chord). Cycling state shows as a small dot under
the button.

**Support sheet** (5 entries, gated):

```
┌────────────────────────────┐
│  ⌗  Sequencer (full grid) │
│  ◧  Mix (full track strips)│
│  ⊞  Session (clip launcher)│
│  ⊐  Arrange (timeline)     │
│  ✦  Custom (BYO mapping)   │
└────────────────────────────┘
```

Open via right-edge swipe on touch, click overflow on desktop, or
press the top-row support pad on hardware. A second L2 button
long-press also opens the support sheet pre-scoped to that rack.

Custom is enabled after Phase C ships. In phase B it remains in the
sheet but disabled with the "available after BYO Mappings phase"
tooltip.

### B.1b Why this passes the Sincerity Filter

| Old slot     | Where it goes after the revision                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------ |
| Play         | Anchor row. Transport is L1, not L2.                                                                   |
| Drum         | "Rhythm" L2 button.                                                                                    |
| Note         | "Melody" L2 button. Sub-layouts (scale / iso-fourths / chord) live inside the rack pod, not the row.   |
| Session      | Support sheet entry #3.                                                                                |
| Sequencer    | Support sheet entry #1.                                                                                |
| Arrange      | Support sheet entry #4.                                                                                |
| Mix          | Two ways — "Mix peek" (volume + send-A) inline on Bass + Melody L2 pods; full FX rows in support #2.   |
| Custom       | Support sheet entry #5.                                                                                |

The user lands with three obvious actions. The advanced surface is
one swipe away. Working memory holds the trinity, not the eight.

### B.2 Note mode

```
GridModeKind = ... | 'note'
```

Layouts (chosen inside the **rack pod**, not the mode row — see B.1):

1. **scale** — rows are octave moves; columns are scale steps. Tap =
   note on; release = note off; pressure (touch) = aftertouch via
   `jam.note.expression`. Default for the Melody L2 button.
2. **iso-fourths** — isomorphic fourths layout (Linnstrument style).
3. **chord** — each pad is a triad on the current scale degree.
4. **bassline** — bottom two rows are two-octave bass; top six rows
   are accent / slide / probability dropdowns. Default for the Bass
   L2 button.

Defaults: scale = pentatonic (already in the toolbar dropdown), root =
C, octave = 3. Held notes latch on double-tap (`jam.note.expression`
`{ parameter: 'latch', value: 1 }`).

All four layouts emit canonical `jam.note.on` / `jam.note.off` /
`jam.note.expression` cells. The active rack is the **selected**
melodic rack from the rack registry; if none is selected,
`jam.rack.poly-keys` (Phase A default) is used.

#### B.2a Scale-channel colour (folded in from `design/COLOUR-AS-DIMENSION.md`)

Note-mode pads are coloured by **two orthogonal channels**:

```
visualColour(pad) = blend(
  trackChannel(pad),    // existing PadColor — track / clip-state / mode
  scaleChannel(pad)     // new — scale-degree colour from Phase A's
                        //       colourForPitch
)
```

Track channel drives **hue**; scale channel drives **saturation,
brightness, border, label**. The two channels never compete for the
same attribute.

| Class     | Saturation | Brightness | Border       | Label                       |
| --------- | ---------- | ---------- | ------------ | --------------------------- |
| root      | full       | full       | gold ring    | "1" or note name            |
| in-scale  | full       | full       | none         | scale degree (2, 3, 4, 5...)|
| modal     | full       | full       | white tick ◊ | degree + ◊                  |
| chromatic | low (0.3)  | low (0.4)  | none         | (none unless lock off)      |

Default palette is `'boomwhacker'` from `JamboxWorldPayload.palette`.
Default label mode is `'off'` from `JamboxWorldPayload.labelMode`; a
toggle in the rack pod cycles `off → number → solfege → note-name →
fingering`.

#### B.2b Scale lock

Scale lock is **on by default** — chromatic pads dim further to
`'off'` and emit a no-op (silent click + 600 ms border flash + label
flash) when pressed. This enforces the "no wrong notes" guarantee
visually as well as audibly.

A user can disable lock per-pod (rack-pod toggle); when disabled,
chromatic pads render at low saturation per the table above and emit
notes normally.

#### B.2c Mode-aware rebalancing

Switching scale rebalances the colour channel over a 200 ms
transition. Modal characteristic notes (Dorian raised 6, Phrygian
lowered 2) get the `◊` border and a brief pulse on first display.
Major drifts warmer; Phrygian drifts cooler.

#### B.2d Layout adapts to scale

Layout footprints change when the scale changes (folded from
`design/COLOUR-AS-DIMENSION.md` §6):

- **scale layout** — pentatonic = 5 columns × 8 rows (~3 octaves);
  major = 7 columns × 8 rows (~1 octave).
- **iso-fourths** — invariant tiling; in-scale pads bright, out-of-
  scale dim.
- **chord** — pentatonic = 5 chord pads; major = 7.
- **bassline** — bottom two rows fit ~16 in-scale degrees across two
  octaves regardless of scale.

#### B.2e Chord highlighting

Tap-and-hold a scale degree → triad lights up (root keeps gold ring;
3rd and 5th get connecting halo in same hue; 7th/9th/11th/13th pulse
at decreasing brightness). Long-press pins the chord lit until next
press.

### B.3 Mix mode

```
GridModeKind = ... | 'mix'
```

Grid layout:

```
Columns 0..7 = the eight visible tracks (or rack channels)
Row 0 = volume    (8 cells, brightness = level, swipe = adjust)
Row 1 = send A    (default: room reverb)
Row 2 = send B    (default: room delay)
Row 3 = mute      (single tap toggle, red when muted)
Row 4 = solo      (single tap toggle, yellow when soloed)
Row 5 = fx-1      (filter / cutoff)
Row 6 = fx-2      (drive)
Row 7 = fx-3      (bitcrush)
```

The right edge column is reserved for "all" (master volume / mute /
solo). Every adjustment emits `jam.rack.macro.set` (for the canonical
8 macros) or `jam.control.change` (for raw track FX). Existing
`audio.ts` `setTrackFilter` / `setTrackReverb` / `setTrackDelay` /
`setTrackDrive` / `setTrackBitcrush` / `setTrackSidechain` are wired
through.

### B.4 Drum / Step / Session / Arrangement upgrades

These modes already work. Phase B's upgrades:

| Mode        | Upgrade                                                                              |
| ----------- | ------------------------------------------------------------------------------------ |
| Drum        | Step toggle reads/writes the selected `jam.pattern` clip's bound `jam.rack`.         |
| Step (param)| Renamed Sequencer in the UI; param pads bind to the rack's macro index where present.|
| Session     | Each cell is a `jam.clip`; states (empty/armed/recording/queued/playing/muted) match the §4.4 spec in the brief; launches emit `jam.clip.launch.queue` + `jam.scene.launch`. |
| Arrangement | Section blocks reference `jam.scene` ids instead of integer scene 0–3.               |

The integer scene 0–3 stays as a fast-path fallback. New code prefers
`jam.scene` ids; old patterns auto-promote on first launch in this phase.

### B.5 Mode discipline

Mode is a property of the **surface instance**, not the user.
`surface.setMode(mode)` updates pad rendering and the active mode
contract. No mode allows raw pitch input in Drum mode and no mode
allows step toggles in Note mode — guardrails are enforced in
`grid/surface.ts`.

---

## Deliverables

### D-B.1 — Anchor row + mode row + support sheet

- New `apps/world-apps/jam-room/src/ui/anchor-row.ts` exporting
  `mountAnchorRow(host)` (transport + tempo + scene + record +
  capture).
- New `apps/world-apps/jam-room/src/ui/mode-row.ts` exporting
  `mountModeRow(host, surface)` with **3 L2 buttons** (Rhythm /
  Melody / Bass).
- New `apps/world-apps/jam-room/src/ui/support-sheet.ts` exporting
  `mountSupportSheet(host, surface)` with **5 entries** (Sequencer,
  Mix, Session, Arrange, Custom). Custom is disabled in this phase.
- Add `<section class="panel anchor-row" data-card="anchor-row">`,
  `<section class="panel mode-row" data-card="mode-row">`, and
  `<section class="panel support-sheet" data-card="support-sheet">`
  to `index.html` card pool.
- Active L2 button is filled colour; inactive dim. Sheet open via
  right-edge swipe (touch), overflow click (desktop), or
  long-press an L2 button (pre-scopes the sheet to that rack).
- Keyboard shortcuts: `1..3` for the three L2 buttons; `Shift+1..5`
  for support sheet entries; `Esc` closes the sheet.
- Tap-tap on an L2 button cycles its secondary mode; the cycle dot
  under the button shows current state.

### D-B.2 — Note mode (with scale-channel colour)

- Extend `GridModeKind` in `src/grid/surface.ts` with `'note'`.
- New `src/grid/note-mode.ts` exporting `renderNotePads(state, layout)`
  and `handleNotePress(event, state)`.
- Layout sub-selector lives **inside the rack pod** (scale /
  iso-fourths / chord / bassline). Default per L2 button is set by
  the mode row (Melody → scale; Bass → bassline).
- Default scale follows the existing toolbar `#scale` dropdown
  (pentatonic / major / minor / dorian / phrygian).
- **Pads consume `colourForPitch` from Phase A's
  `src/colour/scale-colour.ts`.** Track-channel drives hue;
  scale-channel drives saturation, brightness, border, and label per
  §B.2a.
- Scale lock is on by default per §B.2b; chromatic pads dim, no-op on
  press, brief border + label flash for 600 ms.
- Mode-aware rebalancing per §B.2c — 200 ms transition on scale change.
- Layout-by-scale per §B.2d.
- Chord highlight on tap-and-hold per §B.2e.
- Press emits `jam.note.on`; release emits `jam.note.off`; pressure /
  aftertouch (touch input) emits `jam.note.expression`.
- Label mode toggle in the rack pod cycles `off → number → solfege →
  note-name → fingering`. Default from `JamboxWorldPayload.labelMode`.

### D-B.3 — Mix: peek (inline) + full (support sheet)

Mix appears in two places:

- **Mix peek** — the bottom two rows of the Bass and Melody L2 rack
  pods carry volume + send-A only. Always visible when the L2 button
  is active. Drag = `jam.rack.macro.set`.
- **Mix (full)** — support sheet entry #2. Extends `GridModeKind`
  with `'mix'`; new `src/grid/mix-mode.ts` exports `renderMixPads(state)`
  and `handleMixPress(event, state)`. Full grid: volume / send-A /
  send-B / mute / solo / fx-1..3 per the table in §B.3. Swipe
  affordance for continuous adjustment. Adjustments emit
  `jam.rack.macro.set` for canonical macros, `jam.control.change`
  otherwise.

### D-B.4 — Session mode upgrade (support sheet entry #3)

Session moves to support but its handlers are upgraded the same way:

- Each cell in session view is a `jam.clip`. Tapping an empty cell
  emits `jam.clip.arm` + `jam.clip.record.start`; tapping an armed cell
  starts recording; tapping a playing cell emits `jam.clip.stop.queue`
  with the current `quantum`.
- Right-edge column is the scene launch column: tapping emits
  `jam.scene.launch`.
- Launch quantization defaults to 1 bar; transport's `swing` and
  `quantum` controls flow into the launch.

### D-B.5 — Arrangement mode upgrade (support sheet entry #4)

Arrangement moves to support but its handlers are upgraded the same way:

- Arrangement blocks reference `jam.scene` ids.
- Existing integer scene 0–3 auto-promotes to `jam.scene` objects on
  first arrangement-sheet entry per session.
- Drag a scene onto the timeline emits
  `jam.arrangement.section.add { sceneId, lengthBars }`.

### D-B.6 — Drum / Step (Sequencer) refinement

- Step toggle in drum mode emits `jam.pattern.step.toggle` referencing
  the selected pattern's bound `rackId`.
- Param pads bind to the rack's macro index when one matches the param
  name (e.g. `decay` → `snap` macro on `jam.rack.drum-808`); fall back
  to raw `jam.control.change` otherwise.

### D-B.7 — Mode-discipline guardrails

- `surface.setMode(mode)` validates allowed transitions; e.g. you cannot
  enter Mix-full without at least one rack registered.
- L2 button → default mode bindings enforced (Rhythm → Drum, Melody →
  Note-scale, Bass → Note-bassline).
- `surface.assertModeFor(event)` throws (in dev) if a mode-specific
  field is set on an event from the wrong mode. Production silently
  drops the field.
- Note mode chromatic guardrail: when scale-lock is on, presses on
  chromatic pads emit no audible event (silent no-op + 600 ms visual
  flash). Mappings (Phase C) can override per-input via
  `MappingConstraint { kind: 'requires-permission', value: 'chromatic' }`.

### D-B.8 — Anchor + L2 + sheet gate test

`apps/world-apps/jam-room/__tests__/phase-b-gate.test.ts`:

- Anchor row mounts; play/stop/record/capture buttons emit canonical
  cells.
- Mode row shows exactly 3 L2 buttons (Rhythm/Melody/Bass).
- Support sheet contains 5 entries in stable order
  (Sequencer/Mix/Session/Arrange/Custom). Custom is disabled.
- Tapping each L2 button switches `surface.mode` to its default mode
  (Rhythm→`step`, Melody→`note` scale layout, Bass→`note` bassline
  layout).
- Tap-tap on an L2 button cycles to the secondary mode.
- Long-press on an L2 button opens the support sheet pre-scoped to
  that rack.
- Note mode in scale layout: pressing pad (3, 4) on default pentatonic
  emits a `jam.note.on` with the correct pitch and the rendered pad
  carries the expected `colourForPitch` spec (root pad = gold ring).
- Note mode scale-lock: pressing a chromatic pad emits **no**
  `jam.note.on`, but the visual flash logs a `jam.input.pad` with the
  correct pad index.
- Note mode label mode cycle: toggling cycles `off → number → solfege
  → note-name → fingering` and back.
- Mix peek: dragging volume row in Bass L2 pod by ±0.2 emits a
  `jam.rack.macro.set` with the correct rackId and value.
- Mix-full (support): same dragging in the support sheet emits the
  same cells.
- Session view from support sheet: arming, recording, and launching a
  clip emit the four canonical cells in order.
- Phase A gate test re-runs and still passes.

---

## Gate tests (commands)

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-b-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

---

## Completion criteria

1. Anchor row visible; mode row visible with exactly 3 L2 buttons
   (Rhythm/Melody/Bass); support sheet gated and contains 5 entries.
2. Note mode produces musical phrases on first try with no wrong notes
   given a non-`debug` scale and scale-lock on.
3. Note mode pads carry the scale-channel colour from
   `colourForPitch`; root pads have the gold ring; modal pads carry
   the `◊` border.
4. Scale change animates the colour rebalance over ~200 ms; layout
   adapts per scale (5 columns pentatonic, 7 major).
5. Label mode toggle cycles through five options; default is `off` per
   `JamboxWorldPayload.labelMode`.
6. Mix peek (inline) and Mix-full (support sheet) both adjust volume /
   sends / mutes / solos / fx in real time on the existing audio
   engine.
7. Session view (from sheet) records and launches clips as `jam.clip`
   objects; arrangement view (from sheet) references `jam.scene`
   objects.
8. Drum / step modes still feel as fast as they did in phase A.
9. Phase A and Phase B gate tests pass.

---

## Risks & mitigations

| Risk                                                              | Mitigation                                                                                              |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Note mode latency feels worse than Drum mode                      | Note mode dispatches directly into the rack's `play()` (no scheduler hop). Phase A racks already wrap `audio.ts` synchronously. |
| Mix mode swipe conflicts with existing card-drag layout system    | Swipe handler attaches to pad elements only; layout drag handles attach to card chrome.                 |
| Auto-promoting scene 0–3 to `jam.scene` ids on first arrangement entry duplicates objects across sessions | Promotion is idempotent on `(roomId, sceneIndex)` — re-entering produces the same `jam.scene.id`. |
| Mode discipline guardrails break legacy ad-hoc events             | Dev-only assertion; production warn-and-continue.                                                       |

---

## Non-goals

- BYO mapping (= phase C).
- New audio engines (= phase D).
- 3D affordances (= phase E).
- Take capture (= phase F).
- Multi-page macros. Phase B sticks to page 1 (8 macros). Pages arrive
  if and when needed in a later phase.
