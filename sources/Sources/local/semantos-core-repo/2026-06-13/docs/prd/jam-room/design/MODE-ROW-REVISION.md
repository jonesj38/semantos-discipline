---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/design/MODE-ROW-REVISION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.783202+00:00
---

# Mode Row Revision — Sincerity Filter applied to Phase B

**Status**: Draft v0.1 — for design polish
**Audience**: Claude Design / a human designer
**Reads with**: [CSD-COMPRESSION-GRADIENT.md](./CSD-COMPRESSION-GRADIENT.md), `../PHASE-B-MODES.md`

---

## The question

Phase B's mode row currently proposes eight buttons:

```
Play | Drum | Note | Session | Sequencer | Arrange | Mix | Custom
```

That's seven peers + one disabled stub. Eight buttons is creep against
the 1-3-5-3-1 pyramid: it asks the user's working memory to hold every
mode at once. The Sincerity Filter (CSD core rule) says the right
budget is 1 anchor + 3 active + everything else gated.

What does the revised row look like?

---

## The proposal

### Anchor row (always visible, top)

```
┌──────────────────────────────────────────────────────────┐
│  ▶  120 bpm   ◇ scene A     ⏺ rec    ⌃ capture           │
└──────────────────────────────────────────────────────────┘
```

The anchor row carries:

- **Play / stop** — the only transport control on the mobile anchor.
- **Tempo** — read-only on mobile by default; tap-to-edit.
- **Active scene** — the L1 anchor object made visible.
- **Record + Capture** — Capture is the L3 #5 deliverable from Phase F
  but the affordance is so common it earns an anchor pin.

Everything else falls into one of three columns.

### Mode row (3 active buttons)

```
┌──────────────┬──────────────┬──────────────┐
│   RHYTHM     │   MELODY     │     BASS     │
│   (Drum)     │  (Note/Mix)  │  (Bass/Mix)  │
└──────────────┴──────────────┴──────────────┘
```

Each L2 button carries the **rack focus** + the **default mode for
that rack**:

| L2 button | Default mode               | What it shows                                    |
| --------- | -------------------------- | ------------------------------------------------ |
| Rhythm    | Drum / Step                | 8×8 step sequencer for the selected drum rack    |
| Melody    | Note (scale layout)        | Scale-locked melodic grid for the selected lead  |
| Bass      | Note (bassline layout) + Mix peek | Two-octave bass layout + volume strip      |

A second tap on the same L2 button cycles the *secondary mode* for
that rack — e.g. Rhythm tap-tap = Drum → Sequencer (param view).

### Support sheet (5 entries, gated)

Pull from the right edge / long-press an L2 tab / use the overflow
icon:

```
┌────────────────────────────┐
│  ⌗  Sequencer (full grid) │
│  ◧  Mix (track strips)     │
│  ⊞  Session (clip launcher)│
│  ⊐  Arrange (timeline)     │
│  ✦  Custom (BYO mapping)   │
└────────────────────────────┘
```

These are the five Phase B/C/F modes that don't earn a top-level slot.
Each is a single tap from the support sheet.

### Infrastructure (invisible)

Clock, identity, persistence, multiplayer presence — never on the mode
row. Hover-HUD on desktop only. A four-finger tap surfaces a
diagnostics drawer on mobile if needed.

---

## Why this is honest

| Old slot     | Justification for old → revised                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------- |
| Play         | Folds into the anchor row. Transport is L1, not L2.                                                     |
| Drum         | Becomes "Rhythm" L2 button. Same surface, honest naming.                                                 |
| Note         | Becomes "Melody" L2 button. Scale layout is the default; iso/chord are sub-options inside the rack pod. |
| Session      | Demoted to support sheet. Session view is power-user; on mobile it's a sheet, on desktop it's a panel. |
| Sequencer    | Demoted to support sheet. Step editing is power-user.                                                   |
| Arrange      | Demoted to support sheet. Arrangement view is desktop-first; mobile rarely needs it live.               |
| Mix          | Lives inside Bass + Melody buttons as a peek; the full strip is in the support sheet.                   |
| Custom       | Demoted to support sheet. BYO mappings (Phase C) are not first-touch.                                   |

The user lands with three obvious actions. The advanced surface is
one swipe away. The pyramid holds.

---

## What this means for the Phase B PRD

The revisions to Phase B are surgical:

1. **D-B.1 (mode-row card)** — replaces the eight buttons with the
   anchor + 3-active layout above. Support entries become a
   `data-card="support-sheet"` with a discoverable open affordance.
2. **D-B.2 (Note mode)** — sub-layouts (scale / iso-fourths / chord /
   bassline) move from a top-level dropdown into the **rack pod**
   header. Selecting "Bass" defaults to bassline; "Melody" defaults
   to scale.
3. **D-B.3 (Mix mode)** — full Mix mode is in the support sheet. The
   L2 Bass + Melody buttons get a small two-row "Mix peek" (volume +
   send-A only) inline; full FX rows live in the sheet.
4. **D-B.4 (Session)** — demoted to support. Same handlers, different
   placement.
5. **D-B.5 (Arrange)** — demoted to support. Same handlers, different
   placement.
6. **D-B.7 (mode-discipline guardrails)** — extended to enforce
   L2 button → default mode bindings.
7. **D-B.8 (gate test)** — verifies the revised layout: anchor row is
   present, three L2 buttons, support sheet contains five entries,
   Custom is the fifth.

---

## Open questions for design polish

`TODO(design)`:

1. **Naming the L2 buttons.** "Rhythm / Melody / Bass" is generic.
   Could be "Beat / Lead / Low", "Drums / Keys / Bass", or
   instrument-icon-only. Stable wording matters for habit formation.
2. **Support-sheet open gesture.** Edge-pull on touch, click on
   desktop. What about Push 3 hardware? Probably a top-row pad.
3. **Capture on the anchor row.** Phase F's "long-press = capture last
   N bars" is a great affordance. Where on the anchor row does it sit
   on mobile, and what's the visual hint that long-press exists?
4. **Tap-tap to cycle vs. dedicated icon.** Cycling secondary mode
   on second-tap is invisible to a new user. The cycle indicator could
   be a tiny dot under the L2 button. Or skip cycling entirely and
   require the support sheet for secondary modes.
5. **Anchor row contents on landscape tablet.** Tablet landscape has
   room for more — should it grow to "anchor + L2 + support rail" all
   visible at once? Yes if we want, but only if it doesn't make
   portrait feel like a step down.
6. **Rhythm/Melody/Bass when only one rack is registered.** Boot state
   shows the one registered rack on the rhythm slot and "Add melody /
   bass" prompts on the other two? Or hide the empty slots until a
   rack is added? CSD says stable, so probably show prompts.
7. **Multiplayer rack focus.** Two players might both want "Rhythm"
   focus simultaneously. The L2 button is per-player; the underlying
   rack is shared. How does the surface show "Alice is also driving
   rhythm"? A small avatar dot on the button.

---

## Coda

The eight-button mode row was a design holdover from imagining every
power-user mode as a peer. It isn't. Three matter; five wait. The
revised row tells that truth visually.
