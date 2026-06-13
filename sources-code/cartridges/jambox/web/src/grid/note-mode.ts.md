---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/note-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.605752+00:00
---

# cartridges/jambox/web/src/grid/note-mode.ts

```ts
/**
 * D-B.2 Note mode — melodic pad grid with scale-channel colour.
 *
 * Layouts:
 *   scale       — rows = octave moves; columns = scale steps (default for Melody).
 *   iso-fourths — isomorphic fourths tiling (every pad is 5 semitones above left).
 *   chord       — each pad is a triad on that scale degree.
 *   bassline    — bottom two rows = two-octave bass; top six = accent/slide/prob.
 *                 Default for Bass L2 button.
 *
 * Scale lock (on by default):
 *   Chromatic pads dim to 'off' and emit no jam.note.on.
 *   Instead a 600 ms visual flash (border + label) fires to show why.
 *
 * Colour:
 *   Track channel drives hue (via PadColor).
 *   Scale channel drives saturation, brightness, border, label (via colourForPitch).
 *   Scale change animates over 200 ms CSS transition.
 *
 * Events emitted:
 *   jam.note.on        — pad press
 *   jam.note.off       — pad release
 *   jam.note.expression — pressure / aftertouch; also latch on double-tap
 *   jam.input.pad       — always (for chromatic flash visibility)
 */

import type { PadState, PadColor } from './surface';
import {
  colourForPitch,
  classifyPitch,
  type ScaleId,
  type ScalePalette,
} from '../colour/scale-colour';
import type {
  JamNoteOnEvent,
  JamNoteOffEvent,
  JamNoteExpression,
  JamInputPad,
} from '../semantic/events';

// ─── Types ────────────────────────────────────────────────────────────────────

export type NoteLayout = 'scale' | 'iso-fourths' | 'chord' | 'bassline';
export type LabelMode = 'off' | 'number' | 'solfege' | 'note-name' | 'fingering';

export interface NoteModeState {
  layout: NoteLayout;
  scale: ScaleId;
  root: number;         // pitch class 0-11 (C=0)
  octave: number;       // base octave (default 3)
  scaleLock: boolean;   // true = chromatic pads are silent (default on)
  palette: ScalePalette;
  labelMode: LabelMode;
  rackId: string;
  /** Pads currently flashing (chromatic no-op flash). index → expire timestamp */
  flashingPads: Map<number, number>;
  /** Held pads for chord highlight. padIndex → pitch */
  heldPads: Map<number, number>;
  /** Double-tap tracking. padIndex → last tap timestamp */
  doubleTapTimestamps: Map<number, number>;
}

export type NoteModeEvent =
  | JamNoteOnEvent
  | JamNoteOffEvent
  | JamNoteExpression
  | JamInputPad;

const DOUBLE_TAP_MS = 300;
const FLASH_DURATION_MS = 600;

// ─── Scale interval tables ────────────────────────────────────────────────────

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

/** Default scale for pentatonic → 5 cols, major/others → 7 cols. */
export function scaleCols(scale: ScaleId): number {
  const intervals = SCALE_INTERVALS[scale];
  return Math.min(intervals.length, 8); // max 8 cols on the 8×8 grid
}

// ─── Chord helpers ────────────────────────────────────────────────────────────

/** Get triad intervals (root, third, fifth) relative to scale degree. */
function chordIntervals(scale: ScaleId, degree: number): number[] {
  const intervals = SCALE_INTERVALS[scale];
  if (intervals.length === 0) return [0];
  const root = intervals[degree % intervals.length] ?? 0;
  const third = intervals[(degree + 2) % intervals.length] ?? root;
  const fifth  = intervals[(degree + 4) % intervals.length] ?? root;
  return [root, third, fifth];
}

// ─── Pitch from pad position ──────────────────────────────────────────────────

/**
 * Map a (row, col) pad position to a MIDI pitch.
 * Returns null if the pad has no pitch in the current layout.
 */
function pitchForPad(
  row: number, col: number,
  state: NoteModeState,
): number | null {
  const intervals = SCALE_INTERVALS[state.scale];
  const baseNote = state.root + state.octave * 12;

  switch (state.layout) {
    case 'scale': {
      const cols = scaleCols(state.scale);
      if (col >= cols) return null;
      // row 0 = highest octave, row 7 = lowest
      const octaveOffset = (7 - row);
      return baseNote + octaveOffset * 12 + (intervals[col] ?? 0);
    }
    case 'iso-fourths': {
      // Each step up = +1 semitone; each step right = +5 semitones (perfect fourth)
      const pitch = baseNote + row * 5 + col;
      return pitch;
    }
    case 'chord': {
      // Each col is a chord root degree; row 0 = chord root, rows 1-2 = extensions
      const degree = col % intervals.length;
      const chordInts = chordIntervals(state.scale, degree);
      const octaveShift = Math.floor(col / intervals.length);
      const noteInChord = row < chordInts.length ? chordInts[row] : null;
      if (noteInChord === null) return null;
      return baseNote + octaveShift * 12 + noteInChord;
    }
    case 'bassline': {
      // Bottom two rows: in-scale bass notes across 2 octaves
      if (row >= 2) {
        // Top 6 rows: accent (row 2), slide (row 3), probability (rows 4-5), empty (6-7)
        return null;
      }
      const noteIndex = row * 8 + col;
      const octave = Math.floor(noteIndex / intervals.length);
      const degree = noteIndex % intervals.length;
      return baseNote + octave * 12 + (intervals[degree] ?? 0);
    }
  }
}

// ─── renderNotePads ───────────────────────────────────────────────────────────

/**
 * Render all 64 pads for note mode.
 *
 * Scale channel colour is driven by `colourForPitch` from Phase A.
 * Track channel hue is approximated from rackId.
 */
export function renderNotePads(state: NoteModeState): PadState[] {
  const pads: PadState[] = [];
  const now = Date.now();

  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const padIndex = row * 8 + col;
      pads.push(renderSinglePad(row, col, padIndex, state, now));
    }
  }
  return pads;
}

function renderSinglePad(
  row: number, col: number, padIndex: number,
  state: NoteModeState, now: number,
): PadState {
  const pitch = pitchForPad(row, col, state);

  // No-pitch pads (e.g. bassline accent rows)
  if (pitch === null) {
    if (state.layout === 'bassline' && row >= 2) {
      return renderBasslineControlPad(row, col);
    }
    return { color: 'off', brightness: 0, label: '', pulse: false, active: false };
  }

  const scaleClass = classifyPitch(pitch, state.scale, state.root);
  const spec = colourForPitch(pitch, state.scale, state.root, state.palette, state.labelMode);

  // Scale-lock: chromatic pads dim to off
  const isChromatic = scaleClass === 'chromatic';
  const isFlashing = (state.flashingPads.get(padIndex) ?? 0) > now;
  const isHeld = state.heldPads.has(padIndex);

  // Check chord highlight
  const inChordHalo = isChordHighlight(pitch, state);

  let color: PadColor = hueToColor(spec.hue, state.rackId);
  let brightness = spec.brightness;
  let label = spec.label ?? '';
  let active = isHeld;
  let pulse = false;

  if (isChromatic && state.scaleLock) {
    if (isFlashing) {
      // 600 ms visual flash
      color = 'white';
      brightness = 0.7;
      label = '✗';
    } else {
      color = 'off';
      brightness = 0;
      label = '';
    }
  } else if (isChromatic) {
    // Scale lock off: dim but visible
    brightness = Math.min(spec.brightness, 0.35);
  }

  if (isHeld && !isChromatic) {
    brightness = Math.min(1, brightness + 0.2);
    active = true;
    pulse = true;
  }

  if (inChordHalo && !isHeld) {
    brightness = Math.min(1, brightness + 0.15);
    active = true;
  }

  // Border encoding: we map to label prefix for HTML rendering
  if (spec.border === 'gold-ring' && !isChromatic) {
    // Root pad: mark active so the gold-ring is always visible
    active = true;
    pulse = true;
  }

  return {
    color,
    brightness: Math.max(0, Math.min(1, brightness)),
    label: label.slice(0, 4),
    pulse,
    active,
    // Pass extra data for HTML renderer via label prefix convention:
    // '#' prefix = gold-ring, '◊' prefix = modal-tick
    ...(spec.border === 'gold-ring' && !isChromatic ? { label: `#${label}`.slice(0, 4) } : {}),
    ...(spec.border === 'modal-tick' ? { label: `◊${label}`.slice(0, 4) } : {}),
  };
}

