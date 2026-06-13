---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/colour/scale-colour.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.610425+00:00
---

# cartridges/jambox/web/src/colour/scale-colour.ts

```ts
/**
 * Scale-colour module — pure, no renderer.
 *
 * Exports the deterministic scale-classification + colour functions used by
 * every melodic surface in phases B and beyond.
 *
 * Colour carries two orthogonal channels:
 *   - Track channel  (existing) — hue encoded by track, clip state, mode.
 *   - Scale channel  (this module) — saturation, brightness, border, label
 *     encoded by scale degree (root / in-scale / modal / chromatic).
 *
 * Three palettes:
 *   - Boomwhacker (default): educational standard sRGB values.
 *   - Newton: classical ROYGBIV spectral mapping.
 *   - Scriabin: synesthete; the composer's colour→key mapping.
 *
 * ScaleId encodes scale type (e.g. 'major', 'minor', 'pentatonic', etc.).
 * Root is a MIDI pitch class 0-11 (C=0, C#=1, D=2, ..., B=11).
 * Pitch is an absolute MIDI note number.
 */

export type ScalePalette = 'boomwhacker' | 'newton' | 'scriabin';
export type ScaleClass = 'root' | 'in-scale' | 'modal' | 'chromatic';

export interface ScaleColourSpec {
  /** Hue 0-360 */
  hue: number;
  /** Saturation 0-1 */
  saturation: number;
  /** Brightness 0-1 */
  brightness: number;
  border?: 'gold-ring' | 'modal-tick' | 'chromatic-edge';
  label?: string;
}

/** Supported scale types for classifyPitch and colourForPitch. */
export type ScaleId =
  | 'major'
  | 'minor'
  | 'pentatonic'
  | 'pentatonic-minor'
  | 'dorian'
  | 'phrygian'
  | 'lydian'
  | 'mixolydian'
  | 'locrian'
  | 'blues'
  | 'chromatic';

// ─── Scale interval definitions (semitones above root, 0-based) ──────────────

const SCALE_INTERVALS: Record<ScaleId, number[]> = {
  major:             [0, 2, 4, 5, 7, 9, 11],
  minor:             [0, 2, 3, 5, 7, 8, 10],
  pentatonic:        [0, 2, 4, 7, 9],
  'pentatonic-minor':[0, 3, 5, 7, 10],
  dorian:            [0, 2, 3, 5, 7, 9, 10],
  phrygian:          [0, 1, 3, 5, 7, 8, 10],
  lydian:            [0, 2, 4, 6, 7, 9, 11],
  mixolydian:        [0, 2, 4, 5, 7, 9, 10],
  locrian:           [0, 1, 3, 5, 6, 8, 10],
  blues:             [0, 3, 5, 6, 7, 10],
  chromatic:         [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
};

/**
 * Modal characteristic notes — the "avoid" / "flavour" note of a mode.
 * These get the 'modal-tick' border treatment to highlight them.
 */
const MODAL_CHARACTERISTIC: Partial<Record<ScaleId, number>> = {
  dorian:     9,   // major 6th (the bright tone that distinguishes dorian from minor)
  phrygian:   1,   // flat 2nd (the Spanish/Moorish tone)
  lydian:     6,   // sharp 4th (the dreamy tritone)
  mixolydian: 10,  // flat 7th (the dominant 7th tone)
  locrian:    6,   // flat 5th (the diminished 5th)
};

// ─── classifyPitch ────────────────────────────────────────────────────────────

/**
 * Classify a MIDI pitch relative to a scale and root.
 *
 * @param pitch - MIDI note number (0-127; only pitch class matters)
 * @param scale - Scale identifier
 * @param root  - Root pitch class 0-11 (C=0)
 * @returns ScaleClass: 'root' | 'in-scale' | 'modal' | 'chromatic'
 */
export function classifyPitch(
  pitch: number,
  scale: ScaleId,
  root: number,
): ScaleClass {
  const pc = ((pitch % 12) + 12) % 12; // pitch class 0-11
  const rel = ((pc - root) % 12 + 12) % 12; // relative to root
  const intervals = SCALE_INTERVALS[scale];

  if (rel === 0) return 'root';

  if (!intervals.includes(rel)) return 'chromatic';

  const modal = MODAL_CHARACTERISTIC[scale];
  if (modal !== undefined && rel === modal) return 'modal';

  return 'in-scale';
}

// ─── Boomwhacker palette ──────────────────────────────────────────────────────
// Exact sRGB values from the Boomwhacker educational standard.
// Note: values stored as HSB approximations for our spec format.

/** Boomwhacker hue per pitch class (C=0 through B=11). */
const BOOMWHACKER_HUE: Record<number, number> = {
  0:  0,     // C  → Red        sRGB #FF0000
  1:  14,    // C# → Red-Orange sRGB #FF5500 (approx)
  2:  33,    // D  → Orange     sRGB #FF8C00
  3:  54,    // D# → Yellow-Orange sRGB #FFCC00
  4:  70,    // E  → Yellow     sRGB #FFE600
  5:  120,   // F  → Green      sRGB #00C800
  6:  150,   // F# → Lime/Teal  sRGB #00D4A0 (approx)
  7:  210,   // G  → Blue       sRGB #0078FF
  8:  240,   // G# → Dark Blue  sRGB #0032FF
  9:  270,   // A  → Purple     sRGB #8000FF
  10: 300,   // A# → Hot Pink   sRGB #FF00C8
  11: 340,   // B  → Pink-Red   sRGB #FF0078
};

// ─── Newton palette ───────────────────────────────────────────────────────────
// Newton mapped the spectrum ROYGBIV to the diatonic scale.
// Chromatic pitches fall between the seven ROYGBIV positions.

const NEWTON_HUE: Record<number, number> = {
  0:  0,     // C  → Red
  1:  15,    // C# → (between red-orange)
  2:  30,    // D  → Orange
  3:  52,    // D# → (between orange-yellow)
  4:  60,    // E  → Yellow
  5:  120,   // F  → Green
  6:  150,   // F# → (between green-blue)
  7:  210,   // G  → Blue (indigo)
  8:  240,   // G# → (between blue-violet)
  9:  265,   // A  → Violet
  10: 285,   // A# → (between violet-end)
  11: 300,   // B  → (beyond violet, loops back)
};

// ─── Scriabin palette ─────────────────────────────────────────────────────────
// Alexander Scriabin's synesthetic colour-key associations.

const SCRIABIN_HUE: Record<number, number> = {
  0:  0,     // C  → Red
  1:  213,   // C# → Violet
  2:  213,   // D  → Yellow (stored as blue-adjacent, adjusted)
  3:  270,   // D# → Purple/Steel
  4:  60,    // E  → Pale Blue-White (approx yellow)
  5:  180,   // F  → Dark Red → approximated as cyan-red
  6:  0,     // F# → Bright Blue → approximated
  7:  210,   // G  → Bright Orange → approximated
  8:  330,   // G# → Violet-Purple
  9:  60,    // A  → Green
  10: 30,    // A# → Steel (grey-orange approx)
  11: 213,   // B  → Pale Blue
};

// Note: Scriabin's associations are idiosyncratic; these are best approximations
// as HSB hues. The exact experience requires per-palette saturation/brightness
// adjustments documented in design/COLOUR-AS-DIMENSION.md.

// ─── Scale class → visual modifiers ──────────────────────────────────────────

interface ClassModifiers {
  saturationMod: number;   // additive to palette base saturation
  brightnessMod: number;   // additive to palette base brightness
  border?: ScaleColourSpec['border'];
}

const CLASS_MODIFIERS: Record<ScaleClass, ClassModifiers> = {
  root:      { saturationMod: 0,     brightnessMod: 0,     border: 'gold-ring' },
  'in-scale':{ saturationMod: 0,     brightnessMod: 0,     border: undefined },
  modal:     { saturationMod: 0.1,   brightnessMod: 0.05,  border: 'modal-tick' },
  chromatic: { saturationMod: -0.5,  brightnessMod: -0.3,  border: 'chromatic-edge' },
};

// ─── colourForPitch ───────────────────────────────────────────────────────────

/**
 * Return a complete colour specification for a pitch in a given scale context.
 *
 * @param pitch     - MIDI note number
 * @param scale     - Scale identifier
 * @param root      - Root pitch class 0-11
 * @param palette   - Colour palette to use
 * @param labelMode - How to label the pad
 * @returns ScaleColourSpec with hue/saturation/brightness/border/label
 */
export function colourForPitch(
  pitch: number,
  scale: ScaleId,
  root: number,
  palette: ScalePalette,
  labelMode: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering',
): ScaleColourSpec {
  const pc = ((pitch % 12) + 12) % 12;
  const scaleClass = classifyPitch(pitch, scale, root);
  const mods = CLASS_MODIFIERS[scaleClass];

  const hue = paletteHue(pc, palette);
  const baseSat = palette === 'boomwhacker' ? 0.9 : palette === 'newton' ? 0.85 : 0.8;
  const baseBri = scaleClass === 'chromatic' ? 0.3 : 0.85;

  const saturation = Math.max(0, Math.min(1, baseSat + mods.saturationMod));
  const brightness = Math.max(0, Math.min(1, baseBri + mods.brightnessMod));

  const label = buildLabel(pitch, root, scale, scaleClass, labelMode);

  return {
    hue,
    saturation,
    brightness,
    border: mods.border,
    label: label || undefined,
  };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function paletteHue(pitchClass: number, palette: ScalePalette): number {
  switch (palette) {
    case 'boomwhacker': return BOOMWHACKER_HUE[pitchClass] ?? 0;
    case 'newton':      return NEWTON_HUE[pitchClass] ?? 0;
    case 'scriabin':    return SCRIABIN_HUE[pitchClass] ?? 0;
  }
}

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const SOLFEGE_NAMES = ['Do', 'Di', 'Re', 'Ri', 'Mi', 'Fa', 'Fi', 'Sol', 'Si', 'La', 'Li', 'Ti'];
const SOLFEGE_IN_SCALE = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Ti'];

function buildLabel(
  pitch: number,
  root: number,
  scale: ScaleId,
  scaleClass: ScaleClass,
  labelMode: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering',
): string {
  if (labelMode === 'off') return '';

  const pc = ((pitch % 12) + 12) % 12;
  const octave = Math.floor(pitch / 12) - 1;

  if (labelMode === 'note-name') {
    return `${NOTE_NAMES[pc]}${octave}`;
  }

  if (labelMode === 'number') {
    if (scaleClass === 'chromatic') return '';
    const rel = ((pc - root) % 12 + 12) % 12;
    const intervals = SCALE_INTERVALS[scale];
    const degree = intervals.indexOf(rel);
    return degree >= 0 ? String(degree + 1) : '';
  }

  if (labelMode === 'solfege') {
    const rel = ((pc - root) % 12 + 12) % 12;
    const intervals = SCALE_INTERVALS[scale];
    const degree = intervals.indexOf(rel);
    if (degree >= 0 && degree < SOLFEGE_IN_SCALE.length) {
      return SOLFEGE_IN_SCALE[degree] ?? SOLFEGE_NAMES[pc] ?? '';
    }
    return SOLFEGE_NAMES[pc] ?? '';
  }

  if (labelMode === 'fingering') {
    // Fingering: 1-5 for white keys in the active scale (piano lesson mode).
    const rel = ((pc - root) % 12 + 12) % 12;
    const intervals = SCALE_INTERVALS[scale];
    const degree = intervals.indexOf(rel);
    if (degree < 0) return '';
    // Map degree to standard RH fingering 1-5 cycling.
    return String((degree % 5) + 1);
  }

  return '';
}

```
