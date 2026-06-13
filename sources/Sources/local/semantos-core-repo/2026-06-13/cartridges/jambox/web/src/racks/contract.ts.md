---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/contract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.612470+00:00
---

# cartridges/jambox/web/src/racks/contract.ts

```ts
/**
 * JamRack — the unified instrument contract for the jam-room.
 *
 * Every engine (WebAudio, Strudel, PureData, MIDI) exposes the same
 * five verbs: play / stop / setMacro / setPreset / state.
 *
 * The eight macros use canonical musical names so that phase C's mapping
 * editor and phase D's engine bridges can rely on the same vocabulary:
 *
 *   0  brightness   high-shelf gain | filter cutoff      | spectral tilt
 *   1  dirt         drive | bitcrush | saturator         | wavefolder
 *   2  wobble       LFO depth | filter mod | rate stir   | mod-wheel mirror
 *   3  space        reverb send | early-reflection time  | size
 *   4  snap         envelope attack ↘ | transient gain ↗
 *   5  body         low-shelf gain | sub mix | compressor make-up
 *   6  chaos        constrained random source for the rack
 *   7  tension      filter ↘ + resonance ↗ + sidechain ↗ + pitch drift
 */

export type JamRackEngine =
  | 'webaudio' | 'puredata' | 'strudel' | 'midi' | 'hybrid';

/** Note-on event. `voiceId` allows per-voice tracking for polyphonic racks. */
export interface JamNoteOn {
  kind: 'note.on';
  pitch: number;
  velocity: number;
  voiceId?: string;
  time?: number;
  humanise?: number;
  source?: string;
}

/** Note-off event. */
export interface JamNoteOff {
  kind: 'note.off';
  pitch: number;
  voiceId?: string;
  time?: number;
}

/**
 * Trigger event for drum/percussive racks.
 * `voiceId` maps to the drum voice name ('kick', 'snare', etc.).
 */
export interface JamTrigger {
  kind: 'trigger';
  voiceId: string;
  velocity: number;
  probability?: number;
  microOffset?: number;
  ratchet?: number;
  flam?: number;
  condition?: string;
  time?: number;
}

/** Stop event. Causes immediate or transport-aligned silence. */
export interface JamStop {
  kind: 'stop';
  reason: 'panic' | 'transport' | 'user';
}

/** Peak and RMS meter values for a rack's output. */
export interface JamMeters {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
  cpu?: number;
}

/**
 * Hint from a rack about how its inputs should be mapped.
 * Used by phase C's mapping editor.
 */
export interface JamMappingHint {
  inputType: 'pad' | 'key' | 'knob' | 'fader' | 'touch' | 'gamepad';
  /** Stable target id understood by the rack. */
  target: string;
  /** Suggested label for surface feedback. */
  label: string;
  /** 0..1 range if continuous, undefined if discrete. */
  range?: [number, number];
}

/** Serialisable snapshot of a rack's complete state. */
export interface JamRackState {
  presetId?: string;
  /** Macro values, indices 0-7, each 0-1. */
  macros: number[];
  engineState: unknown;
}

/**
 * The unified JamRack interface.
 *
 * Implement this to add a new engine (Strudel, PureData, MIDI, etc.)
 * without changing any surface or sequencer code.
 */
export interface JamRack {
  readonly id: string;
  readonly name: string;
  readonly engine: JamRackEngine;

  /** Play a note or trigger a drum voice. */
  play(event: JamNoteOn | JamTrigger): void;
  /** Stop a voice or all voices (panic). */
  stop(event: JamNoteOff | JamStop): void;
  /**
   * Set a macro value.
   * @param index - 0-7 (clamped if out of range)
   * @param value - 0-1 (clamped if out of range)
   */
  setMacro(index: number, value: number): void;
  /** Load a named preset. */
  setPreset(presetId: string): void;
  /** Get the current serialisable state. */
  getState(): JamRackState;
  /** Restore from a previously saved state. */
  setState(state: JamRackState): void;
  /** Get peak/RMS meters. */
  getMeters(): JamMeters;
  /** Get mapping hints for phase C's mapping editor. */
  getMappingHints(): JamMappingHint[];
}

```