/** Bassline control row pads (accent, slide, probability, etc.). */
function renderBasslineControlPad(row: number, col: number): PadState {
  void col;
  const labels = ['ACC', 'SLD', 'P1', 'P2', '', '', '', ''];
  const colors: PadColor[] = ['orange', 'cyan', 'green', 'green', 'off', 'off', 'off', 'off'];
  return {
    color: colors[row - 2] ?? 'off',
    brightness: 0.4,
    label: labels[row - 2] ?? '',
    pulse: false,
    active: false,
  };
}

/** Check if a pitch is part of a chord highlight (for any held root pad). */
function isChordHighlight(pitch: number, state: NoteModeState): boolean {
  if (state.heldPads.size === 0) return false;
  const intervals = SCALE_INTERVALS[state.scale];
  for (const [, heldPitch] of state.heldPads) {
    const rel = ((pitch - heldPitch) % 12 + 12) % 12;
    const heldPc = ((heldPitch % 12) + 12) % 12;
    const rootRel = ((heldPc - state.root) % 12 + 12) % 12;
    const heldDegree = intervals.indexOf(rootRel);
    if (heldDegree < 0) continue;
    const chord = chordIntervals(state.scale, heldDegree);
    if (chord.includes(rel)) return true;
  }
  return false;
}

