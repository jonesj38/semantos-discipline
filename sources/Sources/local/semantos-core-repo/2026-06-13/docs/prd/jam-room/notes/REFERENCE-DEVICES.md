---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/notes/REFERENCE-DEVICES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.784079+00:00
---

# Reference Devices — Affordance Lessons for the Jam Room

> Design note, not a deliverable. Phase PRDs cite this where relevant.

This note distils the affordance lessons from the controllers and
grooveboxes that influenced the jam-room design. It is **not** a list
of devices to clone. It is a list of decisions other people already
made well, with notes on what to adopt and what to skip.

---

## 1. Ableton Push 3

The lesson is not "copy Push" but **the grid is always contextual**.

Affordances worth taking:

- 8×8 pad grid as a universal semantic surface.
- Mode-specific pad meanings (already true in
  `src/grid/surface.ts` — `global / step / param / session / arrangement`).
- Immediate loop capture from performance.
- Arrangement capture from session launches.
- Device / rack focus: the selected instrument exposes its macros.

Not to copy:

- Ableton-specific hierarchy.
- Hidden shift layers stacked deep.
- DAW mental model as the default.
- Heavy screen dependency.

Phase impact: Phase A's `JamRack.getMappingHints()` and Phase B's
mode row both lean on the "grid is contextual" principle.

---

## 2. Novation Circuit / Circuit Tracks

The better inspiration for **first-touch fun**.

Worth taking:

- One-function-per-view clarity.
- Colour as state, not decoration.
- Track identity by colour.
- Dumb-fast step sequencing.
- Pattern banks and scenes.
- Performance macros that are safe and musical.

Not to copy:

- Fixed number of tracks (the jam-room sequencer is 13-track today,
  expandable).
- Hidden button-combo complexity.
- Device-specific sample/synth limits.

Phase impact: Phase B keeps Drum mode close to the Circuit shape;
Phase A's eight musical macro names (`brightness / dirt / ... /
tension`) are a Circuit-style commitment.

---

## 3. Novation Launchpad / Launchpad Pro

The strongest reference for **open mapping**.

Worth taking:

- Multiple user-definable surfaces.
- Mappings as first-class objects.
- Controller scripts as portable profiles.
- Grid feedback driven by room state.
- Remote control of pad colours, flashing, pulsing, states.

Not to copy:

- Treating custom mode as an advanced extra.
- Requiring external editor software for everything.

Phase impact: Phase C's entire `jam.mapping` model takes the
Launchpad position — a mapping is a content-addressed shareable object,
edited in-app, applicable to any surface shape.

---

## 4. Blipblox myTRACKS

Useful because it proves a groovebox can be playful without being
unserious.

Worth taking:

- Playfulness.
- Sampling as instant magic.
- Opinionated starter instruments.
- "Jam now, understand later".
- Friendly macro controls.
- Chaos / random buttons that are musically constrained.

Not to copy:

- Hidden complexity behind button combos.
- Child-toy aesthetic unless deliberately selected.

Phase impact: the `chaos` macro (Phase A macro index 6) is explicitly
constrained-random, not unconstrained-random. The Phase F default
contribution split policy preserves the playful low-stakes feeling
("anyone who joined gets credit").

---

## 5. Akai MPK49

Role: **musician's entry point.**

Best mapping (Phase C profile):

- Keys: selected melodic rack.
- Pads: selected drum rack or clip launch.
- Knobs (8): macro controls for the focused rack.
- Faders (8): track volume or stem-group levels (Mix mode rows in
  Phase B).
- Transport: room clock start / stop / record / overdub.

This is the minimal real-world test of the BYO mappings system
(Phase C). Anyone with an MPK49 should play a melody and program a
beat without touching the editor.

---

## 6. Numark RX2

Role: **performer / DJ arrangement layer.**

Best mapping (Phase C profile):

- Decks A / B: two active room scenes.
- Crossfader: morph between scenes (or stem groups).
- Jog wheels: scrub arrangement, pitch nudge, loop offset.
- Hot cues: section markers.
- FX pads: room sends — delay throws, filters, risers (Phase A
  `jam.gesture` cells).

The RX2 profile is the strongest test of the gesture vocabulary in
Phase A's event-cell families.

---

## 7. Aggregate principles

Across all six devices, the recurring themes are:

1. **Mode discipline.** Every mode has a clear identity and an
   obvious escape path.
2. **Colour means state.** Track identity, clip state, mode, ownership
   — all encoded as colour. Decorative colour is forbidden.
3. **Macros are musical.** No raw DSP names. Eight is enough.
4. **Performance is not setup.** First sound in <3 seconds. No
   configuration-first flows.
5. **The grid breathes.** Animations show playhead, queued launches,
   recording state, probability — but never obscure the beat.
6. **Local feel beats distributed purity.** Sound triggers locally;
   semantic commit happens in parallel; reconciliation is at musical
   boundaries.

These six principles are echoed in `MASTER.md` §6 and §10. The phase
PRDs cite this note when the device-specific affordances bear on
deliverables.

---

## 8. What this note doesn't cover

- Push 3 stand-alone mode (the room is online-by-default).
- Hardware-specific SysEx beyond what Phase C profiles document.
- Sound-design tutorials. The point of citing devices is *workflow*,
  not engine choice.
- Pricing or marketplace economics. That's a future-phase question.

---

## 9. Where to extend

If you add a new built-in mapping profile in a future phase, add a
section here describing its role and best-mapping table. Keep the
"worth taking / not to copy" structure. The PRDs cite section
numbers; renumbering existing sections breaks those links.
