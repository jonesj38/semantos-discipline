---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/sequencer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.598922+00:00
---

# cartridges/jambox/web/src/sequencer.ts

```ts
/**
 * Step sequencer with zoomable resolution: 16, 32 or 64 steps per bar.
 *
 *   16 → 16ths   (4/beat)   default. Sparse, easy.
 *   32 → 32nds   (8/beat)   tighter rolls + ghost notes.
 *   64 → 64ths  (16/beat)   trap hats, drum-and-bass detail.
 *
 * Changing resolution preserves the on-states of pre-existing 16th
 * positions: a 16-step pattern viewed at 32 spaces them every other
 * cell; viewed at 64, every fourth. New finer subdivisions start
 * empty — the user paints them in. This keeps the pattern audibly
 * identical when zooming so the act of zooming never changes the
 * groove.
 *
 * Tracks: 9 drums + 2 melodic + 4 scenes A/B/C/D. Per-track FX
 * (filter / reverb / delay), mute, solo, per-cell velocity.
 *
 * Clock sync: callers can call `setExternalTransport({ wallStartMs,
 * bpm })` to slave this sequencer to a peer's transport. The next
 * tick lines up to the peer's bar boundary, with an optional `regrid`
 * offset (Denon DJ-style ms nudge) to compensate for network latency.
 */

import {
  playDrum, playNote, playFmNote, playSquareNote, playPulseNote,
  playSubNote, playEpianoNote, playPadNote,
  playAcid, playSample,
  setTrackFilter, setTrackReverb, setTrackDelay,
  setTrackDrive, setTrackBitcrush, setTrackSidechain,
  type DrumKind,
} from './audio';
import type {
  JamPatternStepToggle, JamPatternStepSetVelocity, JamPatternStepSetProbability,
  JamPatternLaneSelect,
} from './semantic/events';

export const TRACK_NAMES = [
  'kick','snare','hat','clap','cb','tom','sub','perc','shaker',
  'acid','bass','lead','samp',
] as const;
export type TrackName = typeof TRACK_NAMES[number];

/** What kind of voice each track triggers. `synth` follows `synthVoice`. */
export const TRACK_KIND: Record<TrackName, 'drum' | 'synth' | 'acid' | 'sampler'> = {
  kick: 'drum', snare: 'drum', hat: 'drum', clap: 'drum', cb: 'drum',
  tom: 'drum', sub: 'drum', perc: 'drum', shaker: 'drum',
  acid: 'acid', bass: 'synth', lead: 'synth', samp: 'sampler',
};
export function isMelodic(t: TrackName): boolean {
  const k = TRACK_KIND[t];
  return k === 'synth' || k === 'acid' || k === 'sampler';
}

const DRUMS: Record<string, DrumKind | null> = {
  kick: 'kick', snare: 'snare', hat: 'hat', clap: 'clap', cb: 'cb',
  tom: 'tom', sub: 'sub', perc: 'perc', shaker: 'shaker',
};

export type SynthVoice = 'saw' | 'fm' | 'square' | 'pulse' | 'sub' | 'epiano' | 'pad';

export type Scene = 0 | 1 | 2 | 3;
export const SCENES: Scene[] = [0, 1, 2, 3];

export type StepCount = 16 | 32 | 64;
export const STEP_COUNTS: StepCount[] = [16, 32, 64];
const MAX_STEPS: StepCount = 64;

export interface Cell {
  on: boolean;
  vel: number;       // 0..1
  semitone: number;  // melodic tracks
  /** Probability (0..1) the trig fires. Default 1 = always. */
  prob?: number;
  /** Ratchet count (1..4). Default 1 = single hit. 2/3/4 = rolls within step. */
  ratchet?: number;
  /** Acid: accent (boosts cutoff + amp). */
  accent?: boolean;
  /** Acid: slide from previous note instead of attacking. */
  slide?: boolean;
}

export type Grid = Record<TrackName, Cell[]>;        // length always 64
export type SceneGrid = Grid[];                      // length 4

export function emptyCell(): Cell { return { on: false, vel: 0.9, semitone: 0 }; }
export function emptyGrid(): Grid {
  const g = {} as Grid;
  for (const t of TRACK_NAMES) {
    g[t] = Array.from({ length: MAX_STEPS }, emptyCell);
  }
  return g;
}
export function emptySceneGrid(): SceneGrid {
  return [emptyGrid(), emptyGrid(), emptyGrid(), emptyGrid()];
}

export interface TrackState {
  mute: boolean;
  solo: boolean;
  filterHz: number;
  reverb: number;
  delay: number;
  drive: number;       // 0..1
  bitcrush: number;    // 2..64 quantize steps (higher = cleaner)
  sidechain: boolean;  // duck this track when kick fires
  /** Per-track loop length in canonical 64th steps. Wraps within the
   *  scene grid: kick at 16, hat at 7 → polyrhythm. Default = 64. */
  loopLength: number;
  /** Per-track synth voice (melodic tracks only). */
  voice: SynthVoice;
  /** Per-track octave shift. Cells store scale-degree semitones in
   *  [0..23]; the actual played pitch is `cell.semitone + octave*12`.
   *  Bass defaults to -1 so it sits low without the user having to
   *  manually shift each cell. Range -2..+2. */
  octave: number;
}

export type TrackStates = Record<TrackName, TrackState>;
export function defaultTrackStates(): TrackStates {
  const s = {} as TrackStates;
  for (const t of TRACK_NAMES) {
    s[t] = {
      mute: false, solo: false,
      filterHz: 18000, reverb: 0, delay: 0,
      drive: 0, bitcrush: 64, sidechain: false,
      loopLength: 64,    // full bar by default
      voice: 'saw',
      octave: 0,
    };
  }
  // Default sidechain ON for the meaty melodic tracks so kick pumps them.
  s.bass.sidechain = true;
  s.acid.sidechain = true;
  // Bass + acid default an octave down so they sit under the lead/chord
  // range without forcing the producer to manually shift every cell.
  s.bass.octave = -1;
  s.acid.octave = -1;
  return s;
}

/** Allowed polymetric loop lengths (in canonical 64th steps). Multiples
 *  of 4 keep the grid musically familiar; 7/9/11/13/15 force odd time. */
export const POLYMETRIC_LENGTHS = [4, 7, 8, 9, 11, 12, 13, 15, 16, 24, 32, 48, 64] as const;
export type PolymetricLength = typeof POLYMETRIC_LENGTHS[number];

export interface SequencerCallbacks {
  onStep: (stepIdx: number, scene: Scene) => void;
  onCellTriggered: (track: TrackName, stepIdx: number, scene: Scene, vel: number) => void;
  onTransport?: (event: 'start' | 'stop', wallStartMs: number) => void;
  /**
   * Phase A (D-A.4): Canonical step-toggle event emitted alongside the
   * existing cell mutation. Additive — existing behaviour unchanged.
   */
  onCanonicalStepToggle?: (event: JamPatternStepToggle) => void;
  /** Phase A (D-A.4): Canonical step-velocity event. */
  onCanonicalStepVelocity?: (event: JamPatternStepSetVelocity) => void;
  /** Phase A (D-A.4): Canonical step-probability event. */
  onCanonicalStepProbability?: (event: JamPatternStepSetProbability) => void;
  /** Phase A (D-A.4): Canonical lane-select event. */
  onCanonicalLaneSelect?: (event: JamPatternLaneSelect) => void;
}

/**
 * Map a logical step index in a coarser grid to the underlying 64th
 * grid. e.g. 16-view step 1 → 64-view step 4. Keeps the canonical
 * grid at 64ths so resolution swaps don't reshape data.
 */
export function logicalToCanonical(stepIdx: number, view: StepCount): number {
  return stepIdx * (MAX_STEPS / view);
}

export class Sequencer {
  private scene: Scene = 0;
  private grids: SceneGrid = emptySceneGrid();
  private tracks: TrackStates = defaultTrackStates();
  private bpm = 120;
  private swing = 0; // 0..0.4
  private beatRepeat = false;
  private repeatStartStep = 0;
  private repeatLength = 4;
  private rootHz = 220;
  /** Visible/interactive step count — not data resolution. */
  private view: StepCount = 16;
  /** Synth voice for melodic tracks (bass/lead). Acid + samp use their own. */
  private synthVoice: SynthVoice = 'saw';
  /** Sample buffers per sampler track. */
  private sampleBuffers = new Map<TrackName, AudioBuffer>();

  private playing = false;
  private currentStep = 0; // 0..63 always
  /** Phantom transport step — advances every tick whether or not slip
   *  is on. When the user releases slip-loop, currentStep jumps back
   *  to phantomStep so we land where the unbroken transport would
   *  have been (Denon DJ slip semantics). */
  private phantomStep = 0;
  /** True = slip-mode (phantom keeps moving). False = legacy beat-repeat. */
  private slipMode = false;
  private nextNoteTime = 0;
  private timer: number | null = null;
  private wallStartMs = 0;
  private regridOffsetMs = 0;
  private cb: SequencerCallbacks;

  constructor(cb: SequencerCallbacks) { this.cb = cb; }

  setBpm(b: number) { this.bpm = Math.max(40, Math.min(240, b)); }
  getBpm(): number { return this.bpm; }
  setSwing(s: number) { this.swing = Math.max(0, Math.min(0.4, s)); }
  setScene(s: Scene) { this.scene = s; this.currentStep = 0; }
  getScene(): Scene { return this.scene; }
  setRootHz(hz: number) { this.rootHz = hz; }

  /** Visible resolution — 16 / 32 / 64. Underlying data stays at 64. */
  setView(view: StepCount) { this.view = view; }
  getView(): StepCount { return this.view; }

  /**
   * Beat-repeat / slip loop.
   *   `slip=false` → classic repeat: currentStep loops in-place; on
   *                  release, transport keeps going from where the
   *                  loop landed (mild drift but tight feel).
   *   `slip=true`  → DJ-style slip: phantomStep keeps marching; on
   *                  release we jump currentStep back to phantomStep
   *                  so the transport is musically aligned again.
   */
  setBeatRepeat(on: boolean, lenSteps = 4, slip = true) {
    if (on) {
      this.beatRepeat = true;
      this.slipMode = slip;
      this.repeatStartStep = this.currentStep;
      this.phantomStep = this.currentStep;
      this.repeatLength = Math.max(1, Math.min(32, lenSteps));
    } else if (this.beatRepeat) {
      this.beatRepeat = false;
      if (this.slipMode) {
        this.currentStep = this.phantomStep;
      }
    }
  }

  /** Read a cell at a *visible-grid* index. Translates to canonical 64ths. */
  cell(track: TrackName, viewStep: number, scene: Scene = this.scene): Cell {
    const k = logicalToCanonical(viewStep, this.view);
    return this.grids[scene][track][k];
  }
  setCell(track: TrackName, viewStep: number, cell: Cell, scene: Scene = this.scene): void {
    const k = logicalToCanonical(viewStep, this.view);
    const prev = this.grids[scene][track][k];
    this.grids[scene][track][k] = cell;
    // Phase A (D-A.4): emit canonical events alongside cell mutation.
    const patternId = `pattern-scene-${scene}`;
    if (cell.on !== prev.on) {
      this.cb.onCanonicalStepToggle?.({
        family: 'jam.pattern.step.toggle',
        patternId,
        lane: track,
        step: k,
        on: cell.on,
      });
    }
    if (cell.vel !== prev.vel) {
      this.cb.onCanonicalStepVelocity?.({
        family: 'jam.pattern.step.setVelocity',
        patternId,
        lane: track,
        step: k,
        velocity: cell.vel,
      });
    }
    if (cell.prob !== prev.prob && cell.prob !== undefined) {
      this.cb.onCanonicalStepProbability?.({
        family: 'jam.pattern.step.setProbability',
        patternId,
        lane: track,
        step: k,
        probability: cell.prob,
      });
    }
  }
  /** Direct canonical access (used by patch application). */
  setCanonicalCell(track: TrackName, canonicalStep: number, cell: Cell, scene: Scene = this.scene): void {
    this.grids[scene][track][canonicalStep] = cell;
  }
  grid(scene: Scene = this.scene): Grid { return this.grids[scene]; }
  setSceneGrid(scene: Scene, grid: Grid): void { this.grids[scene] = grid; }
  setAllGrids(grids: SceneGrid): void { this.grids = grids; }

  trackState(t: TrackName): TrackState { return this.tracks[t]; }
  setTrackMute(t: TrackName, m: boolean): void { this.tracks[t].mute = m; }
  setTrackSolo(t: TrackName, s: boolean): void { this.tracks[t].solo = s; }
  setTrackFx(t: TrackName, fx: Partial<TrackState>): void {
    Object.assign(this.tracks[t], fx);
    if (fx.filterHz !== undefined) setTrackFilter('self', t, fx.filterHz);
    if (fx.reverb !== undefined) setTrackReverb('self', t, fx.reverb);
    if (fx.delay !== undefined) setTrackDelay('self', t, fx.delay);
    if (fx.drive !== undefined) setTrackDrive('self', t, fx.drive);
    if (fx.bitcrush !== undefined) setTrackBitcrush('self', t, fx.bitcrush);
    if (fx.sidechain !== undefined) setTrackSidechain('self', t, fx.sidechain);
  }
  setSynthVoice(v: SynthVoice): void { this.synthVoice = v; }
  getSynthVoice(): SynthVoice { return this.synthVoice; }
  setSampleBuffer(t: TrackName, buf: AudioBuffer): void {
    this.sampleBuffers.set(t, buf);
  }

  /** Slave to a peer's transport: wall-clock start + their BPM. */
  setExternalTransport(opts: { wallStartMs: number; bpm: number; regridMs?: number }): void {
    this.bpm = opts.bpm;
    this.wallStartMs = opts.wallStartMs;
    this.regridOffsetMs = opts.regridMs ?? 0;
    if (this.playing) this.realignFromWall();
  }
  /** Manual nudge applied on top of any external transport, ms. */
  setRegrid(ms: number): void {
    this.regridOffsetMs = ms;
    if (this.playing && this.wallStartMs) this.realignFromWall();
  }
  getRegrid(): number { return this.regridOffsetMs; }

  /** Live drift in ms vs. an external wall-clock origin (>0 = we're ahead). */
  driftVsWall(externalWallMs: number, externalBpm: number): number {
    const expectedElapsed = (Date.now() - externalWallMs) % (60_000 / externalBpm * 4);
    const localElapsed = (Date.now() - this.wallStartMs + this.regridOffsetMs) % (60_000 / this.bpm * 4);
    let drift = localElapsed - expectedElapsed;
    const bar = 60_000 / externalBpm * 4;
    if (drift > bar / 2) drift -= bar;
    if (drift < -bar / 2) drift += bar;
    return drift;
  }

  /**
   * Start the sequencer.
   *   `audioCtxNow` — when (in audio-ctx seconds) the first cell should fire.
   *                   Pass a future value to schedule a sync-drop start.
   *   `wallStartMs` — explicit wall-clock origin for the transport. Defaults
   *                   to `Date.now()`. Used by sync-drop so every peer
   *                   reports the same start instant in their broadcast
   *                   `jam.transport.start` patches.
   */
  start(audioCtxNow: number, wallStartMs?: number) {
    if (this.playing) return;
    this.playing = true;
    this.currentStep = 0;
    this.wallStartMs = wallStartMs ?? Date.now();
    this.nextNoteTime = audioCtxNow;
    this.cb.onTransport?.('start', this.wallStartMs);
    this.tick();
  }
  stop() {
    this.playing = false;
    if (this.timer !== null) { clearTimeout(this.timer); this.timer = null; }
    this.cb.onTransport?.('stop', this.wallStartMs);
  }
  isPlaying(): boolean { return this.playing; }

  /** Seconds per 64th step at current bpm. */
  private secondsPerStep(stepIdx: number): number {
    const sec = 60 / this.bpm / 16;     // 1/64 note in seconds
    // Swing on odd 8th beats — apply at 8th level (every 8 sixty-fourths).
    const isOdd8 = Math.floor(stepIdx / 8) % 2 === 1;
    return isOdd8 ? sec * (1 + this.swing) : sec * (1 - this.swing);
  }

  private soloActive(): boolean {
    for (const t of TRACK_NAMES) if (this.tracks[t].solo) return true;
    return false;
  }
  private trackAudible(t: TrackName): boolean {
    if (this.tracks[t].mute) return false;
    if (this.soloActive()) return this.tracks[t].solo;
    return true;
  }

  private realignFromWall() {
    const elapsedMs = (Date.now() - this.wallStartMs) + this.regridOffsetMs;
    const sec = 60 / this.bpm / 16;
    const stepFloat = (elapsedMs / 1000) / sec;
    this.currentStep = Math.floor(stepFloat) % MAX_STEPS;
    const ctxNow = (window as unknown as { __jamCtxNow?: () => number }).__jamCtxNow?.()
      ?? performance.now() / 1000;
    this.nextNoteTime = ctxNow;
  }

  private tick = () => {
    if (!this.playing) return;
    const ctxNow = (window as unknown as { __jamCtxNow?: () => number }).__jamCtxNow?.()
      ?? performance.now() / 1000;
    while (this.nextNoteTime < ctxNow + 0.1) {
      const stepIdx = this.beatRepeat
        ? this.repeatStartStep + ((this.currentStep - this.repeatStartStep + this.repeatLength) % this.repeatLength)
        : this.currentStep;
      this.fire(stepIdx);
      this.cb.onStep(stepIdx, this.scene);
      this.nextNoteTime += this.secondsPerStep(this.currentStep);
      this.currentStep = (this.currentStep + 1) % MAX_STEPS;
      // Phantom advances regardless of slip / beat-repeat state.
      this.phantomStep = (this.phantomStep + 1) % MAX_STEPS;
    }
    this.timer = window.setTimeout(this.tick, 15) as unknown as number;
  };

  private fire(stepIdx: number) {
    for (const t of TRACK_NAMES) {
      // Polymetric: each track wraps independently inside its own
      // loopLength so kick=16 + hat=7 yields a natural polyrhythm.
      const wrapLen = this.tracks[t].loopLength;
      const localStep = stepIdx % wrapLen;
      const c = this.grids[this.scene][t][localStep];
      if (!c.on) continue;
      if (!this.trackAudible(t)) continue;
      const prob = c.prob ?? 1;
      if (prob < 1 && Math.random() > prob) continue;
      const ratchet = Math.max(1, Math.min(4, c.ratchet ?? 1));
      const stepSec = this.secondsPerStep(stepIdx);
      for (let i = 0; i < ratchet; i++) {
        const offsetMs = (i * stepSec * 1000) / ratchet;
        const fn = () => this.fireOne(t, c);
        if (offsetMs < 1) fn();
        else setTimeout(fn, offsetMs);
      }
      this.cb.onCellTriggered(t, localStep, this.scene, c.vel);
    }
  }

  private fireOne(t: TrackName, c: Cell) {
    const kind = TRACK_KIND[t];
    if (kind === 'drum') {
      const drum = DRUMS[t]!;
      playDrum(drum, c.vel, 0, 'self', t);
      return;
    }
    // Apply per-track octave shift so e.g. bass plays an octave below
    // the cell's stored scale-degree by default. Cells stay clean
    // (semitones 0..23 within an octave); octave is a track-level
    // transposition.
    const semi = c.semitone + (this.tracks[t].octave * 12);
    const freq = this.rootHz * Math.pow(2, semi / 12);
    if (kind === 'acid') {
      const dur = 60 / this.bpm / 8 * 0.9;
      playAcid(freq, c.vel, dur, c.accent ?? false, c.slide ?? false, 0, 'self', t);
    } else if (kind === 'sampler') {
      const buf = this.sampleBuffers.get(t);
      if (buf) playSample(buf, c.vel, semi, 0, 'self', t);
    } else {
      const duration = 60 / this.bpm / 4 * 0.9;
      const voice = this.tracks[t].voice ?? this.synthVoice;
      playMelodic(voice, freq, c.vel, duration, 0, 'self', t);
    }
  }
}

/** Voice dispatch — saw / fm / square / pulse / sub / epiano / pad. */
export function playMelodic(
  voice: SynthVoice, freq: number, vel: number, dur: number, panX: number,
  entityKey: string, trackName: string,
): void {
  if (voice === 'fm') { playFmNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'square') { playSquareNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'pulse') { playPulseNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'sub') { playSubNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'epiano') { playEpianoNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'pad') { playPadNote(freq, vel, dur, panX, entityKey, trackName); return; }
  playNote(freq, vel, dur, panX, entityKey, trackName);
}

```
