---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/novation-instrument-mapping.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.340023+00:00
---

# Novation Launchpad Pro MK3 — Instrument Mapping, Pad Layering, and Mode Architecture

A technical design reference for music-creation surfaces.
Concept-and-rationale focus. Sources cited inline; see Appendix A for the consolidated list.

---

## 0. Why this document exists

We are building a pad-grid music-creation surface (8×8 on mobile, plus a desktop counterpart) with three rack modes (rhythm / melody / bass), Boomwhacker-tinted pads, and scale lock. Novation has spent fifteen years iterating on exactly this design problem. The Launchpad Pro MK3, in particular, is the densest distillation of their thinking: an 8×8 RGB grid with no display, driving a clip launcher, a melodic instrument, a chord composer, and a four-track standalone sequencer — all on the same 64 cells.

This document reconstructs the conceptual model behind that surface, the primitive building blocks it composes from, and the rationale for each design choice. It exists so that when we make our own choices about modes, layering, scale lock, and colour semantics, we are choosing — not improvising.

---

## 1. The primitives

Every behaviour on the Launchpad Pro MK3 reduces to six conceptual atoms. Naming them is half the design; the other half is being disciplined about *not* mixing them.

**1.1 Pad — a polymorphic cell.** A pad is a coordinate `(row, col)` with three signals: press, velocity, and lift. It has no intrinsic meaning. What a press *does* is determined entirely by the resolution stack above it: the active mode, any held overlays, and the current scale/root configuration. The pad never "knows" it is a kick drum or a B♭3; the surrounding state knows, and routes the press accordingly. This is what lets the same physical hardware serve clip launching, melodic play, drum hits, sequencer steps, and faders.

**1.2 Mode — a persistent state.** Exactly one base mode is active at a time. The MK3 exposes five top-level modes — Session, Note, Chord, Custom, Sequencer — selected by dedicated buttons. Mode change rewrites the entire 8×8 mapping atomically. A mode is not a "view" you can peek into; it is the resolution context for every press until you change it. (Programmer Mode is a sixth state, but it lives outside the user-facing model — see §2.)

**1.3 Layer — a transient overlay.** A layer is a *temporary* re-mapping that sits on top of the active mode for as long as a modifier is held (or, in some cases, until another overlay supersedes it). Shift, Stop Clip, Mute, Solo, Record Arm, Volume, Pan, Sends, Device — each, when held or latched, redraws part of the surface and reroutes presses. Releasing the modifier reverts. Layers are how the surface hosts dozens of secondary functions without adding hardware.

**1.4 Scale — a filter and a transform.** A scale is a 7-or-fewer-note subset of the chromatic 12. On the MK3 it does two things at once: it acts as a **visual filter** (out-of-scale pads dim or vanish), and, when Scale Mode is engaged, it acts as a **mapping transform** that compresses the pad lattice so that adjacent pads are scale-degree-adjacent rather than chromatically adjacent. The same pad coordinate plays a different absolute pitch under different scales — but always plays an in-scale note.

**1.5 Root — the origin of the scale.** Root is the pitch class that anchors the scale. It picks out the bottom note of the layout's lowest octave and is reinforced visually (purple, on Novation's palette). Changing the root translates the scale up or down without changing its shape. Together, scale + root parameterise the entire melodic mapping with two values.

**1.6 Colour — a semantic channel.** RGB is not decoration on the MK3. It is the *only* feedback channel — there is no display. Novation reserves a small palette of fixed semantic roles (purple = root, blue = in-scale, red = step has notes assigned, green = playing, gold = shift-available) and uses brightness/pulsing as a second dimension (dim = available, bright = active, pulsing = queued). Custom Mode and Programmer Mode lift these constraints, but everywhere else the palette is the language of the instrument.

