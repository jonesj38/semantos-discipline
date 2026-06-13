---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-B-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.779506+00:00
---

# Phase B Execution Prompt — Modes Consolidation: Note + Mix + Refinement

> Paste this prompt into a fresh session to execute Phase B.

## Context

You are working in `apps/world-apps/jam-room/`. Phase A has merged, so
the semantic vocabulary now contains `jam.rack`, `jam.macro`,
`jam.clip`, `jam.scene`, `jam.take`, `jam.contribution`, `jam.player`,
`jam.gesture`, `jam.mapping`, `jam.permission`, and the canonical
event-cell families. Four default WebAudio racks
(`jam.rack.drum-808`, `jam.rack.acid-303`, `jam.rack.bass-mono`,
`jam.rack.poly-keys`) are wired around the existing `audio.ts` engine.
The 8×8 surface still has the same five modes; the user-visible
behaviour has not changed since before Phase A.

Phase B is the **first user-visible phase**. After you finish, the
workbench has an **anchor row + 3 L2 mode buttons (Rhythm/Melody/Bass)
+ a 5-entry support sheet (Sequencer/Mix/Session/Arrange/Custom)**.
Note mode lets non-keyboard players play melodies in key, with pads
coloured by scale degree from Phase A's `colourForPitch` module
(scale-channel saturation/brightness/border/label, hue stays
track-driven). Mix peek sits inline on the Bass + Melody pods; full
Mix lives in the support sheet. Session and Arrangement modes are
demoted to support sheet entries but their handlers are quietly
upgraded against `jam.clip` and `jam.scene`.

This is the **Conscious Stack 1-3-5-3-1 mode row revision** — folded
in from `design/MODE-ROW-REVISION.md` and `design/COLOUR-AS-DIMENSION.md`.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD, design notes, and master document):

- `docs/prd/jam-room/PHASE-B-MODES.md` — Phase B spec with the
  revised anchor + 3 L2 + support sheet design (§B.1), Note mode +
  scale-channel colour (§B.2 + §B.2a–e), Mix peek vs full (§B.3),
  deliverables D-B.1–D-B.8, gate tests.
- `docs/prd/jam-room/design/MODE-ROW-REVISION.md` — Why the row is
  3 + 5, not 8.
- `docs/prd/jam-room/design/COLOUR-AS-DIMENSION.md` — Two-channel
  colour model, palettes, scale-lock semantics, layout-by-scale,
  label modes.
- `docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md` — Why this
  shape compresses to mobile cleanly (Phase G consumes it).
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context.
- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — The vocabulary
  + the new `colourForPitch` module + `viewportPlan` field. Phase B
  consumes; Phase A produced.

**Read second** (the surface and modes you will extend):

- `apps/world-apps/jam-room/src/grid/surface.ts` — Existing 5 modes,
  `PadState`, `PadPressEvent`, mode router. You add `'note'` and
  `'mix'` to `GridModeKind` and split the per-mode rendering into
  `note-mode.ts` and `mix-mode.ts`.
- `apps/world-apps/jam-room/src/sequencer.ts` — Track list, scale
  helpers, `isMelodic`, scenes, the 16/32/64 zoom. Note mode uses the
  current scale and root from this file (no duplication).
- `apps/world-apps/jam-room/src/audio.ts` — `setTrackFilter`,
  `setTrackReverb`, `setTrackDelay`, `setTrackDrive`, `setTrackBitcrush`,
  `setTrackSidechain`. Mix mode pads call these via the rack macros.
- `apps/world-apps/jam-room/src/racks/contract.ts` (Phase A) — Note
  mode dispatches `play()` on the selected rack; Mix mode calls
  `setMacro()` on the addressed rack.
- `apps/world-apps/jam-room/src/racks/registry.ts` (Phase A) — Use
  this to resolve "selected rack" / "rack by track index".
- `apps/world-apps/jam-room/src/colour/scale-colour.ts` (Phase A) —
  `classifyPitch` + `colourForPitch`. Note mode pads call this for
  every render; do not duplicate the logic.
- `apps/world-apps/jam-room/src/world/viewport-plans.ts` (Phase A) —
  Read the active plan to decide whether the support sheet is a
  bottom-sheet (mobile) or a right-side rail (desktop). The mode
  row + L2 buttons are identical across plans.
- `apps/world-apps/jam-room/index.html` — Existing card pool. Add the
  new `data-card="mode-row"` panel. Do not edit the workbench
  layout system itself; just declare a new card.
- `apps/world-apps/jam-room/style.css` — Match the existing pad colour
  vocabulary (`PadColor` set: `off | white | red | orange | yellow |
  green | cyan | blue | purple | pink | dim`).

**Read third** (cross-cutting):

- `apps/world-apps/jam-room/src/clip.ts` — The Clip type the legacy
  session view uses today. The Phase A `jam.clip` objects supersede it
  for the wire format; the in-memory Clip stays for fast access.
- `apps/world-apps/jam-room/src/main.ts` — Entry point. Confirm where
  the surface, transport, and card pool are mounted; do not refactor.
- `apps/world-apps/jam-room/src/instruments/keys.ts` and `arp.ts` —
  Reference for note-on / note-off in the existing keys module.

**Read fourth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `jam-room-b-modes`,
  commits as `jam-room-b/D-B.{N}: ...`. Gate test path
  `apps/world-apps/jam-room/__tests__/phase-b-gate.test.ts`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NOTE MODE NEVER PLAYS A WRONG NOTE BY DEFAULT

