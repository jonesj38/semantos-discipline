---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/surface.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.604943+00:00
---

# cartridges/jambox/web/src/grid/surface.ts

```ts
/**
 * 8×8 pad surface with Push 3-style mode switching.
 *
 * Modes
 * ──────
 * global      No track selected.  8 drum tracks × 8 steps (step-page A).
 *             Page toggle (col 7 of bottom row) flips to steps 9-16.
 * step        Track selected.  Top 2 rows = 16 steps; rows 2-3 = velocity.
 *             Bottom rows = param pads (one per voice param, brightness = value).
 * param       Same as step's param section but full-screen with value scrub.
 * session     Full 8×8 pattern clip launcher (Ableton Session View style).
 * arrangement Row 0 = timeline; rows 1-7 = pattern bank to drag in.
 *
 * Each mode returns a PadState[64] to render.  Pad press callbacks carry
 * full context so main.ts can call pushCell / audio without any mode knowledge.
 */

import type { DrumVoiceType, JamboxDrumTrackPayload } from '../semantic/objects';
import { DRUM_VOICE_PARAMS } from '../semantic/objects';
import type { TrackName } from '../sequencer';
import type { JamInputPad } from '../semantic/events';

// ─── Types ────────────────────────────────────────────────────────────────────

export type GridModeKind =
  | 'global'
  | 'step'
  | 'param'
  | 'session'
  | 'arrangement'
  | 'note'      // D-B.2: melodic note grid
  | 'mix'       // D-B.3: full track strip mixer
  | 'custom';   // D-C.5: BYO mapping — bypasses all built-in mode rules

export interface PadState {
  /** Background color key. */
  color: PadColor;
  /** 0–1 brightness multiplier. */
  brightness: number;
  /** Short label (≤4 chars). */
  label: string;
  /** Whether the pad pulses with the beat. */
  pulse: boolean;
  active: boolean;
}

export type PadColor =
  | 'off' | 'white' | 'red' | 'orange' | 'yellow'
  | 'green' | 'cyan' | 'blue' | 'purple' | 'pink' | 'dim';

export type ParamKey = keyof Omit<JamboxDrumTrackPayload,
  'voiceType' | 'steps' | 'velocities' | 'loopLength' | 'mute' | 'racks'>;

export interface PadPressEvent {
  padIndex: number;          // 0-63
  row: number;               // 0-7
  col: number;               // 0-7
  mode: GridModeKind;
  // step mode
  stepIndex?: number;        // 0-15 when pressing a step pad
  trackId?: TrackName;
  // param mode
  paramKey?: ParamKey;
  paramDelta?: number;       // +1 or -1 (not used for tap, but for hold+swipe)
  // session mode
  patternSlot?: number;      // 0-63 pattern slot
  // arrangement mode
  arrangementBar?: number;
  arrangementPatternSlot?: number;
}

// ─── Track → colour mapping ───────────────────────────────────────────────────

const DRUM_COLORS: Record<string, PadColor> = {
  kick: 'orange', snare: 'yellow', hat: 'cyan', clap: 'green',
  cb: 'purple', tom: 'blue', sub: 'red', perc: 'pink', shaker: 'white',
  acid: 'cyan', bass: 'blue', lead: 'purple', samp: 'green',
};

export function trackColor(track: TrackName): PadColor {
  return DRUM_COLORS[track] ?? 'dim';
}

// ─── Param range helpers ──────────────────────────────────────────────────────

const PARAM_RANGES: Record<ParamKey, [number, number]> = {
  tune:   [-12, 12],
  decay:  [0, 1],
  punch:  [0, 1],
  crack:  [0, 1],
  ring:   [0, 1],
  tone:   [0, 1],
  drive:  [0, 1],
  reverb: [0, 1],
  delay:  [0, 1],
  volume: [0, 1],
  pan:    [-1, 1],
};

export function paramNormalised(key: ParamKey, value: number): number {
  const [lo, hi] = PARAM_RANGES[key];
  return Math.max(0, Math.min(1, (value - lo) / (hi - lo)));
}

export function paramFromNormalised(key: ParamKey, t: number): number {
  const [lo, hi] = PARAM_RANGES[key];
  return lo + t * (hi - lo);
}

export const PARAM_LABELS: Record<ParamKey, string> = {
  tune: 'TUNE', decay: 'DEC', punch: 'PNC', crack: 'CRK',
  ring: 'RING', tone: 'TONE', drive: 'DRV', reverb: 'REV',
  delay: 'DLY', volume: 'VOL', pan: 'PAN',
};

// ─── DRUM_TRACKS ordered list for global mode rows ────────────────────────────

export const GRID_DRUM_TRACKS: TrackName[] = [
  'kick', 'snare', 'hat', 'clap', 'cb', 'tom', 'sub', 'perc',
];

// ─── GridSurface ─────────────────────────────────────────────────────────────

export interface GridSurfaceCallbacks {
  /** Step toggled (on/off). */
  onStepToggle: (track: TrackName, stepIndex: number, on: boolean) => void;
  /** Param value changed (0-1 normalised). */
  onParamChange: (track: TrackName, key: ParamKey, normValue: number) => void;
  /** Pattern slot pressed in session mode. */
  onPatternSlot: (row: number, col: number) => void;
  /** Pattern placed into arrangement bar. */
  onArrangementPlace: (bar: number, patternSlot: number) => void;
  /** Mode changed externally so HUD / 3D can react. */
  onModeChange: (mode: GridModeKind, track: TrackName | null) => void;
  /**
   * Phase A (D-A.4): Canonical jam.input.pad event — additive alongside
   * existing PadPressEvent. Kept optional for backward-compat; all five
   * surface modes emit this when a pad press resolves to a real action.
   */
  onCanonicalPad?: (event: JamInputPad) => void;
}

export class GridSurface {
  private mode: GridModeKind = 'global';
  private selectedTrack: TrackName | null = null;
  private stepPage = 0; // 0 = steps 1-8, 1 = steps 9-16 (global mode)

  /** Latest snapshot of each track's step/param state for rendering. */
  private trackStates = new Map<TrackName, JamboxDrumTrackPayload>();

  /** Pattern slots for session mode (8×8 = 64 slots). */
  private patternSlots: Array<{ name: string; color: PadColor; playing: boolean } | null> =
    Array(64).fill(null);

  /** Arrangement sections: bar index → pattern slot index. */
  private arrangementSections = new Map<number, number>();

  /** Current playhead step (0-15) for step-ring blinking. */
  private playheadStep = 0;

  /** Set by D-B.7 guardrail: registered rack ids. Mix-full requires at least one. */
  private registeredRackIds: Set<string> = new Set();

  constructor(private cb: GridSurfaceCallbacks) {}

  // ── Mode management ────────────────────────────────────────────────────────

  /**
   * D-B.7: Set mode with validation guardrails.
   * - Cannot enter Mix-full without a registered rack.
   * - L2 default mode bindings are always valid.
   */
  setMode(mode: GridModeKind): void {
    // Guardrail: mix-full requires at least one registered rack
    if (mode === 'mix' && this.registeredRackIds.size === 0) {
      // Dev assertion (production: warn and fall through to param)
      if (typeof process !== 'undefined' && process.env?.NODE_ENV === 'test') {
        throw new Error('D-B.7: Cannot enter mix mode without a registered rack');
      }
      console.warn('[GridSurface] D-B.7: cannot enter mix mode — no racks registered. Falling back to param.');
      mode = 'param';
    }
    this.mode = mode;
    this.cb.onModeChange(mode, this.selectedTrack);
  }

  /**
   * D-B.7: Register a rack id so Mix mode can verify entry precondition.
   */
  registerRack(rackId: string): void {
    this.registeredRackIds.add(rackId);
  }

  /**
   * D-B.7: Unregister a rack id.
   */
  unregisterRack(rackId: string): void {
    this.registeredRackIds.delete(rackId);
  }

  /**
   * D-B.7: Assert that an event is valid for the current mode.
   * Throws in dev; warns + drops the offending field in production.
   *
   * Enforces:
   *   - Drum modes (global/step/param) MUST NOT carry pitch info.
   *   - Note mode MUST NOT carry step-toggle info.
   */
  assertModeFor(event: { family: string; [key: string]: unknown }): void {
    const isDrum = this.mode === 'global' || this.mode === 'step' || this.mode === 'param';
    const isNote = this.mode === 'note';
    const isDev = typeof process !== 'undefined' && process.env?.NODE_ENV === 'test';

    if (isDrum && event.family === 'jam.note.on') {
      const msg = `D-B.7: mode ${this.mode} MUST NOT emit jam.note.on`;
      if (isDev) throw new Error(msg);
      console.warn(`[GridSurface] ${msg}`);
    }
    if (isNote && event.family === 'jam.pattern.step.toggle') {
      const msg = `D-B.7: mode note MUST NOT emit jam.pattern.step.toggle`;
      if (isDev) throw new Error(msg);
      console.warn(`[GridSurface] ${msg}`);
    }
  }

  selectTrack(track: TrackName | null): void {
    this.selectedTrack = track;
    if (track !== null && this.mode === 'global') {
      this.mode = 'step';
    } else if (track === null) {
      this.mode = 'global';
    }
    this.cb.onModeChange(this.mode, this.selectedTrack);
  }

  getMode(): GridModeKind { return this.mode; }
  getSelectedTrack(): TrackName | null { return this.selectedTrack; }

  // ── State updates (called when DAG cells arrive) ───────────────────────────

  updateTrackState(track: TrackName, state: JamboxDrumTrackPayload): void {
    this.trackStates.set(track, state);
  }

  setPlayheadStep(step: number): void {
    this.playheadStep = step % 16;
  }

  setPatternSlot(index: number, slot: { name: string; color: PadColor; playing: boolean } | null): void {
    this.patternSlots[index] = slot;
  }

  placeArrangementSection(bar: number, patternSlot: number | null): void {
    if (patternSlot === null) this.arrangementSections.delete(bar);
    else this.arrangementSections.set(bar, patternSlot);
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  render(): PadState[] {
    switch (this.mode) {
      case 'global':      return this.renderGlobal();
      case 'step':        return this.renderStep();
      case 'param':       return this.renderParam();
      case 'session':     return this.renderSession();
      case 'arrangement': return this.renderArrangement();
      // D-B.2/D-B.3/D-C.5: note, mix, and custom modes are rendered externally
      // by their dedicated modules; return a blank grid as fallback here so the
      // render() contract is always satisfied.
      case 'note':        return Array(64).fill(this.pad('off', 0));
      case 'mix':         return Array(64).fill(this.pad('off', 0));
      case 'custom':      return Array(64).fill(this.pad('dim', 0.1, 'CUST'));
    }
  }

  private pad(
    color: PadColor, brightness: number, label = '', active = false, pulse = false,
  ): PadState {
    return { color, brightness, label, active, pulse };
  }

  private empty(): PadState {
    return this.pad('off', 0);
  }

  // ── GLOBAL mode ────────────────────────────────────────────────────────────
  // 8 rows × 8 cols.  Each row = one drum track.  Cols = steps (page A or B).
  // Bottom-right pad (row 7 col 7) = page toggle.
  private renderGlobal(): PadState[] {
    const pads: PadState[] = [];
    const offset = this.stepPage * 8;

    for (let row = 0; row < 8; row++) {
      const track = GRID_DRUM_TRACKS[row];
      const state = this.trackStates.get(track);
      const color = trackColor(track);

      for (let col = 0; col < 8; col++) {
        // Page toggle: bottom-right pad
        if (row === 7 && col === 7) {
          pads.push(this.pad('white', 0.4, this.stepPage === 0 ? 'A' : 'B', false, false));
          continue;
        }
        const stepIdx = offset + col;
        const on = state?.steps[stepIdx] ?? false;
        const vel = state?.velocities[stepIdx] ?? 100;
        const isPlayhead = stepIdx === this.playheadStep;
        const brightness = on ? (vel / 127) * 0.8 + 0.2 : 0.08;
        pads.push(this.pad(
          isPlayhead ? 'white' : (on ? color : 'dim'),
          isPlayhead ? 1 : brightness,
          '',
          on,
          isPlayhead && on,
        ));
      }
    }
    return pads;
  }

  // ── STEP mode ─────────────────────────────────────────────────────────────
  // Rows 0-1: steps 1-16 on/off (2 rows × 8 cols).
  // Rows 2-3: velocity shading for same steps.
  // Row 4: spacer.
  // Rows 5-6: voice param pads (up to 8 params, brightness = normalised value).
  // Row 7: mode nav (global / param / session / arrangement).
  private renderStep(): PadState[] {
    const pads: PadState[] = [];
    const track = this.selectedTrack;
    const state = track ? this.trackStates.get(track) : undefined;
    const color = track ? trackColor(track) : 'dim';

    for (let row = 0; row < 8; row++) {
      if (row < 2) {
        // On/off rows: row 0 = steps 1-8, row 1 = steps 9-16
        const pageOffset = row * 8;
        for (let col = 0; col < 8; col++) {
          const stepIdx = pageOffset + col;
          const on = state?.steps[stepIdx] ?? false;
          const vel = state?.velocities[stepIdx] ?? 100;
          const isPlayhead = stepIdx === this.playheadStep;
          const brightness = on ? (vel / 127) * 0.75 + 0.25 : 0.1;
          pads.push(this.pad(
            isPlayhead ? 'white' : (on ? color : 'dim'),
            isPlayhead ? 1 : brightness,
            String(stepIdx + 1),
            on,
            isPlayhead,
          ));
        }
      } else if (row < 4) {
        // Velocity rows (visual-only, pressing toggles step muted/full)
        const pageOffset = (row - 2) * 8;
        for (let col = 0; col < 8; col++) {
          const stepIdx = pageOffset + col;
          const on = state?.steps[stepIdx] ?? false;
          const vel = state?.velocities[stepIdx] ?? 100;
          const velBrightness = on ? vel / 127 : 0.04;
          pads.push(this.pad(on ? color : 'dim', velBrightness, '', false, false));
        }
      } else if (row === 4) {
        // Spacer
        for (let col = 0; col < 8; col++) pads.push(this.empty());
      } else if (row < 7) {
        // Param pads: row 5 = params 1-8, row 6 = params 9-16 (most voices have 6)
        const paramOffset = (row - 5) * 8;
        const voiceType = (track ? this.trackStates.get(track)?.voiceType : undefined) ?? 'kick';
        const params = DRUM_VOICE_PARAMS[voiceType as DrumVoiceType];
        for (let col = 0; col < 8; col++) {
          const paramIdx = paramOffset + col;
          const key = params[paramIdx] as ParamKey | undefined;
          if (!key) { pads.push(this.empty()); continue; }
          const rawValue = state ? (state[key] as number) : 0;
          const norm = paramNormalised(key, rawValue);
          pads.push(this.pad(color, 0.2 + norm * 0.8, PARAM_LABELS[key], false, false));
        }
      } else {
        // Row 7: mode nav
        pads.push(...this.modeNavRow());
      }
    }
    return pads;
  }

  // ── PARAM mode ─────────────────────────────────────────────────────────────
  // Full 8×8 devoted to the selected track's params + value visualization.
  // Row 0: param names (top row labels).
  // Rows 1-6: vertical bar per param (col = param, lit rows = value).
  // Row 7: mode nav.
  private renderParam(): PadState[] {
    const pads: PadState[] = [];
    const track = this.selectedTrack;
    const state = track ? this.trackStates.get(track) : undefined;
    const color = track ? trackColor(track) : 'dim';
    const voiceType = state?.voiceType ?? 'kick';
    const params = DRUM_VOICE_PARAMS[voiceType as DrumVoiceType];

    for (let row = 0; row < 8; row++) {
      if (row === 7) {
        pads.push(...this.modeNavRow());
        continue;
      }
      for (let col = 0; col < 8; col++) {
        const key = params[col] as ParamKey | undefined;
        if (!key) { pads.push(this.empty()); continue; }

        if (row === 0) {
          // Label row at top
          pads.push(this.pad(color, 0.9, PARAM_LABELS[key], false, false));
        } else {
          // Value bar: rows 1-6 (inverted: row 1 = top = high value)
          const rawValue = state ? (state[key] as number) : 0;
          const norm = paramNormalised(key, rawValue);
          // Rows 1-6 → 6 levels.  row 1 = level 6 (top), row 6 = level 1 (bottom).
          const level = 7 - row; // 6 at row 1, 1 at row 6
          const lit = norm * 6 >= level;
          pads.push(this.pad(lit ? color : 'dim', lit ? 0.15 + norm * 0.85 : 0.05, '', lit, false));
        }
      }
    }
    return pads;
  }

  // ── SESSION mode ───────────────────────────────────────────────────────────
  // 8 cols = tracks, 7 rows = scenes (patterns).  Row 7 = scene launch strip.
  private renderSession(): PadState[] {
    const pads: PadState[] = [];
    for (let row = 0; row < 8; row++) {
      if (row === 7) {
        pads.push(...this.modeNavRow());
        continue;
      }
      for (let col = 0; col < 8; col++) {
        const idx = row * 8 + col;
        const slot = this.patternSlots[idx];
        if (!slot) {
          pads.push(this.pad('dim', 0.05, '·', false, false));
        } else {
          pads.push(this.pad(
            slot.color,
            slot.playing ? 1 : 0.5,
            slot.name.slice(0, 4),
            slot.playing,
            slot.playing,
          ));
        }
      }
    }
    return pads;
  }

  // ── ARRANGEMENT mode ───────────────────────────────────────────────────────
  // Row 0 = timeline (each col = 2 bars, 8 cols = 16 bars).
  // Rows 1-6 = pattern bank (pattern slot per pad, place into timeline).
  // Row 7 = mode nav.
  private renderArrangement(): PadState[] {
    const pads: PadState[] = [];
    for (let row = 0; row < 8; row++) {
      if (row === 7) {
        pads.push(...this.modeNavRow());
        continue;
      }
      for (let col = 0; col < 8; col++) {
        if (row === 0) {
          // Timeline row
          const bar = col * 2;
          const patSlot = this.arrangementSections.get(bar);
          const slot = patSlot !== undefined ? this.patternSlots[patSlot] : null;
          if (slot) {
            pads.push(this.pad(slot.color, 0.8, slot.name.slice(0, 4), true, false));
          } else {
            pads.push(this.pad('dim', 0.07, String(bar + 1), false, false));
          }
        } else {
          // Pattern bank rows 1-6
          const idx = (row - 1) * 8 + col;
          const slot = this.patternSlots[idx];
          if (slot) {
            pads.push(this.pad(slot.color, slot.playing ? 1 : 0.45, slot.name.slice(0, 4), slot.playing, false));
          } else {
            pads.push(this.pad('dim', 0.05, '·', false, false));
          }
        }
      }
    }
    return pads;
  }

  // ── Mode navigation row (row 7) ────────────────────────────────────────────
  private modeNavRow(): PadState[] {
    const modes: Array<[GridModeKind, string]> = [
      ['global', 'ALL'], ['step', 'STEP'], ['param', 'PAR'],
      ['session', 'SES'], ['arrangement', 'ARR'],
    ];
    const row: PadState[] = [];
    for (let col = 0; col < 8; col++) {
      const entry = modes[col];
      if (!entry) { row.push(this.empty()); continue; }
      const [m, label] = entry;
      const active = this.mode === m;
      row.push(this.pad(active ? 'white' : 'dim', active ? 1 : 0.25, label, active, false));
    }
    return row;
  }

  // ── Pad press dispatch ─────────────────────────────────────────────────────

  /**
   * Process a pad press. Returns the legacy PadPressEvent for backward compat,
   * and additionally emits a canonical `jam.input.pad` event via
   * `onCanonicalPad` (Phase A D-A.4, additive).
   */
  press(padIndex: number): PadPressEvent | null {
    const row = Math.floor(padIndex / 8);
    const col = padIndex % 8;
    const base: PadPressEvent = { padIndex, row, col, mode: this.mode };

    // Row 7 in step/param/session/arrangement = mode nav
    if (row === 7 && this.mode !== 'global') {
      const modeOrder: GridModeKind[] = ['global', 'step', 'param', 'session', 'arrangement'];
      const m = modeOrder[col];
      if (m) {
        if (m === 'global') this.selectTrack(null);
        else this.setMode(m);
      }
      return null;
    }

    let result: PadPressEvent | null;
    switch (this.mode) {
      case 'global': result = this.pressGlobal(row, col, base); break;
      case 'step':   result = this.pressStep(row, col, base); break;
      case 'param':  result = this.pressParam(row, col, base); break;
      case 'session': result = this.pressSession(row, col, base); break;
      case 'arrangement': result = this.pressArrangement(row, col, base); break;
      // D-B.2/D-B.3/D-C.5: note, mix, and custom press events are handled
      // externally. Return a raw base event so the caller can route it.
      case 'note':
      case 'mix':
      case 'custom':
        result = base;
        break;
    }

    // Phase A (D-A.4): emit canonical jam.input.pad event alongside PadPressEvent.
    if (result !== null) {
      this.emitCanonicalPad(padIndex, row, col, result);
    }

    return result;
  }

  /** Emit the canonical jam.input.pad event. Additive — does not replace PadPressEvent. */
  private emitCanonicalPad(_padIndex: number, row: number, col: number, press: PadPressEvent): void {
    if (!this.cb.onCanonicalPad) return;
    const canonical: JamInputPad = {
      family: 'jam.input.pad',
      surfaceId: 'grid-8x8',
      x: col,
      y: row,
      pressure: 1,
      velocity: 100,
      aftertouch: 0,
      ts: Date.now(),
      mode: this.mode,
      target: press.trackId ?? press.patternSlot?.toString() ?? undefined,
    };
    this.cb.onCanonicalPad(canonical);
  }

  private pressGlobal(row: number, col: number, base: PadPressEvent): PadPressEvent | null {
    // Page toggle
    if (row === 7 && col === 7) {
      this.stepPage = 1 - this.stepPage;
      return null;
    }
    const track = GRID_DRUM_TRACKS[row];
    if (!track) return null;
    const stepIdx = this.stepPage * 8 + col;
    const state = this.trackStates.get(track);
    const on = !(state?.steps[stepIdx] ?? false);
    this.cb.onStepToggle(track, stepIdx, on);
    return { ...base, trackId: track, stepIndex: stepIdx };
  }

  private pressStep(row: number, col: number, base: PadPressEvent): PadPressEvent | null {
    const track = this.selectedTrack;
    if (!track) return null;

    if (row < 2) {
      const stepIdx = row * 8 + col;
      const state = this.trackStates.get(track);
      const on = !(state?.steps[stepIdx] ?? false);
      this.cb.onStepToggle(track, stepIdx, on);
      return { ...base, trackId: track, stepIndex: stepIdx };
    }
    if (row >= 5 && row < 7) {
      return this.pressParamPad(track, (row - 5) * 8 + col, base);
    }
    return null;
  }

  private pressParam(row: number, col: number, base: PadPressEvent): PadPressEvent | null {
    const track = this.selectedTrack;
    if (!track || row === 0) return null; // label row is display-only
    return this.pressParamPad(track, col, base);
  }

  private pressParamPad(track: TrackName, paramIdx: number, base: PadPressEvent): PadPressEvent | null {
    const state = this.trackStates.get(track);
    const voiceType = state?.voiceType ?? 'kick';
    const params = DRUM_VOICE_PARAMS[voiceType as DrumVoiceType];
    const key = params[paramIdx] as ParamKey | undefined;
    if (!key) return null;
    // Tap = increment by 1/8 step, wraps
    const rawValue = state ? (state[key] as number) : 0;
    const norm = paramNormalised(key, rawValue);
    const next = norm >= 0.875 ? 0 : Math.min(1, norm + 0.125);
    this.cb.onParamChange(track, key, next);
    return { ...base, trackId: track, paramKey: key };
  }

  private pressSession(row: number, col: number, base: PadPressEvent): PadPressEvent | null {
    if (row >= 7) return null;
    const slot = row * 8 + col;
    this.cb.onPatternSlot(row, col);
    return { ...base, patternSlot: slot };
  }

  private pressArrangement(row: number, col: number, base: PadPressEvent): PadPressEvent | null {
    if (row === 0) {
      const bar = col * 2;
      return { ...base, arrangementBar: bar };
    }
    const patternSlot = (row - 1) * 8 + col;
    const bar = 0; // default: user picks timeline bar first
    this.cb.onArrangementPlace(bar, patternSlot);
    return { ...base, arrangementPatternSlot: patternSlot };
  }
}

```