These six primitives compose. A "press a kick on step 4 of the third pattern" is a pad event under the Sequencer mode, with the Track 1 layer latched, the Drum sub-layout active — no scale or root involved (drums don't quantize to a scale). A "play the V chord in C Dorian" is a pad event in Chord Mode under scale=Dorian root=C, no other layer. The same vocabulary covers both.

---

## 2. The base-mode + overlay architecture

The MK3's surface is organised as a single base mode plus a stack of momentary or latched overlays. Three architectural rules govern the system; understanding these is more important than memorising any particular mode.

**Rule 1 — Base modes are mutually exclusive and persistent.** Pressing Session, Note, Chord, Custom, or Sequencer enters that mode and stays there. There is no "previous mode" stack and no way to be in two base modes at once. When inactive, the mode buttons light dim white; the active button lights pale green. This is the only mode-state indicator on the device. ([Novation user guide][ug-interface])

**Rule 2 — Overlays are transient and additive.** Holding a modifier (Shift, Stop Clip, Mute, Solo, Record Arm, Volume, Pan, Sends, Device, Clear, Duplicate, Quantise, Note Repeat, Capture MIDI) replaces *part* of the surface — sometimes the bottom row, sometimes the entire 8×8, sometimes only certain function buttons — for as long as the modifier is held. Some overlays (Volume, Pan, Sends, Device, Stop Clip, Mute, Solo, Record Arm) can be tap-pressed to **latch** the bottom row to that overlay until another supersedes it. Others (Shift, Clear, Duplicate) only behave as momentary gates. ([Novation user guide][ug-interface]; [DrivenByMoss documentation][dbm-launchpad])

**Rule 3 — Programmer Mode disables everything else.** Entering Programmer Mode from the Setup page turns the entire device into a flat MIDI controller. Every pad and button sends a fixed MIDI note or CC; pad lighting is driven entirely by host-sent velocity-as-colour-index against the device's 127-colour palette. None of the modes, overlays, scales, or any other firmware logic apply. Programmer Mode exists for developers integrating the device with custom hosts and is the boundary between "Novation's instrument" and "Novation's hardware". ([Programmer's Reference Guide][prg-ref]; [Setup page guide][ug-setup])

The architectural clarity here is worth stating: the base/overlay split lets Novation grow the device's vocabulary without adding hardware, and the Programmer Mode escape hatch lets developers ignore the vocabulary entirely when they need the raw surface. These are the two design moves that make a 64-cell instrument scale to its current feature set.

---

## 3. Note Mode — the playable-instrument layer

Note Mode turns the 8×8 into a melodic pad-instrument. It has three sub-layouts, controlled by a Note Mode Settings page (entered with **Shift + Note**) that is shared with Chord Mode.

### 3.1 The three sub-layouts

**Chromatic** (default in Chromatic toggle). Every pad plays a pitch. In-scale notes light blue, the root lights purple, out-of-scale pads are unlit but still playable. Visual filter only — the pad-to-note mapping is fixed.

**Scale** (Scale toggle on). Only in-scale pads have a mapping; out-of-scale pads are blank and silent. Pad coordinates step through scale degrees, not semitones. Changing scale or root **reflows** the entire mapping: the pad that played the 3rd in C major now plays the 3rd in F dorian, etc. Visual filter and mapping transform together.

**Drum** (auto-engaged when an Ableton Live Drum Rack is the armed instrument). The 8×8 splits into four 4×4 quadrants that mirror the four 4×4 quadrants of the Drum Rack. Pads light to indicate Drum Rack pad colours; pressed pads turn blue to indicate selection in Live. Drum mode is *not* user-toggled — it's a contextual auto-switch driven by the host's instrument type. ([Novation user guide][ug-interface])

### 3.2 The 4ths "5-finger overlap" layout

The default Note Mode geometry is what Novation calls the **5-finger overlap** — the well-known *chromatic-fourths* isomorphic layout, also known as the guitar-tuning layout. The structure:

- Each row, read left-to-right, ascends chromatically.
- Each row, read bottom-to-top, is a perfect 4th (5 semitones) above the row below.
- Adjacent rows overlap by 5 semitones, so the rightmost pad of row N equals the leftmost pad of row N+2's range, and column 1 of row N+1 equals column 6 of row N.
- An octave spans "two pads up and two pads across."