Scale-lock is **on by default**. With the default scale = pentatonic,
every pad in the active octave range is in key; chromatic pads dim and
emit a silent no-op + 600 ms visual flash on press. The chromatic
toggle is a per-rack-pod opt-in, not a top-level mode-row option. If
a fresh user can hit a wrong note in 30 seconds, the gate fails.

### 2. MIX MODE WIRES INTO RACK MACROS, NOT NEW DSP

Mix mode emits `jam.rack.macro.set` for the eight canonical macros and
`jam.control.change` for everything else. The fan-out into actual audio
is the Phase A rack's responsibility. Do not add new audio nodes in
Phase B.

### 3. INTEGER SCENE 0–3 IS A FAST PATH, NOT A SOURCE OF TRUTH

After Phase B, the source of truth for scenes is the `jam.scene`
object. The integer 0–3 in the existing sequencer remains as a
performance fast-path; promotion to `jam.scene` is idempotent on
`(roomId, sceneIndex)`.

### 4. NO MODE LEAKS

Drum mode does not emit `jam.note.on`. Note mode does not emit
`jam.pattern.step.toggle`. Mix mode does not emit `jam.trigger`. If
the wrong cell family is being emitted, the dev assertion in
`surface.assertModeFor(event)` must catch it. Add the assertion.

### 5. ANCHOR ROW REPLACES TOP-LEVEL TRANSPORT, BUT NOTHING IS LOST

The new anchor row carries play/stop/tempo/scene/record/capture. The
existing transport panel (sync drop, starter kit, swing, scale, voice,
zoom, anchor) keeps **all its controls** but is moved into the
support sheet under a new "Transport+" entry, OR shrinks to a
collapsible drawer attached to the anchor row. Either way, **no
control is dropped.** The Phase A migration tests must continue to
exercise every existing transport binding.

### 6. KEYBOARD SHORTCUTS DO NOT BREAK EXISTING ONES

The existing app already binds many keys (look at `main.ts`). The new
`1..3` (L2 buttons), `Shift+1..5` (support sheet), and `Esc` (close
sheet) shortcuts must check that no existing binding owns those keys.
If conflict: change the new binding, not the existing one.

### 7. SCALE-CHANNEL COLOUR ALWAYS CALLS `colourForPitch`

Note-mode rendering must consume `colourForPitch` from
`src/colour/scale-colour.ts` for every melodic pad. Do not duplicate
the classification logic, do not embed palette tables in
`note-mode.ts`. The single source of truth is the Phase A module.

### 8. NO PHASE-C/D/E/F/G WORK

Custom button is disabled with a tooltip. No mapping editor (C), no
Strudel/PD panel (D), no 3D loop orbs (E), no take capture (F), no
mobile/Flutter shell (G) in this phase.

---

## Deliverable mapping

| ID    | File(s) you create or change                                                                  |
| ----- | --------------------------------------------------------------------------------------------- |
| D-B.1 | `src/ui/anchor-row.ts`, `src/ui/mode-row.ts`, `src/ui/support-sheet.ts`; `index.html` cards   |
| D-B.2 | `src/grid/note-mode.ts` (consumes `colourForPitch`); extend `surface.ts` `GridModeKind`       |
| D-B.3 | `src/grid/mix-mode.ts` (full); inline mix-peek rows on Bass + Melody L2 pods                  |
| D-B.4 | Update `surface.ts` session-mode handlers (now triggered from sheet) to read/write `jam.clip` |
| D-B.5 | Update `surface.ts` arrangement-mode handlers (now triggered from sheet) for `jam.scene` ids  |
| D-B.6 | Update `surface.ts` drum/step handlers to bind to rack macros                                 |
| D-B.7 | Mode-discipline guardrails incl. scale-lock no-op flash + L2→default-mode bindings            |
| D-B.8 | `apps/world-apps/jam-room/__tests__/phase-b-gate.test.ts`                                     |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-b-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

The Phase A gate test must continue to pass.

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-b-modes
```

Commit prefix: `jam-room-b/D-B.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.4.0`.

---

## Definition of done

1. Anchor row + 3-button mode row + 5-entry support sheet all mounted;
   Custom disabled with tooltip.
2. Note mode: scale layout in pentatonic with root C plays in key on
   every pad with scale-lock on; chromatic pads silent + flash on
   press; iso-fourths, chord, bassline layouts work; pads carry
   `colourForPitch` rendering with root pad gold-ringed.
3. Mode-aware rebalancing: switching scale animates the colour
   transition over ~200 ms; layout adapts (5 columns pentatonic vs
   7 major).
4. Label modes: cycling through `off → number → solfege → note-name →
   fingering` works; default reads from `JamboxWorldPayload.labelMode`.
5. Mix peek (Bass + Melody pods) and Mix-full (support sheet) both
   adjust volume / sends / mutes / solos / fx in real time.
6. Session view from sheet: arming / recording / launching a clip
   emits the four canonical cells in order.
7. Arrangement view from sheet: dragging a scene onto the timeline
   creates a `jam.arrangement.section.add` cell with a real
   `jam.scene.id`.
8. Existing transport panel either preserved as a "Transport+"
   support sheet entry or as a collapsible anchor-row drawer; no
   binding lost.
9. Phase A and Phase B gate tests both pass.

---

## What to **not** do

- Don't reskin the workbench. Match existing pad and panel CSS.
- Don't introduce a Note mode that requires picking a key per session;
  scale + root come from the existing transport dropdowns.
- Don't bypass the rack registry. If a rack isn't registered for a
  track, fall back to the documented Phase A default.
- Don't promote scene-as-integer everywhere; the fast path stays.
- Don't load any external libraries.
