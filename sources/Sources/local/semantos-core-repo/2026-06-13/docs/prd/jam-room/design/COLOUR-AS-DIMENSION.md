---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/design/COLOUR-AS-DIMENSION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.783473+00:00
---

# Colour as a First-Class Dimension — Scales, Modes, Chords, Learning

**Status**: Draft v0.1 — for design polish
**Audience**: Claude Design / a human designer
**Reads with**: [CSD-COMPRESSION-GRADIENT.md](./CSD-COMPRESSION-GRADIENT.md), `apps/world-apps/jam-room/src/grid/surface.ts` (current `PadColor`), `apps/world-apps/jam-room/src/sequencer.ts` (current scale options)

---

## The question

Colour in the existing surface (`grid/surface.ts`) encodes
**track-state** — a kick pad is orange, a clap is green, a muted lane
is dim. That's one channel of meaning. We need a second, orthogonal
channel: colour that encodes **musical position** — scale degree,
chord function, in-key vs out-of-key, mode characteristic.

If we get this right, the room becomes a learning instrument. A child
can press red pads and stay in tune; a producer can switch from major
to dorian and *see* the grid rebalance to a new tonal centre; a
keyboard player can lay a colour overlay over their physical keys to
learn fingerings.

Colour as a dimension also unlocks **layout adaptation by scale** —
because the *number* of in-scale degrees changes between scales (5 in
pentatonic, 7 in major, 12 chromatically), the grid itself can re-flow
to fit.

---

## The proposal

### 1. Two orthogonal colour channels

Every pad renders the **product** of two channels:

```
visualColour(pad) = blend(
  trackChannel(pad),    // current PadColor — track / clip-state / mode
  scaleChannel(pad)     // new — scale-degree colour
)
```

Today's `PadColor` (`'off' | 'white' | 'red' | 'orange' | 'yellow' |
'green' | 'cyan' | 'blue' | 'purple' | 'pink' | 'dim'`) becomes
**hue**; the new scale channel modulates **saturation, brightness,
border, and label**. The two channels never compete for the same
attribute.

| Attribute      | Driven by             |
| -------------- | --------------------- |
| Hue            | Track / clip / mode (existing) |
| Saturation     | In-key / out-of-key (new) |
| Brightness     | Currently playing / queued (existing) + scale-degree weight (new) |
| Border         | Root / fifth / chromatic accent (new) |
| Label          | Scale degree, solfège, or note name (new, toggleable) |
| Pulse          | Beat phase (existing) |

### 2. The chromatic palette (twelve hues)

The 12-tone palette anchors the scale channel. Pick one:

- **Newton's circle** — the classical 7-colour circle extended to 12
  by chromatic interpolation. Familiar from music-theory pedagogy.
- **Boomwhacker** — the educational standard for kids: Do=Red,
  Re=Orange, Mi=Yellow, Fa=Green, Sol=Cyan, La=Blue, Ti=Purple, with
  sharps as desaturated half-steps.
- **Scriabin / Skryabin** — the synesthete's circle; aesthetic but
  idiosyncratic. Good for a "Scriabin" theme but not as default.

**Recommendation**: Boomwhacker as default (it's the Roman / Jacob
chromatic education standard); Newton and Scriabin as alternate
themes selectable per-room.

```
Boomwhacker (default)
  C  - red          C# - red-orange
  D  - orange       D# - orange-yellow
  E  - yellow       F  - green
  F# - blue-green   G  - cyan
  G# - cyan-blue    A  - blue
  A# - blue-purple  B  - purple
```

### 3. Scale projection

Given a scale (the existing dropdown: `pent / major / minor / dorian
/ phrygian` plus future additions), every pitch is classified:

```
classify(pitch, scale, root) =
  'root'       if pitch == root
  'in-scale'   if (pitch - root) mod 12 ∈ scale.degrees
  'modal'      if it's the characteristic note (e.g. Dorian's #6)
  'chromatic'  otherwise