Result: every chord shape transposes to every key by translation alone. A major triad shape played anywhere on the grid is a major triad; sliding it up and right preserves its quality. This is the defining property of an **isomorphic** keyboard, and it is the entire reason this layout exists. (Compare with a piano, where C major and F♯ major are physically different shapes.) ([Sound on Sound review][sos-review]; [CDM analysis][cdm-grids]; [untergeek cheat sheets][ug-cheatsheets])

The MK3 makes the overlap configurable from the Note Mode Settings page. The choices, named by how many fingers it takes to climb a scale vertically:

- **Sequential** — no overlap; each row continues directly from the last. Maximum range, no doubled notes; chord shapes don't translate.
- **2-, 3-, 4-finger overlap** — graded reductions in doubled notes vs. shape consistency.
- **5-finger overlap** — the default; standard guitar-style isomorphic 4ths.

The trade-off curve: more overlap means more doubled notes (smaller usable range) but more consistent chord shapes; less overlap means more range but more cognitive load when changing keys. Sequential is the right choice for monophonic scale-running on a wide range; 5-finger is the right choice for chord-shape players. ([Novation user guide][ug-interface])

### 3.3 The Note Mode Settings page

Held entry: **Shift + Note**. The page is shared with Chord Mode and exposes:

- **Scale Viewer** — a piano-style row of pads. Pressing a pad sets the **root**. Blue = in-scale, purple = root, dim = out-of-scale.
- **Scale Select** — choose 1 of 16 built-in scales: Natural Minor, Major, Dorian, Phrygian, Mixolydian, Melodic Minor, Harmonic Minor, Bebop Dorian, Blues, Minor Pentatonic, Hungarian Minor, Ukrainian Dorian, Marva, Todi, Whole Tone, Hirajoshi.
- **Chromatic / Scale toggle** — single pad, red = chromatic, green = scale.
- **MIDI channel** — 1–16 for note output.
- **Overlap** — sequential, 2-finger, 3-finger, 4-finger, 5-finger.

Default state: C minor, 5-finger overlap, Scale Mode off (Chromatic on). ([Novation user guide][ug-interface])

The settings are sticky per device — they persist across mode switches and across power cycles. This matters: a player can configure the instrument's "tuning" once and then move freely between Note, Chord, and Sequencer with the same mapping context.

---

## 4. Scale and root — the music-theoretic filter

Scale and root are a single configuration that propagates across Note Mode, Chord Mode, and the Sequencer's scale-typed tracks. Two values (one of 16 scales, one of 12 roots) determine the entire melodic vocabulary of the device.

**How scale-lock works depends on the toggle.** This distinction is subtle but architecturally important:

- **Chromatic toggle on**: scale information is *display only*. The pad-to-note mapping is fixed (full chromatic, 5-finger overlap). Scale dictates which pads light blue/purple and which are unlit; pressing an unlit pad still plays the chromatic note. Mistakes are possible; visual guidance is provided.
- **Scale toggle on**: scale information is *structural*. Out-of-scale pads have no mapping; pressing them does nothing. Pad coordinates step through scale degrees. Mistakes are physically impossible; the player gets a "guaranteed-good-notes" instrument at the cost of losing chromatic ornaments.

This is the core trade Novation puts in front of the player: **wrong-notes-possible-but-full-vocabulary** vs **only-right-notes-but-reduced-vocabulary**. They let the player choose, per session, with one pad press.

**Reflow semantics under Scale toggle.** When scale or root changes while Scale toggle is on, the mapping reflows immediately. A pad's *coordinate* keeps the same role (e.g. "first pad of bottom row = root", "third pad of bottom row = 3rd"), but its *absolute pitch* changes. The visual layout — purple root anchor in the bottom-left, in-scale blue pads above — stays stable across all 16 × 12 = 192 (scale, root) pairs.