// ─── handleNotePress ──────────────────────────────────────────────────────────

export interface NotePressResult {
  events: NoteModeEvent[];
  stateChanges: Partial<NoteModeState>;
}

/**
 * Handle a pad press in note mode.
 *
 * Returns the canonical events to dispatch and any state changes.
 */
export function handleNotePress(
  padIndex: number,
  state: NoteModeState,
  pressure = 0.8,
): NotePressResult {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const events: NoteModeEvent[] = [];
  const stateChanges: Partial<NoteModeState> = {};

  const pitch = pitchForPad(row, col, state);

  // Always emit jam.input.pad for every pad press
  const inputPad: JamInputPad = {
    family: 'jam.input.pad',
    surfaceId: 'grid-8x8',
    x: col,
    y: row,
    pressure,
    velocity: Math.round(pressure * 127),
    aftertouch: 0,
    ts: Date.now(),
    mode: 'note',
    target: pitch !== null ? String(pitch) : undefined,
  };
  events.push(inputPad);

  if (pitch === null) {
    // Non-pitch pad (e.g. bassline control row) — no note event
    return { events, stateChanges };
  }

  const scaleClass = classifyPitch(pitch, state.scale, state.root);

  // Scale-lock chromatic guardrail (D-B.7)
  if (scaleClass === 'chromatic' && state.scaleLock) {
    // Silent no-op + 600 ms visual flash
    const flashMap = new Map(state.flashingPads);
    flashMap.set(padIndex, Date.now() + FLASH_DURATION_MS);
    stateChanges.flashingPads = flashMap;
    return { events, stateChanges };
  }

  // Double-tap detection for latch
  const now = Date.now();
  const lastTap = state.doubleTapTimestamps.get(padIndex) ?? 0;
  const isDoubleTap = (now - lastTap) < DOUBLE_TAP_MS;

  const tapMap = new Map(state.doubleTapTimestamps);
  tapMap.set(padIndex, now);
  stateChanges.doubleTapTimestamps = tapMap;

  const voiceId = `pad-${padIndex}`;

  // Note on
  const noteOn: JamNoteOnEvent = {
    family: 'jam.note.on',
    rackId: state.rackId,
    pitch,
    velocity: Math.round(pressure * 127),
    voiceId,
    ts: now,
  };
  events.push(noteOn);

  // Track held pads
  const held = new Map(state.heldPads);
  held.set(padIndex, pitch);
  stateChanges.heldPads = held;

  // Double-tap = latch
  if (isDoubleTap) {
    const latch: JamNoteExpression = {
      family: 'jam.note.expression',
      rackId: state.rackId,
      voiceId,
      parameter: 'latch',
      value: 1,
    };
    events.push(latch);
  }

  return { events, stateChanges };
}