```

The classification drives the saturation / brightness / border:

| Class     | Saturation | Brightness | Border       | Label                       |
| --------- | ---------- | ---------- | ------------ | --------------------------- |
| root      | full       | full       | gold ring    | "1" or note name            |
| in-scale  | full       | full       | none         | scale degree (2, 3, 4, 5...)|
| modal     | full       | full       | white tick   | degree + ◊                  |
| chromatic | low (0.3)  | low (0.4)  | none         | (none unless scale-lock off)|

When **scale lock** is on (default per Phase B), chromatic pads dim
further to `'off'` and emit a click-but-no-note when pressed —
preserving the "no wrong notes" rule.

### 4. Mode-aware rebalancing

Switching scale is not just relabelling. It's a *visible*
re-emphasis:

- **Major** — root + perfect intervals dominate. Bright, balanced.
- **Minor (natural)** — flat 3 / flat 6 / flat 7 carry slight
  desaturation but full saturation; major-quality pitches stay bright.
- **Dorian** — the characteristic raised 6 gets the modal `◊` border
  and a pulse on first display.
- **Phrygian** — the characteristic lowered 2 gets the modal `◊`
  border; the overall palette drifts cooler (deeper hues, slightly
  darker).

The transition between scales animates over ~200 ms — pads that drop
out of scale fade; new in-scale pads brighten. This is itself a
teaching cue.

### 5. Chord highlighting

Tap-and-hold a scale degree → the triad (or seventh, or extended
chord) lights up:

- The root pad keeps its gold ring.
- Third and fifth pads get a thin connecting "halo" in the same hue.
- Extensions (7, 9, 11, 13) pulse at decreasing brightness.

Chord highlight is a transient overlay; releasing the held pad clears
it. A pin gesture (long-press) keeps the chord lit.

### 6. Layout adaptation by scale

The Note-mode grid layouts already exist (Phase B: scale, iso-fourths,
chord, bassline). Each layout's *footprint* changes when the scale
changes:

- **Scale layout** — rows = octaves, columns = scale degrees. A
  pentatonic scale gives 5 columns wide × 8 rows of octave (covering
  ~3 octaves on 8×8). A major scale gives 7 columns × 8 rows (~1
  octave). A chromatic mode (scale-lock off) gives 12-column hidden
  pages with horizontal swipe.

- **Iso-fourths layout** — invariant across scales (it's an
  every-degree-is-a-fourth-up tiling), but the in-scale pads are
  brightly coloured and out-of-scale dim.

- **Chord layout** — each pad is a triad on its scale degree.
  Pentatonic = 5 chord pads visible; major = 7; minor = 7. Empty
  pads stay dim, not greyed-out.

- **Bassline layout** — bottom two rows: 16 in-scale degrees across
  two octaves. Pentatonic: ~3 octaves coverage. Major: ~2 octaves.
  The remaining six rows (accent / slide / probability) are scale-
  invariant.

### 7. Learning overlays

Toggleable label modes on every pad:

- **Off** — colour only (default for performance).
- **Number** — scale degree (1, 2, b3, 4, 5, b6, b7).
- **Solfège** — Do, Re, Mi, Fa, Sol, La, Ti (movable-do).
- **Note name** — C, D, E, F (fixed).
- **Fingering** — for keyboard lessons; piano fingering numbers.

The "fingering" overlay drives a future hardware integration: a
projector / LED-strip on a physical keyboard mirrors the colours
under each key, locked to the same scale. This is the path to "learn
piano in your jam room" — you set the scale, the colours light up,
your fingers follow the colours.

### 8. Cross-surface consistency

The same colour mapping applies on every surface:

| Surface              | How colour appears                                        |
| -------------------- | --------------------------------------------------------- |
| 8×8 grid             | Pad fill + border + label                                 |
| Three.js loop orb    | Orb tint + halo                                           |
| Mobile L2 tab        | Active tab outline                                        |
| Keyboard overlay     | Per-key colour (on a hardware controller with RGB feedback) |
| Phone-as-controller  | XY pad gradient                                           |

A canonical colour vocabulary lives in
`apps/world-apps/jam-room/src/colour/scale-colour.ts`. Every renderer
imports from one place.

---

## Implementation sketch

```ts
// apps/world-apps/jam-room/src/colour/scale-colour.ts (new)

export type ScalePalette = 'boomwhacker' | 'newton' | 'scriabin';
export type ScaleClass   = 'root' | 'in-scale' | 'modal' | 'chromatic';