**Why 16 scales and not more or fewer.** The list is curated, not exhaustive. It covers Western diatonic modes (Major, the seven church modes implicit), common Western altered scales (Melodic Minor, Harmonic Minor, Blues, Minor Pentatonic, Bebop Dorian), and a small set of non-Western scales (Hungarian Minor, Ukrainian Dorian, Marva, Todi, Hirajoshi, Whole Tone). It is large enough to feel rich without forcing the player through a paged menu. The deliberate choice is breadth-with-finite-discoverability: every scale is one pad-press away on a single visible page. ([Novation user guide][ug-interface])

**Why scale + root and not "key" as a single concept.** Decomposing into two orthogonal parameters lets the player do two distinct musical operations: change *modal flavour* (scale) and change *tonal centre* (root) independently. It also matches MIDI's pitch-class semantics natively and avoids needing a string parser ("Cm vs C minor vs Cmin").

---

## 5. Chord Mode — the compositional surface

Chord Mode is its own top-level mode, not a sub-layout of Note Mode. It shares the scale + root + MIDI channel with Note Mode but presents a different 8×8.

### 5.1 The Chord Mode grid layout

The 8×8 is partitioned into five regions:

- **Note Area (5 columns × 7 rows, left)** — each row is a *playable chord*. Row colour encodes chord quality (blue = major, purple = minor, green = diminished/augmented in 7-note scales). The five columns within each row play scale degrees 1, 5, 3-up-an-octave, 7, 5-up-an-octave — an interval pattern that lets the player voice the chord open or stacked, with bass and chord tones across the columns.
- **Triads column (1 column × 7 rows, orange)** — vertical scale-degree triads on the right of the Note Area. One pad press = full diatonic triad on that scale degree.
- **Chord Bank (2 columns × 7 rows, white)** — 14 saveable slots. Bright = saved chord, dim = empty slot. A held chord from the Note Area + a press into the Chord Bank stores it.
- **Sustain pad (pink)** — holds played notes through release.
- **Chord Bank Lock (red)** — when active, lets the player play melody in the Note Area while the saved chords in the Bank continue sounding.

### 5.2 What Chord Mode is *for*

Chord Mode is fundamentally a **compositional** surface, not a performance shortcut. It does three things in sequence:

1. **Build** chords from scale-degree intervals, on the fly, with quality colour-coded.
2. **Save** them into the Chord Bank — 14 voicings the player constructs themselves.
3. **Recall and overlay** — Chord Bank Lock lets the saved palette play under improvised melody.

This is structurally different from Launchkey MK4's **Scale Chord** mode, which is a performance shortcut that triggers diatonic chords from individual keys. Launchpad Pro's Chord Mode is closer to a small chord-progression engine that you build, store, and play over. ([Chord Mode guide][cm-guide])

The architectural choice here is worth flagging: Novation could have stuck "trigger pre-built chords" on a few pads in Note Mode. Instead they made Chord Mode a peer of Note Mode with its own dedicated grid. The reason is that a compositional surface needs *both* a build-area (Note Area + Triads) and a recall-area (Bank) visible simultaneously — you can't fold that into a sub-layout without losing one or the other. Splitting it into its own mode preserves both.

---

## 6. Sequencer — time as a second axis

The Sequencer turns the 8×8 into a four-track 32-step polyphonic step sequencer that runs standalone (no host required). It is the densest single mode on the device, and the model behind it is the most architecturally interesting.

### 6.1 The split layout (Steps view)

In Steps view the 8×8 is partitioned **horizontally**:

- **Top half (4 rows × 8 cols = 32 cells)** — the **step row**. Each cell represents one 16th-note step in the current pattern. Cells light to indicate which steps have notes; the playhead sweeps left-to-right in white during play.
- **Bottom half (4 rows × 8 cols = 32 cells)** — the **Play Area**, governed by the track type (Drum, Scale, or Chromatic). For drum tracks it's the standard 4×4-quadrant Drum Rack layout in the lower 4×4 plus performance pads. For scale/chromatic tracks it's a 4-row note instrument under the same scale + root configuration as Note Mode.

This split is the central design move: **steps and notes are visible at the same time**. The player never has to switch views to see the sequence and play notes into it.