/**
 * Handle a pad release in note mode.
 */
export function handleNoteRelease(
  padIndex: number,
  state: NoteModeState,
): NotePressResult {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const events: NoteModeEvent[] = [];
  const stateChanges: Partial<NoteModeState> = {};

  const pitch = pitchForPad(row, col, state);
  if (pitch === null) return { events, stateChanges };

  const voiceId = `pad-${padIndex}`;
  const noteOff: JamNoteOffEvent = {
    family: 'jam.note.off',
    rackId: state.rackId,
    pitch,
    voiceId,
    ts: Date.now(),
  };
  events.push(noteOff);

  // Remove from held
  const held = new Map(state.heldPads);
  held.delete(padIndex);
  stateChanges.heldPads = held;

  return { events, stateChanges };
}

/**
 * Handle aftertouch / pressure change.
 */
export function handleNotePressure(
  padIndex: number,
  pressure: number,
  state: NoteModeState,
): NoteModeEvent[] {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const pitch = pitchForPad(row, col, state);
  if (pitch === null) return [];

  const scaleClass = classifyPitch(pitch, state.scale, state.root);
  if (scaleClass === 'chromatic' && state.scaleLock) return [];

  const expression: JamNoteExpression = {
    family: 'jam.note.expression',
    rackId: state.rackId,
    voiceId: `pad-${padIndex}`,
    parameter: 'pressure',
    value: pressure,
  };
  return [expression];
}

// ─── createNoteModeState ──────────────────────────────────────────────────────

/** Create a default NoteModeState for a given layout. */
export function createNoteModeState(
  layout: NoteLayout,
  rackId: string,
  opts: Partial<Pick<NoteModeState, 'scale' | 'root' | 'octave' | 'palette' | 'labelMode' | 'scaleLock'>> = {},
): NoteModeState {
  return {
    layout,
    scale: opts.scale ?? 'pentatonic',
    root: opts.root ?? 0,   // C
    octave: opts.octave ?? 3,
    scaleLock: opts.scaleLock ?? true, // on by default (D-B hard rule)
    palette: opts.palette ?? 'boomwhacker',
    labelMode: opts.labelMode ?? 'off',
    rackId,
    flashingPads: new Map(),
    heldPads: new Map(),
    doubleTapTimestamps: new Map(),
  };
}

// ─── Colour helpers ───────────────────────────────────────────────────────────

/**
 * Map a hue (0-360) to the nearest PadColor.
 * Track-channel hue takes precedence; rack id is used as a tiebreak hint.
 */
export function hueToColor(hue: number, _rackId: string): PadColor {
  // Map hue ranges to PadColor vocabulary
  if (hue < 20 || hue >= 340) return 'red';
  if (hue < 45) return 'orange';
  if (hue < 75) return 'yellow';
  if (hue < 150) return 'green';
  if (hue < 195) return 'cyan';
  if (hue < 260) return 'blue';
  if (hue < 300) return 'purple';
  return 'pink';
}

```