export interface ScaleColourSpec {
  hue: number;          // 0-360
  saturation: number;   // 0-1
  brightness: number;   // 0-1
  border?: 'gold-ring' | 'modal-tick' | 'chromatic-edge';
  label?: string;       // depends on labelMode
}

export function colourForPitch(
  pitch: number,
  scale: ScaleId,
  root: number,
  palette: ScalePalette,
  labelMode: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering',
): ScaleColourSpec;

export function classifyPitch(
  pitch: number,
  scale: ScaleId,
  root: number,
): ScaleClass;
```

The `colourForPitch` function is pure and deterministic — testable as
a snapshot. Renderers compose it with the existing track-channel
colour to produce the final pad render.

---

## Cell families touched

No new cell families; this is a renderer concern. Two `jam.world`
fields are added:

```ts
interface JamboxWorldPayload {
  // existing fields ...
  /** Selected colour palette for the scale channel. */
  palette?: ScalePalette;
  /** Default label mode for this world. */
  labelMode?: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering';
}
```

Per-player overrides live in the existing `jam.player` payload (a
new `colourPreferences` field if needed).

---

## What this means for the existing PRDs

- **Phase A** — minor: add `palette` and `labelMode` to
  `JamboxWorldPayload`. No new cell families.
- **Phase B** — Note mode and the new revised mode row pick up the
  scale-channel colours. Layout-by-scale rules in §6 belong in D-B.2
  (Note mode).
- **Phase C** — built-in profiles can declare a scale channel
  preference (e.g. Launchpad-Pro programmer-mode SysEx so RGB
  feedback matches the scale channel).
- **Phase E** — loop-orb tint and arrangement-block colour pick up
  the scale-channel via the same `colourForPitch` import.
- **Phase G (mobile)** — colour is the cheapest way to make a 414-px
  screen feel rich. Boomwhacker on a phone reads beautifully.

---

## Open questions for design polish

`TODO(design)`:

1. **Default palette.** Boomwhacker (educational standard), Newton
   (classical), or Scriabin (synesthete)? Recommendation:
   Boomwhacker as default; Newton and Scriabin as themes.
2. **Sharps and flats colour.** Boomwhacker uses desaturated
   half-steps but the convention is loose. Standardise: sharp =
   midpoint hue at 70% saturation; flat = same at 60%. Document the
   exact sRGB values.
3. **Accessibility — colour-blind users.** A 12-hue palette is
   actively hostile to deuteranopia. Provide a high-contrast mode that
   uses pattern (dot, stripe, ring) in addition to hue, and a
   monochrome+border mode that drops hue entirely.
4. **Label legibility on small pads.** A 414-px-wide phone in portrait
   gives each pad of an 8-wide grid about 50px. A two-character label
   ("b3") is readable; "Sol" is not. Pick a font, pick a size, test on
   a real phone.
5. **Modal characteristic notes — the `◊` glyph.** The diamond glyph
   is one option; a small chevron, a triangle, or simply a brighter
   border are alternatives. Pick one and commit.
6. **Scale lock interaction.** When scale lock is on and the user
   presses a chromatic pad, what do they see / hear? Recommendation:
   silent, but a brief border flash + label appears for 600 ms so the
   user understands *why* nothing happened.
7. **Layout transition timing.** 200 ms feels right for scale changes;
   too fast and it's jarring, too slow and it interrupts the jam. Test
   with users.
8. **Keyboard overlay integration.** A Roli Lumi, a Yamaha CP, an
   LED-strip retrofit on an MPK49 — different surfaces with different
   per-key feedback. Phase C mappings already declare `MappingOutput`
   for `led` feedback; the scale channel feeds that pipeline. The
   design question is what "learning mode" looks like on each device.
9. **Per-track colour vs per-scale colour conflict.** A drum track is
   orange (track channel). Note mode on the same track shows scale
   colours. They can't both win; document the precedence rule. (Most
   likely: drum tracks have no scale channel; melodic tracks fully
   adopt the scale channel.)

---

## Coda

Colour is free. It's the cheapest way to add a dimension of meaning,
the cheapest way to enforce "no wrong notes", and the cheapest way to
turn a jam-room into a music-theory tutor. Done well, it's invisible
discipline; done badly, it's a Christmas tree. The Sincerity Filter
applies to colour the same way it applies to every other UI choice.