### 6.2 Step entry and the "hold-and-cross-press" mechanic

The basic interaction: hold a step in the top half, then press notes in the Play Area to assign them to that step (up to 8 polyphonic notes per step). Or invert it: hold a note in the Play Area, the step row lights to show which steps that note lives on, and the player toggles steps on/off.

The "hold A, press B" pattern is repeated everywhere in the Sequencer: hold a step + press another step to set gate length; hold a pattern + press another to chain; hold Shift + press a step to enter pattern start/end editing. This is the device's substitute for menus. ([Sequencer guide][seq-guide])

### 6.3 Patterns and Scenes

- **Patterns**: 8 per track per project. Each pattern is up to 32 steps. Patterns can be played individually, **chained** (hold one + press another to set start/end of the chain — chains can be up to 8 patterns = 256 steps), or **queued** (press during play → switches at next bar).
- **Scenes**: 16 scene pads. A scene captures one pattern or chain per track — a song-section snapshot across all four tracks. Scenes can themselves be chained for full-song playback.

This is a two-level memory hierarchy: patterns are "loops on a single track," scenes are "song sections across all tracks." It mirrors Ableton's clip-and-scene model exactly, which is the point — the Sequencer's output can be **printed to clip** directly into an Ableton Live session, completing the loop. ([Patterns and Scenes guide][ps-guide])

### 6.4 Per-step modifiers

Each step has four modifiers, accessed via dedicated views:

- **Velocity** (1–16, two-row top slider)
- **Probability** (8 levels) — chance of the step firing
- **Mutation** (8 levels) — random pitch displacement at fire time
- **Micro Steps** (6 sub-divisions) — sub-step timing for strums, flams, off-grid feel

Probability and mutation make the sequencer feel less robotic; micro-steps give it strum/flam expressiveness. These modifiers are evaluated at fire time during play, but **frozen at print time** when a pattern is exported to Ableton — random elements get committed to a deterministic clip.

### 6.5 Pattern Settings (per-pattern)

- **Sync rate**: 1/4, 1/4T, 1/8, 1/8T, 1/16 (default), 1/16T, 1/32, 1/32T
- **Direction**: Forward, Backward, Ping-Pong, Random
- **Start / End step**: defines the active window of the pattern (Shift toggles between editing end and start)

Different patterns on the same track can run at different sync rates and directions simultaneously — a 1/16 forward kick pattern under a 1/8T ping-pong hat pattern, for instance. The surface lets each track's groove evolve independently. ([Sequencer guide][seq-guide])

---

## 7. RGB feedback — colour as a semantic channel

With no display, the colour palette *is* the documentation. Novation has standardised the semantics tightly across modes; the table below is the consolidated palette.

### 7.1 The semantic palette

| Colour | Meaning |
|---|---|
| **Purple** | Root note (Note, Chord, Scale-track Sequencer Play Area) |
| **Blue** | In-scale note (Note, Chord, Scale-track Play Area) |
| **Blank / unlit** | Out-of-scale (Chromatic) or out-of-range / out-of-window (Scale, Sequencer) |
| **Red** | Note(s) assigned to held step (Sequencer); also Chord Bank Lock; also Stop Clip indicator |
| **Orange** | Triads column (Chord Mode); pattern-settings sync-rate / direction pads |
| **White (bright)** | Saved chord slot (Chord Bank); inactive base mode; sequencer playhead |
| **White (dim)** | Empty chord slot; available Custom Mode |
| **Pale green** | Active base mode |
| **Green (flashing)** | Clip queued (Session) |
| **Green (pulsing)** | Clip currently playing (Session) |
| **Green (range)** | Gate-length range visualisation (Sequencer) |
| **Pink** | Sustain pad (Chord Mode); peach/pink in Pattern Settings |
| **Gold** | Available shift function (held Shift) |
| **Track-colour** | Per-track Sequencer cells; 1:1 mirror of Ableton clip colour in Session |

The vocabulary is small enough to memorise. Brightness adds a second dimension (dim = available, bright = active, pulsing = queued/transient) without expanding the colour count. ([Novation user guide][ug-interface]; [Chord Mode guide][cm-guide]; [Sequencer guide][seq-guide])

### 7.2 The two exceptions

- **Custom Mode**: the user assigns the off-colour per pad and the on-colour per Custom slot using Novation Components (a web app). Eight Custom slots, each independently programmed. This is where the device admits that a fixed palette cannot serve every workflow.
- **Programmer Mode**: all 64 pads accept velocity-as-colour-index against a 127-entry palette. Colour is fully under host control. The Programmer's Reference Guide tabulates the palette indices. ([Programmer's Reference][prg-ref])

### 7.3 Why a fixed palette matters

Two reasons. First, *cross-mode legibility* — purple = root in Note Mode, in Chord Mode, in Scale Sequencer tracks, everywhere. The player doesn't relearn the palette per mode. Second, *muscle memory of state* — when the player glances at the surface, the colours are a status display (which clip is playing? which pads are roots? which steps fire?) rather than a decoration. Without the fixed palette, those glances would require re-parsing per-context, which is exactly what a no-display device cannot afford.

---

## 8. Modal layering — the three overlay primitives

Novation's documentation uses several words for layering — "overlay", "shift function", "secondary function", "holding" — but the device implements only three layering primitives. Naming them clearly is more useful than tracking the documentation's vocabulary drift.

**8.1 Momentary overlay** — the modifier is held; the surface remaps; release reverts. Examples: Shift, Clear, Duplicate, Quantise, Note Repeat, Capture MIDI. Volume / Pan / Sends / Device / Stop Clip / Mute / Solo / Record Arm in their *held* form. Used for transient operations: hold Clear and tap a pad to clear it; hold Shift and press a button to invoke its alternate function.

**8.2 Latched overlay** — the modifier is tap-pressed; the bottom row stays remapped until another latched overlay supersedes it. Volume / Pan / Sends / Device / Stop Clip / Mute / Solo / Record Arm all support the latched form. The user guide explicitly describes the design pattern: *"Press and hold Volume, edit a volume fader, and release Volume to return to Mute view."* This means the **previously latched overlay** is remembered and restored on release of a momentary one — a small but consequential detail. ([Novation user guide][ug-interface])

**8.3 Two-button compound** — Shift + X chord. Shift is held, another button is pressed; the press invokes the gold-printed alternate function of that button. Examples: Shift + Note → Note Mode Settings; Shift + Stop Clip → Swing settings; Shift + Device → Tempo; Shift + Save → Save project. Compounds give the device dozens of secondary functions without dedicating hardware to any of them. The gold ink under each button is the affordance.

These three primitives compose. A player can be in Note Mode (base), with Mute latched on the bottom row (latched overlay), and hold Shift (momentary overlay) to invoke a compound. The pad-event resolution is bottom-up: the pad's coordinate is interpreted in the context of the topmost relevant layer.

**Why layering instead of dedicated controls.** Surface real-estate is the binding constraint. The MK3 has 64 pads + 32 surrounding buttons + 0 displays + 0 encoders. To match Push 3's 200+ functional affordances on that hardware, every button has to mean two-to-six things depending on context. Layering — with consistent rules for entering and leaving each layer — is the only way to keep that scalable without confusing the player. The cost is that the player must memorise the rules; the benefit is a small, portable, fast device. ([MusicTech review][mt-review]; [MusicRadar review][mr-review])

---

## 9. Design rationale (the why)

There is no single Novation interview that lays out a unified theory. The rationale below is reconstructed from Novation's own *Ditch The Keys* article, the user guides, and reviewer commentary.

**Why an 8×8 grid.** The 8×8 inherits directly from Ableton Live's Session view, which is itself a 2D grid of clips × tracks. Launchpad's original purpose (2009) was to be a hardware mirror of that grid; everything since — Note Mode, Chord Mode, Sequencer — is layered on top of that lineage. The 8×8 is also a workable compromise: 64 cells is large enough for a melodic instrument with usable range, large enough for 32 sequencer steps + 32-cell play area, and small enough to stay portable. ([Novation: Ditch The Keys][nv-ditch])

**Why the 4ths layout.** Because it is **isomorphic**: chord shapes and scale fingerings transpose by translation. For a producer who doesn't play piano, an isomorphic layout is dramatically faster to internalise than the asymmetric semitone arrangement of a keyboard. *Ditch The Keys* is Novation's polemic on exactly this point — Note/Scale modes are framed as a deliberate alternative to keyboard-based note entry. ([Sound on Sound review][sos-review]; [CDM analysis][cdm-grids]; [Novation: Ditch The Keys][nv-ditch])

**Why scale-aware pads.** Scale Mode removes the cognitive load of knowing your key. Hitting any pad guarantees a usable note. CDM and Sound on Sound both single this out as the feature that turned Launchpad from a clip-launcher into a melodic instrument — the same conceptual move Push made on a richer hardware surface, achieved here on pad-only hardware. ([CDM][cdm-grids]; [Sound on Sound][sos-review])

**Why modal layering instead of dedicated controls.** Surface real-estate. The MK3 keeps the body small (compared to Push 3's 8×8 + 8 encoders + display + transport row) by encoding secondary functions as Shift-prefix combinations and contextual overlays. The trade-off is that the device has no display and the user must learn the layering rules; the benefit is that the device fits in a backpack and works standalone for sequencing. *MusicTech* describes this as "becoming more of a sequencer than a general-purpose controller, at the extreme end of what's doable with a controller without a display." ([MusicTech][mt-review])

**Why scale + root as orthogonal parameters.** Two values, sixteen scales × twelve roots, parameterise the entire melodic vocabulary in a way that maps cleanly to MIDI semantics, supports independent musical operations (modal flavour vs tonal centre), and exposes a small enough configuration that one settings page covers it. The settings persist across modes, so configuring once configures everywhere.

**Why a fixed colour palette.** No display means colour *is* the status read-out. A small fixed semantic palette (purple/blue/red/orange/green/white/gold) preserves cross-mode legibility and lets glances be parsed without context-switching the eye. The palette is consistent enough to memorise and rich enough to differentiate states.

---

## 10. Brief implications for our PadGrid model

(Optional comparative section — included because we're building a parallel surface.)

Where our model and Novation's align:
- **8×8 grid** as the canonical playing surface.
- **Mode-as-persistent-state** — our rhythm / melody / bass tabs are exactly Novation's "base mode" primitive, with mutually-exclusive selection.
- **Scale-lock** — `padGrid` already supports filtering pads to in-scale notes; this is Novation's Scale toggle.
- **Boomwhacker colours** — pitch-class-coloured pads serve the same role as Novation's purple-root + blue-in-scale palette: a fixed semantic colour code that lets glances parse pad state without re-learning per mode.

Where the models differ, and where Novation's choices might inform ours:
- **Layering**. Novation has three distinct overlay primitives (momentary, latched, two-button compound). Our current design has rack tabs (base modes) but no formal overlay grammar. As we add features — clear, duplicate, mute, capture — we should pick which overlay primitive each function uses and stick to it, rather than inventing per-feature gestures.
- **Scale + root as orthogonal parameters**. Worth checking whether our model represents "key" as a single value or as scale + root separately; the latter generalises better.
- **Drum mode as auto-engagement**. Drum/rhythm context-switches based on the armed instrument, not a manual toggle. Our rhythm rack does this implicitly already, but is worth being explicit about.
- **Sequencer split layout**. The "top half = steps, bottom half = play area" model is the densest expression of an 8×8. If we ever ship a step-sequencer mode, this is the layout to start from — both halves visible at once is the design move worth keeping.
- **Compositional Chord Mode vs performance Chord Mode**. Novation's choice to make Chord Mode a peer of Note Mode (with build / save / recall regions visible together) is worth understanding before we add chord features. Performance shortcuts (one-pad-per-chord) and compositional surfaces (build / save / overlay) are different surfaces and probably should not share the same screen.
- **Fixed palette discipline**. We should resist the temptation to colour pads "prettily." Each colour role should mean exactly one thing across all modes. Boomwhacker pitch-class is a great fixed assignment; transient state (active, queued, recording) needs a separate, also-fixed, subset of colours.

These are observations, not prescriptions. The point of mapping our model against Novation's is to see which of their constraints we want to inherit and which we want to reject deliberately.

---

## Appendix A — Sources

Primary (Novation / Focusrite official):

- [ug-interface]: Launchpad Pro MK3 Interface Guide — https://userguides.novationmusic.com/hc/en-gb/articles/25494530115346-Launchpad-Pro-MK3-interface
- [seq-guide]: Using the Launchpad Pro MK3's Sequencer — https://userguides.novationmusic.com/hc/en-gb/articles/25494505907346-Using-Launchpad-Pro-MK3-s-Sequencer
- [cm-guide]: Launchpad Pro MK3 Chord Mode Guide — https://support.novationmusic.com/hc/en-gb/articles/360011206299-Launchpad-Pro-MK3-Chord-Mode-Guide
- [ps-guide]: Patterns and Scenes Explained — https://support.novationmusic.com/hc/en-gb/articles/360011112340-Launchpad-Pro-MK3-Patterns-and-Scenes-explained
- [ug-setup]: Setup Page Guide — https://userguides.novationmusic.com/hc/en-gb/articles/25494545308306-Using-the-Launchpad-Pro-MK3-s-Setup-page
- [prg-ref]: Programmer's Reference Guide (PDF) — https://fael-downloads-prod.focusrite.com/customer/prod/s3fs-public/downloads/LPP3_prog_ref_guide_200415.pdf
- [nv-ditch]: Novation — Ditch The Keys — https://medium.com/novation-notes/ditch-the-keys-if-you-want-to-b162021675d2

Reviews and analysis:

- [sos-review]: Sound on Sound — Launchpad Pro / X / Mini MK3 review — https://www.soundonsound.com/reviews/novation-launchpad-pro-x-mini-mkiii
- [cdm-grids]: CDM — Grids Key: Novation's New Launchpad Pro Scales — https://cdm.link/2016/08/grids-key-novations-new-launchpad-pro-scales/
- [mr-review]: MusicRadar — Launchpad Pro MK3 review — https://www.musicradar.com/reviews/novation-launchpad-pro-mk3
- [mt-review]: MusicTech — Launchpad Pro MK3 review — https://musictech.com/reviews/controllers/novation-launchpad-pro-mk3/
- [ug-cheatsheets]: untergeek — Launchpad note/chord cheat sheets — https://www.untergeek.de/2017/11/how-to-play-notes-and-chords-on-the-launchpad-cheat-sheets/
- [dbm-launchpad]: DrivenByMoss — Launchpad documentation — https://github.com/git-moss/DrivenByMoss-Documentation/blob/master/Novation/Novation-Launchpad.md

Comparative (Push 3 / Ableton):

- Push 3 manual — https://www.ableton.com/en/push/manual/
- Ableton blog — Push in Action: Playing Chromatic and Key Modes — https://www.ableton.com/en/blog/push-action-playing-chromatic-and-key-modes/

---

## Appendix B — Notes on uncertainty

Two specific gaps where the underlying source is weak and the document is interpolating:

- The **chord-row colour-coding inside Chord Mode** (blue/purple/green for major/minor/diminished) is described in the Chord Mode guide and reviewer write-ups, but the exact shade-vs-quality mapping for non-7-note scales (Whole Tone, Blues, Hirajoshi etc.) is not authoritatively documented. Treat this section as accurate for diatonic scales and approximate elsewhere.
- The **rationale section** is reconstructed from Novation's *Ditch The Keys* article and reviewer commentary. There is no single Novation interview explicitly justifying every design choice. The "why" claims are grounded but not first-person attributed.

Both gaps are flagged inline where they appear.
